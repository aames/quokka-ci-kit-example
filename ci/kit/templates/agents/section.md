<!-- quokka-ci-kit section begin: written by kit-init from ci/kit/templates/agents/section.md -->
## quokka-ci-kit

CI in this repository uses quokka-ci-kit, vendored at `ci/kit/`. How it works here:

- `ci/manifest` lists each CI job and the paths its key is a hash of. A job is skipped when a trusted record of its key exists, and runs otherwise.
- `@@ADAPTER@@` is each job's one verdict script, with one arm per job. CI and `@@CHECK@@` run the same script in the same job image.
- Run `@@CHECK@@` before you push. It tests the HEAD commit, not uncommitted changes, so commit first. It runs @@JOBS@@.
- The pre-push hook signs a record of each job that passed and pushes it beside the branch. Each clone needs `git config core.hooksPath .githooks` once.
- Never edit anything under `ci/kit/`. Update the kit with `bash ci/kit/bin/kit-update <tag>` from a checkout of @@MAIN@@, in a pull request of its own.
- To add a job, add its lines to `ci/manifest`, its arm to `@@ADAPTER@@` and its job to `@@WORKFLOW@@`. Commit, then run `bash ci/kit/bin/check-manifest`, `python3 ci/kit/bin/check-workflow`, `python3 ci/kit/bin/check-escaping-reads` and `@@CHECK@@`, then `bash ci/kit/bin/check-adapter <job>` once it passes.
- Never push with `--no-verify`. The only exception was the pull request that added the kit.
- Never put a secret in `ci/manifest` or `@@ADAPTER@@`. Both are committed, and the manifest refuses names that look like secrets.
- Change `@@SIGNERS@@` or `ci/KIT-SIGNERS` only when a person asks you to. Each is a trust file and changes in a reviewed pull request of its own.
- A red `@@CHECK@@` is a failing job. Fix the cause; never narrow a job's paths, change a pin or edit a count to make it pass.
<!-- quokka-ci-kit section end -->
