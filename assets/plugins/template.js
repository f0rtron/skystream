/*
 * Template
 *
 * This file mirrors the JS contract SkyStream currently reads at runtime.
 * It is intentionally a runnable asset plugin, not just documentation.
 *
 * Think of this file as "what the app believes a plugin is".
 * SkyStream does two different reads:
 * 1. A metadata/catalog read for plugin listing and debug asset loading.
 * 2. A runtime read where the app executes the JS and calls its hooks.
 *
 * The manifest below uses the normalized keys the app now prefers:
 * - languages: string[]
 * - categories: string[]
 *
 * The app still accepts older manifest keys for compatibility, but new
 * plugins should use the list-based shape shown here.
 *
 * Manifest notes:
 * - Runtime wrapper reads: id, name, version, baseUrl, languages, categories
 * - Extension catalog/debug UI stores: internalName, description, languages,
 *   categories, authors, iconUrl, status
 * - Asset loading appends ".debug" to this id at import time
 * - Asset manifest parsing is regex-based; if you use baseUrl: SOME_CONST
 *   then debug/catalog metadata sees "SOME_CONST", while runtime getManifest()
 *   still resolves the real value
 * - Subtitle objects still use `lang` for each subtitle track; that is a
 *   different field from manifest-level `languages`
 *
 * Item shape returned by getHome/search/load:
 * {
 *   title: string,
 *   url: string,
 *   posterUrl: string,
 *   bannerUrl?: string,
 *   backgroundPosterUrl?: string, // alias accepted by the app
 *   description?: string,
 *   isFolder?: boolean,
 *   episodes?: Episode[],
 *   provider?: string,            // app usually injects this, plugins can omit
 *   headers?: { [key: string]: string }
 * }
 *
 * Episode shape:
 * {
 *   name: string,
 *   url: string,
 *   season?: number,
 *   episode?: number,
 *   description?: string,
 *   posterUrl?: string,
 *   headers?: { [key: string]: string }
 * }
 *
 * Stream shape returned by loadStreams:
 * {
 *   url: string,
 *   quality?: string,
 *   headers?: { [key: string]: string },
 *   subtitles?: [{ url: string, label: string, lang?: string }],
 *   drmKid?: string,
 *   drmKey?: string,
 *   licenseUrl?: string
 * }
 *
 * JS bridge available in the current app runtime:
 * - http_get(url, headers?, callback?)
 * - http_post(url, headers?, body?, callback?)
 * - _fetch(url)
 * - setPreference(key, value)
 * - getPreference(key)
 * - sendMessage('crypto_decrypt_aes', JSON.stringify({ data, key, iv }))
 * - setTimeout / setInterval (stubbed, immediate in current runtime)
 * - CloudStream.getLanguage() / CloudStream.getRegion()
 */

const TEMPLATE_BASE_URL = "https://example.invalid/skystream-template";
const SAMPLE_MP4 =
    "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4";
const SAMPLE_HLS = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8";
const SAMPLE_SUBTITLE =
    "https://raw.githubusercontent.com/mozilla/vtt.js/master/test/fixtures/webvtt-file.vtt";

const DEFAULT_HEADERS = {
    "Referer": TEMPLATE_BASE_URL,
    "User-Agent": "SkyStream Template Plugin/1.0"
};

/*
 * getManifest()
 * What it does:
 * Returns provider metadata that both the extension catalog and the runtime
 * wrapper read before the plugin is used.
 *
 * Why it exists:
 * Without this object the app cannot identify the plugin, show it in the
 * extensions UI, or expose runtime metadata like categories/languages.
 *
 * How the app uses it:
 * - ExtensionsController parses it when loading asset plugins.
 * - JsBasedProvider calls it at runtime and keeps the result in memory.
 */
function getManifest() {
    return {
        id: "dev.template.plugin",
        name: "Template",
        internalName: "Template",
        version: 1,
        description: "Runnable template that mirrors SkyStream's current JS provider contract.",
        baseUrl: TEMPLATE_BASE_URL,
        languages: ["en"],
        categories: ["Movie", "TvSeries", "Anime", "LiveTv"],
        authors: ["SkyStream"],
        iconUrl: "",
        status: 1
    };
}

