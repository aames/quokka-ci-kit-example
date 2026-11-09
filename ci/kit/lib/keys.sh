#!/usr/bin/env bash
#
# THE ONE DEFINITION OF EVERY JOB'S CONTENT KEY, AND OF THE TRUST IN A RECORD
# (DESIGN.md 5.1, 5.1a, 5.4, 6.7; kit/README.md §2.1).
#
# A job's key is a hash of exactly the paths whose content decides its
# verdict. A job that passed writes refs/ci/green/<job>/<key>, or a signed
# workstation record refs/ci/local/<job>/<key>; a later run whose key already
# has a trusted record skips the job. So a verdict belongs to a TREE, not to a
# commit, and the commit's ci/manifest says which tree.
#
# THE FORMULA, for a commit C, the manifest at C, and a job's ordered paths:
#
#   sha256( "<project>-ci-keys v<key-epoch>\n"
#           + for each path p: p + " " + (git rev-parse C:p, or "absent") + "\n"
#           + for the image and base keys alone: "user <uid>\n" )
#
# `git rev-parse C:p` is the object id of that tree or blob, so a key moves
# exactly when content under a listed path moves, and a depth-1 checkout is
# enough. The path `.` stands for the whole tree (C^{tree}). A key reads the
# manifest OF ITS COMMIT, out of the object store, never the working tree.
#
# THE MANIFEST is data. It is read with `git show <commit>:ci/manifest` and
# parsed by ONE awk program (kit__manifest_awk), which tests every directive's
# SHAPE and prints the dump; it is never sourced and never evaluated. Every
# semantic rule (coverage, existence, the closed kinds) is ci/kit/bin/
# check-manifest's. A reader in another language takes `ci/kit/bin/keys dump`.
#
# HOW IT IS READ. The plan sources this file on the runner. Every other reader
# (the driver, the hook, the launcher) takes the COMMIT's copy out of the
# object store and calls one function of it in a child shell under "$BASH",
# so nothing a commit defines can replace a function of the reader's.
#
# BASH 3.2. The functions the host reaches run under the macOS /bin/bash:
#   kit_key  kit_keys  kit_key_paths  kit_pin_tools  kit_count_fields
#   kit_pin_at  kit_manifest_load  kit_manifest_dump  kit_jobs  kit_env_reserved
#   kit_platform_of
# and call only these host tools: git, awk, cut, and sha256sum or
# shasum -a 256. No declare -A, mapfile, readarray, case-changing expansions,
# [[ -v ]], wait -n, negative subscripts or coproc anywhere in this file. The
# trust functions (kit_record_trusted and the local arm) run on the runner
# only, inside the plan, and also call gh, ssh-keygen, sed, grep, mktemp, rm.
#
# THE REPOSITORY every function reads is KIT_KEYS_REPO when set (a harness's
# fixture), else the working directory. A commit is always an argument.

# SC2034: the KIT_* values are this library's answers, read by its callers.
# shellcheck disable=SC2034

# --- THE RESERVED ENVIRONMENT NAMES ---------------------------------------
#
# Never passed into a job by an `env` line (kit/README.md §3.3 `env`, §2.1).
# ONE list, read by the parser (rule 1) and by the launcher's own refusal
# through kit_env_reserved, so the two cannot drift. A word ending in * is a
# prefix, one starting with * a suffix, any other an exact name.
KIT_RESERVED_ENV='CIKIT_* GITHUB_* ACTIONS_* RUNNER_* GH_* GIT_* SSH_* DOCKER_* PATH HOME CI *_TOKEN *_KEY *_SECRET *_PASSWORD *_CREDENTIALS'

# kit_env_reserved <name>: 0 when <name> is reserved, else 1.
kit_env_reserved() {
  local p pats
  IFS=' ' read -r -a pats <<< "$KIT_RESERVED_ENV"
  for p in "${pats[@]}"; do
    case "$p" in
      *"*") [[ "${1:-}" == "${p%"*"}"* ]] && return 0 ;;
      "*"*) [[ "${1:-}" == *"${p#"*"}" ]] && return 0 ;;
      *) [ "${1:-}" = "$p" ] && return 0 ;;
    esac
  done
  return 1
}

# --- THE PLATFORM STRING ---------------------------------------------------
#
# kit_platform_of <uname -s> <uname -m>: `<os>/<arch>`, the system
# lower-cased, x86_64 read as amd64 and aarch64 as arm64 (DESIGN.md 6.5's
# `platform` row). The ONE computer of the string: the driver, the launcher
# and the record writer all call it, so a local record's platform and a CI
# record's cannot be spelled two ways. An empty word is refused: status 1 and
# nothing printed, so no caller can write `platform /`.
kit_platform_of() {
  local os="${1:-}" arch="${2:-}"
  [ -n "$os" ] && [ -n "$arch" ] || return 1
  case "$os" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) os="$(awk -v s="$os" 'BEGIN { print tolower(s) }')" ;;
  esac
  case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
  printf '%s/%s\n' "$os" "$arch"
}

# KIT_PLATFORM_SHAPE: the ONE shape of a platform string, every string
# kit_platform_of writes on a host the kit admits: a lower-case system word,
# which may carry `.`, `_` or `-` as Git Bash's and Cygwin's unames do
# (`mingw64_nt-10.0-19045`, `cygwin_nt-10.0`), a `/`, and an architecture
# word. Read by the plan's green arm for a job whose verdict ran on the
# runner and by `record` for the launcher's ran file. A `local` job's green
# record is held to linux/amd64 or linux/arm64 besides (kit__green_facts).
KIT_PLATFORM_SHAPE='^[a-z0-9][a-z0-9._-]*/[a-z0-9_]+$'

