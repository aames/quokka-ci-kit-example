
arm_@@FN@@() {
  local pin found json="${scratch}/vitest.json" files tests
  pin="$(tr -d '[:space:]' < @@PIN_FILE@@ 2> /dev/null)"
  found=""
  if command -v node > /dev/null 2>&1; then found="$(node --version 2> /dev/null)"; fi
  need node "$found" "$pin"
  cd @@DIR@@ || refuse "The tree has no @@DIR@@ directory, so ${job} did not run."
@@SERVICE_CHECK@@
  @@NEED_BINS@@ \
    || refuse "@@JOB@@'s dependencies are not installed, so ${job} did not run."

@@TSC_STEP@@
  step "vitest run" node_modules/.bin/vitest run --reporter=default --reporter=json --outputFile="$json"
  files="$(jq -r '.testResults | length' "$json")" || failed "vitest's report could not be read, so ${job} failed."
  tests="$(jq -r '.numPassedTests' "$json")" || failed "vitest's report could not be read, so ${job} failed."
  echo "${PROJECT}-ci-job v1 counts @@JOB@@ vitest_files ${files} vitest_tests ${tests}"
}
