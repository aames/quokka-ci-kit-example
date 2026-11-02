# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-host (kit/README.md §6.2, §2.2): the kit's fence on its own host files:
# `check-host kit/` clean; a `sed` planted in pre-push, a bash 4 construct
# planted in the driver, each caught; text that only mentions them is not.
chost() { CH_RC=0; python3 "$KITT_KIT/bin/check-host" "$1" > "$work/o" 2>&1 || CH_RC=$?; }
fam_host() {
  local d="$work/hostcopy" f
  chost "$KITT_KIT"
  rc_is "check-host on the kit tree under test" 0 "$CH_RC"
  rm -rf "$d"; mkdir -p "$d"
  for f in bin lib hooks; do cp -R "$KITT_KIT/$f" "$d/$f"; done
  printf 'sed s/a/b/ /dev/null\n' >> "$d/bin/pre-push"
  chost "$d"
  rc_is "a sed planted in bin/pre-push" 1 "$CH_RC"; has "is named" "$work/o" "sed"
  cp "$KITT_KIT/bin/pre-push" "$d/bin/pre-push"
  printf 'mapfile -t x < /dev/null\n' >> "$d/bin/local-ci"
  chost "$d"
  rc_is "a bash 4 construct (mapfile) planted in bin/local-ci" 1 "$CH_RC"; has "is named" "$work/o" "mapfile"
  cp "$KITT_KIT/bin/local-ci" "$d/bin/local-ci"
  printf '# sed and awk and jq are only mentioned here\necho "sed in double quotes"\necho '"'"'sed in single quotes'"'"'\n"$BASH" -c true\n' >> "$d/bin/pre-push"
  chost "$d"
  rc_is "commands only named in a comment or a quoted string, and \"\$BASH\", are not commands" 0 "$CH_RC"
  cp "$KITT_KIT/bin/pre-push" "$d/bin/pre-push"
  printf 'awk 1 /dev/null\n' >> "$d/bin/container"
  chost "$d"
  rc_is "awk outside lib/keys.sh is outside the allow-list" 1 "$CH_RC"
  cp "$KITT_KIT/bin/container" "$d/bin/container"
  printf 'x=${y,,}\n' >> "$d/lib/keys.sh"
  chost "$d"
  rc_is "a case-changing expansion planted in the library" 1 "$CH_RC"
  mkdir -p "$work/nohost"; chost "$work/nohost"
  rc_is "a directory holding none of the host files is refused" 2 "$CH_RC"
}
