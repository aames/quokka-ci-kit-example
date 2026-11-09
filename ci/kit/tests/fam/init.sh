# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-init (docs/kit-init.md section 7.3, section 10, section 11 piece 2): the generator of an adopter's
# files, with no Docker daemon and no network. kit-init runs from a vendored copy of the kit under test
# (ci/kit/bin/kit-init in a scratch repository, so tests/plants can plant a defect in the kit tree and see
# this family turn red), on the host farm plus the docker shim, with --checksums, and with https_proxy and
# HTTPS_PROXY pointing at a port nothing listens on, so a lookup that escaped the offline path would fail
# (AC-KI-6). The sources of each shape are fixture/init/src/**; the example adopter's six files at 8ad9623
# are the golden output (fixture/init/golden/**, AC-KI-20).
#
#   AC-KI-2, AC-KI-3  the host rule, as syntax-tree tests (fixture/init/hostrule.py), each with a planted source
#   AC-KI-4, AC-KI-35 every refusal of section 2.3: exit 2, its sentence, and nothing changed
#   AC-KI-6, AC-KI-7  the offline path, with a positive control that the proxy trap is live
#   AC-KI-9           the restore by byte length: a CRLF Makefile of 16 bytes and a write that fails after it
#   AC-KI-20          the golden run on the example's shape
#   AC-KI-27          the guard of the kit's own workflow, extracted from it and run on planted documents
#   AC-KI-28          the five planted defects live in tests/plants and turn this family red
#   AC-KI-29, AC-KI-30  all eight shapes through the four checks (the end-to-end half is tests/image)
#   AC-KI-37          the . shape carries one declared, keyed escaping-read line (the fence half is K-escaping)
#   AC-KI-38          no file under the kit has a name a test runner collects by default; fixture sources are
#                     stored as NAME.fixture and placed as NAME by ki_cp
#   AC-KI-39          a stack directory with no test file: the scan line, exit 1 and the step before make check
#   KI-s 1 to 6       the security read's fixes: no write through a link or outside the top, bounded directory
#                     names, -I, exit 3 when a check did not run, a failed commit named, a detached HEAD refused
KI_FIX="$KITT_FIX/init"
KI_SUMS="$KI_FIX/checksums"
# a run whose checks all hold exits 0 where a python3 with PyYAML runs it, and 3 where none does, because
# check-workflow then does not run (the security read KI-s, finding 4)
KI_GREEN=0
[ -n "$PYYAML" ] || KI_GREEN=3

# init_base: a repository on branch adopt with the kit under test vendored at ci/kit and ci/KIT-VERSION, once.
init_base() {
  local r="$work/ibase" f
  [ -d "$r" ] && return 0
  git init -q --initial-branch=main "$r"
  git -C "$r" config user.name init
  git -C "$r" config user.email init@fixture
  printf 'readme\n' > "$r/README.md"
  git -C "$r" add -A && git -C "$r" commit -qm init
  git -C "$r" checkout -q -b adopt
  mkdir -p "$r/ci/kit"
  for f in bin lib hooks image templates; do cp -R "$KITT_KIT/$f" "$r/ci/kit/$f"; done
  git -C "$r" add -A && git -C "$r" commit -qm vendor
  printf 'tag v1.1.0-rc.1\ncommit %s\ntree %s\nsigner init@fixture\nvendored 2026-11-03\n' \
    "$(git -C "$r" rev-parse HEAD)" "$(git -C "$r" rev-parse HEAD:ci/kit)" > "$r/ci/KIT-VERSION"
  git -C "$r" add -A && git -C "$r" commit -qm version
}
# init_new <name>: a fresh copy of the base at $work/<name>; IR is it.
init_new() {
  init_base
  rm -rf "${work:?}/$1"
  cp -R "$work/ibase" "$work/$1"
  IR="$work/$1"
}
init_commit() { git -C "$IR" add -A && git -C "$IR" commit -qm "${1:-fixture}"; }
# ki_cp <fixture dir> <dest dir>: copy a fixture tree, each NAME.fixture placed as NAME (docs/kit-init.md rev 3,
# R3-5: the kit stores no file a test runner collects by default, so its sources carry .fixture).
ki_cp() {
  local f
  mkdir -p "$2"
  cp -R "$1/." "$2/"
  ( cd "$1" && find . -type f -name '*.fixture' ) | while IFS= read -r f; do mv "$2/$f" "$2/${f%.fixture}"; done
}
# init_put <fixture src> <dest>: copy a source tree from fixture/init/src into the repository, committed.
init_put() { ki_cp "$KI_FIX/src/$1" "$IR/$2"; init_commit "$1"; }
# ki_collectable <dir>: every file under dir whose name a test runner or compiler collects by default from a
# repository's top (AC-KI-38), one per line, sorted; nothing when there is none.
ki_collectable() {
  ( cd "$1" && find . -type f \( -name '*.go' -o -name '*.ts' -o -name '*.tsx' -o -name '*.mts' -o -name '*.cts' \
    -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name 'test_*.py' -o -name '*_test.py' \
    -o -name 'conftest.py' \) | sort )
}
# init_file <path> <text>: a file written (text as printf takes it) and committed.
init_file() { mkdir -p "$(dirname "$IR/$1")"; printf '%b' "$2" > "$IR/$1"; init_commit "$1"; }

