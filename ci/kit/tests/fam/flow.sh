# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-flow (kit/README.md §6.2): one end-to-end case, the integration of the others:
# `run`, `sign`, `push` from the fixture clone; the plan on the fixture origin
# trusts alpha's local record with `local: <principal>` and runs beta; the
# weekly mode ignores the local record.
fam_flow() {
  need_bash4 flow || return 0
  local sha key
  fx_new flow
  git -C "$FX" checkout -q -b feat; printf 'flow\n' > "$FX/src/marker.txt"; fx_commit "flow change"
  sha="$(git -C "$FX" rev-parse HEAD)"; key="$(fx_key alpha)"
  drv run --commit HEAD alpha delta kitself; rc_is "run" 0 "$DRV_RC"
  drv sign --commit HEAD alpha delta kitself; rc_is "sign" 0 "$DRV_RC"
  drv push --commit HEAD alpha delta kitself; rc_is "push" 0 "$DRV_RC"
  git -C "$FX" push -q --no-verify origin feat
  # the plan, on a fresh clone of the origin, as the runner sees it
  rm -rf "$work/runner"; git clone -q "$FXO" "$work/runner"; git -C "$work/runner" checkout -q feat
  FX="$work/runner"; unset GH_TABLE
  plan_run
  rc_is "the plan on the origin" 0 "$PLAN_RC"
  eq "alpha, delta and kitself are green on their local records; beta, gamma and the gate run" "gate=run alpha=green delta=green beta=run gamma=run kitself=green" "$(decisions)"
  has "alpha's provenance names the signer" "$work/summary" "| alpha | \`${key:0:16}\` | local record at"
  has "as local: <principal>" "$work/summary" "| local: signer-a@fixture | **green** |"
  hasnt "no job is vouched for by CI" "$work/summary" "| ci |"
  plan_run CI_PLAN_EVENT=workflow_dispatch CI_PLAN_TASK=weekly
  eq "weekly: every local record is ignored" "gate=off alpha=run delta=run beta=run gamma=run kitself=run" "$(decisions)"
  has "and each says so" "$work/stdout" "alpha: the local record for ${key:0:8} is ignored on a weekly dispatch, so alpha ran."
}
