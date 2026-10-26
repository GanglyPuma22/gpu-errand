---
version: alpha
name: GPU Errand site
description: The quiet instrument. One centred frame, soot brackets around white reading sections, real logs and receipts as the pictures, and one lime action per screen.
colors:
  soot: "#0f0f0f"
  soot-2: "#1a1a1a"
  paper: "#ffffff"
  paper-2: "#f2f2f0"
  paper-3: "#e6e6e3"
  ink: "#0f0f0f"
  ink-soft: "#5c5c5c"
  light: "#ffffff"
  light-soft: "#a3a3a3"
  lime: "#dafa9c"
  lime-ink: "#0f0f0f"
typography:
  display:
    fontFamily: Archivo
    fontSize: 88px
    fontWeight: 400
    lineHeight: 1.0
    letterSpacing: -0.03em
  heading:
    fontFamily: Archivo
    fontSize: 40px
    fontWeight: 400
    lineHeight: 1.1
    letterSpacing: -0.02em
  lead:
    fontFamily: Archivo
    fontSize: 26px
    fontWeight: 400
    lineHeight: 1.25
    letterSpacing: -0.01em
  body:
    fontFamily: Archivo
    fontSize: 19px
    fontWeight: 400
    lineHeight: 1.5
  small:
    fontFamily: Archivo
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.5
  code:
    fontFamily: ui-monospace
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.6
rounded:
  none: 0px
spacing:
  margin: 32px
  frame: 58rem
  section: 176px
  module: 104px
components:
  button-primary:
    backgroundColor: "{colors.lime}"
    textColor: "{colors.lime-ink}"
    rounded: "{rounded.none}"
    height: 46px
    padding: 18px
  button-primary-hover:
    backgroundColor: "#e8ffbd"
  fragment:
    backgroundColor: "{colors.paper-2}"
    textColor: "{colors.ink}"
    typography: "{typography.code}"
    rounded: "{rounded.none}"
    padding: 22px
  receipt:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.small}"
    padding: 22px
---

# GPU Errand site

This file describes the look of the GPU Errand site in `docs/`. Follow it for any new page or section. It was written from the built site, after a pass with the Taste Skill (direction "The quiet instrument") and Impeccable's rules.

## Overview

The site sells a careful tool, so it looks careful: few things, set precisely. The idea behind it: **a run's receipt becomes the page.** The first screen holds a real receipt from a real run, the steps show the real job file and log, and the proof section is a table of measured runs. Nothing is decorated; the pictures are the product's own output.

The landing page persuades (one action: copy the install command). Recipe pages are for reading: a soot header with the title, then one white reading column.

## Colors

Soot brackets the page: the hero and the footer, and the header of each recipe page. The middle sections are white, with `paper-2` for fragments and one full-width band (Measured runs). Lime is the only accent and marks the one action on a screen (the Copy button) or the one word that matters in a fragment (`go`). Body text is always full ink on its ground; `ink-soft` is for secondary notes only.

## Typography

One family, Archivo, at two weights (400, 600). Five sizes do all the work: display, heading, lead, body and small. Headlines stay at two lines or fewer at every width. Monospace appears only in real code: job files, logs, commands and file names.

## Layout

One centred frame, 58rem wide, with equal outer margins at every width. Every section hangs from the frame's left edge. Sections are separated by space alone (about 176px on desktop), never by lines. Each section has its own composition: a line with the receipt beside it, a pinned stage, small proof beside text, a table, rows, reading text in two columns.

## Elevation & Depth

None. Surfaces are told apart by a step in tone (`paper` to `paper-2`, `soot` to `soot-2`), never by a shadow or a border.

## Shapes

Square corners everywhere: buttons, fragments, the receipt, the calculator's choices.

## Components

- **Primary button:** lime fill, soot text, square, 46px tall; it presses down 1px when clicked and turns white with "Copied" after a copy.
- **Fragment:** a real piece of the product (job file, plan, log, results folder) on `paper-2`, in the code face, at true size. Mark its root with `data-ui`.
- **Receipt:** a white slip on soot with two-ended rows and a dashed rule above the total. It prints line by line once on load.
- **Cap calculator:** GPU choices as square toggles (selected is ink on paper), two sliders, and one result sentence that uses the runner's own arithmetic.
- **Rows:** two-ended rows, name left in full ink, value right in `ink-soft` at the small size, no lines between them.

## Do's and Don'ts

- Do use real numbers from real runs, and say when and where they came from. Never invent a figure, a customer or a quote.
- Do keep one lime element per screen.
- Do theme the browser's own surfaces: selection in lime, focus rings in the ink (lime on soot), tabular figures in data.
- Don't add eyebrow labels, numbered steps (01, 02), icon cards, gradients, shadows, glass or thin divider lines.
- Don't use monospace for anything that is not code or a log.
- Don't center more than one moment on a page, and don't let any section leave half the frame empty.
- Motion is small: entrances that rise 20px once, the receipt printing, button presses. Everything keeps its place under reduced motion.
