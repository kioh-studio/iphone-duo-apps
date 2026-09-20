# DuoStudio — plan.md

Non-UI logic: architecture, data flow, and verification status. UI/visual spec lives in
`design.md`.

## Goal

A photographer holds the open iPhone Duo. The camera facing the subject sits on the outer side;
the outer display mirrors the live preview back to the subject together with a pose template and
their own live skeleton, so they can match a pose without the photographer coaching them verbally.
The subject (who can't touch the outer display) steers filter/zoom/exposure/contrast/warmth with
hand gestures the camera reads. No auto-shutter, no countdown — the photographer always presses the
shutter (or, in self-portrait mode, a physical remote). On-device only: no network, no analytics;
photos are written to the Photo library only on shutter; custom pose templates persist in
UserDefaults as JSON.

## Architecture

- `PoseCore` (SwiftPM, pure Foundation): `Pose`/`Joint`/`Bone`/`Point2` — the skeleton model —
  `PoseLibrary` (8 built-in templates), `PoseMatcher` (bone-direction comparison + mirroring),
  `HandGesture`/`HandClassifier` (rule-based hand-shape recognition), `GestureRecognizer`
  (hand-sample stream → discrete `GestureEvent`s), `StudioState`/`Adjustments`/`StudioFilter` (the
  live capture state machine), and the `OKLCH` colour helper used by `Theme.swift`. No
  UIKit/SwiftUI/Vision/CoreGraphics imports, so it's unit-testable without a simulator.
- `StudioModel` (app, `@MainActor @Observable`) — owns `CameraService`, a `GestureRecognizer`,
  `StudioState`, the template list (`PoseLibrary.builtIn` + custom templates loaded from
  UserDefaults), and the live `previewImage`/`livePose`/`match`. It is the single place gesture
  events and inner-UI edits both flow through, so the two paths can never disagree.
- `CameraService` — owns the `AVCaptureSession` (confined to a private serial `sessionQueue`;
  frames delivered on a private `videoQueue`), selects the subject-facing (or, in self-portrait
  mode, user-facing) camera, applies hardware exposure/white-balance adjustments, and sets the
  video connection's rotation/mirroring so frames always arrive upright and un-mirrored (see
  Orientation below). Only the exposure/WB knob that actually changed is touched: white balance
  stays on auto until warmth is deliberately adjusted away from its 5500 K default, so switching
  filters or nudging exposure never locks WB as a side effect; when the active device changes (mode
  switch or a Duo posture change), the last applied exposure is always re-pushed to the new device,
  and warmth only if it was ever touched. White balance is locked only when
  `isLockingWhiteBalanceWithCustomDeviceGainsSupported` is true, and the exposure bias is clamped to
  `device.minExposureTargetBias...maxExposureTargetBias` — both unconditionally would otherwise
  throw an uncatchable ObjC exception on a device with narrower hardware ranges.
- `FrameProcessor` — per frame: builds a `CIImage` (already upright/un-mirrored — see Orientation),
  applies the current filter + contrast, publishes a downscaled `CGImage`; every 3rd frame, runs
  Vision body- and hand-pose requests (against the unfiltered upright image — see Frame drop policy
  below) and converts the results into `PoseCore` types. `FrameResult.isDetectionFrame` marks which
  frames those were, so `StudioModel.receive(_:)` knows when `pose`/`hand` are meaningful.
- `PhotoWriter` — bakes the current filter + contrast into the captured photo and writes it to the
  Photo library (exposure/warmth are already baked in by the hardware at capture time). When
  neither the filter nor the contrast actually changes anything (`filter == .none` and
  `abs(contrast - 1) < 0.001`), the original capture `Data` is saved untouched instead of round-
  tripping through Core Image, so EXIF and bit depth survive.

## Data flow

Camera → `AVCaptureVideoDataOutput` → `FrameProcessor` (upright CIImage → filtered/downscaled
preview image; every 3rd frame → Vision body/hand pose → `PoseCore.Pose` / `HandSample`) →
`@MainActor` hop → `StudioModel.receive(_:)` → updates `previewImage`/`livePose`, computes
`PoseMatcher.match(live:template:)` against the selected template, and — if `gesturesEnabled` —
feeds the hand sample into `GestureRecognizer`. A resulting `GestureEvent` goes through
`StudioState.apply(_:)` (the same call inner-UI controls use), then the changed
filter/contrast/exposure/warmth are pushed back down to `CameraService`/`FrameProcessor`. Both
displays render from the same `StudioModel`/`StudioState`, so the photographer's inner view and the
subject's outer view are always showing the same match %, filter, and parameter.

