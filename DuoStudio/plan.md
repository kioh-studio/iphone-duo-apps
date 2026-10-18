# DuoStudio — plan.md

Non-UI logic: architecture, data flow, and verification status. UI/visual spec lives in
`design.md`.

## Goal

A photographer holds the open iPhone Duo. The camera facing the subject sits on the outer side;
the outer display mirrors the live preview back to the subject together with a pose template and
their own live skeleton, so they can match a pose without the photographer coaching them verbally.
The subject (who can't touch the outer display) steers filter/zoom/exposure/contrast/warmth with
hand gestures the camera reads. No auto-shutter, no countdown for photos — the photographer always
presses the shutter (or, in self-portrait mode, a physical remote). A second shoot kind, **video**,
records clips with a guide on the subject's display (Frame / Script / Dance — see "Video mode"
below). On-device only: no network, no analytics; photos and videos are written to the Photo
library only when the user shoots / stops; custom pose templates persist in UserDefaults as JSON.

## Architecture

- `PoseCore` (SwiftPM, pure Foundation): `Pose`/`Joint`/`Bone`/`Point2` — the skeleton model —
  `PoseLibrary` (8 built-in templates), `PoseMatcher` (bone-direction comparison + mirroring),
  `HandGesture`/`HandClassifier` (rule-based hand-shape recognition), `GestureRecognizer`
  (hand-sample stream → discrete `GestureEvent`s), `StudioState`/`Adjustments`/`StudioFilter` (the
  live capture state machine), the `OKLCH` colour helper used by `Theme.swift`, and the video-mode
  logic: `DanceRoutine` (skeleton timeline + interpolation), `DanceScorer`, `PoseAligner`,
  `FrameGuide`. No UIKit/SwiftUI/Vision/CoreGraphics imports, so it's unit-testable without a
  simulator.
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
- Video-mode services (details in "Video mode"): `MovieRecorder` (AVAssetWriter, fed by
  `FrameProcessor`), `VisionPose` (shared Vision → `Pose` conversion), `RoutineStore` /
  `RoutineImporter` (imported dance videos → skeleton timelines), `MovieComposer` (mux the reference
  music into a dance recording).
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
frame is dropped entirely — no preview render, no Vision detection — rather than queued behind a
busy main actor. (While recording, the frame has already been handed to `MovieRecorder` before this
guard, so the recording never drops a frame because of it.) `frameCount` still advances on a dropped frame, so the every-3rd-frame detection cadence
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

## Studio modes (the mode dial)

`StudioModel.mode: StudioMode` (`pose | selfie | frame | script | dance | interview`, UserDefaults
`"studioMode"`) is the **single source of truth**. `shootKind`, `videoGuide` and `captureMode` below are
computed from it (and from `isSolo`, `"soloVideo"`, default `false`), so they can never disagree:

| mode | shootKind | videoGuide | captureMode |
|---|---|---|---|
| pose | photo | (frame, unused) | partner |
| selfie | photo | (frame, unused) | selfPortrait |
| frame / script / dance | video | frame / script / dance | selfPortrait if `isSolo`, else partner |
| interview | video | interview | partner (Solo ignored) |

Solo is a deliberate deviation from the design canvas: dance and script are often shot alone on a
stand, so the video modes that support it get a "Solo" toggle instead of losing self-portrait video.

`mode` / `isSolo` changes are ignored (reverted in `didSet`) while `recordingPhase != .idle`; the dial is
also disabled. A change calls `applyDerivedChange(from:)`: if the derived video config (kind, guide)
changed -> `configureVideo()`; if the derived capture mode changed -> `isOuterEnabled = (partner)` and
`captureSource.setMode`. Interview is entered after the camera switch and left before it (the session
swap needs the partner camera pair).

**Migration**: if `"studioMode"` is absent (first launch after the redesign), `migratedMode` derives it
once from the old `"captureMode"` / `"shootKind"` / `"videoGuide"` keys (selfPortrait + photo -> selfie,
photo -> pose, video -> its guide; Solo = old captureMode was selfPortrait for a video guide; an old
selfPortrait + interview pairing becomes Frame + Solo) and writes `"studioMode"` / `"soloVideo"`. The
old keys are never written again. In `init` the migration works on locals, not `self.mode`: an
`@Observable` property must not be read before every stored property is initialised.

