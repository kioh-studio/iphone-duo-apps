# FaceToFaceCaption — design.md

`Hallmark · app-scope: native iOS (no web macrostructure/nav/footer) · genre: atmospheric · theme: custom "subtitle" · enrichment: none · pre-emit critique: P4 H5 E4 S5 R5 V4`

Non-UI logic lives in `plan.md`. This file is the UI/visual/interaction spec — implemented as
written; it is also what the app code is built against.

## Inferred context

- Audience: two people without a shared language at one table (travellers, clinics, shops,
  business trips).
- Single job: read the other person's words instantly.
- Tone: atmospheric — dark, calm, legible across a table.

## Concept

Cinema subtitles on a café table — warm white text on warm charcoal, one amber signal. Always
dark: a deliberate single look (OLED, reads at distance, doesn't glare at the person opposite).

## Colour tokens

OKLCH, defined once in `Theme.swift`, converted to RGB via `CaptionCore.OKLCH`:

| Token | Value | Role |
|---|---|---|
| paper | `oklch(14% 0.010 70)` | base surface |
| paper2 | `oklch(19% 0.012 70)` | elevated (sheets, banner) |
| paper3 | `oklch(24% 0.012 70)` | button rest fill |
| rule | `oklch(31% 0.010 70)` | the only separator tone |
| neutral | `oklch(58% 0.010 75)` | tags, previous caption, volatile tail |
| muted | `oklch(74% 0.010 80)` | secondary language line |
| ink | `oklch(95% 0.012 90)` | subtitle white |
| accent | `oklch(84% 0.15 88)` | subtitle amber: listening outline, level meter, pending dots, focus. ≤5% of any screen, never on text blocks |
| danger | `oklch(72% 0.16 32)` | always paired with an SF Symbol + words, never colour alone |

## Type

Native system faces only — captions can be any script, so system fonts are a correctness
requirement, not a style choice.

- **display**: New York (`.system(size:, design: .serif)`, regular, roman) — wordmark "Across" +
  setup headline only.
- **caption**: SF Pro semibold 44pt, scaled with Dynamic Type (`@ScaledMetric(relativeTo:
  .largeTitle)`), line limit 5, `minimumScaleFactor` 0.5.
- **previous caption**: SF Pro regular 24pt, neutral.
- **body**: SF Pro 17 regular (transcript primary, ink); secondary 15 regular (muted).
- **label** (mono outlier, two roles only): SF Mono caption size, uppercase, tracking 1.2 — the
  language chip (`VI ⇄ EN`) and speaker tags (`YOU` / `THEM`).

No italics anywhere. No gradients, no shadows/glows, no glass, no emoji.

## Spacing (4pt scale)

xs 4 · sm 8 · md 16 · lg 24 · xl 32 · xxl 48. Fold band 28pt.

## Motion

Exactly three primitives:

1. Caption crossfade, 220 ms, ease-out curve `(0.16, 1, 0.3, 1)`, opacity only.
2. Live level meter driven by the real mic level (functional, not decorative).
3. Pending-translation dots (functional loader).

Button press: scale 0.98 / 100 ms. Reduce Motion → opacity-only, ≤150 ms, meter updates without
animation. Haptic: selection feedback when the turn changes. Silent success — no toasts except the
undo after Clear.

## Screens

### A. Language setup

First screen each launch; also reachable as a sheet from the language chip.

- Leading-aligned (not centred). Wordmark "Across" (display, 34). Line (muted): "Two languages,
  one table. Everything stays on this iPhone."
- Rows, no cards, separated by `rule` hairlines: "You speak" [menu picker], swap button (SF Symbol
  `arrow.up.arrow.down`, 44×44), "They speak" [menu picker]. Language names shown in the device
  language.
- Readiness list, one row each with an SF Symbol + text:
  - "\<Language\> speech" — Ready / Needs download / Downloading 42%
  - "\<A\> ↔ \<B\> translation" — Ready / Needs download / Not available
- Speech not available (either side): "\<Language\> speech isn't available on this iPhone. Pick
  another language."
- Translation not available: "\<A\> ↔ \<B\> can't be translated on this iPhone yet. Pick another
  language."
- Primary button, bottom: "Download languages" when anything is missing (downloads speech models,
  then asks the system to download the translation languages), otherwise "Start conversation".
- Mic denied: "Microphone access is off. Across needs it to hear the conversation." + button "Open
  Settings".
- All setup notices lead with the `exclamationmark.triangle` symbol in danger; the message text
  itself stays ink. The primary button is disabled (opacity 0.4) while checks or downloads are
  still running and when either language or the pair is unavailable.

### B. Conversation — separate screens (a facing display is connected)

My screen, full height = My side. The facing display shows the Partner view full screen.

### C. Conversation — shared table (no facing display)

Top half = Partner view rotated 180° (with the partner's own turn button), 28pt fold band, bottom
half = My side. Screen stays awake.

### Partner view

Leading-aligned column anchored to the bottom (subtitle position): previous caption (neutral, 24,
≤2 lines) above current caption (ink, 44). Pending translation → three amber dots under the
previous caption. Idle (nothing said) → the partner's language name written in that language
(e.g. "English", "Tiếng Việt") in display 34 neutral + a `waveform` symbol. In shared-table mode,
the partner's turn button sits at its bottom, labelled with their language name in their language.

### My side

- Header row: language chip (mono `VI ⇄ EN`, opens setup sheet) leading, "Clear" text button
  trailing (clears instantly; bottom undo bar "Conversation cleared · Undo" for 5 s).
- Transcript: rows leading-aligned, spacing lg, newest at bottom, auto-scrolls. Row = mono speaker
  tag (`YOU` / `THEM`, neutral) · primary line in my language (ink 17: my lines → original, their
  lines → translation) · secondary line (muted 15: the other language). Volatile tail shown in
  neutral. Pending → amber dots. Failed → danger triangle symbol + "Couldn't translate." + "Retry"
  button.
- Empty state: "Nothing said yet." / shared: "Lay the phone between you. They read the top half;
  you read this one." / separate: "They read the facing screen; you read this one."
- Bottom: my turn button ("Speak Vietnamese"); in separate-screens mode both turn buttons sit side
  by side (the facing display can't take touch).

### Turn button

Capsule, height 56, paper3 fill, ink label, SF Symbol `mic`, one line (`lineLimit` 1,
`minimumScaleFactor` 0.8).

States: default · pressed (scale 0.98) · focus (system ring) · listening (1.5pt accent outline,
label "Done", inline level meter) · finishing (small progress + "Finishing") · disabled (opacity
0.4, while the other side is finishing or languages aren't ready) · error (surfaced in the banner)
· success (silent).

### Error banner

Top of My side, paper2, danger symbol, three-part copy:

- Speech model missing: "\<Language\> speech isn't downloaded. Captions need it to hear this
  side." + "Set up languages"
- Mic stopped: "The microphone stopped. Another app may be using it. Tap Speak to try again."
- Translation missing: "\<A\> ↔ \<B\> translation isn't downloaded." + "Set up languages"

## Copy rules

Specific verbs, curly quotes and … ellipsis, no "Oops", no exclamation marks.