**Frame drop policy:** `FrameProcessor` tracks one `isDelivering` flag; if the previous
`FrameResult` hasn't finished reaching `StudioModel.receive(_:)` on the main actor yet, the current
frame is dropped entirely — no render, no Vision detection — rather than queued behind a busy main
actor. `frameCount` still advances on a dropped frame, so the every-3rd-frame detection cadence
doesn't drift; the flag clears right after `receive(_:)` returns.

**Detection-frame-only pose updates:** Vision only runs on every 3rd frame, but `previewImage`
updates every frame. `StudioModel.receive(_:)` reflects that split: `previewImage` is always
updated, while `livePose`/`match` (and the gesture feed, which depends on `pose`/`hand` anyway) only
update when `FrameResult.isDetectionFrame` is true. Updating `livePose` unconditionally used to null
it out on the 2 of every 3 frames Vision didn't run on, which was the cause of the skeleton overlay
visibly flickering.

**Orientation:** `CameraService.configureConnections()` sets the video data output connection's
`videoRotationAngle = 90` (when supported) and `isVideoMirrored = false` with
`automaticallyAdjustsVideoMirroring = false` (when supported), run after both `configureSession()`
and `reconfigureInput()` since swapping the active input can hand the output a new connection. This
replaces a per-frame `CIImage.oriented(_:)` guess keyed off device position in `FrameProcessor`,
which is now just `CIImage(cvPixelBuffer:)` with no orientation argument — the buffer already
arrives upright and un-mirrored. Photo capture instead uses an `AVCaptureDevice.RotationCoordinator`
(session-queue-confined, recreated whenever the active device changes alongside
`videoDeviceInput`): `capturePhoto()` sets the photo output connection's `videoRotationAngle` to
`rotationCoordinator.videoRotationAngleForHorizonLevelCapture` right before capturing, so a single
photo can reflect the device's horizon-level rotation independently of the live preview's fixed
angle.

## Gesture rules (implemented in `PoseCore.GestureRecognizer`)

- **Swipe** (open palm, wrist moves > 0.15 normalized width within 0.6 s) → `.nextFilter` /
  `.previousFilter`, then a 1.0 s cooldown. Direction is defined from the *subject's* point of
  view, not the camera's: `wrist.x` is reported in the upright, un-mirrored camera image, but the
  subject only ever watches a mirrored view (`SubjectView` mirrors in both capture modes), so a
  swipe towards the subject's right moves the wrist to *smaller* x in that un-mirrored image.
  `dx < -0.15` → `.nextFilter`; `dx > 0.15` → `.previousFilter`.
- **Pinch** (held across consecutive samples) → `.zoom(factor:)`, the ratio of the current
  `pinchDistance` to a baseline, whenever it moves more than 3%. The baseline only advances when a
  zoom actually fires (not every frame), so a slow, steady pinch that never clears 3% in a single
  frame still accumulates towards firing instead of resetting its baseline every sample. Drives
  `outerZoom` only, never the captured photo.
- **Fist held ≥ 0.8 s** → `.nextParameter` once; must release before firing again.
- **Point up/down held ≥ 0.5 s** → `.adjust(step: +1/-1)`, repeating every 0.4 s while held.
- A `nil` hand shape, or switching shapes, resets the other shapes' hold timers (the swipe cooldown
  is time-based, not a hold timer, and is unaffected).

## Pose matching (implemented in `PoseCore.PoseMatcher`)

Bone-direction comparison, translation/scale invariant: for each of the 14 bones in `Pose.bones`
with both endpoints present in both the live and template poses, the angle between the two bone
vectors is computed via the dot-product formula (`acos` of the normalized dot product — this
avoids `atan2` wraparound bookkeeping). Per-bone score is `max(0, 1 - angle/60)`; overall score is
the mean; a bone is "off" past `toleranceDegrees` (20°). Fewer than 4 comparable bones → no match
(`nil`) rather than a misleadingly confident score.

Templates (built-in and custom) are stored in the camera's upright, **un-mirrored** coordinate
space — the same space `livePose` and the pose editor use — so `StudioModel.displayTemplate` is
just `selectedTemplate?.pose`, no mirroring. `PoseMatcher.mirrored(_:)` still exists (and is
tested) but isn't part of this path any more; mirroring for display is `SubjectView`'s job, which
mirrors its whole preview + overlay stack together (live pose and template alike), not `PoseMatcher`'s.

## Capture modes

`StudioModel` owns `CaptureMode: String, CaseIterable { case partner, selfPortrait }`, persisted in
UserDefaults key `"captureMode"`, default `.partner`.

