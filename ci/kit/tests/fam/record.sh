# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-record (kit/README.md §6.2; pattern 5.2): the tag object first, its facts
# block, then the ref at the tag object; 201, 422 "already exists", other 422,
# 403 once then a warning, 000; a `local` job's platform from the launcher's
# ran file, refused with exit 2 when it is absent or malformed; shapes refused
# with exit 2 before any request. The curl shim answers from CURL_CODES and
# logs each request's path and body, the sleep shim logs its arguments.
REC_TAG="$(printf 'a1%.0s' $(seq 1 20))"
rec_run() { # rec_run <codes> <bodies> <args...>
  local codes="$1" bodies="$2"; shift 2
  : > "$work/curl.log"; : > "$work/sleep.log"
  REC_RC=0
  ( cd "$FX" && env -i HOME="$work" PATH="${REC_PATH_PRE:+$REC_PATH_PRE:}$work/shims:$KITT_SYS_PATH" SYS_PATH="$KITT_SYS_PATH" CURL_CODES="$codes" CURL_BODIES="$bodies" CURL_LOG="$work/curl.log" SLEEP_LOG="$work/sleep.log" \
      CURL_TAG_SHA="${CURL_TAG_SHA-$REC_TAG}" GITHUB_RUN_ID=4242 GITHUB_WORKFLOW_REF=fixture/repo/.github/workflows/ci.yml@refs/heads/main \
      GITHUB_TOKEN=t GITHUB_REPOSITORY=fixture/repo "$BASH4" "$KITT_KIT/bin/record" "$@" ) > "$work/rec.out" 2>&1 || REC_RC=$?
}
posts() { wc -l < "$work/curl.log" | tr -d ' '; }
# rec_message <n>: the message of the n-th request's JSON body.
rec_message() { sed -n "${1}p" "$work/curl.log" | cut -d' ' -f3- | python3 -I -c 'import json, sys; print(json.loads(sys.stdin.read())["message"], end="")'; }
fam_record() {
  need_bash4 record || return 0
  local sha key ran img host
  fx_new rec
  sha="$(git -C "$FX" rev-parse HEAD)"; key="$(fx_key alpha)"
  img="sha256:$(printf 'ab%.0s' $(seq 1 32))"
  ran="$(state_dir)/ran/alpha/$key"
  mkdir -p "${ran%/*}"; printf 'platform linux/arm64\nimage %s\n' "$img" > "$ran"
  host="$("$BASH" -c ". '$KITT_KIT/lib/keys.sh'; kit_platform_of \$(uname -s) \$(uname -m)")"
  rec_run '201 201' 'TAG|{}' alpha "$key" "$sha"
  rc_is "201 records" 0 "$REC_RC"; has "201 says the record" "$work/rec.out" "recorded refs/ci/green/alpha/$key -> $sha (tag object ${REC_TAG:0:12}, linux/arm64)"
  eq "two requests: the tag object, then the ref" "2" "$(posts)"
  case "$(sed -n 1p "$work/curl.log")" in "post fixture/repo/git/tags "*'"tag": "ci/green/alpha/'"$key"'"'*'"object": "'"$sha"'", "type": "commit"}') ok "the first is POST git/tags: tag ci/green/<job>/<key>, object the commit, type commit" ;; *) bad "the first request: $(sed -n 1p "$work/curl.log")" ;; esac
  eq "the second is POST git/refs: the ref at the TAG OBJECT's sha" "post fixture/repo/git/refs {\"ref\":\"refs/ci/green/alpha/$key\",\"sha\":\"$REC_TAG\"}" "$(sed -n 2p "$work/curl.log")"
  eq "the tag's message is the facts block, the platform and image the ran file's" "kitfix-green v1
job alpha
key $key
commit $sha
platform linux/arm64
host $host
image $img
run 4242
workflow_ref fixture/repo/.github/workflows/ci.yml@refs/heads/main
." "$(rec_message 1; echo .)"
  rec_run '201 201' 'TAG|{}' beta "$(fx_key beta)" "$sha"
  rc_is "a ci-only job needs no ran file" 0 "$REC_RC"
  case "$(rec_message 1)" in *"platform $host
