# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-sign-push (kit/README.md §6.2; pattern 6.3, 6.4): no passing entry
# refuses; the tag targets the tested commit; no refs/tags/ name is left; an
# existing ref is "already signed"; a second push of an existing ref is success.
fam_signpush() {
  local key st obj
  fx_new sp
  st="$(state_dir)"; key="$(fx_key alpha)"
  drv sign --commit HEAD alpha
  rc_is "sign with no passing entry" 2 "$DRV_RC"
  has "refuses and names the check command" "$work/drv.out" "There is no passing run of alpha for $(git -C "$FX" rev-parse HEAD | cut -c1-8), so nothing was signed. Run make check first."
  check "and writes no ref" test -z "$(git -C "$FX" for-each-ref refs/ci/)"
  drv run --commit HEAD alpha; rc_is "(a passing run first)" 0 "$DRV_RC"
  drv sign --commit HEAD alpha
  rc_is "sign after a passing run" 0 "$DRV_RC"
  obj="$(git -C "$FX" rev-parse "refs/ci/local/alpha/$key")"
  eq "the ref is a tag object" tag "$(git -C "$FX" cat-file -t "$obj")"
  eq "whose object is the commit tested" "$(git -C "$FX" rev-parse HEAD)" "$(git -C "$FX" cat-file tag "$obj" | awk '$1=="object"{print $2;exit}')"
  git -C "$FX" cat-file tag "$obj" > "$work/raw"
  sed -n '/^-----BEGIN SSH SIGNATURE-----$/,/^-----END SSH SIGNATURE-----$/p' "$work/raw" > "$work/sig"
  sed '/^-----BEGIN SSH SIGNATURE-----$/,$d' "$work/raw" > "$work/payload"
  signers_line a > "$work/allowed"
  rc=0; ssh-keygen -Y verify -f "$work/allowed" -I signer-a@fixture -n git -s "$work/sig" < "$work/payload" > /dev/null 2>&1 || rc=$?
  rc_is "its SSH signature verifies in namespace git" 0 "$rc"
  sed '1,/^$/d' "$work/payload" > "$work/msg"
  check "its message is the facts block" cmp -s "$work/msg" "$st/passed/alpha/$key"
  eq "no refs/tags/ name is left" "" "$(git -C "$FX" for-each-ref refs/tags)"
  eq "and no refs/ci/green/ ref is written" "" "$(git -C "$FX" for-each-ref refs/ci/green)"
  drv sign --commit HEAD alpha
  has "an existing ref is already signed" "$work/drv.out" "alpha: already signed at refs/ci/local/alpha/$key."
  git -C "$FX" config --unset user.signingkey
  drv run --commit HEAD delta; drv sign --commit HEAD delta
  rc_is "no user.signingkey" 2 "$DRV_RC"; has "says so" "$work/drv.out" "Git has no user.signingkey, so nothing was signed."
  git -C "$FX" config user.signingkey "$work/keys/a"
  # push: --no-verify, and an existing remote ref is success
  mkdir -p "$FX/hooks2"; printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$work" > "$FX/hooks2/pre-push"; chmod +x "$FX/hooks2/pre-push"
  git -C "$FX" config core.hooksPath hooks2
  drv push --commit HEAD alpha
  rc_is "push" 0 "$DRV_RC"; has "pushes the record" "$work/drv.out" "alpha: pushed refs/ci/local/alpha/$key to origin."
  check "the push went with --no-verify (the repository's hook did not run)" test ! -e "$work/hook-ran"
  check "the origin holds the record" test -n "$(git -C "$FX" ls-remote origin "refs/ci/local/alpha/$key")"
  drv push --commit HEAD alpha
  rc_is "a second push of an existing ref" 0 "$DRV_RC"
  git -C "$FX" push -q --no-verify origin --delete "refs/ci/local/alpha/$key"
  git -C "$FX" push -q --no-verify origin "$(git -C "$FX" rev-parse HEAD):refs/ci/local/alpha/$key"
  printf '#!/bin/sh\nwhile read old new ref; do [ "$old" = 0000000000000000000000000000000000000000 ] || { echo "ref exists" >&2; exit 1; }; done\n' > "$FXO/hooks/pre-receive"
  chmod +x "$FXO/hooks/pre-receive"
  drv push --commit HEAD alpha
  rc_is "an existing remote ref that rejects the push counts as success" 0 "$DRV_RC"; has "and says the record stands" "$work/drv.out" "origin already has refs/ci/local/alpha/$key, so the record stands."
  drv push --commit HEAD delta
  rc_is "push of a job never signed" 2 "$DRV_RC"; has "refuses" "$work/drv.out" "is not signed, so nothing was pushed."
  eq "nothing under refs/ci/green/ on the origin" "" "$(git -C "$FX" ls-remote origin 'refs/ci/green/*')"
}
