# DuoStudio — design.md

`Hallmark · app-scope: native iOS · genre: atmospheric · theme: custom "monitor" · enrichment: none`

Non-UI logic lives in `plan.md`. This file is the UI/visual/interaction spec — implemented as
written; it is also what the app code is built against.

Visual reference (design canvas): https://claude.ai/artifact/WD2zP3gCq7bmykNEUBwSnt

## Inferred context

- Audience: a photographer holding the open iPhone Duo, and the person being photographed (the
  "model") standing opposite, looking at the outer display.
- Single job: get the model into the same pose as a template, fast, without the photographer
  having to talk them through it — the outer display and hand gestures do that instead.
- Tone: atmospheric, professional field-monitor — a photographer's tool, not a toy. Dark, legible
  at 2–3 m for the model, calm and precise for the photographer up close.

## Concept

A pro field monitor with five runtime skins. The default **Studio** skin: graphite surfaces, one
chartreuse signal, mono readouts. The outer display in particular reads like a director's monitor —
big numbers, no chrome, nothing decorative between the model and the number that tells them whether
they're in position.

## Skins (runtime theming)

`Skin` = `studio | mono | vintage | modern | pop`, chosen in the skin picker (camera Skin button, or
onboarding step 3) and persisted in UserDefaults `"skin"` via `SkinStore.shared`. Every `Theme.Palette`
/ `TypeFace` / `Radius` token keeps its name and resolves against the active skin, so a skin change
re-renders both screens live. Colours are defined as OKLCH in `Sources/Design/Theme.swift` (converted
via `PoseCore.OKLCH`); the sRGB hex targets below are what the OKLCH values were derived from.

| skin | blurb | scheme |
|---|---|---|
| Studio | Graphite field monitor, one signal colour | dark |
| Mono | Pure black and white, editor-style | dark |
| Vintage | Warm paper, film-camera serif | light |
| Modern | Light, airy, one electric blue | light |
| Pop | Night purple and hot pink, made for dance | dark |

Hex targets (OKLCH `L, C, h` used in brackets). Studio is the original palette and is given in OKLCH
only: paper `0.13, 0.004, 260` · paper2 `0.18, 0.005, 260` · paper3 `0.23, 0.006, 260` · rule
`0.30, 0.006, 260` · neutral `0.58, 0.006, 260` · muted `0.74, 0.005, 260` · ink `0.96, 0.003, 260` ·
accent `0.88, 0.19, 125` (chartreuse) · danger `0.70, 0.17, 30`; onAccent = paper.

| token | Mono | Vintage | Modern | Pop |
|---|---|---|---|---|
| paper | #000000 (0, 0, 0) | #efe5cf (0.924, 0.031, 86) | #f6f7f9 (0.976, 0.003, 265) | #1b1033 (0.210, 0.066, 294) |
| paper2 | #141414 (0.191, 0, 90) | #e5d8bb (0.885, 0.041, 87) | #ffffff (1, 0, 90) | #2a1a4d (0.270, 0.090, 294) |
| paper3 | #262626 (0.269, 0, 90) | #d8c7a2 (0.834, 0.053, 86) | #e8ebf0 (0.939, 0.007, 261) | #3a2766 (0.332, 0.106, 294) |
| rule | #3d3d3d (0.360, 0, 90) | #a8916a (0.668, 0.060, 81) | #cfd5de (0.871, 0.014, 258) | #5a4694 (0.454, 0.123, 293) |
| neutral | #8a8a8a (0.633, 0, 90) | #7a6750 (0.526, 0.042, 72) | #7a8494 (0.611, 0.027, 260) | #9d8cc4 (0.676, 0.083, 298) |
| muted | #a3a3a3 (0.715, 0, 90) | #5f4e3b (0.436, 0.037, 70) | #525c6a (0.471, 0.026, 257) | #cdbdea (0.826, 0.064, 301) |
| ink | #ffffff (1, 0, 90) | #2a1f14 (0.249, 0.026, 66) | #0e1116 (0.177, 0.011, 261) | #fff6fb (0.982, 0.012, 343) |
| accent | #ffffff (1, 0, 90) | #b8431f (0.540, 0.159, 37) | #2d5bff (0.551, 0.247, 266) | #ff4fa3 (0.695, 0.223, 355) |
| onAccent | #000000 (0, 0, 0) | #fbf4e4 (0.968, 0.022, 87) | #ffffff (1, 0, 90) | #1b1033 (0.210, 0.066, 294) |
| danger | #fe2c55 (0.647, 0.238, 18) | #7d2a16 (0.406, 0.120, 35) | #e5484d (0.626, 0.193, 23) | #ffd166 (0.880, 0.135, 86) |

