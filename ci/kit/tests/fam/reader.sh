# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-reader (kit/README.md §6.2): the reader is composed from `probe` lines;
# the four kinds against fixture tools whose output imitates golangci-lint,
# the shellcheck tool, promtool, cosign, ansible-playbook and node.
fam_reader() {
  local got
  fx_new rd
  sed -e 's/^pin delta shellcheck python/pin delta shellcheck python golangci-lint promtool cosign ansible-core/' \
      -e 's/^probe python python-minor python3/&\nprobe golangci-lint after-word version golangci-lint --version\nprobe promtool version-flag\nprobe cosign version-flag\nprobe ansible-core after-word core ansible-playbook --version/' "$FX/ci/manifest" > "$work/m"
  cp "$work/m" "$FX/ci/manifest"; fx_commit "a pin for every kind the reader reads"
  : > "$DOCKER_LOG"
  host "$BASH" "$KITT_KIT/bin/container" versions --commit HEAD alpha delta > "$work/o" 2> "$work/e"
  rc_is "versions" 0 "$?"
  got="$(tr '\n' ',' < "$work/o")"
  eq "each tool's version, by its own kind, in pin order" "go go1.27.3,node v24.1.0,shellcheck 0.11.0,python 3.14,golangci-lint 2.15.0,promtool 3.5.0,cosign v3.1.3,ansible-core 2.21.4" "${got%,}"
  export SHIM_GO_NOTICE=1 SHIM_NOTICE_shellcheck=1
  host "$BASH" "$KITT_KIT/bin/container" versions --commit HEAD alpha delta > "$work/o2" 2> /dev/null
  check "a notice on stderr beside the answer changes nothing: stdout alone is read" cmp -s "$work/o" "$work/o2"
  unset SHIM_GO_NOTICE SHIM_NOTICE_shellcheck
  sed -e 's/^pin delta shellcheck python/pin delta shellcheck python nosuchtool/' "$FX/ci/manifest" > "$work/m"
  cp "$work/m" "$FX/ci/manifest"; fx_commit "a tool the image lacks"
  host "$BASH" "$KITT_KIT/bin/container" versions --commit HEAD delta > "$work/o3" 2> /dev/null
  has "a tool the image lacks answers nothing, and the comparison with the pin is the caller's" "$work/o3" "nosuchtool "
  hasnt "and gets no invented version" "$work/o3" "nosuchtool v"
  rc=0; host "$BASH" "$KITT_KIT/bin/container" versions --commit HEAD > /dev/null 2>&1 || rc=$?
  rc_is "versions with no job is usage" 2 "$rc"
}

