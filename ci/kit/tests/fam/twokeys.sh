# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-twokeys (kit/README.md §6.2, §3.2): the base tag is
# <project>-ci-base:<base key>, the job tag <project>-ci-job:<image key>; a
# change under image-path rebuilds the job image and not the base; a change
# under ci/kit/image rebuilds both; a found image under another key's label is
# refused; after a build the older tags beyond the three newest are removed.
builds() { grep -c "^buildx build .* -f $1 " "$DOCKER_LOG" || true; }
imgline() { host "$BASH" "$KITT_KIT/bin/container" image --commit HEAD "$@" 2> "$work/img.err"; }
fam_twokeys() {
  local l bk ik i
  fx_new tk
  : > "$DOCKER_LOG"
  l="$(imgline alpha)"
  bk="$(fx_key base)"; ik="$(fx_key image)"
  eq "image prints the job tag, which is the image key" "kitfix-ci-job:$ik" "${l%% *}"
  case "${l#* }" in sha256:????????????????????????????????????????????????????????????????) ok "and the image id" ;; *) bad "the image id: ${l#* }" ;; esac
  eq "one base build and one job build, from their own Dockerfiles" "1 1" "$(builds ci/kit/image/base.Dockerfile) $(builds ci/image/Dockerfile)"
  has "the base is tagged by its own key" "$DOCKER_LOG" "-t kitfix-ci-base:$bk"
  check "the base key is ci/kit/image alone: not the image key" test "$bk" != "$ik"
  : > "$DOCKER_LOG"; imgline alpha > /dev/null
  eq "a second image run finds both and builds nothing" "0 0" "$(builds ci/kit/image/base.Dockerfile) $(builds ci/image/Dockerfile)"
  # a change under image-path, outside ci/kit/image
  printf 'readonly SHELLCHECK_VERSION=v0.11.1\nreadonly PYTHON_VERSION=3.14\n' > "$FX/tools.sh"; fx_commit "tools.sh moves"
  : > "$DOCKER_LOG"; imgline alpha > /dev/null
  eq "a change under image-path rebuilds the job image and not the base" "0 1" "$(builds ci/kit/image/base.Dockerfile) $(builds ci/image/Dockerfile)"
  eq "and the base key did not move" "$bk" "$(fx_key base)"
  # a change under ci/kit/image
  printf '# a comment\n' >> "$FX/ci/kit/image/enter.sh"; fx_commit "the entry script moves"
  : > "$DOCKER_LOG"; imgline alpha > /dev/null
  eq "a change under ci/kit/image rebuilds the base and the job image" "1 1" "$(builds ci/kit/image/base.Dockerfile) $(builds ci/image/Dockerfile)"
  # the kit job runs in the base alone
  printf '# again\n' >> "$FX/ci/kit/image/enter.sh"; fx_commit "again"
  : > "$DOCKER_LOG"; l="$(imgline kitself)"
  eq "the kit job's image is the base, tagged by the base key" "kitfix-ci-base:$(fx_key base) " "${l%%sha256:*}"
  eq "and no job image is built for it" "1 0" "$(builds ci/kit/image/base.Dockerfile) $(builds ci/image/Dockerfile)"
  # a changed `user` builds new images and never finds the old ones (kit/README.md §3.2)
  ik="$(fx_key image)"; bk="$(fx_key base)"
  sed 's/^user 1001/user 1002/' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"; fx_commit "user 1002"
  check "user 1002 moves the base key" test "$(fx_key base)" != "$bk"
  check "user 1002 moves the image key" test "$(fx_key image)" != "$ik"
  : > "$DOCKER_LOG"; imgline alpha > /dev/null
  eq "so both images are built again" "1 1" "$(builds ci/kit/image/base.Dockerfile) $(builds ci/image/Dockerfile)"
  # an image under another key's label
  export SHIM_LABEL=0000
  rc=0; imgline alpha > /dev/null || rc=$?
  rc_is "a found image whose key label is not its key" 2 "$rc"; has "is refused" "$work/img.err" "carries the image key label '0000', so nothing ran."
  unset SHIM_LABEL
  # retention: the three newest of each repository
  for i in 1 2 3 4 5; do
    printf 'readonly SHELLCHECK_VERSION=v0.11.%s\nreadonly PYTHON_VERSION=3.14\n' "$((i + 1))" > "$FX/tools.sh"; fx_commit "tools $i"
    export SHIM_CREATED="2026-11-0${i}T00:00:00.5Z"
    : > "$DOCKER_LOG"; imgline alpha > /dev/null
  done
  unset SHIM_CREATED
  eq "after builds, the three newest job tags are kept" 3 "$(grep -c '^kitfix-ci-job:' "$SHIM_STATE/images")"
  has "and one line names what went" "$work/img.err" "Removed the older job images"
  check "the image just built is among those kept" grep -q "^kitfix-ci-job:$(fx_key image)|" "$SHIM_STATE/images"
}
