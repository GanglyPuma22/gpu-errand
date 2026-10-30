# GPU Errand

**Let Claude Code, Codex or any coding agent run jobs on a Google Colab GPU, with a hard spending cap and a receipt for every run.**

GPU Errand runs a job on a Google Colab GPU straight from the command line. Your agent writes a small job file; your always-on machine starts a Colab GPU, runs the job, brings the results back with checksums and stops the GPU. It can't run past the compute units you allowed.

It ships with recipes for **game music (ACE-Step 1.5)**, **sound effects (Stable Audio Open)** and **headless Godot gameplay capture**. Any repository command that needs CUDA works too.

> GPU Errand is an independent project. It is not made by or affiliated with Google. It drives Google's own [Colab CLI](https://github.com/googlecolab/google-colab-cli) and needs a paid Colab account.

## Why I made this

I make a small game with coding agents. I wanted them to do GPU work while I was away: record gameplay clips for a review, make a batch of sword-swing sounds, try a music cue. Colab already had GPUs and I had compute units. What I didn't have was a way to hand an agent a GPU without worrying about it. Would it leave a runtime running all night? Would it copy my tokens somewhere? Would it say "done" when the run had failed?

So the runner refuses to spend without a ceiling. It never sends a credential to the runtime, and it only counts a run as done when every file that came back matches what the runtime wrote.

## What you get

- **A spending cap that holds.** Each job can set `max_units` (model runs must) and optionally `max_rate`. The runner reads Colab's hourly rate once the GPU is granted. It refuses an unknown or too-high rate, and it stops the runtime at the time or unit ceiling, whichever comes first. It also stops the runtime on any error, and keeps retrying if a stop fails.
- **Results you can trust.** The runtime makes a SHA-256 list of its outputs, and the host checks each file after copying it back. Model runs also write `receipt.json` with each output's hash, length, peak and loudness. A run with missing, silent or broken outputs fails.
- **No secrets on the runtime.** Only the job's commit (from `git archive`, no `.git`) and the scripts go there. For gated Hugging Face models, the host turns its own login into short-lived download links, and the token stays home.
- **A queue, or run now.** Agents can push jobs to a queue branch in a private repo, and a small service on your always-on machine works through them after you type `go`. Or run one job right away, beside the queue.
- **Ready recipes** for audio and game capture, with every model revision pinned.

## Quick start

On your always-on machine (Linux, a server, or WSL):

```bash
pipx install git+https://github.com/GanglyPuma22/gpu-errand
pipx install google-colab-cli        # Google's Colab CLI
colab --auth=oauth2 usage            # sign in as its README says; this shows your units
```

Check a job, read its plan, then run it:

```bash
gpu-errand validate examples/jobs/hello-gpu.json
gpu-errand plan examples/jobs/hello-gpu.json     # every step, with the caps
COLAB_SESSION=hello-1 gpu-errand run examples/jobs/hello-gpu.json
```

Work that needs no GPU (tests, headless sims, benchmarks) can take a cheaper CPU-only runtime: set `"gpu": "CPU"` (see [examples/jobs/hello-cpu.json](examples/jobs/hello-cpu.json)).

Results land in `~/.gpu-errand/results/<id>-<time>/out/`, with the runner's own logs beside them. Set `RESULTS_REPO=you/private-repo` and they are also pushed to branch `errand-results/<id>`, where a cloud agent can read them.

To let your coding agent drive it, install the skill:

- **Claude Code:** `/plugin marketplace add GanglyPuma22/gpu-errand`, then `/plugin install gpu-errand`.
- **Codex and other agents:** copy [skills/gpu-errand](skills/gpu-errand) into your agent's skills folder.

The skill tells the agent to show you the plan and the unit cap and wait for your go before it spends anything.

## Recipes

| Recipe | Makes | GPU | Measured (Oct 2026) |
|---|---|---|---|
| [`stable-audio-open-sfx`](https://ganglypuma22.github.io/gpu-errand/recipes/sound-effects-stable-audio-open-colab/) | Sound effects up to 47 s, 44.1 kHz stereo, one per seed | L4 | 3 effects in 9 min, 0.21 units |
| [`ace-step-music`](https://ganglypuma22.github.io/gpu-errand/recipes/game-music-ace-step-colab/) | Instrumental music 10-240 s, 48 kHz FLAC, optional seamless loop | A100 | 60 s cue + 52 s loop in 5 min, 0.44 units |
| [`godot-capture` jobs](https://ganglypuma22.github.io/gpu-errand/recipes/headless-godot-capture-gpu/) | Your game's own clips and stills, drawn on the GPU | L4 | 2 clips in 3.3 min, about 0.02 units |

Colab sold 100 compute units for about $10 when this was written, so each of these runs cost a few cents. Check Colab's own pricing page for current numbers.

## Limits

- **Paid Colab only.** Remote shells are allowed only on paid accounts with a positive compute-unit balance.
- **Few GPUs at once.** Colab caps how many you can hold. We saw 2 L4s at once, and jobs wait for a free one without spending.
- **Linux or macOS host** (WSL works), since the Colab CLI doesn't run on plain Windows.
- **No GPU frame timings.** Presenting to Colab's virtual screen fails, so frames render correctly but each one stalls. Clips and stills are fine; benchmarks are not.
- **Tested with Colab CLI 0.7.4.** Use `--auth=oauth2` if your default Google login is a different account (`COLAB_AUTH` sets it).
- **Model licenses are yours to check.** Stable Audio Open uses the Stability AI Community License (gated). ACE-Step's terms are on its repository. Read them before shipping outputs in a product.

## FAQ

**How is this different from Modal, RunPod or SkyPilot?** Those rent you GPUs by the second and have their own agent tools. GPU Errand is for people who already pay for Colab and want their agent to use those units safely: a hard cap, checked results and nothing secret on the runtime.

**Why not just run the Colab CLI myself?** You can; GPU Errand uses it. What it adds is the job format, the ceilings, the watchdog that stops a runtime that hangs, the result checks, the queue and the recipes.

**Does it work with the free Colab tier?** No. Colab only allows remote shells on paid accounts.

**Can my cloud agent use it without access to my machine?** Yes, through the queue. The agent pushes a job file to a private repo and reads the results branch later. Your machine runs the job after you type `go`.

## More

- [Job format](skills/gpu-errand/references/job-format.md)
- [What we learned on Colab runtimes](skills/gpu-errand/references/runtime-notes.md)
- [Agent skill](skills/gpu-errand/SKILL.md)
- Site: https://ganglypuma22.github.io/gpu-errand/

MIT licensed. Contributions and bug reports welcome.
