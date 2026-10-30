# Slow Down Buddy: Technical, Legal-Risk, Security, Product and Business Review

**Product:** Slow Down Buddy, https://slowdownbuddy.com, a browser-based app for learning music by ear
**Repository:** `mvanbebber/futurerainbowlazer.com`, branch `claude/transcribe-mac-iphone-app-0zmziq`
**Prepared:** October 30, 2026, as a read-only audit.
**Updated:** October 30, 2026, after the fixes listed in §0.1. Sections below describe the code **as it is now**; findings that were fixed are marked **Fixed** with a pointer to the commit.
**Purpose:** a self-contained briefing for an independent review (for example by ChatGPT or an attorney).

### How to read this report

Each finding is tagged with how it was established:

| Tag | Meaning |
|---|---|
| **[Code]** | Confirmed by reading the source in this repository |
| **[Tested]** | Observed during development in headless Chromium with Playwright, including iPhone, iPad and Android device emulation. Not tested on real devices unless stated. |
| **[Owner]** | Reported by the developer from real-device use |
| **[Verify]** | Needs external verification: legal advice, current vendor terms, competitor products or real-device testing. Not established by code inspection. |

Nothing in this report is legal advice. Where it touches law (copyright, licensing, platform terms, privacy), it describes facts and risks for a qualified attorney to assess.

---

## 0. Executive summary

- **What it is:** a single-page web app (`deploy/index.html`, about 300 KB, no framework and no build step) that:
  - slows audio down without changing pitch (25–200%)
  - transposes and fine-tunes
  - loops and marks passages, with EQ, channel and "karaoke" tools
  - records from the microphone or from another browser tab
  - stores everything locally in IndexedDB

  It is hosted as static files on Netlify. There is no backend, no accounts and no server-side audio processing.
- **Audio engine:**
  - **Main engine:** Signalsmith Stretch 1.3.2 (MIT), a WebAssembly AudioWorklet.
  - **Custom extension:** an attack-preserving time warp that keeps drum and note onsets crisp below 45% speed.
  - **Fallback:** a hand-written WSOLA engine on the deprecated `ScriptProcessorNode`.
- **Third-party code:** shipped code is permissively licensed (MIT, BSD-3-Clause, Apache-2.0, ISC, zlib), **except `codec-parser` 2.5.0 inside `flac-decoder.min.js`, which is LGPL-3.0-or-later** (missed by the first version of this review). Full notices, license texts and the corresponding source packages are now published at `/licenses/` (§2). No GPL or AGPL code is shipped [Code].
- **Repository hygiene:** stray Python wheels, an old project ZIP and screenshots were removed from the current tree. **The repository is public, and those files remain in its Git history** until history is rewritten, which needs the owner's approval (§2.4).
- **Audio never leaves the device [Code].**
  - **Network calls made by the app:** GoatCounter analytics (now from a pinned, self-hosted copy of its script), Netlify Forms (feedback and waitlist), and the local `demo.mp3`. A Content-Security-Policy limits connections to the site itself and the GoatCounter endpoint.
  - **Tab recording:** uses the browser's standard `getDisplayMedia` screen-share prompt and records what the tab plays. It does not download source media, intercept network streams or decrypt anything.
- **Main remaining risks:**
  1. **Data loss:** browser storage can be cleared; Safari may evict it after 7 days without a visit. Warnings and backup reminders are now clearer, but there is still no automatic backup.
  2. **Memory on phones** with very long songs (reduced, see §8.2; not tested on real devices).
  3. **Copyright and platform-terms exposure** from how the recording feature is marketed (§3).
  4. **LGPL obligations** for `codec-parser`, now addressed by notices and source packages, but worth confirming with counsel (§2.3).
  5. **Visual similarity to Transcribe!**, which the owner deliberately modeled the interface on.
  6. **Third-party script and missing CSP: fixed** (§4.3).
- **Monetization fit:**
  - A one-time **$39.99 Pro** purchase is technically easy to add without accounts, using a merchant-of-record license key.
  - **Exporting processed audio is low-to-moderate effort,** because the engine already renders correctly in `OfflineAudioContext`.
  - **Chord detection is moderate effort** for a basic version and high effort for a good one.
  - An iOS App Store version could not simply honor web-purchased licenses without care for Apple's rules **[Verify]**.

### 0.1 Fixes made on October 30, 2026

All of these are in commits on `claude/transcribe-mac-iphone-app-0zmziq`, tested as described in §0.2.

| Area | Fix | Commit |
|---|---|---|
| Repository | Removed tracked Python wheels, `SlowDown.zip` and three screenshots; `.gitignore` blocks them at the repository root. History not rewritten. | `a47a04f` |
| Licenses | Complete `THIRD-PARTY-NOTICES.txt` with full MIT, BSD-3-Clause (libFLAC, libopus with the Opus patent notice), zlib (puff), ISC (GoatCounter) and CC0 texts; full Apache-2.0, LGPL-3.0 and GPL-3.0 texts under `/licenses/`; corresponding source packages for `codec-parser`, the FLAC/Opus decoders and their common package, with SHA-256 sums; new `/licenses/` page linked from the app and every page footer. | `795ed26` |
| Analytics | `count.js` self-hosted at `/vendor/goatcounter-count.js` (unmodified, from `arp242/goatcounter` commit `c031008`, SHA-256 `792b7abd…`). | `795ed26` |
| Security headers | Content-Security-Policy added in `deploy/_headers` (scripts from self, inline, `blob:` and `wasm-unsafe-eval` only; connections to self and `slowdownbuddy.goatcounter.com` only; `frame-ancestors 'none'`; `object-src 'none'`; `form-action 'self'`). | `795ed26` |
| Restore | Backups are rebuilt from an allow-list of validated, clamped fields (no `Object.assign`); bad entries skipped; the ZIP reader bounds-checks offsets and sizes and verifies inflated sizes. | `378bf2c` |
| Data safety | Demo-song edits are saved; storage line explains that clearing browser data deletes the library, suggests the Home Screen on iOS, and shows the last backup date and songs added since. | `378bf2c` |
| Memory | Phones keep 1 decoded song (plus the demo) instead of 3; undo history no longer keeps decoded audio. | `378bf2c`, `49ac8d4` |
| Rendering | Static waveform layer cached; only the playhead is drawn per frame (pixel-identical output). | `98923e6` |
| Bugs | "Claude preview" error message replaced. | `378bf2c` |
| Discoverability | "Record a website" text label on desktop screens ≥1400 px with a mouse. | `f121b8d` |
| Legal pages | Privacy and Terms updated to match actual behavior (storage keys, analytics payload, permissions, retention, recording responsibility). | `b2ba09c` |

Not changed, by design: the pause/stop behavior (Pause and Stop return to where Play was pressed) is a deliberate owner decision from Oct 27 and was left as is.

### 0.2 How the fixes were tested

**Automated, in headless Chromium (Playwright) against a local server that applies the same headers as Netlify. Not tested on physical devices.**

