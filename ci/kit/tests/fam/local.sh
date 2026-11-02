# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-local (kit/README.md §6.2; pattern 6.7): the six conditions and every predicate,
# byte for byte; the grafted signature block and the `-n file` signature (the
# DESIGN.md §6.7 condition 1 cases); a key on two lines (DESIGN.md §6.6); the signers and the allow-list from
# main, never the branch.

# verdict <obj> [<job> [<key> [<ref>]]]: "<rc> <reason or principal>"
verdict() {
  local job="${2:-alpha}" key="${3:-$(fx_key alpha)}"
  lib4 "kit_manifest_load HEAD; kit_local_record_trusted $1 $job $key ${4:-refs/ci/local/$job/$key} && echo \"0 \$KIT_LOCAL_PRINCIPAL\" || echo \"\$? \$KIT_LOCAL_REASON\"" 2> /dev/null
}

fam_local() {
  need_bash4 local || return 0
  local key obj out sig payload
  fx_new local
  key="$(fx_key alpha)"
  lfacts "$work/f"
  obj="$(lrec alpha "$key" "$work/f" a)"
  eq "a record signed by a key main lists, with sound facts, is trusted and names its signer" "0 signer-a@fixture" "$(verdict "$obj")"
  # condition 1: the signature
  git -C "$FX" update-ref refs/ci/local/alpha/zz "$(git -C "$FX" rev-parse HEAD)"
  eq "1: a ref naming a commit, not a tag object" "4 is not a signed tag object" "$(verdict "$(git -C "$FX" rev-parse HEAD)")"
  git -C "$FX" update-ref -d refs/ci/local/alpha/zz
  git -C "$FX" tag -a -F "$work/f" kitt-plain HEAD && out="$(git -C "$FX" rev-parse refs/tags/kitt-plain)" && git -C "$FX" update-ref -d refs/tags/kitt-plain
  eq "1: an annotated tag with no signature" "4 is a tag with no SSH signature" "$(verdict "$out")"
  obj="$(lrec alpha "$key" "$work/f" b)"
  eq "1: signed by a key that is not in main's allowed signers" "4 is signed by a key that is not in main's allowed signers" "$(verdict "$obj")"
  # the DESIGN.md §6.7 condition 1 cases: a signature block of a valid record grafted on another payload
  obj="$(lrec alpha "$key" "$work/f" a)"
  git -C "$FX" cat-file tag "$obj" > "$work/raw"
  sed -n '/^-----BEGIN SSH SIGNATURE-----$/,/^-----END SSH SIGNATURE-----$/p' "$work/raw" > "$work/sig"
  sed '/^-----BEGIN SSH SIGNATURE-----$/,$d' "$work/raw" > "$work/payload"
  lfacts "$work/f2" 's/^duration_s 4/duration_s 5/'
  { sed '/^$/q' "$work/payload"; cat "$work/f2"; cat "$work/sig"; } > "$work/graft"
  out="$(git -C "$FX" hash-object -t tag -w "$work/graft")"
  git -C "$FX" update-ref "refs/ci/local/alpha/$key" "$out"
  eq "a valid signature block grafted on another payload does not verify" "4 carries a signature that does not verify against main's allowed signers" "$(verdict "$out")"
  { sed '/^$/q' "$work/payload"; cat "$work/f2"; } > "$work/p2"
  ssh-keygen -q -Y sign -f "$work/keys/a" -n file "$work/p2" > /dev/null 2>&1
  { cat "$work/p2"; cat "$work/p2.sig"; } > "$work/ns"
  out="$(git -C "$FX" hash-object -t tag -w "$work/ns")"
  git -C "$FX" update-ref "refs/ci/local/alpha/$key" "$out"
  eq "a signature made in namespace file instead of git does not verify" "4 carries a signature that does not verify against main's allowed signers" "$(verdict "$out")"
  obj="$(lrec alpha "$key" "$work/f" a)"
  # condition 2: the key and the facts' own names
  eq "ref: a ref that is not refs/ci/local/<job>/<key>" "4 is not at refs/ci/local/alpha/<its key>" "$(verdict "$obj" alpha "$key" refs/ci/local/alpha/other)"
  lfacts "$work/f" 's/^job alpha/job delta/'
  obj="$(lrec alpha "$key" "$work/f" a)"
  eq "2: facts naming another job than the ref's" "4 carries facts whose job, key or commit differ from its ref and its commit" "$(verdict "$obj")"
  lfacts "$work/f" 's/^commit [0-9a-f]*/commit 0000000000000000000000000000000000000000/'
  obj="$(lrec alpha "$key" "$work/f" a)"
  eq "2: facts naming another commit than the tag's" "4 carries facts whose job, key or commit differ from its ref and its commit" "$(verdict "$obj")"
  lfacts "$work/f"
  obj="$(lrec alpha "$key" "$work/f" a "$(printf 'e%.0s' $(seq 1 64))")"
  eq "2: a ref key its commit does not recompute to" "4 names a key that its commit $(git -C "$FX" rev-parse HEAD | cut -c1-8) does not recompute to" "$(verdict "$obj" alpha "$(printf 'e%.0s' $(seq 1 64))")"
  # the format, platform, image
  for c in 's/^kitfix-local-ci v1/kitfix-local-ci v2/|is not in the kitfix-local-ci v1 format' 's/^platform .*/platform linux\/riscv64/|records the platform linux/riscv64, which is neither linux/amd64 nor linux/arm64' 's/^platform .*/platform darwin\/arm64/|was made outside the job image' '/^platform /d|was made outside the job image' '/^image /d|records no image id of the job image'; do
    lfacts "$work/f" "${c%%|*}"
    obj="$(lrec alpha "$key" "$work/f" a)"
    eq "format and platform: ${c#*|}" "4 ${c#*|}" "$(verdict "$obj")"
  done
  # condition 3: the pins
  lfacts "$work/f" 's/^go go1.27.3/go go1.99.0/'; obj="$(lrec alpha "$key" "$work/f" a)"
  eq "3: a recorded go version off the commit's pin" "4 records go go1.99.0 where its commit pins go1.27.3" "$(verdict "$obj")"
  lfacts "$work/f" '/^node /d'; obj="$(lrec alpha "$key" "$work/f" a)"
  eq "3: a pinned tool with no line in the facts" "4 records no single node version" "$(verdict "$obj")"
  lfacts "$work/f" 's/^node v24.1.0/node 24.1.0/'; obj="$(lrec alpha "$key" "$work/f" a)"
  eq "3: one leading v is dropped from each side" "0 signer-a@fixture" "$(verdict "$obj")"
  # condition 4: the counts
  lfacts "$work/f" 's/^unit_tests 3/unit_tests 0/'; obj="$(lrec alpha "$key" "$work/f" a)"
  eq "4: a zero count" "4 records unit_tests 0, which is not above zero" "$(verdict "$obj")"
  lfacts "$work/f" '/^integration_tests/d'; obj="$(lrec alpha "$key" "$work/f" a)"
  eq "4: a missing count" "4 records no single integration_tests count" "$(verdict "$obj")"
  lfacts "$work/f" 's/^unit_tests 3/unit_tests 1234567890/'; obj="$(lrec alpha "$key" "$work/f" a)"
  eq "4: ten digits" "4 records unit_tests 1234567890, which is not above zero" "$(verdict "$obj")"
  # condition 5: the skips, from main's manifest
  lfacts "$work/f"; echo 'not_run some/harness:leg' >> "$work/f"; obj="$(lrec alpha "$key" "$work/f" a)"
  eq "5: a skipped leg main's manifest does not name" "4 skips some/harness:leg, which main's ci/manifest does not name" "$(verdict "$obj")"
  lfacts "$work/f"; echo 'not_run tests/run:docker-leg' >> "$work/f"; obj="$(lrec alpha "$key" "$work/f" a)"
  eq "5: a skipped leg main's manifest names" "0 signer-a@fixture" "$(verdict "$obj")"
  # condition 6: force and weekly ignore every local record
  lfacts "$work/f"; obj="$(lrec alpha "$key" "$work/f" a)"
  eq "6: ignored on a force dispatch" "4 is ignored on a force dispatch" "$(CI_PLAN_FORCE=true verdict "$obj")"
  eq "6: ignored on a weekly dispatch" "4 is ignored on a weekly dispatch" "$(CI_PLAN_TASK=weekly verdict "$obj")"
  # the job's class
  eq "class: a CI-only job takes no local record" "4 is for a job that records only in CI" "$(verdict "$obj" beta "$(fx_key beta)")"
  eq "class: the always-on job takes no local record" "4 names gate, which no local record may vouch for" "$(verdict "$obj" gate "$(fx_key gate)")"
  # DESIGN.md §6.6: one key on two lines of main's signers file
  git -C "$FX" checkout -q -b dup && { cat "$FX/ci/allowed-signers"; printf 'second-name@fixture %s\n' "$(cut -d' ' -f2,3 "$FX/ci/allowed-signers")"; } > "$work/s" && cp "$work/s" "$FX/ci/allowed-signers"
  fx_commit dup && git -C "$FX" push -q --no-verify origin dup:refs/heads/main -f && git -C "$FX" fetch -q origin
  eq "a key named on two lines of main's signers file vouches for nothing" "4 cannot be checked, because main's allowed signers names one key on more than one line" "$(verdict "$obj")"
  # the signers file and the allow-list come from main, never the branch
  fx_new localb
  key="$(fx_key alpha)"
  { cat "$FX/ci/allowed-signers"; signers_line b; } > "$work/s" && cp "$work/s" "$FX/ci/allowed-signers"
  fx_commit "branch adds its own signer"
  key="$(fx_key alpha)"; lfacts "$work/f"
  obj="$(lrec alpha "$key" "$work/f" b)"
  eq "main's signers, never the checkout's: a branch that added its own key does not vouch for itself" "4 is signed by a key that is not in main's allowed signers" "$(verdict "$obj" alpha "$key")"
  printf 'not-run-allowed some/harness:leg only the branch allows it\n' >> "$FX/ci/manifest"; fx_commit "branch allows a leg"
  key="$(fx_key alpha)"; lfacts "$work/f"; echo 'not_run some/harness:leg' >> "$work/f"
  obj="$(lrec alpha "$key" "$work/f" a)"
  eq "main's not-run-allowed, never the branch's" "4 skips some/harness:leg, which main's ci/manifest does not name" "$(verdict "$obj" alpha "$key")"
}
