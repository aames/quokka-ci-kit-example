# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-workflow (kit/README.md §6.2, §2.3): each rule of the fence against a
# fixture workflow, one red case per rule leg; the adopter shape green; the
# fence run in its two modes.
# wf_red <fixture> <rule> <fragment>: run mode on that red fixture exits 1 and names the rule and the defect.
wf_red() {
  local rc=0
  cp "$KITT_FIX/workflows/$1.yml" "$work/wfroot/.github/workflows/ci.yml"
  "$PYYAML" "$KITT_KIT/bin/check-workflow" --root "$work/wfroot" --manifest-file "$KITT_FIX/manifest" > "$work/o" 2>&1 || rc=$?
  rc_is "$1 in run mode" 1 "$rc"
  has "$1 names $2" "$work/o" "$2"
  has "$1 names its defect" "$work/o" "$3"
}
fam_workflow() {
  local rc f n
  if [ -z "$PYYAML" ]; then note_not_run tests/run:pyyaml "no python3 here has PyYAML, so the workflow fence cannot read YAML"; return 0; fi
  rc=0; "$PYYAML" "$KITT_KIT/bin/check-workflow" --fixture "$KITT_FIX/workflows" > "$work/o" 2>&1 || rc=$?
  rc_is "the fence's fixtures behave: green*.yml green, red-w<N>-*.yml red on W-<N>" 0 "$rc"
  has "and the fence says so" "$work/o" "The workflow fence's fixtures behave"
  for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
    f=""; for g in "$KITT_FIX"/workflows/red-w"$n"-*.yml; do [ -e "$g" ] && { f="$g"; break; }; done
    check "W-$n has a red fixture" test -n "$f"
    if [ -n "$f" ]; then has "W-$n: its red case is seen red" "$work/o" "$(basename "$f"): red on W-$n as expected"; fi
  done
  # a red fixture alone, against the real run mode: the finding names the rule
  mkdir -p "$work/wfroot/.github/workflows"
  cp "$KITT_FIX/workflows/red-w9-name-differs-from-id.yml" "$work/wfroot/.github/workflows/ci.yml"
  rc=0; "$PYYAML" "$KITT_KIT/bin/check-workflow" --root "$work/wfroot" --manifest-file "$KITT_FIX/manifest" > "$work/o" 2>&1 || rc=$?
  rc_is "run mode on a workflow with a defect" 1 "$rc"; has "names W-9" "$work/o" "W-9"
  has "and the verdict" "$work/o" "The workflow fence FAILED"
  # each new rule's red fixture, in run mode, finds its own defect by name
  wf_red red-w1-workflow-run W-1 "carries a workflow_run trigger"
  wf_red red-w7-image-word W-7 "alpha's step 'The job image' is not the checkout"
  wf_red red-w8-token-expression W-8 "is given the job token as TOK"
  wf_red red-w8-token-secrets W-8 "job env TOK carries the job token"
  wf_red red-w8-token-bracket W-8 "the workflow env TOK carries the job token"
  wf_red red-w11-unpinned W-11 "uses actions/checkout@v4, not pinned by a 40-hex commit sha"
  wf_red red-w12-write W-12 "permissions hold packages: write; a scheme job writes contents at most"
  cp "$KITT_FIX/workflows/green.yml" "$work/wfroot/.github/workflows/ci.yml"
  rc=0; "$PYYAML" "$KITT_KIT/bin/check-workflow" --root "$work/wfroot" --manifest-file "$KITT_FIX/manifest" > "$work/o" 2>&1 || rc=$?
  rc_is "run mode on the adopter shape" 0 "$rc"; has "says OK" "$work/o" "OK: .github/workflows/ci.yml keeps the kit's scheme rules W-1 to W-12 for the manifest's 6 jobs."
  mkdir -p "$work/emptyfx"
  rc=0; "$PYYAML" "$KITT_KIT/bin/check-workflow" --fixture "$work/emptyfx" --manifest-file "$KITT_FIX/manifest" > "$work/o" 2>&1 || rc=$?
  rc_is "a fixture directory with no workflow proves nothing and says so" 2 "$rc"
  # no job name of the kit's own project in the fence's text
  check "the fence's text names no job of any project" test "$(grep -ci 'backend\|frontend\|deployfiles\|obsharness' "$KITT_KIT/bin/check-workflow")" -eq 0
}