`lastSaved: SavedClip?` is set after a successful photo or video save (the "Saved to Photos" sheet binds
to it; dance snapshots `scorer.average` as `routineScore`, because `lastRoutineScore` clears itself
after `Motion.scoreHold` and is still what the outer display shows).

### Skins

`SkinStore.shared` (`@MainActor @Observable`, UserDefaults `"skin"`, default `.studio`) holds the active
`Skin`. `Theme.Palette` / `TypeFace` / `Radius` are `@MainActor static var` lookups into it, so every
existing call site keeps compiling and views re-render on a skin change (Observation tracks the read
inside `body`). Services never read it: `FrameProcessor`'s interviewer-half fill stays the Studio
`paper` constant, so recorded files do not depend on the skin. `Canvas` renderer closures
(`SkeletonOverlay`, `FrameGuideOverlay`, `PoseThumbnailView`) capture their colours by value from `body`
and use `nonisolated static` drawing helpers, so they never touch a `@MainActor` token from a
possibly-nonisolated closure. The colour scheme follows the skin (`.light` for Vintage / Modern) via
`RootView`; the outer display (`SubjectView(isOuterDisplay: true)`) forces `.dark`.

### Onboarding

`RootView` shows `OnboardingView` until UserDefaults `"hasOnboarded"` (`@AppStorage`) is true; only the
camera branch runs `model.requestCameraAccess()`, so the permission prompt comes after onboarding.

## Capture modes

`StudioModel` exposes `CaptureMode: String, CaseIterable { case partner, selfPortrait }` as a value
**derived from the mode dial** (see "Studio modes" above; the old `"captureMode"` key is only read once,
for migration).

- **`.partner`** (the primary spec): photographer on the inner display, camera faces the subject,
  the subject sees `SubjectView` on the Duo's outer display via `CameraCaptureAccessory`.
- **`.selfPortrait`** (works on every iPhone, not just the Duo): phone on a tripod facing the user.
  `CameraService.setMode(_:)` reconfigures the input on `sessionQueue`: with
  `DUO_DIRECTION_COORDINATOR` enabled (currently off, see verification table), the direction coordinator's forward-facing
  device (the one facing the same view the user is looking at) is used; otherwise
  `.builtInWideAngleCamera` at position `.front`. The main (and only) screen shows the `SubjectView`
  composition as the preview of the one shared camera layout (the same mode panel, dial and bottom
  row as every other mode sit below it). `isOuterEnabled` is forced `false` in this mode — nothing is driving the outer display,
  so it stays off rather than showing a stale frame. Switching back to `.partner` restores
  `isOuterEnabled = true`.
- **Remote shutter** (both modes, but the only shutter path in self-portrait mode): SwiftUI's
  `.onCameraCaptureEvent { event in if event.phase == .ended { model.capture() } }` (AVKit) fires
  on the volume buttons, Camera Control, or a paired Bluetooth remote. No self-timer, no countdown
  — a physical remote press is the trigger.

### `DUO_DIRECTION_COORDINATOR` flag

**Currently OFF by default.** `AVCaptureDeviceDirectionCoordinator` isn't in the Xcode 27.2 beta 2 SDK (the header is empty), so partner and self-portrait modes use the classic wide back/front camera fallback until the class ships. The text below describes the intended behaviour once it is re-enabled.

`AVCaptureDeviceDirectionCoordinator` (AVKit, main-actor isolated) needs a live `UIView` to reason
about which side of the Duo it's on, so it can't live inside `CameraService` (which owns no view).
`Sources/Views/CameraDirectionAnchor.swift` is an invisible `UIViewRepresentable` placed in
`StudioView`'s background; its `Coordinator` creates
`AVCaptureDeviceDirectionCoordinator(view:deviceTypes:changeHandler:)` with that hosting view and
`[.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera, .builtInDualWideCamera]`, and keeps it
alive as a stored property (a local `let` would be deallocated, and its change handler with it,
before it could ever fire). Right after creating it, `start(view:model:)` also reads
`coordinator.deviceDirections` once, synchronously, and pushes that initial state through
`StudioModel.updateCameraDirections(forwardIDs:backwardIDs:)` the same way the change handler does
— so the right camera is picked from the first frame instead of waiting for the first
`changeHandler` call. The change handler (and that initial read) both work off an
`AVCaptureDeviceDirectionMap` with `forwardFacingDeviceDescriptors`/`backwardFacingDeviceDescriptors`
(forward = facing the same view the photographer looks at); each descriptor's `uniqueID` is
forwarded through `StudioModel.updateCameraDirections(forwardIDs:backwardIDs:)` to
`CameraService.setDirectionalDevices(forwardIDs:backwardIDs:)` (sessionQueue-confined storage, then
`reconfigureInput()` if the session is already configured). `selectDevice(for:)` resolves the first
ID for the mode (`.partner` → backward, `.selfPortrait` → forward) via `AVCaptureDevice
(uniqueID:)`, falling back to the classic `.builtInWideAngleCamera` `.back`/`.front` when there are
no IDs yet.

