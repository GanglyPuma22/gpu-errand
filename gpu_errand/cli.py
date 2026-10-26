"""gpu-errand: check jobs, print plans, and run them.

    gpu-errand types                      job types and model recipes
    gpu-errand validate JOB.json          every reason a job would be refused
    gpu-errand plan JOB.json              each step a runner takes, before anything runs
    gpu-errand queue QUEUE.txt            the job files a queue lists
    gpu-errand run JOB.json               run one job on a Colab GPU now (spends units)
    gpu-errand here JOB.json CHECKOUT OUT run a job on this machine (free)
    gpu-errand service go|stop|status|run the standing queue
    gpu-errand where                      where the scripts and recipes are installed
"""

import argparse
import json
import os
import sys
from pathlib import Path

from . import __version__, jobs

PKG = Path(__file__).resolve().parent
SCRIPTS = PKG / "scripts"


def _print(obj):
    print(json.dumps(obj, indent=2))


def _shell(script, args):
    # The runners find this package through PYTHONPATH, installed or not.
    env = dict(os.environ)
    env["PYTHONPATH"] = str(PKG.parent) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    os.execvpe("bash", ["bash", str(SCRIPTS / script), *args], env)


def main(argv=None):
    p = argparse.ArgumentParser(prog="gpu-errand", description="Run agent jobs on a Google Colab GPU with a spending cap.")
    p.add_argument("--version", action="version", version=f"gpu-errand {__version__}")
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("types", help="job types and model recipes")
    for name in ("validate", "plan"):
        c = sub.add_parser(name, help=f"{name} a job file")
        c.add_argument("job")
        if name == "validate":
            c.add_argument("--allow-repo", action="append", default=[], help="allowed owner/name (trailing * matches a prefix)")
            c.add_argument("--allow-ref", action="append", default=[], help="allowed branch (trailing * matches a prefix)")
        else:
            c.add_argument("--where", choices=jobs.WHERE, help="override the job's where")
    c = sub.add_parser("queue", help="list the jobs in a queue file")
    c.add_argument("queue")
    c = sub.add_parser("run", help="run one job on a Colab GPU now")
    c.add_argument("job")
    c = sub.add_parser("here", help="run one job on this machine")
    c.add_argument("job")
    c.add_argument("checkout")
    c.add_argument("out")
    c = sub.add_parser("service", help="the standing queue")
    c.add_argument("action", choices=["go", "stop", "status", "run"])
    sub.add_parser("where", help="where the scripts and recipes are")
    a = p.parse_args(argv)

    try:
        if a.command == "types":
            _print({"types": {k: v["summary"] for k, v in jobs.JOB_TYPES.items()},
                    "recipes": {k: {x: v.get(x) for x in ("summary", "kind", "gpu", "gated", "tested")}
                                for k, v in jobs.recipes().items()}})
        elif a.command == "validate":
            errors = jobs.validate(jobs.load_job(a.job), a.allow_repo, a.allow_ref)
            _print({"ok": not errors, "errors": errors})
            return 0 if not errors else 2
        elif a.command == "plan":
            _print(jobs.plan(jobs.load_job(a.job), a.where))
        elif a.command == "queue":
            found, stop = jobs.parse_queue(Path(a.queue).read_text(encoding="utf-8"))
            _print({"jobs": found, "stop": stop})
        elif a.command == "run":
            _shell("colab_job.sh", [a.job])
        elif a.command == "here":
            _shell("run_here.sh", [a.job, a.checkout, a.out])
        elif a.command == "service":
            _shell("service.sh", [a.action])
        elif a.command == "where":
            _print({"package": str(PKG), "scripts": str(SCRIPTS), "recipes": str(jobs.RECIPES_DIR)})
    except jobs.ErrandError as e:
        print(f"gpu-errand: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
