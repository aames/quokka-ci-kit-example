
arm_@@FN@@() {
  local pin found out="${scratch}/go-test.log" rc=0 packages tests
  pin="$(awk '$1 == "toolchain" { print $2; exit }' @@PIN_FILE@@ 2> /dev/null)"
  found=""
  if command -v go > /dev/null 2>&1; then found="$(go env GOVERSION 2> /dev/null)"; fi
  need go "$found" "$pin"
  cd @@DIR@@ || refuse "The tree has no @@DIR@@ directory, so ${job} did not run."
@@SERVICE_CHECK@@

  step "gofmt" test -z "$(gofmt -l .)"
  step "go vet" go vet ./...
  echo "--- go test"
  go test -count=1 -v ./... > "$out" 2>&1 || rc=$?
  cat "$out"
  [ "$rc" -eq 0 ] || failed "go test failed (exit ${rc}), so ${job} failed."
  packages="$(grep -c '^ok ' "$out")" || packages=0
  tests="$(grep -c '^--- PASS: ' "$out")" || tests=0
  echo "${PROJECT}-ci-job v1 counts @@JOB@@ go_packages ${packages} go_tests ${tests}"
}
