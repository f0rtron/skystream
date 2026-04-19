# SkyStream Plugin Development Guide

Welcome to the SkyStream plugin ecosystem! This guide will walk you through creating, testing, and distributing plugins using the **Sky Gen 2 (Repository Hub)** architecture.

---

## 1. Prerequisites & Setup

Before you begin, ensure you have the following installed:
- **Node.js**: v18 or higher ([Download](https://nodejs.org/))
- **Git**: For version control and deployment.

### Install the CLI
The SkyStream CLI is your primary tool for managing repositories and plugins.
```bash
npm install -g skystream-cli
```

---

## 2. Core Development Workflow

### Step 1: Initialize a Repository
A repository is a collection of plugins. Use the CLI to scaffold your first one:
```bash
skystream init "my-repo" --package-name com.yourname.repo --plugin-name "my-plugin" --author "YourName"
```

### Step 2: Add More Plugins
You can host multiple plugins in a single repository. To add a second or third plugin:
```bash
# Navigate to your repository root
cd my-repo/

# Add a new plugin folder and template
skystream add "New-Plugin-Name"
```
The CLI will automatically generate a new folder with a safe `packageName` based on your repository ID.

### Step 3: Write Your Scraper Logic
Navigate to your plugin folder (e.g., `my-plugin/`) and open `plugin.js`. This is where you implement the four core functions.

> [!IMPORTANT]
> **Dynamic Base URL Architecture**: Always use `manifest.baseUrl` instead of hardcoded domain strings. This allows users to switch domains (mirrors) directly from the app without any plugin code changes.

### Declaring Mirror Domains

To let users pick from multiple domains, add a `domains` array to `plugin.json`:

```json
{
  "packageName": "com.example.myplugin",
  "name": "My Plugin",
  "baseUrl": "https://primary-domain.com",
  "domains": [
    { "name": "primary-domain.com", "url": "https://primary-domain.com" },
    { "name": "mirror1.com",        "url": "https://mirror1.com" },
    { "name": "mirror2.com",        "url": "https://mirror2.com" }
  ]
}
```

When `domains` is present, a **domain selector** appears in the plugin's settings gear in the Extensions screen. The selected URL is automatically injected as `manifest.baseUrl` — your plugin JS needs **no changes**.

### Declaring Sub-Providers (One JS, Many Feeds)

If a single JS file can serve multiple independent sources (e.g., different M3U playlists), declare them as `providers` instead of creating separate plugins:

```json
{
  "packageName": "com.example.mybundle",
  "name": "My Bundle",
  "baseUrl": "https://fallback.com",
  "providers": [
    { "id": "feed1", "name": "Feed One",  "baseUrl": "https://feed1.com/playlist.m3u" },
    { "id": "feed2", "name": "Feed Two",  "baseUrl": "https://feed2.com/playlist.m3u" },
    { "id": "feed3", "name": "Feed Three","baseUrl": "https://feed3.com/playlist.m3u" }
  ]
}
```

The app creates one provider instance per entry and injects each entry's `baseUrl` as `manifest.baseUrl` — again, **no JS changes needed**. Users can enable/disable individual sub-providers from the plugin settings. Cannot be combined with `domains`.

<details>
<summary><b>View the Core Function Templates</b></summary>

```javascript
(function() {

    // 1. getHome: Returns categories for the dashboard
    async function getHome(cb) {
        // Use dynamic baseUrl
        const homeUrl = `${manifest.baseUrl}/trending`;
        cb({ success: true, data: { "Trending": [ /* MultimediaItems */ ] } });
    }

    // 2. search: Handles user queries
    async function search(query, cb) {
        const searchUrl = `${manifest.baseUrl}/search?q=${query}`;
        cb({ success: true, data: [ /* MultimediaItems */ ] });
    }

    // 3. load: Fetches full details for a specific item
    function load(url, cb) {
        const loadUrl = `${manifest.baseUrl}/load?url=${url}`;
        cb({ success: true, data: { /* MultimediaItem with Episodes */ } });
    }

    // 4. loadStreams: Provides playable video links
    async function loadStreams(url, cb) {
        const streamUrl = `${manifest.baseUrl}/streams?url=${url}`;
        cb({ success: true, data: [ /* StreamResult objects */ ] });
    }

    // Export to SkyStream
    globalThis.getHome = getHome;
    globalThis.search = search;
    globalThis.load = load;
    globalThis.loadStreams = loadStreams;
})();
```
</details>

### Dashboard Layout Rules

The SkyStream dashboard organizes content based on the category names returned by your plugin's `getHome` function:

| Category Name | Behavior |
| :--- | :--- |
| **"Trending"** | **Reserved Name**. Promoted to the large **Hero Carousel** at the top. Items here are hidden from the thumbnail rows below to avoid duplication. |
| **Any other name** | Rendered as a horizontal **Thumbnail Row**. If "Trending" is missing, the **first category** in your data object will be used for the carousel. |

> [!TIP]
> To show an item in both the carousel and the rows, add it to both "Trending" and another category.

### Step 4: Local Testing
Verify your scraper logic directly in your terminal before deploying.

| Function | Command | Purpose |
| :--- | :--- | :--- |
| **getHome** | `skystream test -f getHome` | Check if dashboard categories load. |
| **search** | `skystream test -f search -q "Query"` | Verify search results for a keyword. |
| **load** | `skystream test -f load -q "URL"` | Verify movie/series details & episodes. |
| **loadStreams** | `skystream test -f loadStreams -q "URL"` | Check if playable video links are found. |

> [!TIP]
> If a test fails with `PARSE_ERROR`, the CLI (v1.2.8+) will now attempt to show you the internal JavaScript stack trace to help you pinpoint the exact line that crashed.

### Step 4: Deployment
SkyStream uses GitHub Actions to deploy and host your repository automatically.
1. Create a new repository on GitHub.
2. Push your code:
```bash
git init
git remote add origin https://github.com/USER/REPO.git
git add .
git commit -m "Initial commit"
git push -u origin main
```
### Step 5. Shortcode Sharing (Optional)
To make your repository easier to share, you can create a shortcode.
1.  Go to **[cutt.ly](https://cutt.ly)**.
2.  Paste your **Raw `repo.json` URL**.
3.  Create a custom alias with the prefix `sky-`.
    *   Example: `https://cutt.ly/sky-myrepo`
4.  **Share**: Users can now just type `myrepo` in the app's "Add Repository" dialog.

---

## 3. Installation in SkyStream App

Once your GitHub Action finishes deploying (check the "Actions" tab on GitHub), your repository is live!

1. Open SkyStream -> **Extensions** -> **Add Source**.
2. Paste your `repo.json` URL (e.g., `https://raw.githubusercontent.com/USER/REPO/main/repo.json`).
3. Your plugins are now ready to install!

---

## 4. Technical Reference

<details>
<summary><b>JavaScript Helper Classes (Recommended)</b></summary>

SkyStream provides built-in global classes to ensure data consistency. Using these is highly recommended for better structure and future-proofing.

**MultimediaItem** (Rich Metadata Support)
```javascript
const item = new MultimediaItem({
  title: "Example Title",
  url: "https://site.com/movie/1",
  posterUrl: "https://site.com/poster.jpg",
  type: "movie", // Options: movie, series, anime, livestream
  year: 2024,
  score: 8.5,
  duration: 120, // in minutes
  status: "ongoing", // ongoing, completed, upcoming
  contentRating: "TV-14",
  logoUrl: "https://site.com/logo.png",
  bannerUrl: "https://site.com/banner.jpg",
  playbackPolicy: "none", // none, torrent, "VPN Recommended", "External Player Only", etc.
  isAdult: false,
  description: "A detailed synopsis...",
  cast: [new Actor({ name: "John Doe", role: "Protagonist", image: "..." })],
  trailers: [new Trailer({ url: "https://youtube.com/watch?v=..." })],
  nextAiring: new NextAiring({ episode: 5, season: 1, unixTime: 1710360000 })
});
```

**Episode**
```javascript
const ep = new Episode({
  name: "S01E01",
  url: "https://site.com/watch/1",
  season: 1,
  episode: 1,
  rating: 4.5,
  runtime: 24,
  airDate: "2024-03-13",
  dubStatus: "dubbed", // none, dubbed, subbed
  playbackPolicy: "none"
});
```

**StreamResult**
```javascript
const stream = new StreamResult({
  url: "https://cdn.com/video.m3u8",
  quality: "1080p",
  headers: { "Referer": "https://site.com/" },
  drmKid: "...",
  drmKey: "...",
  licenseUrl: "..."
});
```
</details>

<details>
<summary><b>Standard Data Schemas</b></summary>

If you prefer raw objects, ensure they match these definitions:

### MultimediaItem (Full Schema)
| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `title` | `string` | Yes | Display name. |
| `url` | `string` | Yes | Unique ID (usually the source URL). |
| `posterUrl` | `string` | Yes | Vertical image URL. |
| `type` | `string` | Yes | `movie`, `series`, `anime`, or `livestream`. |
| `year` | `number` | No | Release year. |
| `score` | `number` | No | Rating (0.0 - 10.0). |
| `duration` | `number` | No | Total runtime in minutes. |
| `status` | `string` | No | `ongoing`, `completed`, or `upcoming`. |
| `logoUrl` | `string` | No | Transparent logo for premium header. |
| `contentRating` | `string` | No | Age rating (e.g., "PG-13", "18+"). |
| `playbackPolicy` | `string` | No | Playback status/requirements (e.g., "torrent", "External Only"). |
| `isAdult` | `boolean` | No | Adult content flag. |
| `cast` | `array` | No | List of `Actor` objects. |
| `trailers` | `array` | No | List of `Trailer` objects. |
| `nextAiring` | `object` | No | `NextAiring` object. |
| `recommendations`| `array` | No | List of `MultimediaItem` objects. |
| `syncData` | `object` | No | Map of external IDs `{ mal: "123", tmdb: "456" }`. |

### Episode (Full Schema)
| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `name` | `string` | Yes | Episode title or number label. |
| `url` | `string` | Yes | Unique URL for streaming. |
| `season` | `number` | Yes | Season number. |
| `episode` | `number` | Yes | Episode number. |
| `rating` | `number` | No | Episode specific rating. |
| `runtime` | `number` | No | Episode runtime in minutes. |
| `airDate` | `string` | No | Release date (YYYY-MM-DD). |
| `dubStatus` | `string` | No | `none`, `dubbed`, or `subbed`. |
| `playbackPolicy` | `string` | No | Episode specific playback policy. |
| `streams` | `array` | No | List of `StreamResult` for "Instant Load". |

### StreamResult
| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `url` | `string` | Yes | Playable link (MP4/HLS/Magnet). |
| `quality` | `string` | No | Label (e.g., "1080p"). |
| `headers` | `object` | No | HTTP headers required for playback. |
| `subtitles` | `array` | No | `{ url, label, lang }`. |
| `drmKid` | `string` | No | Widevine Key ID. |
| `licenseUrl` | `string` | No | DRM License server. |
</details>

<details>
<summary><b>Advanced Features</b></summary>

### Native SDK Helpers
SkyStream Gen 2 provides high-level SDK helpers for captcha and crypto.

| Helper | Signature | Description |
| :--- | :--- | :--- |
| **Captcha** | `await solveCaptcha(key, url)` | Opens a captcha solver for the user. Returns token. |
| **Crypto** | `await crypto.decryptAES(data, key, iv)`| Optimized AES decryption bridge. |

### Byte-Level Proxying
If a video host requires specific headers that the player can't send, use the Magic Proxy:
```javascript
const proxyUrl = "MAGIC_PROXY_v1" + btoa(`https://site.com/video.mp4`);
```

### Dynamic M3U8 Generation
Inject custom logic into playlists:
```javascript
const m3u8 = "magic_m3u8:" + btoa("#EXTM3U\n...");
```

### JS Timer Support (Optional)
SkyStream provides standard JavaScript timer functions. These are useful for handling rate-limiting, anti-bot delays, or background polling.

| Function | Description |
| :--- | :--- |
| `setTimeout(callback, delay)` | Executes `callback` after `delay` milliseconds. Returns a timeout ID. |
| `clearTimeout(id)` | Cancels a timeout previously established by `setTimeout`. |
| `setInterval(callback, delay)` | Repeatedly executes `callback` every `delay` milliseconds. Returns an interval ID. |
| `clearInterval(id)` | Cancels a repeating action previously established by `setInterval`. |

> [!NOTE]
> These functions are **globally available**. You do not need to include them in your plugin unless you specifically need delayed or repeated execution.
</details>

---
*Powered by SkyStream Gen 2 Architecture*
