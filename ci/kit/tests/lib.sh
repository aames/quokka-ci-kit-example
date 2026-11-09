#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2154,SC2016
# THE KIT'S PROOFS: the shared helpers (kit/README.md §6.1; sourced by tests/run
# and tests/image, never run alone).
#
# KITT_KIT is the kit tree under test (bin/, lib/, hooks/, image/): the tree
# this file sits in by default, a mutated copy when tests/plants plants a
# defect (kit/README.md §6.2). Everything a family needs from the
# kit it takes from there, so a plant changes exactly one file of one copy.
#
# THE HOST FARM. The driver, the hook and the launcher run on a PATH holding
# only the shims and a directory of symlinks to EXACTLY the host allow-list
# (git, docker, mkdir, mv, rm, mktemp, cat, date, uname, sleep, kill, tail,
# head, tr, wc, shasum, sha256sum: kit/README.md §2.2) plus bash, sh, ssh-keygen and
# python3 for the harness, and awk and cut that kit/lib/keys.sh's header
# names. A host tool outside it fails where it is called, not here.
# shellcheck disable=SC2034
set -uo pipefail

KITT_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KITT_KIT="${KITT_KIT:-$(cd -- "$KITT_HERE/.." && pwd)}"
KITT_FIX="$KITT_HERE/fixture"
KITT_SYS_PATH="$PATH"
export KITT_SYS_PATH
KITT_PROJECT="${CIKIT_PROJECT:-kitfix}"
KITT_JOB="${CIKIT_JOB:-kitself}"

work="$(mktemp -d "${TMPDIR:-/tmp}/cikit-lct-XXXXXX")"
bg_pids=""
kitt_cleanup() {
  local p
  for p in $bg_pids; do kill "$p" 2> /dev/null || true; done
  rm -rf "$work"
}
trap kitt_cleanup EXIT

cases=0 failures=0 family="${family:-}"
ok() { cases=$((cases + 1)); [ "${KITT_QUIET:-}" = 1 ] || echo "ok: [$family] $1"; }
bad() { cases=$((cases + 1)); failures=$((failures + 1)); echo "FAIL: [$family] $1"; }
note_not_run() { echo "NOT RUN $1: $2"; }
show() { sed 's/^/    /' "$1" 2> /dev/null | head -"${2:-25}"; }
# check <label> <command...>: ok when the command succeeds.
check() { local l="$1"; shift; if "$@"; then ok "$l"; else bad "$l"; fi; }
# eq <label> <want> <got>
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: wanted [$2], got [$3]"; fi; }
# has <label> <file> <fixed string>; hasnt likewise
has() { if grep -qF -- "$3" "$2" 2> /dev/null; then ok "$1"; else bad "$1: [$3] not in $2"; show "$2"; fi; }
hasnt() { if grep -qF -- "$3" "$2" 2> /dev/null; then bad "$1: [$3] is in $2"; show "$2"; else ok "$1"; fi; }
# rc_is <label> <want> <got>
rc_is() { eq "$1 (exit code)" "$2" "$3"; }

# bash 4.2 or later, for the runner-only entry points; empty when none.
find_bash4() {
  local b
  for b in "$BASH" /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash /bin/bash "$(command -v bash)"; do
    [ -x "$b" ] || continue
    if "$b" -c '[ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; }' 2> /dev/null; then
      echo "$b"
      return 0
    fi
  done
  return 1
}
# a bash older than 4, for the refusals; empty when none.
find_bash32() {
  local b
  for b in "$BASH" /bin/bash /opt/bash-3.2/bin/bash; do
    [ -x "$b" ] || continue
    if "$b" -c '[ "${BASH_VERSINFO[0]}" -lt 4 ]' 2> /dev/null; then echo "$b"; return 0; fi
  done
  return 1
}
BASH4="$(find_bash4 || true)"
BASH32="$(find_bash32 || true)"
# a python3 that has PyYAML (the workflow fence reads YAML).
PYYAML=""
for p in python3 python3.14 python3.13 python3.12 /opt/homebrew/bin/python3.14; do
  if command -v "$p" > /dev/null 2>&1 && "$p" -c 'import yaml' 2> /dev/null; then PYYAML="$(command -v "$p")"; break; fi