/*
 * poster(label)
 * What it does:
 * Builds a deterministic 2:3 placeholder poster URL.
 *
 * Why it exists:
 * It guarantees this template always has visible artwork, even when no real
 * remote image exists.
 *
 * How the app uses it:
 * The returned URL is fed directly into CachedNetworkImage across home,
 * search, details, library, and playback UI.
 */
function poster(label) {
    return "https://placehold.co/300x450/png?text=" + encodeURIComponent(label);
}

/*
 * banner(label)
 * What it does:
 * Builds a deterministic wide placeholder image URL.
 *
 * Why it exists:
 * The app supports separate banner/backdrop images on detail screens, so this
 * helper makes that path visible in a controlled way.
 *
 * How the app uses it:
 * Returned bannerUrl/backgroundPosterUrl values are shown in provider detail
 * headers and hero backgrounds.
 */
function banner(label) {
    return "https://placehold.co/1280x720/png?text=" + encodeURIComponent(label);
}

/*
 * clone(value)
 * What it does:
 * Produces a plain deep copy of a simple JSON-safe value.
 *
 * Why it exists:
 * Reusing the same object instance for headers or nested arrays can make demo
 * data harder to reason about when examples are modified later.
 *
 * How the app uses it:
 * The app does not call this helper directly; it only receives the cloned
 * objects you return from the runtime hooks.
 */
function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

/*
 * readCounter(key)
 * What it does:
 * Reads a persisted integer from the JS storage bridge.
 *
 * Why it exists:
 * The template demonstrates that plugins can keep lightweight state between
 * calls using getPreference/setPreference.
 *
 * How the app uses it:
 * The app exposes getPreference through the JS bridge. The returned counter is
 * only used to make repeated opens visible in this demo.
 */
async function readCounter(key) {
    const stored = await getPreference(key);
    const parsed = parseInt(stored || "0", 10);
    return Number.isFinite(parsed) ? parsed : 0;
}

/*
 * bumpCounter(key)
 * What it does:
 * Increments and persists a counter under the provided key.
 *
 * Why it exists:
 * It gives the template a visible side effect so developers can confirm that
 * plugin storage survives across calls.
 *
 * How the app uses it:
 * The app does not know about this helper. It only exposes the bridge APIs
 * that make this persistence possible.
 */
async function bumpCounter(key) {
    const next = (await readCounter(key)) + 1;
    setPreference(key, String(next));
    return next;
}

/*
 * base64EncodeAscii(input)
 * What it does:
 * Encodes an ASCII string to base64, falling back to a manual encoder when
 * `btoa` is unavailable in the JS runtime.
 *
 * Why it exists:
 * MAGIC_PROXY_v1 and magic_m3u8 payloads both rely on base64 transport.
 *
 * How the app uses it:
 * The app does not call this helper directly. It decodes the resulting values
 * later inside JsBasedProvider when a stream URL starts with those prefixes.
 */
function base64EncodeAscii(input) {
    try {
        if (typeof btoa === "function") {
            return btoa(input);
        }
    } catch (_) {}

    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
    let output = "";
    let index = 0;

    while (index < input.length) {
        const chr1 = input.charCodeAt(index++);
        const chr2 = input.charCodeAt(index++);
        const chr3 = input.charCodeAt(index++);

        const enc1 = chr1 >> 2;
        const enc2 = ((chr1 & 3) << 4) | ((chr2 || 0) >> 4);
        let enc3 = ((chr2 || 0) & 15) << 2 | ((chr3 || 0) >> 6);
        let enc4 = (chr3 || 0) & 63;

        if (Number.isNaN(chr2)) {
            enc3 = 64;
            enc4 = 64;
        } else if (Number.isNaN(chr3)) {
            enc4 = 64;
        }

        output +=
            chars.charAt(enc1) +
            chars.charAt(enc2) +
            chars.charAt(enc3) +
            chars.charAt(enc4);
    }

    return output;
}

