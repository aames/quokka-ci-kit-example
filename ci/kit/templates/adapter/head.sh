#!/usr/bin/env bash
#
# THE VERDICT SCRIPT: every check that decides a job, as one command list.
#
#   bash ci/ci-job.sh <job>
#     exit 0   every check of <job> passed, and the last line is its counts line
#     exit 2   refused before any check: an unknown job, a tool absent or off its pin
#     other    a check failed
#
# CI runs it and `make check` runs it the same way: ci/kit/bin/container
# copies the commit's tree into the job image and runs this file there, so a
# workstation's verdict and CI's come from one command list under one key.
#
# Settings come from the environment only:
#   @@PROJECT_UPPER@@_TEST_PG_URL  the throwaway Postgres of a job with a `service` line
#                         in ci/manifest, started and handed in by the kit,
#                         never the developer's database
#   GITHUB_ACTIONS        `true` under CI: refusals and failures carry ::error::
#
# Each step's exit status is read directly, never through a pipe; a step
# whose output is counted writes to a file first, and the file is shown after.
set -uo pipefail

readonly PROJECT=@@PROJECT@@
job="${1:-}"

err() {
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    printf '::error::%s\n' "$1" >&2
  else
    printf '%s\n' "$1" >&2
  fi
}
refuse() { err "$1"; exit 2; }
failed() { err "$1"; exit 1; }

# need <tool> <found> <pin>: refuse unless the tool answered at its pin, one
# leading v dropped from each side and nothing else.
need() {
  local tool="$1" found="$2" pin="$3"
  [ -n "$pin" ] || refuse "The tree pins no ${tool}, so ${job} did not run."
  [ -n "$found" ] || refuse "${tool} is not installed, so ${job} did not run."
  [ "${found#v}" = "${pin#v}" ] || refuse "${tool} ${found} is not the pinned ${pin}, so ${job} did not run."
}

# step <description> <command>...: runs one check; a non-zero status ends the job.
step() {
  local what="$1" rc=0
  shift
  echo "--- ${what}"
  "$@" || rc=$?
  [ "$rc" -eq 0 ] || failed "${what} failed (exit ${rc}), so ${job} failed."
}

scratch="$(mktemp -d)" || refuse "No temporary directory could be made, so ${job} did not run."
trap 'rm -rf -- "$scratch"' EXIT
