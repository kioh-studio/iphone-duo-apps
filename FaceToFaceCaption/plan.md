# FaceToFaceCaption — plan.md

Non-UI logic: architecture, data flow, and verification status. UI/visual spec lives in `design.md`.

## Goal

Two people who don't share a language sit face to face. Across transcribes speech on-device and
translates it on-device, showing live captions to both — one on the phone in front of the person
speaking, one on a facing display (or the flipped top half of the same screen) for the person
listening. No network, no server, no persistence of what was said.

## Architecture

- `CaptionCore` (SwiftPM, pure Foundation): `Conversation` — the caption timeline state machine —
  plus `LanguagePair`/`Speaker` and the `OKLCH` colour helper used by `Theme.swift`. No
  UIKit/SwiftUI/Speech imports, so it's unit-testable without a simulator.
- `ConversationModel` (app, `@MainActor @Observable` singleton) — owns a `Conversation`, is shared
  by both the main scene and the external-display scene so they always render the same state.
- `SpeechService` — wraps `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26) and an `AVAudioEngine`
  tap; emits volatile and final recognition results plus a mic level, per speaker/turn.
- `TranslationService` — wraps `TranslationSession(installedSource:target:)` (Translation
  framework); one session per language direction.
- `DisplayMonitor` — watches `UIScene` connect/disconnect notifications for a scene with role
  `.windowExternalDisplayNonInteractive`, i.e. whether a facing display is currently attached.
- `LanguageCatalog` — lists `SpeechTranscriber.supportedLocales` for the language pickers, maps
  device locales like `en-VN` to the closest supported identifier (`bestMatch`), and formats
  language names; translation support is checked per chosen pair with `LanguageAvailability`.

## Data flow

Mic → `AVAudioEngine` tap → format conversion → `SpeechAnalyzer` → volatile/final results →
`ConversationModel` calls `Conversation.receiveVolatile`/`receiveFinal` → view observes
`Conversation` → every final segment that adds committed text asks `TranslationService` to
translate the line's full committed text → result applied back via `Conversation.applyTranslation`/`failTranslation` → both the local
transcript and the partner's facing display re-render from the same `Conversation` value.

## Turn model

Three states: `idle`, `listening(Speaker)`, `finishing(Speaker)`. Only one recognizer runs at a
time. Starting a turn for one speaker first finalizes and closes the other speaker's open line
(`Conversation.closeOpenLine`) so a turn switch never leaves a half-finished line hanging open.
Manual turn buttons only for v1 — no auto language/turn detection (backlog). Taps are ignored
while a start/finish transition is in flight (one `turnTask` at a time), so rapid double taps
can't open two recognizers.

## Translation coalescing

At most one in-flight translation request per line. `Conversation.needsTranslation` is the single
source of truth for "does this line need (re)translating" — it accounts for a line whose committed
text grew again while a translation was in flight. When that happens, the service simply requests
translation again with the latest committed text; `Conversation.applyTranslation`'s stale-source
guard (source shorter than what's already applied) protects against an old, slow result overwriting
a newer one that arrived first.

## Display strategy

- Facing display available today: a second `UIScene` with role
  `.windowExternalDisplayNonInteractive` renders the Partner view full-screen; the phone itself
  shows the My-side view full-screen.
- iPhone Duo outer display: routed through Apple's `.sceneAccessory` modifier once it ships with
  Xcode 27.1 (Apple documents only `CameraCaptureAccessory` so far; whether non-camera apps get
  an accessory type for the outer display is undocumented — backlog).
- No facing display: shared-table layout — Partner view rotated 180° on the top half, My side on
  the bottom half, 28pt fold band between them. `UIApplication.isIdleTimerDisabled = true` while a
  conversation is active, in either display mode.

## Privacy

Speech recognition and translation both run on-device (`SpeechAnalyzer`, `Translation`
framework). No network calls. Transcripts live only in `ConversationModel` for the process
lifetime; "Clear" wipes them immediately (with a 5 s undo window before the wipe is final) and
backgrounding/terminating the app drops them for good — nothing is written to disk.

## Setup & downloads

- Speech: `SpeechTranscriber.installedLocales` tells whether each side's model is on the device;
  `AssetInventory.assetInstallationRequest(supporting:)` downloads missing ones with progress.
- Translation: `.translationTask` + `prepareTranslation()` on the setup screen to trigger the
  system's language-pack download UI for the chosen pair.
- Microphone permission is requested when the user taps "Start conversation" on the setup screen
  (`AVAudioApplication.requestRecordPermission()`); a denial shows an Open Settings notice.
- If a start step fails part-way (audio session, analyzer, converter, engine), `SpeechService`
  tears down everything it already set up before rethrowing, so the mic is never left running.

## Verification status

Every row below is **UNVERIFIED — written on Windows, 2026-09-13.** No Mac/Xcode/Swift toolchain
was available to compile or run any of this.

| API | Used for | Status | Source |
|---|---|---|---|
| `SpeechAnalyzer` / `SpeechTranscriber` | On-device streaming speech-to-text | Unverified | WWDC25 session 277 — https://developer.apple.com/videos/play/wwdc2025/277/ |
| `SpeechAnalyzer` live-mic buffering/format quirks | Feeding a live `AVAudioEngine` tap into the analyzer | Unverified | https://dev.to/simple_memo/ios-26s-speechanalyzer-on-a-live-mic-the-5-things-the-docs-dont-tell-you-2ng5 |
| `TranslationSession(installedSource:target:)` | On-device translation per line | Unverified | iOS 26 initializer, works only for installed pairs (developer write-up) — https://ar-ms.me/thoughts/translation-cli/ |
| `UISceneSession.Role.windowExternalDisplayNonInteractive` | Facing-display scene in a SwiftUI app lifecycle | Unverified | UIKit external-display scene role — not checked against docs from Windows |
| iPhone Duo camera/display behavior for non-camera apps | Whether a normal app can even target the Duo's outer display | Unverified | iPhone Duo camera tech talk — https://developer.apple.com/videos/play/tech-talks/111465/ |
| `.sceneAccessory`/`CameraCaptureAccessory` (outer display, camera apps only — non-camera use undocumented); `.onHingeChange`/`UIHingeInteraction` (hinge, confirmed by Apple); `reservedRegions(kind:)` (SwiftUI `GeometryProxy` / UIKit `view`) | Duo-native display targeting | iOS 27.1 SDK not yet released | Apple Tech Talks 111463, 111464 — https://developer.apple.com/videos/play/tech-talks/111463/, https://developer.apple.com/videos/play/tech-talks/111464/ |

## Out of scope

See root `backlog.md` for everything deferred: Mac build verification, the Duo outer display via
`.sceneAccessory` (only `CameraCaptureAccessory` documented; non-camera outer-display use unconfirmed),
hinge/posture-driven layout, reserved-region-aware fold band, auto language/turn
detection, Vietnamese localization, app icon, on-device testing after the Duo ships, and
differentiation from Apple's own Translate conversation mode.