The whole coordinator implementation is compiled only under the `DUO_DIRECTION_COORDINATOR` Swift
flag, nested inside `if #available(iOS 27.1, *)`. The flag is now **on by default**
(`SWIFT_ACTIVE_COMPILATION_CONDITIONS` in `project.yml`) now that its shape is confirmed against
Apple's published docs — see Verification status below. What's left is verifying the coordinator's
real behavior on hardware/simulator, tracked in `backlog.md`.

## Video mode

`StudioModel.shootKind` (`ShootKind: photo | video`) sits next to `captureMode`: capture mode says
*which camera and whose screen*, shoot kind says *what the shutter makes*. In video kind `videoGuide`
(`VideoGuide: frame | script | dance | interview`) picks what the subject's display shows. Both - like
`captureMode` - are **derived from `StudioModel.mode`** (see "Studio modes"); the old `"shootKind"` /
`"videoGuide"` keys only feed the one-time migration. Mode changes are ignored (reverted in `didSet`)
while `recordingPhase != .idle`; the dial is also disabled.

### Recording pipeline

`RecordingPhase: idle | countdown(Int) | recording | saving`.

- `toggleRecording()` (record button, remote shutter via `remoteShutter()`): idle → countdown, recording
  → stop, countdown → cancel, saving → ignored. Video has a 3-2-1 countdown (1 s per number,
  `Theme.Motion.countdownStep`) because the person starting it is usually also the subject; photos
  still have none.
- After the countdown: `captureSource.startRecording(includeAudio:)`, then `recordingStartUptime` /
  `.recording`. Stop: `captureSource.stopRecording()` → (dance) `MovieComposer` → `PhotoWriter
  .writeVideo(at:)` → temp files removed → `.idle`. Any failure: `errorMessage = "Couldn't save the
  video."`, phase back to `.idle`. Backgrounding (`scenePhase == .background`) and `StudioModel.stop()`
  call `stopRecordingIfNeeded()`.
- `FrameProcessor.process(upright:time:)` hands the **full-resolution, filtered, contrast-adjusted**
  `CIImage` to `MovieRecorder.appendVideo` right after the filter step and **before** the
  `isDelivering` drop guard, so the main actor's frame-drop policy never costs a recorded frame. A
  recording therefore bakes in the current filter + contrast exactly like `PhotoWriter` does for
  photos; exposure/warmth are already in the sensor data.
