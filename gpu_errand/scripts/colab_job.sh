#!/bin/bash
# Host side (your always-on machine: a Linux box, a server, WSL): run one job
# on a Colab GPU runtime from start to finish, then stop the runtime.
#   colab_job.sh JOB.json        (or: gpu-errand run JOB.json)
# Needs: the colab CLI signed in to a paid Colab account, git access to the
# job's repo (GH, default git@github.com:), python3, ssh.
# Colab login: COLAB_AUTH (default oauth2). Each session gets its own private
# CLI state file ($WORK/state/<session>.json, mode 600, never copied into
# results) when the CLI accepts one; COLAB_SHARED_CONFIG=1 uses the CLI's
# default state instead.
# The job's commands run only on the runtime: this host packs the commit with
# git archive, copies it in, polls, copies OUT_DIR back and stops the runtime
# on exit, on error and at the cap.
# Results: $WORK/results/<id>-<UTC time>-XXXX/ (the job's OUT_DIR in out/,
# this host's logs beside it), and, when
# RESULTS_REPO is set, a fresh one-commit branch errand-results/<id> there.
set -euo pipefail
JOBFILE=$(realpath "${1:?usage: colab_job.sh JOB.json}")
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PKG=$(cd "$HERE/.." && pwd)
ERRAND() { PYTHONPATH="$(dirname "$PKG")${PYTHONPATH:+:$PYTHONPATH}" python3 -m gpu_errand "$@"; }
WORK=${ERRAND_HOME:-$HOME/.gpu-errand}; GH=${GH:-git@github.com:}
J() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));$1" "$JOBFILE"; }
ALLOW=(); for r in ${ALLOW_REPOS:-}; do ALLOW+=(--allow-repo "$r"); done
for r in ${ALLOW_REFS:-}; do ALLOW+=(--allow-ref "$r"); done
ERRAND validate "$JOBFILE" "${ALLOW[@]}" > /dev/null || { ERRAND validate "$JOBFILE" "${ALLOW[@]}"; exit 2; }
ID=$(J 'print(d["id"])'); TYPE=$(J 'print(d["type"])')
MAXMIN=$(J 'print(int(d["max_minutes"]))'); CAPMB=$(J 'print(int(d.get("results_max_mb",200)))')
if [ "$TYPE" = model-run ]; then
	# A shipped recipe and the job's plan; no repository.
	RECIPE=$(J 'print(d["recipe"])'); RDIR=$PKG/recipes/$RECIPE
	VER=$(PYTHONPATH="$(dirname "$PKG")" python3 -c "import gpu_errand;print(gpu_errand.__version__)")
	REPO="gpu-errand $VER recipe $RECIPE"; REF=$(git -C "$PKG" rev-parse --abbrev-ref HEAD 2> /dev/null || echo "v$VER")
	GPU=$(J "import json as j;print(d.get('gpu') or j.load(open('$RDIR/recipe.json')).get('gpu','L4'))")
	GATED=$(python3 -c "import json,sys;print(1 if json.load(open(sys.argv[1])).get('gated') else 0)" "$RDIR/recipe.json")
	MAXUNITS=$(J 'print(d["max_units"])'); MAXRATE=$(J 'print(d.get("max_rate",""))')
else
	REPO=$(J 'print(d["repo"])'); REF=$(J 'print(d["ref"])'); GPU=$(J 'print(d.get("gpu","L4"))')
	MAXUNITS=""; MAXRATE=""
fi
SESSION=${COLAB_SESSION:-errand-$ID}
mkdir -p "$WORK/results" "$WORK/repos"
RES=$(mktemp -d "$WORK/results/$ID-$(date -u +%Y%m%dT%H%M%SZ)-XXXX")   # fresh per run, even for a reused id
say() { echo "[errand $(date -u +%T)] $*" | tee -a "$RES/driver.log"; }
COLAB_BIN=${COLAB_BIN:-$(command -v colab || true)}
[ -n "$COLAB_BIN" ] || { say "colab CLI not found: stop"; exit 1; }
COLAB=("$COLAB_BIN" "--auth=${COLAB_AUTH:-oauth2}")
mkdir -p -m 700 "$WORK/state"
if [ "${COLAB_SHARED_CONFIG:-0}" != 1 ]; then
	STATE=$WORK/state/$SESSION.json
	# Only if this CLI takes a separate state file and the login still works with it.
	if (umask 077; timeout 60 "${COLAB[@]}" --config "$STATE" usage < /dev/null > /dev/null 2>&1); then
		COLAB+=(--config "$STATE")
	else
		say "colab: separate state file refused, using the CLI's default state"
	fi