/*
 * makeMagicProxyUrl(url)
 * What it does:
 * Wraps a real URL in the MAGIC_PROXY_v1 transport format the app recognizes.
 *
 * Why it exists:
 * Some streams need to be routed through the app's local proxy so headers and
 * rewritten playlists can be handled consistently.
 *
 * How the app uses it:
 * JsBasedProvider detects the MAGIC_PROXY_v1 prefix and rewrites it to the
 * local proxy server before playback starts.
 */
function makeMagicProxyUrl(url) {
    return "MAGIC_PROXY_v1" + base64EncodeAscii(url);
}

/*
 * makeMagicM3u8(url)
 * What it does:
 * Creates a synthetic base64-encoded HLS playlist payload.
 *
 * Why it exists:
 * The app supports a special magic_m3u8 transport where the plugin returns the
 * playlist content indirectly instead of hosting a real playlist file.
 *
 * How the app uses it:
 * JsBasedProvider decodes the payload, rewrites any MAGIC_PROXY_v1 entries,
 * serves the playlist from the local proxy, and gives the player that URL.
 */
function makeMagicM3u8(url) {
    const playlist = [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        "#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360",
        makeMagicProxyUrl(url)
    ].join("\n");
    return "magic_m3u8:" + base64EncodeAscii(playlist);
}

/*
 * buildListingItems(openCount)
 * What it does:
 * Builds the reusable listing items shown by getHome() and search().
 *
 * Why it exists:
 * Keeping the home/search cards in one place makes it obvious that those two
 * hooks return the same item shape the app expects.
 *
 * How the app uses it:
 * The app turns each returned object into a MultimediaItem and renders it in
 * provider home sections and provider search sections.
 */
function buildListingItems(openCount) {
    return [
        {
            title: "Template Movie",
            url: "template://item/movie",
            posterUrl: poster("Movie"),
            bannerUrl: banner("Movie"),
            description:
                "Home/search item shape. load() expands this into a single-episode movie detail. Home opened " +
                openCount +
                " times."
        },
        {
            title: "Template Series",
            url: "template://item/series",
            posterUrl: poster("Series"),
            bannerUrl: banner("Series"),
            description:
                "Multi-episode detail object. Demonstrates episode arrays, episode headers, direct HLS, MAGIC_PROXY_v1, magic_m3u8 and DRM stream fields."
        },
        {
            title: "Template backgroundPosterUrl Alias",
            url: "template://item/background-alias",
            posterUrl: poster("Alias"),
            description:
                "load() returns backgroundPosterUrl instead of bannerUrl. The app maps backgroundPosterUrl -> bannerUrl."
        },
        {
            title: "Template Folder Flag",
            url: "template://item/folder",
            posterUrl: poster("Folder"),
            isFolder: true,
            description:
                "isFolder is persisted by the app, but the current UI still routes this item through DetailsScreen like any other provider item."
        },
        {
            title: "Template Bridge Notes",
            url: "template://item/bridge-notes",
            posterUrl: poster("Bridge"),
            bannerUrl: banner("Bridge"),
            headers: clone(DEFAULT_HEADERS),
            description:
                "Shows bridge APIs exposed by the current JS runtime and stores open counts with getPreference/setPreference."
        }
    ];
}

/*
 * getHome()
 * What it does:
 * Returns the provider's home feed as a map of section name -> item list.
 *
 * Why it exists:
 * This is the hook the app calls to build the provider-backed home screen.
 *
 * How the app uses it:
 * JsBasedProvider invokes getHome(), converts each object into MultimediaItem,
 * and hands the categorized map to the home UI.
 */
async function getHome() {
    const openCount = await bumpCounter("template-plugin/home-opens");
    const items = buildListingItems(openCount);

    return {
        "01 Item Shape": [items[0], items[1]],
        "02 Aliases + Flags": [items[2], items[3]],
        "03 Runtime Notes": [items[4]]
    };
}

/*
 * search(query, cb)
 * What it does:
 * Filters the same demo items used by getHome() and returns matching results.
 *
 * Why it exists:
 * Provider search is a first-class app feature, so every template should show
 * the exact result shape the app expects here.
 *
 * How the app uses it:
 * JsBasedProvider calls search(query), converts the returned objects into
 * MultimediaItem instances, and renders them in search result rows.
 */
