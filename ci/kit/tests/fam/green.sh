# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-green (kit/README.md §6.2; pattern 5.4): the green arm's codes 0, 1, 2 and 3; one page;
# `github-actions` only; `skipped` never accepted. The gh shim applies the
# jq expression's own conditions to a table of check runs, so a condition the
# library drops changes the count.
fam_green() {
  need_bash4 green || return 0
  local sha key rc obj bkey
  fx_new green
  sha="$(git -C "$FX" rev-parse HEAD)"
  key="$(fx_key alpha)"
  export GH_TABLE="$work/checks" GH_LOG="$work/gh.log"
  trust() { : > "$GH_LOG"; lib4 "kit_record_trusted fixture/repo $sha ${3:-alpha} ${2:-$key} ${4:-}; echo \$?" 2> /dev/null; }
  printf '%s|alpha|success|github-actions\n' "$sha" > "$GH_TABLE"
  eq "0: a successful github-actions check run of the job's name" 0 "$(trust)"
  eq "one page, filtered all, named by job: the one request" "1" "$(wc -l < "$GH_LOG" | tr -d ' ')"
  has "the request names the check and the page size" "$GH_LOG" "check_name=alpha&filter=all&per_page=100"
  printf '%s|alpha|failure|github-actions\n' "$sha" > "$GH_TABLE"
  eq "1: a failed run" 1 "$(trust)"
  printf '%s|alpha|success|some-other-app\n' "$sha" > "$GH_TABLE"
  eq "1: another app's success is not trusted" 1 "$(trust)"
  printf '%s|alpha|skipped|github-actions\n' "$sha" > "$GH_TABLE"
  eq "1: skipped is never accepted (pattern 5.4)" 1 "$(trust)"
  printf '%s|alpha||github-actions\n' "$sha" > "$GH_TABLE"
  eq "1: a run not finished (no conclusion) proved nothing" 1 "$(trust)"
  printf '%s|alpha|success|some-other-app\n%s|alpha|failure|github-actions\n' "$sha" "$sha" > "$GH_TABLE"
  eq "1: another app's success beside a failed github-actions run" 1 "$(trust)"
  printf '%s|alpha|failure|some-other-app\n%s|alpha|success|github-actions\n' "$sha" "$sha" > "$GH_TABLE"
  eq "0: a successful github-actions run beside another app's failure" 0 "$(trust)"
  printf '%s|alpha|success|github-actions\n' "$sha" > "$GH_TABLE"
  eq "2: a key that is not this commit's key for the job" 2 "$(trust x "$(printf 'a%.0s' $(seq 1 64))")"
  eq "2: a key not in the shape of one" 2 "$(trust x notakey)"
  eq "2: a job the commit's manifest does not key" 2 "$(trust x "$key" nojob)"
  printf '%s|gammarecord|success|github-actions\n' "$sha" > "$GH_TABLE"
  eq "0: a job whose check-name line names another check run" 0 "$(trust x "$(fx_key gamma)" gamma gammarecord)"
  eq "1: the same job asked under its own name finds no run" 1 "$(trust x "$(fx_key gamma)" gamma)"
  export GH_FAIL=1
  printf '%s|alpha|success|github-actions\n' "$sha" > "$GH_TABLE"
  eq "1: an unreachable API trusts no record" 1 "$(trust)"
  unset GH_FAIL
  eq "1: no repository to ask" 1 "$(lib4 "kit_record_trusted '' $sha alpha $key; echo \$?" 2> /dev/null)"
  # both shapes (DESIGN.md 5.4): a tag object is peeled, its facts agree, its platform is read
  printf '%s|alpha|success|github-actions\n' "$sha" > "$GH_TABLE"
  eq "a lightweight record reads no platform" "0 []" "$(lib4 "kit_record_trusted fixture/repo $sha alpha $key; echo \"\$? [\$KIT_RECORD_PLATFORM]\"" 2> /dev/null)"
  gfacts "$work/g" alpha; obj="$(grec alpha "$key" "$work/g")"
  eq "0: a tag-object record, peeled to its commit, with agreeing facts, and its platform" "0 [linux/amd64]" \
    "$(lib4 "kit_record_trusted fixture/repo $obj alpha $key; echo \"\$? [\$KIT_RECORD_PLATFORM]\"" 2> /dev/null)"
  eq "the same with the manifest loaded first" "0 [linux/amd64]" \
    "$(lib4 "kit_manifest_load HEAD; kit_record_trusted fixture/repo $obj alpha $key; echo \"\$? [\$KIT_RECORD_PLATFORM]\"" 2> /dev/null)"
  gfacts "$work/g" alpha "s/^key .*/key $(printf 'b%.0s' $(seq 1 64))/"; obj="$(grec alpha "$key" "$work/g")"
  eq "3: a tag object whose facts name another key, with the reason and no platform" "3 [] its facts' job, key or commit differ from its ref and its commit" \
    "$(lib4 "kit_record_trusted fixture/repo $obj alpha $key; echo \"\$? [\$KIT_RECORD_PLATFORM] \$KIT_RECORD_REASON\"" 2> /dev/null)"
  gfacts "$work/g" alpha "/^image /d"; obj="$(grec alpha "$key" "$work/g")"
  eq "3: a local job's tag object with no image id" "3 it records no image id of the job image" \
    "$(lib4 "kit_record_trusted fixture/repo $obj alpha $key; echo \"\$? \$KIT_RECORD_REASON\"" 2> /dev/null)"
  # the refusals no other case reached (ARCH-1 review section 5): a tag of a tag, no platform, two platforms
  gfacts "$work/g" alpha; obj="$(grec alpha "$key" "$work/g")"
  obj="$({ printf 'object %s\ntype tag\ntag ci/green/alpha/%s\ntagger github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com> 1762646400 +0000\n\n' "$obj" "$key"; cat "$work/g"; } | git -C "$FX" mktag)"
  eq "3: a tag of a tag is not a tag that points at a commit" "3 [] it is a tag that does not point at a commit" \
    "$(lib4 "kit_record_trusted fixture/repo $obj alpha $key; echo \"\$? [\$KIT_RECORD_PLATFORM] \$KIT_RECORD_REASON\"" 2> /dev/null)"
  gfacts "$work/g" alpha "/^platform /d"; obj="$(grec alpha "$key" "$work/g")"
  eq "3: a local job's tag object with no platform line" "3 it records no platform" \
    "$(lib4 "kit_record_trusted fixture/repo $obj alpha $key; echo \"\$? \$KIT_RECORD_REASON\"" 2> /dev/null)"
  gfacts "$work/g" alpha "/^platform /p"; obj="$(grec alpha "$key" "$work/g")"
  eq "3: a local job's tag object with two platform lines reads as no platform" "3 it records no platform" \
    "$(lib4 "kit_record_trusted fixture/repo $obj alpha $key; echo \"\$? \$KIT_RECORD_REASON\"" 2> /dev/null)"
  # a job whose verdict ran on the runner: its platform held to KIT_PLATFORM_SHAPE
  printf '%s|alpha|success|github-actions\n%s|beta|success|github-actions\n' "$sha" "$sha" > "$GH_TABLE"
  bkey="$(fx_key beta)"
  gfacts "$work/g" beta "s|^platform .*|platform msys_nt-10.0-19045/amd64|; s|^image .*|image none|"; obj="$(grec beta "$bkey" "$work/g")"
  eq "0: a ci-only job's tag object from a Windows runner (Git Bash's uname), trusted with its platform" "0 [msys_nt-10.0-19045/amd64]" \
    "$(lib4 "kit_record_trusted fixture/repo $obj beta $bkey; echo \"\$? [\$KIT_RECORD_PLATFORM]\"" 2> /dev/null)"
  gfacts "$work/g" beta "s|^platform .*|platform Darwin arm64|; s|^image .*|image none|"; obj="$(grec beta "$bkey" "$work/g")"
  eq "3: a ci-only job's platform out of shape, named as such" "3 [] it records the platform Darwin arm64, which is not of the shape <os>/<arch>" \
    "$(lib4 "kit_record_trusted fixture/repo $obj beta $bkey; echo \"\$? [\$KIT_RECORD_PLATFORM] \$KIT_RECORD_REASON\"" 2> /dev/null)"
  gfacts "$work/g" beta "/^platform /d; s|^image .*|image none|"; obj="$(grec beta "$bkey" "$work/g")"
  eq "3: a ci-only job's tag object with no platform line" "3 it records no platform" \
    "$(lib4 "kit_record_trusted fixture/repo $obj beta $bkey; echo \"\$? \$KIT_RECORD_REASON\"" 2> /dev/null)"
  gfacts "$work/g" beta "/^platform /p; s|^image .*|image none|"; obj="$(grec beta "$bkey" "$work/g")"
  eq "3: a ci-only job's tag object with two platform lines reads as no platform" "3 it records no platform" \
    "$(lib4 "kit_record_trusted fixture/repo $obj beta $bkey; echo \"\$? \$KIT_RECORD_REASON\"" 2> /dev/null)"
  gfacts "$work/g" alpha; obj="$(grec alpha "$key" "$work/g")"
  printf '%s|alpha|failure|github-actions\n' "$sha" > "$GH_TABLE"
  eq "1: a tag object with agreeing facts still needs the check run, and reads no platform" "1 []" \
    "$(lib4 "kit_record_trusted fixture/repo $obj alpha $key; echo \"\$? [\$KIT_RECORD_PLATFORM]\"" 2> /dev/null)"
  unset GH_TABLE GH_LOG
}
