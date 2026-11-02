# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-prune (kit/README.md §6.2; DESIGN.md §5.5): 31 days deleted, 29 kept, the
# tip's key kept at any age, a dateless local ref kept with its warning, a
# dry run deletes nothing.
prune_commit() { # prune_commit <days old> <label>: a commit with that committer date; prints its sha
  local when
  when="$(python3 -c "import time;print(int(time.time())-$1*86400-3600)")"
  GIT_AUTHOR_DATE="$when +0000" GIT_COMMITTER_DATE="$when +0000" git -C "$FX" commit -q --allow-empty -m "$2"
  git -C "$FX" rev-parse HEAD
}
prune_run() { # prune_run <class> <delete>
  PRUNE_RC=0
  ( cd "$FX" && env -i HOME="$work" TMPDIR="$work" PATH="$KITT_SYS_PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$BASH4" "$KITT_KIT/bin/prune" "$1" "$(git rev-parse origin/main)" "$2" ) > "$work/prune.out" 2>&1 || PRUNE_RC=$?
}
remote_has() { [ -n "$(git -C "$FX" ls-remote origin "$1")" ]; }
fam_prune() {
  need_bash4 prune || return 0
  local c31 c29 c100 k tip
  fx_new prune
  tip="$(git -C "$FX" rev-parse HEAD)"
  c31="$(prune_commit 31 old)"; c29="$(prune_commit 29 young)"; c100="$(prune_commit 100 ancient)"
  git -C "$FX" push -q --no-verify origin "$c31:refs/ci/green/alpha/$(printf '1%.0s' $(seq 1 64))" "$c29:refs/ci/green/alpha/$(printf '2%.0s' $(seq 1 64))"
  k="$(fx_key alpha "$tip")"
  git -C "$FX" push -q --no-verify origin "$c100:refs/ci/green/alpha/$k"
  git -C "$FX" push -q --no-verify origin "$c100:refs/ci/green/beta/$(printf '3%.0s' $(seq 1 64))"
  prune_run green false
  rc_is "a dry run" 0 "$PRUNE_RC"
  has "a dry run names what it would delete" "$work/prune.out" "would delete refs/ci/green/alpha/$(printf '1%.0s' $(seq 1 64))"
  has "and counts it as a dry run" "$work/prune.out" "2 green record(s) older than 30 days, DRY RUN"
  check "a dry run deletes nothing" remote_has "refs/ci/green/alpha/$(printf '1%.0s' $(seq 1 64))"
  prune_run green true
  rc_is "the real prune" 0 "$PRUNE_RC"
  check "31 days old is deleted" test -z "$(git -C "$FX" ls-remote origin "refs/ci/green/alpha/$(printf '1%.0s' $(seq 1 64))")"
  check "29 days old is kept" remote_has "refs/ci/green/alpha/$(printf '2%.0s' $(seq 1 64))"
  check "the main tip's key is kept at 100 days" remote_has "refs/ci/green/alpha/$k"
  check "an old record of a job the tip's keys do not name is deleted" test -z "$(git -C "$FX" ls-remote origin "refs/ci/green/beta/$(printf '3%.0s' $(seq 1 64))")"
  # local records: tagger date; a lightweight ref names no tagger date
  git -C "$FX" fetch -q origin
  when="$(python3 -c "import time;print(int(time.time())-40*86400)")"
  GIT_COMMITTER_DATE="$when +0000" git -C "$FX" tag -a -m old kitt-old "$c31"
  git -C "$FX" push -q --no-verify origin "refs/tags/kitt-old:refs/ci/local/alpha/$(printf '4%.0s' $(seq 1 64))" "$c31:refs/ci/local/alpha/$(printf '5%.0s' $(seq 1 64))"
  prune_run local true
  rc_is "the local prune" 0 "$PRUNE_RC"
  check "an old tagger date is deleted" test -z "$(git -C "$FX" ls-remote origin "refs/ci/local/alpha/$(printf '4%.0s' $(seq 1 64))")"
  check "a dateless local ref is kept" remote_has "refs/ci/local/alpha/$(printf '5%.0s' $(seq 1 64))"
  has "and named with its warning" "$work/prune.out" "has no tagger date, so its age is unknown and it was kept."
  prune_run bogus true; rc_is "an unknown class is usage" 2 "$PRUNE_RC"
  prune_run green maybe; rc_is "a delete word that is not true or false" 2 "$PRUNE_RC"
}
