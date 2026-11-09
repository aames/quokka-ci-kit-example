# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-plan (kit/README.md §6.2): the four modes; the schedule read as weekly
# before any record; unreadable records run everything; absent commits are
# fetched; main fetched once; `main` case-sensitive; `ref_group` and its
# `weekly-` prefix; an unknown task turns every kit job `off`; the summary's
# rows and sentences.
fam_plan() {
  need_bash4 plan || return 0
  local sha key all="gate=run alpha=run delta=run beta=run gamma=run kitself=run" a_key g1 g2
  fx_new plan
  sha="$(git -C "$FX" rev-parse HEAD)"
  key="$(fx_key alpha)"
  export GH_TABLE="$work/checks" GH_LOG="$work/gh.log"; : > "$GH_TABLE"
  plan_run
  rc_is "normal, no record" 0 "$PLAN_RC"; eq "normal, no record: every job runs" "$all" "$(decisions)"
  has "the summary names each job, its key and why" "$work/summary" "| alpha | \`${key:0:16}\` | no record for this key | - | - | **run** |"
  eq "main is false when GITHUB_REF is unset" false "$(out_of main)"
  git -C "$FX" push -q --no-verify origin "$sha:refs/ci/green/alpha/$key"
  plan_run; eq "a green record without a check run is not trusted" "$all" "$(decisions)"
  has "and the summary says which check it lacked" "$work/summary" "NOT TRUSTED: no successful 'alpha' check run from github-actions on that commit"
  printf '%s|alpha|success|github-actions\n' "$sha" > "$GH_TABLE"
  plan_run; eq "a trusted green record: that job is green, the rest run" "gate=run alpha=green delta=run beta=run gamma=run kitself=run" "$(decisions)"
  has "the summary shows the record and its provenance" "$work/summary" "| alpha | \`${key:0:16}\` | record at ${sha:0:12}, trusted | - | ci | **green** |"
  eq "a lightweight record: its platform output is empty" "" "$(out_of alpha_platform)"
  git -C "$FX" push -q --no-verify origin "$sha:refs/ci/green/delta/$(printf 'f%.0s' $(seq 1 64))"
  plan_run; eq "a record under another key is not read at all" "gate=run alpha=green delta=run beta=run gamma=run kitself=run" "$(decisions)"
  plan_run CI_PLAN_FORCE=true
  eq "force: every job runs, no record read" "$all" "$(decisions)"; has "force says so" "$work/summary" "force: every record ignored"
  # weekly, the schedule and a task dispatch
  plan_run CI_PLAN_EVENT=workflow_dispatch CI_PLAN_TASK=weekly
  eq "weekly: the always-on job is off; the rest by green record alone" "gate=off alpha=green delta=run beta=run gamma=run kitself=run" "$(decisions)"
  has "weekly: the summary's closing sentence" "$work/summary" "The weekly run (the schedule or a task: weekly dispatch) ignores every local record"
  plan_run CI_PLAN_EVENT=schedule GITHUB_REF=refs/heads/main
  eq "the schedule is read as the weekly run before any record" "gate=off alpha=green delta=run beta=run gamma=run kitself=run" "$(decisions)"
  case "$(out_of ref_group)" in weekly-refs-heads-main-*) ok "the weekly ref_group carries the weekly- prefix" ;; *) bad "the weekly ref_group is $(out_of ref_group)" ;; esac
  plan_run CI_PLAN_EVENT=workflow_dispatch CI_PLAN_TASK=nonsense
  eq "an unknown task turns every kit job off" "gate=off alpha=off delta=off beta=off gamma=off kitself=off" "$(decisions)"
  plan_run CI_PLAN_EVENT=workflow_dispatch CI_PLAN_TASK=tests
  eq "the tests task is the normal mode" "gate=run alpha=green delta=run beta=run gamma=run kitself=run" "$(decisions)"
  # unreadable records
  plan_run CI_PLAN_REMOTE=/nonexistent/remote.git
  eq "ls-remote unreadable: everything runs" "$all" "$(decisions)"; has "and says so" "$work/stdout" "the plan could not read the CI records from /nonexistent/remote.git, so every job runs."
  # main, case-sensitive; ref_group
  plan_run GITHUB_REF=refs/heads/main; eq "main is true for refs/heads/main" true "$(out_of main)"; g1="$(out_of ref_group)"
  plan_run GITHUB_REF=refs/heads/Main; eq "refs/heads/Main is not main (the shell's = is case-sensitive)" false "$(out_of main)"; g2="$(out_of ref_group)"
  check "ref_group differs for refs differing only in case" test "$g1" != "$g2"
  case "$g1" in refs-heads-main-????????????????) ok "ref_group is the lower-cased ref and 16 hex of its hash" ;; *) bad "ref_group is $g1" ;; esac
  plan_run GITHUB_REF=refs/heads/main-fix; eq "main-fix is not main" false "$(out_of main)"
  plan_run GITHUB_REF=refs/heads/MAIN; eq "MAIN is not main" false "$(out_of main)"
  plan_run GITHUB_REF=refs/pull/7/merge; eq "a pull request ref is not main" false "$(out_of main)"
  # an absent record commit is fetched
  git clone -q "$FXO" "$work/clone2" && git -C "$work/clone2" -c user.email=a@b -c user.name=n commit -q --allow-empty -m other
  git -C "$work/clone2" push -q --no-verify origin "HEAD:refs/ci/green/delta/$(fx_key delta)"
  other="$(git -C "$work/clone2" rev-parse HEAD)"
  printf '%s|delta|success|github-actions\n' "$other" >> "$GH_TABLE"
  plan_run; eq "a record commit this checkout lacks is fetched and its key recomputed" "gate=run alpha=green delta=green beta=run gamma=run kitself=run" "$(decisions)"
  # local records
  lfacts "$work/f"; lrec alpha "$key" "$work/f" a > /dev/null
  git -C "$FX" push -q --no-verify origin "refs/ci/local/alpha/$key:refs/ci/local/alpha/$key"
  git -C "$FX" push -q --no-verify origin --delete "refs/ci/green/alpha/$key"
  plan_run
  eq "a trusted local record skips alpha and names its signer" "gate=run alpha=green delta=green beta=run gamma=run kitself=run" "$(decisions)"
  has "provenance is local: <principal>" "$work/summary" "local: signer-a@fixture"
  eq "main's tip is fetched once for the local arm" 1 "$(grep -c 'refs/heads/main:refs/remotes/origin/main' "$work/git.log")"
  plan_run CI_PLAN_EVENT=workflow_dispatch CI_PLAN_TASK=weekly
  eq "weekly: the local record is ignored" "gate=off alpha=run delta=green beta=run gamma=run kitself=run" "$(decisions)"
  has "weekly: with its sentence" "$work/stdout" "alpha: the local record for ${key:0:8} is ignored on a weekly dispatch, so alpha ran."
  eq "weekly: main's tip is not fetched for a record it will ignore" 0 "$(grep -c 'refs/heads/main:refs/remotes/origin/main' "$work/git.log")"
  plan_run CI_PLAN_FORCE=true; eq "force: the local record is ignored too" "$all" "$(decisions)"
  a_key="$(fx_key beta)"; lfacts "$work/f" 's/^job alpha/job beta/'
  lrec beta "$a_key" "$work/f" a > /dev/null; git -C "$FX" push -q --no-verify origin "refs/ci/local/beta/$a_key:refs/ci/local/beta/$a_key"
  plan_run; has "a CI-only job's local ref is looked up only to be refused in its own sentence" "$work/stdout" "beta: the local record for ${a_key:0:8} is for a job that records only in CI, so beta ran."
  eq "and beta still runs" "gate=run alpha=green delta=green beta=run gamma=run kitself=run" "$(decisions)"
  unset GH_TABLE GH_LOG
  fam_plan_platform
}