# the closed port the proxy variables name (AC-KI-6): bound, read, closed.
init_port() {
  [ -n "${KI_PORT:-}" ] && return 0
  KI_PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
}
init_env() {
  init_port
  KI_ENV=(HOME="$work" TMPDIR="$work" PATH="$work/shims:$farm" SYS_PATH="$KITT_SYS_PATH" SHIM_STATE="$SHIM_STATE"
    DOCKER_LOG="$DOCKER_LOG" TOOLS="$TOOLS" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
    https_proxy="http://127.0.0.1:$KI_PORT" HTTPS_PROXY="http://127.0.0.1:$KI_PORT"
    http_proxy="http://127.0.0.1:$KI_PORT" HTTP_PROXY="http://127.0.0.1:$KI_PORT" no_proxy= NO_PROXY=)
}
# kinit <args...>: the vendored kit-init in $IR (or $KI_CWD); KI_RC, $work/ki.out, $work/ki.err.
kinit() {
  local cwd="${KI_CWD:-$IR}"
  init_env
  KI_RC=0
  : > "$DOCKER_LOG"
  ( cd "$cwd" && env -i "${KI_ENV[@]}" "${PYYAML:-python3}" "$IR/ci/kit/bin/kit-init" "$@" ) > "$work/ki.out" 2> "$work/ki.err" || KI_RC=$?
}
# in_repo <command...>: a command in $IR on the same farm; IN_RC, $work/in.out (both streams).
in_repo() {
  init_env
  IN_RC=0
  ( cd "$IR" && env -i "${KI_ENV[@]}" KIT_KEYS_REPO="$IR" "$@" ) > "$work/in.out" 2>&1 || IN_RC=$?
}
# snap: everything a refusal must leave alone, as one text: the porcelain status, the index tree, HEAD, the
# directory listing outside .git (an empty directory is not in git's status) and any state directory.
snap() {
  ( cd "$IR" && git status --porcelain --untracked-files=all; git write-tree; git rev-parse HEAD
    find . -path ./.git -prune -o -print | sort; ls -d .git/*-ci 2> /dev/null; true )
}
# ki_refuse <label> <sentence> <args...>: exit 2, the sentence on stderr, nothing changed (AC-KI-4).
ki_refuse() {
  local label="$1" want="$2" before after
  shift 2
  before="$(snap)"
  kinit "$@"
  after="$(snap)"
  kok "$label" 2
  has "$label: the sentence" "$work/ki.err" "$want"
  eq "$label: the status, the index, HEAD and the tree are as they were" "$before" "$after"
}
# same_exec <file> <other>: the file is executable and byte-equal to the other.
same_exec() { [ -x "$1" ] && cmp -s "$1" "$2"; }
# kok <label> <want>: the last kinit's exit code, with its streams shown when it is not the one wanted.
kok() {
  rc_is "$1" "$2" "$KI_RC"
  [ "$KI_RC" -eq "$2" ] || { echo "    stderr:"; show "$work/ki.err" 8; echo "    stdout:"; show "$work/ki.out" 8; }
}
# no_comment <file>: the file's lines other than comments and blanks.
no_comment() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

fam_init() {
  local f s d out shape want line before rc

  # ------------------------------------------------------------------------------------------------
  # AC-KI-2 and AC-KI-3 (docs/kit-init.md section 8): the host rule, read from the syntax tree.
  # ------------------------------------------------------------------------------------------------
  out="$work/hostrule.out"; rc=0
  python3 "$KI_FIX/hostrule.py" "$KITT_KIT/bin/kit-init" > "$out" 2>&1 || rc=$?
  rc_is "AC-KI-2 and AC-KI-3: kit-init parses as Python 3.9 and starts only git, docker, ssh-keygen, bash and sys.executable, by list, with no shell" 0 "$rc"
  has "AC-KI-3: six subprocess.run calls were read" "$out" "6 subprocess.run calls"
  check "AC-KI-1: the file is executable and starts with an env python3 line" test -x "$KITT_KIT/bin/kit-init" -a "$(head -1 "$KITT_KIT/bin/kit-init")" = '#!/usr/bin/env python3'
  # red once: the checker is held to a source that breaks each rule
  printf 'import subprocess\nsubprocess.run("ls -l", shell=True)\n' > "$work/hr1.py"
  rc=0; python3 "$KI_FIX/hostrule.py" "$work/hr1.py" > "$out" 2>&1 || rc=$?
  rc_is "AC-KI-3 (red once): a string command with shell=True is a finding" 1 "$rc"
  has "AC-KI-3 (red once): and the finding says it was not given a list" "$out" "subprocess.run is not given a list"
  has "AC-KI-3 (red once): and that shell was passed" "$out" "subprocess.run passes shell"
  printf 'import subprocess\nsubprocess.run(["curl", "-s", "x"])\n' > "$work/hr2.py"
  rc=0; python3 "$KI_FIX/hostrule.py" "$work/hr2.py" > "$out" 2>&1 || rc=$?
  rc_is "AC-KI-3 (red once): a list that starts with curl is a finding" 1 "$rc"
  has "AC-KI-3 (red once): and the finding names the rule" "$out" "starts with something other than git, docker, ssh-keygen, bash or sys.executable"
  printf 'import os, subprocess\nos.system("ls")\nsubprocess.check_output(["git", "status"])\n' > "$work/hr3.py"
  rc=0; python3 "$KI_FIX/hostrule.py" "$work/hr3.py" > "$out" 2>&1 || rc=$?
  rc_is "AC-KI-3 (red once): os.system and subprocess.check_output are findings" 1 "$rc"
  has "AC-KI-3 (red once): os.system is named" "$out" "os.system starts a process outside subprocess.run"
  has "AC-KI-3 (red once): subprocess.check_output is named" "$out" "subprocess.check_output starts a process outside subprocess.run"
  printf 'import subprocess, sys\nsubprocess.run([sys.executable, "-c", "1"])\nsubprocess.run(["bash", "-c", "1"])\n' > "$work/hr4.py"
  rc=0; python3 "$KI_FIX/hostrule.py" "$work/hr4.py" > "$out" 2>&1 || rc=$?
  rc_is "AC-KI-3 (control): sys.executable and bash lists pass" 0 "$rc"
  printf 'def f(x):\n    match x:\n        case 1:\n            return 2\n' > "$work/hr5.py"
  rc=0; python3 "$KI_FIX/hostrule.py" "$work/hr5.py" > "$out" 2>&1 || rc=$?
  rc_is "AC-KI-2 (red once): a match statement, newer than Python 3.9, does not parse at feature_version (3, 9)" 1 "$rc"
  has "AC-KI-2 (red once): and the finding says so" "$out" "does not parse as Python 3.9"
  # the version refusal itself: the source run as if Python were 3.8.18, in an empty-handed repository
  init_new vers
  before="$(snap)"
  init_env
  rc=0
  ( cd "$IR" && env -i "${KI_ENV[@]}" KI_SRC="$IR/ci/kit/bin/kit-init" python3 -c 'import os, sys
sys.version_info = (3, 8, 18, "final", 0)
sys.argv = ["kit-init", "--project", "old"]
exec(compile(open(os.environ["KI_SRC"]).read(), "kit-init", "exec"))' ) > "$work/ki.out" 2> "$work/ki.err" || rc=$?
  rc_is "AC-KI-2: on a Python below 3.9 kit-init exits 2" 2 "$rc"
  has "AC-KI-2: with its sentence" "$work/ki.err" "kit-init needs python3 3.9 or later, and this is 3.8.18, so nothing was written."
  eq "AC-KI-2: and nothing was written" "$before" "$(snap)"

  # ------------------------------------------------------------------------------------------------
  # AC-KI-4: every refusal of section 2.3 has a case. One repository holds the stack directories the
  # refusals need; a refusal changes nothing, so the cases share it.
  # ------------------------------------------------------------------------------------------------
  init_new rf
  init_put go api
  init_put go ginex; printf 'module x\n\ngo 1.27\n\ntoolchain go1.27\n' > "$IR/ginex/go.mod"
  init_put go gnotc; printf 'module x\n\ngo 1.27\n' > "$IR/gnotc/go.mod"
  init_put go worker; printf 'module x\n\ngo 1.27\n\ntoolchain go1.27.2\n' > "$IR/worker/go.mod"
  init_put node web
  init_put node web2; printf '24.22.0\n' > "$IR/web2/.nvmrc"
  init_put node nlts; printf 'lts/*\n' > "$IR/nlts/.nvmrc"
  init_put node nbad; printf '{\n' > "$IR/nbad/package.json"
  init_put node nnopin; rm -f "$IR/nnopin/.nvmrc"
  init_put python py
  init_put python pinex; printf '3.12\n' > "$IR/pinex/.python-version"
  mkdir -p "$IR/plain" "$IR/plain2"; printf 'x\n' > "$IR/plain/file"; printf 'x\n' > "$IR/plain2/file"
  init_commit "stack directories"

  # not at the top of a working copy; not a working copy at all
  KI_CWD="$IR/plain" ki_refuse "refusal: run in a subdirectory of a working copy" "kit-init runs at the top of a git working copy, so nothing was written." --project refuse
  mkdir -p "$work/nogit"
  KI_CWD="$work/nogit" ki_refuse "refusal: run outside any working copy" "kit-init runs at the top of a git working copy, so nothing was written." --project refuse
  KI_CWD=""
  # the usage
  ki_refuse "refusal: no --project" "kit-init needs --project NAME, so nothing was written."
  ki_refuse "refusal: an unknown flag" "--rust is not a stack kit-init knows (it knows --go, --node and --python), so nothing was written." --project refuse --rust api
  ki_refuse "refusal: a word that is not a flag" "stray is not a flag; kit-init takes flags only, so nothing was written." --project refuse stray
  ki_refuse "refusal: a flag with no value" "--cron needs a value, so nothing was written." --project refuse --cron
  ki_refuse "refusal: --project twice" "--project is given twice, so nothing was written." --project refuse --project again
  ki_refuse "refusal: --agent-files-only with another flag" "--agent-files-only takes no other flag, and --go was given, so nothing was written." --agent-files-only --go api
  # the project word
  ki_refuse "refusal: a project word with a capital" "Refuse is not a project name the manifest accepts (a lower-case letter, then 1 to 15 lower-case letters or digits), so nothing was written." --project Refuse
  ki_refuse "refusal: a project word of one letter" "r is not a project name the manifest accepts" --project r
  ki_refuse "refusal: a project word of seventeen letters" "abcdefghijklmnopq is not a project name the manifest accepts" --project abcdefghijklmnopq
  ki_refuse "refusal: a cron that is not five words" "--cron 'x y' is not five cron words such as '20 6 * * 1', so nothing was written." --project refuse --cron 'x y'
  # the jobs
  ki_refuse "refusal: a job named checks" "checks cannot name a job (it is kit-init's always-on job); give the directory a name with DIR:JOB, so nothing was written." --project refuse --go api:checks --checksums "$KI_SUMS"
  ki_refuse "refusal: a job named kit" "kit cannot name a job (it is kit-init's kit job)" --project refuse --go api:kit --checksums "$KI_SUMS"
  ki_refuse "refusal: a job named prune" "prune cannot name a job (it is kit-init's prune job)" --project refuse --go api:prune --checksums "$KI_SUMS"
  ki_refuse "refusal: a job named image" "image cannot name a job (it is a word the manifest keeps for the job image)" --project refuse --go api:image --checksums "$KI_SUMS"
  ki_refuse "refusal: a job named base" "base cannot name a job (it is a word the manifest keeps for the base image)" --project refuse --go api:base --checksums "$KI_SUMS"
  ki_refuse "refusal: a job name out of shape" "Bad_Name cannot name a job (a job name is lower-case letters and digits in words joined by -, at most 32 characters); give the directory a name with DIR:JOB, so nothing was written." --project refuse --go api:Bad_Name --checksums "$KI_SUMS"
  ki_refuse "refusal: two directories that would both be named api" "api cannot name a job (api and worker would both be named api); give the directory a name with DIR:JOB, so nothing was written." --project refuse --go api --go worker:api --checksums "$KI_SUMS"
  ki_refuse "refusal: a directory with a .. segment" "../x is not a directory the manifest accepts (it holds a . or .. segment), so nothing was written." --project refuse --go ../x
  ki_refuse "refusal: an absolute directory" "/tmp is not a directory the manifest accepts (it holds an absolute path, white space or one of * ? [ ] \\ : or a leading -), so nothing was written." --project refuse --go /tmp
  ki_refuse "refusal: a directory this working copy lacks" "nope is not a directory in this working copy, so nothing was written." --project refuse --go nope
  # a directory without its stack file
  ki_refuse "refusal: a Go directory with no go.mod" "plain has no go.mod, so it is not a Go directory and nothing was written." --project refuse --go plain
  ki_refuse "refusal: a Node directory with no package.json" "plain has no package.json, so it is not a Node directory and nothing was written." --project refuse --node plain
  ki_refuse "refusal: a Python directory with no .python-version" "plain has no .python-version, and the job image is pinned from it; a range such as pyproject.toml's requires-python is not a pin, so nothing was written." --project refuse --python plain
  # a pin that is absent or not exact
  ki_refuse "refusal: a go.mod with no toolchain line" 'gnotc/go.mod has no toolchain line, and the job image is pinned from it; add one such as "toolchain go1.27.3", so nothing was written.' --project refuse --go gnotc --checksums "$KI_SUMS"
  ki_refuse "refusal: a go.mod toolchain that is not exact" 'ginex/go.mod pins "go1.27", which is not an exact version such as go1.27.3, so nothing was written.' --project refuse --go ginex --checksums "$KI_SUMS"
  ki_refuse "refusal: a Node directory with no .nvmrc or .node-version" "nnopin has no .nvmrc or .node-version, and the job image is pinned from it; add one holding an exact version such as 24.22.1, so nothing was written." --project refuse --node nnopin --checksums "$KI_SUMS"
  ki_refuse "refusal: a .nvmrc of lts/*" 'nlts/.nvmrc holds "lts/*", which is not an exact version such as 24.22.1, so nothing was written.' --project refuse --node nlts --checksums "$KI_SUMS"
  ki_refuse "refusal: a package.json that is not JSON" "nbad/package.json is not JSON kit-init can read, so nothing was written." --project refuse --node nbad --checksums "$KI_SUMS"
  ki_refuse "refusal: a .python-version that is not exact" 'pinex/.python-version holds "3.12", which is not an exact version such as 3.12.7, so nothing was written.' --project refuse --python pinex --checksums "$KI_SUMS"
  # repeated stacks that disagree
  ki_refuse "refusal: two Go directories pinning different toolchains" "api/go.mod pins go1.27.3 and worker/go.mod go1.27.2, and the job image carries one Go, so nothing was written." --project refuse --go api --go worker --checksums "$KI_SUMS"
  ki_refuse "refusal: two Node directories pinning different versions" "web/.nvmrc pins 24.22.1 and web2/.nvmrc 24.22.0, and the job image carries one Node, so nothing was written." --project refuse --node web --node web2 --checksums "$KI_SUMS"
  # --postgres
  ki_refuse "refusal: --postgres naming no stack job" "--postgres names db, which no stack flag declared, so nothing was written." --project refuse --go api --postgres db --checksums "$KI_SUMS"
  ki_refuse "refusal: --postgres with a major that is no number" "--postgres api names the major x, which is not a number such as 18, so nothing was written." --project refuse --go api --postgres api:x --checksums "$KI_SUMS"
  ki_refuse "refusal: --postgres naming a job twice" "--postgres names api twice; a job has one service, so nothing was written." --project refuse --go api --postgres api --postgres api:17 --checksums "$KI_SUMS"
  # the branch
  init_new onmain
  git -C "$IR" branch -D main -q && git -C "$IR" branch -m main
  ki_refuse "refusal: the current branch is the main branch" "kit-init commits the adoption on a branch for its own pull request, and this is main, so nothing was written." --project refuse
  kinit --project refuse --no-commit --no-agent-files
  kok "and --no-commit does not raise it" "$KI_GREEN"
  IR="$work/rf"
  # the checksums: one sentence per value that cannot be had, each naming its URL (AC-KI-7)
  grep -v 'go1.27.3.linux-amd64' "$KI_SUMS" > "$work/sums-nogo"
  ki_refuse "refusal: a checksums file with no Go amd64 line" "--checksums $work/sums-nogo has no sha256 for go1.27.3.linux-amd64.tar.gz; its project publishes it at https://go.dev/dl/?mode=json&include=all, as a line \"<64 hex>  <file name>\", so nothing was written." --project refuse --go api --checksums "$work/sums-nogo"
  grep -v 'node-v24.22.1-linux-arm64' "$KI_SUMS" > "$work/sums-nonode"
  ki_refuse "refusal: a checksums file with no Node arm64 line" "has no sha256 for node-v24.22.1-linux-arm64.tar.xz; its project publishes it at https://nodejs.org/dist/v24.22.1/SHASUMS256.txt" --project refuse --node web --checksums "$work/sums-nonode"
  grep -v 'cpython-3.12.15' "$KI_SUMS" > "$work/sums-nopy"
  ki_refuse "refusal: a checksums file with no Python lines" "has no sha256 for cpython-3.12.15+<tag>-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz; its project publishes it at https://api.github.com/repos/astral-sh/python-build-standalone/releases?per_page=10" --project refuse --python py --checksums "$work/sums-nopy"
  grep -v 'postgres:18' "$KI_SUMS" > "$work/sums-nopg"
  ki_refuse "refusal: a checksums file with no postgres digest" "has no index digest for postgres:18; \`docker buildx imagetools inspect postgres:18\` prints it, as a line \"<64 hex>  postgres:18\", so nothing was written." --project refuse --go api --postgres api --checksums "$work/sums-nopg"
  ki_refuse "refusal: a checksums file that cannot be read" "--checksums $work/no-such-sums cannot be read, so nothing was written." --project refuse --go api --checksums "$work/no-such-sums"
  # no network fallback behind a missing value (AC-KI-7): the docker shim never saw a digest lookup
  check "AC-KI-7: a missing value never reaches a lookup (the docker shim saw no imagetools call)" test -z "$(grep imagetools "$DOCKER_LOG")"

  # --signer
  ki_refuse "refusal: --signer auto with no gpg.format ssh" "--signer auto needs gpg.format ssh and a user.signingkey whose public key can be read, so nothing was written." --project refuse --signer auto
  printf 'not a key\n' > "$work/notkey"
  ki_refuse "refusal: --signer FILE holding no key" "$work/notkey holds no single SSH public key line of a type the signers check knows, so nothing was written." --project refuse --signer "$work/notkey"
  cat "$work/keys/a.pub" "$work/keys/b.pub" > "$work/twokeys"
  ki_refuse "refusal: --signer FILE holding two keys" "$work/twokeys holds no single SSH public key line of a type the signers check knows, so nothing was written." --project refuse --signer "$work/twokeys"
  git -C "$IR" config gpg.format ssh; git -C "$IR" config user.signingkey "$work/keys/nonesuch"
  ki_refuse "refusal: --signer auto with a user.signingkey whose public key cannot be read" "--signer auto needs gpg.format ssh and a user.signingkey whose public key can be read, so nothing was written." --project refuse --signer auto
  git -C "$IR" config --unset gpg.format; git -C "$IR" config --unset user.signingkey

  # no git identity: raised for a commit, and for a signer; not for --no-commit alone
  init_new noid
  git -C "$IR" config --unset user.name; git -C "$IR" config --unset user.email
  ki_refuse "refusal: no git identity for the adoption commit" "git has no user.name or user.email here, and the adoption commit and the signer's principal need them, so nothing was written." --project refuse
  ki_refuse "refusal: no git identity for a signer, even with --no-commit" "git has no user.name or user.email here, and the adoption commit and the signer's principal need them, so nothing was written." --project refuse --no-commit --signer "$work/keys/a.pub"
  kinit --project noid --no-commit --no-agent-files
  kok "no git identity is not raised with --no-commit and no signer: the run is written" "$KI_GREEN"

  # a file it would write exists: one sentence per file
  for f in ci/manifest ci/ci-job.sh ci/image/Dockerfile .github/workflows/ci.yml .githooks/pre-push ci/allowed-signers; do
    init_new ex
    init_file "$f" 'something\n'
    ki_refuse "refusal: $f already exists" "$f already exists, so nothing was written." --project refuse
  done
  init_new ex
  for f in ci/manifest ci/ci-job.sh ci/image/Dockerfile .github/workflows/ci.yml .githooks/pre-push ci/allowed-signers; do mkdir -p "$(dirname "$IR/$f")"; printf 'x\n' > "$IR/$f"; done
  init_commit "all six"
  kinit --project refuse
  kok "refusal: all six files exist" 2
  eq "refusal: and each is named, one sentence per file" "6" "$(grep -c ' already exists, so nothing was written.$' "$work/ki.err")"
  # a file it appends to already holds what it would add
  init_new ex
  init_file Makefile 'check:\n\t@true\n'
  ki_refuse "refusal: a Makefile with a check target" "The Makefile already has a check target, so nothing was written." --project refuse
  init_new ex
  init_file Makefile '.PHONY: check\ncheck ::\n\t@true\n'
  ki_refuse "refusal: a Makefile with a check :: target" "The Makefile already has a check target, so nothing was written." --project refuse
  init_new ex
  init_file AGENTS.md '# Agents\n\n<!-- quokka-ci-kit section begin: written by kit-init -->\nold\n'
  ki_refuse "refusal: an AGENTS.md that already holds the section" "AGENTS.md already holds the quokka-ci-kit section, so nothing was written." --project refuse
  kinit --project refuse --no-agent-files --no-commit
  kok "and --no-agent-files does not raise it" "$KI_GREEN"
  init_new ex
  init_file CLAUDE.md '<!-- quokka-ci-kit section begin: written by kit-init -->\nold\n'
  ki_refuse "refusal: a CLAUDE.md that already holds the section" "CLAUDE.md already holds the quokka-ci-kit section, so nothing was written." --project refuse
  # the kit is not vendored
  init_new ex
  git -C "$IR" rm -q ci/KIT-VERSION && git -C "$IR" commit -qm "unvendor"
  ki_refuse "refusal: the kit is not vendored (no ci/KIT-VERSION)" "There is no ci/kit/lib/keys.sh or ci/KIT-VERSION; vendor the kit with kit-update first, so nothing was written." --project refuse
  # --agent-files-only
  init_new ex
  ki_refuse "refusal: --agent-files-only where HEAD carries no manifest" "HEAD carries no ci/manifest the kit accepts" --agent-files-only
  # the rendered manifest fails the lint (a defect of the generator, so provoked with a lint that refuses)
  init_new lint
  printf '#!/usr/bin/env bash\necho "manifest line 1: a finding the stub lint invented"\nexit 1\n' > "$IR/ci/kit/bin/check-manifest"
  init_commit "a lint that refuses"
  ki_refuse "refusal: the rendered manifest fails check-manifest (AC-KI-5)" "The manifest kit-init would write does not pass check-manifest, so nothing was written." --project refuse
  has "AC-KI-5: and the lint's own finding is printed first" "$work/ki.out" "a finding the stub lint invented"
  # a template that names a token outside the closed set, and one that leaves a token unreplaced (AC-KI-19)
  init_new tok
  printf '# a template with a token kit-init does not know: @@NOPE@@\n' >> "$IR/ci/kit/templates/allowed-signers"
  init_commit "unknown token"
  ki_refuse "refusal: a template naming a token outside the closed set" "names the token @@NOPE@@, which kit-init does not know; that is a defect of the templates, so nothing was written." --project refuse
  init_new tok
  printf '# a token the set knows, left without a value: @@DIGEST@@\n' >> "$IR/ci/kit/templates/allowed-signers"
  init_commit "unreplaced token"
  ki_refuse "refusal: a token left unreplaced in a file it would write (AC-KI-19)" "ci/allowed-signers would hold the unreplaced token @@DIGEST@@, a defect of kit-init, so nothing was written." --project refuse

  # ------------------------------------------------------------------------------------------------
  # AC-KI-35: a file kit-init reads that is not UTF-8 is a refusal with exit 2, not a traceback with exit 1
  # ------------------------------------------------------------------------------------------------
  check "AC-KI-35: the fixture holds the byte 0xe9, which no UTF-8 text does" test "$(LC_ALL=C grep -c "$(printf '\351')" "$KI_FIX/latin1")" -eq 1
  init_new u8
  init_put go lgo;  cp "$KI_FIX/latin1" "$IR/lgo/go.mod"
  init_put node lpkg; cp "$KI_FIX/latin1" "$IR/lpkg/package.json"
  init_put node lnvm; cp "$KI_FIX/latin1" "$IR/lnvm/.nvmrc"
  init_put python lpy; cp "$KI_FIX/latin1" "$IR/lpy/.python-version"
  init_put python lreq; cp "$KI_FIX/latin1" "$IR/lreq/requirements.txt"
  init_commit "latin-1 files"
  ki_refuse "AC-KI-35: a go.mod that is not UTF-8" "lgo/go.mod is not UTF-8 text kit-init can read, so nothing was written." --project refuse --go lgo --checksums "$KI_SUMS"
  ki_refuse "AC-KI-35: a package.json that is not UTF-8" "lpkg/package.json is not UTF-8 text kit-init can read, so nothing was written." --project refuse --node lpkg --checksums "$KI_SUMS"
  ki_refuse "AC-KI-35: a .nvmrc that is not UTF-8" "lnvm/.nvmrc is not UTF-8 text kit-init can read, so nothing was written." --project refuse --node lnvm --checksums "$KI_SUMS"
  ki_refuse "AC-KI-35: a .python-version that is not UTF-8" "lpy/.python-version is not UTF-8 text kit-init can read, so nothing was written." --project refuse --python lpy --checksums "$KI_SUMS"
  ki_refuse "AC-KI-35: a requirements file that is not UTF-8" "lreq/requirements.txt is not UTF-8 text kit-init can read, so nothing was written." --project refuse --python lreq --checksums "$KI_SUMS"
  init_put go api
  ki_refuse "AC-KI-35: a checksums file that is not UTF-8" "$KI_FIX/latin1 is not UTF-8 text kit-init can read, so nothing was written." --project refuse --go api --checksums "$KI_FIX/latin1"
  for f in Makefile .gitignore AGENTS.md CLAUDE.md; do
    init_new u8f
    cp "$KI_FIX/latin1" "$IR/$f"; init_commit "$f in latin-1"
    ki_refuse "AC-KI-35: an append target $f that is not UTF-8" "$f is not UTF-8 text kit-init can read, so nothing was written." --project refuse
  done
  init_new u8f
  cp "$KI_FIX/latin1" "$IR/AGENTS.md"; init_commit "AGENTS.md in latin-1"
  ki_refuse "AC-KI-35: --agent-files-only on an AGENTS.md that is not UTF-8" "AGENTS.md is not UTF-8 text kit-init can read, so nothing was written." --agent-files-only
  # rev 3, R3-2: the tag is read in the preflight, so a ci/KIT-VERSION that is not UTF-8 is refused before any write
  init_new u8v
  cp "$KI_FIX/latin1" "$IR/ci/KIT-VERSION"; init_commit "ci/KIT-VERSION in latin-1"
  ki_refuse "AC-KI-35: a ci/KIT-VERSION that is not UTF-8 (R3-2)" "ci/KIT-VERSION is not UTF-8 text kit-init can read, so nothing was written." --project refuse
  ki_refuse "AC-KI-35: a ci/KIT-VERSION that is not UTF-8, with --no-agent-files (R3-2)" "ci/KIT-VERSION is not UTF-8 text kit-init can read, so nothing was written." --project refuse --no-agent-files

  # ------------------------------------------------------------------------------------------------
  # AC-KI-6 and AC-KI-7: the offline path. The proxy trap is proven live first, by a run that is
  # allowed to look the value up.
  # ------------------------------------------------------------------------------------------------
  init_new net
  init_put go api
  kinit --project netcheck --go api
  kok "AC-KI-6 (control): without --checksums the lookup is tried, and the closed proxy port refuses it" 2
  has "AC-KI-6 (control): and the refusal names the URL and --checksums" "$work/ki.err" "could not be fetched from https://go.dev/dl/?mode=json&include=all"
  has "AC-KI-6 (control): and ends in the sentence" "$work/ki.err" "fetch it yourself and pass it with --checksums, so nothing was written."
  kinit --project netcheck --go api --checksums "$KI_SUMS"
  kok "AC-KI-6: with --checksums the same run passes through the same closed proxy" "$KI_GREEN"
  check "AC-KI-6: the docker shim saw no digest lookup" test -z "$(grep imagetools "$DOCKER_LOG")"
  eq "AC-KI-6: kit-init says where each value came from: the file it was given" "2" "$(grep -c "from $KI_SUMS\$" "$work/ki.out")"

  # ------------------------------------------------------------------------------------------------
  # AC-KI-9 and AC-KI-17: the restore by byte length. A CRLF Makefile of 16 bytes is an append target and
  # a later write fails; the write that succeeds leaves every original byte.
  # ------------------------------------------------------------------------------------------------
  check "AC-KI-9: the fixture Makefile is 16 bytes of CRLF" test "$(wc -c < "$KI_FIX/crlf-Makefile" | tr -d ' ')" -eq 16
  init_new rest
  init_put go api
  cp "$KI_FIX/crlf-Makefile" "$IR/Makefile"
  mkdir -p "$IR/AGENTS.md" && printf 'a directory where the file should be\n' > "$IR/AGENTS.md/note"
  init_commit "a CRLF Makefile and an AGENTS.md that is a directory, so the last write fails"
  before="$(snap)"
  kinit --project restore --go api --checksums "$KI_SUMS"
  kok "AC-KI-9: a write that fails after the Makefile was appended is a refusal" 2
  has "AC-KI-9: with its sentence" "$work/ki.err" "it removed the files it had created, so nothing was written."
  check "AC-KI-9: the CRLF Makefile is byte-equal to its original (16 bytes)" cmp -s "$KI_FIX/crlf-Makefile" "$IR/Makefile"
  eq "AC-KI-9: and is 16 bytes, not the 14 of its decoded text" "16" "$(wc -c < "$IR/Makefile" | tr -d ' ')"
  check "AC-KI-9: every file the run created is gone" test ! -e "$IR/ci/manifest" -a ! -e "$IR/ci/ci-job.sh" -a ! -e "$IR/ci/image" -a ! -e "$IR/.github" -a ! -e "$IR/.githooks" -a ! -e "$IR/ci/allowed-signers"
  eq "AC-KI-9: the status, the index, HEAD and the directory listing are as they were" "$before" "$(snap)"
  # the write that succeeds: every original byte stays and the addition follows after one blank line
  init_new keep
  init_put node web
  cp "$KI_FIX/crlf-Makefile" "$IR/Makefile"
  printf 'dist/' > "$IR/.gitignore"
  printf '# Agents\n\nmy rules\n' > "$IR/AGENTS.md"
  printf '# Claude\r\nmy rules\r\n' > "$IR/CLAUDE.md"
  init_commit "existing append targets"
  cp "$IR/Makefile" "$work/orig-Makefile"; cp "$IR/.gitignore" "$work/orig-gitignore"; cp "$IR/AGENTS.md" "$work/orig-agents"; cp "$IR/CLAUDE.md" "$work/orig-claude"
  kinit --project keep --node web --checksums "$KI_SUMS"
  kok "AC-KI-17: a run over existing append targets" "$KI_GREEN"
  has "AC-KI-17: .gitignore gained the Node stack's line" "$IR/.gitignore" "node_modules/"
  check "AC-KI-17: the Makefile keeps its 16 CRLF bytes as a prefix" cmp -s -n 16 "$work/orig-Makefile" "$IR/Makefile"
  check "AC-KI-17: .gitignore keeps its bytes (it had no final newline)" cmp -s -n "$(wc -c < "$work/orig-gitignore" | tr -d ' ')" "$work/orig-gitignore" "$IR/.gitignore"
  check "AC-KI-17: AGENTS.md keeps its bytes" cmp -s -n "$(wc -c < "$work/orig-agents" | tr -d ' ')" "$work/orig-agents" "$IR/AGENTS.md"
  check "AC-KI-17: CLAUDE.md keeps its CRLF bytes" cmp -s -n "$(wc -c < "$work/orig-claude" | tr -d ' ')" "$work/orig-claude" "$IR/CLAUDE.md"
  line="$(tail -c +17 "$IR/Makefile" | head -3 | tr '\n' '~')"
  case "$line" in "~# "*) ok "AC-KI-17: the Makefile's 17th byte is the blank line, then the kit's comment" ;; *) bad "AC-KI-17: after the original 16 bytes came [$line]" ;; esac
  eq "AC-KI-17: line 4 of AGENTS.md, after its three original lines, is the one blank line" "" "$(sed -n 4p "$IR/AGENTS.md")"
  eq "AC-KI-17: and the kit's section opens on line 5" "<!-- quokka-ci-kit section begin" "$(sed -n 5p "$IR/AGENTS.md" | cut -c1-32)"
  has "AC-KI-18: AGENTS.md now holds the section" "$IR/AGENTS.md" "<!-- quokka-ci-kit section begin"
  has "AC-KI-18: CLAUDE.md now holds the section" "$IR/CLAUDE.md" "<!-- quokka-ci-kit section begin"
  check "AC-KI-18: the section is the rendered template and names its check command" grep -q 'Run `make check` before you push' "$IR/AGENTS.md"
  check "AC-KI-19: no @@ token is in any file the run wrote" test -z "$(git -C "$IR" grep -l '@@' -- ci/manifest ci/ci-job.sh ci/image .github .githooks ci/allowed-signers Makefile AGENTS.md CLAUDE.md)"

  # ------------------------------------------------------------------------------------------------
  # AC-KI-20: the golden run. The example adopter's tree at 8ad9623, with its six files removed, is
  # regenerated and compared with the example's files, comment and blank lines set aside.
  # ------------------------------------------------------------------------------------------------
  init_new gold
  init_put go api
  init_put node web
  kinit --project rottnest --go api --node web --postgres api --checksums "$KI_SUMS" --no-agent-files
  kok "AC-KI-20: the golden run on the example's shape (rottnest, api, web, Postgres)" "$KI_GREEN"
  for f in ci/manifest ci/ci-job.sh ci/image/Dockerfile .github/workflows/ci.yml Makefile ci/allowed-signers; do
    # the example's signers file also holds the signer it added after its landing (docs/kit-init.md R-1, section 3.8)
    case "$f" in
      ci/allowed-signers) grep -v ' namespaces="git" ' "$KI_FIX/golden/$f" | grep -vE '^[[:space:]]*(#|$)' > "$work/g-want" ;;
      *) no_comment "$KI_FIX/golden/$f" > "$work/g-want" ;;
    esac
    no_comment "$IR/$f" > "$work/g-got"
    if cmp -s "$work/g-want" "$work/g-got"; then ok "AC-KI-20: $f equals the example's at 8ad9623, comment and blank lines set aside"
    else bad "AC-KI-20: $f differs from the example's at 8ad9623"; diff "$work/g-want" "$work/g-got" | head -12 | sed 's/^/    /'; fi
  done
  check "AC-KI-14: .githooks/pre-push is byte-equal to ci/kit/hooks/pre-push.shim" cmp -s "$IR/.githooks/pre-push" "$IR/ci/kit/hooks/pre-push.shim"
  no_comment "$KI_FIX/golden/.githooks/pre-push" > "$work/g-want"; no_comment "$IR/.githooks/pre-push" > "$work/g-got"
  check "AC-KI-20: and equals the example's hook, comment and blank lines set aside" cmp -s "$work/g-want" "$work/g-got"
  check "AC-KI-20: ci/ci-job.sh and .githooks/pre-push are executable" test -x "$IR/ci/ci-job.sh" -a -x "$IR/.githooks/pre-push"
  check "AC-KI-20: the golden fixture holds the example's weekly-cron and Postgres digest (the fixture is the real thing)" grep -q 'postgres:18@sha256:3a4264520e121176619f54ff867d12774bc81e95e7b84db58d63bccdb6144b81' "$KI_FIX/golden/ci/manifest"
  # AC-KI-15: one FROM, both checksums per tool, each pin file cross-checked
  eq "AC-KI-15: one FROM \${CIKIT_BASE}" "1" "$(grep -c '^FROM ' "$IR/ci/image/Dockerfile")"
  has "AC-KI-15: the FROM is the base build argument" "$IR/ci/image/Dockerfile" 'FROM ${CIKIT_BASE}'
  for s in 65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40 a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49 \
    6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6 dbabf7a1cbf947e6059ffad2c27b80041db97dea1e553b62afdee7f13fca336e; do
    has "AC-KI-15: the Dockerfile carries checksum ${s:0:12}" "$IR/ci/image/Dockerfile" "$s"
  done
  has "AC-KI-15: the Go pin file is cross-checked against the Dockerfile's version" "$IR/ci/image/Dockerfile" '[ "$toolchain" = "go${GO_VERSION}" ]'
  has "AC-KI-15: the Node pin file is cross-checked against the Dockerfile's version" "$IR/ci/image/Dockerfile" '[ "${nvmrc#v}" = "$NODE_VERSION" ]'
  has "AC-KI-15: the Go cache directory is made" "$IR/ci/image/Dockerfile" "/home/ci/go/pkg/mod"
  has "AC-KI-15: the Node cache directory is made" "$IR/ci/image/Dockerfile" "/home/ci/.npm"

  # ------------------------------------------------------------------------------------------------
  # AC-KI-30 (and AC-KI-10 to AC-KI-13, AC-KI-29's lint half): the eight shapes, each through the generator,
  # check-manifest at HEAD, check-workflow, check-escaping-reads and the adapter's unknown-job leg.
  # ------------------------------------------------------------------------------------------------
  for shape in go node gnp python novitest twogo nostack dot; do
    init_new "sh-$shape"
    case "$shape" in
      go) init_put go api; set -- --project goalone --go api ;;
      node) init_put node web; set -- --project nodeonly --node web ;;
      gnp) init_put go api; init_put node web; set -- --project rottnest --go api --node web --postgres api ;;
      python) init_put python py; set -- --project pyonly --python py ;;
      novitest) init_put novitest web; set -- --project stubnode --node web ;;
      twogo) init_put go api; init_put go worker; set -- --project twogo --go api --go worker ;;
      nostack) set -- --project nostack ;;
      dot) ki_cp "$KI_FIX/src/dot" "$IR"; init_commit dot; set -- --project dotted --go . ;;
    esac
    kinit "$@" --checksums "$KI_SUMS"
    kok "AC-KI-30 [$shape]: kit-init writes and commits" "$KI_GREEN"
    check "AC-KI-21 [$shape]: the adoption is one commit with the kit's message and a clean tree" test "$(git -C "$IR" log -1 --format=%s)" = "ci: adopt quokka-ci-kit v1.1.0-rc.1" -a -z "$(git -C "$IR" status --porcelain)"
    has "AC-KI-22 [$shape]: it prints check-manifest's exit code" "$work/ki.out" "check-manifest: exit 0"
    has "AC-KI-22 [$shape]: it prints check-escaping-reads' exit code" "$work/ki.out" "check-escaping-reads: exit 0"
    has "AC-KI-22 [$shape]: it prints check-prereqs' exit code" "$work/ki.out" "check-prereqs: exit 0"
    in_repo bash ci/kit/bin/check-manifest --commit HEAD
    rc_is "AC-KI-10 [$shape]: check-manifest at HEAD, rules 1 to 12" 0 "$IN_RC"
    if [ -n "$PYYAML" ]; then
      in_repo "$PYYAML" ci/kit/bin/check-workflow
      rc_is "AC-KI-12 [$shape]: check-workflow" 0 "$IN_RC"
    else
      note_not_run "tests/run:init:check-workflow [$shape]" "no python3 with PyYAML on this host, so check-workflow was not run on the generated workflow"
    fi
    in_repo python3 ci/kit/bin/check-escaping-reads
    rc_is "AC-KI-30 [$shape]: check-escaping-reads" 0 "$IN_RC"
    in_repo bash ci/ci-job.sh no-such-job
    rc_is "AC-KI-13 [$shape]: the adapter's unknown-job arm exits 2" 2 "$IN_RC"
    hasnt "AC-KI-13 [$shape]: and prints no counts line" "$work/in.out" "counts"
    has "AC-KI-13 [$shape]: and says there is no such job" "$work/in.out" "There is no job named no-such-job, so nothing ran."
    check "AC-KI-14 [$shape]: .githooks/pre-push is byte-equal to the kit's shim and executable" same_exec "$IR/.githooks/pre-push" "$IR/ci/kit/hooks/pre-push.shim"
    check "AC-KI-19 [$shape]: no @@ token in a written file" test -z "$(grep -rl '@@' "$IR/ci/manifest" "$IR/ci/ci-job.sh" "$IR/ci/image" "$IR/.github" "$IR/.githooks" "$IR/ci/allowed-signers" "$IR/Makefile" "$IR/AGENTS.md" "$IR/CLAUDE.md" 2> /dev/null)"
    eq "AC-KI-8 [$shape]: no state directory is left behind" "" "$(ls -d "$IR"/.git/*-ci 2> /dev/null)"
    check "AC-KI-16 [$shape]: ci/allowed-signers in the landing holds only comments" test -z "$(no_comment "$IR/ci/allowed-signers")"
    case "$shape" in
      novitest)
        in_repo bash ci/ci-job.sh web
        rc_is "AC-KI-13 [novitest]: the stub arm exits 2" 2 "$IN_RC"
        has "AC-KI-13 [novitest]: with its sentence" "$work/in.out" "The web arm is a stub kit-init wrote; put its checks in ci/ci-job.sh, so web did not run."
        hasnt "AC-KI-13 [novitest]: and no counts line" "$work/in.out" "counts"
        has "the stub's pin is not claimed in the manifest (no pin line for a stub, R-4 a)" "$IR/ci/manifest" "count web tests"
        hasnt "and no pin line for the stub" "$IR/ci/manifest" "pin web node"
        has "the closing steps say to fill the stub in" "$work/ki.out" "Fill in the stub arm of web in ci/ci-job.sh"
        ;;
      python)
        has "the Python job is a pytest arm" "$IR/ci/ci-job.sh" "pytest_tests"
        has "and the closing note says its escaping reads are a census by hand" "$work/ki.out" "Declared by hand: py is Python"
        has "the Dockerfile names python-build-standalone and the recorded release" "$IR/ci/image/Dockerfile" "ARG PBS_TAG=20261021"
        has "and the CPython pin cross-check" "$IR/ci/image/Dockerfile" 'pyver="$(tr -d'
        ;;
      twogo)
        eq "AC-KI-30 [twogo]: one Go toolchain in the one image" "1" "$(grep -c '^ARG GO_VERSION=' "$IR/ci/image/Dockerfile")"
        has "AC-KI-30 [twogo]: both directories are jobs" "$IR/ci/manifest" "job worker local"
        has "AC-KI-30 [twogo]: the first is the pin source" "$IR/ci/manifest" "pin-source go toolchain-line api/go.mod"
        eq "AC-KI-30 [twogo]: and only the first" "1" "$(grep -c '^pin-source go' "$IR/ci/manifest")"
        ;;
      nostack)
        has "AC-KI-30 [nostack]: the manifest holds the always-on and kit jobs only" "$IR/ci/manifest" "job kit local"
        eq "AC-KI-30 [nostack]: and no pin line" "0" "$(grep -c '^pin ' "$IR/ci/manifest")"
        has "AC-KI-30 [nostack]: the closing steps are numbered from 1 with no stub step" "$work/ki.out" " 1. make check"
        ;;
      dot)
        has "AC-KI-30 [dot]: the Go job's pin source is go.mod at the root" "$IR/ci/manifest" "pin-source go toolchain-line go.mod"
        has "AC-KI-30 [dot]: the escaping tree is ." "$IR/ci/manifest" "escaping-tree go ."
        # AC-KI-37 (rev 3, R3-3): a declared, keyed escaping-read line under the tree of . is accepted
        printf 'escaping-read go|db/x_test.go|go.mod|reads the module file at the top\n' >> "$IR/ci/manifest"
        init_commit "a declared read under ."
        in_repo bash ci/kit/bin/check-manifest --commit HEAD
        rc_is "AC-KI-37 [dot]: check-manifest at HEAD with the declared read" 0 "$IN_RC"
        in_repo python3 ci/kit/bin/check-escaping-reads
        rc_is "AC-KI-37 [dot]: check-escaping-reads accepts the keyed escaping-read line under ." 0 "$IN_RC"
        hasnt "AC-KI-37 [dot]: and does not say the file is outside the tree" "$work/in.out" "is declared for job go but is not in"
        ;;
      gnp)
        has "AC-KI-11 [gnp]: the Postgres service line names the project's URL variable" "$IR/ci/manifest" "url-env ROTTNEST_TEST_PG_URL"
        has "AC-KI-11 [gnp]: api's paths are its directory, web/.nvmrc and ci" "$IR/ci/manifest" "paths api api web/.nvmrc ci"
        has "AC-KI-11 [gnp]: image-path is ci/image then the pin files in flag order" "$IR/ci/manifest" "image-path ci/image api/go.mod web/.nvmrc"
        ;;
    esac
  done

  # AC-KI-39 (rev 3, R3-4): a Go or Node directory with no test file keeps its scan line, exits 1, and the first
  # closing step says to write a test before make check
  init_new notest
  init_put go api; rm -f "$IR/api/one_test.go"; init_commit "no Go test"
  kinit --project notest --go api --checksums "$KI_SUMS"
  kok "AC-KI-39 [go]: a Go directory with no test file exits 1" 1
  has "AC-KI-39 [go]: the fence's sentence" "$work/ki.out" "the escaping-read fence found no test files, so it would prove nothing."
  has "AC-KI-39 [go]: check-manifest passed" "$work/ki.out" "check-manifest: exit 0"
  has "AC-KI-39 [go]: the step names the directory, first" "$work/ki.out" " 1. Write a first test in api, commit it, and run python3 ci/kit/bin/check-escaping-reads again; CI's checks job refuses this tree until you do."
  has "AC-KI-39 [go]: make check follows it" "$work/ki.out" " 2. make check"
  has "AC-KI-39 [go]: the scan line is written" "$IR/ci/manifest" "escaping-scan go api"
  init_new notestn
  init_put node web; rm -f "$IR/web/src/one.test.ts"; printf 'export const one = 1\n' > "$IR/web/src/one.ts"; init_commit "no Node test"
  kinit --project notestn --node web --checksums "$KI_SUMS"
  kok "AC-KI-39 [node]: a Node directory with no test file exits 1" 1
  has "AC-KI-39 [node]: the step names the scan root, first" "$work/ki.out" " 1. Write a first test in web/src, commit it"
  has "AC-KI-39 [node]: the scan line is written" "$IR/ci/manifest" "escaping-scan ts web/src"
  init_new withtest
  init_put go api
  kinit --project withtest --go api --checksums "$KI_SUMS"
  hasnt "AC-KI-39 (control): with a test file there is no such step" "$work/ki.out" "Write a first test in"

  # AC-KI-38 (rev 3, R3-5): no file under the kit under test has a name a test runner collects by default; the walk
  # is proven live on a copy with one planted file
  eq "AC-KI-38: no file under the kit has a name a test runner collects by default" "" "$(ki_collectable "$KITT_KIT")"
  rm -rf "$work/k38"; cp -R "$KITT_KIT" "$work/k38"
  mkdir -p "$work/k38/tests/fixture/init/src/go"
  printf 'package x\n' > "$work/k38/tests/fixture/init/src/go/planted_test.go"
  eq "AC-KI-38 (red once): the walk finds a planted _test.go in a copy of the kit" "./tests/fixture/init/src/go/planted_test.go" "$(ki_collectable "$work/k38")"
  rm -rf "$work/k38"
  check "AC-KI-38: the fixture sources are stored as NAME.fixture" test -f "$KI_FIX/src/go/one_test.go.fixture"

  # the cron is one value in two places (AC-KI-12), the signer is printed and kept, never landed (AC-KI-16, AC-KI-8)
  init_new cron
  git -C "$IR" config user.email signer@fixture
  kinit --project crony --cron '5 4 * * 3' --signer "$work/keys/a.pub"
  kok "AC-KI-12: a run with --cron and --signer" "$KI_GREEN"
  has "AC-KI-12: the manifest's weekly-cron is the flag's" "$IR/ci/manifest" "weekly-cron 5 4 * * 3"
  has "AC-KI-12: and the workflow's schedule is the same five words" "$IR/.github/workflows/ci.yml" 'cron: "5 4 * * 3"'
  has "AC-KI-23: the last step names the schedule's day" "$work/ki.out" "Read the summary of the first scheduled run on its day: Wednesday 04:05 UTC."
  want="signer@fixture namespaces=\"git\" $(cut -d' ' -f1,2 "$work/keys/a.pub")"
  eq "AC-KI-16: the line kit-init kept is the principal and the key" "$want" "$(cat "$IR"/.git/crony-ci/init/allowed-signers.next 2> /dev/null)"
  has "AC-KI-16: and the line it printed is the same" "$work/ki.out" "$want"
  has "AC-KI-16: with the fingerprint ssh-keygen -lf prints" "$work/ki.out" "$(ssh-keygen -lf "$work/keys/a.pub" | cut -d' ' -f2)"
  eq "AC-KI-8: the state directory holds allowed-signers.next and nothing else" "allowed-signers.next" "$(ls "$IR/.git/crony-ci/init" 2> /dev/null)"
  check "AC-KI-16: the landing's ci/allowed-signers holds only comments, with --signer" test -z "$(no_comment "$IR/ci/allowed-signers")"
  check "AC-KI-16: and so does the committed copy" test -z "$(git -C "$IR" show HEAD:ci/allowed-signers | grep -vE '^[[:space:]]*(#|$)')"

  # AC-KI-18: --no-agent-files writes neither; --agent-files-only writes only the two, uncommitted
  init_new agent
  kinit --project agentic --no-agent-files
  kok "AC-KI-18: --no-agent-files" "$KI_GREEN"
  check "AC-KI-18: neither AGENTS.md nor CLAUDE.md exists" test ! -e "$IR/AGENTS.md" -a ! -e "$IR/CLAUDE.md"
  before="$(git -C "$IR" rev-parse HEAD)"
  kinit --agent-files-only
  kok "AC-KI-18: --agent-files-only on the adopted repository" "$KI_GREEN"
  eq "AC-KI-18: it writes only the two files" "?? AGENTS.md
?? CLAUDE.md" "$(git -C "$IR" status --porcelain)"
  eq "AC-KI-18: and commits nothing" "$before" "$(git -C "$IR" rev-parse HEAD)"
  has "AC-KI-18: the values came from the committed manifest: its adapter" "$IR/AGENTS.md" "\`ci/ci-job.sh\` is the one test script"
  has "AC-KI-18: its check command" "$IR/CLAUDE.md" "Run \`make check\` before you push."
  hasnt "AC-KI-18: no token is left" "$IR/AGENTS.md" "@@"

  # ------------------------------------------------------------------------------------------------
  # The security read KI-s, findings 1 to 6 (kit-init 3c): each red once against the kit-init before it.
  # ------------------------------------------------------------------------------------------------
  # Finding 1: no write through a symbolic link or outside the top; the outside files stay as they were
  rm -rf "$work/outside"; mkdir -p "$work/outside/gh"
  printf 'outside claude\n' > "$work/outside/x"; printf 'outside make\n' > "$work/outside/m"
  cp "$work/outside/x" "$work/outside-x.orig"; cp "$work/outside/m" "$work/outside-m.orig"
  init_new sym1
  ln -s ../outside/x "$IR/CLAUDE.md"; init_commit "a CLAUDE.md link out of the working copy"
  ki_refuse "KI-s 1: a committed CLAUDE.md that links out of the working copy" "CLAUDE.md is a symbolic link, and kit-init writes no file through one, so nothing was written." --project refuse
  check "KI-s 1: and the file it links to is untouched" cmp -s "$work/outside-x.orig" "$work/outside/x"
  init_new sym2
  ln -s ../outside/m "$IR/Makefile"; init_commit "a Makefile link out of the working copy"
  ki_refuse "KI-s 1: a committed Makefile that links out of the working copy" "Makefile is a symbolic link, and kit-init writes no file through one, so nothing was written." --project refuse
  check "KI-s 1: and the Makefile it links to is untouched" cmp -s "$work/outside-m.orig" "$work/outside/m"
  init_new sym3
  ln -s ../outside/gh "$IR/.github"; init_commit "a .github directory link out of the working copy"
  ki_refuse "KI-s 1: a committed .github that is a directory link out of the working copy" ".github is a symbolic link, and kit-init writes no file through one, so nothing was written." --project refuse
  eq "KI-s 1: and nothing was written in the directory it links to" "" "$(ls -A "$work/outside/gh")"
  init_new sym4
  ln -s ../outside/x "$IR/CLAUDE.md"; ln -s ../outside/m "$IR/Makefile"; ln -s ../outside/gh "$IR/.github"
  init_commit "all three links"
  ki_refuse "KI-s 1: all three links at once" "CLAUDE.md is a symbolic link" --project refuse
  eq "KI-s 1: one sentence for each link" "3" "$(grep -c ' is a symbolic link, and kit-init writes no file through one, so nothing was written.$' "$work/ki.err")"
  check "KI-s 1: and every outside file is as it was" cmp -s "$work/outside-x.orig" "$work/outside/x"
  check "KI-s 1: the outside Makefile too" cmp -s "$work/outside-m.orig" "$work/outside/m"
  init_new sym5
  printf '# Agents\n' > "$IR/AGENTS.md"; ln -s AGENTS.md "$IR/CLAUDE.md"; init_commit "a link inside the working copy"
  ki_refuse "KI-s 1: a link that stays inside the working copy is refused too" "CLAUDE.md is a symbolic link, and kit-init writes no file through one, so nothing was written." --project refuse
  init_new sym6
  kinit --project symsix --no-agent-files
  kok "KI-s 1 (setup): an adoption with no agent files" "$KI_GREEN"
  ln -s ../outside/x "$IR/CLAUDE.md"
  ki_refuse "KI-s 1: --agent-files-only refuses a CLAUDE.md link" "CLAUDE.md is a symbolic link, and kit-init writes no file through one, so nothing was written." --agent-files-only
  check "KI-s 1: and the file it links to is untouched" cmp -s "$work/outside-x.orig" "$work/outside/x"

  # Finding 2: a directory value reaches no generated file outside the bounded shape
  init_new bound
  d='api$(touch${IFS}PWNED)'
  ki_cp "$KI_FIX/src/go" "$IR/$d"; init_commit "a directory named with a substitution"
  ki_refuse "KI-s 2: a directory named with a command substitution" "$d is not a directory name kit-init writes into a generated file (a directory is ., or letters, digits and . _ / - starting with a letter or digit, with no .. segment), so nothing was written." --project refuse --go "$d:api" --checksums "$KI_SUMS"
  check "KI-s 2: no ci/ci-job.sh carries it and nothing ran it" test ! -e "$IR/ci/ci-job.sh" -a ! -e "$IR/PWNED"
  init_new bound2
  d="api'q"
  ki_cp "$KI_FIX/src/go" "$IR/$d"; init_commit "a directory named with a quote"
  ki_refuse "KI-s 2: a directory named with a quote" "$d is not a directory name kit-init writes into a generated file (a directory is ., or letters" --project refuse --go "$d:api" --checksums "$KI_SUMS"

  # Finding 3: the generator's own python runs isolated, so a yaml.py at the top is not imported
  init_new isol
  init_put go api
  printf 'open("YAML-IMPORTED", "w").close()\n' > "$IR/yaml.py"; init_commit "a yaml.py at the top"
  kinit --project isol --go api --checksums "$KI_SUMS"
  kok "KI-s 3: a run with a yaml.py at the repository's top" "$KI_GREEN"
  check "KI-s 3: the yaml.py was never imported" test ! -e "$IR/YAML-IMPORTED"
  eq "KI-s 3: and nothing was compiled from it" "" "$(ls "$IR/__pycache__" 2> /dev/null)"

  # Finding 4: a check that did not run is exit 3, said, with how to run it
  rm -rf "$work/venv-noyaml"
  "${PYYAML:-python3}" -m venv --without-pip "$work/venv-noyaml"
  rc=0; "$work/venv-noyaml/bin/python" -I -c 'import yaml' > /dev/null 2>&1 || rc=$?
  check "KI-s 4 (control): the venv's python cannot import yaml" test "$rc" -ne 0
  init_new noyaml
  init_put go api
  f="$PYYAML"; PYYAML="$work/venv-noyaml/bin/python"
  kinit --project noyaml --go api --checksums "$KI_SUMS"
  PYYAML="$f"
  kok "KI-s 4: with no PyYAML, check-workflow does not run and kit-init exits 3" 3
  has "KI-s 4: the NOT RUN line says how to run it" "$work/ki.out" "venv-noyaml/bin/python) has no PyYAML; install it and run python3 ci/kit/bin/check-workflow yourself; CI's always-on job runs it too."
  has "KI-s 4: and opens with NOT RUN, naming the python3 it asked" "$work/ki.out" "NOT RUN check-workflow: this python3 ("
  has "KI-s 4: and the closing lines say so" "$work/ki.out" "check-workflow did not run, so this run proves nothing about it: install PyYAML for python3 and run python3 ci/kit/bin/check-workflow before you push."
  check "KI-s 4: the files are still written and committed" test "$(git -C "$IR" log -1 --format=%s)" = "ci: adopt quokka-ci-kit v1.1.0-rc.1"

  # Finding 5: a failed commit is exit 1 and one line naming which step failed and what it said
  init_new cfail
  init_put go api
  mkdir -p "$IR/.git/hooks"
  printf '#!/bin/sh\necho "the hook refuses this commit" >&2\nexit 1\n' > "$IR/.git/hooks/pre-commit"; chmod +x "$IR/.git/hooks/pre-commit"
  before="$(git -C "$IR" rev-parse HEAD)"
  kinit --project cfail --go api --checksums "$KI_SUMS"
  kok "KI-s 5: a commit that fails is exit 1" 1
  has "KI-s 5: and one line names it" "$work/ki.out" "The files are written but the commit failed (git commit exited 1: the hook refuses this commit), so nothing is committed; commit them yourself, then run the checks below."
  eq "KI-s 5: and nothing was committed" "$before" "$(git -C "$IR" rev-parse HEAD)"

  # Finding 6: a detached HEAD is refused; the guess of main is said when origin/HEAD is missing
  init_new det
  git -C "$IR" checkout -q --detach
  ki_refuse "KI-s 6: a detached HEAD" "HEAD is detached, and kit-init commits on a branch for its own pull request, so nothing was written." --project refuse
  kinit --project det --no-commit --no-agent-files
  kok "KI-s 6: --no-commit on a detached HEAD commits nothing, so it is not refused" "$KI_GREEN"
  init_new guess
  kinit --project guess --no-agent-files
  kok "KI-s 6: a run with no origin/HEAD" "$KI_GREEN"
  has "KI-s 6: the closing lines say the main branch was guessed, and how to set origin/HEAD" "$work/ki.out" "kit-init took the main branch to be main, because origin/HEAD is not set here. If it is another branch, run git remote set-head origin -a"
  init_new guessed
  git -C "$IR" update-ref refs/remotes/origin/main HEAD
  git -C "$IR" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  kinit --project guessed --no-agent-files
  kok "KI-s 6 (control): a run with origin/HEAD set" "$KI_GREEN"
  hasnt "KI-s 6 (control): says no guess" "$work/ki.out" "kit-init took the main branch to be main"

  # ------------------------------------------------------------------------------------------------
  # AC-KI-27: the kit repository's workflow fails when its README or the guide for adopting with an agent
  # repeats a body line of the agent section, and passes when they cite its path. The guard is the step
  # itself, read out of .github/workflows/ci.yml and run on planted documents.
  # ------------------------------------------------------------------------------------------------
  init_guard
}

# init_guard: AC-KI-27.
init_guard() {
  local yml="$KITT_KIT/../.github/workflows/ci.yml" g="$work/g27" rc body
  if [ ! -f "$yml" ] || ! grep -q '^      - name: The agent section is cited, never copied$' "$yml"; then
    # not a NOT RUN line: the guard belongs to the kit repository's own workflow, and an adopter's kit job (kit/README.md
    # section 6.1) must print no NOT RUN line, so a tree without that workflow has nothing to apply it to
    echo "init: AC-KI-27's guard is a step of the kit repository's own workflow; this tree has none, so it does not apply."
    return 0
  fi
  awk '
    /^      - name: The agent section is cited, never copied$/ { on = 1; next }
    on && /^        run: \|$/ { body = 1; next }
    on && body { if ($0 ~ /^          / || $0 == "") { sub(/^          /, ""); print; next } else exit }
  ' "$yml" > "$work/guard.sh"
  check "AC-KI-27: the guard step was read out of the workflow" test -s "$work/guard.sh"
  rm -rf "$g"; mkdir -p "$g/kit/templates/agents" "$g/docs"
  cp "$KITT_KIT/templates/agents/section.md" "$g/kit/templates/agents/section.md"
  cp "$KITT_KIT/README.md" "$g/kit/README.md"
  guard() { rc=0; ( cd "$g" && env -i PATH="$KITT_SYS_PATH" HOME="$work" bash "$work/guard.sh" ) > "$work/guard.out" 2>&1 || rc=$?; }
  guard
  rc_is "AC-KI-27: the kit's README, which cites the template's path, passes" 0 "$rc"
  has "AC-KI-27: and the guard says what it read" "$work/guard.out" "body lines of kit/templates/agents/section.md, none repeated in kit/README.md."
  body="$(grep -m1 'Never push with' "$g/kit/templates/agents/section.md")"
  printf '\n%s\n' "$body" >> "$g/kit/README.md"
  guard
  rc_is "AC-KI-27 (red once): a body line copied into kit/README.md fails" 1 "$rc"
  has "AC-KI-27 (red once): and the finding names the document and the line" "$work/guard.out" "::error::kit/README.md repeats a body line of kit/templates/agents/section.md: - Never push with"
  cp "$KITT_KIT/README.md" "$g/kit/README.md"
  printf 'See ci/kit/templates/agents/section.md for what the agent is told.\n' > "$g/docs/adopt-with-an-agent.md"
  guard
  rc_is "AC-KI-27: a guide that cites the template's path passes" 0 "$rc"
  has "AC-KI-27: and both documents were read" "$work/guard.out" "none repeated in docs/adopt-with-an-agent.md, kit/README.md."
  body="$(grep -m1 'Never put a secret' "$g/kit/templates/agents/section.md" | sed 's/@@[A-Z_]*@@/ci\/ci-job.sh/g')"
  printf '\n%s\n' "$body" >> "$g/docs/adopt-with-an-agent.md"
  guard
  rc_is "AC-KI-27 (red once): a body line copied with its tokens filled in, into the guide, fails" 1 "$rc"
  has "AC-KI-27 (red once): and the finding names the guide" "$work/guard.out" "::error::docs/adopt-with-an-agent.md repeats a body line"
  rm -f "$g/docs/adopt-with-an-agent.md"
  guard
  rc_is "AC-KI-27: with no guide yet the guard passes on the README alone" 0 "$rc"
  : > "$g/kit/templates/agents/section.md"
  guard
  rc_is "AC-KI-27: an empty template is a failure, not a pass of nothing" 1 "$rc"
}