# --- THE PARSER -----------------------------------------------------------
#
# kit__manifest_awk <label>: the manifest text on stdin. On success, exit 0
# and one record per directive, in file order: `<line>\t<directive>\t<word>...`
# with a free-text field last and untouched. On a refusal, exit 2 and one
# sentence, `<label> line <n>: <the rule>`, and nothing else.
kit__manifest_awk() {
  LC_ALL=C awk -v label="$1" -v reserved_env="$KIT_RESERVED_ENV" '
    function refuse(msg) { refuse_at(NR, msg) }
    function refuse_at(n, msg) { if (!bad) print label " line " n ": " msg; bad = 1; exit 2 }
    function isname(s) { return s ~ /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/ && length(s) <= 32 }
    # A PATH holds no glob or pathspec character and no leading -, so the
    # lint never globs what the key reads literally and no word reaches git or
    # docker as an option (kit/README.md §3.1).
    function ispath(s) {
      if (s == ".") return 1
      if (index(s, "*") || index(s, "?") || index(s, "[") || index(s, "]") || index(s, "\\") || index(s, ":")) return 0
      return s != "" && s !~ /^-/ && s !~ /[ \t]/ && s !~ /^\// && s !~ /\/$/ && s !~ /\/\// && s !~ /(^|\/)\.\.?(\/|$)/
    }
    function envreserved(v,   i, p, n) {
      for (i = 1; i <= nres; i++) {
        p = res[i]; n = length(p) - 1
        if (substr(p, n + 1) == "*") { if (index(v, substr(p, 1, n)) == 1) return 1 }
        else if (substr(p, 1, 1) == "*") { p = substr(p, 2); if (length(v) >= length(p) && substr(v, length(v) - length(p) + 1) == p) return 1 }
        else if (v == p) return 1
      }
      return 0
    }
    function isint(s, lo, hi) { return s ~ /^[0-9]+$/ && length(s) <= 6 && s + 0 >= lo && s + 0 <= hi }
    function isdigested(s,   i, name, hex) {
      i = index(s, "@sha256:"); if (i < 2) return 0
      name = substr(s, 1, i - 1); hex = substr(s, i + 8)
      return length(hex) == 64 && hex ~ /^[0-9a-f]+$/ && name !~ /^-/ &&
        name ~ /^([a-z0-9.-]+(:[0-9]+)?\/)?[a-z0-9._\/-]+(:[A-Za-z0-9_][A-Za-z0-9_.-]*)?$/
    }
    function shape(s, t) {
      if (t == "name") return isname(s)
      if (t == "path") return ispath(s)
      if (t == "tool" || t == "kind") return s ~ /^[a-z][a-z0-9-]*$/
      if (t == "field") return s ~ /^[a-z][a-z0-9_]*$/
      if (t == "var") return s ~ /^[A-Z][A-Z0-9_]*$/
      if (t == "cron") return s ~ /^[A-Za-z0-9*,\/-]+$/
      return 0
    }
    function all(from, t,   i) {
      if (from > NF) return 0
      for (i = from; i <= NF; i++) if (!shape($i, t)) return 0
      return 1
    }
    # The text after the first k words, outer white space trimmed.
    function rest(k,   s, i) {
      s = $0; sub(/^[ \t]+/, "", s)
      for (i = 1; i <= k; i++) sub(/^[^ \t]+[ \t]*/, "", s)
      sub(/[ \t]+$/, "", s); return s
    }
    function isentry(s,   p, f, i, n, w) {
      for (i = 1; i <= 3; i++) { p = index(s, "|"); if (!p) return 0; f[i] = substr(s, 1, p - 1); s = substr(s, p + 1) }
      if (!isname(f[1]) || !ispath(f[2]) || s ~ /^[ \t]*$/) return 0
      if (f[3] == "WHOLE-TREE" || f[3] == "NONE") return 1
      n = split(f[3], w, " "); if (n == 0) return 0
      for (i = 1; i <= n; i++) if (!ispath(w[i])) return 0
      return 1
    }
    function probe_ok(   i, k) {
      if (NF < 3 || !shape($2, "tool")) return 0
      k = $3; i = 4
      if (k == "after-word") { if (NF < 4) return 0; i = 5 }
      else if (k != "version-flag" && k != "first-line" && k != "python-minor") return 0
      if (i <= NF && $i == "in") { if (i + 1 > NF || !ispath($(i + 1))) return 0; i += 2 }
      return i > NF || $i !~ /^-/
    }
    function service_ok(   i, nimg, nurl) {
      if (NF < 4 || !isname($2) || !shape($3, "kind")) return 0
      nimg = 0; nurl = 0
      for (i = 4; i <= NF; i += 2) {
        if (i == NF) return 0
        if ($i == "image") { if (nimg++ || !isdigested($(i + 1))) return 0 }
        else if ($i == "url-env") { if (nurl++ || !shape($(i + 1), "var")) return 0 }
        else if ($i == "flag") { if ($(i + 1) !~ /^[a-z_][a-z0-9_.]*=[^ \t]+$/) return 0 }
        else return 0
      }
      return nimg == 1 && nurl == 1
    }
    # 1 when the line is in shape; sets free to the free-text field, if any.
    function check(d) {
      free = ""
      if (d == "manifest") return NF == 2 && $2 == "v1"
      if (d == "project") return NF == 2 && $2 ~ /^[a-z][a-z0-9]+$/ && length($2) <= 16
      if (d == "key-epoch" || d == "local-epoch") return NF == 2 && isint($2, 1, 999)
      if (d == "prune-days") return NF == 2 && isint($2, 1, 365)
      if (d == "lock-wait-minutes") return NF == 2 && isint($2, 1, 240)
      if (d == "user") return NF == 2 && isint($2, 1000, 65533)
      if (d == "main-branch" || d == "always-on" || d == "kit-job") return NF == 2 && isname($2)
      if (d ~ /^(workflow|adapter|plan-extension|signers|image)$/) return NF == 2 && ispath($2)
      if (d == "image-path") return all(2, "path")
      if (d == "prune-keep-green" || d == "socket" || d == "history") return all(2, "name")
      if (d == "refuse-drafts") return NF == 2 && ($2 == "yes" || $2 == "no")
      if (d == "weekly-cron") return NF == 6 && all(2, "cron")
      if (d == "check-command") { free = rest(1); return free != "" }
      if (d == "job") return NF == 3 && isname($2) && $3 ~ /^(always-on|local|ci-only|content)$/
      if (d == "paths" || d == "escaping-tree") return isname($2) && all(3, "path")
      if (d == "check-name") return NF == 3 && isname($2) && isname($3)
      if (d == "pin") return isname($2) && all(3, "tool")
      if (d == "count") return isname($2) && all(3, "field")
      if (d == "cache") return isname($2) && all(3, "kind")
      if (d == "env") return isname($2) && all(3, "var")
      if (d == "install") return NF == 4 && isname($2) && shape($3, "kind") && ispath($4)
      if (d == "service") return service_ok()
      if (d == "pin-source") return NF == 4 && ($2 == "*" || shape($2, "tool")) && shape($3, "kind") && ispath($4)
      if (d == "probe") return probe_ok()
      if (d == "not-run-allowed") { free = rest(2); return NF >= 3 }
      if (d == "escaping-scan") return NF == 3 && shape($2, "kind") && ispath($3)
      if (d == "escaping-read") { free = rest(1); return isentry(free) }
      return 0
    }
    BEGIN {
      nreq = split("manifest project key-epoch local-epoch main-branch workflow always-on adapter kit-job signers check-command weekly-cron prune-keep-green refuse-drafts image image-path", req, " ")
      for (i = 1; i <= nreq; i++) single[req[i]] = 1
      n = split("plan-extension prune-days lock-wait-minutes user", a, " ");             for (i = 1; i <= n; i++) single[a[i]] = 1
      n = split("paths check-name pin count install service cache env escaping-tree", a, " "); for (i = 1; i <= n; i++) perjob[a[i]] = 1
      n = split("job socket history pin-source probe not-run-allowed escaping-scan escaping-read", a, " "); for (i = 1; i <= n; i++) other[a[i]] = 1
      nres = split(reserved_env, res, " ")
      n = split("prepare probe-after-prepare docker client-major client-bin-env", a, " "); for (i = 1; i <= n; i++) reserved[a[i]] = 1
      n = split("paths check-name pin-source probe", a, " ");                          for (i = 1; i <= n; i++) oncekey[a[i]] = 1
      # The names of the facts block, never a TOOL or a FIELD (kit/README.md §3.1).
      n = split("job key commit started duration_s platform host docker image not_run log_sha256", a, " "); for (i = 1; i <= n; i++) facts[a[i]] = 1
      usage["manifest"] = "the one word v1, and is the first line"
      usage["project"] = "one word of 2 to 16 lower-case letters and digits, starting with a letter"
      usage["key-epoch"] = usage["local-epoch"] = "one INTEGER from 1 to 999"
      usage["prune-days"] = "one INTEGER from 1 to 365"
      usage["lock-wait-minutes"] = "one INTEGER from 1 to 240"
      usage["user"] = "one INTEGER from 1000 to 65533"
      usage["main-branch"] = usage["always-on"] = usage["kit-job"] = "one NAME"
      usage["workflow"] = usage["adapter"] = usage["plan-extension"] = usage["signers"] = usage["image"] = "one PATH"
      usage["image-path"] = "one or more PATHs"
      usage["prune-keep-green"] = usage["socket"] = usage["history"] = "one or more job NAMEs"
      usage["refuse-drafts"] = "yes or no"
      usage["weekly-cron"] = "the five fields of a cron schedule"
      usage["check-command"] = "free text"
      usage["job"] = "a NAME and a CLASS: always-on, local, ci-only or content"
      usage["paths"] = usage["escaping-tree"] = "a job NAME and one or more PATHs"
      usage["check-name"] = "a job NAME and one NAME"
      usage["pin"] = "a job NAME and one or more TOOLs"
      usage["count"] = "a job NAME and one or more FIELDs"
      usage["cache"] = "a job NAME and one or more KINDs"
      usage["env"] = "a job NAME and one or more VARs"
      usage["install"] = "a job NAME, a KIND and a DIR PATH"
      usage["service"] = "a job NAME, a KIND, then image <DIGESTED IMAGE> and url-env <VAR> once each and flag <name=value> any number of times"
      usage["pin-source"] = "a TOOL or *, a KIND and a PATH"
      usage["probe"] = "a TOOL, a KIND (version-flag, first-line, after-word WORD or python-minor), an optional in DIR, then an optional BINARY not starting with - and its ARGs"
      usage["not-run-allowed"] = "a LEG and the free text of the criteria it stands for"
      usage["escaping-scan"] = "a KIND and a PATH"
      usage["escaping-read"] = "one ENTRY, job|test file|outside paths, WHOLE-TREE or NONE|why"
      first = 1; nrec = 0; nref = 0
    }
    {
      if (index($0, "\r")) refuse("the line ends in a carriage return, and ci/manifest takes LF line ends.")
      if (NR == 1 && substr($0, 1, 3) == "\357\273\277") refuse("the file starts with a byte order mark, which ci/manifest does not take.")
      if ($0 ~ /^[ \t]*(#|$)/) next
      d = $1
      if (first) {
        first = 0
        if (d != "manifest") refuse("the first directive is " d ", and ci/manifest starts with manifest v1.")
        if (NF == 2 && $2 ~ /^v[0-9]+$/ && $2 != "v1") refuse("the manifest is manifest " $2 ", which this kit (manifest v1) does not read.")
      }
      if (d in reserved) refuse(d " is reserved for a later kit release, so nothing ran.")
      if (!(d in single) && !(d in perjob) && !(d in other)) refuse(d " is not a directive of manifest v1.")
      if (d in single) { if (d in seen) refuse(d " appears twice, and line " seen[d] " has it already."); seen[d] = NR }
      if (!check(d)) refuse(d " takes " usage[d] ".")
      if (d == "job" && ($2 == "image" || $2 == "base")) refuse($2 " is the kit\047s own name, so it cannot name a job.")
      if (d == "pin") for (i = 3; i <= NF; i++) if ($i in facts) refuse($i " is the kit\047s own name, so it cannot name a tool.")
      if ((d == "probe" || d == "pin-source") && ($2 in facts)) refuse($2 " is the kit\047s own name, so it cannot name a tool.")
      if (d == "env") for (i = 3; i <= NF; i++) if (envreserved($i)) refuse("env names " $i ", which the kit reserves, so it is never passed into a job.")
      if (d == "count") for (i = 3; i <= NF; i++) if ($i in facts) refuse($i " is the kit\047s own name, so it cannot name a count.")
      if (d in oncekey) { k = d SUBSEP $2; if (k in once) refuse(d " names " $2 " twice, and line " once[k] " has it already."); once[k] = NR }
      if (d == "job") { if ($2 in jobs) refuse("job " $2 " is declared twice, and line " jobs[$2] " declares it already."); jobs[$2] = NR }
      if (d == "paths") haspaths[$2] = 1
      if (d in perjob) { ref[++nref] = $2; refline[nref] = NR; refdir[nref] = d }
      if (d == "socket" || d == "history") for (i = 2; i <= NF; i++) { ref[++nref] = $i; refline[nref] = NR; refdir[nref] = d }
      if (d == "check-command" || d == "escaping-read") r = d "\t" free
      else if (d == "not-run-allowed") r = d "\t" $2 "\t" free
      else { r = $1; for (i = 2; i <= NF; i++) r = r "\t" $i }
      rec[++nrec] = NR "\t" r
    }
    END {
      if (bad) exit 2
      if (first) refuse_at(NR, "ci/manifest holds no directive, and it starts with manifest v1.")
      for (i = 1; i <= nreq; i++) if (!(req[i] in seen)) refuse_at(NR, "the manifest ends without a " req[i] " line.")
      for (i = 1; i <= nref; i++) if (!(ref[i] in jobs)) refuse_at(refline[i], refdir[i] " names " ref[i] ", which no job line declares.")
      for (i = 1; i <= nrec; i++) {
        split(rec[i], f, "\t")
        if (f[2] == "job" && !(f[3] in haspaths)) refuse_at(f[1], "job " f[3] " has no paths line.")
      }
      for (i = 1; i <= nrec; i++) print rec[i]
    }'
}

# kit__manifest_records <label>: the text on stdin through the parser; the
# numbered records on stdout, or the refusal on stderr and status 2.
kit__manifest_records() {
  local out rc=0
  out="$(kit__manifest_awk "$1")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "${out:-$1: the manifest could not be parsed.}" >&2
    return 2
  fi
  printf '%s\n' "$out"
}

kit__reset() {
  KIT__REC=()
  KIT_JOBS=() KIT_JOB_CLASS=()
  KIT_PROJECT="" KIT_KEY_EPOCH="" KIT_LOCAL_EPOCH="" KIT_MAIN_BRANCH="" KIT_WORKFLOW=""
  KIT_ALWAYS_ON="" KIT_ADAPTER="" KIT_KIT_JOB="" KIT_PLAN_EXTENSION="" KIT_SIGNERS=""
  KIT_CHECK_COMMAND="" KIT_WEEKLY_CRON="" KIT_PRUNE_KEEP_GREEN="" KIT_REFUSE_DRAFTS=""
  KIT_IMAGE="" KIT_IMAGE_PATH="" KIT_LOADED=""
  KIT_PRUNE_DAYS=30 KIT_LOCK_WAIT_MINUTES=30 KIT_USER=1001
}

# kit__manifest_load_text <label> <text>: parse and load. The records stay in
# KIT__REC (one `<line>\t<directive>\t<word>...` each); the singular values
# and the job list are read out once here; per-job values by scan.
kit__manifest_load_text() {
  local tab=$'\t' recs rec body d args name
  recs="$(kit__manifest_records "$1" <<< "$2")" || return 2
  kit__reset
  while IFS= read -r rec; do
    KIT__REC[${#KIT__REC[@]}]="$rec"
    body="${rec#*"$tab"}"
    d="${body%%"$tab"*}"
    args="${body#*"$tab"}"
    case "$d" in
      check-command) KIT_CHECK_COMMAND="$args" ;;
      job)
        name="${args%%"$tab"*}"
        KIT_JOBS[${#KIT_JOBS[@]}]="$name"
        KIT_JOB_CLASS[${#KIT_JOB_CLASS[@]}]="${args#*"$tab"}"
        ;;
      project) KIT_PROJECT="$args" ;;
      key-epoch) KIT_KEY_EPOCH="$args" ;;
      local-epoch) KIT_LOCAL_EPOCH="$args" ;;
      main-branch) KIT_MAIN_BRANCH="$args" ;;
      workflow) KIT_WORKFLOW="$args" ;;
      always-on) KIT_ALWAYS_ON="$args" ;;
      adapter) KIT_ADAPTER="$args" ;;
      kit-job) KIT_KIT_JOB="$args" ;;
      plan-extension) KIT_PLAN_EXTENSION="$args" ;;
      signers) KIT_SIGNERS="$args" ;;
      weekly-cron) KIT_WEEKLY_CRON="${args//"$tab"/ }" ;;
      prune-days) KIT_PRUNE_DAYS="$args" ;;
      prune-keep-green) KIT_PRUNE_KEEP_GREEN="${args//"$tab"/ }" ;;
      lock-wait-minutes) KIT_LOCK_WAIT_MINUTES="$args" ;;
      refuse-drafts) KIT_REFUSE_DRAFTS="$args" ;;
      image) KIT_IMAGE="$args" ;;
      image-path) KIT_IMAGE_PATH="${args//"$tab"/ }" ;;
      user) KIT_USER="$args" ;;
    esac
  done <<< "$recs"
  KIT_LOADED="text:$1"
}