fi
say "colab: $("${COLAB[@]}" --version 2> /dev/null | head -1), auth ${COLAB_AUTH:-oauth2}"

# --- 0. what runs, packed here (no .git, no credentials go to the runtime)
RUNJOB=$JOBFILE
if [ "$TYPE" = model-run ]; then
	if git -C "$PKG" rev-parse --git-dir > /dev/null 2>&1; then
		COMMIT=$(git -C "$PKG" rev-parse HEAD)$(git -C "$PKG" diff --quiet HEAD -- "$RDIR" 2> /dev/null || echo +local-changes)
	else
		COMMIT="gpu-errand-$VER"
	fi
	PACK=$(mktemp -d); cp -r "$RDIR"/. "$PACK/"
	python3 -c "import json,sys;json.dump(json.load(open(sys.argv[1]))['plan'],open(sys.argv[2],'w'),indent=2)" "$JOBFILE" "$PACK/plan.json"
	# The runtime's own job file: the recipe's setup and run, the job's caps.
	RUNJOB=$RES/runtime-job.json
	python3 -c "import json,sys;d=json.load(open(sys.argv[1]));json.dump({'id':d['id'],'max_minutes':d['max_minutes'],'setup':'bash setup.sh','command':'bash run.sh'},open(sys.argv[2],'w'))" "$JOBFILE" "$RUNJOB"
	tar -cf "$RES/repo.tar" --exclude=__pycache__ -C "$PACK" .; rm -rf "$PACK"
