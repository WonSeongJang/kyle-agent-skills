// @ts-check

/**
 * @param {Array<{ id: string, text: string, mandatory?: boolean }>} constraints
 */
export function createConstraintLedger(constraints = []) {
    return {
        constraints: constraints.map(constraint => ({
            id: constraint.id,
            text: constraint.text,
            mandatory: constraint.mandatory !== false,
            status: 'pending',
            evidence: [],
        })),
        candidates: [],
        pending: constraints.map(constraint => constraint.id),
        supported: [],
        ready: false,
    };
}

/**
 * @param {ReturnType<typeof createConstraintLedger>} ledger
 * @param {{ url: string, title?: string, text?: string, candidate?: string, constraintIds?: string[], source?: string }} evidence
 */
export function updateLedgerWithEvidence(ledger, evidence) {
    const next = cloneLedger(ledger);
    const body = `${evidence.title || ''}\n${evidence.text || ''}`;
    const supportedIds = evidence.constraintIds?.length
        ? evidence.constraintIds
        : next.constraints
            .filter(constraint => textSupportsConstraint(body, constraint.text))
            .map(constraint => constraint.id);

    for (const constraint of next.constraints) {
        if (!supportedIds.includes(constraint.id)) continue;
        constraint.status = 'supported';
        constraint.evidence.push({
            url: evidence.url,
            title: evidence.title || '',
            source: evidence.source || 'fetch',
        });
    }

    if (evidence.candidate) {
        const candidate = getOrCreateCandidate(next, evidence.candidate);
        for (const constraintId of supportedIds) {
            candidate.support[constraintId] ||= [];
            candidate.support[constraintId].push(evidence.url);
        }
    }

    return refreshLedgerStatus(next);
}

/**
 * @param {ReturnType<typeof createConstraintLedger>} ledger
 */
export function summarizeLedger(ledger) {
    const refreshed = refreshLedgerStatus(cloneLedger(ledger));
    return {
        ready: refreshed.ready,
        supported: refreshed.supported,
        pending: refreshed.pending,
        status: refreshed.ready ? 'complete' : 'insufficient-evidence',
    };
}

/**
 * @param {string} text
 * @param {string} constraint
 */
export function textSupportsConstraint(text = '', constraint = '') {
    const haystack = normalizeForMatch(text);
    const terms = normalizeForMatch(constraint)
        .split(' ')
        .filter(term => term.length >= 2)
        .filter(term => !['그리고', '또는', '모두', '동시에', '확인', '필요'].includes(term));
    if (terms.length === 0) return false;
    const hits = terms.filter(term => haystack.includes(term)).length;
    return hits >= Math.min(2, terms.length);
}

/**
 * @param {ReturnType<typeof createConstraintLedger>} ledger
 * @param {string} name
 */
function getOrCreateCandidate(ledger, name) {
    let candidate = ledger.candidates.find(item => item.name === name);
    if (!candidate) {
        candidate = { name, support: {} };
        ledger.candidates.push(candidate);
    }
    return candidate;
}

/**
 * @param {ReturnType<typeof createConstraintLedger>} ledger
 */
function refreshLedgerStatus(ledger) {
    ledger.supported = ledger.constraints
        .filter(constraint => constraint.status === 'supported')
        .map(constraint => constraint.id);
    ledger.pending = ledger.constraints
        .filter(constraint => constraint.mandatory && constraint.status !== 'supported')
        .map(constraint => constraint.id);
    ledger.ready = ledger.pending.length === 0;
    return ledger;
}

/**
 * @param {ReturnType<typeof createConstraintLedger>} ledger
 */
function cloneLedger(ledger) {
    return JSON.parse(JSON.stringify(ledger));
}

/**
 * @param {string} text
 */
function normalizeForMatch(text) {
    return String(text || '')
        .replace(/[^\p{L}\p{N}]+/gu, ' ')
        .replace(/\s+/g, ' ')
        .trim()
        .toLowerCase();
}