done

# A runner's own CI variables never reach a case: GITHUB_* and RUNNER_TEMP are
# dropped here, so each case sets or leaves unset both itself (launch ... GITHUB_ACTIONS=true
# RUNNER_TEMP=<its own dir>) and the same cases pass on a workstation and on a runner.
for v in $(compgen -v); do
  case "$v" in GITHUB_* | RUNNER_TEMP | RUNNER_OS | CI) unset "$v" ;; esac
done

sha256_of() { if command -v sha256sum > /dev/null 2>&1; then sha256sum "$1" | cut -c1-64; else shasum -a 256 "$1" | cut -c1-64; fi; }

# --- the host farm ---------------------------------------------------------------------
farm="$work/farm"
mkdir -p "$farm" "$work/shims"
for t in git docker mkdir mv rm mktemp cat date uname sleep kill tail head tr wc shasum sha256sum sh ssh-keygen python3 awk cut; do
  p="$(command -v "$t" 2> /dev/null || true)"
  case "$p" in /*) ln -sf "$p" "$farm/$t" ;; esac
done
ln -sf "$BASH" "$farm/bash"
# the shims, which restore the system PATH for their own work
cp "$KITT_FIX"/shims/* "$work/shims/"
chmod +x "$work/shims"/*
HOSTPATH="$work/shims:$farm"
# the docker shim's job image tools and its state
export SHIM_STATE="$work/state" DOCKER_LOG="$work/docker.log" TOOLS="$work/tools"
mkdir -p "$SHIM_STATE" "$TOOLS"
: > "$DOCKER_LOG"

# tool shims the job image holds: the pinned tools' outputs imitate the real ones.
mk_tool() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$TOOLS/$1"; chmod +x "$TOOLS/$1"; }
mk_tool go 'case "$*" in "env GOVERSION") echo "${SHIM_V_go:-go1.27.3}";; esac; [ -z "${SHIM_GO_NOTICE:-}" ] || echo "go: downloading go1.99 (linux/amd64)" >&2'
mk_tool node 'echo "${SHIM_V_node:-v24.1.0}"'
mk_tool shellcheck '[ -z "${SHIM_NOTICE_shellcheck:-}" ] || echo "version: 0.0.0-notice" >&2; printf "ShellCheck - shell script analysis tool\nversion: %s\nlicense: GPL\n" "${SHIM_V_shellcheck:-0.11.0}"'
mk_tool python3 'case "$*" in *version_info*) echo "${SHIM_V_python:-3.14}";; esac'
mk_tool golangci-lint 'echo "golangci-lint has version ${SHIM_V_golangci:-2.15.0} built with go1.27.3 from abc on 2026-10-01"'
mk_tool promtool 'echo "promtool, version ${SHIM_V_promtool:-3.5.0} (branch: HEAD, revision: abc)"'
mk_tool cosign 'case "$1" in --version) exit 1;; version) printf "GitVersion:    v%s\nGitCommit:     abc\n" "${SHIM_V_cosign:-3.1.3}";; esac'
mk_tool ansible-playbook 'echo "ansible-playbook [core ${SHIM_V_ansible:-2.21.4}]"; echo "  config file = None"'

# --- git, keys, a fixture repository ----------------------------------------------------
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@invalid GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@invalid
mkdir -p "$work/keys"
[ -f "$work/keys/a" ] || ssh-keygen -q -t ed25519 -N '' -C signer-a@fixture -f "$work/keys/a" > /dev/null
[ -f "$work/keys/b" ] || ssh-keygen -q -t ed25519 -N '' -C signer-b@fixture -f "$work/keys/b" > /dev/null
signers_line() { printf 'signer-%s@fixture %s\n' "$1" "$(cut -d' ' -f1,2 "$work/keys/$1.pub")"; }

# fx_new <name>: a bare origin and a clone at $work/<name>/{origin.git,repo}
# holding the fixture manifest's repository with ci/kit copied from the kit
# under test; FX is the clone. One commit on main, pushed.
fx_new() {
  local d="$work/$1" f
  rm -rf "$d"
  mkdir -p "$d"
  rm -f "$SHIM_STATE/images"
  git init -q --bare --initial-branch=main "$d/origin.git"
  git init -q --initial-branch=main "$d/repo"
  FX="$d/repo" FXO="$d/origin.git"
  git -C "$FX" config user.email fixture@invalid
  git -C "$FX" config user.name fixture
  git -C "$FX" config user.signingkey "$work/keys/a"
  git -C "$FX" config gpg.format ssh
  mkdir -p "$FX/ci/image" "$FX/ci/kit" "$FX/src/a" "$FX/src/web" "$FX/deploy" "$FX/obs" "$FX/.github/workflows" "$FX/.githooks"
  cp "$KITT_FIX/manifest" "$FX/ci/manifest"
  cp "$KITT_FIX/adapter.sh" "$FX/ci/adapter.sh"
  cp "$KITT_FIX/workflows/green.yml" "$FX/.github/workflows/ci.yml"
  printf 'ARG CIKIT_BASE\nFROM ${CIKIT_BASE}\n' > "$FX/ci/image/Dockerfile"
  printf '# the plan extension\n:\n' > "$FX/ci/plan-extension.sh"
  signers_line a > "$FX/ci/allowed-signers"
  printf 'module fixture\n\ngo 1.27\n\ntoolchain go1.27.3\n' > "$FX/src/go.mod"
  printf 'v24.1.0\n' > "$FX/src/web/.nvmrc"
  printf 'readonly SHELLCHECK_VERSION=v0.11.0\nreadonly PYTHON_VERSION=3.14\n' > "$FX/tools.sh"
  printf 'one\n' > "$FX/src/marker.txt"
  printf '#!/bin/sh\necho tool\n' > "$FX/deploy/tool.sh"
  printf 'package a\n\nimport ("path/filepath")\n\nvar _ = filepath.Join("..", "..", "deploy", "tool.sh")\n' > "$FX/src/a/a_test.go"
  printf 'export const x = 1\n' > "$FX/src/web/x.test.ts"
  printf 'package obs\n\nimport ("path/filepath")\n\nvar _ = filepath.Join("..", "x")\n' > "$FX/obs/harness_test.go"
  printf 'check:\n\t@echo check\n' > "$FX/Makefile"
  printf 'readme\n' > "$FX/README.md"
  cp "$KITT_KIT/hooks/pre-push.shim" "$FX/.githooks/pre-push"
  chmod +x "$FX/.githooks/pre-push"
  for f in bin lib hooks image templates tests; do cp -R "$KITT_KIT/$f" "$FX/ci/kit/$f"; done
  git -C "$FX" add -A
  git -C "$FX" commit -qm kit
  fx_version
  git -C "$FX" remote add origin "$FXO"
  git -C "$FX" push -q --no-verify origin HEAD:refs/heads/main
  git -C "$FX" fetch -q origin
  FXBASE="$(git -C "$FX" rev-parse HEAD)"
}
# fx_version: ci/KIT-VERSION naming the tree of ci/kit (rule 7), as a commit.
fx_version() {
  local tree
  tree="$(git -C "$FX" rev-parse HEAD:ci/kit)"
  printf 'tag v0.0.0-fixture\ncommit %s\ntree %s\nsigner signer-a@fixture\nvendored 2026-11-01\n' "$(git -C "$FX" rev-parse HEAD)" "$tree" > "$FX/ci/KIT-VERSION"
  git -C "$FX" add ci/KIT-VERSION
  git -C "$FX" commit -qm version
}
# fx_reset: back to the fixture's first commit.
fx_reset() { git -C "$FX" reset -q --hard "$FXBASE"; }
# fx_commit <message>: commit everything in the clone.
fx_commit() { git -C "$FX" add -A && git -C "$FX" commit -qm "$1"; }
# fx_key <job> [commit]: the key by the library under test.
fx_key() { KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/keys" "${2:-HEAD}" "$1"; }

# host <command...>: run on the farm with the shims, inside the fixture clone
# (cwd = $FX), on exactly the allow-list; the SHIM_, ADAPTER_ and KITT_MARK
# variables of the harness reach it, and no other.
host() {
  local v ev=()
  ev=(HOME="$work" TMPDIR="$work" PATH="${KITT_PATH_PRE:+$KITT_PATH_PRE:}$HOSTPATH" SYS_PATH="$KITT_SYS_PATH" SHIM_STATE="$SHIM_STATE" DOCKER_LOG="$DOCKER_LOG" TOOLS="$TOOLS"
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0 GH_TABLE="${GH_TABLE:-}")
  for v in $(compgen -v); do
    case "$v" in SHIM_STATE) ;; SHIM_* | ADAPTER_* | KITT_MARK* | CIKIT_LOCK_* | CIKIT_REMOTE | GITHUB_* | RUNNER_TEMP | GO_TEST_COUNT | CI) ev+=("$v=${!v}") ;; esac
  done
  ( cd "$FX" && env -i "${ev[@]}" "$@" )
}

# git_logger: a directory holding a git that appends its arguments to
# $SHIM_GIT_LOG and then runs the real one; put it first on the host's PATH with
# KITT_PATH_PRE="$work/gitlogger" (host() takes that variable; SHIM_GIT_LOG
# reaches the wrapper as every SHIM_ variable does).
git_logger() {
  mkdir -p "$work/gitlogger"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$SHIM_GIT_LOG"\nPATH="$SYS_PATH" exec git "$@"\n' > "$work/gitlogger/git"
  chmod +x "$work/gitlogger/git"
  SHIM_GIT_LOG="$work/git-calls.log"; export SHIM_GIT_LOG
  : > "$SHIM_GIT_LOG"
}

# lib4 <snippet>: the library sourced under bash 4.2 or later, on the fixture
# clone ($FX), the gh shim on PATH; prints what the snippet prints.
lib4() {
  KIT_KEYS_REPO="$FX" GH_TABLE="${GH_TABLE:-/dev/null}" GH_LOG="${GH_LOG:-}" GH_FAIL="${GH_FAIL:-}" CI_PLAN_FORCE="${CI_PLAN_FORCE:-}" CI_PLAN_TASK="${CI_PLAN_TASK:-}" \
    PATH="$work/shims:$KITT_SYS_PATH" "$BASH4" -c ". '$KITT_KIT/lib/keys.sh'; $1"
}
# need_bash4 <family>: true when a bash 4.2 exists, else the NOT RUN line.
need_bash4() { if [ -n "$BASH4" ]; then return 0; fi; note_not_run tests/run:bash4 "no bash 4.2 or later on this host, so the $1 family did not run"; return 1; }

# lrec <job> <key> <facts file> <signing key name> [<ref key>]: a signed tag
# object of that facts block at refs/ci/local/<job>/<ref key>; prints the object.
lrec() {
  local job="$1" key="$2" facts="$3" signer="$4" rk="${5:-$2}" obj
  git -C "$FX" -c gpg.format=ssh -c user.signingkey="$work/keys/$signer" tag -s --cleanup=verbatim -F "$facts" kitt-tmp "$(git -C "$FX" rev-parse HEAD)" > /dev/null
  obj="$(git -C "$FX" rev-parse refs/tags/kitt-tmp)"
  git -C "$FX" update-ref -d refs/tags/kitt-tmp
  git -C "$FX" update-ref "refs/ci/local/${job}/${rk}" "$obj"
  echo "$obj"
}
# lfacts <file> [sed expression]: alpha's facts block at HEAD, edited.
lfacts() {
  local key; key="$(fx_key alpha)"
  { printf 'kitfix-local-ci v1\njob alpha\nkey %s\ncommit %s\nstarted 2026-11-01T00:00:00+13:00\nduration_s 4\nplatform linux/arm64\nhost darwin/arm64\ndocker 29.9.2\nimage sha256:%s\n' \
      "$key" "$(git -C "$FX" rev-parse HEAD)" "$(printf 'ab%.0s' $(seq 1 32))"
    printf 'go go1.27.3\nnode v24.1.0\nunit_tests 3\nintegration_tests 2\nlog_sha256 %s\n' "$(printf 'cd%.0s' $(seq 1 32))"; } > "$1"
  if [ -n "${2:-}" ]; then sed -e "$2" "$1" > "$1.e" && mv "$1.e" "$1"; fi
}

# gfacts <file> <job> [sed expression]: a green record's facts block for <job>
# at HEAD (the record writer's shape), edited.
gfacts() {
  { printf 'kitfix-green v1\njob %s\nkey %s\ncommit %s\nplatform linux/amd64\nhost linux/amd64\nimage sha256:%s\nrun 4242\nworkflow_ref fixture/repo/.github/workflows/ci.yml@refs/heads/main\n' \
      "$2" "$(fx_key "$2")" "$(git -C "$FX" rev-parse HEAD)" "$(printf 'ab%.0s' $(seq 1 32))"; } > "$1"
  if [ -n "${3:-}" ]; then sed -e "$3" "$1" > "$1.e" && mv "$1.e" "$1"; fi
}
# grec <job> <key> <facts file> [<repo>]: an UNSIGNED tag object of that facts
# block naming <repo>'s HEAD (default the fixture clone), as the record writer
# makes one through the API, at refs/ci/green/<job>/<key> there; prints the object.
grec() {
  local r="${4:-$FX}" obj
  obj="$({ printf 'object %s\ntype commit\ntag ci/green/%s/%s\ntagger github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com> 1762646400 +0000\n\n' \
      "$(git -C "$r" rev-parse HEAD)" "$1" "$2"; cat "$3"; } | git -C "$r" mktag)"
  git -C "$r" update-ref "refs/ci/green/$1/$2" "$obj"
  echo "$obj"
}

# plan_run <VAR=value>...: the real plan under bash 4.2 or later in $FX at its
# HEAD, on a git that logs its calls and the gh shim; sets PLAN_RC and leaves
# $work/out (the outputs), $work/summary and $work/stdout.
plan_run() {
  mkdir -p "$work/gitlog"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$GIT_LOG"\nPATH="$KITT_SYS_PATH" exec git "$@"\n' > "$work/gitlog/git"
  chmod +x "$work/gitlog/git"
  : > "$work/out"; : > "$work/summary"; : > "$work/git.log"
  PLAN_RC=0
  ( cd "$FX" && env -i HOME="$work" TMPDIR="$work" PATH="$work/gitlog:$work/shims:$KITT_SYS_PATH" KITT_SYS_PATH="$KITT_SYS_PATH" GIT_LOG="$work/git.log" \
      GH_TABLE="${GH_TABLE:-/dev/null}" GH_LOG="${GH_LOG:-/dev/null}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0 \
      CI_PLAN_SHA="$(git rev-parse HEAD)" CI_PLAN_EVENT=push CI_PLAN_REPO=fixture/repo \
      GITHUB_OUTPUT="$work/out" GITHUB_STEP_SUMMARY="$work/summary" "$@" "$BASH4" "$KITT_KIT/bin/plan" ) > "$work/stdout" 2>&1 || PLAN_RC=$?
}
# decisions: the kit's per-job decisions from the last plan, on one line.
decisions() { grep -vE '_key=|_platform=|^main=|^ref_group=' "$work/out" | tr '\n' ' ' | sed 's/ $//'; }
out_of() { grep "^$1=" "$work/out" | head -1 | cut -d= -f2-; }

# drv <local-ci args...>: the driver on the farm in $FX; DRV_RC and $work/drv.out.
drv() {
  : > "$DOCKER_LOG"
  DRV_RC=0
  host "$BASH" "$KITT_KIT/bin/local-ci" "$@" > "$work/drv.out" 2>&1 || DRV_RC=$?
}
state_dir() { echo "$(git -C "$FX" rev-parse --path-format=absolute --git-common-dir)/kitfix-ci"; }