host $host
image none
"*) ok "its platform is this runner's and its image none" ;; *) bad "beta's facts: $(rec_message 1)" ;; esac
  rec_run '201 422' 'TAG|{"message":"Reference already exists"}' alpha "$key" "$sha"
  rc_is "422 Reference already exists is success" 0 "$REC_RC"; has "and says the earlier record stands" "$work/rec.out" "this tree was proven green before, and that record stands."
  rec_run '201 422' 'TAG|{"message":"Validation Failed: sha is invalid"}' alpha "$key" "$sha"
  rc_is "any other 422 fails the step" 1 "$REC_RC"; has "and names the refusal" "$work/rec.out" "::error::GitHub refused refs/ci/green/alpha/$key (422)"
  rec_run '422' '{"message":"Validation Failed"}' alpha "$key" "$sha"
  rc_is "a refused tag object fails the step" 1 "$REC_RC"; eq "and no ref is asked for" 1 "$(posts)"
  rec_run '403 201 201' '{}|TAG|{}' alpha "$key" "$sha"
  rc_is "403 then 201: retried once" 0 "$REC_RC"; eq "after one sleep of five seconds" "5" "$(cat "$work/sleep.log" | tr -d '\n')"; eq "three requests were made, the tag twice" 3 "$(posts)"
  rec_run '403 403' '{"message":"denied"}' alpha "$key" "$sha"
  rc_is "403 twice warns and exits 0" 0 "$REC_RC"; has "the warning names the record" "$work/rec.out" "::warning::refs/ci/green/alpha/$key was not written: GitHub refused it twice with 403"
  eq "403 twice: still only two requests" 2 "$(posts)"
  rec_run '201 403 403' 'TAG|{"message":"denied"}' alpha "$key" "$sha"
  rc_is "403 twice on the ref warns and exits 0 too" 0 "$REC_RC"; eq "three requests" 3 "$(posts)"
  rec_run 000 '' alpha "$key" "$sha"
  rc_is "000 (the API cannot be reached) fails the step" 1 "$REC_RC"; has "and says the status" "$work/rec.out" "answered 000"
  rec_run 500 '{"message":"boom"}' alpha "$key" "$sha"
  rc_is "500 fails the step" 1 "$REC_RC"
  CURL_TAG_SHA="" rec_run '201 201' 'TAG|{}' alpha "$key" "$sha"
  rc_is "an answer naming no tag object fails the step" 1 "$REC_RC"; eq "and no ref is asked for" 1 "$(posts)"
  # the ran file: absent or malformed is refused before any request
  rm -f "$ran"
  rec_run '201 201' 'TAG|{}' alpha "$key" "$sha"
  rc_is "a local job with no ran file is refused" 2 "$REC_RC"; eq "no request" 0 "$(posts)"
  has "with the sentence" "$work/rec.out" "::error::alpha has no ran file at $ran, so no record was written"
  printf 'platform linux/arm64\n' > "$ran"
  rec_run '201 201' 'TAG|{}' alpha "$key" "$sha"
  rc_is "a ran file without its image line is refused" 2 "$REC_RC"; eq "no request" 0 "$(posts)"
  has "with the sentence" "$work/rec.out" "is not the two lines platform and image, so no record was written."
  printf 'platform Linux aarch64\nimage %s\n' "$img" > "$ran"
  rec_run '201 201' 'TAG|{}' alpha "$key" "$sha"
  rc_is "a ran file whose platform is not one word os/arch is refused" 2 "$REC_RC"; eq "no request" 0 "$(posts)"
  printf 'platform Linux/aarch64\nimage %s\n' "$img" > "$ran"
  rec_run '201 201' 'TAG|{}' alpha "$key" "$sha"
  rc_is "a ran file whose platform is one word out of shape is refused" 2 "$REC_RC"; eq "no request" 0 "$(posts)"
  has "with the sentence that names it" "$work/rec.out" "::error::the ran file $ran records the platform Linux/aarch64, which is not of the shape <os>/<arch>, so no record was written."
  # the ran file is held to the library's one shape, the plan's: a system word carrying - and . is written as given
  printf 'platform msys_nt-10.0-19045/amd64\nimage %s\n' "$img" > "$ran"
  rec_run '201 201' 'TAG|{}' alpha "$key" "$sha"
  rc_is "a ran file's platform in KIT_PLATFORM_SHAPE, its system word carrying - and ., is recorded" 0 "$REC_RC"
  has "and named in the line" "$work/rec.out" "recorded refs/ci/green/alpha/$key -> $sha (tag object ${REC_TAG:0:12}, msys_nt-10.0-19045/amd64)"
  # this runner's platform unread (an empty uname): refused before any request, never `platform /`
  mkdir -p "$work/nouname"; printf '#!/bin/sh\nexit 0\n' > "$work/nouname/uname"; chmod +x "$work/nouname/uname"
  REC_PATH_PRE="$work/nouname" rec_run '201 201' 'TAG|{}' beta "$(fx_key beta)" "$sha"
  rc_is "a runner whose uname says nothing is refused" 2 "$REC_RC"; eq "no request" 0 "$(posts)"
  has "with the sentence" "$work/rec.out" "::error::this runner did not say its platform, so no record was written."
  printf 'platform linux/arm64\nimage %s\n' "$img" > "$ran"
  rec_run 201 '{}' alpha "$key"
  rc_is "shape: a wrong argument count" 2 "$REC_RC"; eq "and no request was made" 0 "$(posts)"
  rec_run 201 '{}' nojob "$key" "$sha"
  rc_is "shape: a job the recorded commit's manifest does not declare" 2 "$REC_RC"; eq "no request" 0 "$(posts)"
  has "and the sentence" "$work/rec.out" "::error::no green record exists for job nojob"
  rec_run 201 '{}' alpha ABC "$sha"
  rc_is "shape: a key that is not 64 lower-case hex" 2 "$REC_RC"; eq "no request" 0 "$(posts)"
  rec_run 201 '{}' alpha "$key" abc123
  rc_is "shape: a sha that is not 40 hex" 2 "$REC_RC"; eq "no request" 0 "$(posts)"
  rc=0; ( cd "$FX" && env -i PATH="$KITT_SYS_PATH" "$BASH4" "$KITT_KIT/bin/record" alpha "$key" "$sha" ) > "$work/rec.out" 2>&1 || rc=$?
  check "without GITHUB_TOKEN the step refuses" test "$rc" -ne 0
}
