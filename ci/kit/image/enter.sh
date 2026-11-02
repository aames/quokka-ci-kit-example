#!/usr/bin/env bash
#
# THE JOB IMAGE'S ENTRY (kit/README.md §2.2, §2.1).
# Derived from the author's private reference implementation. Installed in
# the base image as /usr/local/bin/cikit-enter and started by
# ci/kit/bin/container run:
#
#   cikit-enter <job>   < git archive --format=tar <commit>
#   cikit-enter <job>   < git pack-objects --revs --stdout (the commit's id), with CIKIT_COMMIT
#
# It knows no job list: <job> is a word, and what it does is decided by the
# environment the launcher set from the commit's ci/manifest:
#   CIKIT_TREE     the commit's tree hash (always)
#   CIKIT_COMMIT   the commit's id, set only for a `history` job; its
#                  presence selects the pack path
#   CIKIT_PROJECT  the manifest's `project`, for the dead push path
#   CIKIT_ADAPTER  the verdict script, a path in the tree: the manifest's
#                  `adapter`, or ci/kit/tests/run for the kit job
#   CIKIT_INSTALL  `<kind> <dir>` from the job's `install` line, when it has
#                  one; the one kind of manifest v1 is npm-ci
#
# THE TREE GOES IN BY COPY, NEVER BY A BIND MOUNT. The archive path unpacks
# into /src on the container's own filesystem, makes one commit of everything
# with the fixed identity cikit <cikit@invalid> at 2000-01-01T00:00:00Z, and
# compares that commit's tree with CIKIT_TREE: a synthetic commit is enough
# for a verdict that reads no history. The pack path (a `history` job) makes
# an empty repository in /src, indexes the pack from stdin, detaches HEAD at
# CIKIT_COMMIT and checks the tree out, then asserts HEAD is CIKIT_COMMIT and
# HEAD's tree is CIKIT_TREE. Either way a mismatch is exit 2 and nothing runs,
# which keeps "the commit, never the working copy" true. /src has no remote
# and no ref but HEAD.
#
# Equal: the job's install, if any, against the cache the launcher mounted,
# an install and not a check, its failure exit 2; then
# `exec bash "$CIKIT_ADAPTER" <job>` in /src, whose status is the job's.
#
# A SECOND FENCE ON THE ORIGIN: the job has no credential and no remote by
# construction; the four variables below also re-aim a push at any GitHub
# prefix to /dev/null/<project>-no-push-from-a-job/, which cannot exist.
#
# This runs inside the image under its own bash; it is not a host file.
#
# EXIT: the job's status; 2 when the job did not run (usage, the environment,
# the commit, the tree, the install, no verdict script).
set -euo pipefail

say() { printf '%s\n' "$*"; }
no() { say "$1" >&2; exit 2; }

