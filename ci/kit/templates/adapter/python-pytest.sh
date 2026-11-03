
arm_@@FN@@() {
  local pin found venv="${scratch}/venv" report="${scratch}/pytest.xml" tests
  pin="$(tr -d '[:space:]' < @@PIN_FILE@@ 2> /dev/null)"
  found=""
  if command -v python3 > /dev/null 2>&1; then found="$(python3 -c 'import platform; print(platform.python_version())' 2> /dev/null)"; fi
  need python "$found" "$pin"
  cd @@DIR@@ || refuse "The tree has no @@DIR@@ directory, so ${job} did not run."
@@SERVICE_CHECK@@

  step "venv" python3 -m venv "$venv"
  step "pip install" "${venv}/bin/pip" install --quiet --require-hashes -r @@REQUIREMENTS@@
  step "pytest" "${venv}/bin/python" -m pytest --junitxml="$report"
  # The tests that passed: each suite's tests less its failures, errors and skips.
  tests="$("${venv}/bin/python" -c 'import sys, xml.etree.ElementTree as E
r = E.parse(sys.argv[1]).getroot()
s = [r] if r.tag == "testsuite" else list(r.iter("testsuite"))
print(sum(int(x.get(k, 0)) * (1 if k == "tests" else -1) for x in s for k in ("tests", "failures", "errors", "skipped")))' "$report")" \
    || failed "pytest's report could not be read, so ${job} failed."
  echo "${PROJECT}-ci-job v1 counts @@JOB@@ pytest_tests ${tests}"
}
