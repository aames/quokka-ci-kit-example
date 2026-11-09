# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-keys (kit/README.md §6.2): the formula against an independent
# computation and against golden vectors; `absent`; `.` as the tree; the epoch
# moves every key; a working-tree manifest edit moves no key (kit/README.md §3.1); each
# function of the library's interface (pattern 5.1a).

# The formula, written again here in Python so the library is not its own oracle.
kitt_formula() { # kitt_formula <repo> <commit> <header> <path>...
  python3 - "$@" <<'PY'
import hashlib, os, subprocess, sys
repo, commit, header, paths = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
out = header + "\n"
for p in paths:
    if p == ".":
        oid = subprocess.run(["git", "-C", repo, "rev-parse", commit + "^{tree}"], capture_output=True, text=True).stdout.strip()
    else:
        r = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "-q", commit + ":" + p], capture_output=True, text=True)
        oid = r.stdout.strip() if r.returncode == 0 else "absent"
    out += p + " " + oid + "\n"
if os.environ.get("KITT_UID"):
    out += "user " + os.environ["KITT_UID"] + "\n"
print(hashlib.sha256(out.encode()).hexdigest())
PY
}

# Three golden commits: fixed blobs, a fixed manifest, the keys as literals.
kitt_golden_repo() {
  local d="$work/golden"
  rm -rf "$d"
  git init -q --initial-branch=main "$d"
  mkdir -p "$d/ci/kit/image" "$d/ci/image" "$d/src"
  cat > "$d/ci/manifest" <<'M'
manifest v1
project golden
key-epoch 3
local-epoch 1
main-branch main
workflow w.yml
always-on gate
adapter ci/a.sh
kit-job kself
signers ci/s
check-command make check
weekly-cron 7 5 * * 1
prune-keep-green gate
refuse-drafts yes
image ci/image/Dockerfile
image-path ci/image
job gate always-on
job one local
job kself local
paths gate .
paths one src missing/file ci
paths kself ci
count one n
count kself n
M
  printf 'FROM x\n' > "$d/ci/image/Dockerfile"
  printf 'base v1\n' > "$d/ci/kit/image/base.Dockerfile"
  printf 'package a\n' > "$d/src/a.go"
  git -C "$d" add -A && GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z git -C "$d" commit -qm one
  printf 'package a // two\n' > "$d/src/a.go"
  git -C "$d" add -A && GIT_AUTHOR_DATE=2026-01-02T00:00:00Z GIT_COMMITTER_DATE=2026-01-02T00:00:00Z git -C "$d" commit -qm two
  printf 'base v2\n' > "$d/ci/kit/image/base.Dockerfile"
  git -C "$d" add -A && GIT_AUTHOR_DATE=2026-01-03T00:00:00Z GIT_COMMITTER_DATE=2026-01-03T00:00:00Z git -C "$d" commit -qm three
}