job="${1:-}"
if ! [[ "$job" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] || [ "${#job}" -gt 32 ]; then
  no "usage: cikit-enter <job> (the archive, or for a history job the pack, on stdin; CIKIT_TREE, CIKIT_PROJECT and CIKIT_ADAPTER set)"
fi
readonly HASH_RE='^[0-9a-f]{40}([0-9a-f]{24})?$'
# A repository-relative path: no leading /, no . or .. segment, no space.
readonly PATH_RE='^[A-Za-z0-9_.@+-]+(/[A-Za-z0-9_.@+-]+)*$'
readonly DOTS_RE='(^|/)\.\.?(/|$)'
[[ "${CIKIT_TREE:-}" =~ $HASH_RE ]] || no "CIKIT_TREE does not name a tree, so ${job} did not run."
[[ "${CIKIT_PROJECT:-}" =~ ^[a-z][a-z0-9]{1,15}$ ]] || no "CIKIT_PROJECT does not name a project, so ${job} did not run."
adapter="${CIKIT_ADAPTER:-}"
if ! [[ "$adapter" =~ $PATH_RE ]] || [[ "$adapter" =~ $DOTS_RE ]]; then
  no "CIKIT_ADAPTER does not name a path in the tree, so ${job} did not run."
fi
history=false
if [ -n "${CIKIT_COMMIT+set}" ]; then
  [[ "$CIKIT_COMMIT" =~ $HASH_RE ]] || no "CIKIT_COMMIT does not name a commit, so ${job} did not run."
  history=true
fi
not_the_tree() { no "The tree in the container is not the commit's tree, so ${job} did not run."; }

readonly SRC=/src
readonly DEAD_PUSH="/dev/null/${CIKIT_PROJECT}-no-push-from-a-job/"
export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false
export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
export GIT_CONFIG_KEY_1="url.${DEAD_PUSH}.pushInsteadOf" GIT_CONFIG_VALUE_1=https://github.com/
export GIT_CONFIG_KEY_2="url.${DEAD_PUSH}.pushInsteadOf" GIT_CONFIG_VALUE_2=git@github.com:
export GIT_CONFIG_KEY_3="url.${DEAD_PUSH}.pushInsteadOf" GIT_CONFIG_VALUE_3=ssh://git@github.com/
unset SSH_AUTH_SOCK

mkdir -p "$SRC"
[ -z "$(ls -A "$SRC")" ] || no "${SRC} is not empty, so ${job} did not run."
cd "$SRC"
git init -q --object-format="$([ "${#CIKIT_TREE}" -eq 64 ] && echo sha256 || echo sha1)" .
git config core.autocrlf false
git config commit.gpgsign false

if [ "$history" = true ]; then
  # THE COMMIT ITSELF. index-pack checks every object's hash as it writes the
  # pack, so what arrived is what the commit names. Checking out the id
  # detaches HEAD and writes no ref.
  git index-pack --stdin > /dev/null || not_the_tree
  git -c advice.detachedHead=false checkout -q --detach "$CIKIT_COMMIT" 2> /dev/null || not_the_tree
  head="$(git rev-parse --verify -q HEAD)" || not_the_tree
  [ "$head" = "$CIKIT_COMMIT" ] || not_the_tree
else
  tar -x -p -f - -C "$SRC" || not_the_tree
  # One commit of exactly what arrived. -f, because a tracked file that matches
  # a .gitignore pattern is in the archive and must be in the tree.
  git --literal-pathspecs add -A -f .
  GIT_AUTHOR_NAME=cikit GIT_AUTHOR_EMAIL=cikit@invalid GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' \
    GIT_COMMITTER_NAME=cikit GIT_COMMITTER_EMAIL=cikit@invalid GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
    git commit -q --no-verify --allow-empty -m "the tree of ${CIKIT_TREE}"
fi
tree="$(git rev-parse 'HEAD^{tree}')" || not_the_tree
[ "$tree" = "$CIKIT_TREE" ] || not_the_tree
if [ "$history" = true ]; then
  say "The commit in the container is ${head} with its history, and its tree is ${tree}, the commit's."
else
  say "The tree in the container is ${tree}, the commit's."
fi

# THE INSTALL, one closed kind per manifest v1 (kit/README.md §3.3 `install`).
if [ -n "${CIKIT_INSTALL:-}" ]; then
  kind="${CIKIT_INSTALL%% *}"
  dir="${CIKIT_INSTALL#* }"
  if [ "$kind" = "$CIKIT_INSTALL" ] || ! [[ "$dir" =~ $PATH_RE ]] || [[ "$dir" =~ $DOTS_RE ]]; then
    no "CIKIT_INSTALL is not <kind> <dir>, so ${job} did not run."
  fi
  case "$kind" in
    npm-ci)
      say "Installing the dependencies in ${dir} in the job image."
      rc=0
      (cd "${SRC}/${dir}" && npm ci --no-audit --no-fund) < /dev/null || rc=$?
      [ "$rc" -eq 0 ] || no "npm ci failed in the job image, so ${job} did not run."
      ;;
    *) no "The install kind ${kind} is not one this kit knows, so ${job} did not run." ;;
  esac
fi

[ -f "${SRC}/${adapter}" ] || no "The tree has no ${adapter}, so ${job} did not run."
exec bash "$adapter" "$job"
