# DuoStudio — VERIFY.md

Runbook for checking this app on the iPhone Duo simulator with Xcode 27.1 beta. Nothing in this
repo has ever compiled (written on Windows — see root `CLAUDE.md`), so this is the first real
signal on whether any of it works.

## Setup

```
brew install xcodegen
cd DuoStudio && xcodegen generate && open DuoStudio.xcodeproj
```

Pick the **iPhone Duo** simulator as the run destination, then Run.

### Optional: real Vision on a video clip

A sample clip is committed at `DuoStudio/Resources/SimulatorSample.mp4` — "A Young Woman Dancing
While Looking at the Camera" from Pexels
(https://www.pexels.com/video/a-young-woman-dancing-while-looking-at-the-camera-6868329/, Pexels
License). It is front-facing full body with no hand gestures, so it exercises preview/skeleton/match %
but NOT gestures. To test gestures, replace it with your own upright portrait clip (full body visible,
doing the hand gestures), re-run `xcodegen generate`, and run. The Simulator loops the clip as the
camera feed and runs the real Vision body/hand detection on it. Without the file it falls back to the
canned stick figure. The file is excluded from device builds. To convert, bake in rotation and shrink:

```
ffmpeg -i input.mov -vf "scale=-2:1280" -an -c:v libx264 -pix_fmt yuv420p SimulatorSample.mp4
```

Apple has noted a known issue where the *first* launch of a new simulator device can take several
minutes (device bring-up, not a hang) — don't assume it's stuck if it sits at a blank screen
briefly.

## Feature checklist

| Feature | Where | What to do | What you must see |
|---|---|---|---|
| App launch / synthetic preview | Main screen | Launch the app, grant camera access if prompted | A live-updating preview image — the simulator has no camera, so `SimulatedFrameSource` drives it (the looping clip if `SimulatorSample.mp4` is bundled, else the stick figure) (see `plan.md`'s Simulator section) |
| Template + live skeleton overlay | Main screen | Watch the preview after launch | A dashed "ghost" template skeleton and a solid live skeleton drawn aligned over the preview |
| Match % | Main screen | Watch for a few seconds | The match percentage changes continuously — with the clip, from real Vision on the video; without it, from `SimulatedFrameSource`'s canned pose swing |
| Gestures | Main + outer/subject view | With the clip: watch the gestures performed in it (real Vision). Without it: watch a full ~16 s canned loop | Canned fallback, in order: filter change → zoom → parameter switch → adjust up → adjust down, each firing a toast on the subject view |
| Template chips | Pose / Selfie mode panel | Scroll/tap the chips | Selecting a different built-in template updates the ghost skeleton; "+ New pose" opens the pose editor |
| Pose editor | Template editor | Drag joints, tap "Use live pose", Save, then delete a custom template | Joints move under drag; "Use live pose" snaps to the current synthetic pose; Save persists it into the strip; delete removes it |
| Controls sheet | Bottom row, "Controls" | Open the sheet; pick filters, move each slider, read the gesture cards, flip "Show outer display" / "Hand gestures" | Sliders track touch; the HUD readout updates to match; four legend cards (Swipe palm / OK sign / Hold fist / Point up/down); the toggles match the top-bar Outer / Gestures chips |
| Pose ↔ Selfie | Mode dial | Switch between Pose and Selfie | Selfie moves the guide and score onto this screen (`SubjectView` as the preview) and turns the outer display off; the panel, dial and bottom row stay the same; Pose turns the outer display back on |
| Shutter → Photos | Main screen | Tap shutter, grant the add-only Photos prompt | A photo is saved; opening it in Photos shows the synthetic frame (clip frame or stick figure), not a real camera image |
| Mode dial | Under the panel | Tap each of Pose, Selfie, Frame, Script, Dance, Interview | Two labelled groups PHOTO / VIDEO; the selected mode is accent-filled; the one-line summary under the dial changes (copy matches `StudioMode.summary`); the panel row changes; the choice survives relaunch; the dial is disabled while recording |
| Solo toggle | Top bar, Frame / Script / Dance only | Toggle "Solo" | The preview becomes the mirrored `SubjectView` on this screen and the outer display turns off; survives relaunch; absent in Pose / Selfie / Interview |
| Migration from the old keys | First launch after updating from a build with the three switches | Before updating set photo + self-portrait (or video + Dance + self-portrait) | Opens in Selfie (or Dance with Solo on); thereafter "studioMode" is the only key written |
| Onboarding | Fresh install (delete the app) | Launch | Three pages with dots: DUO STUDIO value page with the INSIDE / OUTSIDE illustration; "Six modes. Two groups." list; "Pick a look." skin list; "Start shooting" opens the camera and only then asks for camera permission; not shown again |
| Skins | Skin button in the top bar / onboarding page 3 | Tap each of Studio, Mono, Vintage, Modern, Pop | Both screens (and open sheets) re-theme live; the row shows "IN USE"; the choice survives relaunch; Vintage and Modern turn the inner display light |
| Light skins over video | Vintage and Modern, any mode | Watch the preview, top bar chips, skeleton, outer display, countdown, REC badge and teleprompter | Everything drawn over video or on the outer display stays readable (near-white text on dark scrims, brighter overlay accent, off bones visible); the outer display stays dark |
| Library | Bottom row, "Library" | Open each tab | Poses: 3-column thumbnails + "New pose"; tapping one returns to the camera in Pose mode with it selected; long-press deletes a custom one. Routines: rows with duration / frames / flipped, "Flip L/R", delete, import + the rights line. Scripts and Questions: one row each opening the editor |
| Saved sheet | After a photo or a recording | Take a photo; record a clip; record a dance | "Saved to Photos" with a mode-specific subline; Dance also shows "ROUTINE SCORE nn%" (the same number the outer display shows for 4 s); "Shoot again" dismisses; no Share button |
| Frame guide | Frame mode | Watch the preview and the subject view | A safe box drawn on both previews (mirrored on the subject view); the subject view shows a hint ("Step back" / "Come closer" / "Move left" / … / "In frame" — accent when in frame); with the dancing clip, the box turns accent when she is inside it |
| Script editor + teleprompter | Script mode → "Edit" | Type a long script, set the speed, Done, start recording | The subject view shows the script in the top 60% resting at its start; after the countdown it scrolls up at the chosen pt/s; the speed readout matches the slider |
| Countdown + recording | Record button | Tap it | 3, 2, 1 on the subject view (crossfade; none with Reduce Motion), then "REC 00:01…" on the inner top bar and the subject view; gesture HUD/legend hidden; hand gestures do nothing; the button shows a square; tapping during the countdown cancels it |
| Recording saved | Record button, then tap it again | Stop, grant the add-only Photos prompt | Photos shows a portrait video with the filter/contrast you had set baked in. **Simulator: no audio** (no microphone). Temp files are gone |
| Stick-figure fallback | Remove `SimulatorSample.mp4`, any video mode | Tap record | After the countdown an alert reads "Recording isn't supported in this simulator mode." and the phase returns to idle |
| Dance import | Dance mode → "+ Import video" | Pick a short (< 90 s) dance video | "Importing N%" counts up, then a "Routine 1" chip is selected; a > 90 s video shows "That video is longer than 90 seconds."; the ghost (dashed) shows the routine's opening pose |
| Dance recording | Dance mode → record | Record along | The ghost skeleton moves in time with the reference music (audible from the speaker), the live skeleton + match % show over it, recording auto-stops at the video's end, then "ROUTINE SCORE nn%" shows for 4 s; the saved clip has the reference audio and no mic audio |
| Flip / delete routine | Long-press a routine chip | "Flip left/right"; then "Delete" | The chip gains "(flipped)" and the ghost mirrors; delete removes the chip and its file |
| Interview guide (simulator) | Interview mode (always partner: the Solo toggle is absent) | Add questions via the card's "Edit" (one per line), step with the chevrons, record 5 s, stop | The inner preview is a 9:16 split: the clip on top, the same clip flipped on the bottom; the card shows "1/N"; the saved video is portrait with both halves; the outer display shows only the plain mirrored preview + countdown + REC (no skeleton, no %). With the stick-figure fallback the "can't record both cameras" line shows and recording fails with the simulator alert |
| Interview guide (device) | Real Duo | Same, with the microphone allowed | Guest on top, interviewer on the bottom, audio present; the question card works during recording; on a phone without multi-cam support the notice appears and only the guest is recorded full-frame |
| Backgrounding | During a recording | Go to the home screen and back | The recording was stopped and saved (or an error shown), never left running |
| Camera-denied state | N/A in simulator | — | Can only be exercised by denying the camera prompt **on a real device** — the simulator's synthetic path bypasses `CameraService.requestAuthorization()` entirely (see `StudioModel.requestCameraAccess()`) |

## Postures

Use the simulator's pose/hinge controls (Device menu or the simulator's posture UI) to cycle
through open, closed, book, laptop, and tent postures. Confirm the layout doesn't clip or overlap
the fold in any of them.