function search(query, cb) {
    const q = (query || "").toLowerCase().trim();
    const items = buildListingItems(0);

    if (!q) {
        cb(items);
        return;
    }

    cb(
        items.filter(item => {
            const haystack = (item.title + " " + (item.description || "")).toLowerCase();
            return haystack.includes(q);
        })
    );
}

/*
 * buildMovieDetails(openCount)
 * What it does:
 * Builds a single-item movie detail response with one playable episode entry.
 *
 * Why it exists:
 * In the current app contract, even "movies" usually flow through the same
 * detail object shape and can expose playback through `episodes`.
 *
 * How the app uses it:
 * The details screen reads the returned item, then the play action eventually
 * passes the nested episode URL into loadStreams().
 */
function buildMovieDetails(openCount) {
    return {
        title: "Template Movie",
        url: "template://item/movie",
        posterUrl: poster("Movie"),
        bannerUrl: banner("Movie detail uses bannerUrl"),
        description: [
            "This detail object demonstrates the exact MultimediaItem fields SkyStream currently reads.",
            "Fields used here: title, url, posterUrl, bannerUrl, description, episodes, headers.",
            "Single-episode details are treated as a movie by the current details controller.",
            "Detail opened " + openCount + " times."
        ].join("\n"),
        headers: clone(DEFAULT_HEADERS),
        episodes: [
            {
                name: "Play Movie - Direct MP4",
                url: "template://stream/direct-mp4",
                season: 1,
                episode: 1,
                description: "Single-episode movie pattern.",
                posterUrl: poster("Movie play"),
                headers: clone(DEFAULT_HEADERS)
            }
        ]
    };
}

/*
 * buildSeriesDetails(openCount)
 * What it does:
 * Builds a series-style detail response with multiple episodes.
 *
 * Why it exists:
 * It demonstrates the fields the app reads from Episode objects and shows the
 * different stream transport types supported today.
 *
 * How the app uses it:
 * The details UI renders the episode list, and selecting one episode forwards
 * that episode URL into loadStreams().
 */
function buildSeriesDetails(openCount) {
    return {
        title: "Template Series",
        url: "template://item/series",
        posterUrl: poster("Series"),
        bannerUrl: banner("Series detail"),
        description: [
            "This detail object demonstrates the Episode array shape the app currently reads.",
            "Episode fields used here: name, url, season, episode, description, posterUrl, headers.",
            "Detail opened " + openCount + " times."
        ].join("\n"),
        episodes: [
            {
                name: "Episode 1 - Direct HLS",
                url: "template://stream/direct-hls",
                season: 1,
                episode: 1,
                description: "Direct stream with headers + subtitles.",
                posterUrl: poster("S1E1"),
                headers: clone(DEFAULT_HEADERS)
            },
            {
                name: "Episode 2 - MAGIC_PROXY_v1",
                url: "template://stream/proxy-hls",
                season: 1,
                episode: 2,
                description: "Stream url starts with MAGIC_PROXY_v1 so the app rewrites it through the local proxy.",
                posterUrl: poster("S1E2"),
                headers: clone(DEFAULT_HEADERS)
            },
            {
                name: "Episode 3 - magic_m3u8",
                url: "template://stream/magic-m3u8",
                season: 1,
                episode: 3,
                description: "Synthetic playlist served by the app from a magic_m3u8 payload.",
                posterUrl: poster("S1E3"),
                headers: clone(DEFAULT_HEADERS)
            },
            {
                name: "Episode 4 - DRM Shape",
                url: "template://stream/drm-shape",
                season: 1,
                episode: 4,
                description: "Demonstrates drmKid, drmKey and licenseUrl fields. Values are illustrative only.",
                posterUrl: poster("S1E4"),
                headers: clone(DEFAULT_HEADERS)
            }
        ]
    };
}

/*
 * buildAliasDetails(openCount)
 * What it does:
 * Returns a detail object using `backgroundPosterUrl` instead of `bannerUrl`.
 *
 * Why it exists:
 * The app currently accepts both names, so this example documents the alias
 * behavior explicitly.
 *
 * How the app uses it:
 * MultimediaItem.fromJson maps backgroundPosterUrl -> bannerUrl before the UI
 * reads the object.
 */