- **43 checks in one run, all passed.** They covered:
  - **Imports:** MP3, WAV, FLAC, M4A (AAC, ALAC, Opus), OGG, WebM and MP4 video.
  - **Persistence:** the library survives a reload.
  - **Speeds:** 25/50/70/100/150/200%, with audible output and the playhead moving at the expected rate (within 6%).
  - **Attack preservation** data loaded.
  - **Pitch,** measured on a 440 Hz tone: +12 → 880.2 Hz, −12 → 220.7 Hz, +7 → 659.5 Hz, +50 cents → 454.9 Hz.
  - **Channel modes and EQ:** karaoke cancels centered audio (0.0624 → 0.0000 RMS), left-only plays, an EQ cut reduces a 440 Hz tone.
  - **Transport, seek and loop wrap.**
  - **Markers** with undo and redo.
  - **Recording:** microphone (simulated device), and **tab recording** (Chromium's automatic tab selection, no real picker).
  - **Backup:** a full backup → delete-all → restore round trip.
  - **Layouts** for iPhone 15 Pro, iPhone SE, Pixel 7, iPad portrait and landscape, and desktop at 1280 and 1920 px.
  - **Cleanliness:** no CSP violations, console errors or failed requests.
- **Forced-fallback decoding** (simulating Safari's refusals) of FLAC, ALAC, Opus-in-M4A and AAC under the CSP.
- **Analytics:** under the CSP, the page view and all app events reached the GoatCounter endpoint. The endpoint was simulated, because this environment cannot reach goatcounter.com.
- **Hostile backups:**
  - prototype-pollution keys, out-of-range values, bad IDs and paths: sanitized, or skipped and counted
  - non-JSON, wrong-app, garbage and truncated ZIPs: rejected with a message
  - deflate-compressed backups and pre-rename (`SlowDown`) backups: still restore
- **Waveform cache:** the canvas was pixel-identical to the previous version in 10 states (loop, zoom, drag selection, growing loop band, adding/moving/deleting markers, whole-song view, switching songs).
  - Draw time per frame: 0.93 → 0.11 ms (desktop) and 1.9 → 0.21 ms (iPhone size at 4× CPU slowdown).
- **Memory:** renderer memory growth after importing three 5-minute songs fell from about 500 MB to about 400 MB (desktop) and about 300 MB (phone emulation).

**Not tested:** real iPhone, iPad, Android or Mac/Windows hardware; Safari and Firefox (only Chromium is available here); a real tab-picker interaction; the live Netlify deployment, which this environment cannot reach.

---

## 1. Technical architecture

### 1.1 Languages, frameworks and libraries [Code]

| Layer | What it is |
|---|---|
| Web app | Plain HTML, CSS and JavaScript in one file, `deploy/index.html`. No framework, no bundler, no package manager, no `package.json` or lockfile. |
| Time-stretch / pitch-shift | **Signalsmith Stretch 1.3.2**, inlined in `index.html`. It is a C++ library compiled to WebAssembly, wrapped as an AudioWorklet (the WASM is embedded as base64 and loaded via a `blob:` URL). MIT license header present inline. |
| FLAC fallback decoder | `deploy/flac-decoder.min.js`: `@wasm-audio-decoders/flac` 0.2.11 (MIT), containing libFLAC (BSD-3-Clause) compiled to WASM. Loaded on demand. |
| Opus fallback decoder | `deploy/opus-decoder.min.js`: `opus-decoder` 0.7.12 (MIT), containing libopus (BSD-3-Clause). Loaded on demand. |
| MP4/M4A fallback | `deploy/m4a-decoder.js`, written for this project: an MP4 demuxer, an Apple Lossless (ALAC) decoder ported from Apple's Apache-2.0 reference decoder, AAC via WebCodecs or by re-wrapping as ADTS, and Opus via the decoder above. |
| ZIP backup | Custom ZIP writer (stored, CRC-32) and reader (stored, or deflate via `DecompressionStream`) inside `index.html`. |
| Analytics | GoatCounter `count.js`, self-hosted unmodified at `deploy/vendor/goatcounter-count.js` (pinned to upstream commit `c031008`), reporting to `https://slowdownbuddy.goatcounter.com/count`. |
| Hosting | Netlify static hosting (`netlify.toml`, `deploy/_headers` with Permissions-Policy and Content-Security-Policy) plus Netlify Forms. |
| Guide and legal pages | Static HTML (`deploy/*/index.html`) sharing `deploy/guides.css`. |
| Native app (not shipped) | `SlowDownBuddy/`: a Swift/SwiftUI project for macOS 14+ and iOS 17+, generated with XcodeGen (`project.yml`). Uses AVFoundation, Accelerate, ScreenCaptureKit (macOS system audio), ReplayKit (iOS broadcast extension), SwiftUI and Observation. **It has never been compiled or shipped [Owner]**; a GitHub Actions workflow exists to build it. |

### 1.2 Audio processing architecture [Code]

**Decoding:**
- Files are decoded to an in-memory `AudioBuffer` with `decodeAudioData`.
- The fallbacks above cover what the browser's own decoder rejects: FLAC on iOS; ALAC, Opus-in-MP4 and some AAC M4A on Safari.

**Playback chain:**
- `Engine` class → Signalsmith `AudioWorkletNode` (or the WSOLA `ScriptProcessorNode` fallback) → 5-band EQ (80 Hz, 300 Hz, 1 kHz, 3 kHz, 8 kHz) → gain → output.
- An `AnalyserNode` probe on the stretcher output detects whether the high-quality engine is silent and then switches to the fallback automatically. This addresses a real iOS issue seen in development.

**Channel modes** are pre-computed buffers handed to the stretcher:
- stereo
- mono (L+R)
- left only
- right only
- "karaoke" ((L−R)×0.7, center cancel)

**Looping, seeking and the playhead:**
- These use Signalsmith's `schedule()` time-map API.
- The playhead position is estimated on the main thread from the schedule segments.

**Visuals and analysis:**
- **Waveform:** a peaks array pre-computed per song (`computePeaks`). The waveform, loop band and marker lines are drawn into a cached offscreen canvas and only the playhead is drawn each frame.
- **Keyboard view:** notes at the playhead come from a 32,768-point FFT in JavaScript (`noteLevels`), run about every 180 ms while the keyboard is visible.
- **Onset detection:** runs once per song load, using spectral flux on half-sample-rate audio with a 512-point FFT, in slices so the page stays responsive.

### 1.3 Time-stretch, pitch-shift and the attack warp [Code] [Tested]

- **Signalsmith Stretch** is an STFT/phase-vocoder-family stretcher with independent pitch shifting. The app uses its default preset: about 120 ms blocks with a 30 ms interval.
- **Custom "attack warp"** (added Oct 26):
  - **The problem:** below 45% speed, a phase vocoder smears each transient into a swell.
  - **What it does:** each detected onset plays at normal speed from 35 ms before to 60 ms after the onset, and the gaps between onsets stretch slightly more to compensate. The overall timing, loops and the playhead stay exact.
  - **Where it lives:** `warpAt()` inside the worklet code, plus `detectOnsets()` and `attackWarp()` on the main thread.
  - **Measured on synthetic test material at 25%:** pre-echo before a hit fell from about 19% to 2%, and drum-attack prominence roughly doubled [Tested]. This is similar in spirit to Rubber Band's "crisp" mode; Rubber Band itself is GPL and was deliberately not used.
- **WSOLA fallback:** a hand-written time-domain overlap-add engine on `ScriptProcessorNode`, with resampling for pitch.
- **Speed mapping:** a slider from −100 to +100 maps to 25–100% and 100–200%. The presets are 25, 50, 60, 70, 80, 90 and 100%.
- **Pitch range:** semitone buttons for ±1 and ±12, typed values up to ±24 semitones, and fine-tune in ±1-cent steps up to ±50 cents.

### 1.4 Browser recording and tab capture [Code]

- **Tab capture:**
  - Calls `navigator.mediaDevices.getDisplayMedia({ video: true, audio: {echoCancellation:false, noiseSuppression:false, autoGainControl:false}, systemAudio: 'include', selfBrowserSurface: 'exclude' })`.
  - The browser shows its own picker, and the user chooses a tab and enables "Share tab audio".
  - Only the audio tracks are recorded, with `MediaRecorder` (preferred MIME type chosen by `pickMime()`, 256 kbps), collected in 1-second chunks in memory.
  - On stop, all tracks are stopped, the chunks become a `Blob`, and the result goes through the normal import path into IndexedDB.
- **Microphone:** `getUserMedia({audio: {...processing off}})`, with the same recorder path.
- **A video track is requested** because browsers require one for tab sharing. It is not recorded, but it stays live, with the browser's sharing indicator showing, until recording stops.
- **Where the button appears:** `CAN_CAPTURE_TAB` hides the tab-capture button on iOS, Android and other mobile user agents, because no phone or tablet browser supports tab capture.
- **Permissions-Policy** (`deploy/_headers`): `microphone=(self), display-capture=(self)`.

### 1.5 Local storage [Code]

| Store | Contents |
|---|---|
| IndexedDB database `slowdown`, version 1 | object store `songs` (keyPath `id`): song metadata (title, source, duration, settings, markers, loops, `audioLost` flag); object store `audio`: one `Blob` per song (the original file bytes or the compressed recording) |
| localStorage | `slowdown.keyboard` (keyboard view on/off), `slowdown.hq` (high-quality engine on/off), `slowdown.phoneTip` (first-visit tip dismissed), `slowdown.recNote` (first-recording notice shown), `slowdown.demo` (the demo song's loops, markers and settings), `slowdown.lastBackup` (time of the last backup). GoatCounter's script reads `skipgc` only if a visitor opts out with `#toggle-goatcounter`. |
| `navigator.storage.persist()` | requested on import and recording |
| OPFS / Cache API | **not used** |

- **Storage fix, Oct 29–30:**
  - Imports and restores now store a full in-memory copy (`new Blob([arrayBuffer])`) instead of the picked `File`, or a slice of the backup ZIP. On iOS those can be references to temporary files that iOS later deletes [Owner reported the symptom].
  - Songs that can still be read are re-saved as copies when opened.
  - Songs whose audio is already lost are flagged `audioLost`. Re-opening the same file, matched by title, or restoring the backup again re-attaches the audio while keeping loops and markers.
- **Undo/redo:** snapshot-based, up to 300 entries, in memory only. Undo steps for adding or deleting songs keep the compressed audio file, not the decoded audio.
- **Restore validation:** `cleanBackupSong()`, `cleanSettings()`, `cleanMarkers()` and `cleanLoops()` rebuild every restored record from allowed fields; the demo record in localStorage goes through the same functions.

### 1.6 Offline and PWA [Code]

- `manifest.webmanifest` (standalone display, icons) and Apple "web app capable" meta tags let users add the app to the Home Screen.
- **There is no service worker.** The app does **not** work offline on a first or uncached visit, and there is no install prompt flow or update strategy.
- Once loaded, playback needs no network: everything after load is local, except analytics and the forms.

### 1.7 Browser compatibility and known limitations

| Item | Status |
|---|---|
| Chrome, Edge, Brave (desktop) | Full feature set, including tab capture [Owner confirmed Brave; Spotify web player tab capture worked for the owner] |
| Opera, Vivaldi, Arc | Chromium-based, so expected to work; **not tested [Verify]** |
| Firefox desktop | Everything except tab audio capture (Firefox doesn't provide tab audio via `getDisplayMedia`) [Verify current Firefox] |
| Safari macOS | Everything except tab audio capture [Verify] |
| iPhone / iPad (all iOS browsers use WebKit) | Playback, file import (FLAC, ALAC, Opus via the fallbacks), mic recording; no tab capture. Required unlocking audio with a silent `<audio>` element and `navigator.audioSession` handling. Storage subject to 7-day eviction for non-installed sites [Verify]. |
| Android Chrome | Playback, import, mic; no tab capture [Owner: a user on Samsung/Chrome hit the old tab-capture error, now hidden] |
| `ScriptProcessorNode` fallback | Deprecated API; still works in current browsers but could be removed in future |

### 1.8 Architectural strengths and weaknesses

**Strengths:**
- Zero-backend, privacy-by-design architecture: nothing to breach server-side, near-zero hosting cost, and a strong privacy story.
- A high-quality stretcher, with a measurable improvement for transients at slow speeds.
- Unusually broad format support on iOS, through the custom fallbacks.
- No build tooling, so it is simple to deploy and audit.

**Weaknesses:**
- **One ~3,800-line file** (≈300 KB, of which the inlined Signalsmith library is a large part): hard to maintain or test, and there are no automated tests in the repository. The Playwright checks used during development were ad-hoc scripts, not committed.
- **Most work runs on the main thread,** apart from the AudioWorklet: decoding fallbacks, the FFTs and peak computation. Per-frame drawing is now cheap (cached waveform layer).
- **Memory-heavy design:** full decoded float audio plus copies (see §8).
- **Single point of truth in browser storage,** with only manual ZIP backups.
- **Fixed:** the analytics script is now self-hosted and pinned, and a Content-Security-Policy is in place (see §4). The CSP still needs `'unsafe-inline'` for scripts, because the app is one HTML file with inline code.

---

## 2. Open-source licenses and legal risks

### 2.1 Components shipped to browsers [Code]

There are no lockfiles because there is no package manager. These are all the third-party components in `deploy/`:

| Component | Version | Location | License | Obligations |
|---|---|---|---|---|
| Signalsmith Stretch (C++ library + JS wrapper, compiled to WASM) | 1.3.2 | inlined in `index.html` | MIT (header inline, lines ~687–695) | Keep the copyright notice and permission notice: **met** inline and in `THIRD-PARTY-NOTICES.txt` |
| `@wasm-audio-decoders/flac` | 0.2.11 | `flac-decoder.min.js` | MIT (Ethan Halsall) | Keep the notice: **met** in the notices file |
| ↳ libFLAC (inside the WASM) | not recorded upstream | same file | BSD-3-Clause (Xiph.Org) | Reproduce notice, conditions and disclaimer: **met** (full text in the notices file) |
| ↳ codec-parser (bundled JS) | 2.5.0 | same file | **LGPL-3.0-or-later** | Provide the LGPL-3.0 and GPL-3.0 texts, notice, and corresponding source; allow replacement of the library. **Met:** texts and source packages at `/licenses/`; the decoder is a separate, replaceable file. Confirm sufficiency with counsel **[Verify]** |
| `opus-decoder` | 0.7.12 | `opus-decoder.min.js` | MIT (Ethan Halsall) | Met |
| ↳ libopus (inside the WASM) | not recorded upstream | same file | BSD-3-Clause (Xiph.Org and contributors), plus royalty-free patent licenses | **Met** (full text and patent notice in the notices file) |
| ↳ `@wasm-audio-decoders/common` | 9.0.7 | both decoder files | MIT | Met |
| ↳ simple-yenc | 1.x | both decoder files | MIT | Met |
| ↳ puff (Mark Adler, WASM inflate) | 2.3 | both decoder files | zlib-style | Met (notice reproduced) |
| ↳ Emscripten runtime glue | n/a | `index.html` and decoders | MIT | Met (notice included) |
| `@eshaz/web-worker` | 1.2.2 | **not bundled** (only required in Node/CommonJS builds) | Apache-2.0 | None |
| ALAC decoder (port) | n/a | `m4a-decoder.js` | Apache-2.0 (derived from Apple's ALAC reference decoder; structure informed by alac.js) | Copy of the license, statement of changes and attribution: **met**. Apple's `macosforge/alac` repository has **no NOTICE file** (checked). alac.js's own license (npm says Apache-2.0) **[Verify]** |
| GoatCounter `count.js` | upstream commit `c031008` | `vendor/goatcounter-count.js` | **ISC** (stated in the file; the rest of GoatCounter is EUPL-1.2 but isn't shipped) | Keep the notice: **met** |
| Demo recording `demo.mp3` | n/a | `deploy/demo.mp3` | Stated CC0 1.0 (Kimiko Ishizaka, *The Open Well-Tempered Clavier*) | None under CC0; provenance should be confirmed **[Verify]**: the file was supplied by the owner; the notices file asserts CC0 |

**Copyleft:** one LGPL-3.0-or-later component (`codec-parser`, inside the FLAC fallback decoder) is shipped; no GPL or AGPL code [Code]. The first version of this review missed it. The minified decoder files were confirmed byte-for-byte identical to the published npm builds (opus with its source-map comment removed).

**Fonts, icons and graphics [Code]:**
- **Fonts:** system fonts only (`system-ui`, `-apple-system`, `ui-monospace`). No web fonts are loaded.
- **Icons:** all are inline SVG paths written for this project, not copied from icon libraries.
- **Logo:** headphones and waveform, an original SVG (`branding/logo.svg`).
- **Screenshots:** `og-image.png` and `guides-app.png` are screenshots of this app.

### 2.2 Native project [Code]

The `SlowDownBuddy/` Swift sources use only Apple system frameworks; there are no third-party packages (no Swift Package Manager dependencies, CocoaPods or Carthage).

### 2.3 Problems and gaps in licensing

1. **Fixed: incomplete notices.** Full texts for every license are now in `THIRD-PARTY-NOTICES.txt` and `/licenses/`.
2. **Partly open: versions of the bundled C libraries.** The wasm-audio-decoders packages don't state the exact libFLAC and libopus versions they compile [Verify upstream].
3. **Fixed: provenance.** Package versions are recorded, the decoder files match npm byte-for-byte, the source packages are published with SHA-256 sums, and the GoatCounter script is pinned to a commit with its hash.
4. **Fixed: notices accessible.** `/licenses/` is linked from the app's Help tab and from every page footer.
5. **New, addressed: LGPL `codec-parser`.**
   - Obligations met by the notices, the license texts, the source packages, and the decoder being a separately loaded, replaceable file.
   - **Counsel should confirm** this satisfies LGPL-3.0 §4 for a minified web bundle [Verify].
   - Alternative if preferred: replace the FLAC fallback with a decoder that doesn't bundle `codec-parser`.
6. **AI-assisted authorship:** much of the code was written with an AI coding assistant, for example the ALAC port written from the reference implementation [Owner context]. Two questions for counsel [Verify]:
   - Copyrightability and ownership of AI-assisted code under current US Copyright Office guidance.
   - Whether any generated code reproduces third-party code closely enough to carry its license. The ALAC port is acknowledged as derived and licensed accordingly.

### 2.4 Unrelated files committed to the repository [Code]

**Fixed in the current tree** (`a47a04f`): these were tracked in git but not part of the app, and have been removed:

| File | Size | Notes |
|---|---|---|
| `numpy-2.5.4-…whl` | 16.7 MB | Python wheel. Bundles numpy (BSD-3) plus native libraries such as OpenBLAS / gfortran runtime under their own licenses **[Verify]** |
| `soundfile-0.14.0-…manylinux….whl` | — | python-soundfile (BSD-3); **manylinux wheels typically bundle libsndfile, which is LGPL-2.1 [Verify]** |
| `cffi-…whl`, `pycparser-…whl`, `typing_extensions-…whl` | small | MIT / BSD / PSF |
| `SlowDown.zip` | 53 KB | An archive of the earlier native project ("SlowDown") |
| `desktop.png`, `phone.png`, `pitch.png` | ~100–220 KB each | Development screenshots |

They were committed accidentally during development: tool downloads written into the working directory. **The repository is public** (confirmed), so these files, including the wheels that bundle third-party native libraries, possibly LGPL ones, **are still downloadable from Git history**. Removing them from history requires rewriting history and force-pushing, which **needs the owner's approval**; it would also change commit hashes for anyone with a clone. They were never served by the website, since Netlify publishes only `deploy/`.

### 2.5 Would selling a Pro version create licensing obligations?

- **The current components allow commercial use** (MIT, BSD-3, Apache-2.0, ISC, zlib, and LGPL-3.0 for `codec-parser`). Selling Pro creates no new copyleft obligations for the app's own code. Keep the notices, keep offering the LGPL source and keep the decoder replaceable, and don't use contributors' names for endorsement (BSD-3 clause 3).
- **Watch future Pro dependencies:**
  - **MP3 encoders:** LAME and its ports such as lamejs are **LGPL**. Shipping them in a web page is possible but brings LGPL obligations (replaceability, source offer). Alternatives: WAV export (no encoder), or WebCodecs `AudioEncoder` (AAC/Opus) where supported.
  - **FFmpeg.wasm:** LGPL, or GPL depending on the build.
  - **Rubber Band:** GPL-2.0+, or a commercial license. Avoided so far; keep it that way unless licensed commercially.
  - **AI stem separation models** (Demucs, Spleeter, others): check both the code and the **model-weight** licenses. Some weights are non-commercial **[Verify]**.
  - **Chord recognition libraries:** for example Essentia is AGPL-3.0, and madmom's code is BSD while its models are CC BY-NC-SA, which is non-commercial **[Verify current terms]**. Writing your own avoids this.
- **Trademarks:** the guide pages compare against named products (Transcribe!, Capo, Amazing Slow Downer, Anytune, Moises) with disclaimers. Comparative use is generally permitted when truthful **[Verify]**.

### 2.6 Trade dress / look-and-feel

- **The history [Owner]:** the owner asked for the interface to "copy" Transcribe!'s UI, a commit message reads "Transcribe!-style layout", and a musician publicly asked whether it is Transcribe!.
- **What's original [Code]:** the code and graphics are original.
- **What's similar:** the overall arrangement deliberately echoes Transcribe!: toolbar, marker strip with flags, stereo waveform, keyboard strip, transport and a tabbed lower panel.
- **Risk:** copyright generally doesn't protect functional layouts, but distinctive combinations of visual elements can raise trade-dress or unfair-competition questions **[Verify with counsel]**. Mitigation: a distinct visual identity (§9.7).

---

## 3. Copyright and browser recording

### 3.1 Exactly how recording works [Code]

1. The user clicks **Record a website** (desktop Chromium browsers only).
2. The app calls `getDisplayMedia`, and the **browser** shows its own picker. The user must choose a tab and enable audio sharing.
3. The browser hands the app a live `MediaStream` of what that tab is rendering: decoded audio output, plus a video track the app does not record.
4. `MediaRecorder` encodes the audio (Opus/WebM in Chromium) in memory.
5. On stop, the recording is saved to the user's IndexedDB as a library item.

### 3.2 What it does *not* do [Code]

- **Does not download source media:** no requests to YouTube, Spotify or any media site, and no URL input.
- **Does not intercept network streams:** no proxy, no extension, no access to other tabs' network traffic or page code.
- **Does not circumvent technical protections:** no decryption, no DRM/EME interaction. It receives whatever audio the browser chooses to share through its standard screen-capture API. The owner reports that capturing Spotify's web player worked, which indicates the browser shared that tab's output audio. Whether capturing the output of a DRM-protected stream raises anti-circumvention issues (for example DMCA §1201, the "analog hole") is a **legal question [Verify]**, but the app performs no circumvention steps of its own.
- **Uses no external APIs or services for audio.** The only external services are GoatCounter (analytics) and Netlify (hosting and forms).

### 3.3 Do recordings stay local? [Code]

Yes. Recordings, imported files, loops and markers live only in the user's browser storage. The only ways they leave the device are actions the user takes themselves:
- **Back up library**, which downloads a ZIP containing the audio.
- Sharing that ZIP.

### 3.4 Features that add copyright or platform-terms risk

| Feature / practice | Why it matters |
|---|---|
| Marketing copy naming YouTube and Spotify as sources ("record from any browser tab: Spotify, YouTube, Bandcamp") | Could be read as encouraging copying from those services; their terms of service generally prohibit recording or downloading **[Verify]**. Courts have weighed inducement, e.g. *MGM v. Grokster* **[Verify]** |
| Backup ZIPs contain the original audio | A user could share a ZIP of copyrighted recordings, which is distribution, though by the user |
| Planned **export** of processed audio | Makes it easier to produce portable copies of recorded content |
| A future iOS app with system-audio capture (ReplayKit) | Apple's App Review Guideline 5.2.3 restricts apps that save or convert media from third-party sources **[Verify current text]** |

**Existing mitigations [Code]:**
- A Terms of Use page with "only record audio you have the right to use", personal practice and "follow the site's terms" language.
- A one-time notice in the recording bar on the first recording.
- No sharing or upload features.
- Recordings stay local.

### 3.5 Legal questions for independent review [Verify]

1. Does providing a general-purpose tab recorder, without circumvention, create secondary-liability exposure under US law (*Sony*, *Grokster*), and how much does marketing language matter?
2. Is the personal practice copy made by users fair use, and does that matter for the provider?
3. Platform terms (YouTube, Spotify): any exposure for the provider, as opposed to the user?
4. Do the export and backup features change the analysis?
5. Are the existing Terms of Use and Privacy pages adequate for a paid product, including disclaimer enforceability, governing law, consumer law and the EU/UK if marketed there?

---

## 4. Privacy and security

### 4.1 Data stored, collected or sent [Code]

| Data | Where | Leaves the device? |
|---|---|---|
| Audio files, recordings | IndexedDB `audio` | **No.** Only inside a backup ZIP the user downloads |
| Song metadata, loops, markers, settings | IndexedDB `songs` | No |
| UI preferences, demo edits, last-backup time (6 keys) | localStorage | No |
| Page views and feature events | GoatCounter (script self-hosted) | **Yes:** path or event name, page title, referrer, query string, screen width and a bot flag; the request also carries the IP address and user agent, from which GoatCounter derives browser, OS and country. Event names: `import-<ext>`, `recorded-website`, `recorded-mic`, `backup`, `open-feedback`, `open-waitlist`, `feedback-sent`, `waitlist-joined`, `played`, `slowed-down`, `used-loop`, `tip-dismissed` |
| Feedback form | Netlify Forms (POST to `/`) | **Yes:** message, optional email, and a `context` field with the **full user agent**, the current song's source type (file / tab / mic / example) and the current speed |
| Pro waitlist form | Netlify Forms | **Yes:** email (required), checked features, free text |
| Demo song | `GET /demo.mp3` from the same origin | Request only |
| Venmo "Support" link | opens venmo.com in a new tab | Only if clicked |

- **Cookies:** none set by the app. GoatCounter states it doesn't use cookies [Verify].
- **Other telemetry:** none; no error reporting, no fingerprinting code.

### 4.2 Permissions [Code]

- The microphone and tab capture are requested **only when the user clicks a record button,** through the browser's own prompts.
- `Permissions-Policy` restricts both to the site's own origin.
- During tab capture, the unused video track stays active, so the browser's "sharing" indicator shows, until recording stops.

### 4.3 Security review [Code]

- **XSS:**
  - User-controlled strings (song titles, marker and loop names, file names, restored backup contents) are written with `textContent` or `.value`.
  - The `innerHTML` uses found are constant strings or app-computed numbers (storage line, EQ labels, icons).
  - **No direct XSS path found.**
- **Restore from backup (fixed, `378bf2c`):**
  - Each record is rebuilt from an allow-list: types checked, numbers clamped, strings capped.
  - IDs and audio paths must match strict patterns; unknown keys, including `__proto__`, are dropped.
  - The ZIP reader rejects offsets or sizes outside the file, checks local-header signatures and verifies inflated sizes.
  - Malformed files are rejected with a message, and damaged entries are skipped and counted.
- **Third-party script (fixed, `795ed26`):**
  - `count.js` is served from the site itself, pinned to an upstream commit and unmodified.
  - It still runs with page privileges, but it can no longer change without a commit to this repository.
- **Content-Security-Policy (added, `795ed26`):**
  ```
  default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' blob:; worker-src 'self' blob:;
  connect-src 'self' https://slowdownbuddy.goatcounter.com; img-src 'self' data: blob: https://slowdownbuddy.goatcounter.com;
  media-src 'self' blob: data:; style-src 'self' 'unsafe-inline'; font-src 'self'; manifest-src 'self'; object-src 'none';
  base-uri 'self'; form-action 'self'; frame-ancestors 'none'; upgrade-insecure-requests
  ```
  - Even injected code can't send data anywhere except the site and the GoatCounter endpoint.
  - `'unsafe-inline'` remains for scripts and styles because the app is a single HTML file with inline code. Moving to hashes or a nonce is possible but would need regenerating on every change.
- **No `eval` or `new Function` in app code.** `URL.createObjectURL` is used for the worklet and downloads.
- **Netlify Forms:** a honeypot field is present. No rate limiting or CAPTCHA [Verify Netlify spam filtering].
- **Fixed: leftover user-facing text.** The recording error that mentioned the Claude preview now tells users to check their browser's permissions.

### 4.4 Data-loss risks

- **All user data lives in browser storage:**
  - Clearing site data, "clear history", browser reinstalls, switching browsers or profiles, and private windows all lose it.
  - Safari can evict storage after 7 days without a visit for sites not added to the Home Screen [Verify current WebKit policy].
  - **The storage status line (improved, `378bf2c`)** now:
    - says plainly that clearing history or site data deletes the library
    - on iPhone/iPad, suggests adding the app to the Home Screen
    - shows the last backup date and how many songs were added since
  - **Persistent storage** (`navigator.storage.persist()`) is requested when the user imports or records. It isn't requested on every page load, because Firefox shows a permission prompt for it.
- **iOS file-reference bug** (fixed Oct 29–30): songs imported or restored before the fix may already have lost their audio. They now show a clear message and can be re-linked [Code][Owner].
- **No automatic backup or sync.** Backups are manual ZIP downloads, now with a reminder of the last backup date.
- **Demo-song edits** are now saved (localStorage, `378bf2c`).
- **Storage quota:** large libraries can hit browser quotas. On a failed write, the app warns that a song "plays now but couldn't be saved".
- **Undo history is lost on reload** (in memory only).

### 4.5 Privacy-policy disclosures

**Updated (`b2ba09c`):** `/privacy/` now covers:
- the localStorage keys and their purposes
- that clearing browser data deletes the library
- microphone and screen-sharing permissions
- the exact analytics payload and event names
- the full user-agent string in feedback
- form retention in Netlify and deletion requests

`/terms/` now says that being able to record something doesn't mean you're allowed to, that no service has authorized recording through the app, and that backups contain audio. Still open:
- **Contact details:** currently "use the feedback form". A dedicated email may be expected under some laws [Verify].
- **If the app is marketed to the EU or UK:** lawful basis, rights and international transfers [Verify].

---

## 5. Feature inventory [Code], with [Tested] or [Owner] where noted

### 5.1 Getting audio in
- **Open files** with the folder button or by drag and drop, several at once:
  - MP3, WAV, AAC/M4A, MP4/MOV audio, OGG/WebM where the browser supports them
  - FLAC (WASM fallback on iOS)
  - Apple Lossless M4A and Opus-in-M4A (custom fallbacks)
  - Voice memos (M4A)
- **Record a website tab** (desktop Chrome, Edge and Brave): saved straight to the library as "Captured tab".
- **Record the microphone** (all platforms).
- **Built-in demo:** Bach Prelude in C major (CC0), with 35 bar markers, 3 section markers and 3 saved loops. Changes to it are now saved between visits.
- **Recover lost audio:** re-opening a file with the same title re-links its audio, keeping loops and markers.

### 5.2 Playback and transport
- **Buttons:** play, pause and stop. Pause/stop return to where Play was pressed; pressing Stop twice goes to the loop or song start.
- **Play always starts at the loop start** when a loop is on.
- **Navigation buttons:** previous/next marker (◀◀ / ▶▶), song start (|◀), last marker (▶|).
- **End of song** returns to the loop start or to the play origin, and keeps playing.
- **Seeking:** click the waveform or ruler, click a marker, or type a time into the position box.

### 5.3 Speed and pitch
- **Speed:** 25–200% via slider, presets, typed value, and Shift+↑/↓ for ±5%.
- **Full-speed / practice-speed toggle** (turtle button, T key).
- **Transpose:** ±1 and ±12 semitone buttons (hold to repeat), typed values up to ±24, with a green "0" when in the original key.
- **Fine-tune:** ±1 cent steps up to ±50 cents, typed or by holding the buttons; Reset button.
- **Engine options:** high-quality (Signalsmith) on by default, a basic-engine toggle, and automatic fallback if the HQ engine is silent.
- **Attack-preserving playback** below 45% speed (automatic).

### 5.4 Loops and markers
- **Making loops:**
  - drag across the waveform
  - the [AB] button or L key: first press marks the start, and the blue band grows with the playhead until the second press
  - A or I sets just the start; O sets just the end
- **Editing loops:**
  - drag a loop's middle to move it; drag its edges to resize
  - type exact loop start/end times
  - loop on/off (button, Shift+L), clear loop
  - zoom to loop
- **Saved loops:** named, listed and clickable.
- **Markers:**
  - three kinds: section, marker (measure) and beat, added with S, M, B or buttons
  - while playing: + Marker button on phones
  - drag on the ruler; double-click to rename
  - list with "Loop from here", "Move here" and delete
  - time labels on the ruler
- **Undo/redo:** ⌘Z/Ctrl+Z, ⇧⌘Z/Ctrl+Y, covering edits, deletions and song removal.

### 5.5 Waveform and visualization
- **Stereo waveform canvas,** normalized to each song's peak, with ruler, marker flags and loop band.
- **Zoom:** slider, + and − keys, ⌘/Ctrl+scroll or pinch; horizontal scrollbar; follow-playhead.
- **Piano keyboard strip** (C1–C7) lighting up the notes at the playhead, following transpose. Click a key to hear it; toggle with the keyboard button.
- **Bigger-waveform view toggle**, which hides the panel, plus the Fullscreen API.

### 5.6 Audio tools
- **5-band EQ** with presets: Flat, Bass focus, Bass boost, Vocal focus, Guitar/keys, Drums & cymbals, Treble focus.
- **Pan / channel:** Stereo, Mono, Left only, Right only, Karaoke (center cancel).
- **Volume slider.**

### 5.7 Library
- **Song list:** the demo is pinned; title editing and deletion (with undo).
- **Storage meter** and persistence status.
- **Backup** to a ZIP containing audio, metadata, loops and markers, and **restore** from a ZIP, which merges, skips duplicates and repairs lost audio.
- **Memory cache** of the 3 most recently used decoded songs.

### 5.8 Export
- **Implemented:** library backup ZIP only.
- **Not implemented:** export of processed (slowed or pitch-shifted) audio, which is planned for Pro.

### 5.9 Keyboard shortcuts [Code]
| Key | Action |
|---|---|
| Space | Play / stop (returns to the start point) |
| Enter | Stop; press again for loop or song start |
| ← / → | −5 s / +5 s |
| Alt+← / Alt+→ | Previous / next marker |
| Home / End | Song start / last marker |
| Shift+↑ / Shift+↓ | Speed ±5% |
| L | Loop start, then loop end |
| Shift+L | Loop on/off |
| A or I / O | Set loop start / end at the playhead |
| T | Full speed ↔ practice speed |
| S / M / B | Add a section / marker / beat |
| + / − | Zoom in / out |
| ⌘Z / Ctrl+Z; ⇧⌘Z / Ctrl+Y | Undo / redo |

Shortcuts are paused while typing in fields or while a form dialog is open.

### 5.10 Mobile and touch [Code][Tested]
- **Phones** (≤600 px):
  - a three-row toolbar of 44 px buttons
  - a smaller waveform (≤26% of the viewport height)
  - large "+ Marker" and "Loop start/Loop end" buttons
  - a bottom-sheet tool panel
  - a first-visit tip
  - the tab-capture button hidden
- **Tablets and other touch screens** (>600 px, `pointer: coarse`): 46 px toolbar buttons.
- **iOS audio handling:** a silent-audio unlock and `audioSession` set to playback.
- **Home Screen install** via the manifest; no offline support (no service worker).

### 5.11 Other
- Feedback form and Pro waitlist (Netlify Forms)
- Help tab: recording how-to, shortcuts, sound check (test beep, engine status) and links
- "Support" tip link (Venmo)
- SEO guide pages: `/alternatives/`, `/free-transcribe-alternative/`, `/slow-down-youtube-without-changing-pitch/`, `/learn-songs-by-ear/`
- Legal pages: `/terms/`, `/privacy/`
- Sitemap, robots.txt, Open Graph image and structured data

### 5.12 Experimental, incomplete or planned
| Item | Status |
|---|---|
| Native macOS/iOS app (`SlowDownBuddy/`) | Source exists, uses ScreenCaptureKit/ReplayKit capture and an AVAudioEngine time-pitch unit; **never compiled or tested**; behind the web app in features |
| Export processed audio | Planned (Pro) |
| Chord detection | Planned (Pro); a note-level analysis exists for the keyboard view |
| Automatic bar/beat detection | Not implemented (the demo's markers were computed offline and hard-coded) |
| Stem separation | Not implemented (waitlist option) |
| YouTube link mode | Not implemented (waitlist option) |
| Sync between devices | Not implemented |
| Offline/PWA service worker | Not implemented |

---

## 6. Competitor differentiation

Competitor details below come from public sources reviewed during development (Oct 2026) and general knowledge. **All of them need re-checking before you publish claims [Verify].**

| Product | Model / platforms (as researched) | Notable strengths |
|---|---|---|
| **Transcribe!** (Seventh String) | One-time license, about $39 per seventhstring.com; Windows, macOS, Linux desktop | Long-established; video; spectrum/note analysis; manual section, measure and beat markers with tap-in; tempo computation over a selection |
| **Amazing Slow Downer** (Roni Music) | Paid apps per platform (iOS, Android, Mac; Windows availability unclear); a free Lite version plays part of each song | Long-established; on iOS plays from the music library (including Apple Music per its listing) |
| **Capo** (SuperMegaUltraGroovy) | Yearly subscription; Mac and iOS | Automatic beat/downbeat (bar) detection and chord detection |
| **Moises** | Free tier plus subscription; web, mobile and desktop; account required | AI stem separation; chord and tempo detection |
| **Anytune** | Apple platforms; free download with paid upgrades (unverified) | Practice tools for Apple devices |
| **Soundslice** | Web-based; interactive notation and tab synced to recordings or video; slowdown and looping; paid plans **[Verify details]** | Notation-centric learning and teaching platform |
| **Transpose** (Chrome extension) | Freemium | Changes pitch, speed and loops inside YouTube and other pages, live in the page; doesn't record |
| **Capo** (Firefox add-on, a different product), LoopTube, Tune Transcriber | Free / browser | YouTube-link or in-page slowdown and looping |

**Differentiators that look genuine for Slow Down Buddy:**
1. **Recording audio from another browser tab directly into a persistent local practice library,** with no extension, download or converter. It takes three actions: Record → pick the tab → Stop. In-page extensions don't keep the audio; desktop apps require obtaining files. **No equivalent was found in the products reviewed, but don't claim exclusivity without a broader search [Verify].**
2. **Free, with no account, on every platform** through one URL, including iPhone/iPad and Android.
3. **Privacy:** audio never uploaded, in contrast with cloud and AI tools.
4. **Attack-preserving slow-down** at very low speeds, a measurable quality point that can be demonstrated.
5. **Format coverage on iOS:** FLAC, ALAC and Opus-in-M4A.

**Gaps compared with competitors:**
- automatic chords and bars (Capo, Moises)
- AI stems (Moises)
- notation sync (Soundslice)
- video display (Transcribe!)
- music-library playback on iOS (Amazing Slow Downer)
- offline desktop app
- cross-device sync

---

## 7. Monetization strategy

The owner is considering keeping the current app free and adding a one-time Pro purchase, possibly around $39.99, with no subscriptions.

### 7.1 Keep free
Keep everything that exists today free:
- import and recording
- slow-down and pitch
- loops and markers
- EQ and pan
- library, backup and restore

This is the acquisition engine. The traction to date (§11) came from these features, and removing any of them would undercut the "free" positioning used in marketing and on the guide pages.

### 7.2 Candidate Pro features
| Feature | User value | Effort | Running cost |
|---|---|---|---|
| **Export processed audio** (slowed or transposed, with loop range; WAV, plus AAC/Opus via WebCodecs) | High | **Low–moderate** (§7.4) | None (client-side) |
| **Chord names on the timeline** | High (2 of the first 2 waitlist signups) | **Moderate (basic) to high (good)** (§7.3) | None if client-side |
| Automatic bar/beat markers | High | Moderate–high; rubato is hard | None |
| Practice tools: speed trainer (auto-increase speed each loop), count-in, metronome, A/B loop repeat counts | Medium | Low | None |
| Multiple saved "sessions" or setlists, tags, search | Medium | Low | None |
| Cross-device sync | High | **High**: needs accounts, a backend and storage costs | Ongoing |
| AI stem separation | High | **High**: big models; slow on phones; server costs if server-side; model licensing | Possibly high |

### 7.3 Chord detection: technical complexity
- **Basic approach, all client-side:**
  - compute chroma (12-bin pitch-class energy) from FFT frames; `noteLevels()` already computes note energies
  - smooth over time
  - match against major, minor, 7th and similar templates, with an HMM or Viterbi pass for stable segments
  - optionally align to beats

  Expect decent results on clear pop/rock and weaker results on dense mixes, distortion or jazz voicings. About 1–3 weeks of focused work, plus tuning.
- **Higher accuracy:** a small neural model (CNN/CRNN) run with ONNX Runtime Web or TF.js. It adds model size (often several MB), inference time on phones, and **model and dataset licensing review [Verify]**. Several popular chord models and datasets are non-commercial.
- **UX:** a chord lane above the waveform, editable chord labels, chords stored with markers, and transposition-aware display. Users forgive errors if they can correct them easily.

### 7.4 Exporting processed audio: technical complexity
- The engine already renders correctly in an `OfflineAudioContext`. This was done repeatedly during development testing, including the attack warp [Tested]. Export would:
  1. Build an offline graph: Signalsmith node (same speed, semitones, cents, channel mode, warp) → EQ → gain.
  2. Render the loop or the whole song.
  3. Encode it:
     - **WAV:** trivial, no dependencies
     - **AAC/Opus:** via WebCodecs `AudioEncoder` where available (Chromium; Safari support varies **[Verify]**)
     - **MP3:** would need an LGPL encoder (§2.5)
- **Constraints:**
  - **Memory:** a 5-minute song slowed to 50% gives 10 minutes of float audio (about 200 MB stereo before encoding). Long renders on phones need chunked rendering, or limits.
  - **Delivery:** use a download for the file, and the share sheet on iOS.
- **Effort:** about 3–7 days for a solid WAV export plus loop-only and whole-song options.
- **Copyright consideration:** see §3.4.

### 7.5 Licensing and activation without accounts
- **Recommended approach:** a merchant of record (for example Lemon Squeezy, Paddle or Gumroad) issues a **license key**. The app validates it once through the vendor's license API and stores a signed token in localStorage or IndexedDB, re-checking occasionally with an offline grace period. No accounts or backend of your own are needed **[Verify vendor APIs and fees]**.
- **Hardening:** an Ed25519-signed offline license file, verified in the app with a public key, avoids vendor calls entirely.
- **Reality check:** any client-side check in a JavaScript app can be bypassed by a determined user. Keep friction low: a single key entry per device, a generous device limit, and backups that include the license. Gate features in code paths, not just the UI, but don't over-invest.
- **Cross-device:** a key can be entered on each device (decide the device limit). Sync would require accounts.
- **Tax:** a merchant of record handles sales tax and VAT.

### 7.6 A future iOS app and shared licenses [Verify current Apple rules]
- **In-app purchase rule:** App Review Guideline 3.1.1 generally requires in-app purchase to unlock digital features inside iOS apps.
- **Multiplatform exception:** Guideline 3.1.3(b) lets an app give access to content or features bought elsewhere, **if** those items are also available to buy in-app.
- **US storefront changes:** after the 2025 court ruling (Epic v. Apple), external purchase links and buttons are allowed in the US storefront. Rules differ by region, including EU DMA alternatives.
- **Practical paths:**
  - offer Pro via IAP in the iOS app and also honor web-purchased keys under 3.1.3(b), which in practice requires some account or restore mechanism; or
  - keep iOS as the free web app (Home Screen web apps aren't subject to App Store rules) and sell Pro on the web only.
- **Apple's commission:** 15% under the Small Business Program for IAP **[Verify]**.

### 7.7 Price point
- **$39.99 is in line with Transcribe!** (about $39 one-time) and above Amazing Slow Downer's mobile price points.
- **Considerations:**
  - For a browser app, a lower launch price ($19.99–$29.99, with early-bird pricing for the waitlist) may convert better. Test it.
  - One-time pricing fits the zero-running-cost architecture.
  - Avoid features with recurring server costs (stems, sync) in a one-time tier, or price them separately.

---

## 8. Performance and reliability

### 8.1 CPU
- **Waveform drawing (improved, `98923e6`):** the static waveform layer is cached, and only the playhead is drawn per frame. Measured: 0.93 → 0.11 ms per frame on desktop, and 1.9 → 0.21 ms on an iPhone-sized page at 4× CPU slowdown.
- **The ruler (`drawRuler`) is still fully redrawn each frame:** about 0.35 ms on desktop and 1.5 ms at 4× slowdown. It could be cached the same way; its flag hit-boxes would need preserving.
- **Keyboard analysis:** a 32,768-point FFT in JavaScript about every 180 ms while the keyboard is visible. Moderate on desktop, more noticeable on low-end phones. It could use a smaller FFT, a Web Worker, or run only when paused.
- **One-time costs per song load, on the main thread:**
  - onset detection (chunked with `setTimeout` yields)
  - peak computation
  - fallback decoders (WASM, chunked)
- **AudioWorklet:** Signalsmith at its default quality is efficient (WASM). The WSOLA fallback runs on the main thread (`ScriptProcessorNode`) and can glitch under UI load.

### 8.2 Memory (estimates from code, at 44.1 kHz stereo) [Code]
Per loaded song:
| Item | Size |
|---|---|
| Decoded `AudioBuffer` (2 channels × float32) | ≈ 0.35 MB per second |
| Mono mix buffer, always created | ≈ 0.18 MB/s |
| "Karaoke" derived buffer, when used | ≈ 0.18 MB/s |
| Buffers posted to the AudioWorklet via `addBuffers` (structured clone, so the worklet holds its own copy) | ≈ 0.35 MB/s |
| Peaks and onset arrays | small |

- **Per song:** a 5-minute song is roughly 250–300 MB in total while loaded.
- **Cache (fixed, `378bf2c`, `49ac8d4`):** up to 3 decoded songs are cached on desktop, and **1 on phones and tablets (plus the demo)**.
- **Undo history no longer keeps decoded audio:** it used to pin every imported song in memory for the whole session.
- **Measured:** renderer growth after three 5-minute imports was about 400 MB on desktop and about 300 MB in phone emulation, down from about 500 MB.
- **Risk:** long recordings (20–60 minutes) or large WAV files can exceed mobile Safari's per-tab memory limits and crash or reload the page **[Verify on devices]**.
- **Remaining mitigations, not done because they need larger changes:**
  - **Transfer buffers to the worklet:** this would detach the main-thread copy that the waveform, keyboard view, attack detection and fallback engine still use.
  - **Derive the mono or karaoke signal in the worklet.**
  - **Stream long files** instead of decoding them whole.
- **Recordings:** `MediaRecorder` chunks accumulate in memory until stop. They are compressed (256 kbps ≈ 115 MB per hour), so this is OK, but a crash loses the whole recording. Writing chunks to IndexedDB periodically would make it resilient.

### 8.3 Large libraries
- **IndexedDB holds compressed originals** (efficient). Quota is browser-dependent.
- **The song list is a simple DOM list,** fine for hundreds of songs.
- **Backups:** the ZIP is built in memory, so very large libraries could exceed memory on phones.

### 8.4 Glitches, sync and browser limits
- **Playhead:** estimated from schedule segments on the main thread. During attack-warped playback, the audio near an onset can be up to about 45 ms (input time) off the visual playhead between attacks, by design, and is exact at the attack itself.
- **iOS:**
  - AudioContext suspension needs auto-resume (implemented)
  - silent-switch and route changes
  - Safari's high-quality-engine silence was observed early, and handled with an automatic fallback
- **Tab-capture start-up:** the first fraction of a second can be clipped while the user picks a tab.
- **Speed/pitch changes during playback** re-schedule the worklet; brief artifacts are possible.
- **`ScriptProcessorNode` is deprecated** and could be removed by browsers.

### 8.5 Waveform rendering
Peaks are pre-computed once. The waveform layer is cached and redrawn only when the view, loop, markers or song change (§8.1).

### 8.6 Improvements without sacrificing quality
- Cache the ruler layer too (the waveform is done).
- Move the FFT work (keyboard view, onsets, chords later) into a Web Worker.
- Transfer buffers to the worklet, and drop the duplicate copies.
- A service worker for offline use and faster repeat loads.
- Shrink `demo.mp3` (6.5 MB at 320 kbps) for faster first loads on phones, possibly a shorter excerpt or 160–192 kbps.
- Incremental save of long recordings.

---

## 9. UI/UX review

**Basis:** code inspection [Code], plus renderings in headless Chromium with device emulation during development [Tested]. Real-device usability testing is still needed.

### 9.1 Organization
- **Desktop:** a single toolbar; then the marker ruler, waveform, scrollbar and keyboard strip; then the controls (zoom and volume, time and loop boxes, transport, speed, transpose and fine-tune); then a tabbed panel ("Library & loops", EQ, Pan, Shortcuts).
- **Phones:** a three-row toolbar, then the waveform and keyboard, then large transport and quick buttons; the panel opens as a bottom sheet.
- **Library & loops:** a three-column layout on wide screens (songs, loops, markers), two columns at mid widths, stacked on phones.

### 9.2 Responsiveness [Tested]
- **Phones:** iPhone SE, 14 and 15 Pro, and Pixel 7 sizes fit without horizontal scrolling after recent changes. The waveform is deliberately small on phones.
- **Tablets:** two toolbar rows with larger buttons.
- **Not tested on real devices or in landscape phone orientation [Verify].**

### 9.3 Accessibility [Code]
- **Positives:**
  - most icon buttons have `aria-label` and `title`
  - focus-visible outlines
  - the dialogs are native `<dialog>` elements
  - `role="status"` on the toast
- **Gaps:**
  - The waveform, ruler and keyboard are `<canvas>` with no text alternative or keyboard-accessible equivalent for loops and markers; the marker and loop lists help partially.
  - Color is used for state: green/pink/purple time boxes and orange active states. Check contrast, for example the muted grey text [Verify with tooling].
  - Small text in places (12 px hints).
  - Drag interactions without non-drag alternatives in some cases (typed loop times exist).
  - No reduced-motion considerations; minor.

### 9.4 Discoverability
- **Strong:** the first-visit tip on phones, the Help tab's "Record audio from any website" section, and tooltips.
- **Weak:**
  - **Improved (`f121b8d`): the headline feature, tab recording,** now shows a "Record a website" label on desktop screens ≥1400 px wide with a mouse. Below that, and on touch devices, it is still an icon, with a tooltip on desktop. It is hidden on phones and tablets, where browsers can't capture tabs.
  - Keyboard shortcuts are only listed in the Shortcuts tab.
  - The attack-preserving engine and the HQ toggle are invisible, which is fine.
  - The Pro waitlist is in small text in the Library tab.

### 9.5 Potentially confusing controls
- **Pause button:** behaves like "stop and return to start point". There is no true pause/resume-in-place, a deliberate owner decision that may surprise some users.
- **Loop keys:** L (start/end), Shift+L (toggle), A/I/O and the [AB] button overlap.
- **Two sets of navigation buttons:** previous/next marker and start/last marker, with similar icons.
- **Time boxes:** the yellow, pink and purple boxes mean position, loop start and loop end; their meaning isn't labeled.
- **"Example" demo song:** pinned and not deletable. **Fixed:** changes made to it are now saved between visits (`378bf2c`). There is no "reset demo" button yet.
- **Storage warnings:** reworded to "Safari may delete this if you don't open the app for 7 days", with practical advice (Home Screen, backup) and the last backup date.

### 9.6 Similarity to desktop transcription software
The overall arrangement closely follows Transcribe!: toolbar, marker flags strip, stereo waveform, keyboard strip, round transport buttons and grey "studio" styling. This was deliberate [Owner], and a user publicly noticed the resemblance. Trade-dress considerations are in §2.6.

### 9.7 Differentiating visually without losing usability
- **Keep the familiar layout,** which lowers learning cost for Transcribe! users, but change the visual identity:
  - the brand palette (charcoal and orange)
  - a distinct marker and loop styling
  - a different transport style
  - a branded waveform color scheme
  - a logo in the toolbar
- **Emphasize the unique flow with a "Record a website" call to action** on the empty state and the desktop toolbar.

---

## 10. Questions the developer should answer (not answerable from code)

1. **Who exactly is the target user,** and which matters most? Hobbyist learners, working musicians, students, or teachers who assign material; and which instruments?
2. **What is the business goal over 12 months:** side income, a full-time product, or a portfolio piece? What monthly revenue would count as success?
3. **Pricing model:** why $39.99 one-time? Would you consider a lower launch price, education or teacher licenses, or a "Pro+" tier for features with server costs (stems, sync)?
4. **Is the repository public or private,** and do you plan to open-source any part of the app?
5. **Native apps:** do you intend to ship the native Mac and iOS apps, accepting App Store review, in-app purchase rules and Guideline 5.2.3 risk, or stay web-only?
6. **Legal posture:** have you consulted an attorney on the tab-recording feature, the Terms/Privacy pages, AI-assisted code ownership and trade dress? Which jurisdictions will you sell in (US only, or the EU/UK)?
7. **How much data loss risk is acceptable?** Would you add accounts or cloud backup and sync later, given the cost and privacy trade-offs?
8. **Marketing:** are you comfortable continuing to name YouTube and Spotify in promotional copy, or should messaging shift to "record what's playing" and practice?
9. **Support capacity:** how will you handle support, refunds and license issues for paid users? Is there a support email?
10. **Roadmap priorities after export and chords:** bar/beat detection, practice tools (speed trainer), notation or tab, or video?

---

## 11. Development and traction context [Owner]

This context was supplied by the developer during development; it is not verifiable from code.

- **Launched October 2026** on Netlify with the custom domain slowdownbuddy.com.
  - The Netlify team once ran out of credits, pausing the site; the owner bought more.
  - Pushes that don't change `deploy/` now skip builds.
- **First days of promotion** (Facebook personal post and a bass group, r/BassLessons, r/SideProject):
  - about **187 visits** in the first ~2 days
  - about 65% of visitors on phones (54% iOS)
  - Facebook was the top source
  - a few organic Google visits
- **r/BassLessons post:** about 2.3K views and 13 upvotes.
- **Moderation:** r/Bass mods were asked for permission after an automated "No Sales" flag. r/guitarlessons prohibits self-built apps.
- **Feature use observed** (GoatCounter events): imports (MP3, WAV, M4A, FLAC), website recordings, mic recording, backup, and feedback and waitlist opens.
- **Pro waitlist:** 2 signups. Requested features: export (1), chords (2), stems (1).
- **User feedback:**
  - "Looks like Transcribe" (a musician)
  - "Use a DAW / Moises instead" (a Facebook commenter)
  - an Android user who hit the tab-capture error (since hidden on mobile)
  - the owner's own iPhone files becoming unreadable (fixed)

---

## Appendix A: Files reviewed

- `deploy/index.html`: the app, including the inlined Signalsmith Stretch, the Engine, UI, storage, capture, backup/restore and analytics hooks
- `deploy/m4a-decoder.js`, `deploy/flac-decoder.min.js`, `deploy/opus-decoder.min.js`
- `deploy/THIRD-PARTY-NOTICES.txt`, `deploy/_headers`, `netlify.toml`, `deploy/manifest.webmanifest`, `deploy/robots.txt`, `deploy/sitemap.xml`
- `deploy/terms/`, `deploy/privacy/` and the guide pages under `deploy/*/`
- `SlowDownBuddy/` (Swift sources, `project.yml`), `.github/workflows/slowdownbuddy-build.yml`
- `branding/`, `CLAUDE.md`, `.gitignore`, and the stray root files listed in §2.4 (now removed)
- Added on Oct 30: `deploy/licenses/` (license texts, source packages, page), `deploy/vendor/goatcounter-count.js`

## Appendix B: Checklist status (updated October 30, 2026)

1. **Done:** complete notices and license texts, source URLs and hashes. The exact libFLAC/libopus versions aren't stated upstream.
2. **Done for the current tree:** stray files removed. **Owner decision needed:** rewrite the public repository's history to purge them.
3. **Done:** GoatCounter script self-hosted and pinned; Content-Security-Policy added.
4. **Done:** "Claude preview" message reworded.
5. **Done:** restores rebuilt from allow-listed, validated fields; ZIP reader bounds-checked.
6. **Done:** "Record a website" label on wide desktop screens.
7. **Partly done:** waveform layer cached. The ruler cache and moving FFT work to a Web Worker remain.
8. **Partly done:** 1-song cache on phones; undo no longer keeps decoded audio. Transferring buffers to the worklet remains (larger change).
9. **Open:** service worker for offline use.
10. **Open (owner/counsel):** review the Terms, Privacy, LGPL compliance for `codec-parser`, recording-feature marketing and trade dress before launching Pro.
