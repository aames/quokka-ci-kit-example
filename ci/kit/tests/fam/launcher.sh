# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-launcher (kit/README.md §6.2): the flags per job class against the
# fixture manifest, read from the docker shim's record of every call.
launch() { # launch <job> [VAR=value...]: LCH_RC, the docker record
  local job="$1" kv; shift
  # shellcheck disable=SC2163
  for kv in "$@"; do export "$kv"; done
  : > "$DOCKER_LOG"; LCH_RC=0
  host "$BASH" "$KITT_KIT/bin/container" run --run-id T1 --commit HEAD "$job" > "$work/lch.out" 2>&1 || LCH_RC=$?
  for kv in "$@"; do unset "${kv%%=*}"; done
}
fam_launcher() {
  local line hard names ran
  fx_new lch
  launch alpha
  rc_is "alpha, a service job" 0 "$LCH_RC"
  line="$(grep 'cikit-enter alpha' "$DOCKER_LOG")"
  case "$line" in *"--network kitfix-ci-T1"*) ok "alpha joins its run network" ;; *) bad "alpha network: $line" ;; esac
  case "$line" in *docker.sock* | *"--group-add"* | *"--network host"*) bad "a socket or host network on alpha: $line" ;; *) ok "alpha holds no socket, no group and no host network" ;; esac
  has "alpha's sidecar is on the same network" "$DOCKER_LOG" "run -d --name kitfix-check-postgres-T1 --network kitfix-ci-T1"
  # the ran file: the platform read inside the job image, after a pass (DESIGN.md 5.2)
  ran="$(state_dir)/ran/alpha/$(fx_key alpha)"
  eq "a pass writes the ran file: the image's platform and the image id" "platform linux/arm64 image sha256:" \
    "$(sed -E 's/^(image sha256:)[0-9a-f]{64}$/\1/' "$ran" 2> /dev/null | tr '\n' ' ' | sed 's/ $//')"
  line="$(grep -- 'uname -s -m' "$DOCKER_LOG" | tail -1)"
  case "$line" in *"--network none --security-opt no-new-privileges --cap-drop ALL --user 1001:1001 kitfix-ci-job:"*) ok "the platform is read in the job image with no network and the hardening" ;; *) bad "the ran file's uname: $line" ;; esac
  launch alpha ADAPTER_alpha=fail
  rc_is "a failing job" 1 "$LCH_RC"
  check "removes an earlier ran file and writes none" test ! -e "$ran"
  launch alpha SHIM_UNAME_FAIL=1
  rc_is "a pass whose image says no platform is refused" 2 "$LCH_RC"
  has "with the sentence" "$work/lch.out" "alpha passed, but its image did not say its platform, so no record can be written for it."
  check "and writes no ran file" test ! -e "$ran"
  launch delta
  rc_is "delta, the socket and history job" 0 "$LCH_RC"
  line="$(grep 'cikit-enter delta' "$DOCKER_LOG")"
  case "$line" in *"-v /var/run/docker.sock:/var/run/docker.sock --group-add 991 --network host"*) ok "delta: the socket, its group and the host network" ;; *) bad "delta: $line" ;; esac
  case "$line" in *"source=kitfix-ci-gomod"*) ok "delta: its own cache kinds" ;; *) bad "delta caches: $line" ;; esac
  case "$line" in *kitfix-ci-npm* | *kitfix-ci-gobuild*) bad "delta mounts a cache its cache line does not name: $line" ;; *) ok "delta: no cache its line does not name" ;; esac
  check "delta runs in the job image, alpha's tag" grep -q "kitfix-ci-job:" <<< "$line"
  launch kitself
  rc_is "kitself, the kit job" 0 "$LCH_RC"
  line="$(grep 'cikit-enter kitself' "$DOCKER_LOG")"
  case "$line" in *"kitfix-ci-base:"*) ok "the kit job runs in the base image" ;; *) bad "kitself image: $line" ;; esac
  case "$line" in *"CIKIT_ADAPTER=ci/kit/tests/run"*) ok "its verdict is the kit's proofs, not the adapter" ;; *) bad "kitself adapter: $line" ;; esac
  case "$line" in *"--network bridge"*) ok "the default bridge: neither a service nor a socket" ;; *) bad "kitself network: $line" ;; esac
  launch beta; rc_is "a CI-only job" 2 "$LCH_RC"; has "is not a local job" "$work/lch.out" "beta is not a local job of"
  launch alpha GITHUB_ACTIONS=true
  rc_is "CI without RUNNER_TEMP" 2 "$LCH_RC"; has "refuses" "$work/lch.out" "RUNNER_TEMP is unset in CI"
  mkdir -p "$work/rt"
  launch alpha GITHUB_ACTIONS=true RUNNER_TEMP="$work/rt" GITHUB_RUN_ID=77 GITHUB_JOB=alpha
  rc_is "CI with RUNNER_TEMP" 0 "$LCH_RC"
  line="$(grep 'cikit-enter alpha' "$DOCKER_LOG")"
  case "$line" in *"type=bind,source=$work/rt/kitfix-ci-gomod,target=/home/ci/go/pkg/mod"*) ok "caches are directories under RUNNER_TEMP in CI" ;; *) bad "CI caches: $line" ;; esac
  case "$line" in *"-e GITHUB_ACTIONS=true"*) ok "GITHUB_ACTIONS is passed in CI" ;; *) bad "no GITHUB_ACTIONS: $line" ;; esac
  case "$line" in *"kitfix-ci-alpha-T1"*) ok "the run id is the run and job in CI" ;; *) bad "CI name: $line" ;; esac
  # the hardening is on the job run, the reader and the socket-group probe, and not on the sidecar (the security review, SECURITY.md)
  hard="--security-opt no-new-privileges --cap-drop ALL --user 1001:1001"
  launch alpha
  line="$(grep 'cikit-enter alpha' "$DOCKER_LOG")"
  case "$line" in *"--user 1001:1001 --security-opt no-new-privileges --cap-drop ALL"*) ok "the job run (alpha) reads no-new-privileges, cap-drop ALL and --user" ;; *) bad "alpha run: $line" ;; esac
  line="$(grep 'run -d --name kitfix-check-postgres' "$DOCKER_LOG")"
  case "$line" in *no-new-privileges* | *cap-drop* | *"--user"*) bad "the sidecar must run without the hardening: $line" ;; *) ok "the sidecar holds none of the three flags" ;; esac
  launch delta
  line="$(grep 'cikit-enter delta' "$DOCKER_LOG")"
  case "$line" in *"--security-opt no-new-privileges --cap-drop ALL"*) ok "the socket job takes them too" ;; *) bad "delta run: $line" ;; esac
  line="$(grep 'stat -c %g' "$DOCKER_LOG")"
  case "$line" in *"--security-opt no-new-privileges --cap-drop ALL --user 1001:1001"*) ok "the socket-group probe takes them" ;; *) bad "socket probe: $line" ;; esac
  : > "$DOCKER_LOG"; host "$BASH" "$KITT_KIT/bin/container" versions --commit HEAD alpha > /dev/null 2>&1
  line="$(grep -- '--network none' "$DOCKER_LOG" | head -1)"
  case "$line" in *"--security-opt no-new-privileges --cap-drop ALL --user 1001:1001"*) ok "the probe reader takes them" ;; *) bad "reader: $line" ;; esac
  # every git archive the launcher runs carries --literal-pathspecs (the security review, SECURITY.md)
  git_logger
  rm -f "$SHIM_STATE/images"
  KITT_PATH_PRE="$work/gitlogger" host "$BASH" "$KITT_KIT/bin/container" image --commit HEAD alpha > /dev/null 2>&1
  KITT_PATH_PRE="$work/gitlogger" host "$BASH" "$KITT_KIT/bin/container" versions --commit HEAD alpha delta > /dev/null 2>&1
  KITT_PATH_PRE="$work/gitlogger" host "$BASH" "$KITT_KIT/bin/container" run --run-id T2 --commit HEAD alpha > /dev/null 2>&1
  KITT_PATH_PRE="$work/gitlogger" host "$BASH" "$KITT_KIT/bin/container" run --run-id T3 --commit HEAD delta > /dev/null 2>&1
  eq "the launcher ran git archive for the base, the job image, the probes and the job run" "4" "$(grep -c 'archive --format=tar' "$SHIM_GIT_LOG")"
  eq "every git archive carries --literal-pathspecs" "0" "$(grep 'archive --format=tar' "$SHIM_GIT_LOG" | grep -vc '^--literal-pathspecs archive')"
  unset SHIM_GIT_LOG
  # CI=true enters the job container under GITHUB_ACTIONS only (DESIGN.md §6.2, kit/README.md §2.2)
  launch alpha GITHUB_ACTIONS=true RUNNER_TEMP="$work/rt" GITHUB_RUN_ID=78 GITHUB_JOB=alpha
  rc_is "CI=true (a): a run with the runner's variables" 0 "$LCH_RC"
  line="$(grep 'cikit-enter alpha' "$DOCKER_LOG")"
  names="$(grep -oE -- '-e [A-Za-z_][A-Za-z0-9_]*=' <<< "$line" | sed 's/^-e //; s/=$//' | sort | tr '\n' ' ')"
  case "$line" in *"-e CI=true"*) ok "CI=true (a): the job container carries CI=true" ;; *) bad "CI=true (a) no CI=true: $line" ;; esac
  case "$line" in *"-e GITHUB_ACTIONS=true"*) ok "CI=true (a): and GITHUB_ACTIONS=true" ;; *) bad "CI=true (a) no GITHUB_ACTIONS: $line" ;; esac
  case " $names" in *" ACTIONS_"* | *" RUNNER_"*) bad "CI=true (a): a runner variable entered: $names" ;; *) ok "CI=true (a): and nothing of ACTIONS_* or RUNNER_* ($names)" ;; esac
  launch alpha CI=true
  rc_is "CI=true (b): a run with CI=true and no GITHUB_ACTIONS" 0 "$LCH_RC"
  line="$(grep 'cikit-enter alpha' "$DOCKER_LOG")"
  case "$line" in *"-e CI="* | *"-e GITHUB_ACTIONS="*) bad "CI=true (b): CI entered without GITHUB_ACTIONS: $line" ;; *) ok "CI=true (b): no CI in the container without GITHUB_ACTIONS" ;; esac
  export GITHUB_ACTIONS=true CI=true
  drv run --commit HEAD alpha
  unset GITHUB_ACTIONS CI
  rc_is "CI=true (c): local-ci run with both exported by its caller" 0 "$DRV_RC"
  line="$(grep 'cikit-enter alpha' "$DOCKER_LOG")"
  case "$line" in
    "") bad "CI=true (c): no job container ran" ;;
    *"-e CI="* | *"-e GITHUB_ACTIONS="*) bad "CI=true (c): local-ci passed CI or GITHUB_ACTIONS: $line" ;;
    *) ok "CI=true (c): local-ci's container carries neither CI nor GITHUB_ACTIONS" ;;
  esac
  fx_reset
  sed "s/^env alpha GO_TEST_COUNT/env alpha CI/" "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest" && fx_commit "env CI"
  launch alpha
  rc_is "CI=true (d): the launcher refuses env alpha CI" 2 "$LCH_RC"
  has "CI=true (d): and names it" "$work/lch.out" "env names CI, which the kit reserves"
  hasnt "CI=true (d): and ran no job" "$DOCKER_LOG" "cikit-enter alpha"
  # the launcher refuses the reserved names of the one list; nothing is run (the security review, SECURITY.md)
  for v in ACTIONS_RUNTIME_TOKEN RUNNER_TEMP GH_TOKEN GIT_DIR SSH_AUTH_SOCK DOCKER_HOST NPM_TOKEN DEPLOY_KEY DB_PASSWORD; do
    fx_reset
    sed "s/^env alpha GO_TEST_COUNT/env alpha $v/" "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest" && fx_commit "env $v"
    launch alpha
    rc_is "the launcher refuses env $v" 2 "$LCH_RC"
    has "and names it" "$work/lch.out" "$v"
    hasnt "and ran no job" "$DOCKER_LOG" "cikit-enter alpha"
  done
  fx_reset
  git -C "$FX" checkout -q -b old2 && git -C "$FX" rm -rfq . && printf 'x\n' > "$FX/x" && git -C "$FX" add x && git -C "$FX" commit -qm old
  launch alpha; rc_is "a commit that predates the kit" 2 "$LCH_RC"
  git -C "$FX" checkout -q -f main
  : > "$DOCKER_LOG"; LCH_RC=0
  host "$BASH" "$KITT_KIT/bin/container" run --run-id 'bad id!' --commit HEAD alpha > "$work/lch.out" 2>&1 || LCH_RC=$?
  rc_is "a run id Docker would not accept" 2 "$LCH_RC"
}