# The platform (DESIGN.md 5.2 to 5.4, 6.7): a tag-object green record is
# peeled, its facts checked, its platform shown in the note, the table and the
# output; a trusted local record shows its own; a tag-object record the
# checkout lacks is fetched whole at depth 1.
fam_plan_platform() {
  local sha key obj other okey lobj
  fx_new plan2
  sha="$(git -C "$FX" rev-parse HEAD)"; key="$(fx_key alpha)"
  export GH_TABLE="$work/checks" GH_LOG="$work/gh.log"
  printf '%s|alpha|success|github-actions\n%s|beta|success|github-actions\n' "$sha" "$sha" > "$GH_TABLE"
  gfacts "$work/g" alpha; obj="$(grec alpha "$key" "$work/g")"
  git -C "$FX" push -q --no-verify origin "refs/ci/green/alpha/$key:refs/ci/green/alpha/$key"
  plan_run
  eq "a tag-object green record is trusted on its peeled commit's check run" "gate=run alpha=green delta=run beta=run gamma=run kitself=run" "$(decisions)"
  has "its row names the tag object, the platform and ci" "$work/summary" "| alpha | \`${key:0:16}\` | record at ${obj:0:12}, trusted, linux/amd64 | linux/amd64 | ci | **green** |"
  eq "and its platform is an output" linux/amd64 "$(out_of alpha_platform)"
  eq "a job that runs has an empty platform output" "" "$(out_of delta_platform)"
  has "the table's header has the Platform column between Record and Provenance" "$work/summary" "| Job | Key | Record | Platform | Provenance | Decision |"
  check "the check run was looked up on the commit, not the tag object" grep -q "commits/${sha}/check-runs?check_name=alpha" "$work/gh.log"
  gfacts "$work/g" alpha "s/^commit .*/commit $(printf '0%.0s' $(seq 1 40))/"; obj="$(grec alpha "$key" "$work/g")"
  git -C "$FX" push -q --no-verify -f origin "refs/ci/green/alpha/$key:refs/ci/green/alpha/$key"
  plan_run
  eq "a tag-object record whose facts name another commit is not trusted" "gate=run alpha=run delta=run beta=run gamma=run kitself=run" "$(decisions)"
  has "with its own sentence" "$work/summary" "record at ${obj:0:12} NOT TRUSTED: its facts' job, key or commit differ from its ref and its commit"
  gfacts "$work/g" alpha "s|^platform .*|platform darwin/arm64|"; obj="$(grec alpha "$key" "$work/g")"
  git -C "$FX" push -q --no-verify -f origin "refs/ci/green/alpha/$key:refs/ci/green/alpha/$key"
  plan_run
  eq "a local job's tag-object record whose platform is not linux is not trusted" "gate=run alpha=run delta=run beta=run gamma=run kitself=run" "$(decisions)"
  has "with its own sentence" "$work/summary" "record at ${obj:0:12} NOT TRUSTED: it records the platform darwin/arm64, and a local job's verdict runs in its image on linux/amd64 or linux/arm64"
  gfacts "$work/g" alpha "s/^kitfix-green v1/kitfix-green v2/"; obj="$(grec alpha "$key" "$work/g")"
  git -C "$FX" push -q --no-verify -f origin "refs/ci/green/alpha/$key:refs/ci/green/alpha/$key"
  plan_run
  has "a tag-object record in another format is not trusted" "$work/summary" "record at ${obj:0:12} NOT TRUSTED: its facts are not in the kitfix-green v1 format"
  gfacts "$work/g" beta "s|^platform .*|platform darwin/arm64|; s|^image .*|image none|"; obj="$(grec beta "$(fx_key beta)" "$work/g")"
  git -C "$FX" push -q --no-verify origin "refs/ci/green/beta/$(fx_key beta):refs/ci/green/beta/$(fx_key beta)"
  plan_run
  has "a ci-only job's record, made on the runner itself, is trusted on any platform" "$work/summary" "| beta | \`$(fx_key beta | cut -c1-16)\` | record at ${obj:0:12}, trusted, darwin/arm64 | darwin/arm64 | ci | **green** |"
  gfacts "$work/g" beta "s|^platform .*|platform msys_nt-10.0-19045/amd64|; s|^image .*|image none|"; obj="$(grec beta "$(fx_key beta)" "$work/g")"
  git -C "$FX" push -q --no-verify -f origin "refs/ci/green/beta/$(fx_key beta):refs/ci/green/beta/$(fx_key beta)"
  plan_run
  has "a ci-only job's record from a Windows runner (Git Bash's uname) is trusted with its platform" "$work/summary" "| beta | \`$(fx_key beta | cut -c1-16)\` | record at ${obj:0:12}, trusted, msys_nt-10.0-19045/amd64 | msys_nt-10.0-19045/amd64 | ci | **green** |"
  eq "and its platform is an output" msys_nt-10.0-19045/amd64 "$(out_of beta_platform)"
  gfacts "$work/g" beta "s|^platform .*|platform Darwin arm64|; s|^image .*|image none|"; obj="$(grec beta "$(fx_key beta)" "$work/g")"
  git -C "$FX" push -q --no-verify -f origin "refs/ci/green/beta/$(fx_key beta):refs/ci/green/beta/$(fx_key beta)"
  plan_run
  eq "a ci-only job's record whose platform is out of shape is not trusted" "gate=run alpha=run delta=run beta=run gamma=run kitself=run" "$(decisions)"
  has "with the sentence that names the platform it records" "$work/summary" "record at ${obj:0:12} NOT TRUSTED: it records the platform Darwin arm64, which is not of the shape <os>/<arch>"
  # a trusted local record shows its platform
  git -C "$FX" push -q --no-verify origin --delete "refs/ci/green/alpha/$key"
  lfacts "$work/f"; lobj="$(lrec alpha "$key" "$work/f" a)"
  git -C "$FX" push -q --no-verify origin "refs/ci/local/alpha/$key:refs/ci/local/alpha/$key"
  plan_run
  has "a trusted local record's row names its platform" "$work/summary" "| alpha | \`${key:0:16}\` | local record at ${lobj:0:12}, trusted, linux/arm64 | linux/arm64 | local: signer-a@fixture | **green** |"
  eq "and its platform is an output" linux/arm64 "$(out_of alpha_platform)"
  # a tag-object record the depth-1 checkout lacks: the fetch by its ref brings the tag and its commit
  git clone -q "$FXO" "$work/clone3" && git -C "$work/clone3" -c user.email=a@b -c user.name=n commit -q --allow-empty -m other3
  other="$(git -C "$work/clone3" rev-parse HEAD)"; okey="$(fx_key delta)"
  { printf 'kitfix-green v1\njob delta\nkey %s\ncommit %s\nplatform linux/arm64\nhost linux/amd64\nimage sha256:%s\n' "$okey" "$other" "$(printf 'cd%.0s' $(seq 1 32))"; } > "$work/g3"
  obj="$(grec delta "$okey" "$work/g3" "$work/clone3")"
  git -C "$work/clone3" push -q --no-verify origin "refs/ci/green/delta/$okey:refs/ci/green/delta/$okey"
  printf '%s|delta|success|github-actions\n' "$other" >> "$GH_TABLE"
  check "(the checkout lacks that commit)" test -z "$(git -C "$FX" cat-file -t "$other" 2> /dev/null)"
  plan_run
  has "a tag-object record this checkout lacks is fetched with its commit and trusted" "$work/summary" "| delta | \`${okey:0:16}\` | record at ${obj:0:12}, trusted, linux/arm64 | linux/arm64 | ci | **green** |"
  check "by one depth-1 fetch of its ref" grep -q -- "fetch -q --no-tags --depth=1 origin refs/ci/green/delta/$okey" "$work/git.log"
  unset GH_TABLE GH_LOG
}
