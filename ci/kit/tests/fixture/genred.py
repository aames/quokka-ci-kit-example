# Regenerates the red-w<N>-*.yml fixtures from green.yml; run it in fixture/workflows/ (python3 ../genred.py).
import re
g = open('green.yml').read()
def block(name):
    m = re.search(r'^  %s:\n' % name, g, re.M)
    n = re.search(r'^  [a-z]+:\n', g[m.end():], re.M)
    return m.start(), (m.end() + n.start()) if n else len(g)
def jmut(job, old, new, cnt=1):
    a, b = block(job); blk = g[a:b]
    assert old in blk, (job, old)
    return g[:a] + blk.replace(old, new, cnt) + g[b:]
def gmut(old, new, cnt=1):
    assert old in g, old
    return g.replace(old, new, cnt)
H = "# RED FIXTURE for the workflow fence (kit/README.md §2.3): green.yml with exactly one defect, %s.\n"
c = {}
c['red-w1-pull-request-target'] = ("a pull_request_target trigger", gmut("  push:\n    branches: [main]\n", "  push:\n    branches: [main]\n  pull_request_target:\n    branches: [main]\n"))
c['red-w1-path-filter'] = ("a path filter on pull_request", gmut("    types: [opened, synchronize, reopened, ready_for_review]\n", "    types: [opened, synchronize, reopened, ready_for_review]\n    paths: [\"src/**\"]\n"))
c['red-w1-wrong-cron'] = ("a cron that is not weekly-cron", gmut('cron: "40 5 * * 1"', 'cron: "41 5 * * 1"'))
c['red-w2-no-draft-refusal'] = ("no draft refusal as the always-on job's first step", jmut('gate', """      - name: Refuse a draft pull request
        if: github.event_name == 'pull_request' && github.event.pull_request.draft
        run: |
          echo "::error::This pull request is a draft, so no checks ran. Mark it ready for review to run them."
          exit 1
""", ""))
c['red-w2-skip-on-draft'] = ("an if: that skips on draft", jmut('alpha', "    if: needs.gate.outputs.alpha == 'run'\n", "    if: needs.gate.outputs.alpha == 'run' && !github.event.pull_request.draft\n"))
c['red-w3-github-sha'] = ("a checkout of github.sha instead of the plan's sha", jmut('alpha', "          ref: ${{ needs.gate.outputs.sha }}\n", "          ref: ${{ github.sha }}\n"))
c['red-w3-gate-sha-output'] = ("the always-on job's sha output not the head expression", gmut("      sha: ${{ github.event.pull_request.head.sha || github.sha }}\n", "      sha: ${{ github.sha }}\n"))
c['red-w4-no-if'] = ("a job with no if: on its plan output", jmut('alpha', "    if: needs.gate.outputs.alpha == 'run'\n", ""))
c['red-w4-record-unconditional'] = ("a record step that is not if: success()", jmut('alpha', "      - name: Record this tree green\n        if: success()\n", "      - name: Record this tree green\n"))
c['red-w5-ref-group-from-github-ref'] = ("a concurrency group built from github.ref", jmut('alpha', "      group: ci-alpha-${{ needs.gate.outputs.ref_group }}", "      group: ci-alpha-${{ github.ref }}"))
c['red-w5-workflow-level-concurrency'] = ("workflow-level concurrency", gmut("permissions:\n  contents: read\n\njobs:", "permissions:\n  contents: read\n\nconcurrency:\n  group: all\n  cancel-in-progress: true\n\njobs:"))
c['red-w6-plan-env-missing'] = ("the plan step lacking CI_PLAN_REPO", gmut("          CI_PLAN_REPO: ${{ github.repository }}\n", ""))
c['red-w6-plan-command'] = ("the plan step running another command", gmut("        run: bash ci/kit/bin/plan\n", "        run: bash scripts/my-plan\n"))
c['red-w7-services'] = ("a local job holding services:", jmut('alpha', "    steps:\n", "    services:\n      pg:\n        image: postgres\n    steps:\n"))
c['red-w7-setup-action'] = ("a local job holding a setup-* action", jmut('delta', "      - name: The job image\n", "      - uses: actions/setup-go@4b73464bb391d4059bd26b0524d20df3927bd417 # v5\n      - name: The job image\n"))
c['red-w7-container-key'] = ("a job with a container: key", jmut('beta', "    steps:\n", "    container: ubuntu:24.04\n    steps:\n"))
c['red-w7-apt-get'] = ("a local job running apt-get", jmut('kitself', "      - name: The job image\n", "      - name: Tools\n        run: sudo apt-get install -y jq\n      - name: The job image\n"))
c['red-w8-token-in-job-env'] = ("GITHUB_TOKEN in the job env, not the record step's alone", jmut('alpha', "      CIKIT_IMAGE_CACHE: gha\n", "      CIKIT_IMAGE_CACHE: gha\n      GITHUB_TOKEN: ${{ github.token }}\n"))
c['red-w8-other-writer'] = ("another step writing a refs/ci/green/ ref", jmut('beta', "      - name: The beta verdict, on the runner\n", "      - name: A second writer\n        run: git push origin HEAD:refs/ci/green/beta/x\n      - name: The beta verdict, on the runner\n"))
c['red-w9-name-differs-from-id'] = ("a job whose name is not its id", jmut('alpha', "    name: alpha\n", "    name: Alpha tests\n"))
c['red-w10-history-shallow'] = ("a history job whose checkout lacks fetch-depth: 0", jmut('delta', "          fetch-depth: 0\n", ""))
c['red-w1-workflow-run'] = ("a workflow_run trigger", gmut("  push:\n    branches: [main]\n", "  push:\n    branches: [main]\n  workflow_run:\n    workflows: [CI]\n    types: [completed]\n"))
c['red-w7-image-word'] = ("an image step naming a job word that is not the job's own id", jmut('alpha', 'container image --commit "$SHA"\n', 'container image --commit "$SHA" beta\n'))
c['red-w8-token-expression'] = ("the job token as ${{ github.token }} in a verdict step's env", jmut('alpha', "      - name: The alpha verdict\n        env:\n", "      - name: The alpha verdict\n        env:\n          TOK: ${{ github.token }}\n"))
c['red-w8-token-secrets'] = ("the job token as ${{ secrets.GITHUB_TOKEN }} in the job env", jmut('alpha', "      CIKIT_IMAGE_CACHE: gha\n", "      CIKIT_IMAGE_CACHE: gha\n      TOK: ${{ secrets.GITHUB_TOKEN }}\n"))
c['red-w8-token-bracket'] = ("the job token as ${{ github['token'] }} in the workflow env", gmut("permissions:\n  contents: read\n\njobs:", "permissions:\n  contents: read\n\nenv:\n  TOK: ${{ github['token'] }}\n\njobs:"))
c['red-w11-unpinned'] = ("an action referenced by a tag, not a sha", jmut('alpha', "uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4", "uses: actions/checkout@v4"))
c['red-w12-write'] = ("a local job holding packages: write", jmut('alpha', "    permissions:\n      contents: write\n", "    permissions:\n      contents: write\n      packages: write\n"))
for k, (why, text) in c.items():
    open(k + '.yml', 'w').write(H % why + text)
print(len(c))
