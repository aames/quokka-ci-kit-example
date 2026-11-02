# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-shape (kit/README.md §6.2; DESIGN.md §5.1a): the driver's shell holds no function of the
# commit's library after `run`, and a probe never runs the commit's code. The
# commit's library and its pin source carry a line that records the pid of
# whatever shell executes it; the driver's own pid is the lock's.
fam_shape() {
  local st line pid drvpid
  fx_new shape
  printf 'printf "%%s\\n" "$$" >> "${KITT_MARK:-/dev/null}"\n' >> "$FX/ci/kit/lib/keys.sh"
  printf 'touch "${KITT_MARK2:-/dev/null}"\n' >> "$FX/tools.sh"
  fx_commit "a library and a pin source that record who runs them"
  export KITT_MARK="$work/mark" KITT_MARK2="$work/mark2"; : > "$KITT_MARK"; rm -f "$KITT_MARK2"
  drv run --commit HEAD alpha
  rc_is "a run with a commit whose library and pin source are instrumented" 0 "$DRV_RC"
  check "the commit's library ran (in children)" test -s "$KITT_MARK"
  drvpid="$(cat "$SHIM_STATE/lockpid-alpha" 2> /dev/null)"
  check "the lock names the driver's pid" test -n "$drvpid"
  if grep -qx "$drvpid" "$KITT_MARK"; then bad "the commit's library ran in the driver's own shell (pid $drvpid)"; else ok "the commit's library never ran in the driver's shell"; fi
  check "a probe's pin source (tools.sh) is read as data and never executed" test ! -e "$KITT_MARK2"
  unset KITT_MARK KITT_MARK2
}