fam_keys() {
  local d c i job want got shas k paths out rc
  kitt_golden_repo
  d="$work/golden"
  shas="$(git -C "$d" rev-list --reverse HEAD)"
  i=0
  for c in $shas; do
    i=$((i + 1))
    for job in gate one kself; do
      if [ "$job" = gate ]; then paths="."; elif [ "$job" = one ]; then paths="src missing/file ci"; else paths="ci"; fi
      # shellcheck disable=SC2086
      want="$(kitt_formula "$d" "$c" 'golden-ci-keys v3' $paths)"
      got="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$c" "$job")"
      eq "the formula, commit $i, job $job: the library equals the independent computation" "$want" "$got"
    done
    want="$(KITT_UID=1001 kitt_formula "$d" "$c" 'golden-ci-keys v3' ci/kit/image)"
    got="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$c" base)"
    eq "the base key is ci/kit/image alone then the user line, commit $i" "$want" "$got"
    want="$(KITT_UID=1001 kitt_formula "$d" "$c" 'golden-ci-keys v3' ci/kit/image ci/image)"
    got="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$c" image)"
    eq "the image key is ci/kit/image then the image-path PATHs then the user line, commit $i" "$want" "$got"
  done
  # The literals: fixed blobs give fixed keys on every machine and every run.
  # shellcheck disable=SC2034
  local g1 g2 g3
  set -- $shas
  g1="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$1" one)"
  g2="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$2" one)"
  g3="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$3" one)"
  eq "golden vector 1 (job one)" "f3eb2b9a5ddba099e14d9269124192600af54fd06bcd4405316bf39e6a320e1e" "$g1"
  eq "golden vector 2 (job one; src changed)" "119d119b73002c646213856dc110e3d25e2feb7f90d1b1a3464c0589d43965ef" "$g2"
  eq "golden vector 3 (job one; only ci/kit/image changed)" "9bb42f2b4c7124b013c4ca3c6db1e49157ef2aa63d4ecbcda57de33b3e14d0c9" "$g3"
  eq "golden vector 3 base key" "015e38c4a66f2e4ac3c4d50df7b6e634ad25a4095ccc8f6c7e39def9fce29a83" "$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$3" base)"
  eq "golden vector 1 gate key (the whole tree)" "a3ab2eb753921fe6748e53856bba7fe0607e89e143534bba25168076f29530c4" "$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$1" gate)"
  check "a change under a listed path moves the key; one outside every listed path of a job does not (gate moves, kself does not)" \
    test "$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$1" kself)" = "$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$2" kself)" \
    -a "$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$1" gate)" != "$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$2" gate)"
  # `absent`: a listed path the commit lacks is the word, and appears in the payload.
  want="$(kitt_formula "$d" "$1" 'golden-ci-keys v3' src missing/file ci)"
  eq "absent: a missing listed path hashes as the word absent" "$want" "$g1"
  # The epoch moves every key.
  git -C "$d" checkout -q -b epoch "$3"
  sed 's/^key-epoch 3/key-epoch 4/' "$d/ci/manifest" > "$d/m" && mv "$d/m" "$d/ci/manifest"
  git -C "$d" commit -qam epoch
  for job in gate one kself base image; do
    got="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" epoch "$job")"
    want="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$3" "$job")"
    check "the epoch moves the $job key" test "$got" != "$want"
  done
  # `user 1002` against the default 1001 moves the base and image (kit/README.md §3.2)
  # keys to the formula's value with the user line, and no other job's key.
  git -C "$d" checkout -q -b uid "$3"
  printf 'user 1002\n' >> "$d/ci/manifest"
  git -C "$d" commit -qam uid
  for job in base image; do
    paths="ci/kit/image"; [ "$job" = image ] && paths="ci/kit/image ci/image"
    got="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" uid "$job")"
    want="$(KITT_UID=1002 kitt_formula "$d" uid 'golden-ci-keys v3' $paths)"
    eq "user 1002 gives the $job key the formula with the user line" "$want" "$got"
    check "user 1002 moves the $job key from user 1001's" test "$got" != "$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" "$3" "$job")"
  done
  # kit/README.md §3.1: the key reads the commit's manifest, never the working tree's.
  git -C "$d" checkout -q -f main
  want="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" HEAD one)"
  sed 's/^key-epoch 3/key-epoch 9/; s/^paths one .*/paths one nowhere/' "$d/ci/manifest" > "$d/m" && mv "$d/m" "$d/ci/manifest"
  got="$(KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" HEAD one)"
  eq "an uncommitted edit of ci/manifest moves no key" "$want" "$got"
  git -C "$d" checkout -q -- ci/manifest
  # The interface (pattern 5.1a).
  rc=0; KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" nonsense one > /dev/null 2>&1 || rc=$?
  rc_is "a key of something that is not a commit" 1 "$rc"
  rc=0; KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" HEAD nojob > /dev/null 2>&1 || rc=$?
  rc_is "a key of a job the manifest lacks" 2 "$rc"
  rc=0; "$BASH" "$KITT_KIT/bin/keys" > /dev/null 2>&1 || rc=$?
  rc_is "keys with no argument is usage" 2 "$rc"
  KIT_KEYS_REPO="$d" "$BASH" "$KITT_KIT/bin/keys" HEAD > "$work/keys.out"
  eq "kit_keys: a line per job in manifest order" "gate one kself" "$(cut -d' ' -f1 "$work/keys.out" | tr '\n' ' ' | sed 's/ $//')"
  out="$(KIT_KEYS_REPO="$d" "$BASH" -c ". '$KITT_KIT/lib/keys.sh'; kit_manifest_load HEAD; kit_jobs local | tr '\n' ' '; echo; kit_key_paths one | tr '\n' ' '; echo; kit_count_fields kself; kit_pin_tools one; echo; kit_key_paths nojob; echo rc=\$?")"
  eq "kit_jobs, kit_key_paths, kit_count_fields, kit_pin_tools and an unkeyed name's status 2" "one kself 