# kit_manifest_load <commit>: <commit>:ci/manifest into the KIT_* values.
# Status 2, with the line and the rule on stderr, on any refusal.
kit_manifest_load() {
  local repo="${KIT_KEYS_REPO:-.}" resolved text
  resolved="$(git -C "$repo" rev-parse --verify -q "${1:-}^{commit}")" \
    || { echo "ci-kit: ${1:-} is not a commit in this repository" >&2; return 2; }
  [ "${KIT_LOADED:-}" = "$resolved" ] && return 0
  text="$(git -C "$repo" show "${resolved}:ci/manifest" 2>/dev/null)" \
    || { echo "ci-kit: ${resolved:0:8} carries no ci/manifest" >&2; return 2; }
  kit__manifest_load_text ci/manifest "$text" || return 2
  KIT_LOADED="$resolved"
}

# kit_manifest_dump <commit>: the validated manifest, one line per directive,
# `<directive>\t<word>...`, free text last and untouched, in file order
# (kit/README.md §3.1). Nothing and status 2 when the manifest is refused.
kit_manifest_dump() (
  tab=$'\t'
  kit_manifest_load "${1:-}" || exit 2
  for rec in ${KIT__REC[@]+"${KIT__REC[@]}"}; do
    printf '%s\n' "${rec#*"$tab"}"
  done
)

