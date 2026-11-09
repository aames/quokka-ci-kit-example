# Rottnest quokka sightings: an example of local-evidence CI

```text
        .-"""-.
       / .===. \       zzz
       \/ = = \/       nothing to re-run tonight,
       ( \___/ )       the records say so
  ___ooo__V__ooo___
```

## Use this template

Want this for your own Go or Node repository? Click **Use this template** above, then follow the kit's [QUICKSTART.md](https://github.com/aames/quokka-ci-kit/blob/main/QUICKSTART.md): nine steps from the template to green CI in about 30 minutes, including every rename and which of `api/` and `web/` to keep.

This is a small project that records quokka sightings on Rottnest Island. It
exists to show one CI kit, [quokka-ci-kit](https://github.com/aames/quokka-ci-kit),
vendored into a real repository. The service is deliberately small; the
interesting part is what CI does around it.

It shows three things:

1. **A job is skipped when its files have already passed.** Each CI job has a
   *key*: a hash of exactly the files its result depends on, as listed in
   `ci/manifest`. When a job passes, a record of that key is kept. A change
   under `web/` changes the `web` key and leaves the `api` key alone, so the
   next run tests `web` and skips `api`.
2. **A passing `make check` on your own machine counts.** `make check` runs the
   same jobs in the same container image CI uses. When you push, the pre-push
   hook signs a record of each passing job with your SSH key and pushes it
   alongside the branch. CI checks the signature against `ci/allowed-signers`
   on `main`, recomputes the key and skips the job, so the pull request only
   runs the short `checks` job. This only works for a key listed in that file;
   a contributor's records go to their own fork, which this repository's plan
   never reads.
3. **CI double-checks the workstations every week.** Every Monday at 06:20 UTC
   a scheduled run ignores every workstation record and runs each job in CI,
   unless CI itself has already passed that exact content. A red there is a
   red `main`.

## The service

- `GET /sightings` lists every sighting, newest first.
- `POST /sightings` records one, from a body like
  `{"where":"Thomson Bay","count":2}`.

It stores sightings in Postgres (the `ROTTNEST_DATABASE_URL` variable) and
creates its one table if it is missing. `web/` formats a sighting as a
sentence, such as "Two quokkas at Thomson Bay on 3 November 2026."

## Run the checks on your machine

You need Docker running, and git. Nothing else: Go, Node and Postgres come in
the job image.

```
git config core.hooksPath .githooks
make check
```

The first run builds two images (the kit's base, then this project's Go and
Node layer) and takes several minutes; later runs reuse them. It then runs
three jobs on your `HEAD` commit, not on uncommitted changes:

- `api`: `gofmt`, `go vet` and `go test`, with a throwaway Postgres alongside;
- `web`: `npm ci`, `tsc --noEmit` and `vitest run`;
- `kit`: the vendored kit's own tests.

`make check JOBS=web` runs just the one.

## What a push does

For your passing runs to count, set up signing once:

```
git config gpg.format ssh
git config user.signingkey ~/.ssh/id_ed25519.pub
```

and add your public key to `ci/allowed-signers` in a pull request of its own.
A record only counts once that line is on `main`.

On `git push`, the hook works out each job's key for the pushed commit. A key
that already has a record needs nothing more. A key with a passing `make check`
behind it is signed and pushed. Anything else runs first, and a failure stops
the push. `git push --no-verify` skips the hook, and the pull request then runs
the jobs in CI.

In CI, the `checks` job plans the run. Its summary table lists each job with
its key, the record it found (if any), who made it, and whether the job runs.
Each record also says which platform its run was on: `linux/amd64` for one CI
wrote, and `linux/arm64` for one this Mac's `make check` signed. The table
shows that in a Platform column.

## Layout

| Path | What it is |
|---|---|
| `api/` | The Go service and its tests |
| `web/` | The TypeScript formatter and its tests |
| `ci/manifest` | The jobs, the files each job's key covers, the tool pins |
| `ci/ci-job.sh` | Every check of each job, one script for CI and `make check` alike |
| `ci/image/Dockerfile` | Go and Node on top of the kit's base image |
| `ci/allowed-signers` | The SSH keys whose local records CI trusts, read from `main` |
| `ci/kit/` | The vendored kit, unchanged; `ci/KIT-VERSION` records its release |
| `ci/KIT-SIGNERS` | The keys a kit release must be signed with |
| `.github/workflows/ci.yml` | The workflow, in the shape the kit's workflow check requires |
| `.githooks/pre-push` | The hook, a copy of the kit's |
| `Makefile` | `make check` |

## Updating the kit

```
ci/kit/bin/kit-update <tag>
```

checks that the tag is a signed release from a key in `ci/KIT-SIGNERS`,
replaces `ci/kit/` with it and rewrites `ci/KIT-VERSION`. Every key changes, so
run `make check` and open one pull request for the update.
