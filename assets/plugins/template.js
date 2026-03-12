(function() {
    /*
     * SkyStream Plugin v2 Template
     *
     * This file serves as the official reference for the Plugin v2 standard.
     * v2 Plugins feature:
     * 1. IIFE Sandboxing (prevents global namespace pollution).
     * 2. Explicit globalThis exports (manifest, and hooks).
     * 3. Standardized Result Objects: All async hooks return { success, data, errorCode?, message? }.
     *
     * Result Contract:
     * - success: boolean (true if the operation completed normally)
     * - data: The actual result (feed map, item object, stream list, etc.)
     * - errorCode: Optional string (e.g., "SITE_OFFLINE", "PARSE_ERROR", "CAPTCHA_REQUIRED")
     * - message: Optional human-readable developer/debug message
     */

     /*
     * Standard v2 Update: 
     * The 'getManifest' function is now OPTIONAL in JS.
     * The app automatically injects a global 'manifest' object from the .json sidecar.
     * Use it to access metadata without redundancy.
     */
    const BASE_URL = manifest.baseUrl; 
    const HEADERS = { "User-Agent": "SkyStream Plugin v2 Reference/1.0" };

    /**
     * getHome(cb)
     * @param {Function} cb - The callback to receive the PluginResult.
     */

    async function getHome(cb) {
        try {
            // Simulation of fetching data
            const homeData = {
                "Pinned": [
                    { title: "Sample Movie", url: "template://1", posterUrl: "https://placehold.co/300x450", isFolder: false },
                    { title: "Sample Series", url: "template://2", posterUrl: "https://placehold.co/300x450", isFolder: true }
                ]
            };
            cb({ success: true, data: homeData });
        } catch (e) {
            cb({ success: false, errorCode: "SITE_OFFLINE", message: e.message });
        }
    }

    /**
     * search(query, cb)
     */

    async function search(query, cb) {
        cb({ success: true, data: [] }); // Standard empty result
    }

    /**
     * load(url, cb)
     */

    async function load(url, cb) {
        const item = {
            title: "Sample Content",
            url: url,
            posterUrl: "https://placehold.co/300x450",
            description: "Detailed description of the content.",
            isFolder: false,
            episodes: [{ name: "Play", season: 1, episode: 1, url: url }]
        };
        cb({ success: true, data: item });
    }

    /**
     * loadStreams(url, cb)
     */

    async function loadStreams(url, cb) {
        const streams = [
            { url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", quality: "Auto", headers: HEADERS }
        ];
        cb({ success: true, data: streams });
    }

    // Export to globalThis for the app wrapper to find

    globalThis.getHome = getHome;
    globalThis.search = search;
    globalThis.load = load;
    globalThis.loadStreams = loadStreams;
})();