# Job format

One JSON object per job. `gpu-errand validate <file>` checks every rule below; `gpu-errand plan <file>` prints the steps a runner will take.

| Key | Required | Rule |
|---|---|---|
| `schema` | yes | `1` |
| `id` | yes | 3-64 lowercase letters, digits and dashes. Names the results branch `errand-results/<id>`, so reuse an id only to replace its results. |
| `type` | yes | `shell`, `godot-capture` (adds a virtual screen with Vulkan) or `model-run` (below). `gpu-errand types` lists them. |
| `repo` | yes | `owner/name`. The service also checks it against its `ALLOW_REPOS`. |
| `ref` | yes | Branch or commit. The runner packs exactly this commit. The service checks branches against `ALLOW_REFS`. |
| `setup` | no | One line of shell run from the repository root before `command` (fetch the engine, import). |
| `command` | yes | One line of shell run from the repository root. Write results under `$OUT_DIR`. `$ERRAND_COMMIT` holds the full commit id (the copy has no `.git`). |
| `where` | no | `colab` (default) or `here`. |
| `gpu` | no | `L4` (default), `T4`, `A100`, or `CPU` for a runtime with no accelerator (`colab new` with no `--gpu`). Use `CPU` for work that never touches a GPU: tests, headless sims, benches. It costs a small fraction of a GPU's units an hour, with fewer cores. A `godot-capture` job on `CPU` draws with the software Vulkan driver; a headless job should be `shell`. What the account can hold decides how many run at once. |
| `high_mem` | no | `true` asks for Colab's High-RAM runtime (`--high-mem`), which also has more CPU cores; needs a plan that offers it. |
| `max_minutes` | yes | 1-240. Setup and command together; the runner adds 20 minutes for the runtime to start and copy in. |
| `max_units` | no | 0.01-20 compute units, as for `model-run` below. On Colab the runtime is stopped at this ceiling or the time cap, whichever comes first. Set it whenever the person gave a unit cap. |
| `max_rate` | no | Units per hour, with `max_units`: the run stops at once if the session's rate is higher. On `CPU`, set it just above the CPU rate so the job can never spend at a GPU's rate. |
| `results_max_mb` | no | 1-500 (default 200). Past it, only files under 10 MB come back. Files over 10 MB never go to a results branch. |
| `godot` | no | `{"url": "https://...zip", "sha256": "<64 hex>"}`: the runner downloads the engine, checks it and sets `GODOT`. A game that fetches its own engine in `setup` leaves this out. |
| `env` | no | `{"NAME": "value"}`, upper-case names, one-line values. Not `OUT_DIR`, `GODOT`, `JOB_ID`, `ERRAND_COMMIT`, `DISPLAY`, and nothing that looks like a token, secret, password or key. |

## model-run jobs

`model-run` replaces `repo`, `ref`, `setup`, `command`, `godot` and `env` (all refused) with:

| Key | Required | Rule |
|---|---|---|
| `recipe` | yes | A folder under `gpu_errand/recipes` with a `recipe.json`. |
| `plan` | yes | `{"cues": [...]}` plus recipe settings. Each cue: unique `id`, the recipe's text field (`prompt` or `caption`), `seeds` (distinct whole numbers, one output each), `seconds` (or a plan-wide `seconds`) within the recipe's limits. Total outputs within the recipe's `max_outputs`. |
| `max_units` | yes | 0.01-20 compute units: the runtime is stopped when this much time at the observed rate has passed. |
| `max_rate` | no | Units per hour; the run stops at once if the session's rate is higher. |
| `gpu` | no | Defaults to the recipe's; must be one the recipe lists. |
| `where` | no | `colab` only. |

## Queue file

`queue.txt` on the queue branch, one job file name per line (`<id>.json`, the file itself under `jobs/`). Blank lines and `#` comments are skipped. A line `STOP` stops the service after running jobs finish. A job runs once per host; to rerun, use a new id or remove its line from `~/.gpu-errand/service.done`.

## Results

From a Colab run, the results folder holds the host's files: `driver.log`, `BUILD.txt` (repository, ref, commit, GPU and the `gpu=` line) and `removed-not-regular.txt`. Its `out/` folder holds the job's own `OUT_DIR`, with only regular files kept. In `out/` the runner adds `runner.json` (`{"id", "setup_exit", "run_exit", "minutes", "gpu"}`), `env.txt` (what the runtime had), `setup.log`, `run.log`, `progress.txt` and `MANIFEST.sha256`. `setup` and `command` share `max_minutes`: the command gets only the time setup left.
