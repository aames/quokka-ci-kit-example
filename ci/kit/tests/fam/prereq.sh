# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-prereq (kit/README.md §6.2, §2.2): check-prereqs refuses Docker not
# answering, git below 2.34 and an ssh-keygen without -Y, each with its
# sentence; the runner-only entry points refuse bash below 4.2.
prereq_farm() { # prereq_farm <dir> <docker rc|absent> <git version> <ssh-keygen usage text>
  local d="$1"
  rm -rf "$d"; mkdir -p "$d"
  [ "$2" = absent ] || printf '#!/bin/sh\nexit %s\n' "$2" > "$d/docker"
  printf '#!/bin/sh\necho "git version %s"\n' "$3" > "$d/git"
  printf '#!/bin/sh\necho "%s" >&2\nexit 1\n' "$4" > "$d/ssh-keygen"
  chmod +x "$d"/*
}
prereq() { PRE_RC=0; env -i PATH="$1" "$BASH" "$KITT_KIT/bin/check-prereqs" > "$work/o" 2>&1 || PRE_RC=$?; }
fam_prereq() {
  local d="$work/pre" good='usage: ssh-keygen [-Y find-principals] [-Y sign]'
  prereq_farm "$d" 0 2.43.0 "$good"; prereq "$d"
  rc_is "all four hold" 0 "$PRE_RC"; has "one line says so" "$work/o" "check-prereqs: Docker answers, git version 2.43.0"
  prereq_farm "$d" 1 2.43.0 "$good"; prereq "$d"
  rc_is "Docker not answering" 2 "$PRE_RC"; has "its sentence" "$work/o" "Docker does not answer docker info. Start Docker (Docker Desktop on a Mac) and run this again."
  prereq_farm "$d" absent 2.43.0 "$good"; prereq "$d"
  rc_is "Docker absent" 2 "$PRE_RC"; has "its sentence" "$work/o" "docker is not on PATH."
  prereq_farm "$d" 0 2.33.9 "$good"; prereq "$d"
  rc_is "git below 2.34" 2 "$PRE_RC"; has "its sentence" "$work/o" "git 2.33 is older than 2.34, the first git that signs with SSH keys."
  prereq_farm "$d" 0 1.9.0 "$good"; prereq "$d"
  rc_is "git 1.x" 2 "$PRE_RC"
  prereq_farm "$d" 0 2.34.0 "$good"; prereq "$d"
  rc_is "git exactly 2.34 is enough" 0 "$PRE_RC"
  prereq_farm "$d" 0 2.43.0 'usage: ssh-keygen [-q] [-b bits]'; prereq "$d"
  rc_is "an ssh-keygen without -Y" 2 "$PRE_RC"; has "its sentence" "$work/o" "ssh-keygen does not know -Y find-principals. Install OpenSSH 8.2 or later."
  prereq_farm "$d" 1 2.20.0 'usage: nothing'; prereq "$d"
  rc_is "every check runs: three refusals" 2 "$PRE_RC"; eq "three sentences" 3 "$(grep -c '^check-prereqs: ' "$work/o")"
  # the runner-only entry points
  if [ -z "$BASH32" ]; then note_not_run tests/run:bash32 "no bash below 4 on this host, so the runner-only refusals did not run"; return 0; fi
  for e in plan record prune; do
    rc=0; env -i PATH="$KITT_SYS_PATH" "$BASH32" "$KITT_KIT/bin/$e" > "$work/o" 2>&1 || rc=$?
    rc_is "$e under bash below 4.2" 2 "$rc"; has "$e says it needs bash 4.2 or later" "$work/o" "needs bash 4.2 or later and this is bash"
  done
}
