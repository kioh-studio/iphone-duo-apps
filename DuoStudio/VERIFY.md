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

Drop an upright portrait clip of a person (full body visible, ideally doing the hand gestures) at
`DuoStudio/Resources/SimulatorSample.mp4`, re-run `xcodegen generate`, and run. The Simulator then
loops it as the camera feed and runs the real Vision body/hand detection on it. Without the file it
falls back to the canned stick figure. The file is git-ignored and excluded from device builds. To
convert, bake in rotation and shrink:

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
| Template strip | Main screen | Scroll/tap the template strip | Selecting a different built-in template updates the ghost skeleton |
| Pose editor | Template editor | Drag joints, tap "Use live pose", Save, then delete a custom template | Joints move under drag; "Use live pose" snaps to the current synthetic pose; Save persists it into the strip; delete removes it |
| Adjustments sheet | Adjustments sheet | Open the sheet, move each slider | Sliders track touch; the HUD readout (exposure/contrast/warmth) updates to match |
| Partner ↔ self-portrait switch | Mode toggle | Switch modes | Outer display content turns off in self-portrait mode (per `StudioModel.isOuterEnabled`); main screen shows the `SubjectView` composition directly |
| Shutter → Photos | Main screen | Tap shutter, grant the add-only Photos prompt | A photo is saved; opening it in Photos shows the synthetic frame (clip frame or stick figure), not a real camera image |
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

Look at these two files first — they're where the 27.x-only APIs live:

- `Sources/Views/OuterDisplayAccessory.swift`
- `Sources/Views/CameraDirectionAnchor.swift`
