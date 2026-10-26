---
layout: home
title: GPU Errand
description: Run Claude Code or Codex jobs on a Google Colab GPU from the command line, with a hard compute-unit cap, checked results and ready recipes for game music, sound effects and headless Godot capture.
---

**Let your coding agent run jobs on a Google Colab GPU, with a hard spending cap and a receipt for every run.**

Your agent writes a small job file. Your always-on machine starts a Colab GPU, runs the job, brings the results back with checksums and stops the GPU. It can't run past the compute units you allowed, and no credential ever reaches the runtime.

```bash
pipx install git+https://github.com/GanglyPuma22/gpu-errand
gpu-errand plan examples/jobs/sound-effects.json   # every step, with the caps
COLAB_SESSION=sfx-1 gpu-errand run examples/jobs/sound-effects.json
```

## What it's for

- **Game audio from text:** [music with ACE-Step 1.5](recipes/game-music-ace-step-colab/) and [sound effects with Stable Audio Open](recipes/sound-effects-stable-audio-open-colab/), with pinned model versions and a receipt per batch.
- **Headless game capture:** [record Godot gameplay clips and stills on a GPU](recipes/headless-godot-capture-gpu/) with no screen attached.
- **Any CUDA command** from a git repository: the `shell` job type.

## What makes it safe to hand to an agent

- **A unit ceiling that holds.** The runner reads Colab's hourly rate once the GPU is granted and refuses an unknown or too-high rate. It stops the runtime at the time or unit cap, on error, and if anything hangs.
- **Checked results.** Every file is checked against a SHA-256 list made on the runtime. Missing, silent or broken model outputs fail the run.
- **Nothing secret on the runtime.** Only the job's commit and the scripts go there. Gated Hugging Face weights arrive through short-lived links made on your machine.
- **Your go first.** The agent skill shows you the plan and the cap before it spends anything, and the queue service only runs after you type `go`.

## Measured costs (October 2026)

| Job | GPU | Time | Compute units |
|---|---|---|---|
| 3 sound effects, 5 s each | L4 | 9 min | 0.21 |
| 60 s music cue + seamless loop | A100 | 5 min | 0.44 |
| 2 Godot gameplay clips | L4 | 3.3 min | about 0.02 |

Colab sold 100 units for about $10 at the time, so these cost a few cents each. Check Colab's pricing page for current numbers.

## Questions

**Is this a Google product?** No. It's an independent open-source tool that drives Google's own [Colab CLI](https://github.com/googlecolab/google-colab-cli).

**Does it work on the free Colab tier?** No. Colab allows remote shells only on paid accounts with compute units.

**How is it different from Modal, RunPod or SkyPilot?** Those rent GPUs by the second. GPU Errand is for people who already have Colab units and want an agent to use them safely.

**Which agents does it work with?** Claude Code (plugin), Codex (skill folder) and anything that can run a shell command.

[Source, install and docs on GitHub](https://github.com/GanglyPuma22/gpu-errand) · MIT licensed
