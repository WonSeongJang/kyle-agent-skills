// @ts-check

const DEFAULT_MAX_ACTIONS = 5;
const WEAK_VERDICTS = new Set([
    'weak_ok',
    'blocked',
    'auth_required',
    'challenge',
    'paywall',
    'browser_required',
    'unsupported',
    'error',
    'unknown',
]);

/**
 * @param {ReturnType<import('./search-strategy.mjs').planKoreanResearch>} plan
 * @param {Awaited<ReturnType<import('./fetch-enrichment.mjs').enrichSearchResultsWithFetch>>} enrichment
 * @param {{ maxActions?: number }} [options]
 */
export function planBrowseEscalation(plan, enrichment, options = {}) {
    const maxActions = positiveInteger(options.maxActions, DEFAULT_MAX_ACTIONS);
    const pending = enrichment.summary?.pending || [];
    const completeWithStrongFetch = Boolean(enrichment.summary?.ready)
        && (enrichment.candidates || []).every(candidate => isStrongFetch(candidate.fetch));
    const actions = completeWithStrongFetch
        ? []
        : (enrichment.candidates || [])
            .map((candidate, index) => buildAction(plan, enrichment, candidate, index + 1, pending))
            .filter(Boolean)
            .sort(compareActions)
            .slice(0, maxActions);
    const reasons = [...new Set(actions.flatMap(action => action.reasons))];

    return {
        schemaVersion: 'research-browse-escalation-v1',
        planSchemaVersion: plan.schemaVersion || 'unknown',
        enrichmentSchemaVersion: enrichment.schemaVersion || 'unknown',
        needsBrowse: actions.length > 0,
        summary: {
            actionCount: actions.length,
            reasons,
            pending,
            ledgerStatusBeforeBrowse: enrichment.summary?.status || 'unknown',
        },
        actions,
    };
}

/**
 * @param {ReturnType<import('./search-strategy.mjs').planKoreanResearch>} plan
 * @param {Awaited<ReturnType<import('./fetch-enrichment.mjs').enrichSearchResultsWithFetch>>} enrichment
 * @param {any} candidate
 * @param {number} rank
 * @param {string[]} pending
 */
function buildAction(plan, enrichment, candidate, rank, pending) {
    const reasons = inferReasons(plan, enrichment, candidate, pending);
    if (reasons.length === 0) return null;
    return {
        rank,
        url: candidate.url,
        title: candidate.title || candidate.fetch?.title || '',
        priority: priorityForReasons(reasons),
        reasons,
        commands: buildCommands(candidate.url, reasons),
        verify: {
            pendingConstraintIds: pending,
            discoveryConstraintIds: candidate.discoveryConstraintIds || [],
            supportedConstraintIds: candidate.constraintIds || [],
            ledgerStatusBeforeBrowse: enrichment.summary?.status || 'unknown',
        },
    };
}

/**
 * @param {ReturnType<import('./search-strategy.mjs').planKoreanResearch>} plan
 * @param {Awaited<ReturnType<import('./fetch-enrichment.mjs').enrichSearchResultsWithFetch>>} enrichment
 * @param {any} candidate
 * @param {string[]} pending
 */
function inferReasons(plan, enrichment, candidate, pending) {
    const reasons = new Set();
    const planReasons = plan.followUp?.browseReasons || [];
    const sourceHints = plan.sourceHints || [];
    const url = candidate.url || candidate.fetch?.finalUrl || '';
    const fetch = candidate.fetch || {};
    const textExcerpt = String(fetch.textExcerpt || '').trim();

    if (isNaverUrl(url) || planReasons.includes('naver-shell-or-iframe-risk')) {
        reasons.add('naver-shell-or-iframe-risk');
    }
    if (fetch.chromeRequired || fetch.verdict === 'browser_required' || planReasons.includes('dynamic-page-state')) {
        reasons.add('dynamic-page-state');
    }
    if (sourceHints.includes('structured') || planReasons.includes('table-list-ordinal-requires-dom')) {
        if (pending.length > 0) reasons.add('table-list-ordinal-requires-dom');
    }
    if (sourceHints.includes('official') && isWeakOrEmpty(fetch, textExcerpt)) {
        reasons.add('official-page-fetch-empty');
    }
    if ((enrichment.nextStep?.type === 'browse-candidates' || pending.length > 0) && isWeakOrEmpty(fetch, textExcerpt)) {
        reasons.add('fetch-insufficient-or-constraints-pending');
    }
    return [...reasons];
}

/**
 * @param {string} url
 * @param {string[]} reasons
 */
function buildCommands(url, reasons) {
    const quotedUrl = quoteShellArg(url);
    const commands = [
        `agbrowse new-tab ${quotedUrl} --json`,
        'agbrowse snapshot --interactive',
    ];
    if (reasons.includes('naver-shell-or-iframe-risk')) {
        commands.push('agbrowse text');
        commands.push('agbrowse get-dom --selector body --max-chars 20000');
    }
    if (reasons.includes('dynamic-page-state')) {
        commands.push('agbrowse network --duration 2000 --filter json');
        commands.push('agbrowse snapshot --interactive');
    }
    if (reasons.includes('table-list-ordinal-requires-dom')) {
        commands.push('agbrowse get-dom --selector body --max-chars 20000');
        commands.push('agbrowse scroll down --amount 1200 --json');
    }
    if (reasons.includes('official-page-fetch-empty')) {
        commands.push('agbrowse text');
        commands.push('agbrowse network --duration 1500');
    }
    if (reasons.includes('fetch-insufficient-or-constraints-pending')) {
        commands.push('agbrowse text');
    }
    return [...new Set(commands)];
}

/**
 * @param {any} fetch
 */
function isStrongFetch(fetch = {}) {
    return Boolean(fetch.ok) && fetch.verdict === 'strong_ok' && !fetch.chromeRequired && !fetch.chromeUsed;
}

/**
 * @param {any} fetch
 * @param {string} textExcerpt
 */
function isWeakOrEmpty(fetch, textExcerpt) {
    return !fetch.ok
        || WEAK_VERDICTS.has(fetch.verdict || 'unknown')
        || Boolean(fetch.chromeRequired)
        || textExcerpt.length === 0;
}

/**
 * @param {string[]} reasons
 */
function priorityForReasons(reasons) {
    if (reasons.some(reason => [
        'naver-shell-or-iframe-risk',
        'dynamic-page-state',
        'official-page-fetch-empty',
    ].includes(reason))) return 'high';
    if (reasons.includes('table-list-ordinal-requires-dom')) return 'medium';
    return 'low';
}

/**
 * @param {any} a
 * @param {any} b
 */
function compareActions(a, b) {
    const scores = { high: 0, medium: 1, low: 2 };
    return (scores[a.priority] ?? 9) - (scores[b.priority] ?? 9) || a.rank - b.rank;
}

/**
 * @param {string} url
 */
function isNaverUrl(url) {
    try {
        const host = new URL(url).hostname.toLowerCase();
        return host === 'naver.com' || host.endsWith('.naver.com');
    } catch {
        return false;
    }
}

/**
 * @param {string} value
 */
function quoteShellArg(value) {
    return JSON.stringify(String(value || ''));
}

/**
 * @param {unknown} value
 * @param {number} fallback
 */
function positiveInteger(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) && n >= 0 ? Math.floor(n) : fallback;
}

