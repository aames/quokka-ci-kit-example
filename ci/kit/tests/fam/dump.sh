# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-dump (kit/README.md §6.2): the dump is byte-identical through
# `bin/keys dump` and the library sourced; the awk program is the one place a
# directive's shape is tested, and every other reader takes the dump (kit/README.md §3.1).
fam_dump() {
  local m="$KITT_FIX/manifest" rc
  fx_new dumpfx
  KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/keys" dump HEAD > "$work/dump.cli"
  KIT_KEYS_REPO="$FX" "$BASH" -c ". '$KITT_KIT/lib/keys.sh'; kit_manifest_dump HEAD" > "$work/dump.lib"
  check "the dump through bin/keys equals the dump through the sourced library, byte for byte" cmp -s "$work/dump.cli" "$work/dump.lib"
  check "the dump is not empty and holds a line per directive" test "$(wc -l < "$work/dump.cli" | tr -d ' ')" -ge 60
  has "free text last and untouched (check-command)" "$work/dump.cli" "$(printf 'check-command\tmake check')"
  has "free text last and untouched (escaping-read, bars kept)" "$work/dump.cli" "$(printf 'escaping-read\talpha|src/a/a_test.go|deploy/tool.sh|reads the deploy helper it wraps')"
  # A shape the awk program refuses never reaches a dump, whichever reader asks.
  sed 's/^refuse-drafts yes/refuse-drafts maybe/' "$m" > "$work/badshape"
  rc=0; "$BASH" "$KITT_KIT/bin/check-manifest" --file "$work/badshape" --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "a bad shape is refused by the library's parser (the lint)" 2 "$rc"
  has "the refusal names the line and the rule" "$work/o" "line 22: refuse-drafts takes yes or no."
  rc=0; python3 "$KITT_KIT/bin/check-escaping-reads" --root "$FX" --manifest-file "$work/badshape" > "$work/o" 2>&1 || rc=$?
  rc_is "the escaping-read fence takes the dump, so the same bad shape stops it" 2 "$rc"
  if [ -n "$PYYAML" ]; then
    rc=0; "$PYYAML" "$KITT_KIT/bin/check-workflow" --fixture "$KITT_FIX/workflows" --manifest-file "$work/badshape" > "$work/o" 2>&1 || rc=$?
    rc_is "the workflow fence takes the dump, so the same bad shape stops it" 2 "$rc"
  fi
  git -C "$FX" show HEAD:ci/manifest | sed 's/^refuse-drafts yes/refuse-drafts maybe/' > "$work/m2"
  cp "$work/m2" "$FX/ci/manifest" && fx_commit "bad shape"
  rc=0; KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/keys" dump HEAD > "$work/o" 2> "$work/e" || rc=$?
  rc_is "keys dump of a commit whose manifest has a bad shape" 2 "$rc"
  check "and prints no dump line" test ! -s "$work/o"
  rc=0; KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/keys" HEAD alpha > "$work/o" 2> "$work/e" || rc=$?
  rc_is "a key that cannot be computed does not exist" 2 "$rc"
}
