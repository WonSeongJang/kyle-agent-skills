// @ts-check

/**
 * @typedef {{ tail: Promise<void>, waiters: number }} MutexEntry
 */

export class KeyedMutex {
    /** @type {Map<string, MutexEntry>} */
    #entries = new Map();

    /**
     * @template T
     * @param {string} key
     * @param {() => Promise<T>} fn
     * @returns {Promise<T>}
     */
    async runExclusive(key, fn) {
        key = String(key);
        let entry = this.#entries.get(key);
        if (!entry) {
            entry = { tail: Promise.resolve(), waiters: 0 };
            this.#entries.set(key, entry);
        }
        entry.waiters += 1;
        /** @type {() => void} */
        let release;
        const previous = entry.tail;
        entry.tail = new Promise((resolve) => { release = resolve; });
        await previous;
        try {
            return await fn();
        } finally {
            // @ts-ignore — release is always assigned before await previous resolves
            release();
            entry.waiters -= 1;
            if (entry.waiters === 0 && this.#entries.get(key) === entry) {
                this.#entries.delete(key);
            }
        }
    }

    /** @returns {number} */
    get size() {
        return this.#entries.size;
    }
}
