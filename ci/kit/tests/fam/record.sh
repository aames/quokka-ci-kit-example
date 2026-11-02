# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-record (kit/README.md §6.2; pattern 5.2): 201, 422 "already exists", other 422, 403
# once then a warning, 000; shapes refused with exit 2 before any request. The
# curl shim answers from CURL_CODES, the sleep shim logs its arguments.
rec_run() { # rec_run <codes> <bodies> <args...>
  local codes="$1" bodies="$2"; shift 2
  : > "$work/curl.log"; : > "$work/sleep.log"
  REC_RC=0
  ( cd "$FX" && env -i HOME="$work" PATH="$work/shims:$KITT_SYS_PATH" SYS_PATH="$KITT_SYS_PATH" CURL_CODES="$codes" CURL_BODIES="$bodies" CURL_LOG="$work/curl.log" SLEEP_LOG="$work/sleep.log" \
      GITHUB_TOKEN=t GITHUB_REPOSITORY=fixture/repo "$BASH4" "$KITT_KIT/bin/record" "$@" ) > "$work/rec.out" 2>&1 || REC_RC=$?
}
fam_record() {
  need_bash4 record || return 0
  local sha key
  fx_new rec
  sha="$(git -C "$FX" rev-parse HEAD)"; key="$(fx_key alpha)"
  rec_run 201 '{}' alpha "$key" "$sha"
  rc_is "201 records" 0 "$REC_RC"; has "201 says the record" "$work/rec.out" "recorded refs/ci/green/alpha/$key -> $sha"
  rec_run 422 '{"message":"Reference already exists"}' alpha "$key" "$sha"
  rc_is "422 Reference already exists is success" 0 "$REC_RC"; has "and says the earlier record stands" "$work/rec.out" "this tree was proven green before, and that record stands."
  rec_run 422 '{"message":"Validation Failed: sha is invalid"}' alpha "$key" "$sha"
  rc_is "any other 422 fails the step" 1 "$REC_RC"; has "and names the refusal" "$work/rec.out" "::error::GitHub refused refs/ci/green/alpha/$key (422)"
  rec_run '403 201' '{}' alpha "$key" "$sha"
  rc_is "403 then 201: retried once" 0 "$REC_RC"; eq "after one sleep of five seconds" "5" "$(cat "$work/sleep.log" | tr -d '\n')"; eq "two requests were made" 2 "$(wc -l < "$work/curl.log" | tr -d ' ')"
  rec_run '403 403' '{"message":"denied"}' alpha "$key" "$sha"
  rc_is "403 twice warns and exits 0" 0 "$REC_RC"; has "the warning names the record" "$work/rec.out" "::warning::refs/ci/green/alpha/$key was not written: GitHub refused it twice with 403"
  eq "403 twice: still only two requests" 2 "$(wc -l < "$work/curl.log" | tr -d ' ')"
  rec_run 000 '' alpha "$key" "$sha"
  rc_is "000 (the API cannot be reached) fails the step" 1 "$REC_RC"; has "and says the status" "$work/rec.out" "answered 000"
  rec_run 500 '{"message":"boom"}' alpha "$key" "$sha"
  rc_is "500 fails the step" 1 "$REC_RC"
  rec_run 201 '{}' alpha "$key"
  rc_is "shape: a wrong argument count" 2 "$REC_RC"; eq "and no request was made" 0 "$(wc -l < "$work/curl.log" | tr -d ' ')"
  rec_run 201 '{}' nojob "$key" "$sha"
  rc_is "shape: a job the recorded commit's manifest does not declare" 2 "$REC_RC"; eq "no request" 0 "$(wc -l < "$work/curl.log" | tr -d ' ')"
  has "and the sentence" "$work/rec.out" "::error::no green record exists for job nojob"
  rec_run 201 '{}' alpha ABC "$sha"
  rc_is "shape: a key that is not 64 lower-case hex" 2 "$REC_RC"; eq "no request" 0 "$(wc -l < "$work/curl.log" | tr -d ' ')"
  rec_run 201 '{}' alpha "$key" abc123
  rc_is "shape: a sha that is not 40 hex" 2 "$REC_RC"; eq "no request" 0 "$(wc -l < "$work/curl.log" | tr -d ' ')"
  rc=0; ( cd "$FX" && env -i PATH="$KITT_SYS_PATH" "$BASH4" "$KITT_KIT/bin/record" alpha "$key" "$sha" ) > "$work/rec.out" 2>&1 || rc=$?
  check "without GITHUB_TOKEN the step refuses" test "$rc" -ne 0
}