else
	MIRROR=$WORK/repos/${REPO//\//__}.git
	[ -d "$MIRROR" ] || git clone -q --bare "$GH$REPO.git" "$MIRROR"
	git -C "$MIRROR" fetch -q origin "+refs/heads/*:refs/heads/*" 2> /dev/null || git -C "$MIRROR" fetch -q origin
	COMMIT=$(git -C "$MIRROR" rev-parse --verify -q "$REF^{commit}") || { say "ref $REF not found in $REPO: stop"; exit 1; }
	git -C "$MIRROR" archive --format=tar "$COMMIT" > "$RES/repo.tar"
fi
say "job $ID: $REPO $REF @ $COMMIT ($(( $(stat -c %s "$RES/repo.tar") / 1048576 )) MB), $GPU, cap $MAXMIN min"

# --- 1. runtime (the account holds a few GPUs at once; wait for a free one, no spend while waiting)
cat > "$RES/ssh.cfg" <<CFG
Host runtime
  HostName colab-runtime
  User root
  ProxyCommand ${COLAB[*]} ssh --proxy-mode -s $SESSION
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  ServerAliveInterval 30
  ServerAliveCountMax 4
  ConnectTimeout 60
CFG
ssh() { command ssh -F "$RES/ssh.cfg" "$@"; }
# Hourly rate from `colab usage` (account-wide; the CLI's wording may change).
rate() { python3 -c '
import re, sys
m = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*(?:compute\s*)?(?:units?\s*)?(?:/|per\s*)\s*h(?:ou)?r", sys.stdin.read(), re.I)
print(m.group(1) if m else "")'; }
RATE0=$("${COLAB[@]}" usage 2> /dev/null | rate || true)
WAIT=${GPU_WAIT_MIN:-240}
for try in $(seq $(( WAIT / 5 + 1 ))); do
	"${COLAB[@]}" new --gpu "$GPU" -s "$SESSION" && break
	[ "$try" -gt $(( WAIT / 5 )) ] && { say "no $GPU after $WAIT min: stop"; exit 1; }
	say "no free $GPU yet (try $try), waiting 5 min"; sleep 300
done
T0=$(date +%s)
CAP=$(( (MAXMIN + 20) * 60 ))
# Watchdog over the whole runtime's life (start-up, copies, the job, results),
# started the moment the GPU is granted. It stops the runtime at the deadline
# in $DEADLINE (seconds since the epoch), which ends any ssh call still hanging;
# the unit ceiling below can only move that deadline earlier.
DEADLINE=$RES/deadline; echo $(( T0 + CAP )) > "$DEADLINE"
# One bounded stop attempt; success means the CLI confirmed the stop.
PAUSE=${ERRAND_STOP_PAUSE:-10}   # seconds between stop tries (tests set 0)
stop_once() { timeout 120 "${COLAB[@]}" stop -s "$SESSION" < /dev/null; }
( exec 7>&-; trap '' HUP
  while [ "$(date +%s)" -lt "$(cat "$DEADLINE" 2> /dev/null || echo 0)" ]; do sleep 5; done
  echo "[errand $(date -u +%T)] watchdog: deadline reached $(( $(date +%s) - T0 )) s after the runtime started, stopping it" >> "$RES/driver.log"
  # Keeps trying for about 30 minutes: a failed stop doesn't release the GPU.
  for try in $(seq 30); do
	stop_once > /dev/null 2>&1 && { touch "$RES/stopped"; echo "[errand $(date -u +%T)] watchdog: runtime stopped" >> "$RES/driver.log"; exit 0; }
	sleep $(( PAUSE * 6 ))
  done
  echo "[errand $(date -u +%T)] watchdog: could not stop session $SESSION after 30 tries; stop it by hand: colab stop -s $SESSION" >> "$RES/driver.log" ) &
WATCHDOG=$!
# The watchdog stays armed until a stop succeeds. If cleanup can't stop the
# runtime, it pulls the deadline to now and waits while the watchdog retries,
# so the runner (and a queue that tracks it) lives until those retries end.
cleanup() {
	local rc=$? try
	rm -f "$RES/repo.tar"
	say "stopping runtime"
	for try in 1 2 3; do
		[ -e "$RES/stopped" ] && { say "the watchdog already stopped it"; exit "$rc"; }
		if stop_once; then kill "$WATCHDOG" 2> /dev/null; exit "$rc"; fi
		say "stop failed (try $try)"; sleep $(( try * PAUSE ))
	done
	date +%s > "$DEADLINE"
	say "stop not confirmed: the watchdog keeps trying for up to 30 min (see driver.log)"
	wait "$WATCHDOG" 2> /dev/null || true
	if [ -e "$RES/stopped" ]; then say "the watchdog stopped the runtime"; exit "$rc"; fi
	say "WARNING: runtime not confirmed stopped; it may still spend units. Stop it by hand: colab stop -s $SESSION"
	exit 1
}
trap cleanup EXIT
USAGE=$(timeout 60 "${COLAB[@]}" usage 2> /dev/null || true)
echo "$USAGE" | head -5 >> "$RES/driver.log"
RATE1=$(echo "$USAGE" | rate || true)
# The ceilings use the account's whole rate after allocation: never less than this
# session's own, so with other sessions running they are stricter, never looser.
OWN=$RATE1
say "rate: account ${RATE1:-unknown} units/hour with this session (before it: ${RATE0:-unknown}); ceilings use the account rate"
if [ -n "$MAXUNITS" ]; then
	# A model run spends only with a known rate, under its ceiling, and no longer than its units allow.
	[ -n "$OWN" ] || { say "hourly rate unknown: refusing to spend; stop"; exit 1; }
	if [ -n "$MAXRATE" ] && python3 -c "import sys;sys.exit(0 if float(sys.argv[1])>float(sys.argv[2]) else 1)" "$OWN" "$MAXRATE"; then
		say "rate $OWN is over the job's max_rate $MAXRATE: stop"; exit 1
	fi
	# Counted from T0, so time spent reading the rate is already spent.
	UCAP=$(python3 -c "import sys;print(int(float(sys.argv[1])/float(sys.argv[2])*3600))" "$MAXUNITS" "$OWN")
	if [ "$UCAP" -lt "$CAP" ]; then
		CAP=$UCAP; echo $(( T0 + CAP )) > "$DEADLINE"
		say "cap: $CAP s after the runtime started, from the $MAXUNITS unit ceiling"
	fi
	[ $(( $(date +%s) - T0 )) -lt "$CAP" ] || { say "unit ceiling already reached: stop"; exit 1; }
fi
for try in 1 2 3 4 5; do
	ssh runtime 'mkdir -p /content/job/repo /content/job/out' && break
	[ "$try" = 5 ] && { say "ssh to the runtime failed 5 times: stop"; exit 1; }
	say "ssh not ready (try $try)"; sleep $((15 * try))
done
# Each start-up step is safe to repeat, so a dropped connection gets two more
# tries instead of ending a paid run (an A100 start once hung 2.5 min, then broke).
put() { # put REMOTE_COMMAND [LOCAL_FILE for stdin]
	local t
	for t in 1 2 3; do
		ssh runtime "$1" < "${2:-/dev/null}" && return 0
		say "ssh dropped (try $t of 3): ${1%% *}..."; sleep $((10 * t))
	done
	say "ssh failed 3 times: stop"; exit 1
}
put 'tar -xf - -C /content/job/repo' "$RES/repo.tar"
put 'cat > /content/job/job.json' "$RUNJOB"
if [ "${GATED:-0}" = 1 ]; then
	# Gated weights: short-lived links made here with the host's login; the token stays here.
	W=$WORK/state/$SESSION-weights.json
	python3 "$HERE/stage_hf.py" "$RDIR/recipe.json" "$W" >> "$RES/driver.log" 2>&1 || { say "weight staging failed (see driver.log): stop"; rm -f "$W"; exit 1; }
	OK=0; ( put 'umask 077; cat > /content/job/weights.json' "$W" ) || OK=1; rm -f "$W"; [ "$OK" = 0 ] || exit 1
	say "weights staged for $RECIPE"
fi
echo "$COMMIT" > "$RES/commit.txt"
put 'cat > /content/job/commit.txt' "$RES/commit.txt"
for f in runtime_display.sh runtime_job.sh; do put "cat > /content/job/$f" "$HERE/$f"; done
say "copied in after $(( $(date +%s) - T0 )) s"

# --- 2. screen, then the job (detached; polled)
SCREEN_ARG=--no-screen; [ "$TYPE" = godot-capture ] && SCREEN_ARG=""
ssh runtime "bash /content/job/runtime_display.sh $SCREEN_ARG" >> "$RES/driver.log" 2>&1 \
	|| ssh runtime "bash /content/job/runtime_display.sh $SCREEN_ARG" >> "$RES/driver.log" 2>&1 \
	|| { say "runtime preparation failed: stop"; exit 1; }
# Start the job once: a retry after a dropped connection sees runner.pid and
# only confirms the start.
put 'cd /content/job && if [ ! -s runner.pid ]; then setsid nohup bash runtime_job.sh > runner.log 2>&1 < /dev/null & sleep 3; fi; [ -s runner.pid ]'
while :; do
	sleep 60
	P=$(ssh runtime 'tail -1 /content/job/progress.txt 2>/dev/null; [ -f /content/job/finished ] && echo RUNNER-FINISHED' || true)
	echo "  $P" >> "$RES/driver.log"
	case "$P" in *RUNNER-FINISHED) break ;; esac
	if [ $(( $(date +%s) - T0 )) -gt "$CAP" ]; then
		say "time cap reached: stopping the job, then fetching partial results"
		ssh runtime 'P=$(cat /content/job/runner.pid 2>/dev/null); [ -n "$P" ] && { kill -TERM -- -$P 2>/dev/null; sleep 3; kill -KILL -- -$P 2>/dev/null; }; true' || true
		break
	fi
done

# --- 3. results (size-capped)
# A file list with SHA-256 made on the runtime, checked here after the copy:
# a run counts only when what arrived matches what the runtime wrote.
ssh runtime "cd /content/job && cp progress.txt runner.log out/ 2>/dev/null; (cd out && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 -r sha256sum > MANIFEST.sha256); du -sm out | cut -f1" > "$RES/out-mb.txt" || true
MB=$(cat "$RES/out-mb.txt" 2>/dev/null || echo 0)
# The job's files land in $RES/out, apart from this host's own files, and only
# regular files are asked for. Anything else that arrives (links, devices) is
# deleted before the host reads a single path, and listed.
OUT=$RES/out; mkdir -p "$OUT"
LIMIT=""; if [ "${MB:-0}" -gt "$CAPMB" ]; then LIMIT="-size -10M"
	say "OUT_DIR is $MB MB, over the job's $CAPMB MB: bringing back files under 10 MB only"; fi
ssh runtime "cd /content/job/out && find . -type f $LIMIT -print0 | tar --null --no-recursion -T - -cf -" | tar -xf - -C "$OUT" --no-same-owner --no-same-permissions
find "$OUT" -mindepth 1 ! -type f ! -type d -print -delete > "$RES/removed-not-regular.txt"
[ -s "$RES/removed-not-regular.txt" ] && say "removed $(grep -c . "$RES/removed-not-regular.txt") link(s) or special file(s) from the results (listed in removed-not-regular.txt)"
VERIFIED=0
if [ -s "$OUT/MANIFEST.sha256" ]; then
	if [ "${MB:-0}" -gt "$CAPMB" ]; then
		(cd "$OUT" && sha256sum --quiet -c --ignore-missing MANIFEST.sha256) && VERIFIED=1
	else
		(cd "$OUT" && sha256sum --quiet -c MANIFEST.sha256) && VERIFIED=1
	fi
fi
[ "$VERIFIED" = 1 ] && say "results match the runtime's SHA-256 list" || say "results do NOT match the runtime's SHA-256 list (or it is missing)"
say "runtime minutes: $(( ($(date +%s) - T0) / 60 ))"
"${COLAB[@]}" usage 2> /dev/null | head -3 >> "$RES/driver.log" || true
echo "build: $REPO $REF @ $COMMIT, $GPU, $(grep -m1 gpu= "$OUT/env.txt" 2>/dev/null || echo 'gpu line missing')" > "$RES/BUILD.txt"

PUSHED=0; [ -n "${RESULTS_REPO:-}" ] || PUSHED=1   # no results repo: the local folder is the delivery
# Per-file size on a results branch: 10 MB for repo jobs (clips are small), 95 MB
# for model runs (a 180 s FLAC is about 30 MB; GitHub refuses files over 100 MB).
FILE_MB=10; [ "$TYPE" = model-run ] && FILE_MB=95
LEFTOUT=0
if [ -n "${RESULTS_REPO:-}" ]; then
	P=$(mktemp -d); mkdir -p "$P/$ID"
	(cd "$RES" && find . -type f ! -name repo.tar ! -name ssh.cfg -size -${FILE_MB}M -print0 | tar --null -T - -cf -) | tar -xf - -C "$P/$ID"
	(cd "$RES" && find . -type f ! -name repo.tar -size +$((FILE_MB - 1))M -print) > "$P/$ID/LEFT-OUT-over-${FILE_MB}MB.txt"
	LEFTOUT=$(grep -c . "$P/$ID/LEFT-OUT-over-${FILE_MB}MB.txt" || true)
	[ "$LEFTOUT" -gt 0 ] && say "$LEFTOUT file(s) over $FILE_MB MB stay in $RES only (listed in LEFT-OUT-over-${FILE_MB}MB.txt)"
	( cd "$P" && git init -q && git checkout -q -b "errand-results/$ID" && git add -A \
		&& git -c user.name=gpu-errand -c user.email=gpu-errand@localhost commit -qm "gpu-errand results $ID ($(basename "$RES"))" \
		&& git push -q -f "$GH$RESULTS_REPO.git" "errand-results/$ID" ) \
		&& { say "results pushed to $RESULTS_REPO branch errand-results/$ID"; PUSHED=1; } || say "results push FAILED (kept in $RES)"
	rm -rf "$P"
fi
RC=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(0 if d.get('setup_exit')==0 and d.get('run_exit')==0 else 1)" "$OUT/runner.json" 2>/dev/null || echo 1)
# Results nobody can reach are a failed job: the queue stops and says so.
[ "$RC" = 0 ] && [ "$VERIFIED" = 0 ] && RC=4
[ "$RC" = 0 ] && [ "$PUSHED" = 0 ] && RC=3
# A model run's outputs are the product: any left behind means it was not delivered.
if [ "$TYPE" = model-run ] && [ "$RC" = 0 ] && { [ "${LEFTOUT:-0}" -gt 0 ] || [ "${MB:-0}" -gt "$CAPMB" ]; }; then
	say "model outputs not all delivered (size limits): exit 3"; RC=3
fi
say "job $ID: exit $RC; results in $RES"
exit "$RC"
