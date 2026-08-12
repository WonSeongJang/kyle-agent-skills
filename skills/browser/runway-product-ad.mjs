// @ts-check

import { parseArgs } from 'node:util';
import { buildRunwaySafety } from './runway-selectors.mjs';
import { setupRunwayGeneration, clickRunwayGenerate } from './runway-generate.mjs';
import { waitForRunwayCompletion } from './runway-monitor.mjs';

const DEFAULT_GENERATE_TIMEOUT_MS = 600000;
const DEFAULT_GENERATE_INTERVAL_MS = 10000;

/**
 * @param {any} deps
 * @param {string} text
 */
function emit(deps, text) {
    if (typeof deps.write === 'function') deps.write(text);
    else console.log(text);
}

/**
 * Execute a product marketing video generation.
 *
 * Compound workflow:
 * 1. Set prompt describing the ad concept
 * 2. Upload product image (or let Runway fetch from product URL)
 * 3. Generate storyboard → generate final video
 *
 * @param {any} page
 * @param {object} options
 * @param {string} options.prompt — ad creative concept
 * @param {string} [options.productUrl] — product page URL for auto-extraction
 * @param {string[]} [options.productImages] — product image file paths
 * @param {string[]} [options.referenceImages] — mood/style reference images
 * @param {number} [options.duration]
 * @param {string} [options.ratio]
 * @param {boolean} [options.explore]
 * @param {string} [options.output]
 * @param {number} [options.timeout]
 * @param {number} [options.interval]
 * @param {(ms: number) => Promise<void>} [options.sleep]
 * @returns {Promise<object>}
 */
export async function executeProductAd(page, options) {
    // Build the prompt: include product URL context if provided
    let fullPrompt = options.prompt;
    if (options.productUrl) {
        fullPrompt = `Product: ${options.productUrl}\n\n${options.prompt}`;
    }

    // Merge product images and reference images for upload
    const allImages = [
        ...(options.productImages || []),
        ...(options.referenceImages || []),
    ];

    // Setup
    const setupResult = await setupRunwayGeneration(page, {
        surface: 'custom-tools',
        prompt: fullPrompt,
        mode: 'video',
        duration: options.duration || 10,
        ratio: options.ratio || '16:9',
        referenceImages: allImages.length ? allImages : undefined,
        explore: options.explore,
    });

    // Get baseline
    const baseline = await page.evaluate(() => {
        const outputPattern = /\.(?:mp4|png|jpe?g)\b|\/(?:result|task_artifact|video-previews)\b/i;
        return Array.from(document.querySelectorAll('img[src], video[src], source[src]'))
            .filter(el => outputPattern.test(el.getAttribute('src') || ''))
            .length;
    });

    // Click Generate
    const genResult = await clickRunwayGenerate(page);
    if (!genResult.clicked) {
        return {
            ok: false,
            command: 'product-ad',
            status: 'generate_failed',
            error: genResult.error,
            setup: setupResult,
            safety: buildRunwaySafety(2),
        };
    }

    // Poll — product ad can be slower (compound workflow)
    const pollResult = await waitForRunwayCompletion(page, {
        timeoutMs: options.timeout || DEFAULT_GENERATE_TIMEOUT_MS,
        intervalMs: options.interval || DEFAULT_GENERATE_INTERVAL_MS,
        afterCount: baseline,
        sleep: options.sleep,
    });

    // Extract output
    let outputUrl = null;
    try {
        const { extractRunwayOutputUrl } = await import('./runway-download.mjs');
        const extracted = await extractRunwayOutputUrl(page, 0);
        outputUrl = extracted.url;
    } catch { /* ok */ }

    // Download if requested
    let downloadResult = null;
    if (options.output && outputUrl) {
        try {
            const { downloadRunwayOutput } = await import('./runway-download.mjs');
            downloadResult = await downloadRunwayOutput(outputUrl, options.output);
        } catch (e) {
            downloadResult = { ok: false, error: e instanceof Error ? e.message : String(e) };
        }
    }

    return {
        ok: pollResult.terminal && pollResult.state === 'idle',
        command: 'product-ad',
        status: pollResult.state === 'idle' ? 'complete' : pollResult.state,
        prompt: options.prompt,
        productUrl: options.productUrl || null,
        explore: Boolean(options.explore),
        outputUrl,
        outputFile: downloadResult?.ok ? options.output : null,
        download: downloadResult,
        poll: {
            polls: pollResult.polls,
            waitedMs: pollResult.waitedMs,
            timedOut: pollResult.timedOut,
        },
        safety: buildRunwaySafety(2),
    };
}

/**
 * @param {string[]} args
 * @param {any} deps
 */
export async function runRunwayProductAdCli(args = [], deps = {}) {
    const { values } = parseArgs({
        args,
        options: {
            prompt: { type: 'string' },
            'product-url': { type: 'string' },
            'product-images': { type: 'string', multiple: true },
            'reference-images': { type: 'string', multiple: true },
            duration: { type: 'string', default: '10' },
            ratio: { type: 'string', default: '16:9' },
            explore: { type: 'boolean', default: false },
            output: { type: 'string' },
            timeout: { type: 'string', default: String(DEFAULT_GENERATE_TIMEOUT_MS) },
            interval: { type: 'string', default: String(DEFAULT_GENERATE_INTERVAL_MS) },
            'allow-submit': { type: 'boolean', default: false },
            json: { type: 'boolean', default: false },
        },
        strict: false,
    });

    if (!values['allow-submit']) {
        throw new Error('product-ad requires --allow-submit flag');
    }
    if (!values.prompt) {
        throw new Error('--prompt is required for product-ad command');
    }

    const page = await deps.getPage();
    const result = await executeProductAd(page, {
        prompt: String(values.prompt),
        productUrl: values['product-url'] ? String(values['product-url']) : undefined,
        productImages: values['product-images']?.map(String),
        referenceImages: values['reference-images']?.map(String),
        duration: Number(values.duration || 10),
        ratio: String(values.ratio || '16:9'),
        explore: Boolean(values.explore),
        output: values.output ? String(values.output) : undefined,
        timeout: Number(values.timeout || DEFAULT_GENERATE_TIMEOUT_MS),
        interval: Number(values.interval || DEFAULT_GENERATE_INTERVAL_MS),
        sleep: deps.sleep,
    });

    emit(deps, values.json
        ? JSON.stringify(result, null, 2)
        : formatProductAdResult(result));
}

/**
 * @param {any} result
 */
function formatProductAdResult(result) {
    const lines = [
        'Runway product-ad',
        `status: ${result.status || (result.ok ? 'ok' : 'error')}`,
        `prompt: ${String(result.prompt || '').slice(0, 100)}`,
        `productUrl: ${result.productUrl || 'n/a'}`,
        `explore: ${result.explore ? 'yes' : 'no'}`,
    ];
    if (result.outputUrl) lines.push(`outputUrl: ${result.outputUrl}`);
    if (result.outputFile) lines.push(`outputFile: ${result.outputFile}`);
    if (result.poll) {
        lines.push(`polls: ${result.poll.polls}, waitedMs: ${result.poll.waitedMs}`);
    }
    if (result.error) lines.push(`error: ${result.error}`);
    return lines.join('\n');
}