function buildAliasDetails(openCount) {
    return {
        title: "Template backgroundPosterUrl Alias",
        url: "template://item/background-alias",
        posterUrl: poster("Alias"),
        backgroundPosterUrl: banner("backgroundPosterUrl alias"),
        description: [
            "The app maps backgroundPosterUrl to MultimediaItem.bannerUrl.",
            "Use this when you want to confirm the alias path visually.",
            "Detail opened " + openCount + " times."
        ].join("\n"),
        episodes: [
            {
                name: "Play Alias Demo",
                url: "template://stream/direct-hls",
                season: 1,
                episode: 1,
                description: "Uses the same stream model as other examples.",
                posterUrl: poster("Alias play")
            }
        ]
    };
}

/*
 * buildFolderDetails(openCount)
 * What it does:
 * Returns a detail object with `isFolder: true`.
 *
 * Why it exists:
 * The current app stores this flag, and the template makes it easy to verify
 * what the runtime does with it today.
 *
 * How the app uses it:
 * The flag is preserved on MultimediaItem, but the current provider detail UI
 * still routes the item through the normal details/playback flow.
 */
function buildFolderDetails(openCount) {
    return {
        title: "Template Folder Flag",
        url: "template://item/folder",
        posterUrl: poster("Folder"),
        bannerUrl: banner("Folder"),
        isFolder: true,
        description: [
            "This item sets isFolder: true.",
            "The current app stores the flag, but provider items still open the standard details flow.",
            "Detail opened " + openCount + " times."
        ].join("\n"),
        episodes: [
            {
                name: "Play Folder Example",
                url: "template://stream/direct-mp4",
                season: 1,
                episode: 1,
                description: "Playback still works because the current UI does not special-case provider folders here.",
                posterUrl: poster("Folder play")
            }
        ]
    };
}

/*
 * bridgeDescription(openCount)
 * What it does:
 * Builds a human-readable description of the JS bridge features available in
 * the current app runtime.
 *
 * Why it exists:
 * Plugin authors need to know which globals and helper functions they can rely
 * on inside the embedded JS engine.
 *
 * How the app uses it:
 * The returned text is just normal item description content rendered by the
 * details screen; the app does not parse it structurally.
 */
function bridgeDescription(openCount) {
    return [
        "Current JS bridge exposed by the app runtime:",
        "- http_get(url, headers?, callback?)",
        "- http_post(url, headers?, body?, callback?)",
        "- _fetch(url)",
        "- setPreference(key, value)",
        "- getPreference(key)",
        "- sendMessage('crypto_decrypt_aes', JSON.stringify({ data, key, iv }))",
        "- setTimeout / setInterval (immediate stub in this runtime)",
        "- CloudStream.getLanguage() / CloudStream.getRegion()",
        "",
        "CloudStream stub reports: " +
            CloudStream.getLanguage() +
            "-" +
            CloudStream.getRegion(),
        "Detail opened " + openCount + " times."
    ].join("\n");
}

/*
 * load(url)
 * What it does:
 * Resolves a listing/search URL into a full detail object.
 *
 * Why it exists:
 * The app separates "lightweight card data" from "full detail data", so this
 * hook is where providers expand an item before playback selection.
 *
 * How the app uses it:
 * JsBasedProvider calls load(url) from getDetails(), converts the returned map
 * into MultimediaItem, and the details screen renders the result.
 */
async function load(url) {
    const key = "template-plugin/detail-opens/" + (url || "unknown");
    const openCount = await bumpCounter(key);

    if (url === "template://item/movie") {
        return buildMovieDetails(openCount);
    }
    if (url === "template://item/series") {
        return buildSeriesDetails(openCount);
    }
    if (url === "template://item/background-alias") {
        return buildAliasDetails(openCount);
    }
    if (url === "template://item/folder") {
        return buildFolderDetails(openCount);
    }

    return {
        title: "Template Bridge Notes",
        url: "template://item/bridge-notes",
        posterUrl: poster("Bridge"),
        bannerUrl: banner("Bridge"),
        description: bridgeDescription(openCount),
        headers: clone(DEFAULT_HEADERS),
        episodes: [
            {
                name: "Play Runtime Note Stream",
                url: "template://stream/direct-mp4",
                season: 1,
                episode: 1,
                description: "Simple playable stream so the bridge notes item is still testable end-to-end.",
                posterUrl: poster("Bridge play")
            }
        ]
    };
}

