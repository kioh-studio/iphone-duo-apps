# iphone-duo-apps — CLAUDE.md

## What this repo is

Apps designed specifically for the iPhone Duo (foldable, announced 2026-09-09,
ships 2026-10-23, iOS 27). One folder per app, each a self-contained Xcode
project. Current app: `FaceToFaceCaption/` (display name **Across**) — live
face-to-face speech captioning and translation.

## Stack

- SwiftUI, native. No React Native, no cross-platform UI.
- Swift 6, strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`).
- iOS 26.0 minimum — apps run on any iPhone, using a shared-table fallback
  where the Duo's outer display would otherwise be used.
- Duo-specific APIs (outer display via `.sceneAccessory` — Apple documents
  only `CameraCaptureAccessory` so far, non-camera use is undocumented —,
  hinge/posture, reserved regions) ship with the iOS 27.1 SDK. Gate anything that touches
  them behind availability checks when it's added — don't assume the SDK is
  present.
- XcodeGen (`project.yml`) generates the `.xcodeproj`; nothing is hand-edited
  in Xcode's project format.
- Each app has a platform-neutral SwiftPM core package (e.g. `CaptionCore`)
  holding pure logic and its own tests, with no UIKit/SwiftUI/Speech imports.

## Build (on a Mac)

```
brew install xcodegen
cd FaceToFaceCaption && xcodegen generate && open FaceToFaceCaption.xcodeproj
cd FaceToFaceCaption/CaptionCore && swift test
```

## Windows caveat

Code in this repo was written on a Windows machine with no Swift toolchain —
nothing here has ever compiled. Treat everything as UNVERIFIED until it
builds on a Mac. API usages that couldn't be checked against real
documentation carry a `// UNVERIFIED (<date>, written on Windows)` comment.

## Conventions

- Views are thin. Logic lives in `@Observable` models or in the core package
  — never inline in a view body.
- All colours, fonts, spacing, and durations come from each app's
  `Sources/Design/Theme.swift` tokens. Never inline a raw value.
- On-device only: no network calls, no analytics, no persistence of
  transcripts or other captured speech/text.
- No third-party dependencies without asking anh Khôi first.

## Documentation policy

- UI/visual/interaction changes → `<App>/design.md`.
- Non-UI logic changes → `<App>/plan.md`.
- Unfinished or deferred work → root `backlog.md` (delete an item once it's
  done — the file only tracks what's left).
- Update docs in the same session as the code change.

## Hallmark

UI follows the Hallmark design skill, adapted to native iOS (no web
macrostructure/nav/footer concepts). `.hallmark/log.json` records each run.