- **`.partner`** (the primary spec): photographer on the inner display, camera faces the subject,
  the subject sees `SubjectView` on the Duo's outer display via `CameraCaptureAccessory`.
- **`.selfPortrait`** (works on every iPhone, not just the Duo): phone on a tripod facing the user.
  `CameraService.setMode(_:)` reconfigures the input on `sessionQueue`: with
  `DUO_DIRECTION_COORDINATOR` enabled on iOS 27.1+, the direction coordinator's forward-facing
  device (the one facing the same view the user is looking at) is used; otherwise
  `.builtInWideAngleCamera` at position `.front`. The main (and only) screen shows the `SubjectView`
  composition directly, with a thin control layer added on top (shutter, mode switch, template
  picker). `isOuterEnabled` is forced `false` in this mode — nothing is driving the outer display,
  so it stays off rather than showing a stale frame. Switching back to `.partner` restores
  `isOuterEnabled = true`.
- **Remote shutter** (both modes, but the only shutter path in self-portrait mode): SwiftUI's
  `.onCameraCaptureEvent { event in if event.phase == .ended { model.capture() } }` (AVKit) fires
  on the volume buttons, Camera Control, or a paired Bluetooth remote. No self-timer, no countdown
  — a physical remote press is the trigger.

### `DUO_DIRECTION_COORDINATOR` flag

`AVCaptureDeviceDirectionCoordinator` (AVKit, main-actor isolated) needs a live `UIView` to reason
about which side of the Duo it's on, so it can't live inside `CameraService` (which owns no view).
`Sources/Views/CameraDirectionAnchor.swift` is an invisible `UIViewRepresentable` placed in
`StudioView`'s background; its `Coordinator` creates
`AVCaptureDeviceDirectionCoordinator(view:deviceTypes:changeHandler:)` with that hosting view and
`[.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera, .builtInDualWideCamera]`, and keeps it
alive as a stored property (a local `let` would be deallocated, and its change handler with it,
before it could ever fire). The change handler receives an `AVCaptureDeviceDirectionMap` with
`forwardFacingDeviceDescriptors`/`backwardFacingDeviceDescriptors` (forward = facing the same view
the photographer looks at); each descriptor's `uniqueID` (UNVERIFIED) is forwarded through
`StudioModel.updateCameraDirections(forwardIDs:backwardIDs:)` to
`CameraService.setDirectionalDevices(forwardIDs:backwardIDs:)` (sessionQueue-confined storage, then
`reconfigureInput()` if the session is already configured). `selectDevice(for:)` resolves the first
ID for the mode (`.partner` → backward, `.selfPortrait` → forward) via `AVCaptureDevice
(uniqueID:)`, falling back to the classic `.builtInWideAngleCamera` `.back`/`.front` when there are
no IDs yet.

The whole coordinator implementation is compiled only under the `DUO_DIRECTION_COORDINATOR` Swift
flag (documented, but **not** set, in `project.yml`), nested inside `if #available(iOS 27.1, *)` —
so the flag is off by default and a first Mac build can't fail on an API that's never been checked
against the real SDK. Turning it on is tracked in `backlog.md`.

## Privacy

Everything on-device: Vision pose/hand detection, Core Image filtering, and PHPhotoLibrary writes
never leave the phone. No network calls, no analytics. Custom pose templates are the only thing
persisted (UserDefaults, JSON) — no transcript or captured-frame history is kept once the app is
backgrounded or terminated.

`Resources/PrivacyInfo.xcprivacy` declares this: no tracking, no tracking domains, no collected data
types, and one accessed-API-type entry for `NSPrivacyAccessedAPICategoryUserDefaults` (reason
`CA92.1`, for the custom-template/capture-mode persistence above). Not excluded from the `Resources`
group in `project.yml`, so XcodeGen picks it up as a plain resource alongside `Info.plist`/
`Assets.xcassets`.

## Verification status

Every row below is **UNVERIFIED — written on Windows, 2026-09-20.** No Mac/Xcode/Swift toolchain
was available to compile or run any of this.