Token roles (same in every skin): **paper** base surface · **paper2** elevated (cards, sheets, mode
dial track) · **paper3** button rest fill · **rule** the only separator tone · **neutral** secondary
chrome · **muted** secondary text · **ink** primary text · **accent** the one signal colour: selected
states, primary buttons, shutter ring, focus (≤5% of any screen, never on text blocks) · **onAccent**
text / icons on accent fills · **danger** off bones on inner surfaces — always paired with a thicker
stroke (`Stroke.offBone`), never colour alone.

### Overlay-ink rule

Everything drawn **over live video or on the outer display** must stay readable in every skin, but
`ink` / `muted` / `accent` are dark on Vintage and Modern. So that surface uses a separate, always
dark/near-white set and never the plain tokens:

| token | role | Studio | Mono | Vintage | Modern | Pop |
|---|---|---|---|---|---|---|
| overlayBase | dark base of `scrim` / `scriptScrim` and the outer display background | = paper | #000000 | #2b1d12 (0.245, 0.029, 59), warm brown | #12151b (0.195, 0.013, 264), neutral | = paper (purple) |
| overlayInk | text / icons over video | = ink | #ffffff | #fbf4e4 (0.968, 0.022, 87) | #fafbfc (0.988, 0.002, 248) | = ink |
| overlayAccent | live skeleton, match %, countdown over video | = accent | #ffffff | #e0693f (0.657, 0.159, 39) | #5b82ff (0.642, 0.190, 268) | = accent |
| overlayDanger | off bones over video (`danger` is too dark on Vintage) | = danger | = danger | #ff7a59 (0.729, 0.170, 35) | #ff6369 (0.701, 0.190, 21) | = danger |

Derived: `overlayMuted` = `overlayInk` at 70% · `ghost` (template skeleton, dashed) = `overlayInk` at
70% · `scrim` = `overlayBase` at 55% · `scriptScrim` = `overlayBase` at 80% (denser, so the script stays
readable at 2–3 m over a bright preview). `SubjectView`, `SkeletonOverlay`, `FrameGuideOverlay`,
`TeleprompterView` and the top-bar chips on the preview all use these. (`overlayDanger` is an addition
to the spec's token list, needed because Vintage's `danger` is a dark red.)

The inner display follows the skin's colour scheme (`preferredColorScheme`: light for Vintage /
Modern); the outer display is always dark.

## Type

Per-skin **system font designs only** (no bundled fonts, no dependencies); Dynamic Type text styles on
the inner display, fixed sizes on the outer HUD. Mono and Pop run one weight step heavier.

| skin | body / display | readouts (`label`, `readout`, outer score / label / legend / countdown) |
|---|---|---|
| Studio | `.default` | `.monospaced` |
| Mono | `.default`, heavier | `.monospaced`, heavier |
| Vintage | `.serif` | `.monospaced` |
| Modern | `.rounded` | `.rounded` |
| Pop | `.rounded`, heavier | `.rounded`, heavier |

- **body**: `.body` — inner-display UI text. **title**: `.title2` semibold — sheet / page titles.
  **display**: `.largeTitle` bold — onboarding headline, Saved checkmark. **control**: `.footnote`
  medium — mode dial buttons, summaries, chips, bottom-row captions.
- **label**: `.caption` readout design, medium, uppercase, tracking 1.2 — short readout tags
  ("MATCH", "PHOTO", "FILTER").