# kit__job_words <directive> <job>: the words after the job name of every
# <directive> line naming <job>, space separated on one line.
kit__job_words() {
  local tab=$'\t' rec body out="" lead="$1"$'\t'"$2"$'\t'
  for rec in ${KIT__REC[@]+"${KIT__REC[@]}"}; do
    body="${rec#*"$tab"}"
    case "$body" in
      "$lead"*) body="${body#"$lead"}"; out="${out:+$out }${body//"$tab"/ }" ;;
    esac
  done
  printf '%s\n' "$out"
}

# kit__words <text>: each space-separated word of <text> on its own line,
# never glob-expanded.
kit__words() {
  local w words
  IFS=' ' read -r -a words <<< "$1"
  for w in ${words[@]+"${words[@]}"}; do printf '%s\n' "$w"; done
}

# kit_key_paths <job|image|base>: the ordered path list; status 2 for a name
# with no key. `base` is the kit's base image, keyed on ci/kit/image alone;
# `image` is the job image, ci/kit/image then the image-path PATHs (kit/README.md §3.2).
kit_key_paths() {
  local words
  case "${1:-}" in
    base) printf '%s\n' ci/kit/image ;;
    image)
      [ -n "$KIT_IMAGE_PATH" ] || return 2
      printf '%s\n' ci/kit/image
      kit__words "$KIT_IMAGE_PATH"
      ;;
    *)
      words="$(kit__job_words paths "${1:-}")"
      [ -n "$words" ] || return 2
      kit__words "$words"
      ;;
  esac
}

