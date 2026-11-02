#!/usr/bin/env bash
# THE TOY ADAPTER (kit/README.md §4.5), the fixture's one verdict script. Arms
# `alpha` and `delta` (local) and `beta` (CI-only); any other word is refused
# with 2 and no counts line. The mode is the environment variable
# ADAPTER_<JOB>:
#   (unset)   pass, one counts line
#   fail      exit 1, no counts line        failcounts  counts line, then exit 1
#   nocounts  pass, no counts line          zero        a zero count
#   ten       a ten-digit count             allowed     a NOT RUN line the manifest allows
#   unlisted  a NOT RUN line it does not    prose       prose holding the words NOT RUN
#   pipe      a counts line, then a failing step masked by a pipe
#   hang      waits for a signal            push        git push towards a GitHub prefix
# ADAPTER_MODE is the same switch for a real run, where a manifest `env` line
# can only name an upper-case variable.
set -uo pipefail
job="${1:-}"
case "$job" in alpha | delta | beta) ;; *) echo "refused: no job named ${job:-nothing}" >&2; exit 2 ;; esac
mode_var="ADAPTER_${job}"
mode="${!mode_var:-${ADAPTER_MODE:-}}"
project="${CIKIT_PROJECT:-kitfix}"
case "$job" in
  alpha | beta) fields="unit_tests 3 integration_tests 2" ;;
  delta) fields="harnesses 4" ;;
esac
echo "marker=$(cat src/marker.txt 2> /dev/null || echo none) job=${job}"
counts() { echo "${project}-ci-job v1 counts ${job} ${1:-$fields}"; }
case "$mode" in
  fail) exit 1 ;;
  failcounts) counts; exit 1 ;;
  nocounts) ;;
  zero) counts "unit_tests 0 integration_tests 2" ;;
  ten) counts "unit_tests 1234567890 integration_tests 2" ;;
  allowed) echo "NOT RUN tests/run:docker-leg: needs a daemon"; counts ;;
  unlisted) echo "NOT RUN some/harness:leg: no reason allowed"; counts ;;
  prose) echo "the words NOT RUN appear mid-line here, and this is only prose"; counts ;;
  pipe) counts; false | cat; echo "a step failed above and a pipe masked it" ;;
  hang) : > "${SHIM_STATE:-/tmp}/job-started"; sleep 30 ;;
  push) git push https://github.com/example/repo.git HEAD:refs/heads/x > /dev/null 2>&1 || echo "push refused"; counts ;;
  *) counts ;;
esac
exit 0