- `MovieRecorder` (`@unchecked Sendable`, everything queue-confined): `start` only arms it; the
  `AVAssetWriter` is created on the first frame (H.264 `.mp4`, even width/height from that frame,
  32BGRA pixel-buffer adaptor, real-time input, session started at the first frame's time). Optional
  AAC mono audio input. `finish()` throws `MovieRecorderError.noFrames` if no frame ever arrived.
- Audio: `FrameProcessor` also conforms to `AVCaptureAudioDataOutputSampleBufferDelegate`; the one
  `captureOutput` dispatches on `output is AVCaptureAudioDataOutput`. `CameraService` points the
  audio output at the same `videoQueue` as the video output, so the recorder sees both in capture
  order (and only buffers stamped at/after the session start are written).
- Capture preset: `CameraService.setVideoConfiguration(isVideo:recordsAudio:)` switches the session
  between `.photo` and `.hd1920x1080` (fallback `.high`) and adds/removes the microphone input +
  audio output. The connection rotation (90°) is unchanged, so recorded frames are portrait
  1080×1920 and need no transform. `StudioModel.configureVideo()` computes `recordsAudio = video kind
  && guide != .dance && microphone authorized`, requesting microphone permission the first time a
  mic-using guide is entered; if it is denied the video is simply silent. Dance never records the
  microphone — see below.
- Simulator: video mode records the looping sample clip through the same path (no audio —
  `includeAudio` is ignored); the stick-figure fallback throws `CameraServiceError
  .recordingUnsupported` and the alert reads "Recording isn't supported in this simulator mode."

### Frame guide

`PoseCore.FrameGuide.hint(for:)` turns the live pose's bounding box into a `FrameHint`, set as
`StudioModel.frameHint` on detection frames in video + Frame guide. The safe box in the un-mirrored
image is x 0.08…0.82, y 0.08…0.82 (clear of TikTok's right-hand buttons and bottom caption). Priority:
no person (nil or < 6 joints) → step back (taller than the safe band, crossing the top and/or bottom
edge, or spanning past both sides) → come closer (box height < 0.35) → move left/right → in frame.
Left/right is from the **subject's** point of view: they face the camera, so their left is +x in the
un-mirrored image; a body leaving the image's left edge (`minX < 0.08`) is fixed by stepping toward
+x, i.e. their own left → "Move left" (same reasoning as `GestureRecognizer`'s swipe).

### Script (teleprompter)

`scriptText` (key `"teleprompterScript"`) and `scriptSpeed` (points/second, key `"teleprompterSpeed"`,
default 40, clamped 10…120) live in the model. The subject's display scrolls the text up by
`recordingElapsed × scriptSpeed` (`scriptOffset(at:)`), read from a `TimelineView` — no timer in the
model; idle shows the start of the script. The script is user-typed text kept in UserDefaults, like
custom templates.

### Dance

- **Import**: `PhotosPicker(matching: .videos)` → `PickedMovie` (a `Transferable` that copies the
  picked file into a temp file we own) → `StudioModel.importRoutine(from:)` → `RoutineImporter`.
  Videos over 90 s are rejected (`RoutineImportError.tooLong`; `ponytail:` ceiling — Vision per
  sample time and `routines.json` size). The file is copied into `RoutineStore`
  (`Application Support/Routines/<uuid>.<ext>`); an `AVAssetReader` decodes 32BGRA frames, each
  oriented upright from the track's `preferredTransform` (EXIF-orientation mapping, then re-origined
  to (0,0)), and every 0.1 s (10 fps) `VisionPose.detectBody(in:)` produces a `TimedPose`
  (`pose == nil` when nobody is found). Progress = timestamp / duration, shown as "Importing 42%".
  Runs off the main actor (`@concurrent`, one cooperative thread for the duration) and honours
  cancellation. A video with no audio track imports fine; the recording is then just silent.
- **Routine** (`PoseCore.DanceRoutine`): `pose(at:)` interpolates linearly per joint between the
  surrounding frames (binary search); a nil frame breaks interpolation — the nearest real pose within
  0.25 s is used, else nil. `isMirrored` (set from the chip's "Flip left/right") flips joints on read
  for tutorials filmed mirrored.
- **The music is the clock**: while recording, `AVPlayer(url:)` plays the reference video;
  `player.currentTime()` is the routine time `t` used for both the ghost and scoring, so picture,
  music and ghost can't drift apart from each other. Recorder start and `player.play()` are a few ms
  apart (`ponytail:` comment — add an offset knob if device testing shows drift).
  `AVAudioSession` is set to `.playback` first. The recording ends automatically at `routine.duration`.
- **Ghost**: `danceGhost` is updated on **every** frame in `receive(_:)` (not just detection frames)
  so it moves smoothly: while recording `routine.pose(at: t)` run through `PoseAligner.align` onto
  `livePose` (root on root, torso length matched — drawing only; matching is already translation/scale
  invariant); while idle (and during the countdown) the routine's opening pose as a preview.
  `displayTemplate` returns it, so `SkeletonOverlay` draws it as the dashed ghost.
- **Scoring** (`PoseCore.DanceScorer`): on detection frames while recording, the live pose is
  compared with every routine pose in `[t − 0.35 s, t]` (dancers react after the beat) and the best
  `PoseMatcher.match` counts; the live match % shown is that best match. The mean (`average`) × 100,
  rounded, is `lastRoutineScore`, shown on the subject's display for `Theme.Motion.scoreHold` (4 s).
  Frames with no comparable pose are not counted.
- **Audio mux**: no microphone is recorded in dance mode (the music plays out loud; recording it
  would add room echo and double the track). `MovieComposer.replacingAudio` builds an
  `AVMutableComposition` of the recording's video + the reference video's first audio track
  (`min(video, media)` long) and exports it with the passthrough preset to a new temp `.mp4`; with no
  audio track in the reference it returns the recording unchanged.

### Interview

Partner mode only. One open Duo records **both cameras** into a single 1080x1920 split-screen clip:
guest (the camera partner mode already uses) on the top half, interviewer (the camera self-portrait
uses; on the Duo, the inner under-display camera) on the bottom half. The guest sees themselves on
the outer display; the interviewer sees the recorded composite and question cards on the inner one.
`VideoGuide.interview` is hidden (`availableGuides`) in self-portrait mode, and switching to
self-portrait while on it resets the guide to `.frame` (also reconciled in `init`).

- **Session swap** (`CameraService`): `setVideoConfiguration(isVideo:recordsAudio:interview:)` rebuilds
  `session` (now a `var`, sessionQueue-confined) as an `AVCaptureMultiCamSession` when entering the
  guide and as a plain `AVCaptureSession` when leaving. `tearDown` stops the old one and detaches
  every input/output so the shared outputs can join the next. Any change while a dual session is up
  (e.g. the microphone arriving) rebuilds it. Never switched mid-recording - the model's `didSet`
  guards revert guide/kind changes while `recordingPhase != .idle`.
- **Manual wiring**: `addInputWithNoConnections` / `addOutputWithNoConnections` +
  `AVCaptureConnection(inputPorts:output:)`: guest input -> `videoOutput` (delegate
  `FrameProcessor`, as always), interviewer input -> `secondaryOutput` (delegate `SecondaryFrameSink`,
  same `videoQueue`), mic -> `audioOutput`. No photo output (`capturePhoto` throws if asked).
  Rotation 90 / un-mirrored on both video connections (`configureConnections()`). Exposure/WB
  `apply(_:)` still targets the guest device only. A multi-cam session has no preset, so
  `selectMultiCamFormat` picks the largest `isMultiCamSupported` format up to 1080p at 30 fps.
- **Availability / fallback**: dual needs `AVCaptureMultiCamSession.isMultiCamSupported`, two
  distinct cameras that appear together in `supportedMultiCamDeviceSets`, wirable connections, and
  `hardwareCost` / `systemPressureCost` <= 1.0 after commit; otherwise the normal single-session
  path records the guest camera full-frame (**guest-only fallback**), also when `startRunning()`
  leaves the dual session not running (`dualDisabled` for the rest of the run). The outcome is
  reported through `CaptureSource.setDualCaptureHandler` to `StudioModel.interviewDualAvailable`
  (assumed true until reported), and the inner card shows "This iPhone can't record both cameras
  — recording the guest only." when false. `ponytail:` lowering `activeFormat` would keep dual
  working on more devices.
- **Frames**: `SecondaryFrameSink` keeps only the latest interviewer frame (lock-guarded upright
  `CIImage`). `FrameProcessor` holds an optional sink in `cameraState`; when set, `process` builds
  the recorded frame as the composite: each camera's frame gets the current filter + contrast
  (per-pixel, so equal to filtering the composite - and the guest frame is filtered only once, shared
  with the outer preview), then is aspect-filled and centre-cropped into its 1080x960 half
  (geometry: `PoseCore.SplitLayout.aspectFill`, tested; Core Image y-up, so the guest half is the
  larger y). Until the interviewer's first frame arrives, the bottom half is `paper` colour.
  The composite goes to `recorder.appendVideo` (before the drop guard, like every recording).
- **Preview split**: Vision still runs on the guest frame only; `FrameResult.image` stays the
  guest-only frame (outer display). `FrameResult.compositePreview` is the composite downscaled to a
  960 px long edge, non-nil only in interview; the inner preview shows it (falling back to `image`
  in guest-only mode) with no skeleton overlay.
- **Model**: `interviewQuestionsText` (UserDefaults `"interviewQuestions"`, stored as typed so a
  trailing newline survives editing), `interviewQuestions` = trimmed non-empty lines,
  `currentQuestionIndex` (not persisted, reset to 0 in `startRecording()`), `nextQuestion()` /
  `previousQuestion()` clamp. Recording uses the normal countdown/start/stop/save pipeline with
  `includeAudio = micAuthorized` (the mic permission is requested on entering any non-Dance guide).
- **Simulator**: no second camera. In video mode `SimulatedFrameSource` feeds the same clip frame to
  the sink as the "interviewer", flipped horizontally so the halves differ, and reports dual
  available; the split layout and recording are testable. The stick-figure fallback reports
  guest-only (it can't record anyway).

### Gestures while recording

`receive(_:)` does not feed `GestureRecognizer` while `recordingPhase != .idle` (countdown, recording
and saving), and `startRecording()` replaces the recognizer so no half-finished hold fires when
control returns. The subject's gesture HUD/legend are hidden during countdown/recording.

## Privacy

Everything on-device: Vision pose/hand detection, Core Image filtering, and PHPhotoLibrary writes
never leave the phone. No network calls, no analytics. Persisted: custom pose templates, the
studio mode (`"studioMode"`), Solo (`"soloVideo"`), skin (`"skin"`), the onboarding flag (`"hasOnboarded"`),
teleprompter script and speed / interview questions (UserDefaults; the old `"captureMode"` / `"shootKind"` /
`"videoGuide"` keys are read once to migrate and no longer written), and — new
with video mode — **imported dance reference videos plus `routines.json` (their skeleton timelines)
in `Application Support/Routines/`, which stay until the user deletes the routine**. Recordings are
saved only to Photos (add-only authorization, file moved in); every temp file (the recording, the
muxed copy, the picker's copy of an imported video) is deleted afterwards. The microphone is used
only for Frame/Script/Interview recordings and its audio only goes into the video file.
`NSPhotoLibraryUsageDescription` is deliberately **not** added: `PhotosPicker` runs out of process
and needs no library read permission. No captured-frame or live-audio history is kept once the app is
backgrounded or terminated.

`Resources/PrivacyInfo.xcprivacy` declares this: no tracking, no tracking domains, no collected data
types, and one accessed-API-type entry for `NSPrivacyAccessedAPICategoryUserDefaults` (reason
`CA92.1`, for the persistence above). `RoutineStore` never reads file timestamps, so no
file-timestamp entry is needed. Not excluded from the `Resources`
group in `project.yml`, so XcodeGen picks it up as a plain resource alongside `Info.plist`/
`Assets.xcassets`.

## Verification status

CI: the app builds green on GitHub Actions with Xcode 26.6 (Duo APIs off) and Xcode 27.2 beta 2 (scene accessory on).

Rows below marked **confirmed against published docs (2026-09-20)** have had their Swift API
signatures checked against Apple's developer documentation. That confirms the shape of the call —
it does not confirm real-hardware/Duo-simulator *behavior*, which stays unverified until this runs
on a Mac with Xcode 27.1. Everything else is still **UNVERIFIED — written on Windows, 2026-09-20**;
no Mac/Xcode/Swift toolchain was available to compile or run any of this.

| API | Used for | Status | Source |
|---|---|---|---|
| `View.sceneAccessory(content:)`, `SceneAccessoryContent.onAvailabilityChange(perform:)` | Outer display in Partner mode | Compiles with Xcode 27.2 beta 2 (CI, 2026-10-18); runtime behaviour on Duo unverified | https://developer.apple.com/documentation/swiftui/view/sceneaccessory(content:) |
| `CameraCaptureAccessory<Content>` (`init(content:)`, `init(isEnabled:content:)`) | Outer display in Partner mode | Compiles with Xcode 27.2 beta 2 (CI, 2026-10-18); runtime behaviour on Duo unverified | https://developer.apple.com/documentation/swiftui/cameracaptureaccessory |
| `AVCaptureDeviceDirectionCoordinator(view:deviceTypes:changeHandler:)`, `deviceDirections`, `AVCaptureDeviceDirectionMap.forwardFacingDeviceDescriptors`/`backwardFacingDeviceDescriptors`, `AVCaptureDeviceDescriptor.uniqueID` | Picking the subject-facing (Partner) or user-facing (self-portrait) camera on the Duo; `deviceDirections` is also read once right after creating the coordinator so the initial pick doesn't wait for the first `changeHandler` call | compiles with Xcode 27.2 beta 2 (CI) ONLY with the flag off: with it on, `cannot find 'AVCaptureDeviceDirectionCoordinator' in scope` (SDK header `AVKit.framework/Headers/AVCaptureDeviceDirectionCoordinator.h` is an empty stub, 2026-10-18), so `DUO_DIRECTION_COORDINATOR` is now OFF by default (camera falls back to wide front/back). Re-enable when an SDK ships the class; shape originally from published docs, still unverified. | https://developer.apple.com/documentation/avkit/avcapturedevicedirectioncoordinator |
| `AVCaptureDevice.RotationCoordinator(device:previewLayer:)`, `videoRotationAngleForHorizonLevelCapture`, `AVCaptureConnection.videoRotationAngle`/`isVideoMirrored` | Upright, un-mirrored live preview + horizon-correct photo capture | Unverified — documented iOS 17+ API, but exact behavior on Duo hardware not checked from Windows | Not checked from Windows |
| Camera-only dual-display behavior; outer display takes no touch | Confirms the non-interactive `SubjectView` design and that only `CameraCaptureAccessory` (not a general window) targets the outer display | Unverified — third-party notes, not Apple docs | Group Labs Q&A — https://gist.github.com/frankschlegel/6356a059426b2393528691822edfdae6 |
| `.onCameraCaptureEvent` (AVKit, iOS 18+) | Remote shutter (volume buttons / Camera Control / Bluetooth remote) in both capture modes | Unverified — signature/availability not checked against real docs from Windows | Not checked from Windows |
| `VNDetectHumanBodyPoseRequest` / `VNDetectHumanHandPoseRequest` joint names and confidence semantics | Converting Vision output into `PoseCore.Pose` / hand joints (body conversion now shared in `VisionPose`) | Unverified | Not checked from Windows |
| `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor` (`pixelBufferPool` non-nil after `startWriting()`), real-time H.264 + AAC inputs, `startSession(atSourceTime:)` | `MovieRecorder` | Unverified (UNVERIFIED markers in `MovieRecorder.swift`) | Not checked from Windows |
| `AVCaptureAudioDataOutput` sharing `videoQueue` and one delegate object with the video output; mic input add/remove on a live session; `.hd1920x1080` preset switch | Audio + video arriving in capture order; photo ↔ video preset switch | Unverified (`CameraService.updateAudio`) | Not checked from Windows |
| `AVAudioSession` `.playback` while an `AVCaptureSession` (video only) runs | Dance music playback during recording | Unverified (`StudioModel.startPlayer`) | Not checked from Windows |
| `AVAssetExportSession(asset:presetName:)` + async `export(to:as:)`, Passthrough + `.mp4` | `MovieComposer` audio mux | Unverified (`MovieComposer.swift`) | Not checked from Windows |
| `PhotosPicker(matching: .videos)` + `Transferable` `FileRepresentation(contentType: .movie)` closure shapes; `PhotosPicker` inside a `Menu` | Dance import | Unverified (`PickedMovie.swift`, `StudioView.videoMenuButton`) | Not checked from Windows |
| Orienting imported video frames from `preferredTransform` via `CIImage.oriented(_:)` before Vision | `RoutineImporter` | Unverified (`RoutineImporter.swift`) | Not checked from Windows |
| `@concurrent` on `RoutineImporter.importRoutine` (Swift 6.2) | Keep the Vision loop off the main actor | Unverified | Not checked from Windows |
| `PHAssetResourceCreationOptions.shouldMoveFile` + `.video` resource | `PhotoWriter.writeVideo` | Unverified | Not checked from Windows |
| `AVCaptureMultiCamSession` pair availability (`supportedMultiCamDeviceSets`) for the Duo's outer (guest) + inner under-display (interviewer) cameras, and which `deviceTypes` the inner camera is discoverable under | Interview dual capture | Unverified (`CameraService.isSupportedPair`) | Not checked from Windows |
| `CameraCaptureAccessory` (outer display) while the app's session is an `AVCaptureMultiCamSession` | Interview guest display | Unverified | Not checked from Windows |
| `AVCaptureMultiCamSession.hardwareCost` / `systemPressureCost` after commit, and `isMultiCamSupported` formats up to 1080p at 30 fps | Dual-mode fallback decision | Unverified (`CameraService.makeDualSession`, `selectMultiCamFormat`) | Not checked from Windows |
| The inner under-display camera's resolution cap (assumed 1080p max) | Bottom half quality | Unverified | Not checked from Windows |
| Manual `AVCaptureConnection(inputPorts:output:)` rotation/mirroring on a multi-cam session; `CIColor(red:green:blue:alpha:colorSpace:)` linear paper fill | Interview composite | Unverified (`CameraService.configureConnections`, `FrameProcessor.paper`) | Not checked from Windows |
| Observation tracking through `@MainActor static var` token getters read inside `body` (`Theme.Palette` / `TypeFace` / `Radius` -> `SkinStore.shared.skin`), including `.sheet` content and the outer-display `CameraCaptureAccessory` scene | Live skin switching re-renders both screens | Unverified (marker in `Theme.swift`); fallback is `.id(skin)` on the root views | Not checked from Windows |
| `Font.system(_:design:)` + `.weight(_:)` with `.serif` / `.rounded` / `.monospaced` per skin; `preferredColorScheme` following the skin for sheets and `nil` from the inner `SubjectView` | Skin typography and light skins | Unverified | Not checked from Windows |
| `Canvas` renderer closure isolation (colours captured by value, drawing helpers `nonisolated static`) | `SkeletonOverlay`, `FrameGuideOverlay`, `PoseThumbnailView` | Unverified - written to compile whether or not the closure is `@MainActor` | Not checked from Windows |
| `@AppStorage("hasOnboarded")` in `RootView`; `.sheet(item:)` bound to `StudioModel.lastSaved` | Onboarding gate, "Saved to Photos" sheet | Unverified | Not checked from Windows |

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

### Video mode

If the app bundle contains `SimulatorSample.mp4` (looked up via `Bundle.main`), `SimulatedFrameSource`
runs in video mode instead; the stick figure above is the fallback when the file is absent.

- An `AVAssetReader` loops the clip (reopened at end of file) from the same `timerQueue`, ticking at
  a fixed ~30 fps (the clip's `nominalFrameRate` is ignored).
- Each frame goes through the real `FrameProcessor` via `process(upright:time:)` — the same
  filter/contrast, frame drop, Vision body + hand detection and `MainActor` delivery as on device.
  `SimulatedFrameSource` just owns a `FrameProcessor` and forwards `model` / `updateFilter`.
- `time` is monotonic elapsed uptime, not the video PTS: PTS resets each loop and
  `GestureRecognizer` needs time that never runs backwards.
- `lastImage` (what `capturePhoto()` encodes) is the unfiltered frame, matching device, where
  `PhotoWriter` bakes filter + contrast in afterwards.
- Self-portrait mode mirrors the frame horizontally before Vision, as the stick figure does.
- Video shoot kind records this clip through `FrameProcessor` → `MovieRecorder` (filter + contrast
  baked in) with no audio; the stick-figure fallback can't record and shows an alert instead.
- `project.yml` sets `EXCLUDED_SOURCE_FILE_NAMES[sdk=iphoneos*]: SimulatorSample.mp4` so the clip
  never ships to devices. A Pexels sample clip is committed ("A Young Woman Dancing While Looking at
  the Camera", https://www.pexels.com/video/a-young-woman-dancing-while-looking-at-the-camera-6868329/,
  Pexels License); device builds still exclude it via `EXCLUDED_SOURCE_FILE_NAMES`.
- Interview guide: the same clip frame also feeds `SecondaryFrameSink` as the "interviewer" (flipped
  horizontally) so the split-screen layout and its recording can be exercised - see "Interview".
- Ceiling: the clip must already be upright portrait — `preferredTransform` is not applied.

## Out of scope

See root `backlog.md` for everything deferred: Mac build verification, on-device hand-gesture
accuracy at 2–3 m, reserved-region-aware inner-display layout, UserDefaults-only template
persistence (no export/share yet), App Store name reservation, app icon, and App Store Connect
Featuring Nomination prep.