# sha256 of stdin, hex only, on either coreutils or macOS.
kit__sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

# The object id of one path at a commit, or "absent".
kit__path_oid() {
  local commit="$1" path="$2" oid
  if [ "$path" = "." ]; then
    oid="$(git -C "${KIT_KEYS_REPO:-.}" rev-parse --verify -q "${commit}^{tree}")" || return 1
  else
    oid="$(git -C "${KIT_KEYS_REPO:-.}" rev-parse --verify -q "${commit}:${path}")" || oid=absent
  fi
  printf '%s\n' "$oid"
}

# kit_key <commit> <job|image|base>: the key at that commit, from that
# commit's own manifest. Status 1 when <commit> is not a commit; 2 when the
# commit's manifest is absent or refused, or names no such key. A subshell,
# so a caller's loaded manifest is never replaced.
kit_key() (
  resolved="$(git -C "${KIT_KEYS_REPO:-.}" rev-parse --verify -q "${1:-}^{commit}")" \
    || { echo "ci-kit keys: ${1:-} is not a commit in this repository" >&2; exit 1; }
  kit_manifest_load "$resolved" || { echo "ci-kit keys: no key is defined for ${2:-} at ${resolved:0:8}" >&2; exit 2; }
  paths="$(kit_key_paths "${2:-}")" || { echo "ci-kit keys: no key is defined for job ${2:-}" >&2; exit 2; }
  payload="${KIT_PROJECT}-ci-keys v${KIT_KEY_EPOCH}"$'\n'
  while IFS= read -r path; do
    payload+="${path} $(kit__path_oid "$resolved" "$path")"$'\n'
  done <<< "$paths"
  # The two image keys take the uid the base creates and the job runs as
  # (kit/README.md §3.2): a changed `user` builds new images, never finds old ones.
  case "${2:-}" in image | base) payload+="user ${KIT_USER}"$'\n' ;; esac
  printf '%s' "$payload" | kit__sha256
)

# kit_keys <commit>: `<job> <key>` for every job line, in manifest order.
kit_keys() (
  resolved="$(git -C "${KIT_KEYS_REPO:-.}" rev-parse --verify -q "${1:-}^{commit}")" \
    || { echo "ci-kit keys: ${1:-} is not a commit in this repository" >&2; exit 1; }
  kit_manifest_load "$resolved" || exit 2
  for job in ${KIT_JOBS[@]+"${KIT_JOBS[@]}"}; do
    key="$(kit_key "$resolved" "$job")" || exit $?
    printf '%s %s\n' "$job" "$key"
  done
)

# kit_jobs <class>: the job names of one class, one per line, in order.
kit_jobs() {
  local i
  for ((i = 0; i < ${#KIT_JOBS[@]}; i++)); do
    [ "${KIT_JOB_CLASS[$i]}" = "${1:-}" ] && printf '%s\n' "${KIT_JOBS[$i]}"
  done
  return 0
}

# kit_escaping_reads: the escaping-read entries, one per line, as written
# (`<job>|<test file>|<outside paths, or WHOLE-TREE or NONE>|<why>`).
kit_escaping_reads() {
  local tab=$'\t' rec body
  for rec in ${KIT__REC[@]+"${KIT__REC[@]}"}; do
    body="${rec#*"$tab"}"
    case "$body" in
      "escaping-read$tab"*) printf '%s\n' "${body#escaping-read"$tab"}" ;;
    esac
  done
}

# The pin tools and the count fields of a job (the `pin` and `count` lines),
# space separated on one line; an empty line for a job with none.
kit_pin_tools() { kit__job_words pin "${1:-}"; }
kit_count_fields() { kit__job_words count "${1:-}"; }

# kit_pin_at <commit> <tool>: the tool's pin AT THAT COMMIT, read as data by
# the kind its `pin-source` line names (the exact tool's line, else `*`'s) in
# that commit's manifest, and never executed. Empty when the commit pins no
# such tool.
kit_pin_at() (
  tab=$'\t' repo="${KIT_KEYS_REPO:-.}" tool="${2:-}" kind="" path=""
  kit_manifest_load "${1:-}" 2>/dev/null || exit 0
  for want in "$tool" "*"; do
    for rec in ${KIT__REC[@]+"${KIT__REC[@]}"}; do
      body="${rec#*"$tab"}"
      case "$body" in
        "pin-source$tab$want$tab"*)
          body="${body#"pin-source$tab$want$tab"}"
          kind="${body%%"$tab"*}" path="${body#*"$tab"}"
          break 2
          ;;
      esac
    done
  done
  [ -n "$path" ] || exit 0
  text="$(git -C "$repo" show "${KIT_LOADED}:${path}" 2>/dev/null)" || text=""
  case "$kind" in
    toolchain-line) awk '$1 == "toolchain" { print $2; exit }' <<< "$text" ;;
    first-line) awk 'NR == 1 { gsub(/[[:space:]]/, ""); print; exit }' <<< "$text" ;;
    readonly-version)
      LC_ALL=C awk -v t="$tool" '
        BEGIN { n = toupper(t); gsub(/-/, "_", n); p = "readonly " n "_VERSION=" }
        index($0, p) == 1 { v = substr($0, length(p) + 1); if (v != "" && v !~ /[[:space:]]/) { print v; exit } }' <<< "$text"
      ;;
  esac
)

