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
  has "the summary names each job, its key and why" "$work/summary" "| alpha | \`${key:0:16}\` | no record for this key | - | **run** |"
  eq "main is false when GITHUB_REF is unset" false "$(out_of main)"
  git -C "$FX" push -q --no-verify origin "$sha:refs/ci/green/alpha/$key"
  plan_run; eq "a green record without a check run is not trusted" "$all" "$(decisions)"
  has "and the summary says which check it lacked" "$work/summary" "NOT TRUSTED: no successful 'alpha' check run from github-actions on that commit"
  printf '%s|alpha|success|github-actions\n' "$sha" > "$GH_TABLE"
  plan_run; eq "a trusted green record: that job is green, the rest run" "gate=run alpha=green delta=run beta=run gamma=run kitself=run" "$(decisions)"
  has "the summary shows the record and its provenance" "$work/summary" "| alpha | \`${key:0:16}\` | record at ${sha:0:12}, trusted | ci | **green** |"
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
}