| API | Used for | Status | Source |
|---|---|---|---|
| `.sceneAccessory` / `CameraCaptureAccessory` | Outer display in Partner mode | Unverified — iOS 27.1 SDK not yet released | Tech Talk 111464 — https://developer.apple.com/videos/play/tech-talks/111464/ |
| `AVCaptureDeviceDirectionCoordinator(view:deviceTypes:changeHandler:)`, `AVCaptureDeviceDirectionMap.forwardFacingDeviceDescriptors`/`backwardFacingDeviceDescriptors`, `AVCaptureDeviceDescriptor.uniqueID` | Picking the subject-facing (Partner) or user-facing (self-portrait) camera on the Duo | Unverified — gated behind `DUO_DIRECTION_COORDINATOR` (off), not compiled into the default build | Tech Talk 111465 — https://developer.apple.com/videos/play/tech-talks/111465/ |
| `AVCaptureDevice.RotationCoordinator(device:previewLayer:)`, `videoRotationAngleForHorizonLevelCapture`, `AVCaptureConnection.videoRotationAngle`/`isVideoMirrored` | Upright, un-mirrored live preview + horizon-correct photo capture | Unverified — documented iOS 17+ API, but exact behavior on Duo hardware not checked from Windows | Not checked from Windows |
| Camera-only dual-display behavior; outer display takes no touch | Confirms the non-interactive `SubjectView` design and that only `CameraCaptureAccessory` (not a general window) targets the outer display | Unverified — third-party notes, not Apple docs | Group Labs Q&A — https://gist.github.com/frankschlegel/6356a059426b2393528691822edfdae6 |
| `.onCameraCaptureEvent` (AVKit, iOS 18+) | Remote shutter (volume buttons / Camera Control / Bluetooth remote) in both capture modes | Unverified — signature/availability not checked against real docs from Windows | Not checked from Windows |
| `VNDetectHumanBodyPoseRequest` / `VNDetectHumanHandPoseRequest` joint names and confidence semantics | Converting Vision output into `PoseCore.Pose` / hand joints | Unverified | Not checked from Windows |

## Simulator

The iOS Simulator has no camera: without a fake source, the app would show a black preview and
none of the pose/gesture UI could be exercised. `CaptureSource` (`Sources/Services/CaptureSource
.swift`) is the protocol `StudioModel` drives instead of talking to `CameraService` directly
(`start`/`stop`/`apply`/`setMode`/`capturePhoto`) — `CameraService` conforms to it, and
`Sources/Services/SimulatedFrameSource.swift` (whole file gated behind
`#if targetEnvironment(simulator)`) is a second conformer built for the Simulator. `StudioModel`
picks between them in `init()` with the same flag; `setDirectionalDevices` stays off the protocol
and `CameraService`-only, since it means nothing without a real, physical Duo.

`SimulatedFrameSource` runs a `DispatchSourceTimer` on its own private serial queue, ~10 Hz, and
feeds `StudioModel.receive(_:)` the same way `FrameProcessor` does (a `@MainActor` hop):

- **Image**: a soft vertical gradient (mirroring `Theme.Palette.paper`/`paper3`'s OKLCH values,
  reused directly via `PoseCore.OKLCH` since a Service can't import SwiftUI's `Theme`) plus a stick
  figure drawn from the current pose, rendered into a `CGContext` and then run through the same
  filter + contrast `CIImage` pipeline `FrameProcessor` uses, so switching filters is visibly
  testable.
- **Pose**: `PoseLibrary.builtIn[0]`, perturbed continuously (wrists/elbows on a slow sine, the
  whole figure drifting a little) so the match % moves instead of sitting constant. The same
  perturbed pose is what gets drawn into the image, so the skeleton overlay lines up with the
  figure underneath it.
- **Hand**: a canned gesture script looping every ~16 s — idle → open-palm swipe (fires a filter
  change) → growing pinch (fires zoom) → held fist (~1 s, next parameter) → held pointUp (~1.5 s,
  adjust up) → held pointDown (~1.5 s, adjust down) → idle — feeding real `HandSample` values
  through the *existing* `GestureRecognizer` (`StudioModel.receive(_:)` already owns that call;
  the simulated source never calls it directly), so every gesture path gets exercised.
- **Capture**: `capturePhoto()` JPEG-encodes the last drawn (post-filter) image via
  `CIContext.jpegRepresentation`, so the `PhotoWriter`/Photos-permission path also runs.

**What this proves**: the full `StudioModel` → `SkeletonOverlay`/`SubjectView` → gesture → filter/
capture UI path, end to end, without hardware.

**What this does NOT prove**: nothing about Vision's real accuracy (there's no `VNDetectHuman*
PoseRequest` call anywhere in this path — the "detection" is just handed over pre-classified),
nothing about a real camera's behavior (exposure/white-balance/rotation/mirroring, multi-camera
selection), and nothing about the Duo's outer display or direction coordinator specifically — see
`backlog.md` for the real-device verification this still owes.

## Out of scope

See root `backlog.md` for everything deferred: Mac build verification, on-device hand-gesture
accuracy at 2–3 m, reserved-region-aware inner-display layout, UserDefaults-only template
persistence (no export/share yet), App Store name reservation, app icon, and App Store Connect
Featuring Nomination prep.
