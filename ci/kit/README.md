# The kit: command and manifest reference

This directory is what you vendor, byte for byte, at `ci/kit/`, using `kit-update <tag>` from a signed release (§5.3). Don't edit anything in it: the manifest check (§3.7, rule 7) compares `ci/kit` with the tree hash recorded in `ci/KIT-VERSION` and fails if they differ.

This document is the reference for the kit's commands, the manifest, the test script's contract, vendoring and versions, the kit's own tests and the adoption procedure. The design, the trust model and every invariant with its reason are in the kit repository's `DESIGN.md`, cited below as "DESIGN §x". The "In the example" columns give the values chosen by the example adopter, [`quokka-ci-kit-example`](https://github.com/aames/quokka-ci-kit-example): the project `rottnest`, which records quokka sightings on Rottnest Island, with a Go API (`api`) tested against Postgres and a web front end (`web`) tested with vitest.

## 1. Commands

The commands that run on a workstation work under bash 3.2 or later (the macOS system bash is enough) and need only Docker, git 2.34 or later, `ssh-keygen -Y` (`check-prereqs` checks those) and the standard Unix tools. The commands that run on the CI runner need bash 4.2 or later. The two Python checks need `python3` (the workflow check also needs PyYAML) and run under any bash, in CI and on a workstation. The generator `bin/kit-init` needs `python3` 3.9 or later and its standard library only, and is run once, by hand, when you adopt the kit. Every path below is as vendored, under `ci/kit/`.

| Command | Where | Usage | What it does |
|---|---|---|---|
| `bin/keys` | host, runner | `keys <commit> [<job>]`; `keys dump <commit>` | prints every `<job> <key>` in manifest order, or one key (`<job>` may be `image` or `base`); `dump` prints the validated manifest as data, one line per directive, `<directive>\t<word>...` |
| `bin/check-manifest` | host, runner | `check-manifest [--commit <rev>] [--file <path>] [--no-vendor-check]` | the twelve rules of the manifest check (§3.7); exit 1 on a finding, 2 when the manifest cannot be parsed |
| `bin/check-prereqs` | host | `check-prereqs` | checks that Docker answers, git is 2.34 or later, `ssh-keygen -Y find-principals` exists and bash is 3.2 or later; exit 2, naming each that fails |
| `bin/container` | host, runner | `container image --commit <sha> [<job>]`; `container run --commit <sha> <job>`; `container versions --commit <sha> <job>...` | builds or finds the base and job images keyed on the commit (with `<job>`, only the image that job runs in: the base for the kit job); runs one job's tests in its container with the services, socket, caches and environment the manifest lists; reads the pinned tools' versions in the image. After tests that exit 0, `run` reads the image's platform inside it and writes the ran file `<git common dir>/<project>-ci/ran/<job>/<key>` (`platform <os/arch>`, `image <id>`) that `bin/record` reads. Every container of a job's image runs with `--security-opt no-new-privileges`, `--cap-drop ALL` and `--user`; only the service sidecar runs without them |
| `bin/local-ci` | host | `local-ci run --commit <rev> <job>...`; `local-ci sign --commit <rev> <job>...`; `local-ci push [--remote <name>] --commit <rev> <job>...` | runs the local jobs through the launcher and keeps the passing entries; signs a passing entry as a local record; pushes the records |
| `bin/pre-push` | host | called by your `.githooks/pre-push` shim with git's hook arguments | runs, signs and pushes each pushed commit's local jobs whose keys have no record yet |
| `hooks/pre-push.shim` | host | copied to `.githooks/pre-push` byte for byte | the three-line shim that runs the working copy's `bin/pre-push` (§2.4) |
| `bin/kit-update` | host, from a checkout of main | `kit-update <tag> [--verify-only] [<url>]` (`--verify-only` may come before or after the tag) | clones the kit in full, accepts the tag only if it is a release (§5.3), replaces `ci/kit/` with the tag's `kit/` tree and writes `ci/KIT-VERSION`; `--verify-only` prints the five lines and changes nothing |
| `bin/check-adapter` | host | `check-adapter <job>` | the contract check of §4.5 (a) and (b) for a real test script |
| `bin/kit-init` | host, once, at adoption | `python3 ci/kit/bin/kit-init --project NAME [--go DIR[:JOB]]... [--node DIR[:JOB]]... [--python DIR[:JOB]]... [--postgres JOB[:MAJOR]]... [--signer auto\|FILE] [--cron 'M H D M W'] [--checksums FILE] [--no-commit] [--no-agent-files]`; `python3 ci/kit/bin/kit-init --agent-files-only` | writes an adopter's files from `templates/` (the manifest, the test script, the job image's Dockerfile with both architectures' checksums, the workflow, `.githooks/pre-push` copied from `hooks/pre-push.shim`, the Makefile's `check` target, the signers file holding only its comment line, and the kit's section in `AGENTS.md` and `CLAUDE.md`), commits exactly those paths on the landing branch (together with `ci/kit/`, `ci/KIT-VERSION` and `ci/KIT-SIGNERS` if the vendoring is uncommitted), then runs `check-manifest`, both Python checks and `check-prereqs`. Go, Node with vitest and a lockfile, and Python with pytest in a requirements file carrying `--hash=` lines are written in full; any other test runner gets a stub section that refuses to run. `--signer` prints the signer's line and fingerprint and keeps the line in `<git common dir>/<project>-ci/init/allowed-signers.next`, never in the landing commit. It writes no file through a symbolic link, and puts no directory or file name into a generated file other than letters, digits and `. _ / -`. Exit 0: written, and every check passed. Exit 1: written, and a check found something or the commit failed. Exit 2: refused, nothing written. Exit 3: written, no check found anything, but a check did not run, and the output says which and how to run it (the kit repository's `docs/kit-init.md`) |
| `bin/plan` | runner | `bash ci/kit/bin/plan` with `CI_PLAN_SHA`, `CI_PLAN_EVENT`, `CI_PLAN_FORCE`, `CI_PLAN_TASK`, `CI_PLAN_REPO`, `GH_TOKEN` (and `CI_PLAN_REMOTE`, default `origin`; the local side reads `main`'s tip as `refs/remotes/origin/<main-branch>` whatever it says, so keep the remote named `origin`) | the always-on job's plan: one key per job, the records found and checked, one decision per job as a step output (`<job>`, `<job>_key`, `<job>_platform`, `main`, `ref_group`), the plan extension sourced afterwards, and the summary table (`Job`, `Key`, `Record`, `Platform`, `Provenance`, `Decision`) |
| `bin/record` | runner | `bash ci/kit/bin/record <job> <key> <sha>` with `GITHUB_TOKEN`, `GITHUB_REPOSITORY` | the one writer of `refs/ci/green/<job>/<key>`, a job's last step; `<job>` must be a `job` line of `<sha>`'s manifest. It writes an unsigned tag object of `<sha>` whose message is the green facts block (DESIGN §5.2: the job, key and commit, the `platform` and `image` from the launcher's ran file for a `local` job or the runner's for any other, the runner's `host`, the run and the workflow ref), then the ref pointing at it; exit 2, nothing written, when a `local` job has no ran file |
| `bin/prune` | runner | `bash ci/kit/bin/prune <green\|local> <main tip> <true\|false>` (remote `CIKIT_REMOTE`, default `origin`) | deletes records older than `prune-days`, except the main tip's keys for `prune-keep-green` (green) or the `local` jobs (local); a dry run unless the third word is `true`; run it from a job of your own (§5.5) |
| `bin/check-workflow` | runner, host | `python3 ci/kit/bin/check-workflow [--root <dir>] [--manifest-file <path>]`; `python3 ci/kit/bin/check-workflow --fixture <dir> [--manifest-file <path>]` | the workflow check: rules W-1 to W-12 (§2.3) over the manifest's `workflow` (`--manifest-file` reads a working-tree manifest through the same parser instead of `keys dump HEAD`); `--fixture` requires each `green*.yml` to pass and each `red-w<N>-*.yml` to fail on W-N. Needs `python3` with PyYAML; the kit's own workflow installs Ubuntu's `python3-yaml` when the runner lacks it (`python3 -c 'import yaml' \|\| sudo apt-get install -y python3-yaml`) |
| `bin/check-escaping-reads` | runner, host | `python3 ci/kit/bin/check-escaping-reads [--root <dir>] [--manifest-file <path>]` | the escaping-read check over the manifest's `escaping-tree`, `escaping-scan` and `escaping-read` lines, read through `bin/keys dump HEAD` |
| `bin/check-host` | runner | `python3 ci/kit/bin/check-host <dir>` | the kit's check on its own host files: the host allow-list and the bash 3.2 constructs (§2.2) |
| `tests/run` | runner, kit job | `bash ci/kit/tests/run` | the kit's tests that need no Docker daemon; ends with the counts line |
| `tests/image` | where a socket is held | `bash ci/kit/tests/image [--family <name>]...` | the base image's build test, the entry script's tree-in cases, the job hardening, the kit job in the base, and `kit-init`'s two end-to-end shapes (`initgo`: Go, Node and Postgres; `initpy`: Python with pytest), each generated, built and run through `make check` and `check-adapter` |

The library, `lib/keys.sh`, is sourced by the plan and read in a child shell under `"$BASH"` by every host reader; its interface is §2.1. The names it derives from your project are in §3.5.

## 2. The boundary

### 2.1 What the kit owns, what you write, and the interfaces between them

| The kit owns (identical in every adopter, changed only by a release) | You write (your own, reviewed in your own pull requests) |
|---|---|
| `ci/kit/` as a whole: the key formula, the record namespaces `refs/ci/green/<job>/<key>` and `refs/ci/local/<job>/<key>`, the trust check with both sides, the plan's decisions for the jobs the manifest lists, the summary table, the record writer, the prune | `ci/manifest`: jobs, classes, paths, pins and where they are read from, probes, counts, services, sockets, caches, environment names, history jobs, the image and its inputs, the signers path, the allow-list, the escaping-read census |
| the launcher's flags per job class; the base image; the entry script's tree-in, pack-in and install kinds; the in-image version reader composed from `probe` lines | `ci/image/Dockerfile`: the toolchain layer `FROM ${CIKIT_BASE}`, every tool at a pin a `pin-source` kind can read, `PATH` set so that the test script's refusals find each tool |
| the driver (`run`, `sign`, `push`), the lock, the facts block and its format line, the passing-entry cache | the adapter: one test script, one section per job, the counts line, the refusals (§4.1); a `ci-only` section the driver refuses and CI runs |
| the hook's logic | `.githooks/` as a directory, holding the shim and any other hooks of yours |
| `kit-update`, `check-manifest`, `check-prereqs`, `check-adapter`, `check-workflow`, `check-escaping-reads`, `check-host`; the generator `kit-init` and its `templates/`, whose output is yours once written | the workflow YAML: the always-on job's own guards and the check steps, each job's YAML around the kit's steps (W-7), timeouts, permissions |
| the kit's tests (`tests/run`, `tests/image`) | the plan extension for jobs outside the scheme (§4.4); your own checks, harnesses and planted failures (§6.3); the trust paragraph in your own documentation (DESIGN §3.4); the contents of `ci/allowed-signers` and `ci/KIT-SIGNERS` |

**Why the manifest is a separate data file and the kit a vendored copy.** The code that decides whether a job may be skipped has to be reviewed in the adopting project's own pull requests, so the kit is vendored by signed release and never fetched at run time. And a project's values cannot live in a library several projects share, so they live in a manifest that every reader takes from the commit under test, as data.

**The kit's constants**, named once: the paths `ci/kit`, `ci/manifest`, `ci/KIT-VERSION`, `ci/KIT-SIGNERS` (fixed, because every reader must find the library before it can read anything else); the image entry `/usr/local/bin/cikit-enter`; the image label `io.github.aames.quokka-ci-kit.image-key`; the build arguments `CIKIT_BASE`, `CIKIT_INPUTS_HASH`, `CIKIT_UID`; the container environment `CIKIT_TREE`, `CIKIT_JOB`, `CIKIT_COMMIT`, `CIKIT_PROJECT`, `CIKIT_ADAPTER`, `CIKIT_INSTALL`, `GITHUB_ACTIONS`; the host environment `CIKIT_IMAGE_CACHE`, `CIKIT_LOCK_WAIT_S`, `CIKIT_LOCK_TICK_S`, `CIKIT_REMOTE` (the driver's and the prune's remote, default `origin`); the plan's `CI_PLAN_*`; the three GitHub push prefixes and the `github-actions` application slug; the synthetic commit's identity `cikit <cikit@invalid>` at `2000-01-01T00:00:00Z`; the base image's user name `ci` and home `/home/ci`; the cache targets `/home/ci/go/pkg/mod` (`gomod`), `/home/ci/.cache/go-build` (`gobuild`), `/home/ci/.npm` (`npm`). The kit's functions are `kit_*` and `kit__*`, its variables `KIT_*`, its environment `CIKIT_*`, so a plan extension that sources another library in the same shell never shares a name with it.

**The library's interface** (`lib/keys.sh`, bash 3.2-clean, sourced by the plan on the runner and read in a child shell by the driver, the hook and the launcher on the host; DESIGN §5.1a):

```
kit_manifest_load <commit>                 reads <commit>:ci/manifest into KIT_* variables; exit 2 with the line and rule on a refusal
kit_manifest_dump <commit>                 the validated dump (§3.1)
kit_key <commit> <job|image|base>          the key; 1 when <commit> is not a commit, 2 when <job> has no key
kit_keys <commit>                          `<job> <key>` per job line, in manifest order
kit_key_paths <job|image|base>             the ordered path list
kit_pin_tools <job>  kit_count_fields <job>  kit_pin_at <commit> <tool>   (the `pin`, `count` and `pin-source` lines)
kit_jobs <class>                           the job names of one class, in order
kit_escaping_reads                         the `escaping-read` entries, one per line, bar-separated
kit_record_trusted <owner/name> <sha> <job> <key> [<check name>] [<ref>]   0 trusted; 1 check-run test failed; 2 key differs; 3 a green tag object's facts disagree (KIT_RECORD_REASON set); 4 local side refused (KIT_LOCAL_REASON, KIT_LOCAL_PRINCIPAL set); on 0, KIT_RECORD_PLATFORM is the record's platform (empty for a lightweight green record)
kit_local_record_trusted <object> <job> <key> <ref>
kit_platform_of <uname -s> <uname -m>      `<os>/<arch>`, the system lower-cased, x86_64 as amd64, aarch64 as arm64: the one function that computes every record's platform; 1 and nothing printed on an empty word; its shape is `KIT_PLATFORM_SHAPE`
```

Everything is derived from `project` by §3.5. `KIT_KEYS_REPO` names the repository every function reads (the working directory when unset). Four facts about the interface: (1) the local side reads `main-branch` and `signers` from the manifest the caller last loaded, which is the record's commit's, so a caller loads the commit before it asks; on a pull-request run the branch's plan decides anyway, and on `main`'s push run the manifest is `main`'s own. (2) `kit__manifest_records <label>` (manifest text on stdin) is how the driver and the hook read the **working copy's** manifest; it stays private, and the `kit_*` names are the ones your extension may call. (3) The host allow-list that `bin/check-host` enforces is §2.2's. (4) The reserved environment names of §3.3's `env` are one constant in `lib/keys.sh` (`kit_env_reserved`), read by the parser and by the launcher's own refusal, so the two cannot drift apart.

**The plan extension's interface** (§4.4; bash 4.2 or later, runner only): the extension is sourced after every kit decision with `KIT_MODE` (`normal`, `force`, `weekly`, `task:<name>`), `KIT_MAIN` (`true` or `false`), `KIT_REF_GROUP`, `KIT_SHA`, and the associative arrays `KIT_KEY`, `KIT_DECISION`, `KIT_NOTE`, `KIT_PROVENANCE` in scope. It may call `kit_decide <job> <decision> <note> [<provenance>]` for a job name the manifest does not declare, `kit_output <name> <value>` (never a kit name: `<job>`, `<job>_key`, `<job>_platform`, `main`, `ref_group`), and `kit_summary_row <job> <key or -> <note> <provenance> <decision>` (its Platform cell is `-`).

### 2.2 The host side: shells and the allow-list

The commands that run on a workstation (`bin/local-ci`, `bin/pre-push`, `bin/container`, `bin/keys` when the hook calls it, `bin/kit-update`, `bin/check-prereqs`, and the functions of `lib/keys.sh` they call) are written for bash 3.2, the macOS `/bin/bash`, and run under 3.2 or later: the hook shim and a Makefile's `bash` both take whichever `bash` is first on `PATH` (a Homebrew bash 5, say), and the scripts behave the same under it. They call only this allow-list of host commands: `git`, `docker`, `mkdir`, `mv`, `rm`, `mktemp`, `cat`, `date`, `uname`, `sleep`, `kill`, `tail`, `head`, `tr`, `wc`, `shasum` or `sha256sum`, and `ssh-keygen`; the host-side functions of `lib/keys.sh` also call `awk` and `cut`, and the shim runs `bash`. No host tool parses any output: bash's own `[[ =~ ]]`, `case` and `read` do that, and anything that needs a real parser is parsed inside the job image. If a BSD and a GNU version of one of the library's host tools disagreed, the result would be a key that matches no record, so the job would run; never a pass.

The commands that run only on the CI runner (`bin/plan`, `bin/record`, `bin/prune`) need bash 4.2 or later and refuse anything older in one sentence. The two Python checks need `python3`, the workflow check with PyYAML, and run under any bash: in CI, and on a workstation when you run them by hand. `bin/kit-init`, the generator you run once at adoption, sits beside them on the same terms, outside `check-host`'s file list: it is Python, not a host bash command, so the allow-list above does not apply to it. Instead its source parses as Python 3.9, it imports the standard library only, and its subprocesses are a closed set (`git`, `docker` for the Postgres digest, `ssh-keygen` for a signer's fingerprint, `bash` for `check-manifest` and `check-prereqs`, and its own `python3` for the two Python checks), each called with an argument list, never through a shell. Its own `python3` always runs in isolated mode (`-I`), so a `yaml.py` in the repository is never imported, and the PyYAML it sees is the one in that interpreter's own site-packages, not one in the user site or on `PYTHONPATH`; without it, `check-workflow` does not run and `kit-init` exits 3. So the kit needs from a workstation: Docker, git 2.34 or later (the first git that signs with SSH keys), `ssh-keygen -Y`, the system bash and the standard Unix tools, and `bin/check-prereqs` checks the first four. Your project adds `make` when its check command uses it, `python3` with PyYAML wherever the checks are run by hand, and `python3` 3.9 or later on the workstation that runs `kit-init` once.

`bin/check-host` holds the kit's host files to this section: no external command outside the list in command position, and no bash 4 construct (`declare -A`, `mapfile`, `readarray`, `${x,,}`, `${x^^}`, `[[ -v`) anywhere in the file.

### 2.3 The workflow check's rules

`bin/check-workflow` carries the scheme's rules only; your own rules about your own jobs belong in your own check. The manifest supplies the names. `<always-on>` is the manifest's `always-on` job. A **scheme job** is a job the manifest lists, or a job a `check-name` line names. The rules read the manifest's `workflow` file; where a rule says "any workflow" it reads every file under `.github/workflows/`. A job outside the scheme (a prune, a deploy) is held only by the rules that reach it: W-4's gate (in the `workflow` file), W-9's name (likewise), and in any workflow W-1's ban on `pull_request_target` and `workflow_run`, W-4's `if: success()` on a record step, W-5's ban on a group built from the raw ref, W-7's ban on a `container:` key and W-8's ban on writing a green record.

| # | Rule |
|---|---|
| W-1 | the `workflow`'s triggers are exactly `pull_request` (`branches: [<main-branch>]`, `types: [opened, synchronize, reopened, ready_for_review]`, no path filter), `push` (`branches: [<main-branch>]`), `schedule` (one cron equal to `weekly-cron`) and `workflow_dispatch` (inputs `force`, `task` of `type: choice` whose options include `weekly`, and `delete`; the check only requires `force` and `delete` to exist, and W-6's expressions read them as booleans, so declare both `type: boolean`, as the table below the rules does); no workflow in the repository carries `pull_request_target` or `workflow_run` |
| W-2 | when `refuse-drafts yes`: the always-on job's first step, before any checkout, is the draft refusal with the kit's sentence (`This pull request is a draft, so no checks ran. Mark it ready for review to run them.`) and `exit 1`; no job's `if:` skips on draft |
| W-3 | the always-on job's output `sha` and the plan's `CI_PLAN_SHA` are the pull request's head sha (`github.event.pull_request.head.sha \|\| github.sha`); every other scheme job's checkout `ref:` and record step `SHA` read `needs.<always-on>.outputs.sha`; no step or job env reads `github.sha` or `GITHUB_SHA` on its own |
| W-4 | every job of the `workflow` except the always-on one `needs` it and has an `if:` reading one of its outputs (`needs.<always-on>.outputs.`); a manifest job's `if:` holds `needs.<always-on>.outputs.<job> == 'run'`, joined to anything else only by `&&` and with no status function (success-only); a job outside the scheme may gate on any output, as the example's `prune` gates on `main`; every record step in any workflow is `if: success()`. A job in another workflow file is not held to the gate |
| W-5 | no workflow-level concurrency; the always-on job's group is `ci-<always-on>-${{ github.run_id }}` with `cancel-in-progress: true`; every `local`, `ci-only` and `content` job's group is `ci-<job>-${{ needs.<always-on>.outputs.ref_group }}` with `cancel-in-progress: true`; no group is built from `github.ref`, `github.head_ref`, `github.ref_name` or a dispatch input; the always-on job's output `ref_group` is `${{ steps.plan.outputs.ref_group }}` |
| W-6 | the always-on job holds one step `id: plan`, `run: bash ci/kit/bin/plan`, its env exactly the six strings in the table below the rules, after a checkout with `persist-credentials: false` of the head sha; its `permissions` hold `contents: write`, `checks: read` |
| W-7 | every `local` job holds exactly, in order: the checkout (`persist-credentials: false`, `ref:` per W-3; `fetch-depth: 0` when the job is in `history`, otherwise absent or 1), the cache-runtime step (`crazy-max/ghaction-github-runtime` by sha), zero or more cache steps (`actions/cache` by sha, each `path:` `${{ runner.temp }}/<project>-ci-<kind>` for a kind the job's `cache` line names; a date-stamp step whose one command writes `date=` to `$GITHUB_OUTPUT` for a cache key is allowed among them), `bash ci/kit/bin/container image --commit "$SHA"` (optionally followed by the job's own id, which builds only what that job needs), `bash ci/kit/bin/container run --commit "$SHA" <job>`, the record step; its env sets `CIKIT_IMAGE_CACHE: gha`; it holds no `setup-*` action, no `services:`, no `container:` key, no `apt-get`, no `docker run` of its own. Every `ci-only` job runs `bash <adapter> <job>` exactly once, as the step before its record step, and no other step of it runs the test script or the launcher. No job in any workflow has a `container:` key |
| W-8 | for every manifest job, the last step of the job that writes its record (the job itself, or the job its `check-name` line names) is exactly `run: bash ci/kit/bin/record <job> "$KEY" "$SHA"` with `GITHUB_TOKEN` in its env; no other step in any workflow, and no code file under `ci/kit/` (its tests aside), the test script or the plan extension, writes a `refs/ci/green/` ref or calls `record`; the token, by any of its three spellings (`GITHUB_TOKEN`, `${{ github.token }}`, `secrets.GITHUB_TOKEN`), is never in the `workflow`'s workflow-level env, and in a scheme job's job env or step env only as the record step's `GITHUB_TOKEN` and the plan step's `GH_TOKEN` (W-6). A job outside the scheme (a prune, a deploy) may hold the token in its own steps (§5.5) |
| W-9 | every job's `name` equals its id (the check-run name the CI side of the trust check reads, DESIGN §5.4) |
| W-10 | every `history` job's checkout carries `fetch-depth: 0` |
| W-11 | every `uses:` in a scheme job, `actions/checkout` included, names its action by a full 40-hex commit sha |
| W-12 | no job the manifest lists holds a `write` permission other than `contents: write`, and that only when the job holds a record step; the always-on job holds `checks: read` (W-6); a workflow-level `permissions` block, when present, holds nothing above `read`. Read-level permissions beyond these are yours to choose |

The plan step's environment, which W-6 compares string for string, and the dispatch inputs it reads:

| Variable | Exactly |
|---|---|
| `CI_PLAN_SHA` | `${{ github.event.pull_request.head.sha \|\| github.sha }}` |
| `CI_PLAN_EVENT` | `${{ github.event_name }}` |
| `CI_PLAN_FORCE` | `${{ inputs.force && 'true' \|\| 'false' }}` |
| `CI_PLAN_TASK` | `${{ inputs.task }}` |
| `CI_PLAN_REPO` | `${{ github.repository }}` |
| `GH_TOKEN` | `${{ github.token }}` |

| Input | Type | As the example declares it |
|---|---|---|
| `force` | `boolean` | default `false`: ignore every record and run every job |
| `task` | `choice` | options `[tests, weekly]`, default `tests`: `tests` is the usual run, `weekly` the independent check; any other value turns every kit job `off` for your plan extension |
| `delete` | `boolean` | default `false`: read only by your prune job, which deletes on `true` and lists otherwise |

### 2.4 The hook shim and the state directory

`.githooks/pre-push` in every adopter is exactly:

```
#!/bin/sh
# The kit's hook (ci/kit/bin/pre-push) runs; this file is held byte-equal to ci/kit/hooks/pre-push.shim.
exec bash "$(git rev-parse --show-toplevel)/ci/kit/bin/pre-push" "$@"
```

It runs the **working copy's** hook, never the pushed commit's. `#!/bin/sh` and a bare `bash` word: the shim runs whichever `bash` is first on `PATH` (3.2 or later), and the kit's hook starts every child under that same `"$BASH"`. The kit owns the logic and you own the directory, so `.githooks/` can hold your other hooks too. Rule 8 of the manifest check requires the shim to be byte-identical to the kit's. The state directory is `<git common dir>/<project>-ci/` with `logs/`, `passed/<job>/`, `ran/<job>/` (the launcher's ran files, read by `bin/record` in CI) and `lock/`.

## 3. The manifest

### 3.1 File, location, format

- **Name and place:** `ci/manifest`, in the `ci/` directory at the repository root.
- **Format:** UTF-8 text, LF line endings, no byte order mark. One **directive** per line: the first word is the directive's name, the rest are its words, separated by one or more spaces or tabs; leading and trailing white space is ignored. No quoting, no continuation lines, no variable expansion. A line whose first non-blank character is `#` is a comment; a blank line is nothing. Only `not-run-allowed`, `escaping-read` and `check-command` take free text (their last field), and their rows below say so.
- **First line:** exactly `manifest v1` (the first non-blank, non-comment line). A kit release that changes the format bumps this line; an older kit refuses a newer manifest, and the other way round, in one sentence naming both versions.
- **How it is read:** by `lib/keys.sh`, from a named commit, as `git -C "$repo" show <commit>:ci/manifest`, then parsed by one `awk` program. It is never sourced, never `eval`ed and never passed to a shell, so data cannot redefine a function, and a format awk can read needs no `jq` or `yq` on any workstation. The trust inputs (the signers file at the path the commit's manifest gives, and the `not-run-allowed` lines) come from `main`'s tip, `refs/remotes/origin/<main-branch>` (DESIGN §6.7). There is one parser: every reader that is not bash takes `bin/keys dump <commit>` (one line per directive after validation, `<directive>\t<word>\t<word>...`, free-text fields last and untouched, in file order), because a directive that one parser accepted and another refused would be a key one side can compute and the other cannot.
- **Refusals:** an unknown directive, a word of the wrong shape, a repeated singular directive, a job named twice, a per-job directive naming an undeclared job, a reserved word (§3.8), or a broken constraint from the tables below: exit 2, naming the line number and the rule, before anything is computed. A key that cannot be computed is a key that does not exist (DESIGN §5.1a).

Shapes: a NAME is `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`, at most 32 characters; a PATH is a repository-relative path with no white space, no leading `/`, no `.` or `..` segment and no trailing `/`, or exactly `.` for the whole tree; a VAR is `^[A-Z][A-Z0-9_]*$`; a TOOL is `^[a-z][a-z0-9-]*$`; a FIELD is `^[a-z][a-z0-9_]*$`; an INTEGER is `^[0-9]+$` within its stated bounds; a DIGESTED IMAGE is `<name>[:<tag>]@sha256:<64 hex>`.

Three more shapes, as the parser defines them: a KIND (of `install`, `service`, `cache`, `pin-source`, `escaping-scan`) is `^[a-z][a-z0-9-]*$` before its closed set is checked; a cron word is `^[A-Za-z0-9*,/-]+$`; a `service` `flag` value is `^[a-z_][a-z0-9_.]*=[^ \t]+$`. A PATH also contains none of `*`, `?`, `[`, `]`, `\` or `:` and does not start with `-`: the check must never expand as a glob what the key reads literally, and no word may reach `git` or `docker` looking like an option. A DIGESTED IMAGE's name does not start with `-`. A job NAME is never `image` or `base`, the two image words of `kit_key`. A TOOL and a FIELD are never one of the facts block's own names: `job`, `key`, `commit`, `started`, `duration_s`, `platform`, `host`, `docker`, `image`, `not_run`, `log_sha256`. Each of these is a shape refusal (rule 1) with its line: *"ci/manifest line <n>: <word> is the kit's own name, so it cannot name a <job, tool or count>."*

### 3.2 Project-wide directives (each exactly once unless marked optional)

| Directive | Words | Constraint | Default | In the example |
|---|---|---|---|---|
| `manifest` | `v1` | the first line | none | `manifest v1` |
| `project` | one word | `^[a-z][a-z0-9]{1,15}$`; every derived name in §3.5 comes from it | none | `rottnest` |
| `key-epoch` | INTEGER | 1 to 999; the key header is `<project>-ci-keys v<epoch>`; a bump moves every key | none | `1` |
| `local-epoch` | INTEGER | 1 to 999; the facts' format line is `<project>-local-ci v<epoch>`; a record with any other format line is refused | none | `1` |
| `main-branch` | NAME | the protected branch; the plan's `main` output, the hook's merge warning and the prune's tip all use it | none | `main` |
| `workflow` | PATH | the one workflow `check-workflow` reads and the plan's jobs live in | none | `.github/workflows/ci.yml` |
| `always-on` | NAME | a `job <name> always-on` line | none | `checks` |
| `adapter` | PATH | the test script (§4); in the key of every job the script runs (rule 3) | none | `ci/ci-job.sh` |
| `kit-job` | NAME | a `local` job whose tests are `bash ci/kit/tests/run` in the base image, never the test script (§5.6); its `paths` line is exactly `ci`; no `pin`, `service`, `socket`, `cache`, `install`, `history` or `env` line names it | none | `kit` |
| `plan-extension` | PATH | optional; sourced by the plan after its decisions (§4.4) | none | none |
| `signers` | PATH | the allowed-signers file, read from `main` (DESIGN §6.6); covered by at least one `local` job's key (rule 5) | none | `ci/allowed-signers` |
| `check-command` | free text | the command the `sign` refusal names (*"Run <check-command> first."*) | none | `make check` |
| `weekly-cron` | five words | a cron whose minute is not `0`; `check-workflow` requires the workflow's one schedule to equal it (W-1) | none | `20 6 * * 1` |
| `prune-days` | INTEGER | 1 to 365 | `30` | `30` |
| `prune-keep-green` | NAME... | jobs whose green record at `main`'s tip is kept at any age; the local keep set is always the `local` jobs | none | `checks api web kit` |
| `lock-wait-minutes` | INTEGER | 1 to 240 | `30` | `30` |
| `refuse-drafts` | `yes` or `no` | `yes` makes W-2 require the draft refusal | none | `yes` |
| `image` | PATH | your toolchain Dockerfile; exactly one `FROM ${CIKIT_BASE}`; every other `FROM` a DIGESTED IMAGE (rule 9); under one of the `image-path` PATHs; `ARG CIKIT_BASE` declared before that `FROM` (Docker requires it; BuildKit then prints an `InvalidDefaultArgInFrom` warning on every build, which is expected, because the launcher always passes the argument), and no `LABEL` with the kit's key, which the launcher sets at build time | none | `ci/image/Dockerfile` |
| `image-path` | PATH... | the toolchain image's inputs: its build context (`git archive <commit> -- <these>`) and the paths rule 9 requires inside every `local` job's key except the kit job's. The job image's key is `ci/kit/image` plus these; the base image's key is `ci/kit/image` alone, so a pin bump rebuilds your layer and not the base | none | `ci/image api/go.mod web/.nvmrc` |
| `user` | INTEGER | optional; 1000 to 65533; the uid and gid the base image creates and the job runs as, equal to the runner's; a value line in both image keys, so a change rebuilds both | `1001` | `1001` |

### 3.3 Job directives

| Directive | Words | Constraint | In the example |
|---|---|---|---|
| `job` | NAME CLASS | CLASS is `always-on`, `local`, `ci-only` or `content`; the order is the plan's report order; exactly one `always-on`; the NAME is the workflow job's id and `name` (W-9); never `image` or `base` (§3.1). A `local` job may record on a workstation; a `ci-only` job runs only in CI through the test script; a `content` job is keyed and decided by records but never runs through the test script (an apply step, say) | `job checks always-on`, `job api local`, `job web local`, `job kit local` |
| `paths` | NAME PATH... | once per job; the ordered path list of DESIGN §5.1; a listed PATH covers itself and everything under it; `.` is the whole tree | `paths checks .`; `paths api api web/.nvmrc ci`; `paths web web api/go.mod ci`; `paths kit ci` |
| `check-name` | NAME NAME | optional; the check run that vouches for the job's green record when another job writes it | none |
| `pin` | NAME TOOL... | optional; the tools whose versions the facts carry and the preflight checks | `pin api go`; `pin web node` |
| `count` | NAME FIELD... | required for `local` and `ci-only`; at least one FIELD. The kit job's line must be exactly `count <kit job> kit_cases`: `tests/run` prints that field name itself | `count api go_packages go_tests`; `count web vitest_files vitest_tests`; `count kit kit_cases` |
| `install` | NAME KIND DIR | optional, at most once per `local` job; KIND is `npm-ci` in v1; DIR a PATH; runs inside the container by the entry script after the tree is in and before the tests, with exit 2 on failure; never on a job named in `socket`, because an install's lifecycle scripts would run with the socket and the host network | `install web npm-ci web` |
| `service` | NAME KIND KEY VALUE... | optional, at most one per `local` job; KIND is `postgres` in v1; keys: `image` (a DIGESTED IMAGE, required), `url-env` (a VAR, required), `flag` (repeatable, one `-c` server flag each); the sidecar runs on the per-run network, published on no port, waited on with `pg_isready` for up to 60 s, removed on every exit; the job gets `postgres://<project>:<project>-test-password@<service container>:5432/postgres?sslmode=disable` in `url-env`, so the database is `postgres` (§3.5 names the container); never on a job named in `socket` | `service api postgres image postgres:18@sha256:<64 hex> url-env ROTTNEST_TEST_PG_URL flag fsync=off flag synchronous_commit=off` |
| `socket` | NAME... | optional; the `local` jobs given the Docker socket with `--group-add` of its group and `--network host`; every other job gets neither (DESIGN §6.0 says what that reach means) | none |
| `history` | NAME... | optional; the `local` jobs that take the commit and its whole ancestry as a pack with `CIKIT_COMMIT`, refused on a shallow clone before any container starts; the rest take the archive; W-10 requires their checkout at `fetch-depth: 0` | none |
| `cache` | NAME KIND... | optional; KIND is `gomod`, `gobuild` or `npm` (the targets in §2.1); a named volume `<project>-ci-<kind>` on the workstation, `$RUNNER_TEMP/<project>-ci-<kind>` in CI, mounted at the kind's target: `/home/ci/go/pkg/mod` (`gomod`), `/home/ci/.cache/go-build` (`gobuild`), `/home/ci/.npm` (`npm`). Your toolchain image must create those directories owned by the job user and point the tools at them (`GOPATH=/home/ci/go`, `GOCACHE=/home/ci/.cache/go-build`, `npm_config_cache=/home/ci/.npm`), or the cache is mounted where nothing looks and a root-owned mount point refuses the writes | `cache api gomod gobuild`; `cache web npm` |
| `env` | NAME VAR... | optional; the host variables passed into the job's container by name when set, empty included; never a reserved name: `CIKIT_*`, `GITHUB_*`, `ACTIONS_*`, `RUNNER_*`, `GH_*`, `GIT_*`, `SSH_*`, `DOCKER_*`, `PATH`, `HOME`, `CI`, a name ending `_TOKEN`, `_KEY`, `_SECRET`, `_PASSWORD` or `_CREDENTIALS`, or a service's `url-env`; refused by the parser (rule 1) and again by the launcher | none |
| `escaping-tree` | NAME PATH... | the job's own trees for `check-escaping-reads` (DESIGN §5.1) | `escaping-tree api api`; `escaping-tree web web` |

### 3.4 Pins, probes, skips, escaping reads

| Directive | Words | Constraint | In the example |
|---|---|---|---|
| `pin-source` | TOOL KIND PATH | TOOL, or `*` as the fallback for a tool no other line names; KIND is one of `toolchain-line` (the second field of the first line whose first field is `toolchain`), `first-line` (the first line, white space removed) and `readonly-version` (the value after `readonly <NAME>_VERSION=` at the start of a line, `<NAME>` being the tool upper-cased with `-` as `_`, refused if empty or containing white space); read at the commit with `git show`, never executed (DESIGN §6.7 condition 3); the PATH is in the key of every job that pins the tool (rule 4) | `pin-source go toolchain-line api/go.mod`; `pin-source node first-line web/.nvmrc` |
| `probe` | TOOL KIND [`in` DIR] [BINARY [ARG...]] | optional per pinned tool; a tool with no line is `version-flag` with BINARY the tool's name. The reader runs **inside** the job image, once for all tools, with no network, as an awk program the launcher composes from these lines; each BINARY runs as an argument vector, never through a shell; only stdout is read. KINDs: **`version-flag`**: `BINARY --version`, then `BINARY version` if the first exits non-zero; the answer is the first token on the first line that has one matching `^v?[0-9]+\.[0-9]+(\.[0-9]+)?` after surrounding `[](),;` are stripped. **`first-line`**: the first line of stdout, white space trimmed, whole. **`after-word` WORD**: the token after the first occurrence of WORD (an exact token, compared after the same stripping) on the first line that has it, stripped the same way, so `after-word core` reads `ansible-playbook [core 2.21.4]` as `2.21.4`. **`python-minor`**: BINARY (default `python3`) run with `-c 'import sys; print("%d.%d" % sys.version_info[:2])'`. `in DIR` runs the probe in that directory of the tree. No regular expression and no shell text is ever read from the manifest, because a pattern read from data would be code reaching `sed` or `awk` | `probe go first-line go env GOVERSION`; `probe node first-line node --version` |
| `not-run-allowed` | LEG free text | LEG `^[^ ]+$` (`<harness path>:<leg name>`); the rest is the criteria it stands for (DESIGN §6.10); read from `main`'s manifest by the plan and from the working copy's by the driver | none |
| `escaping-scan` | KIND PATH | KIND `go` (files `*_test.go`) or `ts` (`*.test.ts`, `*.test.tsx`, and every file under a `test/` directory of the PATH); `node_modules`, `dist` and `coverage` directories are skipped. The kit scans these two languages only, and in them test files only; a crossing in any other language is declared by hand, and the check says so in its output. **What the scanners cannot see is yours to declare**: a non-test file your tests import that reads files at run time (a Go test-database helper loading migrations through a relative path, a fixture loader), and a climb that is computed rather than written out (`filepath.Dir` chains, `strings.Repeat("../", n)`, a name bound to another name or imported). For each, add every path it reads to the job's `paths` line and write an `escaping-read` line naming the file; the check then holds that path to the key. A manifest with no escaping-scan line has nothing scanned; the check says so, checks the escaping-read lines against the keys and passes. | `escaping-scan go api`; `escaping-scan ts web/src` |
| `escaping-read` | one ENTRY | the rest of the line is DESIGN §5.1's four-field entry, `<job>\|<test file>\|<outside paths, or WHOLE-TREE or NONE>\|<why>`; the job is `local` or `ci-only`; the test file sits in that job's `escaping-tree`; each outside path is covered by the job's key (rule 6) | none |

### 3.5 What the kit derives from `project`

| Derived | Rule | In the example |
|---|---|---|
| key header | `<project>-ci-keys v<key-epoch>` | `rottnest-ci-keys v1` |
| facts format | `<project>-local-ci v<local-epoch>` | `rottnest-local-ci v1` |
| counts prefix | `<project>-ci-job v1 counts` | `rottnest-ci-job v1 counts` |
| state directory | `<git common dir>/<project>-ci/` | `rottnest-ci/` |
| temporary files | `${TMPDIR:-/tmp}/<project>-ci-container.XXXXXX`, `<project>-ci-keys.XXXXXX` | `rottnest-ci-container.XXXXXX` |
| temporary tag | `<project>-ci-local-<job>-<key12>-<pid>` | `rottnest-ci-local-api-<key12>-<pid>` |
| image repositories | `<project>-ci-job:<image key>`, `<project>-ci-base:<base key>` | `rottnest-ci-job`, `rottnest-ci-base` |
| gha builder and cache scopes | `<project>-ci-gha`; `<project>-ci-job-base`, `<project>-ci-job` | `rottnest-ci-gha` |
| run network, job container | `<project>-ci-<run id>`, `<project>-ci-<job>-<run id>` | `rottnest-ci-api-<run id>` |
| service container | `<project>-check-<kind>-<run id>` | `rottnest-check-postgres-<run id>` |
| service credentials | user `<project>`, password `<project>-test-password` | user `rottnest` |
| cache volumes and directories | `<project>-ci-<kind>`; `$RUNNER_TEMP/<project>-ci-<kind>` | `rottnest-ci-gomod` |
| dead push path | `/dev/null/<project>-no-push-from-a-job/` | `/dev/null/rottnest-no-push-from-a-job/` |
| record namespaces | `refs/ci/green/<job>/<key>`, `refs/ci/local/<job>/<key>` | the kit's constants, never per project |

### 3.6 The example's manifest in full (an illustration; the directive tables above are the normative text)

The example repository's `ci/manifest`, byte for byte (only the service image's digest is shortened here):

```
# The kit's one file of this project's facts: the jobs, the paths each job's
# verdict depends on, the pins, and where the tools and records live. The kit
# reads it as data (ci/kit/README.md section 3 is the reference); nothing here
# is executed. `ci/kit/bin/check-manifest` lints it.
manifest v1
project rottnest
key-epoch 1
local-epoch 1
main-branch main
workflow .github/workflows/ci.yml
always-on checks
adapter ci/ci-job.sh
kit-job kit
signers ci/allowed-signers
check-command make check
weekly-cron 20 6 * * 1
prune-days 30
prune-keep-green checks api web kit
lock-wait-minutes 30
refuse-drafts yes
image ci/image/Dockerfile
image-path ci/image api/go.mod web/.nvmrc
user 1001

# checks runs on every run; api and web run on a workstation (make check) or
# in CI; kit runs the vendored kit's own proofs.
job checks always-on
job api local
job web local
job kit local

# A job's key is a hash of these paths at the commit. `ci` holds the kit, this
# manifest, the adapter, the image and the signers file, so a change to any of
# them runs every job; web/.nvmrc and api/go.mod are the job image's inputs,
# so each is in the other job's key too.
paths checks .
paths api api web/.nvmrc ci
paths web web api/go.mod ci
paths kit ci

pin api go
pin web node
count api go_packages go_tests
count web vitest_files vitest_tests
count kit kit_cases
install web npm-ci web
service api postgres image postgres:18@sha256:<64 hex> url-env ROTTNEST_TEST_PG_URL flag fsync=off flag synchronous_commit=off
cache api gomod gobuild
cache web npm

pin-source go toolchain-line api/go.mod
pin-source node first-line web/.nvmrc
probe go first-line go env GOVERSION
probe node first-line node --version

# The escaping-read fence: a test file may read only inside its own job's
# trees unless an escaping-read line below declares what it reads.
escaping-tree api api
escaping-tree web web
escaping-scan go api
escaping-scan ts web/src
```

Read it against the manifest check (§3.7): `ci` in the `api` and `web` keys covers `ci/kit`, `ci/manifest`, the test script, the signers file and `ci/image` (rules 3, 5 and 9); each job's key also lists the other job's pin file, because both are image inputs (rule 9); the always-on job's key is `.` (rule 3). The example's keys list neither its Makefile nor its workflow, because in the container form neither decides what runs inside the image: the launcher calls the test script directly. Where this copy and the repository's file differ, the repository's is the one that runs.

### 3.7 The manifest check (`ci/kit/bin/check-manifest [--commit <rev>] [--no-vendor-check]`), run in the always-on job

It reads the **committed** manifest and tree at HEAD (or `--commit`), not your working copy, so commit first: rules 8 and 11 need the shim, the test script, the workflow, the image file and the signers file in that commit. Each finding is one sentence naming the line; exit 1 on a finding, 2 when the manifest cannot be parsed (rule 1). `--no-vendor-check` skips rule 7 and is for fixture manifests only (the kit's own tests, and the kit repository's own workflow before it vendors itself); your always-on job never passes it (the workflow check reads the command). `check-manifest` runs under `set -f`, so no manifest word is ever expanded as a glob. `--file <path>` reads a working-tree file with no tree behind it, and the rules that need one (6's existence half, 7, 8, 9's image file, 11) each print that they did not run.

1. Every shape and constraint of §3.1 to §3.4, and no reserved word of §3.8.
2. Exactly one `always-on` job, named by `always-on`; every `local` and `ci-only` job has a `count` line with at least one FIELD; exactly one `kit-job`, a `local` job whose `paths` is exactly `ci` and which no `pin`, `service`, `socket`, `cache`, `install`, `history` or `env` line names.
3. The key of every `local` and `ci-only` job except the kit job covers `ci/kit`, `ci/manifest` and the `adapter` PATH, because a key that leaves out the code that ran the job would let a record outlive a change to that code. The always-on job's key is `.` or covers `ci/kit`, `ci/manifest` and the `workflow` PATH.
4. Every `pin-source` PATH is covered by the key of every job that pins a tool it is the source for (`*` is the source for every pinned tool no other line names). Every pinned tool has a source: a `pin-source` line names it or a `*` line exists.
5. The `signers` PATH is covered by at least one `local` job's key.
6. Every `escaping-read` entry names a `local` or `ci-only` job, a test file inside that job's `escaping-tree`, and outside paths each covered by that job's key; every `escaping-tree` and `escaping-scan` PATH exists at the commit.
7. `git rev-parse <commit>:ci/kit` equals the `tree` line of `ci/KIT-VERSION` (§5.2).
8. `.githooks/pre-push` at the commit equals `ci/kit/hooks/pre-push.shim` byte for byte (§2.4).
9. Every `image-path` PATH is covered by the key of every `local` job except the kit job; the `image` PATH is under an `image-path` PATH; the `image` file holds exactly one `FROM ${CIKIT_BASE}` and every other `FROM` names a DIGESTED IMAGE; every `socket` and `history` NAME is a `local` job; every `service` image is a DIGESTED IMAGE; at most one `service` and one `install` per job. In the `image` file every `COPY --from=` and every `RUN --mount=` `from=` names a stage defined earlier in the file or a DIGESTED IMAGE, and a `# syntax=` line, when present, names a DIGESTED IMAGE; no job named in `socket` has an `install` or a `service` line.
10. Every `probe` TOOL is pinned by at least one job; every `env` VAR is in shape and not reserved; every `cache` KIND, `install` KIND, `service` KIND, `escaping-scan` KIND and `pin-source` KIND is in its closed set.
11. The `adapter`, `workflow`, `image`, `signers` and (when given) `plan-extension` PATHs exist at the commit as files. An empty file, or one holding only a comment line, counts as a file: the landing commits the signers file that way, and it trusts nobody until a signer's line merges (DESIGN §6.6, §9).
12. `weekly-cron`'s minute is not `0`; `prune-keep-green` names declared jobs.

### 3.8 Reserved words, refused with *"<word> is reserved for a later kit release, so nothing ran."*

`prepare` (the section of §4.3, not built in `v1`: no adopter has yet needed per-run preparation beyond `install`, and the kit only admits what some run has shown is needed), `probe-after-prepare`, `docker`, `client-major`, `client-bin-env`. The directive set of `manifest v1` is otherwise final; a second `service`, `install`, `cache` or `escaping-scan` KIND would be a MINOR release (§5.1).

## 4. The test script's contract

The manifest calls the test script the adapter, and so do the kit's commands (`check-adapter`, `CIKIT_ADAPTER`). This section uses both words for the same file.

### 4.1 Running a job

```
<adapter> <job>
  exit 0     every check of <job> passed
  exit 2     refused before any check: an unknown job, a tool absent or off its pin
  any other  a check failed
```

1. **One command list.** CI runs it as one step (DESIGN §6.1); the driver runs the same file in the job container, under the isolation of DESIGN §6.2 step 10, with stdin `/dev/null` and its output redirected to the log.
2. **Settings from the environment only:** the service's `url-env`, the variables the manifest's `env` lines pass, and your own. It reads no file it finds lying around for its settings.
3. **Under CI** (`GITHUB_ACTIONS=true`, which the launcher passes with the constant `CI=true` beside it and nothing else of the runner's) it prefixes refusals and failures with `::error::`; the driver unsets the variable on a workstation, so a local run carries neither.
4. **On exit 0, exactly one counts line** for the job: `<project>-ci-job v1 counts <job> <field> <value> [<field> <value>...]`, with every field of the manifest's `count` line for the job, in that order, each value one to nine digits and above zero when anything ran. The driver takes the last such line and refuses a record otherwise (DESIGN §6.2 step 11); the driver and the plan apply the same one-to-nine-digit rule, so a run and the plan cannot disagree.
5. **On a non-zero exit, no counts line.**
6. **A part that cannot run on the platform** prints `NOT RUN <leg>: <reason>` at the start of a line (DESIGN §6.10); nothing else in the log is a skip.
7. **Exit statuses are read directly**, never through a pipe (DESIGN §6.1).
8. **Refusal sentences** name the tool, the version found, the pin and the job (DESIGN §6.1).
9. **A `ci-only` job's section** behaves the same; the driver refuses to run it (DESIGN §6.1) and CI runs it.

### 4.2 Services

The test script never starts a service. The launcher starts each `service` the manifest lists for a job before running that job's section and hands its URL over in `url-env`, in CI and on a workstation alike. A job that needs a kind of service the kit lacks cannot be a local job until a kit minor release adds the kind.

### 4.3 The `prepare` section (not built in v1)

`prepare` is a reserved word the manifest refuses (§3.8). If a later minor release builds it, the design is: `<adapter> prepare <job> <state dir>`, run once per job named in a `prepare` line, inside the container after the tree is in and the installs have run, printing zero or more `env <NAME> <value>` lines that set variables for that job's process only; any other line, or a non-zero exit, refuses the run (exit 2). `check-adapter` does not call it.

### 4.4 The plan extension (optional)

Sourced by `ci/kit/bin/plan` after every kit decision, with the kit's arrays, the mode (`normal`, `force`, `weekly`, `task:<name>`), `main` and the keys in scope (§2.1). It may set decisions, outputs and summary rows for job names the manifest does not declare (a build, a deploy, the weekly prune); it may read the records of its own kinds. The plan takes a snapshot of every kit job's decision and key before sourcing it and compares afterwards: a changed decision fails the plan with *"The plan extension changed the decision of <job>, which is the kit's to make, so nothing ran."*, a changed key with *"The plan extension changed the key of <job>, which is the kit's to compute, so nothing ran."*, and every kit job's outputs (its decision, key and platform) are written from the snapshot. This is a check against **accidents** in your own reviewed code, never a security boundary: the extension is sourced into the plan's shell and can reach everything the plan reaches. A malicious extension is out of scope exactly as a malicious commit is (DESIGN §3.4); a mis-keyed record it might write is refused by the recomputed key, so it can cause a run, never a skip.

### 4.5 How the kit tests the contract

- **The toy test script** (`ci/kit/tests/fixture/adapter.sh`): two sections, `alpha` (local) and `beta` (CI-only), each driven by a fixture variable to pass, fail, refuse, print no counts line, print a zero count, print an allowed or unlisted `NOT RUN` line, print a counts line through a pipe that masks a failure, or call `git push` towards a GitHub prefix. The kit's tests (§6) run against it.
- **The contract check for a real test script** (`ci/kit/bin/check-adapter <job>`, run by you, §7 step 6): (a) `<adapter> no-such-job` exits 2 and prints no counts line; (b) in the log of one real passing run through the driver, exactly one counts line names the manifest's fields in order with values above zero, and every `NOT RUN` line is in shape and allow-listed. What no generic check can do stays yours: one planted failing step per section that turns the section red and removes the counts line (§6.3).

## 5. Vendoring and versioning

### 5.1 The kit repository and its releases

The kit repository holds `kit/` (what is vendored: `lib/`, `bin/`, `image/`, `hooks/`, `tests/`, this `README.md`), `DESIGN.md` and its workflow. Releases are SSH-signed annotated tags `vMAJOR.MINOR.PATCH` (a candidate may carry a suffix, `v1.0.0-rc.1`) on a protected `main` that accepts pull requests only, with signed commits required.

**Versions mean something.** MAJOR: the manifest format (`manifest v2`), the test script's contract, the key formula or a predicate sentence changes, so you have to act. A predicate sentence is something the plan decides by and your workflow reads: a decision value, the name or meaning of an existing output, or the outcome of a trust check on a record an earlier release wrote. A new output, a new summary column, a clause added to a note, or a refusal of a record shape no earlier release wrote is MINOR; a newly reserved output name is MINOR and its entry names it. MINOR: a new optional directive, kind or scanner. PATCH: a fix that changes no interface; a base image digest bump is a PATCH. Every release's `CHANGELOG.md` entry states whether it changes keys (every release does, §5.4), the `kit/` tree it contains, and what you have to do, so that the update pull request can say in one line whether you have any work.

### 5.2 `ci/KIT-VERSION`

```
tag v1.0.0
commit <40 hex: the commit the tag names>
tree <40 hex: git rev-parse <tag>^{commit}:kit>
signer <principal from ci/KIT-SIGNERS>
vendored <YYYY-MM-DD>
```

The manifest check compares `git rev-parse HEAD:ci/kit` with `tree` on every run (§3.7 rule 7). An accidental edit in `ci/kit/` fails the always-on job; a deliberate one has to change `KIT-VERSION` as well, and so shows up in review as a change to both, which is the control (an offline check cannot tell a real release tree from an invented one; §5.3 step 2 does).

### 5.3 The update procedure, one pull request

1. On your workstation, at the top of a working copy checked out at `main` (never a branch someone else wrote): `bash ci/kit/bin/kit-update <tag> [<kit repository URL>]` (default `https://github.com/aames/quokka-ci-kit.git`) clones the kit in full into a temporary directory and fetches the tag. This is the one network act, done by a person, never in CI. At a first vendoring there is no `ci/kit/` yet, so run the same file from a clone of the kit: `bash <clone>/kit/bin/kit-update <tag>`.
2. It accepts `<tag>` only as a **release**, not merely as an object some listed key signed. A listed signer's key signs other git objects too (every local record is an annotated tag signed in the `git` namespace), so all of the following must hold:
   - (a) `refs/tags/<tag>` is an annotated tag object whose own `type` header is `commit` and whose own `tag` header equals `<tag>`;
   - (b) the first line of its message is exactly `quokka-ci-kit <tag>`;
   - (c) its commit is the kit repository's `main`, or an ancestor of it, in the same full clone;
   - (d) `git tag -v` exits 0 and its **standard error** alone, read line by line, holds exactly one line matching `^Good "git" signature for ([^ ]+) with [^ ]+ key [^ ]+$`, whose principal is the `signer` written to `ci/KIT-VERSION`;
   - (e) the allowed-signers file is `ci/KIT-SIGNERS` (DESIGN §6.6's format, one line per release signer, `<principal> namespaces="git" <key type> <key>`; the release signer's line and fingerprint are in the kit repository's README.md, under "Releases and the release signer") as your `refs/remotes/origin/<main-branch>` carries it, and the working copy's copy must equal it (*"ci/KIT-SIGNERS differs from <main-branch>'s, so nothing was changed. Change it in a pull request of its own first."*); when `main` carries none (your first vendoring), the working copy's is used and the fingerprint of each of its lines is printed for you to confirm through another channel. If no fingerprint line is printed for a line of the file, stop: do not vendor.

   The tag's `kit/` tree must hold regular files only (no symlink, no submodule). A record's tag name and message cannot take a release's (§3.5's temporary tag; the facts' format line), so (a) and (b) are what no record object can carry; (c) makes a release a reviewed commit on the kit's protected branch; (d) keeps text the signed object controls out of the parse; (e) means a branch cannot vendor against signers `main` never accepted.
3. It writes the tag's `kit/` tree by git's own checkout, confirms the tree hashes to `<tag>^{commit}:kit`, then replaces `ci/kit/` with it byte for byte and rewrites `ci/KIT-VERSION`.
4. It prints the tag's `CHANGELOG.md` entry, which lists what you have to do; make any manifest change in the same branch.
5. Run the check command (`make check`, or `ci/kit/bin/local-ci run --commit HEAD <the local jobs>`): every local job, the kit job included, because every key that includes the test script has moved (§5.4).
6. Open one pull request naming the tag, the commit, the tree, and the entry's "changes keys" line. The reviewer re-runs `kit-update --verify-only <tag>` from `main`'s copy and reads the same five lines.

`ci/KIT-SIGNERS` holds the keys that may sign a kit release, in a file separate from your project's `signers`: the right to release the trust code and the right to vouch for one tree are different powers, and one file would grant both.

### 5.4 How the kit's version enters the key

Through content, not through a version string: `ci/kit` is in the key of every job that runs through the test script (§3.7 rule 3), so every kit release, patches included, moves those keys. No kit version is added to the key header, because a header carrying only a MAJOR would let a driver fix pass without re-testing. The price is one re-test per upgrade: one local run per local job (workstation minutes, no billed minutes when the hook signs them), one CI run per `ci-only` job, and nothing for `content` jobs whose keys do not list `ci`.

### 5.5 How the workflow calls the kit

No composite action, local or remote. The plan step is `run: bash ci/kit/bin/plan` from the vendored copy; the script masks the token and sets git's authorisation header itself. A composite action's outputs would have to be declared statically, while each project's job list differs; and a pinned remote action would run trust-deciding code your pull request never shows. So nothing outside your repository runs in the plan, and the one fetch (§5.3 step 1) is a person's, verified, and reviewed as a diff. The workflow check (W-6) holds the step's shape.

**The wiring, job by job.** The example's `.github/workflows/ci.yml` (in [`quokka-ci-kit-example`](https://github.com/aames/quokka-ci-kit-example)) is a complete reference that passes the workflow check: copy it and rename `rottnest`, `checks`, `api`, `web` and `kit` to your project and job names, rather than writing one from nothing. Each job's `name` equals its id and its manifest job name (W-9).

- **The always-on job** (`checks` in the example): `permissions: contents: write, checks: read`; concurrency `ci-<job>-${{ github.run_id }}`; outputs `sha` (the head sha), `ref_group`, `main`, and one `<job>` and `<job>_key` per manifest job from `steps.plan.outputs`. Steps: the draft refusal first when `refuse-drafts yes` (W-2); the checkout with `persist-credentials: false` at `github.event.pull_request.head.sha || github.sha`; the `Plan` step (W-6); then, under `if: steps.plan.outputs.<always-on> == 'run'`, `bash ci/kit/bin/check-manifest --commit "$SHA"`, `python3 ci/kit/bin/check-workflow` and `python3 ci/kit/bin/check-escaping-reads`; and last, the record step. The workflow check needs PyYAML: the example relies on the runner image carrying it, and where yours does not, one step before the checks installs it, which the workflow check allows in the always-on job (W-7 refuses `apt-get` only in `local` jobs): `python3 -c 'import yaml' 2>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq python3-yaml; }`.
- **Each `local` job** (`api`, `web`, the kit job): `needs` the always-on job, `if:` on its output `== 'run'`, `permissions: contents: write`, concurrency `ci-<job>-${{ needs.<always-on>.outputs.ref_group }}`, env `CIKIT_IMAGE_CACHE: gha`; steps exactly as W-7 lists them: checkout at `needs.<always-on>.outputs.sha`, the cache-runtime action, the job's cache steps, `container image`, `container run`, the record step. The kit job has no cache step and names itself on the image step (`container image --commit "$SHA" kit`), so only the base is built.
- **Each `ci-only` job:** the same gating, its own setup, `bash <adapter> <job>` once, then the record step.
- **The weekly prune**, a job outside the scheme, because no scheme job may hold the token beyond its record and plan steps (W-8): in the example, `prune` needs the always-on job, runs `if: needs.<always-on>.outputs.main == 'true' && (github.event_name == 'schedule' || inputs.task == 'weekly')`, holds `contents: write`, checks out the head sha with no credential, hands `GH_TOKEN` to git for its one step through `GIT_CONFIG_COUNT` and an `http.<server>/.extraheader` basic header (masked first), and runs `bash ci/kit/bin/prune green "$SHA" "$DELETE"` then `prune local`, with `DELETE` the dispatch's `delete` input (`false` on the schedule, so the schedule only lists). W-1 requires the `delete` input whether or not you prune. A plan extension can decide such a job instead, when you have one.

**The actions, as the example pins them** (W-11; check each sha against the action's own release before you copy it, and move them together when you upgrade):

| Action | Pinned as |
|---|---|
| `actions/checkout` | `actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4` |
| `crazy-max/ghaction-github-runtime` | `crazy-max/ghaction-github-runtime@04d248b84655b509d8c44dc1d6f990c879747487 # v4.0.0` |
| `actions/cache` | `actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4` |

**The cache keys, as the example writes them.** The `path:` is fixed by W-7, `${{ runner.temp }}/<project>-ci-<kind>`; the `key:` is yours, and a key that moves too rarely only costs a cold cache, never a result, because caches are no input to a result:

| Kind | `key:` in the example |
|---|---|
| `gomod` | `rottnest-ci-gomod-${{ runner.os }}-${{ hashFiles('api/go.sum') }}` |
| `gobuild` | `rottnest-ci-gobuild-${{ runner.os }}-${{ steps.gobuild.outputs.date }}`, after a date-stamp step `id: gobuild` whose one command is `echo "date=$(date -u +%Y-%m-%d)" >> "$GITHUB_OUTPUT"` |
| `npm` | `rottnest-ci-npm-${{ runner.os }}-${{ hashFiles('web/package-lock.json') }}` |

**Branch protection's required checks:** the always-on job and every scheme job by name (`checks`, `api`, `web` and `kit` in the example). A job skipped on its `if:` reports success (DESIGN §4 item 7), so requiring a skipped job blocks nothing. A job outside the scheme that runs only on `main`, such as `prune`, need not be required.

**The example's skeleton**, as an illustration (the rules above are normative, and where this and the example's file differ, the example's is the one that runs). The triggers, the always-on job and one `local` job in full; `web` is `api` with its own name and its one `npm` cache, and `kit` is as the bullet above says:

```yaml
name: CI

on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, ready_for_review]
  push:
    branches: [main]
  schedule:
    - cron: "20 6 * * 1"
  workflow_dispatch:
    inputs:
      force:
        description: Ignore every record and run every job
        type: boolean
        default: false
      task:
        description: tests, the usual run; weekly, the independent check
        type: choice
        options: [tests, weekly]
        default: tests
      delete:
        description: weekly only; the prune deletes the old records it would otherwise list
        type: boolean
        default: false

permissions:
  contents: read

jobs:
  checks:
    name: checks
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: write
      checks: read
    concurrency:
      group: ci-checks-${{ github.run_id }}
      cancel-in-progress: true
    outputs:
      sha: ${{ github.event.pull_request.head.sha || github.sha }}
      ref_group: ${{ steps.plan.outputs.ref_group }}
      main: ${{ steps.plan.outputs.main }}
      checks: ${{ steps.plan.outputs.checks }}
      api: ${{ steps.plan.outputs.api }}
      web: ${{ steps.plan.outputs.web }}
      kit: ${{ steps.plan.outputs.kit }}
      checks_key: ${{ steps.plan.outputs.checks_key }}
      api_key: ${{ steps.plan.outputs.api_key }}
      web_key: ${{ steps.plan.outputs.web_key }}
      kit_key: ${{ steps.plan.outputs.kit_key }}
    steps:
      - name: Refuse a draft pull request
        if: github.event_name == 'pull_request' && github.event.pull_request.draft
        run: |
          echo "::error::This pull request is a draft, so no checks ran. Mark it ready for review to run them."
          exit 1
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
        with:
          persist-credentials: false
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
      - name: Plan
        id: plan
        env:
          CI_PLAN_SHA: ${{ github.event.pull_request.head.sha || github.sha }}
          CI_PLAN_EVENT: ${{ github.event_name }}
          CI_PLAN_FORCE: ${{ inputs.force && 'true' || 'false' }}
          CI_PLAN_TASK: ${{ inputs.task }}
          CI_PLAN_REPO: ${{ github.repository }}
          GH_TOKEN: ${{ github.token }}
        run: bash ci/kit/bin/plan
      - name: The manifest lint
        if: steps.plan.outputs.checks == 'run'
        env:
          SHA: ${{ github.event.pull_request.head.sha || github.sha }}
        run: bash ci/kit/bin/check-manifest --commit "$SHA"
      - name: The workflow fence
        if: steps.plan.outputs.checks == 'run'
        run: python3 ci/kit/bin/check-workflow
      - name: The escaping-read fence
        if: steps.plan.outputs.checks == 'run'
        run: python3 ci/kit/bin/check-escaping-reads
      - name: Record this tree green
        if: success() && steps.plan.outputs.checks == 'run'
        env:
          GITHUB_TOKEN: ${{ github.token }}
          KEY: ${{ steps.plan.outputs.checks_key }}
          SHA: ${{ github.event.pull_request.head.sha || github.sha }}
        run: bash ci/kit/bin/record checks "$KEY" "$SHA"

  api:
    name: api
    needs: checks
    if: needs.checks.outputs.api == 'run'
    runs-on: ubuntu-latest
    timeout-minutes: 20
    permissions:
      contents: write
    concurrency:
      group: ci-api-${{ needs.checks.outputs.ref_group }}
      cancel-in-progress: true
    env:
      CIKIT_IMAGE_CACHE: gha
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
        with:
          persist-credentials: false
          ref: ${{ needs.checks.outputs.sha }}
      - name: Expose the Actions cache runtime to the image build
        uses: crazy-max/ghaction-github-runtime@04d248b84655b509d8c44dc1d6f990c879747487 # v4.0.0
      - name: Cache Go modules
        uses: actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4
        with:
          path: ${{ runner.temp }}/rottnest-ci-gomod
          key: rottnest-ci-gomod-${{ runner.os }}-${{ hashFiles('api/go.sum') }}
      - name: Date stamp for the build cache key
        id: gobuild
        run: echo "date=$(date -u +%Y-%m-%d)" >> "$GITHUB_OUTPUT"
      - name: Cache the Go build cache
        uses: actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4
        with:
          path: ${{ runner.temp }}/rottnest-ci-gobuild
          key: rottnest-ci-gobuild-${{ runner.os }}-${{ steps.gobuild.outputs.date }}
      - name: The job image
        env:
          SHA: ${{ needs.checks.outputs.sha }}
        run: bash ci/kit/bin/container image --commit "$SHA"
      - name: The api verdict
        env:
          SHA: ${{ needs.checks.outputs.sha }}
        run: bash ci/kit/bin/container run --commit "$SHA" api
      - name: Record this tree green
        if: success()
        env:
          GITHUB_TOKEN: ${{ github.token }}
          KEY: ${{ needs.checks.outputs.api_key }}
          SHA: ${{ needs.checks.outputs.sha }}
        run: bash ci/kit/bin/record api "$KEY" "$SHA"
```

The example's `prune` job, in full, is in its file; the bullet above gives every line that matters to the workflow check. Set each `timeout-minutes` by measuring the job (DESIGN §11).

### 5.6 The kit job

Every adopter declares a `local` job that runs the kit's own tests from the vendored copy, named by `kit-job` and keyed on `ci` alone (`ci/kit` and `ci/manifest` are under it). You run the scheme's tests on your own workstation and runner at each upgrade without writing them, and the weekly run re-runs them on CI's platform; between upgrades the job costs nothing, because its key only moves on a kit upgrade or an edit under `ci/`. The test script does not run it: the launcher runs `bash ci/kit/tests/run` for it in the kit's **base** image (no toolchain layer) with `CIKIT_ADAPTER=ci/kit/tests/run` and `CIKIT_PROJECT` set, so the harness prints the counts line itself, and its tests run on the same bash, git and tools for every adopter. The base carries Debian's `python3` with PyYAML, bash 5 and bash 3.2 at `/opt/bash-3.2`, so every family of `tests/run` runs there and the kit job prints no `NOT RUN` line: it needs no `not-run-allowed` line. Its workflow job is W-7's shape with no cache step. What it proves is `tests/run`'s families; the base image's build test and the entry script's tree-in are `tests/image`, which needs a Docker daemon and runs where a socket is held (§6.1).

### 5.7 The kit's own CI, and how a release is cut

The kit repository's workflow runs the kit's **source** checks directly: `bash -n` over every bash file of the kit, the manifest check on the fixture manifest (`--no-vendor-check`), `check-host` on the kit's host files, the workflow check over its fixture workflows, then `bash kit/tests/run` and `bash kit/tests/image` against the runner's Docker. A repository cannot vendor a release of itself before one is tagged; once one exists, the kit may adopt itself like any adopter. Cutting a release is described in the kit repository's `CONTRIBUTING.md`.

## 6. The kit's own tests

### 6.1 The fixture

`ci/kit/tests/` holds: a fixture builder that makes a bare origin and a clone with a fixture `ci/manifest` (project `kitfix`; an always-on job `gate`; `alpha local`; `beta ci-only`; one `content` job `gamma`; `delta local`, the `history` and `socket` job; and a `kit-job` line naming `kitself`, which no fixture case runs), the toy test script (§4.5), a `gh` shim answering the check-runs API from a table, `docker`, `curl` and `sleep` shims, two throwaway SSH signing keys generated per run, and fixed **golden vectors**: fixture commits built from fixed blobs with fixed dates and their expected keys as literal hex. Every case uses the real clock for ages. The tests are three harnesses:

- `tests/run` needs no Docker daemon: every family runs on its shims. It prints `ok:` or `FAIL:` per case and one `NOT RUN <leg>: <reason>` line for a platform leg it cannot run, and ends with `${CIKIT_PROJECT}-ci-job v1 counts ${CIKIT_JOB} kit_cases <n>`. It is the kit job's test run.
- `tests/image` needs a Docker daemon: the base image built cold from `image/base.Dockerfile`, the entry script's tree-in with a fixture archive and a fixture pack, and the kit job run through the launcher in that base. It never starts, stops or reconfigures Docker, and removes what it tagged.
- `tests/plants` (Python) copies the kit tree, plants **one** defect from the "fails when" column below, runs that family against the copy and requires it to fail; the kit tree itself is never touched.

### 6.2 What the kit's tests prove on their own

Each family names what it proves and the planted defect that makes it fail. You do not prove these again; you run them (§5.6).

| Family | Proves | Fails when |
|---|---|---|
| K-keys | the formula against the golden vectors; `absent`; `.` as the tree; the epoch moves every key; a working-tree manifest edit moves no key; each function of the library's interface (DESIGN §5.1a); `kit_platform_of` on Git Bash's, Cygwin's and OpenBSD's unames, each in `KIT_PLATFORM_SHAPE`, and refusing an empty word | the header's newline is dropped; the manifest is read from the working tree; the empty-word refusal is removed |
| K-dump | `keys dump` is the one parser's output; every shape refusal | a shape rule is moved out of the awk program |
| K-manifest | every refusal of §3.1 to §3.4, each with its line number; the check's rules, rule 6 accepting the path `.` | each rule is removed in turn; rule 6's `.` case is removed |
| K-green | the CI side's codes 0, 1, 2 and 3; one page; `github-actions` only; `skipped` never accepted; both record shapes, a tag object peeled to its commit with its facts agreeing and `KIT_RECORD_PLATFORM` set (DESIGN §5.4); a tag of a tag refused; a `platform` line absent or given twice read as no platform, for a `local` job and another; a `ci-only` job's Windows platform (`msys_nt-10.0-19045/amd64`) trusted and one out of shape refused by name | the app-slug filter is removed; the check run is looked up on the tag object; a tag object's facts are not checked; the tag-of-a-tag refusal is removed; a `local` job's record is admitted with no platform; a line given twice is read as its last; an absent platform is reported as one out of shape; the platform shape before F-3 |
| K-local | the six conditions and every predicate of DESIGN §6.7 byte for byte; the grafted signature block and the `-n file` signature; a key on two lines; signers and allow-list from `main`, never the branch | the `-Y verify` call is removed (both signature cases turn green and no other); `main`'s signers are replaced by the checkout's |
| K-plan | the four modes; the schedule read as weekly before any record; `ls-remote` unreadable runs everything; absent commits fetched or untrusted; `main` fetched once; `main` case-sensitive; `ref_group` and its `weekly-` prefix; an unknown task turns every kit job `off`; the summary's rows and sentences; a green tag object trusted with its platform in the row and `<job>_platform`, a lightweight one with `-`, and one whose facts name another commit, another format or a non-Linux platform for a `local` job refused with its sentence; a `ci-only` job's Windows platform trusted and one out of shape refused with its sentence; a tag object the checkout lacks fetched whole at depth 1 | the schedule case is removed; the `weekly-` prefix is removed; a green facts' commit is not compared; a `local` job's green record is admitted on any platform |
| K-extension | an extension adding a job's decision passes; one changing a kit job's decision or key fails red with its sentence; a kit output name, `<job>_platform` among them, is refused; the platform outputs are written from the snapshot (§4.4) | the snapshot comparison is removed; the platform outputs are written from the live array |
| K-record | the tag object first with the facts block, then the ref at the tag object; 201, 422 "already exists", other 422, 403 once then warn (on either request), 000; a `local` job's missing or malformed ran file, or one whose platform is outside `KIT_PLATFORM_SHAPE`, and every bad shape refused with exit 2 before any request; a runner whose `uname` says nothing refused the same way | the 422 text check is removed; the ran file's presence check is removed; the ref is pointed at the commit; the platform shape before F-3 |
| K-prune | 31 days deleted, 29 kept, the tip's key kept at any age, a green tag object aged by its commit, a dateless local ref kept with its warning, a dry run deletes nothing | the tip exception is removed; the tag object's age is read without `%(*committerdate:unix)` |
| K-driver | DESIGN §6.2's steps: the lock waits, refuses naming the holder, and a stale lock is taken by rename; preflight refusals; the isolation; the counts and skip rules; the one-to-nine-digit rule; the facts in field order; a host whose `uname` says nothing refused | the trap is removed; the rename is replaced by a pid write; the isolation is removed; the counts are read through a pipe |
| K-shape | the driver's shell holds no function of the commit's library after `run`; a probe never runs the commit's code | the commit's library is sourced into the driver |
| K-sign-push | DESIGN §6.3 and §6.4: no passing entry refuses; the tag targets the tested commit; the sign and push lines name the platform; no `refs/tags/` name is left behind; an existing ref is "already signed"; a second push of an existing ref is success | `sign` writes the ref without the passing entry |
| K-hook | DESIGN §6.8: a failing run refuses and pushes nothing; a cached pass signs without running; every key recorded runs nothing; deletion, tag and `refs/ci/*` pushes exit 0 untouched; the environment refusal names `--no-verify`; a `ci-only` job is never keyed; a pushed commit with no `ci/kit/lib/keys.sh` says one sentence and passes | `sign` is called before the run's status is read |
| K-workflow | each rule of the workflow check (§2.3) against a fixture workflow, one failing case per rule | each rule is removed in turn |
| K-escaping | the declaration rules for any language; the Go and TypeScript scanners on a planted `../../../x` read, declared, and the same text in a comment; a test directly in its tree at depth zero; a manifest with no escaping-scan line passing with its sentence; the depth under a tree of `.` | the comment stripper is bypassed; a test directly in its tree is counted one level deep; the no-scan pass is turned back into a refusal; the depth under `.` is cut from the path's first characters |
| K-prereq | `check-prereqs`: Docker not answering, git below 2.34 and an `ssh-keygen` without `-Y` each refused with its sentence; the runner-only commands refuse bash below 4.2 | the version check is removed |
| K-launcher, K-reader, K-twokeys | the socket only to the jobs `socket` names; a pass writes the ran file from `uname` read in the image with no network and the hardening, a failure leaves none, a pass whose image names no platform exits 2; the in-image probe reader per kind; the base and job image keys apart, each with the uid | a socket is granted to `alpha`; an earlier ran file is not removed before the job (`rm -f -- "$ran"`); the `]` stripping is removed; the base's key is widened to `image-path` |
| K-update | `kit-update`'s release checks (a) to (e) of §5.3, among them a local-record tag object pushed under a release tag's name, which is refused | the `tag -v` call is removed |
| K-host | the host check of §2.2 | a `sed` is planted in `pre-push` |
| K-image, K-enter (in `tests/image`) | the base runs as its non-root user with bash 3.2.57 and `python3` and no secret-shaped `ENV`; the archive goes in by copy and a tree that is not the commit's runs nothing; a history job's pack is indexed and checked | `USER` is removed from the base; the tree comparison is removed from `enter.sh` |
| K-init | `kit-init` (the kit repository's `docs/kit-init.md`): every refusal with nothing written; offline with `--checksums` behind a closed proxy; the restore after a failed write, a CRLF Makefile byte for byte; every supported shape (Go; Node with vitest; Go, Node and Postgres; Python with pytest; a Node stub; two Go directories; no stack; a stack at `.`) generated and held to `check-manifest`, `check-workflow`, `check-escaping-reads` and the test script's unknown-job case; the example's files as the golden output; the source parsing as Python 3.9 and starting only its five commands; the agent section cited, never copied, by the kit repository's documents (that guard's cases print an info line in an adopter's tree); the security read's fixes: no write through a symbolic link, the bounded names, `-I` against a `yaml.py` at the top, exit 3 when a check did not run, the failed-commit line, a detached HEAD refused and the guess of `main` said | the link refusal is removed; the name bound is removed; the existing-file refusal is removed; the Go pin cross-check is removed from its template; the hook is copied from another path; the unreplaced-token check is disabled; the restore truncates to the decoded length; a file that is not UTF-8 is read as absent; `--checksums` is ignored |
| `initgo`, `initpy` (in `tests/image`) | `kit-init`'s Go, Node and Postgres shape and its Python with pytest shape end to end: generated with recorded checksums, the job image built, `make check` passing every job with counts above zero, `check-adapter` passing each stack job; the Python job answering with the pinned interpreter, not the base image's `python3` | the pinned Python is taken off the job image's `PATH` |
| K-flow | one end-to-end case: `run`, `sign`, `push` from the fixture clone; the plan on the fixture origin trusts `alpha`'s local record with `local: <principal>` and runs `beta`; the weekly mode ignores the local record | none: this case is the integration of the others |

### 6.3 What remains yours

1. **Your manifest:** the manifest check (§3.7) passing on your tree, and your path lists honest: each local job's key covers what its tests read. The escaping-read check finds Go and TypeScript crossings; any other crossing is a census you do by hand, written as `escaping-read` entries.
2. **Your test script:** the contract check (§4.5) and one planted failing step per section, seen to fail once, in your own harness.
3. **Your workflow:** the workflow check passing; each job's `name` equal to its id; the runner's `python3` able to `import yaml` for the check.
4. **Your host settings, confirmed on the host:** protected `main`, pull requests only, signed commits required; the skipped-required-check behaviour of DESIGN §4 item 7 confirmed with a scratch pull request; a record ref push starting no run (DESIGN §4 item 5).
5. **Your signers:** each line's fingerprint confirmed through another channel before it is committed (DESIGN §6.6).
6. **The first local record end to end** on a real workstation before a job is listed `local`: the trust check admits only what some run has shown can be produced.
7. **The weekly read** of the scheduled run's summary, by a named person or a duty you give an agent (DESIGN §6.9).

## 7. Adoption, step by step

Each step says what shows it is done. The example repository is every step done once.

| # | Step | Done when |
|---|---|---|
| 1 | **Prerequisites** (DESIGN §4): protected `main`, pull requests only, signed commits required; Actions billing per job; every job's checks expressible as one script; every tool pinned in a file a `pin-source` kind can read; every local job's tests runnable inside one job image your Dockerfile builds; a `refs/ci/*` push starts no run; the Actions settings do not cap the token below `contents: write` and `checks: read`; your remote for `main` is named `origin`; on each workstation Docker, git 2.34 or later, `ssh-keygen -Y`, the system bash and the standard Unix tools (and `make` when your check command uses it), and `python3` 3.9 or later, to run `kit-init` once; on the runner bash 4.2 or later and `python3` with PyYAML | the branch protection and the Actions settings read back; a test ref pushed and no run started; `bash <clone of the kit>/kit/bin/check-prereqs` exits 0 on each workstation (the kit is not vendored yet, so run it from a clone) |
| 2 | **Skipped required check confirmed** (DESIGN §4 item 7) | a scratch pull request whose required job is skipped by its `if:` shows it passing |
| 3 | **Vendor the kit** by §5.3: put the release signer's line (the kit repository's README.md, under "Releases and the release signer") in `ci/KIT-SIGNERS`, then run `bash <clone of the kit>/kit/bin/kit-update <tag>` from a checkout of `main`, never a branch someone else wrote. At the first vendoring `ci/KIT-SIGNERS` is the one input nothing on `main` vouches for: `kit-update` prints each line's fingerprint, and you confirm it against the published one through another channel before committing. If no fingerprint line is printed for a line of the file, stop | `ci/kit/` and `ci/KIT-VERSION` written; the fingerprint confirmation is one line of the landing pull request's description |
| 4 | **Write the files**, on the landing branch, with the generator: `python3 ci/kit/bin/kit-init --project <name>` with one `--go`, `--node` or `--python` flag per directory to test, `--postgres <job>` for each job that needs the throwaway database, and `--signer auto` to have your signer's line and fingerprint printed for step 10 (`bin/kit-init` in §1; `--checksums FILE` when the workstation is offline). It writes the manifest (§3), the test script (§4), the job image's Dockerfile on the kit's base with each toolchain's checksum for both architectures from that project's own published files, the workflow (§5.5), `.githooks/pre-push` copied from `ci/kit/hooks/pre-push.shim`, the `Makefile` target `check`, the signers file holding only its comment line (DESIGN §9), and the kit's section in `AGENTS.md` and `CLAUDE.md` (its one text is `templates/agents/section.md`), and refuses with nothing written when any of those would overwrite a file. A stack it does not know gets a stub section that refuses until you write it. By hand instead: write the same files yourself, with the example adopter's as the reference (the manifest's jobs, classes, path lists from a census of each job's reads, pins, counts and services; the allow-list empty unless a leg has been shown to be impossible on a workstation) | every file the manifest's `adapter`, `workflow`, `image` and `signers` lines name exists, and the shim; with the generator, its exit code is 0 |
| 5 | **Escaping reads**: the generator writes the scanners' lines for Go and TypeScript and says which jobs are a census by hand; the census of what the scanners cannot see is yours either way: other languages, non-test files your tests import that read files (§3.4 `escaping-scan`), computed climbs | an `escaping-read` line per crossing, and every outside path in its job's `paths` line |
| 6 | **Commit and check.** The manifest check and the two Python checks read the commit, not the working copy. The generator commits exactly its own paths (with `ci/kit/`, `ci/KIT-VERSION` and `ci/KIT-SIGNERS` when the vendoring is uncommitted) and then runs `ci/kit/bin/check-manifest`, both Python checks and `check-prereqs` itself; by hand, commit everything first and run them. Then the check command once, and `ci/kit/bin/check-adapter <job>` for every local job except the kit job (it reads that run's log) | each exits 0 (rule 7 of the manifest check among them, so the vendored tree is the release's); one planted failure per section of the test script, seen to fail once, in your own harness |
| 7 | **The trust paragraph written into your own documentation** (DESIGN §3.4, word for word, with the two facts beside it) | the paragraph committed before the first local record is trusted |
| 8 | **Required checks**: branch protection requires the always-on job and every scheme job by name (§5.5) | the protection read back |
| 9 | **The landing pull request**: merge `origin/main` into the branch, then push it with `--no-verify` before any hook is installed (DESIGN §9), opened with the sentence that its local records are refused until a signer is on `main` | its run executes every job in CI once and writes the first green records; merged |
| 10 | **Signers**: one line per key in the `signers` file, in its own pull request after the landing (with `--signer`, `kit-init` printed yours with its fingerprint and kept it in `<git common dir>/<project>-ci/init/allowed-signers.next`), the fingerprint confirmed through another channel, and the key confirmed as the one that signs that person's commits. Its run executes on CI every job whose key covers the file, because `main`'s file still names nobody | merged; `git log --show-signature`, with the file as `gpg.ssh.allowedSignersFile`, reads Good for the signer's commits |
| 11 | **Per workstation** (DESIGN §10): `core.hooksPath .githooks`, `gpg.format ssh`, `user.signingkey`, Docker running | `ci/kit/bin/check-prereqs` exits 0; the check command passes and its facts block is read once by hand |
| 12 | **First trusted push**: a branch pushed through the hook; its pull request's summary shows `local: <principal>` for each local job | the summary row seen |
| 13 | **The weekly schedule** runs on its first scheduled day | the run's summary carries the weekly sentence; its result reported the same day (DESIGN §6.9) |
| 14 | **A security review at the milestone** where you first trust a local record on `main`, if your project needs more than the kit's own review (the kit repository's `SECURITY.md`) | the review's findings dealt with, or your decision that the kit's review covers you written down |