- **readout**: `.subheadline` readout design — adjustment values, speed, percentages.
- Outer-display HUD (fixed sizes, not Dynamic Type — read at 2–3 m, not held close):
  - **outerScore**: 96pt semibold — the match %.
  - **outerLabel**: 34pt semibold — filter name / selected parameter / frame hint.
  - **outerToast**: 44pt bold, body design — recognised-gesture toast.
  - **outerLegend**: 22pt medium — the gesture legend row (bigger than `label`, which doesn't read at
    2–3 m).
  - **outerScript**: 40pt semibold, body design — teleprompter text, line spacing `Space.sm`.
  - **outerCountdown**: 180pt bold — the 3-2-1.

No italics, no gradients, no shadows/glows, no glass, no emoji.

## Corner radii

`Radius.card` / `Radius.control` per skin: Studio 14/10 · Mono 12/8 · Vintage 6/4 · Modern 20/14 ·
Pop 24/999 (control = pill; `RoundedRectangle` clamps 999 to half the shorter side, so no separate
Capsule branch). Cards: Library cards, skin rows, legend cards, the question card. Controls: chips, the
mode dial track and its buttons, primary buttons.

## Spacing (4pt scale)

xs 4 · sm 8 · md 16 · lg 24 · xl 32 · xxl 48 · hitTarget 44 · shutter 76.

## Stroke widths (skeleton drawing)

liveBone 6 · ghostBone 4 (dash `[10, 8]`) · offBone 9 · jointDot 10 · shutterRing 4 · frameGuide 3 ·
recordCorner 8 (the record button's inner square) · thumbBone 2 / thumbJoint 4 (Library pose
thumbnails) · swatchRing 3 (skin swatch) · selection 2 (outline on a selected card).

Layout tokens: `teleprompterFraction` 0.6 (share of the outer display the script panel takes) ·
`modePanelHeight` 84 (minimum height of the mode panel row) · `topBarClearance` 64 (space `SubjectView`
keeps at the top when it is the inner preview) · `libraryColumns` 3 · `thumbAspect` 0.75 ·
`illustrationHeight` 180 (onboarding) · `swatch` 36. `Opacity.disabled` 0.4.

## The two displays

### Inner display (photographer) — the camera screen (`StudioView`)

One structure for every mode, top to bottom:

