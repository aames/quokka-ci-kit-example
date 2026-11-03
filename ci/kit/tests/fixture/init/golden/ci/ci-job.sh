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
#   ROTTNEST_TEST_PG_URL  the throwaway Postgres for api's integration test,
#                         started and handed in by the kit (ci/manifest's
#                         `service api` line), never the developer's database
#   GITHUB_ACTIONS        `true` under CI: refusals and failures carry ::error::
#
# Each step's exit status is read directly, never through a pipe; a step
# whose output is counted writes to a file first, and the file is shown after.
set -uo pipefail

readonly PROJECT=rottnest
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

arm_api() {
  local pin found out="${scratch}/go-test.log" rc=0 packages tests
  pin="$(awk '$1 == "toolchain" { print $2; exit }' api/go.mod 2> /dev/null)"
  found=""
  if command -v go > /dev/null 2>&1; then found="$(go env GOVERSION 2> /dev/null)"; fi
  need go "$found" "$pin"
  cd api || refuse "The tree has no api directory, so ${job} did not run."
  [ -n "${ROTTNEST_TEST_PG_URL:-}" ] || refuse "ROTTNEST_TEST_PG_URL is not set, so ${job} did not run."

  step "gofmt" test -z "$(gofmt -l .)"
  step "go vet" go vet ./...
  echo "--- go test"
  go test -count=1 -v ./... > "$out" 2>&1 || rc=$?
  cat "$out"
  [ "$rc" -eq 0 ] || failed "go test failed (exit ${rc}), so ${job} failed."
  packages="$(grep -c '^ok ' "$out")" || packages=0
  tests="$(grep -c '^--- PASS: ' "$out")" || tests=0
  echo "${PROJECT}-ci-job v1 counts api go_packages ${packages} go_tests ${tests}"
}

arm_web() {
  local pin found json="${scratch}/vitest.json" files tests
  pin="$(tr -d '[:space:]' < web/.nvmrc 2> /dev/null)"
  found=""
  if command -v node > /dev/null 2>&1; then found="$(node --version 2> /dev/null)"; fi
  need node "$found" "$pin"
  cd web || refuse "The tree has no web directory, so ${job} did not run."
  [ -x node_modules/.bin/tsc ] && [ -x node_modules/.bin/vitest ] \
    || refuse "web's dependencies are not installed, so ${job} did not run."

  step "tsc --noEmit" node_modules/.bin/tsc --noEmit
  step "vitest run" node_modules/.bin/vitest run --reporter=default --reporter=json --outputFile="$json"
  files="$(jq -r '.testResults | length' "$json")" || failed "vitest's report could not be read, so ${job} failed."
  tests="$(jq -r '.numPassedTests' "$json")" || failed "vitest's report could not be read, so ${job} failed."
  echo "${PROJECT}-ci-job v1 counts web vitest_files ${files} vitest_tests ${tests}"
}

case "$job" in
  api) arm_api ;;
  web) arm_web ;;
  *) refuse "There is no job named ${job:-(none)}, so nothing ran." ;;
esac
