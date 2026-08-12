// @ts-check
// In-page Defuddle extraction for the browser-escalation path.
// The vendored IIFE bundle (vendor/defuddle.iife.min.js) is injected into the
// rendered page and parses the live DOM into markdown. See vendor/README.md.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const VENDOR_BUNDLE_PATH = join(
    dirname(fileURLToPath(import.meta.url)),
    'vendor',
    'defuddle.iife.min.js',
);

/** @type {string|null} */
let cachedBundle = null;

/**
 * @returns {string}
 */
function loadBundleSource() {
    if (cachedBundle === null) {
        cachedBundle = readFileSync(VENDOR_BUNDLE_PATH, 'utf8');
    }
    return cachedBundle;
}

/** Reset the bundle cache (test hook). */
export function resetDefuddleBundleCache() {
    cachedBundle = null;
}

/**
 * Run Defuddle inside the rendered page and return the parsed result.
 *
 * Injection is attempted in two stages: `addScriptTag` first (fails on
 * CSP-strict pages), then `evaluate` + `new Function` (CDP eval; fails when
 * the page CSP forbids unsafe-eval). Both failing yields `null` with a
 * `reason` so the caller can record a warning — the plain innerText
 * candidate still exists, so extraction degrades, never breaks.
 *
 * @param {any} page
 * @returns {Promise<{ parsed: { content?: string, title?: string, author?: string, published?: string, wordCount?: number } | null, reason: string | null }>}
 */
export async function runDefuddleInPage(page) {
    if (typeof page?.evaluate !== 'function') {
        return { parsed: null, reason: 'defuddle:no-evaluate' };
    }
    let source;
    try {
        source = loadBundleSource();
    } catch (error) {
        console.error('[defuddle-extractor]', /** @type {any} */ (error)?.message || error);
        return { parsed: null, reason: 'defuddle:bundle-missing' };
    }

    const injected = await injectBundle(page, source);
    if (!injected.ok) return { parsed: null, reason: injected.reason };

    try {
        const parsed = await page.evaluate(() => {
            const ns = /** @type {any} */ (globalThis).Defuddle;
            // UMD/IIFE interop: the global may be the class or a namespace object.
            const D = typeof ns === 'function' ? ns : (ns?.Defuddle || ns?.default);
            if (typeof D !== 'function') return null;
            try {
                const result = new D(document, { markdown: true, url: location.href }).parse();
                if (!result || typeof result.content !== 'string') return null;
                return {
                    content: result.content,
                    title: result.title || '',
                    author: result.author || '',
                    published: result.published || '',
                    wordCount: Number(result.wordCount || 0),
                };
            } catch {
                return null;
            }
        });
        if (!parsed || !String(parsed.content || '').trim()) {
            return { parsed: null, reason: 'defuddle:empty-content' };
        }
        return { parsed, reason: null };
    } catch (error) {
        console.error('[defuddle-extractor]', /** @type {any} */ (error)?.message || error);
        return { parsed: null, reason: 'defuddle:parse-failed' };
    }
}

/**
 * @param {any} page
 * @param {string} source
 * @returns {Promise<{ ok: boolean, reason: string | null }>}
 */
async function injectBundle(page, source) {
    const alreadyInjected = await page
        .evaluate(() => typeof (/** @type {any} */ (globalThis).Defuddle) !== 'undefined')
        .catch(() => false);
    if (alreadyInjected) return { ok: true, reason: null };

    if (typeof page.addScriptTag === 'function') {
        try {
            await page.addScriptTag({ content: source });
            return { ok: true, reason: null };
        } catch {
            // CSP-blocked script tag — fall through to the CDP eval path.
        }
    }
    try {
        await page.evaluate((src) => {
            // eslint-disable-next-line no-new-func -- vendored bundle injection on CSP-strict pages
            new Function(src)();
        }, source);
        const defined = await page
            .evaluate(() => typeof (/** @type {any} */ (globalThis).Defuddle) !== 'undefined')
            .catch(() => false);
        return defined
            ? { ok: true, reason: null }
            : { ok: false, reason: 'defuddle:inject-failed' };
    } catch {
        return { ok: false, reason: 'defuddle:csp-blocked' };
    }
}
