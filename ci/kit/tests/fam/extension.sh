# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-extension (kit/README.md §6.2, §4.4): an extension adding a job's decision
# passes; one changing a kit job's decision fails red with the sentence.
ext_run() { # ext_run <extension body>
  fx_reset
  printf '%s\n' "$1" > "$FX/ci/plan-extension.sh"; fx_commit ext
  plan_run
}
fam_extension() {
  need_bash4 extension || return 0
  fx_new ext
  ext_run 'kit_decide extra run "added by the extension" "-"
kit_output stacks "one two"
kit_summary_row extra - "a further row" - run'
  rc_is "an extension that adds a job's decision passes" 0 "$PLAN_RC"
  has "its decision is an output" "$work/out" "extra=run"
  has "its output is written" "$work/out" "stacks=one two"
  has "its row is in the summary" "$work/summary" "| extra | - | added by the extension | - | - | **run** |"
  has "its further row is too" "$work/summary" "| extra | - | a further row | - | - | **run** |"
  ext_run 'KIT_DECISION[alpha]=off'
  rc_is "an extension that sets a kit job's decision directly" 1 "$PLAN_RC"
  has "fails red with the sentence" "$work/stdout" "::error::The plan extension changed the decision of alpha, which is the kit's to make, so nothing ran."
  ext_run 'kit_decide alpha off "no"'
  rc_is "an extension that calls kit_decide on a kit job" 1 "$PLAN_RC"
  has "fails with the same sentence" "$work/stdout" "The plan extension changed the decision of alpha, which is the kit's to make, so nothing ran."
  ext_run 'kit_output alpha_key x'
  rc_is "an extension writing a kit output name" 1 "$PLAN_RC"
  has "is refused as the kit's" "$work/stdout" "the plan extension wrote the output alpha_key, which is the kit's, so nothing ran."
  ext_run 'kit_output alpha_platform linux/arm64'
  rc_is "an extension writing a kit platform output" 1 "$PLAN_RC"
  has "is refused as the kit's" "$work/stdout" "the plan extension wrote the output alpha_platform, which is the kit's, so nothing ran."
  ext_run 'platform[alpha]=linux/riscv64'
  rc_is "an extension changing the plan's own platform[alpha]" 0 "$PLAN_RC"
  has "the platform output is still the snapshot's" "$work/out" "alpha_platform="
  hasnt "and never the changed one" "$work/out" "riscv64"
  ext_run 'kit_decide Bad_Name run x'
  rc_is "an extension deciding a job named out of shape" 1 "$PLAN_RC"
  # the snapshot holds keys too, and a kit job's outputs come from it (the security review, SECURITY.md)
  ext_run 'KIT_KEY[alpha]=0000'
  rc_is "an extension setting KIT_KEY[alpha]" 1 "$PLAN_RC"
  has "fails with the key's sentence" "$work/stdout" "::error::The plan extension changed the key of alpha, which is the kit's to compute, so nothing ran."
  ext_run 'key[alpha]=0000'
  rc_is "an extension setting the plan's own key[alpha]" 1 "$PLAN_RC"
  has "fails with the key's sentence too" "$work/stdout" "The plan extension changed the key of alpha, which is the kit's to compute, so nothing ran."
  ext_run 'decision[alpha]=off; note[alpha]="forged note"'
  rc_is "an extension changing the plan's own decision[alpha] and note[alpha], leaving KIT_DECISION" 0 "$PLAN_RC"
  has "the output is still the snapshot's decision" "$work/out" "alpha=run"
  hasnt "and never the changed one" "$work/out" "alpha=off"
  hasnt "the summary row is the snapshot's too" "$work/summary" "forged note"
  fx_reset; git -C "$FX" rm -q ci/plan-extension.sh; fx_commit "no extension file"
  plan_run; rc_is "a manifest naming an extension that is not in the tree" 1 "$PLAN_RC"
  has "says so" "$work/stdout" "ci/manifest names ci/plan-extension.sh as the plan extension, which is not in this tree, so nothing ran."
}
