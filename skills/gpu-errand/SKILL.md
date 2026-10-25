---
name: gpu-errand
description: Run a job on a Google Colab GPU from a coding agent, with a hard compute-unit cap and checked results. Use it for a repository command that needs a GPU, a headless Godot capture (clips, stills), or a model run from the shipped recipes (game music with ACE-Step, sound effects with Stable Audio Open). Results come back with SHA-256 checks and a receipt.
---

# GPU Errand

Use this when work needs a GPU that the agent's own machine doesn't have. Examples: render gameplay clips, make sound effects or music from text, or run a script on CUDA. The job runs on a Colab runtime that the person's always-on machine starts, and the runtime is stopped afterwards. Every run spends the person's Colab compute units, so nothing starts without their go.

Install: `pipx install git+https://github.com/GanglyPuma22/gpu-errand` (or `pip install .` in a checkout; `python3 -m gpu_errand` also works from a checkout). The host needs the [Colab CLI](https://github.com/googlecolab/google-colab-cli) signed in to a paid Colab account, plus `git`, `ssh` and Python 3.9+.

## 1. Write the job

One JSON file. Pick the type:

| Type | Use it for | Brings its own |
|---|---|---|
| `shell` | any repository command that needs a GPU | `repo`, `ref`, `setup`, `command` |
| `godot-capture` | a game's own capture command; adds a virtual screen with Vulkan on the GPU | the same, plus optional pinned `godot` download |
| `model-run` | a shipped recipe: `stable-audio-open-sfx` (L4) or `ace-step-music` (A100) | `recipe` and `plan`; no repository |

Start from [examples/jobs](../../examples/jobs) and the [job format](references/job-format.md). Rules that matter:

- Git decides what runs: the runner packs exactly the commit `ref` names, without `.git`. Push first.
- Write results under `$OUT_DIR`. `$JOB_ID` and `$ERRAND_COMMIT` are set for you.
- No credentials go to a runtime, and `env` refuses names that look like secrets.
- `model-run` needs `max_units` (the spending ceiling). Add `max_rate` (units per hour) to refuse a pricier GPU than expected.

## 2. Check it and show the plan

```text
gpu-errand validate job.json
gpu-errand plan job.json
```

`plan` prints every step and the caps. Show it to the person with the GPU, time cap and unit ceiling, and wait for their go. A go covers that job and those caps only.

## 3. Run it

```text
COLAB_SESSION=<unique-name> RESULTS_REPO=<owner/private-repo> gpu-errand run job.json
```

What happens:

1. The runner waits (spending nothing) for a free GPU.
2. It reads the hourly rate. If the rate is unknown or over `max_rate`, it refuses.
3. It caps the runtime's life at `max_minutes` + 20 minutes or the unit ceiling, whichever comes first.
4. It copies the job in, runs it, and brings `OUT_DIR` back.
5. It checks every file against a SHA-256 list made on the runtime.
6. It stops the runtime, also on error and at the cap.

The job's files land in `~/.gpu-errand/results/<id>-<time>/out/`, and the runner's logs sit beside that folder. Links and special files are dropped. With `RESULTS_REPO` set, they also go to branch `errand-results/<id>`.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | Done and verified. |
| 1 | The job failed, or the runtime or a ceiling stopped it. |
| 2 | The job was refused. |
| 3 | Results not delivered. |
| 4 | Results did not match the runtime's list. |

On any failure, read `driver.log`, `setup.log` and `run.log`, then report. Never rerun, switch GPU or raise a cap by yourself.

`gpu-errand here job.json <checkout> <out>` runs `shell` and `godot-capture` jobs on this machine instead. It's free, and slow without a GPU.

## 4. Read the results honestly

- `runner.json` says how the job exited. Its `gpu=` line says whether a real GPU drew the frames or a software driver did.
- A model run's `receipt.json` lists every output with its hash, length, peak and loudness. It proves the files are valid, not that they fit the prompt. In our first test a "heavy" sword swing came out light. Ask the person to listen before anything is used.
- Don't trust frame timings from Colab: presenting to the virtual screen fails and stalls each frame (see [runtime notes](references/runtime-notes.md)).

## Gated models

Stable Audio Open is gated on Hugging Face. The host's own login (`HF_TOKEN`, `HF_TOKEN_PATH` or `~/.cache/huggingface/token`) turns into short-lived download links for the exact pinned files. The runtime checks each file's SHA-256, and the token never leaves the host. The account must accept the model's license on its page first.

## A queue on the always-on machine

For a standing queue, run `gpu-errand service go`. The queue lives on a branch of a private repo: `queue.txt` lists job files and `jobs/<id>.json` holds them. Any agent can add a job by pushing those two files.

The service runs only after a typed go, keeps to the host's bounds and stays stopped after a clean stop. The bounds are allowed repos and refs, jobs per go, hours per go and jobs at once. Settings live in `~/.gpu-errand/service.env`; [service.sh](../../gpu_errand/scripts/service.sh) documents each one.