src missing/file ci 
n


rc=2" "$out"
  fx_new keysfx
  eq "kit_pin_at: the toolchain-line, first-line and readonly-version kinds, read as data" "go1.27.3 v24.1.0 v0.11.0 3.14" \
    "$(KIT_KEYS_REPO="$FX" "$BASH" -c ". '$KITT_KIT/lib/keys.sh'; echo \$(kit_pin_at HEAD go) \$(kit_pin_at HEAD node) \$(kit_pin_at HEAD shellcheck) \$(kit_pin_at HEAD python)")"
  eq "kit_escaping_reads: the entries as written" "3" "$(KIT_KEYS_REPO="$FX" "$BASH" -c ". '$KITT_KIT/lib/keys.sh'; kit_manifest_load HEAD; kit_escaping_reads | wc -l | tr -d ' '")"
  eq "kit_platform_of: the system lower-cased, x86_64 as amd64, aarch64 as arm64, under this bash" "linux/amd64 linux/arm64 darwin/arm64 freebsd/riscv64" \
    "$("$BASH" -c ". '$KITT_KIT/lib/keys.sh'; echo \$(kit_platform_of Linux x86_64) \$(kit_platform_of Linux aarch64) \$(kit_platform_of Darwin arm64) \$(kit_platform_of FreeBSD riscv64)")"
  # the one shape (KIT_PLATFORM_SHAPE): every string kit_platform_of writes, Git Bash's and Cygwin's unames among them
  eq "kit_platform_of: Git Bash's, MSYS2's, Cygwin's and OpenBSD's unames" "mingw64_nt-10.0-19045/amd64 msys_nt-10.0-19045/amd64 cygwin_nt-10.0/amd64 openbsd/amd64" \
    "$("$BASH" -c ". '$KITT_KIT/lib/keys.sh'; echo \$(kit_platform_of MINGW64_NT-10.0-19045 x86_64) \$(kit_platform_of MSYS_NT-10.0-19045 x86_64) \$(kit_platform_of CYGWIN_NT-10.0 x86_64) \$(kit_platform_of OpenBSD amd64)")"
  eq "KIT_PLATFORM_SHAPE accepts what kit_platform_of writes and refuses the rest, under this bash" "linux/amd64:y darwin/arm64:y msys_nt-10.0-19045/amd64:y mingw64_nt-10.0-19045/amd64:y cygwin_nt-10.0/amd64:y openbsd/amd64:y Linux/amd64:n linux_amd64:n /amd64:n linux/:n -linux/amd64:n linux/amd64/x:n" \
    "$("$BASH" -c ". '$KITT_KIT/lib/keys.sh'; for p in linux/amd64 darwin/arm64 msys_nt-10.0-19045/amd64 mingw64_nt-10.0-19045/amd64 cygwin_nt-10.0/amd64 openbsd/amd64 Linux/amd64 linux_amd64 /amd64 linux/ -linux/amd64 linux/amd64/x; do if [[ \$p =~ \$KIT_PLATFORM_SHAPE ]]; then printf '%s:y ' \$p; else printf '%s:n ' \$p; fi; done" | sed 's/ $//')"
  # an empty word is refused: status 1 and nothing printed, so no caller can write `platform /`
  eq "kit_platform_of refuses an empty system, an empty architecture and both" "1[] 1[] 1[] 0[linux/amd64]" \
    "$("$BASH" -c ". '$KITT_KIT/lib/keys.sh'; for a in ':x86_64' 'Linux:' ':' 'Linux:x86_64'; do o=\$(kit_platform_of \"\${a%%:*}\" \"\${a#*:}\") && r=0 || r=\$?; printf '%s[%s] ' \$r \"\$o\"; done" | sed 's/ $//')"
}
