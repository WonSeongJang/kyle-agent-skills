// @ts-check

import { parseArgs } from 'node:util';
import { buildRunwaySafety } from './runway-selectors.mjs';
import { setupRunwayGeneration, clickRunwayGenerate, setRunwayPrompt } from './runway-generate.mjs';
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
 * Execute a multishot (multi-scene) video generation.
 *
 * Auto mode: storyPrompt → Runway auto-splits into scenes.
 * Custom mode: individual shot prompts.
 *
 * @param {any} page
 * @param {object} options
 * @param {string} [options.story] — auto mode narrative prompt
 * @param {string[]} [options.shots] — custom mode per-scene prompts (3-5)
 * @param {number} [options.duration]
 * @param {string} [options.ratio]
 * @param {string} [options.resolution]
 * @param {string} [options.firstSceneImage]
 * @param {boolean} [options.explore]
 * @param {string} [options.output]
 * @param {number} [options.timeout]
 * @param {number} [options.interval]
 * @param {(ms: number) => Promise<void>} [options.sleep]
 * @returns {Promise<object>}
 */
export async function executeMultishot(page, options) {
    const isAutoMode = Boolean(options.story);
    const shots = options.shots || [];

    if (!isAutoMode && shots.length < 2) {
        return {
            ok: false,
            command: 'multishot',
            error: 'Multishot requires --story or at least 2 --shots prompts',
        };
    }

    const prompt = isAutoMode
        ? options.story
        : shots.join(' | ');

    // Setup with the combined prompt
    const setupResult = await setupRunwayGeneration(page, {
        surface: 'custom-tools',
        prompt: /** @type {string} */ (prompt),
        mode: 'video',
        duration: options.duration,
        ratio: options.ratio,
        resolution: options.resolution,
        seedImage: options.firstSceneImage,
        explore: options.explore,
    });

    if (!isAutoMode) {
        // For custom mode, attempt to find and populate multishot scene fields
        const scenesSet = await page.evaluate((/** @type {string[]} */ scenePrompts) => {
            const normalize = (/** @type {unknown} */ v) => String(v || '').replace(/\s+/g, ' ').trim();
            // Look for scene input fields (multi-shot UI)
            const sceneInputs = Array.from(document.querySelectorAll(
                '[data-testid*="scene"], [data-testid*="shot"], [class*="scene"] textarea, [class*="scene"] [contenteditable], [class*="shot"] textarea'
            ));

            if (sceneInputs.length === 0) return { found: false, count: 0 };

            const filled = Math.min(scenePrompts.length, sceneInputs.length);
            for (let i = 0; i < filled; i++) {
                const input = sceneInputs[i];
                if (input instanceof HTMLTextAreaElement) {
                    input.value = scenePrompts[i];
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                } else if (input instanceof HTMLElement) {
                    input.textContent = scenePrompts[i];
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                }
            }
            return { found: true, count: filled };
        }, shots);

        setupResult.steps = { ...(setupResult.steps || {}), scenes: scenesSet };
    }

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
            command: 'multishot',
            status: 'generate_failed',
            error: genResult.error,
            setup: setupResult,
            safety: buildRunwaySafety(2),
        };
    }

    // Poll — multishot takes longer
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
        command: 'multishot',
        mode: isAutoMode ? 'auto' : 'custom',
        sceneCount: isAutoMode ? 'auto' : shots.length,
        status: pollResult.state === 'idle' ? 'complete' : pollResult.state,
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
export async function runRunwayMultishotCli(args = [], deps = {}) {
    const { values } = parseArgs({
        args,
        options: {
            story: { type: 'string' },
            shots: { type: 'string', multiple: true },
            duration: { type: 'string' },
            ratio: { type: 'string', default: '16:9' },
            resolution: { type: 'string' },
            'first-scene-image': { type: 'string' },
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
        throw new Error('multishot requires --allow-submit flag');
    }
    if (!values.story && (!values.shots || values.shots.length < 2)) {
        throw new Error('multishot requires --story or at least 2 --shots prompts');
    }

    const page = await deps.getPage();
    const result = await executeMultishot(page, {
        story: values.story ? String(values.story) : undefined,
        shots: values.shots?.map(String),
        duration: values.duration ? Number(values.duration) : undefined,
        ratio: values.ratio ? String(values.ratio) : undefined,
        resolution: values.resolution ? String(values.resolution) : undefined,
        firstSceneImage: values['first-scene-image'] ? String(values['first-scene-image']) : undefined,
        explore: Boolean(values.explore),
        output: values.output ? String(values.output) : undefined,
        timeout: Number(values.timeout || DEFAULT_GENERATE_TIMEOUT_MS),
        interval: Number(values.interval || DEFAULT_GENERATE_INTERVAL_MS),
        sleep: deps.sleep,
    });

    emit(deps, values.json
        ? JSON.stringify(result, null, 2)
        : formatMultishotResult(result));
}

/**
 * @param {any} result
 */
function formatMultishotResult(result) {
    const lines = [
        'Runway multishot',
        `mode: ${result.mode}`,
        `sceneCount: ${result.sceneCount}`,
        `status: ${result.status || (result.ok ? 'ok' : 'error')}`,
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