## What the simulator CANNOT prove

- No camera: no real exposure/white-balance behavior. With `SimulatorSample.mp4` bundled, pose/hand
  data come from real `VNDetectHumanBodyPoseRequest`/`VNDetectHumanHandPoseRequest` on the clip;
  without it, they come from `SimulatedFrameSource`'s canned data, not Vision.
- Per Apple's Group Labs Q&A, the simulator does not reproduce simultaneous camera content on the
  inner and outer displays — so `CameraCaptureAccessory` can likely only be checked here for
  "compiles and doesn't crash," not for actually showing camera content on a second display.
- The outer display has no touch on real hardware; the simulator can't demonstrate that absence
  either way.

## If it doesn't compile

Also new and entirely unverified: `Sources/Services/MovieRecorder.swift`, `MovieComposer.swift`,
`RoutineImporter.swift`, `Sources/Views/PickedMovie.swift` (every API there carries an UNVERIFIED
marker — see the table in `plan.md`).

The redesign (mode dial, skins, onboarding, Library, Saved/Controls sheets) is equally unverified:
`Sources/Design/Theme.swift` (`@MainActor static var` token lookups, `SkinStore`), `StudioModel.swift`'s
derived `captureMode` / `shootKind` / `videoGuide`, `Sources/Views/StudioView.swift`, `LibraryView.swift`,
`OnboardingView.swift`, `RootView.swift`.

Look at these two files first — they're where the 27.x-only APIs live:

- `Sources/Views/OuterDisplayAccessory.swift`
- `Sources/Views/CameraDirectionAnchor.swift`

## CI

`.github/workflows/duostudio-app.yml` builds the app for the iOS Simulator on a macOS runner
(manual or on push to `duo-studio`/`main`). If the runner's iOS SDK is older than 27.1 it drops
`DUO_DIRECTION_COORDINATOR` and `DUO_SCENE_ACCESSORY` (with a warning), so it only proves the
non-Duo path compiles; the Duo code still needs Xcode 27.1 on a Mac.
