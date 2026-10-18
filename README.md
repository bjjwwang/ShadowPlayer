# Shadowing Player

A small native macOS app for practising English with local video and an interactive SRT transcript. Video is rendered above the transcript; imported subtitles are never overlaid on the video. Local-file mode requires no packages, accounts, services, database, or network access. Optional YouTube mode fetches public videos and existing English captions into a temporary local cache, then uses the same native player. Optional one-click English lessons use your existing local Codex ChatGPT login.

## Copy to another Mac (standalone version)

Use `dist/ShadowingPlayer-1.3.1-universal.zip`: copy it to another Mac, extract it, and open **Shadowing Player.app**. You can move the app to Applications or keep it in any writable folder. Requires macOS 14 or later. The app and both bundled tools contain **arm64 and x86_64** executable slices for Apple Silicon and Intel. No Homebrew, Python, Node, Deno, yt-dlp, FFmpeg, Swift, or Xcode installation is required for playback on the receiving computer. YouTube import still needs internet access. English lessons additionally require Codex installed and signed in on that Mac; another computer's login is never included in the app.

The standalone bundle includes the official yt-dlp macOS executable (with Python and EJS included) and a universal Deno runtime. It exclusively uses those bundled tools, never silently falls back to Homebrew/user tools. Audio/video merging uses AVFoundation passthrough export, so FFmpeg is not needed. Tool versions, upstream release URLs, checked SHA-256 digests, and third-party license notices are included under `Contents/Resources`.

This is an **ad-hoc signed test build, not Apple-notarized**: no Developer ID certificate is installed on this machine. On a receiving Mac, Gatekeeper can prompt or block the first launch. Follow Apple's [instructions for opening an app from an unidentified developer](https://support.apple.com/en-ie/102445) if you choose to run this test build. A standard Developer ID signature and Apple notarization are needed for normal verified distribution. The build does not change Gatekeeper or system security settings.

Rebuild the portable package from source:

```sh
./scripts/build-standalone.sh
```

The script downloads pinned upstream binaries, verifies their SHA-256 digests, builds both app architectures, embeds and signs the tools, validates the universal slices, and produces a ZIP plus its checksum. It uses only Command Line Tools and Python's standard library. The ordinary `build-app.sh` remains a small developer build and can use locally installed retrieval tools.

## Build and run

Requires macOS 14 or later and Swift 6.2 or later (Xcode 26 or current Command Line Tools). Built and tested here with Swift 6.3.2 on macOS 26.5.1, Apple Silicon.

With Xcode installed:

1. Open `ShadowingPlayer.xcodeproj`.
2. Select the **ShadowingPlayer** scheme and **My Mac** destination.
3. Run with **⌘R**. Run the core tests with **⌘U**.

The project uses local ad-hoc signing and does not need an Apple developer account. Its deployment target is macOS 14. Source uses Swift's isolated deinitializers, requiring Swift 6.2 or newer.

With Command Line Tools only, from this directory:

```sh
./scripts/build-app.sh
open "build/Shadowing Player.app"
```

This builds the optimized executable through Swift Package Manager, creates a normal `.app` bundle, and signs it locally. `swift build` also builds the executable for development. To build with Xcode from Terminal:

```sh
xcodebuild -project ShadowingPlayer.xcodeproj -scheme ShadowingPlayer \
  -configuration Debug -derivedDataPath build/xcode build
```

## YouTube mode

Click **YouTube…** in the toolbar, paste a public YouTube watch/Shorts/youtu.be link, then choose **Load & practise**. The app automatically selects creator-provided English captions, falling back to YouTube automatic English captions. It retrieves the captions and caches a compatible MP4, then opens both together in the native player. All existing sentence, A–B, speed, offset, and five-second arrow shortcuts work unchanged. The subtitle offset resets to zero for each YouTube import. The transcript indicates the caption source.

YouTube mode uses **yt-dlp** plus a supported JavaScript runtime. The standalone app bundles both; the following setup is only for developer builds. Developer tools are discovered in `~/.local/bin`, Homebrew directories, and PATH. Swift source has no added package dependency. This machine was set up with `uv tool install 'yt-dlp[default]'` and uses its existing Node installation. On another machine, choose one setup method:

