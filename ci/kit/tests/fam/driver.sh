# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-driver (kit/README.md §6.2; pattern 6.2): the host side of a run on the
# docker shim and the host farm: the preflight refusals, the lock, the commit
# and never the working copy, the services and their removal, the job
# container's isolation, the counts and skip rules, the facts in field order.
fam_driver() {
  local st key entry log n first line tmpfx
  fx_new drv
  st="$(state_dir)"; key="$(fx_key alpha)"; entry="$st/passed/alpha/$key"
  # Docker not answering: no start, desktop or context call.
  export SHIM_DOCKER_INFO_RC=1
  drv run --commit HEAD alpha
  rc_is "Docker not answering" 2 "$DRV_RC"; has "refuses in one sentence" "$work/drv.out" "Docker is not running, so alpha did not run."
  hasnt "and never starts or reconfigures Docker (no start)" "$DOCKER_LOG" start
  hasnt "(no desktop)" "$DOCKER_LOG" desktop; hasnt "(no context)" "$DOCKER_LOG" context
  unset SHIM_DOCKER_INFO_RC
  # The refusals before any docker call.
  drv run --commit HEAD beta
  rc_is "a CI-only job" 2 "$DRV_RC"; has "is refused in its own sentence" "$work/drv.out" "beta runs in CI only, so it did not run here. The pull request runs it."
  check "before any Docker call" test ! -s "$DOCKER_LOG"
  drv run --commit HEAD nojob; rc_is "a job the manifest lacks" 2 "$DRV_RC"
  drv run --commit nonsense alpha; rc_is "a revision that is not a commit" 2 "$DRV_RC"
  drv run --commit HEAD alpha extra=1; rc_is "a word that is not a job name" 2 "$DRV_RC"
  git -C "$FX" checkout -q --orphan old && git -C "$FX" rm -rfq . && printf 'x\n' > "$FX/x" && git -C "$FX" add x && git -C "$FX" commit -qm old
  drv run --commit HEAD alpha
  rc_is "a commit that predates the kit" 2 "$DRV_RC"; has "says so" "$work/drv.out" "predates the kit, so nothing ran."
  git -C "$FX" checkout -q -f main; git -C "$FX" branch -D -q old
  # The pins read in the image.
  export SHIM_V_go=go9.9.9
  drv run --commit HEAD alpha
  rc_is "a tool off its pin in the job image" 2 "$DRV_RC"; has "names the tool, the version and the pin" "$work/drv.out" "go go9.9.9 is not the pinned go1.27.3 in the job image, so alpha did not run."
  hasnt "and no job container ran" "$DOCKER_LOG" cikit-enter
  unset SHIM_V_go
  export SHIM_V_node=v99.0.0
  drv run --commit HEAD alpha; rc_is "node off its pin (a file read as data)" 2 "$DRV_RC"
  unset SHIM_V_node
  export SHIM_CONTAINER_OS=Darwin
  drv run --commit HEAD alpha; rc_is "an image that is not Linux" 2 "$DRV_RC"; has "says so" "$work/drv.out" "not Linux"
  unset SHIM_CONTAINER_OS
  # A passing run, a dirty working copy, and the facts.
  printf 'two\n' > "$FX/src/marker.txt"; printf 'junk\n' > "$FX/untracked.txt"
  git -C "$FX" status --porcelain > "$work/status.before"
  drv run --commit HEAD alpha
  rc_is "a passing run" 0 "$DRV_RC"
  git -C "$FX" status --porcelain > "$work/status.after"
  check "a dirty working copy is changed by nothing" cmp -s "$work/status.before" "$work/status.after"
  eq "the working copy's file is still its dirty content" two "$(cat "$FX/src/marker.txt")"
  has "the commit's content ran, never the dirty working copy's" "$st/logs/alpha-$key.log" "marker=one job=alpha"
  eq "no worktree was made (DESIGN.md §6.2 step 3)" 1 "$(git -C "$FX" worktree list | wc -l | tr -d ' ')"
  check "and none is registered under the git dir" test ! -d "$FX/.git/worktrees"
  git -C "$FX" checkout -q -- src/marker.txt; rm -f "$FX/untracked.txt"
  check "the passing entry is written under the state directory" test -f "$entry"
  first="$(awk '{print $1}' "$entry" | tr '\n' ' ')"
  eq "the facts in field order" "kitfix-local-ci job key commit started duration_s platform host docker image go node unit_tests integration_tests log_sha256 " "$first"
  has "the format line is the manifest's" "$entry" "kitfix-local-ci v1"
  has "the platform is the container's" "$entry" "platform linux/arm64"
  has "the commit is the one tested" "$entry" "commit $(git -C "$FX" rev-parse HEAD)"
  has "the pin line is the image's answer" "$entry" "go go1.27.3"
  has "the counts are the log's" "$entry" "integration_tests 2"
  eq "log_sha256 is the log's hash" "$(sha256_of "$st/logs/alpha-$key.log")" "$(awk '$1=="log_sha256"{print $2}' "$entry")"
  # The job container's isolation (DESIGN.md §6.2 step 10): flags and the environment by name.
  line="$(grep 'cikit-enter alpha' "$DOCKER_LOG" | head -1)"
  case "$line" in *" --rm "*) ok "the job container is --rm" ;; *) bad "no --rm: $line" ;; esac
  case "$line" in *"--user 1001:1001"*) ok "it runs as the manifest's user" ;; *) bad "no --user: $line" ;; esac
  case "$line" in *"--name kitfix-ci-alpha-"*) ok "it is named for project, job and run id" ;; *) bad "no name: $line" ;; esac
  case "$line" in *--privileged* | *--pid*) bad "a privileged or pid flag: $line" ;; *) ok "never --privileged, never --pid" ;; esac
  case "$line" in *docker.sock* | *"--network host"* | *--publish* | *" -p "*) bad "socket, host network or published port on alpha: $line" ;; *) ok "no socket, no host network, no published port on alpha" ;; esac
  case "$line" in *"type=volume,source=kitfix-ci-gomod,target=/home/ci/go/pkg/mod"*"source=kitfix-ci-gobuild"*"source=kitfix-ci-npm,target=/home/ci/.npm"*) ok "named volumes for the cache kinds, not bind mounts" ;; *) bad "caches: $line" ;; esac
  names="$(printf '%s\n' "$line" | tr ' ' '\n' | awk '$0=="-e"{getline; split($0,a,"="); print a[1]}' | sort | tr '\n' ' ')"
  eq "-e carries only the allow-list's names" "CIKIT_ADAPTER CIKIT_INSTALL CIKIT_JOB CIKIT_PROJECT CIKIT_TREE KITFIX_TEST_PG_URL " "$names"
  export GO_TEST_COUNT=; drv run --commit HEAD alpha
  rc_is "(a second run of the same key re-runs)" 0 "$DRV_RC"
  case "$(grep 'cikit-enter alpha' "$DOCKER_LOG" | head -1)" in *"-e GO_TEST_COUNT="*) ok "an env name set and empty is passed, empty included" ;; *) bad "GO_TEST_COUNT not passed" ;; esac
  unset GO_TEST_COUNT
  drv run --commit HEAD alpha
  case "$(grep 'cikit-enter alpha' "$DOCKER_LOG" | head -1)" in *GO_TEST_COUNT*) bad "an unset env name was passed" ;; *) ok "an env name that is unset is not passed" ;; esac
  # The services: sidecar on its own network, published nowhere, removed on every exit.
  has "the sidecar's network is made" "$DOCKER_LOG" "network create kitfix-ci-"
  case "$(grep 'run -d' "$DOCKER_LOG" | head -1)" in
    *"--name kitfix-check-postgres-"*"--network kitfix-ci-"*"POSTGRES_USER=kitfix"*"postgres:18@sha256:"*"-c fsync=off -c max_connections=300"*) ok "the sidecar: name, network, credentials, digest image, flags" ;;
    *) bad "the sidecar: $(grep 'run -d' "$DOCKER_LOG" | head -1)" ;;
  esac
  case "$(grep 'run -d' "$DOCKER_LOG" | head -1)" in *--publish* | *" -p "*) bad "the sidecar publishes a port" ;; *) ok "the sidecar publishes nothing" ;; esac
  has "it is waited on with pg_isready" "$DOCKER_LOG" "pg_isready -U kitfix"
  has "the job's URL is in url-env" "$DOCKER_LOG" "KITFIX_TEST_PG_URL=postgres://kitfix:kitfix-test-password@kitfix-check-postgres-"
  has "removed on success with its volume (-v)" "$DOCKER_LOG" "rm -f -v kitfix-check-postgres-"
  has "the network is removed" "$DOCKER_LOG" "network rm kitfix-ci-"
  export ADAPTER_alpha=fail
  drv run --commit HEAD alpha
  rc_is "a failing verdict" 1 "$DRV_RC"
  has "prints the sidecar's last 200 log lines" "$DOCKER_LOG" "logs --tail 200 kitfix-check-postgres-"
  has "removes the sidecar on failure" "$DOCKER_LOG" "rm -f -v kitfix-check-postgres-"
  has "removes the network on failure" "$DOCKER_LOG" "network rm kitfix-ci-"
  has "names the failure and the log" "$work/drv.out" "alpha failed after"
  rm -f "$entry"
  drv run --commit HEAD alpha; check "a failing run writes no entry" test ! -f "$entry"
  export ADAPTER_alpha=hang; rm -f "$SHIM_STATE/job-started"
  : > "$DOCKER_LOG"; DRV_RC=0
  host python3 "$KITT_FIX/sigint.py" "$SHIM_STATE/job-started" "$BASH" "$KITT_KIT/bin/local-ci" run --commit HEAD alpha > "$work/drv.out" 2>&1 || DRV_RC=$?
  # the group's SIGINT may leave the launcher a moment to finish its cleanup after the driver is gone
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50; do
    grep -qF "network rm kitfix-ci-" "$DOCKER_LOG" && break
    /bin/sleep 0.2
  done
  check "SIGINT stops the run non-zero" test "$DRV_RC" -ne 0
  has "SIGINT removes the job container" "$DOCKER_LOG" "rm -f -v kitfix-ci-alpha-"
  has "SIGINT removes the sidecar" "$DOCKER_LOG" "rm -f -v kitfix-check-postgres-"
  has "SIGINT removes the network" "$DOCKER_LOG" "network rm kitfix-ci-"
  check "SIGINT leaves no lock behind" test ! -d "$st/lock"
  rm -f "$SHIM_STATE/job-started"
  # The counts and skip rules.
  for m in nocounts:"has no counts line" zero:"counted unit_tests as 0" ten:"counted unit_tests as 1234567890" unlisted:"says some/harness:leg did not run" failcounts:"alpha failed after"; do
    export ADAPTER_alpha="${m%%:*}"; rm -f "$entry"
    drv run --commit HEAD alpha
    check "${m%%:*}: no entry is written" test ! -f "$entry"
    check "${m%%:*}: the run does not pass" test "$DRV_RC" -ne 0
    has "${m%%:*}: the sentence" "$work/drv.out" "${m#*:}"
  done
  export ADAPTER_alpha=allowed; drv run --commit HEAD alpha
  rc_is "an allowed NOT RUN leg" 0 "$DRV_RC"; has "becomes a not_run fact" "$entry" "not_run tests/run:docker-leg"
  export ADAPTER_alpha=prose; drv run --commit HEAD alpha
  rc_is "prose holding the words NOT RUN" 0 "$DRV_RC"; hasnt "writes no not_run line" "$entry" not_run
  unset ADAPTER_alpha
  # The lock.
  export CIKIT_LOCK_WAIT_S=2 CIKIT_LOCK_TICK_S=1
  sleep 60 & holder=$!; bg_pids="$bg_pids $holder"
  mkdir -p "$st/lock"; echo "$holder" > "$st/lock/pid"
  drv run --commit HEAD alpha
  rc_is "a live holder: the run waits, then refuses" 2 "$DRV_RC"
  has "it waits with a line a tick" "$work/drv.out" "Waiting for the check run in process $holder to finish"
  has "and refuses naming the holder's process id" "$work/drv.out" "Another check run, process $holder, still holds the lock"
  kill "$holder"; wait "$holder" 2> /dev/null || true
  drv run --commit HEAD alpha
  rc_is "a stale lock (its holder gone) is taken over" 0 "$DRV_RC"
  check "by rename, leaving nothing aside" test -z "$(ls -d "$st"/lock.stale-* 2> /dev/null)"
  check "and the lock is released at the end" test ! -d "$st/lock"
  # (the short wait stays for the rest of the family, so a defect cannot hang it)
  # The history and socket job.
  drv run --commit HEAD delta
  rc_is "delta, the history and socket job" 0 "$DRV_RC"
  line="$(grep 'cikit-enter delta' "$DOCKER_LOG" | head -1)"
  case "$line" in *"-v /var/run/docker.sock:/var/run/docker.sock --group-add 991 --network host"*) ok "delta gets the socket, its group and the host network" ;; *) bad "delta flags: $line" ;; esac
  case "$line" in *"-e CIKIT_COMMIT=$(git -C "$FX" rev-parse HEAD)"*) ok "and takes the pack route with CIKIT_COMMIT" ;; *) bad "no CIKIT_COMMIT: $line" ;; esac
  git clone -q --depth 1 "file://$FX" "$work/shallow"
  fxsave="$FX"; FX="$work/shallow"
  drv run --commit HEAD delta
  FX="$fxsave"
  rc_is "a shallow clone for a history job (the launcher refuses with 2; the driver reports the job failed)" 1 "$DRV_RC"; has "is refused before any container" "$work/drv.out" "needs the commit's whole history and this clone is shallow, so delta did not run."
  hasnt "no job container started" "$DOCKER_LOG" cikit-enter
}