/*
 * templateSubtitles()
 * What it does:
 * Returns a sample subtitle list using the subtitle shape the app reads.
 *
 * Why it exists:
 * Subtitles are part of the runtime stream contract and they use `lang` per
 * subtitle entry even though the manifest now uses `languages`.
 *
 * How the app uses it:
 * The player bottom sheet reads these subtitle objects and exposes them as
 * selectable tracks during playback.
 */
function templateSubtitles() {
    return [
        {
            url: SAMPLE_SUBTITLE,
            label: "English Template Subtitle",
            lang: "en"
        }
    ];
}

/*
 * loadStreams(url, cb)
 * What it does:
 * Resolves an episode/playback URL into one or more stream objects.
 *
 * Why it exists:
 * This is the final runtime hook before playback. It demonstrates direct URLs,
 * proxy URLs, synthetic playlists, subtitles, headers, and DRM metadata.
 *
 * How the app uses it:
 * JsBasedProvider converts each returned object into StreamResult, rewrites
 * magic transport URLs when needed, and sends the result to the player.
 */
function loadStreams(url, cb) {
    if (url === "template://stream/direct-mp4") {
        cb([
            {
                url: SAMPLE_MP4,
                quality: "Direct MP4",
                headers: clone(DEFAULT_HEADERS),
                subtitles: templateSubtitles()
            }
        ]);
        return;
    }

    if (url === "template://stream/direct-hls") {
        cb([
            {
                url: SAMPLE_HLS,
                quality: "Direct HLS",
                headers: clone(DEFAULT_HEADERS),
                subtitles: templateSubtitles()
            }
        ]);
        return;
    }

    if (url === "template://stream/proxy-hls") {
        cb([
            {
                url: makeMagicProxyUrl(SAMPLE_HLS),
                quality: "MAGIC_PROXY_v1",
                headers: clone(DEFAULT_HEADERS),
                subtitles: templateSubtitles()
            }
        ]);
        return;
    }

    if (url === "template://stream/magic-m3u8") {
        cb([
            {
                url: makeMagicM3u8(SAMPLE_HLS),
                quality: "magic_m3u8",
                headers: clone(DEFAULT_HEADERS),
                subtitles: templateSubtitles()
            }
        ]);
        return;
    }

    if (url === "template://stream/drm-shape") {
        cb([
            {
                url: SAMPLE_HLS,
                quality: "DRM Shape Example",
                headers: clone(DEFAULT_HEADERS),
                subtitles: templateSubtitles(),
                drmKid: "dGhpcy1pcy1hLXRlbXBsYXRlLWtpZA==",
                drmKey: "dGhpcy1pcy1hLXRlbXBsYXRlLWtleQ==",
                licenseUrl: "https://license.example.invalid/widevine"
            }
        ]);
        return;
    }

    cb([
        {
            url: SAMPLE_MP4,
            quality: "Fallback Stream",
            headers: clone(DEFAULT_HEADERS)
        }
    ]);
}

/*
 * Optional bridge helper patterns you can copy into real plugins:
 *
 * async function exampleHttp() {
 *   const response = await http_get("https://example.com", { Referer: TEMPLATE_BASE_URL });
 *   return response.statusCode;
 * }
 *
 * function exampleHttpCallback(cb) {
 *   http_post("https://example.com/api", { "Content-Type": "application/json" }, JSON.stringify({ ok: true }), cb);
 * }
 *
 * async function exampleAesDecrypt(data, key, iv) {
 *   return await sendMessage("crypto_decrypt_aes", JSON.stringify({ data: data, key: key, iv: iv }));
 * }
 */
