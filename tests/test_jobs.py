"""Jobs and queues: validation and plans, with no runtime or network."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from gpu_errand import jobs as cloudrun
from gpu_errand.jobs import ErrandError

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "gpu_errand/scripts"


def job(**over):
    j = {
        "schema": 1, "id": "game-clips-1", "type": "godot-capture",
        "repo": "Owner/game", "ref": "claude/clips", "setup": "tools/setup.sh",
        "command": "tools/clips.sh recipe.json \"$OUT_DIR\"", "where": "colab", "gpu": "L4",
        "max_minutes": 60,
    }
    j.update(over)
    return j


class JobTests(unittest.TestCase):
    def test_a_complete_job_is_runnable(self):
        self.assertEqual(cloudrun.validate(job()), [])

    def test_bad_fields_are_each_named(self):
        cases = {
            "id": ("Bad_ID", "id must be"),
            "type": ("render-farm", "type must be"),
            "repo": ("not a repo", "repo must be"),
            "ref": ("../main", "ref must be"),
            "command": ("a\nb", "command must be one line"),
            "where": ("laptop", "where must be"),
            "gpu": ("H100", "gpu must be"),
            "max_minutes": (0, "max_minutes"),
            "results_max_mb": (10_000, "results_max_mb"),
        }
        for key, (value, message) in cases.items():
            with self.subTest(key=key):
                errors = cloudrun.validate(job(**{key: value}))
                self.assertTrue(any(message in e for e in errors), errors)

    def test_the_status_branch_id_is_reserved(self):
        self.assertTrue(any("queue-status" in e for e in cloudrun.validate(job(id="queue-status"))))

    def test_model_run_examples_are_runnable(self):
        for recipe in ("stable-audio-open-sfx", "ace-step-music"):
            plan = json.loads((cloudrun.RECIPES_DIR / recipe / "plan.example.json").read_text())
            mj = {"schema": 1, "id": "audio-test", "type": "model-run", "recipe": recipe, "plan": plan,
                  "max_minutes": 20, "max_units": 1}
            self.assertEqual(cloudrun.validate(mj), [], recipe)
            steps = " ".join(cloudrun.plan(mj)["steps"])
            self.assertIn("1 units", steps)
            self.assertEqual("token never leaves the host" in steps, recipe == "stable-audio-open-sfx")

    def test_model_run_refuses_game_fields_missing_ceiling_and_bad_plans(self):
        plan = {"cues": [{"id": "swing", "prompt": "a swing", "seconds": 5, "seeds": [1, 2]}]}
        base = {"schema": 1, "id": "audio-test", "type": "model-run", "recipe": "stable-audio-open-sfx",
                "plan": plan, "max_minutes": 20, "max_units": 1}
        def errs(**over):
            return " ".join(cloudrun.validate({**base, **over}))
        self.assertIn("repo is not used", errs(repo="a/b"))
        self.assertIn("command is not used", errs(command="rm -rf /"))
        self.assertIn("max_units", errs(max_units=None))
        self.assertIn("recipe must be one of", errs(recipe="nope"))
        self.assertIn("runs on", errs(recipe="ace-step-music", gpu="L4",
                                      plan={"cues": [{"id": "mus", "caption": "x", "seconds": 60, "seeds": [1]}]}))
        self.assertIn("seconds", errs(plan={"cues": [{"id": "swing", "prompt": "x", "seconds": 90, "seeds": [1]}]}))
        self.assertIn("distinct", errs(plan={"cues": [{"id": "swing", "prompt": "x", "seconds": 5, "seeds": [1, 1]}]}))
        self.assertIn("prompt must be text", errs(plan={"cues": [{"id": "swing", "caption": "x", "seconds": 5, "seeds": [1]}]}))
        self.assertIn("limit", errs(plan={"cues": [{"id": "swing", "prompt": "x", "seconds": 5, "seeds": list(range(40))}]}))
        self.assertIn("colab only", errs(where="here"))
        music = {"recipe": "ace-step-music", "gpu": "A100"}
        self.assertIn("under half", errs(**music, plan={"loop_crossfade_seconds": 8, "cues": [{"id": "mus", "caption": "x", "seconds": 10, "seeds": [1]}]}))
        self.assertEqual(errs(**music, plan={"loop_crossfade_seconds": 4, "cues": [{"id": "mus", "caption": "x", "seconds": 10, "seeds": [1]}]}), "")

    def test_recipes_pin_their_models(self):
        for name, r in cloudrun.recipes().items():
            m = r["model"]
            pins = [m.get("revision"), m.get("commit")] + list(m.get("repos", {}).values())
            self.assertTrue(any(pins), name)
            for pin in filter(None, pins):
                self.assertRegex(pin, r"^[0-9a-f]{40}$", name)
            self.assertIn("license", m, name)
            for f in ("setup.sh", "run.sh", "worker.py", "plan.example.json"):
                self.assertTrue((cloudrun.RECIPES_DIR / name / f).is_file(), f"{name}/{f}")

    def test_unknown_type_is_refused(self):
        self.assertTrue(any("type must be" in e for e in cloudrun.validate(job(type="anything"))))

    def test_env_cannot_carry_secrets_or_runner_names(self):
        self.assertTrue(cloudrun.validate(job(env={"API_TOKEN": "x"})))
        self.assertTrue(cloudrun.validate(job(env={"OUT_DIR": "/tmp"})))
        self.assertTrue(cloudrun.validate(job(env={"lower": "x"})))
        self.assertEqual(cloudrun.validate(job(env={"CLIP_SET": "review"})), [])

    def test_pinned_engine_needs_https_and_sha256(self):
        self.assertTrue(cloudrun.validate(job(godot={"url": "http://x/godot.zip", "sha256": "0" * 64})))
        self.assertTrue(cloudrun.validate(job(godot={"url": "https://x/godot.zip", "sha256": "abc"})))
        self.assertEqual(cloudrun.validate(job(godot={"url": "https://x/godot.zip", "sha256": "a" * 64})), [])

    def test_service_allow_lists(self):
        self.assertEqual(cloudrun.validate(job(), ["Owner/*"], ["claude/*", "main"]), [])
        self.assertTrue(any("allowed list" in e for e in cloudrun.validate(job(), ["Other/*"])))
        self.assertTrue(any("allowed list" in e for e in cloudrun.validate(job(ref="feature/x"), None, ["claude/*"])))

    def test_plan_names_every_host_and_runtime_step(self):
        steps = cloudrun.plan(job())["steps"]
        self.assertIn("git archive", steps[0])
        self.assertTrue(any("colab new --gpu L4" in s for s in steps))
        self.assertTrue(any(s.startswith("runtime: run:") for s in steps))
        self.assertTrue(any("stop the runtime" in s for s in steps))
        here = cloudrun.plan(job(), "here")["steps"]
        self.assertFalse(any("colab" in s for s in here))

    def test_shell_jobs_get_no_screen_and_capture_jobs_do(self):
        shell = " ".join(cloudrun.plan(job(type="shell"))["steps"])
        self.assertIn("no screen", shell)
        self.assertNotIn("Xvfb", shell)
        self.assertIn("Xvfb", " ".join(cloudrun.plan(job())["steps"]))
        text = (SCRIPTS / "colab_job.sh").read_text(encoding="utf-8")
        self.assertIn('SCREEN_ARG=--no-screen; [ "$TYPE" = godot-capture ] && SCREEN_ARG=""', text)

    def test_plan_refuses_an_invalid_job(self):
        with self.assertRaises(ErrandError):
            cloudrun.plan(job(id="x"))


class QueueTests(unittest.TestCase):
    def test_lines_comments_and_stop(self):
        found, stop = cloudrun.parse_queue("# clips\ngame-clips-1.json\n\nsfx-x.json  note\nSTOP\nlater.json\n")
        self.assertEqual(found, ["game-clips-1.json", "sfx-x.json"])
        self.assertTrue(stop)

    def test_a_path_or_odd_name_is_refused(self):
        for line in ("../x.json", "jobs/x.json", "X.json", "x.txt"):
            with self.subTest(line=line), self.assertRaises(ErrandError):
                cloudrun.parse_queue(line)


class CliAndScriptsTests(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, "-m", "gpu_errand", *args], cwd=ROOT,
                              capture_output=True, text=True)

    def test_cli_validate_plan_and_types(self):
        with tempfile.TemporaryDirectory() as tmp:
            good = Path(tmp) / "job.json"
            good.write_text(json.dumps(job()), encoding="utf-8")
            r = self.run_cli("validate", str(good))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(json.loads(r.stdout)["ok"])
            bad = Path(tmp) / "bad.json"
            bad.write_text(json.dumps(job(max_minutes=9999)), encoding="utf-8")
            r = self.run_cli("validate", str(bad))
            self.assertEqual(r.returncode, 2)
            r = self.run_cli("plan", str(good), "--where", "here")
            self.assertEqual(json.loads(r.stdout)["where"], "here")
        r = self.run_cli("types")
        self.assertIn("godot-capture", json.loads(r.stdout)["types"])

    def test_shell_runners_parse(self):
        for script in sorted(SCRIPTS.glob("*.sh")):
            with self.subTest(script=script.name):
                r = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, r.stderr)

    def test_watchdog_starts_before_the_rate_lookup(self):
        # Spend is bounded from the moment the GPU is granted, even if `colab usage` hangs.
        text = (SCRIPTS / "colab_job.sh").read_text(encoding="utf-8")
        self.assertLess(text.index("WATCHDOG=$!"), text.index('USAGE=$(timeout 60'))
        self.assertIn('echo $(( T0 + CAP )) > "$DEADLINE"', text)

    def test_results_land_apart_from_host_files_without_links(self):
        text = (SCRIPTS / "colab_job.sh").read_text(encoding="utf-8")
        self.assertIn('tar -xf - -C "$OUT"', text)
        cleanup = text.index('! -type f ! -type d -print -delete')
        self.assertLess(cleanup, text.index('"$RES/BUILD.txt"'))

    def test_queue_jobs_do_not_inherit_the_service_lock(self):
        self.assertIn("2>&1 7>&- &", (SCRIPTS / "service.sh").read_text(encoding="utf-8"))

    def test_command_gets_only_the_time_left_after_setup(self):
        text = (SCRIPTS / "runtime_job.sh").read_text(encoding="utf-8")
        self.assertNotIn("LEFT=60", text)
        self.assertIn('if [ "$LEFT" -le 0 ]; then', text)

    def test_here_refuses_a_destination_it_cannot_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
            (repo / "a.txt").write_text("x")
            subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
            subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "x"], check=True)
            jf = Path(tmp) / "job.json"
            jf.write_text(json.dumps(job(type="shell", ref="main", setup="", command="touch \"$OUT_DIR/ran\"", where="here")))
            dest = Path(tmp) / "a-file"
            dest.write_text("not a folder")
            r = subprocess.run([sys.executable, "-m", "gpu_errand", "here", str(jf), str(repo), str(dest)],
                               cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(r.returncode, 2, r.stderr)
            self.assertIn("cannot write results", r.stderr)
            out = Path(tmp) / "out"
            r = subprocess.run([sys.executable, "-m", "gpu_errand", "here", str(jf), str(repo), str(out)],
                               cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue((out / "ran").is_file())

    def test_service_host_never_runs_job_commands(self):
        # The host packs, copies and polls; setup and command run only on the runtime.
        text = (SCRIPTS / "colab_job.sh").read_text(encoding="utf-8")
        self.assertNotIn('bash -c "$CMD"', text)
        self.assertNotIn('d["command"]', text)
        self.assertIn("git -C \"$MIRROR\" archive", text)
        self.assertIn('"${COLAB[@]}" stop -s "$SESSION"', text)
        self.assertIn("trap", text)


class PublicTextTests(unittest.TestCase):
    def test_no_private_machine_or_project_names(self):
        # The public repo talks about hosts and games in general terms.
        words = ("aptivio", "salvage", "skybreak", "mmounier", "openclaw", "studio-cloudrun", "game-studio-kit")
        for path in ROOT.rglob("*"):
            if path.is_file() and ".git" not in path.parts and path.suffix in (".py", ".sh", ".md", ".json", ".yml", ".service", ".toml", ".html", ""):
                text = path.read_text(encoding="utf-8", errors="ignore").lower()
                for w in words:
                    if path.name == "test_jobs.py":
                        continue
                    with self.subTest(path=str(path.relative_to(ROOT)), word=w):
                        self.assertNotIn(w, text)


class StageHfTokenFile(unittest.TestCase):
    def test_token_file_forms(self):
        import importlib.util
        path = SCRIPTS / "stage_hf.py"
        spec = importlib.util.spec_from_file_location("stage_hf", path)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        self.assertEqual(m.token_from_file("hf_abc\n"), "hf_abc")
        self.assertEqual(m.token_from_file('export HF_TOKEN="hf_x"\n'), "hf_x")
        self.assertEqual(m.token_from_file("# note\nOTHER=1\nHF_TOKEN=hf_y\n"), "hf_y")
        self.assertEqual(m.token_from_file("OTHER=1\n"), "")


if __name__ == "__main__":
    unittest.main()
