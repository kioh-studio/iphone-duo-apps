# DuoStudio — design.md

`Hallmark · app-scope: native iOS · genre: atmospheric · theme: custom "monitor" · enrichment: none`

Non-UI logic lives in `plan.md`. This file is the UI/visual/interaction spec — implemented as
written; it is also what the app code is built against.

## Inferred context

- Audience: a photographer holding the open iPhone Duo, and the person being photographed (the
  "model") standing opposite, looking at the outer display.
- Single job: get the model into the same pose as a template, fast, without the photographer
  having to talk them through it — the outer display and hand gestures do that instead.
- Tone: atmospheric, professional field-monitor — a photographer's tool, not a toy. Dark, legible
  at 2–3 m for the model, calm and precise for the photographer up close.

## Concept

A pro field monitor: graphite surfaces, one chartreuse signal, mono readouts. The outer display in
particular reads like a director's monitor — big numbers, no chrome, nothing decorative between
the model and the number that tells them whether they're in position.

## Colour tokens

OKLCH, defined once in `Sources/Design/Theme.swift`, converted to RGB via `PoseCore.OKLCH`:

| Token | Value | Role |
|---|---|---|
| paper | `oklch(13% 0.004 260)` | base surface |
| paper2 | `oklch(18% 0.005 260)` | elevated (sheets, HUD scrim base) |
| paper3 | `oklch(23% 0.006 260)` | button rest fill |
| rule | `oklch(30% 0.006 260)` | the only separator tone |
| neutral | `oklch(58% 0.006 260)` | secondary chrome, disabled hints |
| muted | `oklch(74% 0.005 260)` | secondary text |
| ink | `oklch(96% 0.003 260)` | primary text; also the ghost skeleton's base (at 70% opacity) |
| accent | `oklch(88% 0.19 125)` | chartreuse signal: live skeleton, match %, shutter ring, focus. ≤5% of any screen, never on text blocks |
| danger | `oklch(70% 0.17 30)` | off bones — always paired with a thicker stroke (`Stroke.offBone`), never colour alone |
| ghost | `ink.opacity(0.7)` | template skeleton, dashed |
| scrim | `paper.opacity(0.55)` | HUD text legibility over live video |

## Type

- **body**: `.system(.body)` — inner-display UI text, Dynamic Type.
- **label**: `.system(.caption, design: .monospaced).weight(.medium)`, uppercase, tracking 1.2 —
  short readout tags ("MATCH", "FILTER").
- **readout**: `.system(.subheadline, design: .monospaced)` — adjustment values, template names.
- Outer-display HUD (fixed sizes, not Dynamic Type — read at 2–3 m, not held close):
  - **outerScore**: `.system(size: 96, weight: .semibold, design: .monospaced)` — the match %.
  - **outerLabel**: `.system(size: 34, weight: .semibold, design: .monospaced)` — filter name /
    selected parameter value.
  - **outerToast**: `.system(size: 44, weight: .bold)` — recognised-gesture toast.

No italics, no gradients, no shadows/glows, no glass, no emoji.

## Spacing (4pt scale)

xs 4 · sm 8 · md 16 · lg 24 · xl 32 · xxl 48 · hitTarget 44 · shutter 76.

## Stroke widths (skeleton drawing)

liveBone 6 · ghostBone 4 (dash `[10, 8]`) · offBone 9 · jointDot 10.

## The two displays

### Inner display (photographer)

Full-bleed camera preview (aspect-fill, **not** mirrored — this is the photographer's own working
view) with the skeleton overlay drawn on top (`SkeletonOverlay`, sharing its point mapping with the
preview via `PreviewLayout.aspectFillRect`).

- **Top bar**: outer-display toggle (`rectangle.portrait.on.rectangle.portrait`, disabled + hint
  when no outer display is available), gesture toggle (`hand.raised`), match % readout (label +
  accent number).
- **Bottom**: horizontally scrolling template strip (names in `readout`; "Edit" and "+ New" open
  the pose editor; custom templates are deletable via context menu), the shutter (76pt circle,
  accent ring, haptic on press), and a button opening the adjustments sheet.
- **Camera denied**: centred message + "Open Settings" button.
- **Shutter flash**: full-screen `paper`-coloured overlay, opacity pulse over `Motion.shutterFlash`
  (skipped under Reduce Motion — an instant cut instead).

### Outer display (the model) — `SubjectView`

Non-interactive (the outer display takes no touch): mirrored preview + overlay together
(`scaleEffect(x: -1)` on the combined stack, not the image alone, so the skeleton mirrors with it),
scaled by `state.outerZoom` around its centre.

- **Top**: match % in `outerScore` (accent), or "—" when no person is detected.
- **Bottom HUD**: filter name + the currently selected parameter's value, in `outerLabel` on a
  `scrim` background band.
- **Centre toast**: the last recognised gesture (icon + word) in `outerToast`, crossfading in/out,
  clearing after 1.5 s.
- **Gesture legend**: a small persistent row, SF Symbols + one word each — swipe palm = filter,
  pinch = zoom, fist = setting, point = adjust.
- Always dark, regardless of system appearance — the outer display is a monitor, not a themed
  screen.

## Self-portrait mode

See `plan.md` for `CaptureMode` and the camera-selection logic. Visually: on the main (and only)
screen, self-portrait mode shows the same `SubjectView` composition described above — mirrored
preview, template + live skeleton, big match %, HUD, gesture toast, and legend — with a thin
control layer added on top for the person using the phone alone: the shutter, the mode switch, and
a template-picker button. There is no separate "inner" screen in this mode; the outer accessory is
disabled (`isOuterEnabled` forced `false`) since nobody is standing opposite to look at it.

**Mode switch**: a two-icon segmented control in the top bar — `person.2` (Partner mode) /
`person.crop.square` (Self-portrait mode) — accessibility labels "Partner mode" / "Self-portrait
mode". Switching modes is instant; no confirmation, no lost state (each mode keeps its own last
template/filter/adjustments via the shared `StudioState`).

No self-timer, no countdown in either mode — a physical remote (volume buttons, Camera Control, a
Bluetooth remote) is the self-portrait shutter, since there's no one else to press it.

## Motion

Exactly the motion primitives in `Theme.Motion`: `micro` (0.10s, button press scale 0.98),
`short`/`easeOut` (0.22s, `(0.16, 1, 0.3, 1)` — the outer toast crossfade), `reduced` (0.15s,
Reduce Motion fallback, opacity-only), `shutterFlash` (0.12s). No other durations, no spring
animations, no parallax.

## Gesture legend (reference)

| Hand shape | Action |
|---|---|
| Swipe open palm | Change filter (direction = swipe direction) |
| Pinch | Zoom the outer preview only (inspection zoom — the captured photo is never zoomed) |
| Hold fist | Select next parameter (exposure → contrast → warmth → …) |
| Hold point up / point down | Adjust the selected parameter up / down, repeating while held |

## Accessibility

Every icon-only button has an `accessibilityLabel` ("Take photo" for the shutter, "Partner mode" /
"Self-portrait mode" for the mode switch, etc.). Inner-display text uses Dynamic Type styles
(`.body`, `.caption`, `.subheadline`); the outer HUD deliberately does not (fixed sizes, read at a
distance). The match % readout carries an `accessibilityValue` with the percentage. Off bones are
never colour-only — the thicker `Stroke.offBone` line width is the primary cue, `danger` colour is
secondary.

## Copy rules

Specific verbs, curly quotes and … ellipsis, no "Oops", no exclamation marks — same rules as
Across's `design.md`.