```sh
# If uv is installed:
uv tool install 'yt-dlp[default]'
# Also install Node 22+ or Deno 2.3+ if neither is installed.

# Or with Homebrew:
brew install yt-dlp deno
```

AVFoundation merges separate H.264 video (up to 720p) and AAC audio into MP4 without re-encoding; a compatible combined MP4 is also accepted. FFmpeg is not required. yt-dlp's official [setup documentation](https://github.com/yt-dlp/yt-dlp/wiki/EJS) describes the runtime requirements for developer builds. For standalone builds, rebuild the package to update the pinned retrieval tools when YouTube changes.

Loading needs an internet connection and can take minutes. The modal shows the current stage and offers cancellation. A failed or cancelled import leaves your existing practice session intact. Opening another local video or transcript while retrieval is pending prevents the pending import from replacing it. Imported temporary files are removed when you replace the video or normally quit. There is no persistent media library; a crash can leave temporary files for macOS to clean up.

Only accessible public/unlisted recorded videos are supported. No login/cookies are used, no missing captions are generated, and no translation is requested. Videos with no compatible English captions, live streams, sign-in restrictions, unavailable formats, network errors, and rate limits produce a message. YouTube can restrict retrieval even when a video plays in a browser; success for every link is not guaranteed. The official [caption download API](https://developers.google.com/youtube/v3/docs/captions/download) requires video editing permission, so it cannot supply arbitrary public-video captions for this app.

## One-click English lessons with local Codex

Click **学习** beside any subtitle, or **学习当前句** in the toolbar. Playback pauses and a native panel teaches listening first: what information to catch, meaning groups with English/Chinese pairs, specific likely pronunciation changes and listening traps, and a replay/shadowing drill. A short grammar explanation, useful expressions, substitution practice, and a self-test follow. Pronunciation guidance explicitly describes possible readings inferred from text; it does not claim to analyze the recording.

Choose **这句话** or **附近几句**. Apple's built-in NaturalLanguage sentence tokenizer locates the sentence containing the selected cue's first word, even when its beginning/end falls inside another cue. For example, a final cue containing `budget cuts that caused them. France is` is cut after `them.` in sentence mode. Nearby mode includes up to one sentence before and after. Analysis is bounded to two adjacent cues on either side (three in nearby mode), with gap/duration and text-size limits; missing punctuation or a longer sentence can leave a fragment. No third-party NLP dependency is added. Successful lessons persist locally for reuse after relaunch. Original subtitle text/timestamps stay unchanged; study playback derives a separate combined interval.

The study panel's **播放整句** and **循环整句** play the entire displayed study selection across cues, with pause/resume and the same speed controls. Playback works while a lesson is loading or Codex is unavailable. The existing AVPlayer, serialized seeks, boundary observation, offset, and padding are reused. Whole-cue edges retain original timestamps. For a sentence boundary inside a cue, timing is **estimated by its text position**, not measured word alignment; the panel labels this and exposes start/end (subtitle seconds) plus padding under **调整播放范围**. Closing the panel stops study playback. Replacing video/transcript invalidates the playback snapshot, preventing an old lesson from playing against new media.

The toolbar shows the detected Codex login state. Install the Codex desktop app or CLI and sign in **with ChatGPT** on this Mac, then click **刷新登录状态**. If using the CLI, run `codex login`. API-key authentication is intentionally unsupported for this feature. Common desktop app locations, `~/.local/bin`, Homebrew, and PATH are searched; this version was verified with Codex CLI **0.163.0**. Update Codex if its local interface is incompatible.

The app queries Codex's advertised model list instead of assuming a model is available. It defaults to an available lightweight Luna/mini/nano model (GPT-6-Luna on the development account), using its lowest advertised minimal/low effort. You may explicitly select another listed model. If no lightweight model is available, choose one yourself; the app does not silently substitute a larger model.

Login and models are read through the official [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server). Lessons use [Codex non-interactive execution](https://learn.chatgpt.com/docs/non-interactive-mode) with a strict JSON response schema, a temporary working directory, ephemeral sessions, read-only execution, disabled shell/apps/plugins/web search, and ignored user rules/configuration. The player invokes Codex directly using literal arguments, reads no credential files, copies no credentials, and does not change your Codex configuration. Only the selected subtitle excerpt is supplied as learning material; video and audio are not uploaded by this feature. Temporary lesson files are removed after each request. Closing the panel or clicking Cancel stops the owned request; late responses cannot replace a newer selection.

Generating a new lesson **requires internet and available Codex account quota/model access**; being signed in alone does not guarantee availability. Reading an already learned lesson requires neither login nor another model request. Explanations can be wrong, and pronunciation suggestions are based on written text rather than listening to your audio. Local playback, subtitles, and loops continue to work without Codex.

Lessons are saved as atomic JSON files in `~/Library/Application Support/Shadowing Player/Lessons/`. Keys use SHA-256 of the normalized excerpt (canonical Unicode and whitespace), so revisiting the same text, adjusting timing, changing models, or encountering it in another video reuses the result. The actual generating model is retained for display/export. New surrounding text creates a different study excerpt. Model/prompt changes do not silently invalidate learned material; **重新生成（耗额度）** is the explicit way to replace a cached lesson. Repeated clicks during the same pending request are coalesced. An unreadable cache produces an error instead of silently paying for a replacement; failed writes retain the current result in memory and offer a local save retry. Cache files have no automatic expiry and contain no credentials. They stay outside the app bundle/Git repository and may be copied separately to migrate learned lessons. Results lost on quitting the older memory-only versions cannot be recovered automatically.

## Save a lesson to Obsidian

If this Mac has configured Obsidian vaults, **存入 Obsidian** saves the original text, source link, subtitle/playback range, model name, and all lesson sections as a new Markdown note under that vault's `Shadowing Player/` folder. Open vaults are preferred, then the most recently used; a picker appears for multiple vaults. Saving keeps the study panel open for listening. Repeated clicks on the same saved lesson are disabled; existing files are never overwritten. **在 Obsidian 打开** uses Obsidian's official [open URI](https://obsidian.md/help/uri).

Every saved note requires an associated video and includes its original link plus an `HH:MM:SS.mmm → HH:MM:SS.mmm` timeline. YouTube notes also contain a start-at-time link (rounded down to the preceding whole second), preserving the video ID and replacing old start parameters. This follows YouTube's [start-at sharing](https://support.google.com/youtube/answer/57741?hl=en) behavior. The timeline uses the adjusted playback interval when available, otherwise the subtitle interval. Local files retain a file link and the written timeline; clicking a local file link does not seek automatically. Reusing a cached explanation always exports the current video's link/timing and the cached result's actual model.

No Obsidian plugin, CLI, account, server, or API key is needed. Detection reads `~/Library/Application Support/obsidian/obsidian.json` and validates the vault's `.obsidian` directory. No configured vault means the save button is disabled; refresh after configuring one. Only clicking Save creates a note. The app neither creates vaults nor modifies existing notes/settings. Exported local-video links refer to that Mac's file path; YouTube exports retain the original watch URL instead of a disposable cache path. Audio/video files are not copied into notes.

## Use

1. **Open Video…** (`⌘O`): choose a local MP4/MOV or another system-supported video. Video starts paused.
2. **Import SRT…** (`⇧⌘O`): choose a UTF-8 SRT file. Importing subtitles before the video also works. `Samples/practice.srt` includes multiline, adjacent, overlapping, and separated entries; use your own matching subtitles for actual speech practice.
3. Click a transcript entry to select it and seek to its original start plus the global offset. This preserves the current play/pause intent.
4. Use **Play sentence** to practise the selection (or current active entry). **Repeat** loops it; uncheck Repeat to play it once and pause at its end. **R** starts repeated sentence practice regardless of the checkbox.
5. Mark **A**, seek or play ahead, then mark **B**. **Loop A–B** enables/disables looping; **Replay A–B** starts the interval in loop mode. Any positive interval length is allowed.
6. Choose 0.75×, 1.0×, or 1.25× playback. **Offset (s)** accepts positive or negative seconds; its stepper adjusts by 50 ms. Positive offsets delay subtitles. Padding adds 0–300 ms to each side of a sentence, bounded by video duration.
7. The transcript automatically follows the active subtitle. Manual scrolling pauses follow temporarily; it resumes automatically after two seconds without scrolling. Starting playback or sentence/A–B practice also restores follow. Click **Following** only if you deliberately want to disable it. Drag the divider to change panel proportions.

Seeking with the slider, arrow keys, or transcript exits active practice mode. Selection and valid A–B markers remain available. Esc exits practice mode while allowing normal playback to continue. Replacing the video resets transport, selection, practice mode, and A–B markers; imported subtitles, offset, padding, and chosen speed remain available.

| Shortcut | Action |
| --- | --- |
| Space | Play / pause |
| Left / Right | Seek backward / forward 5 seconds |
| Up / Down | Select previous / next subtitle |
| R | Repeat selected or active subtitle |
| A / B | Mark A–B start / end at current video time |
| L | Toggle A–B loop |
| Esc | Exit active practice mode |
| ⌘O / ⇧⌘O | Open video / import SRT |

Click the video or a transcript row to focus playback. Player shortcuts leave text editing controls alone. The toolbar's **?** button contains the same help.

## Architecture and timing

- `Sources/ShadowingCore/Subtitle.swift`: UTF-8 text parser and indexed timeline. Source timestamps remain unmodified. IDs are unique source-block ordinals, so duplicate SRT numbering is harmless. Entries are sorted by start time and ID; malformed blocks are counted and skipped. Empty imports display a useful empty state. Multiline text is preserved.
- `Sources/ShadowingCore/PlaybackInterval.swift`: pure interval validation and bounded offset/padding calculations shared by sentence and A–B practice.
- `Sources/ShadowingPlayer/PlayerController.swift`: one main-actor playback owner. AVPlayer's actual media time is the only clock. A 40 ms periodic observer updates progress and highlighting; an AVPlayer boundary observer plus the periodic fallback detects interval ends. Source lookup uses `videoTime - offset`. Changing subtitle offset immediately refreshes highlighting and updates sentence practice boundaries; A–B markers are unaffected.
- `MainContentView.swift`: native `AVPlayerLayer`, transport controls, a resizable split view, and a lazy transcript. Embedded legible tracks are deselected. Active entries have a filled highlight; independently selected entries have an outline. Auto-follow reacts to active-entry changes, without animation.
- `Sources/ShadowingCore/YouTube.swift`: canonical video-link validation, creator/automatic English caption selection, and JSON3 timing parsing. Multiline text is kept; appended events are merged. For automatic captions only, lingering display overlaps are clipped at the next utterance start to make shorter practice segments. Original SRT and manual caption times remain unchanged.
- `YouTubeLoader.swift` / `YouTubeImportView.swift`: bundled tool discovery, native AVFoundation remuxing, and cancellable staged retrieval through yt-dlp with literal Process arguments (no shell), explicit source-pair handoff, and temporary cache ownership. Personal yt-dlp config and plugins are disabled.
- `InputMonitors.swift`: window-scoped keyboard and manual transcript scroll handling. Local event monitors are removed when their views are dismantled.
- `EnglishStudy.swift`: pure bounded sentence/context selection, structured lesson schema, and lightweight model selection. `CodexStudy.swift` owns cancellable local Codex subprocesses and looks up learned material before authentication/model generation. `LessonCache.swift` stores atomic, content-keyed JSON using Apple's CryptoKit. `EnglishStudyView.swift` displays login/cache state, scope/model choices, and lessons separately from video.
- `StudyNote.swift` formats Markdown and safe unique filenames. `ObsidianExport.swift` discovers configured vaults, writes new notes without replacing files, and opens saved notes through the URI protocol. Study playback is another practice mode in `PlayerController`, sharing the existing interval/seek lifecycle.

Subtitle ranges are half-open: **[start, end)**. At adjacent boundaries the next entry is active; gaps have no active entry. For overlaps, the latest start wins, with highest ID breaking equal-start ties. If that entry ends while an earlier entry still covers the time, lookup returns the earlier entry. Binary search and a prefix maximum end index make normal lookups efficient; pathological overlaps can require a backward scan.

All seeks use zero tolerances and are serialized. While a seek is in flight, new destinations replace one queued request; only the newest completed destination resumes playback. Playback intent and selected rate survive internal loop seeks. Item generations discard stale completion callbacks after video replacement. Boundary generations reject obsolete boundary callbacks. Periodic/boundary time observers, status observation, notification tokens, and scoped file access have explicit cleanup.

## Tests and verification

```sh
./scripts/test.sh
```

The original sixteen core tests cover millisecond parsing, BOM/CRLF and UTF-8, multiline entries, empty and malformed files, sorting and duplicate indices, adjacent/exact boundaries, gaps, overlaps, offsets, long timelines, padding/duration bounds, and A–B validation. The script accommodates the Swift Testing framework/runtime paths in the installed Command Line Tools; full Xcode uses normal SwiftPM discovery.

An optional integration test uses the actual AVPlayer with a local video at least three seconds long:

```sh
SHADOWING_TEST_VIDEO=/absolute/path/to/video.mp4 ./scripts/test.sh
```

It verifies import-before-video, coalesced rapid seeks (including repeated five-second steps with a sufficiently long fixture), offset highlighting, play-once boundaries, sentence and A–B wraparound, loops at the physical video end, normal playback ending, 1.25×/0.75× rate preservation, pause stability, seek exit behavior, and state reset on video replacement. Without that environment variable the local-player integration test is skipped. This test is also included in the Xcode test target.

YouTube tests cover accepted/rejected links, English track selection, restricted/live metadata, millisecond JSON3 parsing, appended/multiline text, automatic-caption overlap handling, literal subprocess arguments, error cleanup, and cancellation. An opt-in network integration test exercises the real importer, native playback, transcript seeking, and replacement-cache cleanup:

```sh
SHADOWING_TEST_YOUTUBE='https://www.youtube.com/watch?v=VIDEO_ID' ./scripts/test.sh
```

It downloads that video temporarily; normal test runs skip it. Network availability is separate from the offline unit tests.

Original MVP validation on this machine: debug and release app compilation succeeded; all **17 tests** passed with a generated 25-second H.264/AAC fixture. The bundled app was launched and inspected through its native UI. Full Xcode is not installed (only an installation placeholder), so `xcodebuild` could not run; project and Info.plist syntax were validated with `plutil`.

YouTube extension validation: all **28 tests** passed together with both integration options enabled. A public TED video was retrieved with creator-provided English captions, opened in AVPlayer, sought using its transcript, and played in sentence mode. Cache removal on video replacement was verified. These tests exercise an actual network import, not a simulated downloader. Additional standalone tests cover strict bundled-tool selection and native remux track/duration preservation.

The release app's YouTube dialog was also exercised through the native UI: import completed with 80 English entries, transcript selection and R started sentence practice, Space paused, and manual scrolling switched to Resume follow. One UI import received YouTube HTTP 403; retrying succeeded. That external retrieval limitation is surfaced in the dialog rather than silently replacing the current video.

Standalone 1.1 validation: both app architectures compiled; all **30 tests** passed with the local-video and real-YouTube integration tests enabled, using only the bundled yt-dlp/Deno directory. Native remuxing preserved one audio track, one video track, and duration within 50 ms on the fixture. Both bundled tools ran with a system-only PATH; their x86_64 slices also ran under Rosetta on this Apple Silicon Mac. The 112 MiB ZIP passed CRC checks and was extracted to a different path: app/helper signatures, both CPU slices, and absence of Homebrew/user-library linkage were verified. An isolated copy launched its native window. A physical second Mac was not available for testing.

Codex 1.2 validation: six new offline tests cover sentence reconstruction, punctuation/gap boundaries, nearby scope, excerpt bounds, quoted input, model/effort selection, and strict schema objects. A real opt-in integration test detected this Mac's ChatGPT login and obtained a structured lesson from GPT-6-Luna with low effort in about 6.5 seconds. The run contained 37 tests: 34 passed and three unrelated optional media integration tests were skipped. To exercise Codex yourself (uses your account quota and sends the fixed example sentence):

```sh
SHADOWING_TEST_CODEX=1 ./scripts/test.sh
```

Listening update 1.2.1: all 12 focused study tests passed, including a real GPT-6-Luna low-effort response with the new listening schema. Five additional regression cases cover the reported three-cue French-school example, sentence boundaries inside neighboring cues, selecting the next sentence later, abbreviations/decimals/quotes/questions, and multiple sentences inside one cue. The integration test now sends that fixed screenshot sentence, excluding `France is`, and checks listening chunks, pronunciation notes, and a practice drill. No new manual playback/UI verification is claimed for this update.

Study playback/Obsidian 1.3 validation: 48 tests were discovered; 46 passed with the local-video fixture enabled and the unrelated Codex/YouTube network tests skipped. Real AVPlayer tests exercised combined three-cue play-once and looping, rapid replay requests, rate/offset preservation, stop-during-seek, and stale-source rejection. Export tests used temporary fake vaults to verify discovery/order, complete Markdown, unique non-overwriting writes, invalid configs, escaped-folder rejection, and encoded open URLs. The actual configured vault was detected read-only; tests did not add notes there. Audio was muted during automated playback tests, so these do not measure audible sentence-cut accuracy.

Persistent cache/link update 1.3.1: 53 tests were discovered; 51 passed with local video enabled and the two network tests skipped. Injected generation counters verify one generation for rapid repeated clicks, disk reuse by a fresh unauthenticated controller, reuse despite model/timestamp changes, and generation only after explicit regeneration. Corrupt-cache and failed-write/save-retry cases also verify no automatic replacement requests. Note tests check current video/timing after explanation reuse, full timestamps, and replacement of old YouTube start parameters. This validation made no GPT requests.

## Known limitations

- Actual seek/render/audio behavior depends on AVFoundation, the codec, and the machine. Subtitle observation is approximately 40 ms and seeks may take time; frame-perfect presentation or sample-exact audio cuts are not claimed. Zero-tolerance seeks can briefly stall between repetitions.
- Developer builds require external local tools; the standalone app includes them. YouTube requires an internet connection for import; captions are platform-provided phrases, which may not be complete sentences. Automatic captions can contain recognition errors. Initial caching trades instant streaming for native seek and loop behavior.
- New English lessons require a compatible local Codex installation, ChatGPT login, network, and account quota; cached lessons can be reviewed offline. No login browser or credential storage is implemented in the player. Sentence detection is bounded and heuristic: missing punctuation or long sentences may yield fragments, and a cue with multiple sentences targets the one containing its first word. Audio is not analyzed; model explanations can be inaccurate.
- Study playback at a sentence boundary inside one subtitle uses proportional text timing; it can cut speech or include a little of the neighboring sentence. Adjust start/end and padding by ear. No word alignment or audio analysis is performed.
- Obsidian detection supports the standard macOS configuration location. Custom configuration/profile paths are not discovered automatically. Vault filesystem permissions must allow writing; no plugin or existing-note append integration is implemented.
- Supports UTF-8 SRT with standard `HH:MM:SS,mmm` timestamps. SRT styling/HTML is displayed as literal text; malformed or nonstandard entries are skipped. No subtitle editing or embedded subtitle import.
- Manual scrolling temporarily suspends follow and automatically resumes after two seconds of inactivity. The inactivity delay only controls UI scrolling; subtitle timing continues to come exclusively from AVPlayer.
- No saved playback sessions, bookmarks, or custom shortcut preferences. No custom app icon. The sample transcript is illustrative, not synchronized to a bundled spoken video.
- Physical-machine validation is on Apple Silicon and macOS 26.5.1. Intel slices are cross-compiled; an actual Intel Mac and older macOS versions were not exercised. The portable build is locally ad-hoc signed and has not been Apple-notarized.