# --- THE TRUST IN A RECORD (runner only, inside the plan) -----------------

# kit_record_trusted <owner/name> <sha> <job> <key> [<check name>] [<ref>]:
# true when the record of <job> under <key>, pointing at <sha>, may be
# believed (DESIGN.md 5.4). The check name defaults to <job>.
#
#   1. THE KEY IS RECOMPUTED: kit_key(<sha>, <job>) equals <key>, the key in
#      the ref's name. <sha> must be in the local repository; the caller
#      fetches it first.
#   2. <sha> carries a SUCCESSFUL check run named <check name> from the
#      github-actions app, through `gh api` with a token holding checks: read.
#
# Returns 0 trusted; 2 when the key differs or cannot be computed; 1 when the
# check-run test fails, an unreadable API included. False on any doubt.
#
# THE LOCAL ARM (DESIGN.md 6.7). A sixth argument under refs/ci/local/ (the
# namespace, never the object's type) selects it: <sha> is then the object the
# ref names, and the test is kit_local_record_trusted's six conditions.
# Returns 0 trusted, 4 not; KIT_LOCAL_REASON and KIT_LOCAL_PRINCIPAL say why
# and who.
#
# THE CI ARM (DESIGN.md 5.4) takes both shapes of green record: <sha> is a
# commit (a lightweight record, written before v1.2.0) or a tag object of one
# (its message the facts block, DESIGN.md 5.2). Either is peeled to its
# commit, the key is recomputed on the commit and the check run is looked up
# on the commit. A tag object's facts must also agree (kit__green_facts),
# else 3 with KIT_RECORD_REASON one clause for the plan's sentence.
#
# KIT_RECORD_PLATFORM: on a trusted record, the platform its facts name (a
# local record's, or a tag-object green record's); empty for a lightweight
# record and on every refusal.
kit_record_trusted() {
  local repo="$1" sha="$2" job="$3" key="${4:-}" check="${5:-$3}" actual count commit
  KIT_RECORD_PLATFORM="" KIT_RECORD_REASON=""
  if [[ "${6:-}" == refs/ci/local/* ]]; then
    kit_local_record_trusted "$sha" "$job" "$key" "$6"
    return
  fi
  [[ "$key" =~ ^[0-9a-f]{64}$ ]] || return 2
  commit="$(git -C "${KIT_KEYS_REPO:-.}" rev-parse --verify -q "${sha}^{commit}" 2>/dev/null)" || return 2
  actual="$(kit_key "$commit" "$job" 2>/dev/null)" || return 2
  [ "$actual" = "$key" ] || return 2
  if [ "$(git -C "${KIT_KEYS_REPO:-.}" cat-file -t "$sha" 2>/dev/null)" = tag ]; then
    kit__green_facts "$sha" "$job" "$key" "$commit" || return 3
  fi
  [ -n "$repo" ] || { KIT_RECORD_PLATFORM=""; return 1; }
  count="$(gh api "repos/${repo}/commits/${commit}/check-runs?check_name=${check}&filter=all&per_page=100" \
    --jq '[.check_runs[] | select(.conclusion == "success" and .app.slug == "github-actions")] | length' 2>/dev/null)" \
    || { KIT_RECORD_PLATFORM=""; return 1; }
  [ "${count:-0}" -gt 0 ] || { KIT_RECORD_PLATFORM=""; return 1; }
}

# kit__green_facts <tag object> <job> <key> <commit>: 0 when the tag names
# <commit> directly and its facts block agrees with its ref, KIT_RECORD_PLATFORM
# then set; else non-zero with KIT_RECORD_REASON. The facts: the first line
# `<project>-green v1`; `job`, `key` and `commit` the ref's job, the ref's key
# and the peeled commit; for a `local` job, whose verdict runs in the job
# image, a `platform` of linux/amd64 or linux/arm64 and an `image` id; for any
# other job, a `platform` of KIT_PLATFORM_SHAPE. A `platform` line absent or
# given twice is no platform.
kit__green_facts() {
  local obj="$1" job="$2" key="$3" commit="$4" raw header facts value class="" i
  local format
  # The loaded manifest's project and job classes, as the local arm reads
  # them; a caller that loaded none gets the record commit's.
  [ -n "${KIT_PROJECT:-}" ] || kit_manifest_load "$commit" 2>/dev/null \
    || { KIT_RECORD_REASON="the ci/manifest of its commit could not be read"; return 1; }
  format="${KIT_PROJECT}-green v1"
  raw="$(git -C "${KIT_KEYS_REPO:-.}" cat-file tag "$obj" 2>/dev/null)" || { KIT_RECORD_REASON='its tag object could not be read'; return 1; }
  header="$(sed '/^$/q' <<< "$raw")"
  facts="$(sed '1,/^$/d' <<< "$raw")"
  if [ "$(awk '$1 == "type" { print $2; exit }' <<< "$header")" != commit ] \
      || [ "$(awk '$1 == "object" { print $2; exit }' <<< "$header")" != "$commit" ]; then
    KIT_RECORD_REASON='it is a tag that does not point at a commit'; return 1
  fi
  if [ "$(awk 'NR == 1' <<< "$facts")" != "$format" ]; then
    KIT_RECORD_REASON="its facts are not in the ${format} format"; return 1
  fi
  if [ "$(kit__local_fact "$facts" job)" != "$job" ] || [ "$(kit__local_fact "$facts" key)" != "$key" ] \
      || [ "$(kit__local_fact "$facts" commit)" != "$commit" ]; then
    KIT_RECORD_REASON="its facts' job, key or commit differ from its ref and its commit"; return 1
  fi
  for ((i = 0; i < ${#KIT_JOBS[@]}; i++)); do
    [ "${KIT_JOBS[$i]}" = "$job" ] && class="${KIT_JOB_CLASS[$i]}"
  done
  value="$(kit__local_fact "$facts" platform)" || value=""
  if [ "$class" = local ]; then
    case "$value" in
      linux/amd64 | linux/arm64) ;;
      "") KIT_RECORD_REASON='it records no platform'; return 1 ;;
      *) KIT_RECORD_REASON="it records the platform ${value}, and a local job's verdict runs in its image on linux/amd64 or linux/arm64"; return 1 ;;
    esac
    if ! [[ "$(kit__local_fact "$facts" image)" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      KIT_RECORD_REASON='it records no image id of the job image'; return 1
    fi
  elif [ -z "$value" ]; then
    KIT_RECORD_REASON='it records no platform'; return 1
  elif ! [[ "$value" =~ $KIT_PLATFORM_SHAPE ]]; then
    KIT_RECORD_REASON="it records the platform ${value}, which is not of the shape <os>/<arch>"; return 1
  fi
  KIT_RECORD_PLATFORM="$value"
}

# --- LOCAL RECORDS (DESIGN.md 6.5 to 6.7) ----------------------------------
#
# A local record is a signed annotated tag object under
# refs/ci/local/<job>/<key>, written by a workstation after that job's verdict
# exited 0 there; its message is the facts block. It proves that the holder of
# a key in main's signers file asserted the tree passed, not that the tests
# ran (the residual, DESIGN.md 3.4).
#
# THE TRUST INPUTS COME FROM MAIN'S TIP, refs/remotes/origin/<main-branch>
# (DESIGN.md §6.7): the signers file at the path the loaded manifest's
# `signers` names, and the `not-run-allowed` legs of main's own ci/manifest,
# NEVER the tree under test: a branch that added its own key would otherwise
# vouch for itself. The job lists, the pin tools and the count fields are the
# loaded manifest's (the plan loads the commit under test's), as DESIGN.md §6.7 rules.

# kit__local_fact <facts> <name>: the value of the one `<name> <value>` line;
# non-zero when the line is absent or appears more than once.
kit__local_fact() {
  awk -v n="$2" 'index($0, n " ") == 1 { c++; v = substr($0, length(n) + 2) } END { if (c != 1) exit 1; print v }' <<< "$1"
}

# kit__local_allowed: the LEG of each `not-run-allowed` line of main's
# ci/manifest, one per line, through the one parser; nothing when main's
# manifest is absent or refused.
kit__local_allowed() (
  tab=$'\t'
  text="$(git -C "${KIT_KEYS_REPO:-.}" show "refs/remotes/origin/${KIT_MAIN_BRANCH}:ci/manifest" 2>/dev/null)" || exit 0
  recs="$(kit__manifest_records ci/manifest <<< "$text" 2>/dev/null)" || exit 0
  while IFS= read -r rec; do
    body="${rec#*"$tab"}"
    case "$body" in
      "not-run-allowed$tab"*) body="${body#not-run-allowed"$tab"}"; printf '%s\n' "${body%%"$tab"*}" ;;
    esac
  done <<< "$recs"
)

kit__local_no() { KIT_LOCAL_REASON="$1"; }

# kit__local_signers_one_line_per_key: 0 when the allowed-signers text on
# stdin names each public key on one line at most. A key is its type and its
# base64 blob: the first field after the principals that is an SSH public key
# type, and the field after it; blank lines and comments name none.
kit__local_signers_one_line_per_key() {
  awk '
    /^[[:space:]]*(#|$)/ { next }
    {
      for (i = 2; i < NF; i++) {
        if ($i ~ /^(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)$/) {
          k = $i " " $(i + 1); if (seen[k]++) bad = 1; break
        }
      }
    }
    END { exit bad }'
}

# kit__local_check <dir> <object> <job> <key>: the six conditions, in a
# scratch directory the caller removes. Returns 0, or 4 with KIT_LOCAL_REASON.
kit__local_check() {
  local dir="$1" obj="$2" job="$3" key="$4" repo="${KIT_KEYS_REPO:-.}"
  local main="refs/remotes/origin/${KIT_MAIN_BRANCH}" signers="$KIT_SIGNERS"
  local format="${KIT_PROJECT}-local-ci v${KIT_LOCAL_EPOCH}"
  local header facts commit principals principal n tool field value pin legs leg allowed actual platform
  # 6. Neither a force nor a weekly dispatch.
  if [ "${CI_PLAN_FORCE:-false}" = true ]; then kit__local_no 'is ignored on a force dispatch'; return 4; fi
  if [ "${CI_PLAN_TASK:-}" = weekly ]; then kit__local_no 'is ignored on a weekly dispatch'; return 4; fi
  # 1. A tag object whose SSH signature verifies against main's signers, in
  #    namespace git, with exactly one principal matching.
  if [ "$(git -C "$repo" cat-file -t "$obj" 2>/dev/null)" != tag ]; then
    kit__local_no 'is not a signed tag object'; return 4
  fi
  git -C "$repo" cat-file tag "$obj" > "$dir/raw" 2>/dev/null || { kit__local_no 'could not be read'; return 4; }
  sed -n '/^-----BEGIN SSH SIGNATURE-----$/,/^-----END SSH SIGNATURE-----$/p' "$dir/raw" > "$dir/sig"
  sed '/^-----BEGIN SSH SIGNATURE-----$/,$d' "$dir/raw" > "$dir/payload"
  if ! [ -s "$dir/sig" ]; then kit__local_no 'is a tag with no SSH signature'; return 4; fi
  if [ -z "$signers" ] || ! git -C "$repo" show "${main}:${signers}" > "$dir/signers" 2>/dev/null; then
    kit__local_no "cannot be checked, because main carries no ${signers}"; return 4
  fi
  # One line per key: find-principals prints only the first matching line's
  # principal, so a key named twice would be attributed by line order; such a
  # file vouches for no record.
  if ! kit__local_signers_one_line_per_key < "$dir/signers"; then
    kit__local_no "cannot be checked, because main's allowed signers names one key on more than one line"; return 4
  fi
  principals="$(ssh-keygen -Y find-principals -s "$dir/sig" -f "$dir/signers" 2>/dev/null)" || principals=""
  n="$(grep -c . <<< "$principals" || true)"
  if [ "$n" -eq 0 ]; then kit__local_no "is signed by a key that is not in main's allowed signers"; return 4; fi
  if [ "$n" -gt 1 ]; then kit__local_no "is signed by a key that more than one of main's allowed signers names"; return 4; fi
  principal="$principals"
  if ! ssh-keygen -Y verify -f "$dir/signers" -I "$principal" -n git -s "$dir/sig" < "$dir/payload" > /dev/null 2>&1; then
    kit__local_no "carries a signature that does not verify against main's allowed signers"; return 4
  fi
  # 2. The key recomputes from the tag's commit, and the facts' job, key and
  #    commit are the ref's job, the ref's key and that commit.
  header="$(sed '/^$/q' "$dir/payload")"
  facts="$(sed '1,/^$/d' "$dir/payload")"
  commit="$(awk '$1 == "object" { print $2; exit }' <<< "$header")"
  if [ "$(awk '$1 == "type" { print $2; exit }' <<< "$header")" != commit ] || ! [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then
    kit__local_no 'does not point at a commit'; return 4
  fi
  # The format, the platform and the image: a record in any other format, or
  # one whose platform is not Linux, was not made in the job image.
  value="$(awk 'NR == 1' <<< "$facts")"
  if [ "$value" != "$format" ]; then
    kit__local_no "is not in the ${format} format"; return 4
  fi
  value="$(kit__local_fact "$facts" platform)" || value=""
  platform="$value"
  case "$value" in
    linux/amd64 | linux/arm64) ;;
    linux/*) kit__local_no "records the platform ${value}, which is neither linux/amd64 nor linux/arm64"; return 4 ;;
    *) kit__local_no 'was made outside the job image'; return 4 ;;
  esac
  value="$(kit__local_fact "$facts" image)" || value=""
  if ! [[ "$value" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    kit__local_no 'records no image id of the job image'; return 4
  fi
  actual="$(kit_key "$commit" "$job" 2>/dev/null)" || actual=""
  if [ "$actual" != "$key" ]; then
    kit__local_no "names a key that its commit ${commit:0:8} does not recompute to"; return 4
  fi
  if [ "$(kit__local_fact "$facts" job)" != "$job" ] || [ "$(kit__local_fact "$facts" key)" != "$key" ] \
      || [ "$(kit__local_fact "$facts" commit)" != "$commit" ]; then
    kit__local_no 'carries facts whose job, key or commit differ from its ref and its commit'; return 4
  fi
  # 3. Each pin line equals the pin at that commit (one leading v dropped
  #    from each side, as the tools print it both ways).
  for tool in $(kit_pin_tools "$job"); do
    value="$(kit__local_fact "$facts" "$tool")" || { kit__local_no "records no single ${tool} version"; return 4; }
    pin="$(kit_pin_at "$commit" "$tool")"
    if [ -z "$pin" ]; then kit__local_no "names a commit that pins no ${tool}"; return 4; fi
    if [ "${value#v}" != "${pin#v}" ]; then
      kit__local_no "records ${tool} ${value} where its commit pins ${pin}"; return 4
    fi
  done
  # 4. Each count is present and above zero.
  for field in $(kit_count_fields "$job"); do
    value="$(kit__local_fact "$facts" "$field")" || { kit__local_no "records no single ${field} count"; return 4; }
    if ! [[ "$value" =~ ^[0-9]{1,9}$ ]] || [ "$value" -le 0 ]; then
      kit__local_no "records ${field} ${value}, which is not above zero"; return 4
    fi
  done
  # 5. Every not_run leg is a not-run-allowed leg of main's ci/manifest.
  legs="$(awk '$1 == "not_run" { sub(/^not_run[[:space:]]*/, ""); print }' <<< "$facts")"
  if [ -n "$legs" ]; then
    allowed="$(kit__local_allowed)"
    while IFS= read -r leg; do
      if [ -z "$leg" ] || ! grep -qxF -- "$leg" <<< "$allowed"; then
        kit__local_no "skips ${leg:-an unnamed leg}, which main's ci/manifest does not name"; return 4
      fi
    done <<< "$legs"
  fi
  KIT_LOCAL_PRINCIPAL="$principal"
  KIT_RECORD_PLATFORM="$platform"
  return 0
}

