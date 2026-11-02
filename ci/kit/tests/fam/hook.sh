# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-hook (kit/README.md §6.2; pattern 6.8): the hook through a real
# `git push` on the host farm and the shims.
hookpush() { # hookpush <git push args...>: HOOK_RC, $work/push.out
  : > "$DOCKER_LOG"; HOOK_RC=0
  host git -c core.hooksPath=.githooks push "$@" > "$work/push.out" 2>&1 || HOOK_RC=$?
}
fam_hook() {
  local sha k st
  fx_new hook
  st="$(state_dir)"
  check "the shim is byte-equal to hooks/pre-push.shim" cmp -s "$FX/.githooks/pre-push" "$KITT_KIT/hooks/pre-push.shim"
  eq "and is three lines" 3 "$(wc -l < "$KITT_KIT/hooks/pre-push.shim" | tr -d ' ')"
  git -C "$FX" checkout -q -b feat; printf 'a\n' > "$FX/src/marker.txt"; fx_commit change; sha="$(git -C "$FX" rev-parse HEAD)"
  export ADAPTER_alpha=fail
  hookpush origin feat
  check "a failing run refuses the push" test "$HOOK_RC" -ne 0
  has "naming the failed job and its log" "$work/push.out" "alpha failed on ${sha:0:8}, so nothing was pushed. The log is"
  eq "nothing reached the origin" "" "$(git -C "$FX" ls-remote origin refs/heads/feat 'refs/ci/*')"
  unset ADAPTER_alpha
  hookpush origin feat
  rc_is "a passing run pushes" 0 "$HOOK_RC"
  for j in alpha delta kitself; do
    k="$(fx_key "$j")"
    check "the origin holds $j's local record" test -n "$(git -C "$FX" ls-remote origin "refs/ci/local/$j/$k")"
  done
  check "and the branch" test -n "$(git -C "$FX" ls-remote origin refs/heads/feat)"
  eq "a ci-only job is never keyed" "" "$(git -C "$FX" ls-remote origin 'refs/ci/local/beta/*')"
  hasnt "and never run" "$DOCKER_LOG" "cikit-enter beta"
  # every key recorded runs nothing
  git -C "$FX" checkout -q -b feat2; printf 'more\n' >> "$FX/README.md"; fx_commit readme
  hookpush origin feat2
  rc_is "a push whose keys are all recorded" 0 "$HOOK_RC"; hasnt "runs nothing" "$DOCKER_LOG" cikit-enter
  # a cached pass signs without running
  printf 'b\n' > "$FX/src/marker.txt"; fx_commit change2
  drv run --commit HEAD alpha delta kitself; rc_is "(the jobs run once by hand)" 0 "$DRV_RC"
  hookpush origin feat2
  rc_is "a cached pass is signed and pushed" 0 "$HOOK_RC"; hasnt "without running again" "$DOCKER_LOG" cikit-enter
  check "the record is on the origin" test -n "$(git -C "$FX" ls-remote origin "refs/ci/local/alpha/$(fx_key alpha)")"
  # the pushes the hook leaves alone
  hookpush origin --delete feat; rc_is "a deletion" 0 "$HOOK_RC"; check "touches nothing" test ! -s "$DOCKER_LOG"
  git -C "$FX" tag kitt-v1; hookpush origin kitt-v1; rc_is "a tag push" 0 "$HOOK_RC"; check "touches nothing" test ! -s "$DOCKER_LOG"
  hookpush origin HEAD:refs/ci/other; rc_is "a refs/ci/* push" 0 "$HOOK_RC"; check "touches nothing" test ! -s "$DOCKER_LOG"
  # the environment
  printf 'c\n' > "$FX/src/marker.txt"; fx_commit change3
  export SHIM_DOCKER_INFO_RC=1
  hookpush origin feat2
  check "Docker down refuses the push" test "$HOOK_RC" -ne 0
  has "and names --no-verify" "$work/push.out" "--no-verify"
  unset SHIM_DOCKER_INFO_RC
  # a pushed commit with no ci/kit/lib/keys.sh predates the kit
  git -C "$FX" checkout -q --orphan oldline && git -C "$FX" rm -rfq . && printf 'x\n' > "$FX/x" && git -C "$FX" add x && git -C "$FX" commit -qm old
  git -C "$FX" checkout -q -f feat2 2> /dev/null || true
  hookpush origin oldline
  rc_is "a pushed commit that predates the kit passes" 0 "$HOOK_RC"
  has "with one sentence" "$work/push.out" "predates the kit, so no local record was made and the pull request will run its jobs."
}
