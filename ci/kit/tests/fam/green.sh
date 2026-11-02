# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-green (kit/README.md §6.2; pattern 5.4): the green arm's codes 0, 1 and 2; one page;
# `github-actions` only; `skipped` never accepted. The gh shim applies the
# jq expression's own conditions to a table of check runs, so a condition the
# library drops changes the count.
fam_green() {
  need_bash4 green || return 0
  local sha key rc
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
  unset GH_TABLE GH_LOG
}