# kit_local_record_trusted <object> <job> <key> <ref>: 0 when the local
# record <ref> (naming <object>) may be believed for <job> under <key>, else 4
# with KIT_LOCAL_REASON one predicate for the plan's sentence ("<job>: the
# local record for <key8> <reason>, so <job> ran."); KIT_LOCAL_PRINCIPAL is
# the signer's principal when trusted. The object, the tag's commit and main's
# tip must be in the local repository; the caller fetches them first. Needs
# git and ssh-keygen; no API call.
kit_local_record_trusted() {
  local obj="$1" job="$2" key="$3" ref="$4" dir rc=0 class="" i
  KIT_LOCAL_REASON="" KIT_LOCAL_PRINCIPAL="" KIT_RECORD_PLATFORM=""
  for ((i = 0; i < ${#KIT_JOBS[@]}; i++)); do
    [ "${KIT_JOBS[$i]}" = "$job" ] && class="${KIT_JOB_CLASS[$i]}"
  done
  case "$class" in
    local) ;;
    ci-only) kit__local_no 'is for a job that records only in CI'; return 4 ;;
    *) kit__local_no "names ${job}, which no local record may vouch for"; return 4 ;;
  esac
  if ! [[ "$key" =~ ^[0-9a-f]{64}$ ]] || [ "$ref" != "refs/ci/local/${job}/${key}" ]; then
    kit__local_no "is not at refs/ci/local/${job}/<its key>"; return 4
  fi
  dir="$(mktemp -d)" || { kit__local_no 'could not be checked (no scratch directory)'; return 4; }
  kit__local_check "$dir" "$obj" "$job" "$key" || rc=$?
  rm -rf "$dir"
  return "$rc"
}