1. **Preview** (rounded `Radius.card`, 16pt side margin) with the **top bar** overlaid. Partner modes:
   full-bleed camera preview (aspect-fill, **not** mirrored — the photographer's own working view)
   with `SkeletonOverlay` on top (sharing its point mapping via `PreviewLayout.aspectFillRect`), the
   Frame box in Frame mode, the 9:16 composite in Interview. **Selfie and Solo video** use
   `SubjectView` itself as the preview (the user is the subject) — same panel, dial and bottom row
   below it; there is no separate minimal self-portrait layout any more.
   - **Top bar** (everything on `scrim` capsules in `overlayInk`, 44pt tall): **Outer**
     (`rectangle.portrait.on.rectangle.portrait`; disabled + hint when no outer display is available
     or the mode shoots from this screen), **Gestures** (`hand.raised` / `hand.raised.slash`),
     **Solo** (`person.crop.square`, only in Frame / Script / Dance), spacer, the **MATCH** readout
     (Pose, Selfie, Dance) or `REC 00:12` while recording (`readout`, `overlayAccent`, ticking once a
     second via `TimelineView(.periodic)`), and the **Skin** button (`paintpalette`, label "Change
     skin"). On state = `overlayAccent` icon and text; off = `overlayInk`. Toggles carry
     `accessibilityValue` On / Off.
2. **Mode panel** (`ModePanelView`, min height 84pt, one row):
   - Pose / Selfie: template chips (`ChipLabel`: `accent` fill + `onAccent` text when selected,
     `paper3` + `ink` otherwise, 44pt) and "+ New pose" (opens the pose editor); custom templates are
     deletable via context menu. Selfie adds the remote-shutter hint under the chips ("Remote shutter:
     volume button, Camera Control or a Bluetooth remote.").
   - Frame: the hint "Hints appear on the outer screen." (Solo: "...on this screen.").
   - Script: the script's first line (or "No script yet" in `muted`), the speed readout ("40 pt/s")
     and an "Edit" chip → `ScriptEditorView`.
   - Dance: routine chips (context menu "Flip left/right" / "Delete"; a flipped routine reads
     "<name> (flipped)") and "+ Import video" (`PhotosPicker`, videos only) which becomes the mono
     readout "Importing 42%" while an import runs.
   - Interview: the question card (`InterviewCardView`, see below) with an "Edit" button.
3. **Mode dial** (`ModeDialView`): two groups labelled `PHOTO` (Pose, Selfie) and `VIDEO` (Frame, Script,
   Dance, Interview) in `label` / `neutral`; each group is a row of buttons on a `paper2` track
   (`Radius.control`); selected = `accent` fill with `onAccent` text; 44pt minimum height; selected
   carries the `.isSelected` trait. Under it the mode's one-line `summary` in `muted` (reserved at
   three lines so the layout doesn't jump). The whole dial is disabled while a recording runs.
4. **Bottom row**: **Library** (`square.grid.2x2` + caption) · the shutter / record button (76pt
   circle, accent ring, haptic on press; inner `ink` circle, or while recording a rounded square of
   half size with corner `Stroke.recordCorner`; labels "Take photo" / "Start recording" / "Stop
   recording"; disabled only while saving, a tap during the countdown cancels it) · **Controls**
   (`slider.horizontal.3` + caption).

Other behaviour:
- **Camera denied**: centred message + "Open Settings" button.
- **Shutter flash**: full-screen `paper` overlay, opacity pulse over `Motion.shutterFlash` (skipped
  under Reduce Motion).
- **Idle timer**: disabled for as long as `StudioView` is on screen, re-enabled on disappear — same
  pattern as Across's `ConversationView`; needed most when the phone sits on a stand.
- Library is presented as a **sheet** (not a full-screen cover) on purpose: `StudioView.onDisappear`
  stops the camera and a cover might trigger it.

**Pose editor** (`PoseEditorView`, sheet): a frozen snapshot of the preview — taken once, on
appear, not the live feed — dimmed to 40% opacity, with the selected template's skeleton drawn over
it and a 44pt drag handle per present joint. Frozen so the backdrop (and the handles positioned
against it) don't shift under the photographer's finger mid-drag; "Use live pose" still pulls the
*current* live pose into the editable skeleton on demand.

**Controls** (`ControlsView`, sheet, replaces the old Adjustments sheet): title "Controls", Done.
Sections `FILTER` (chips for every filter), `ADJUST` (exposure / contrast / warmth sliders with mono
readouts; same `setFilter` / `setAdjustment` path a hand gesture uses), `HAND GESTURES` (2×2 legend
cards: "Swipe palm — Change filter", "OK sign — Zoom their view", "Hold fist — Next setting", "Point
up/down — Adjust it"), then the toggles "Show outer display" and "Hand gestures".

**Library** (`LibraryView`, sheet): Back button, title "Library", four tabs (chips) — Poses: 3-column
grid of thumbnails (`PoseThumbnailView`, thin accent skeleton) plus a "New pose" card; tap selects the
template and returns to the camera in Pose mode; context menu: Edit (built-ins edit as a new pose) and
Delete for custom ones. Routines: rows with name, "0:24 · 240 frames · Flipped", "Flip L/R" and delete;
a "+ Import video" button; the line "Use videos you have the rights to. Moves are read on this iPhone,
nothing is uploaded." Scripts: the single script as one row (first line, "N words · about M s at 40
pt/s") → `ScriptEditorView`. Questions: the question set as one row (first question, count) →
`QuestionsEditorView`.

**Saved** (`SavedView`, medium sheet after a successful photo or video save): checkmark, "Saved to
Photos", a subline by mode — photo "Filter and contrast baked in."; Dance "Original music added back
in." plus "ROUTINE SCORE 82%" (the real score); Interview "Guest on top, you below."; other video
"Filter baked in, ready to post." — and a primary "Shoot again" button (dismiss). No Share button (the
saved temp file is gone). The routine score still also shows on the outer display for `Motion.scoreHold`.

**Skin picker** (`SkinPickerSheet`, from the Skin button; same content is onboarding's last page):
"Pick a look." / "Changes both screens. Switch any time from the camera." and five rows — a swatch (the
skin's paper with an accent ring), title, blurb, and an "IN USE" mark on the current one. Tapping a row
applies it immediately (live). Done.

**Onboarding** (`OnboardingView`, first launch only, UserDefaults `"hasOnboarded"`): three pages with
page dots and a primary button. 1: kicker "DUO STUDIO", "Your subject finally sees the shot.", the
body line, and an illustration of two rounded rectangles (INSIDE: you frame / OUTSIDE: they watch);
"Continue". 2: "Six modes. Two groups." — the PHOTO and VIDEO lists, each mode with a short phrase;
"Continue". 3: the skin picker; "Start shooting". The camera permission prompt comes after onboarding.

### Outer display (the model) — `SubjectView`

Non-interactive (the outer display takes no touch): mirrored preview + overlay together
(`scaleEffect(x: -1)` on the combined stack, not the image alone, so the skeleton mirrors with it),
scaled by `state.outerZoom` around its centre.

- **Top**: match % in `outerScore` (accent), or "—" when no person is detected.
- **Bottom HUD**: filter name + the currently selected parameter's value, in `outerLabel` on a
  `scrim` background band.
- **Centre toast**: the last recognised gesture (icon + word) in `outerToast`, crossfading in/out,
  clearing after 1.5 s.
- **Gesture legend**: a small persistent row, SF Symbols + one word each, in `outerLegend` — swipe
  palm = filter, OK sign = zoom, fist = setting, point = adjust. "OK sign", not "pinch": the
  classifier only recognises `.pinch` when the other three fingers are extended (an OK sign) — an
  ordinary pinch with the rest of the hand curled reads as `.fist` instead, so the word has to match
  what actually triggers it.
- Always dark, regardless of system appearance and of the light skins — the outer display is a
  monitor. It follows the skin's `overlayAccent` / `scrim` / type design (see the overlay-ink rule), and
  uses `overlayInk` / `overlayMuted` for all text.

## Selfie and Solo (self-portrait)

See `plan.md` for how `captureMode` derives from the mode dial. Visually: Selfie (photo) and Solo video
(Frame / Script / Dance with the top-bar Solo toggle on) use the same camera screen as every other mode,
with `SubjectView` as the preview — mirrored preview, template + live skeleton, big match %, HUD, gesture
toast and legend — and the same mode panel, dial and bottom row below it. The outer accessory is
disabled (`isOuterEnabled` forced `false`) since nobody is standing opposite to look at it.

**Solo toggle** (deviation from the design canvas, on purpose): dance and script are often shot alone on
a stand, so instead of losing self-portrait video the video modes that support it get a "Solo" toggle in
the top bar (persisted `"soloVideo"`). Interview is always partner (needs both cameras of the open Duo).

No self-timer, no countdown for photos in any mode — a physical remote (volume buttons, Camera
Control, a Bluetooth remote) is the self-portrait shutter, since there's no one else to press it.
(Video has its 3-2-1 countdown — see "Video modes".)

## Video modes

Frame, Script, Dance and Interview are the VIDEO group of the mode dial. See `plan.md` "Video mode"
for the logic. Recorded video bakes in the current filter + contrast; gestures are off while the
countdown / recording runs; the dial, Solo and Library are disabled during a recording.

- **Interview**: the preview area shows the recorded 9:16 split-screen composite (guest on top,
  interviewer below; the plain camera preview in the guest-only fallback), with no skeleton. The
  **question card** (`InterviewCardView`, in the mode panel): the current question in `body` on
  `paper2`, radius `Radius.card`; `chevron.left` / `chevron.right` buttons (44pt, labels "Previous
  question" / "Next question", dimmed at the ends) around it; a mono "2/7" readout in `label` /
  `neutral` under the question; an "Edit" button opening `QuestionsEditorView`. No questions: "Add
  questions to keep the interview on track" in `muted`. When the iPhone can't record both cameras, a
  centred `label` / `muted` line reads "This iPhone can't record both cameras — recording the guest
  only." The card stays usable while recording.
- **`ScriptEditorView`** (sheet, medium/large detents): a `TextEditor` on `paper2`, a "SCROLL SPEED"
  label with a mono readout ("40 pt/s") and an accent `Slider` (10…120, step 5), Done.
- **`QuestionsEditorView`** (sheet, medium/large detents): a `TextEditor` on `paper2`, one question
  per line, Done.

### Outer display (`SubjectView`) — video modes

Mirrored preview as in photo kind. Inside the mirrored stack (so it mirrors with the image): the
Frame guide's **safe box** — `Stroke.frameGuide` (3pt), `rule` colour, `accent` once the hint is
"In frame". The top readout depends on the guide (not mirrored — readable text):

- **Frame**: the hint in `outerLabel` on a scrim capsule — "Step into frame", "Step back", "Come
  closer", "Move left", "Move right", "In frame" (accent only for "In frame"; left/right are from the
  subject's point of view).
- **Script**: a `TeleprompterView` panel across the top 60% on `scriptScrim`, text in `outerScript`
  `ink`, line spacing `Space.sm`, sliding up at the chosen speed while recording and resting at the
  start when idle. Empty script: "Write a script on the inner screen" in `muted`.
- **Dance**: the match % as in photo kind (ghost skeleton dashed, live skeleton solid); after a
  recording, the routine score in `outerScore` accent over a "ROUTINE SCORE" caption (`outerLegend`,
  tracked, `muted`) for `Motion.scoreHold` (4 s).

- **Interview**: the mirrored guest preview only - no skeleton, no match %, no top readout; just the
  countdown, the REC badge and (when idle) the usual filter HUD.

Also: the centred **countdown** number in `outerCountdown` accent, crossfading per number (no
animation under Reduce Motion); a small `REC 00:12` badge in `outerLabel` on a scrim capsule at the
top-trailing corner while recording; the gesture toast, HUD band and legend are hidden during the
countdown and the recording and shown otherwise.

## Motion

Exactly the motion primitives in `Theme.Motion`: `micro` (0.10s, button press scale 0.98),
`short`/`easeOut` (0.22s, `(0.16, 1, 0.3, 1)` — the outer toast and countdown crossfade), `reduced`
(0.15s, Reduce Motion fallback, opacity-only), `shutterFlash` (0.12s), plus the video-mode timings
`countdownStep` (1.0s per countdown number) and `scoreHold` (4.0s routine score). No other
durations, no spring animations, no parallax. The teleprompter's continuous scroll is content, not
decoration, so Reduce Motion does not stop it.

## Gesture legend (reference)

| Hand shape | Action |
|---|---|
| Swipe open palm | Change filter (direction = swipe direction) |
| OK sign (pinch with the other three fingers extended) | Zoom the outer preview only (inspection zoom — the captured photo is never zoomed) |
| Hold fist | Select next parameter (exposure → contrast → warmth → …) |
| Hold point up / point down | Adjust the selected parameter up / down, repeating while held |

## Accessibility

Every icon-only button has an `accessibilityLabel` ("Take photo" for the shutter, "Start recording" /
"Stop recording" for the record button, "Change skin", "Delete <routine>", etc.); the mode dial's
buttons carry `.isSelected`, the top-bar toggles an On / Off value, the onboarding dots "Page 2 of 3". Inner-display text uses Dynamic Type styles
(`.body`, `.caption`, `.subheadline`); the outer HUD deliberately does not (fixed sizes, read at a
distance). The match % readout carries an `accessibilityValue` with the percentage. Off bones are
never colour-only — the thicker `Stroke.offBone` line width is the primary cue, `danger` colour is
secondary.

## Copy rules

Specific verbs, curly quotes and … ellipsis, no "Oops", no exclamation marks — same rules as
Across's `design.md`. The error alert's title is the message itself ("Couldn't save the photo.",
"Couldn't save the video.", "That video is longer than 90 seconds.", "Couldn't import that video.",
"Import a dance video first."), with a single OK button.
