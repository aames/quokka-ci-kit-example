# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-update (kit/README.md §6.2, §5.3): the signed, unsigned and unlisted tags
# on a scratch bare repository; a replaced ci/kit hashes to the tag's kit tree.
fam_update() {
  local k="$work/kitrepo" bare="$work/kit.git" a="$work/adopter" ao="$work/adopter-origin.git" rc tree before obj side facts
  rm -rf "$k" "$bare" "$a" "$ao"
  git init -q --initial-branch=main "$k"; git -C "$k" config user.email f@i; git -C "$k" config user.name f
  mkdir -p "$k/kit/bin" "$k/kit/lib"
  printf '#!/bin/sh\necho x\n' > "$k/kit/bin/tool"; chmod +x "$k/kit/bin/tool"
  printf 'lib\n' > "$k/kit/lib/keys.sh"
  printf '# Changelog\n\n## v1.0.0\n\nmoves keys: yes\nthe adopter reruns the check.\n\n## v0.9.0\n\nold\n' > "$k/CHANGELOG.md"
  git -C "$k" add -A; git -C "$k" commit -qm one
  # A release is an annotated, signed tag whose message begins `quokka-ci-kit <tag>` (kit/README.md §5.3).
  ktag() { # ktag <key> <tag> [message...]: a signed release-shaped tag at main's tip
    local key="$1" t="$2"; shift 2
    git -C "$k" -c gpg.format=ssh -c user.signingkey="$work/keys/$key" tag -s -m "quokka-ci-kit $t" ${1:+-m "$1"} "$t"
  }
  ktag a v1.0.0
  git -C "$k" tag -a -m "quokka-ci-kit v1.0.1" v1.0.1
  git -C "$k" tag v1.0.2
  ktag b v1.0.3
  # release check (c): a release whose message carries a forged `Good` line.
  ktag a v1.0.5 'Good "git" signature for someone-else with ED25519 key SHA256:x'
  # release check (a): a record object made by local-ci sign's own command, placed at a release name.
  facts="$work/ku-facts"
  printf 'kitfix-local-ci v1\njob alpha\nkey %064d\ncommit %s\n' 0 "$(git -C "$k" rev-parse HEAD)" > "$facts"
  git -C "$k" -c gpg.format=ssh -c user.signingkey="$work/keys/a" tag -s --cleanup=verbatim -F "$facts" kitt-record HEAD
  obj="$(git -C "$k" rev-parse refs/tags/kitt-record)"; git -C "$k" update-ref -d refs/tags/kitt-record
  git -C "$k" update-ref refs/tags/v9.9.9 "$obj"
  # the same, with the record's `tag` header and a release-shaped first line: only the header check refuses it
  git -C "$k" -c gpg.format=ssh -c user.signingkey="$work/keys/a" tag -s -m "quokka-ci-kit v9.9.7" kitt-named HEAD
  obj="$(git -C "$k" rev-parse refs/tags/kitt-named)"; git -C "$k" update-ref -d refs/tags/kitt-named
  git -C "$k" update-ref refs/tags/v9.9.7 "$obj"
  # release check (b): a release-shaped tag on a commit off main.
  git -C "$k" checkout -q -b side; printf 'side\n' > "$k/kit/side"; git -C "$k" add -A; git -C "$k" commit -qm side
  side="$(git -C "$k" rev-parse HEAD)"; git -C "$k" checkout -q main
  git -C "$k" -c gpg.format=ssh -c user.signingkey="$work/keys/a" tag -s -m "quokka-ci-kit v9.9.8" v9.9.8 "$side"
  # a release whose first line is not `quokka-ci-kit <tag>`
  git -C "$k" -c gpg.format=ssh -c user.signingkey="$work/keys/a" tag -s -m "release v9.9.6" v9.9.6
  # a release signed by a listed key whose first line is the private kit's old form `ci-kit <tag>`
  git -C "$k" -c gpg.format=ssh -c user.signingkey="$work/keys/a" tag -s -m "ci-kit v9.9.5" v9.9.5
  # a symlink in kit/, last, so every other tag names a regular-file tree
  ln -s /etc/passwd "$k/kit/lib/link"; git -C "$k" add -A; git -C "$k" commit -qm link
  ktag a v1.0.4
  git clone -q --bare "$k" "$bare"
  # the adopter: a clone of its own origin, whose main carries ci/KIT-SIGNERS
  git init -q --bare --initial-branch=main "$ao"
  git init -q --initial-branch=main "$a"; git -C "$a" config user.email f@i; git -C "$a" config user.name f
  mkdir -p "$a/ci/kit/bin"; printf 'old\n' > "$a/ci/kit/bin/stale"; signers_line a > "$a/ci/KIT-SIGNERS"
  git -C "$a" add -A; git -C "$a" commit -qm adopter
  git -C "$a" remote add origin "$ao"; git -C "$a" push -q origin main; git -C "$a" fetch -q origin
  FX="$a"
  ku() { : > "$work/o"; KU_RC=0; host "$BASH" "$KITT_KIT/bin/kit-update" "$@" > "$work/o" 2>&1 || KU_RC=$?; }
  before="$(git -C "$a" status --porcelain)"
  ku v1.0.0 --verify-only "file://$bare"
  rc_is "release check (e): --verify-only on a good release" 0 "$KU_RC"
  eq "release check (e): prints the five lines" "tag commit tree signer vendored" "$(awk '{print $1}' "$work/o" | tr '\n' ' ' | sed 's/ $//')"
  has "the signer is the principal ci/KIT-SIGNERS names" "$work/o" "signer signer-a@fixture"
  has "the tree is the tag's kit tree" "$work/o" "tree $(git -C "$k" rev-parse 'v1.0.0^{commit}:kit')"
  eq "and nothing in the working copy changed" "$before" "$(git -C "$a" status --porcelain)"
  ku v1.0.1 --verify-only "file://$bare"; rc_is "an unsigned annotated tag" 2 "$KU_RC"; has "says no signature" "$work/o" "carries no SSH signature, so nothing was changed."
  ku v1.0.2 --verify-only "file://$bare"; rc_is "a lightweight tag" 2 "$KU_RC"; has "says it is not annotated" "$work/o" "is not an annotated tag"
  ku v1.0.3 --verify-only "file://$bare"; rc_is "a tag signed by a key ci/KIT-SIGNERS does not list" 2 "$KU_RC"; has "says unlisted" "$work/o" "is not signed by a key that ci/KIT-SIGNERS lists, so nothing was changed."
  ku v1.0.4 --verify-only "file://$bare"; rc_is "a signed tag whose kit/ holds a symlink" 2 "$KU_RC"; has "says not a regular file" "$work/o" "holds an entry that is not a regular file"
  ku v9.9.9 --verify-only "file://$bare"; rc_is "release check (a): a record object, signed by a listed key, at refs/tags/v9.9.9" 2 "$KU_RC"
  has "release check (a): refused for its own name" "$work/o" "names a tag object whose own name is 'kitt-record' and type 'commit', not v9.9.9 and commit"
  ku v9.9.7 --verify-only "file://$bare"; rc_is "release check (a): a signed release-shaped object whose tag header is another name" 2 "$KU_RC"
  has "release check (a): refused for its own name, alone" "$work/o" "whose own name is 'kitt-named'"
  ku v9.9.8 --verify-only "file://$bare"; rc_is "release check (b): a release-shaped tag on a commit off main" 2 "$KU_RC"
  has "release check (b): says it is not on main" "$work/o" "which is not on file://$bare's main, so it is not a release"
  ku v9.9.6 --verify-only "file://$bare"; rc_is "a message whose first line is not quokka-ci-kit <tag>" 2 "$KU_RC"; has "says it does not begin with the line" "$work/o" "does not begin with the line 'quokka-ci-kit v9.9.6'"
  ku v9.9.5 --verify-only "file://$bare"; rc_is "a signed tag whose first line is the old form ci-kit <tag>" 2 "$KU_RC"; has "says it does not begin with the renamed line" "$work/o" "does not begin with the line 'quokka-ci-kit v9.9.5'"
  ku v1.0.5 --verify-only "file://$bare"; rc_is "release check (c): a good release whose message forges a Good line" 0 "$KU_RC"
  has "release check (c): the signer is the real principal" "$work/o" "signer signer-a@fixture"
  hasnt "release check (c): not the forged one" "$work/o" "someone-else"
  ku v9.9.99 --verify-only "file://$bare"; rc_is "a tag that does not exist" 2 "$KU_RC"
  ku main --verify-only "file://$bare"; rc_is "a name that is not a release tag" 2 "$KU_RC"
  # release check (d): a working copy whose ci/KIT-SIGNERS differs from main's, listing the signer of v1.0.3
  { signers_line a; signers_line b; } > "$a/ci/KIT-SIGNERS"
  ku v1.0.3 --verify-only "file://$bare"; rc_is "release check (d): a working copy's ci/KIT-SIGNERS that differs from main's" 2 "$KU_RC"
  has "release check (d): says it differs from main's" "$work/o" "ci/KIT-SIGNERS differs from main's, so nothing was changed."
  signers_line a > "$a/ci/KIT-SIGNERS"
  # the first vendoring: main carries no ci/KIT-SIGNERS, so the working copy's is used and fingerprinted
  git -C "$a" update-ref -d refs/remotes/origin/main
  ku v1.0.0 --verify-only "file://$bare"; rc_is "a first vendoring" 0 "$KU_RC"
  has "it says so" "$work/o" "this is a first vendoring"
  has "and prints each line's fingerprint" "$work/o" "ci/KIT-SIGNERS line 1, signer-a@fixture: 256 SHA256:"
  git -C "$a" fetch -q origin
  # the real update
  ku v1.0.0 "file://$bare"
  rc_is "the update of a signed tag" 0 "$KU_RC"
  check "ci/kit is the tag's kit/ tree: the old file is gone" test ! -e "$a/ci/kit/bin/stale"
  check "an executable stays executable" test -x "$a/ci/kit/bin/tool"
  git -C "$a" add -A
  eq "ci/kit hashes to the tag's kit tree" "$(git -C "$k" rev-parse 'v1.0.0^{commit}:kit')" "$(git -C "$a" rev-parse "$(git -C "$a" write-tree):ci/kit")"
  eq "ci/KIT-VERSION's tree line names that tree" "$(git -C "$k" rev-parse 'v1.0.0^{commit}:kit')" "$(awk '$1=="tree"{print $2}' "$a/ci/KIT-VERSION")"
  has "the release's changelog entry is printed" "$work/o" "moves keys: yes"
  hasnt "and not the next release's" "$work/o" "old"
  git -C "$a" commit -qm vendored
  tree="$(git -C "$a" rev-parse HEAD:ci/kit)"
  ku v1.0.3 "file://$bare"
  rc_is "a refused update after a good one" 2 "$KU_RC"
  eq "leaves ci/kit as it was" "$tree" "$(git -C "$a" add -A && git -C "$a" rev-parse "$(git -C "$a" write-tree):ci/kit")"
  rm "$a/ci/KIT-SIGNERS"; ku v1.0.0 --verify-only "file://$bare"
  rc_is "no ci/KIT-SIGNERS" 2 "$KU_RC"; has "says no release can be verified" "$work/o" "There is no ci/KIT-SIGNERS in this working copy"
}
