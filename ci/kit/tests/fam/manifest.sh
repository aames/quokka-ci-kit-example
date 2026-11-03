# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-manifest (kit/README.md §6.2): every refusal of kit/README.md §3.1 to §3.4
# with its line number, by a one-line mutation of the fixture, and the lint's
# rules 2 to 12 on a fixture repository, each by its own mutation.

# refusal <label> <sed expression> <exit> <expected sentence fragment>
refusal() {
  local label="$1" expr="$2" want_rc="$3" want="$4" rc=0
  sed -e "$expr" "$KITT_FIX/manifest" > "$work/m"
  "$BASH" "$KITT_KIT/bin/check-manifest" --file "$work/m" --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "$label" "$want_rc" "$rc"
  has "$label: the sentence" "$work/o" "$want"
}

fam_manifest() {
  local rc=0 reserved
  "$BASH" "$KITT_KIT/bin/check-manifest" --file "$KITT_FIX/manifest" --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "the fixture manifest is accepted" 0 "$rc"
  # 3.1 and the shapes
  printf '\xef\xbb\xbfmanifest v1\n' > "$work/bom"; tail -n +2 "$KITT_FIX/manifest" >> "$work/bom"
  rc=0; "$BASH" "$KITT_KIT/bin/check-manifest" --file "$work/bom" --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "a byte order mark is refused" 2 "$rc"; has "the BOM sentence names line 1" "$work/o" "line 1: the file starts with a byte order mark"
  sed 's/$/\r/' "$KITT_FIX/manifest" > "$work/crlf"
  rc=0; "$BASH" "$KITT_KIT/bin/check-manifest" --file "$work/crlf" --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "CRLF line ends are refused" 2 "$rc"; has "the CRLF sentence" "$work/o" "carriage return"
  refusal "the first directive is not manifest" 's/^manifest v1/project early/' 2 "line 6: the first directive is project"
  refusal "a newer manifest version names both" 's/^manifest v1/manifest v2/' 2 "the manifest is manifest v2, which this kit (manifest v1) does not read."
  refusal "an unknown directive" 's/^prune-days 30/prune-daze 30/' 2 "line 19: prune-daze is not a directive of manifest v1."
  refusal "a repeated singular directive" 's/^prune-days 30/user 1002/' 2 "user appears twice, and line"
  refusal "a job declared twice" 's/^job beta ci-only/job alpha local/' 2 "job alpha is declared twice"
  refusal "a per-job directive naming an undeclared job" 's/^count delta harnesses/count delta2 harnesses/' 2 "count names delta2, which no job line declares."
  refusal "a job with no paths line" 's/^paths gamma .*/# gone/' 2 "job gamma has no paths line."
  refusal "a missing required directive" 's/^check-command make check/# gone/' 2 "the manifest ends without a check-command line."
  for reserved in prepare probe-after-prepare docker client-major client-bin-env; do
    refusal "the reserved word $reserved" "s/^prune-days 30/$reserved x/" 2 "$reserved is reserved for a later kit release, so nothing ran."
  done
  refusal "project shape" 's/^project kitfix/project Kitfix/' 2 "project takes one word of 2 to 16 lower-case"
  refusal "key-epoch bounds (0)" 's/^key-epoch 1/key-epoch 0/' 2 "key-epoch takes one INTEGER from 1 to 999"
  refusal "key-epoch bounds (1000)" 's/^key-epoch 1/key-epoch 1000/' 2 "key-epoch takes one INTEGER from 1 to 999"
  refusal "user below 1000" 's/^user 1001/user 999/' 2 "user takes one INTEGER from 1000 to 65533"
  refusal "a PATH with .. in it" 's#^adapter ci/adapter.sh#adapter ../adapter.sh#' 2 "adapter takes one PATH"
  refusal "a PATH with a trailing slash" 's#^image-path ci/image #image-path ci/image/ #' 2 "image-path takes one or more PATHs"
  refusal "a weekly-cron of four words" 's/^weekly-cron 40 5 \* \* 1/weekly-cron 40 5 * */' 2 "weekly-cron takes the five fields"
  refusal "a service image with no digest" 's/@sha256:[0-9a-f]*//' 2 "service takes a job NAME, a KIND, then image"
  refusal "a probe whose BINARY starts with a dash" 's/^probe go first-line go env GOVERSION/probe go first-line -x/' 2 "probe takes a TOOL, a KIND"
  refusal "an escaping-read with three fields" 's#^escaping-read alpha|src/web/x.test.ts|NONE|.*#escaping-read alpha|src/web/x.test.ts|NONE#' 2 "escaping-read takes one ENTRY"
  refusal "a pin-source of an unknown shape" 's/^pin-source go toolchain-line src\/go.mod/pin-source go toolchain-line/' 2 "pin-source takes a TOOL or *, a KIND and a PATH."
  refusal "a count line naming no field" 's/^count delta harnesses/count delta/' 2 "count takes a job NAME and one or more FIELDs."
  refusal "a probe named twice for one tool" 's/^probe go first-line go env GOVERSION/&\nprobe go first-line go env GOVERSION/' 2 "probe names go twice"
  refusal "paths named twice for one job" 's/^paths kitself ci/&\npaths kitself ci/' 2 "paths names kitself twice"
  # a PATH holds no glob or pathspec character and no leading dash (the security review, SECURITY.md)
  refusal "paths with a star" 's#^paths gamma .*#paths gamma *#' 2 "paths takes a job NAME and one or more PATHs."
  refusal "paths with a bracket class" 's#^paths gamma .*#paths gamma src/[ab]#' 2 "paths takes a job NAME and one or more PATHs."
  refusal "paths with a pathspec magic word" 's#^paths gamma .*#paths gamma :(glob)x#' 2 "paths takes a job NAME and one or more PATHs."
  refusal "paths with a leading dash" 's#^paths gamma .*#paths gamma -x#' 2 "paths takes a job NAME and one or more PATHs."
  refusal "paths with a question mark" 's#^paths gamma .*#paths gamma sr?#' 2 "paths takes a job NAME and one or more PATHs."
  refusal "paths with a backslash" 's#^paths gamma .*#paths gamma a\\b#' 2 "paths takes a job NAME and one or more PATHs."
  refusal "image-path with a leading dash" 's#^image-path .*#image-path -x#' 2 "image-path takes one or more PATHs."
  refusal "a service image whose name leads with a dash" "s#image postgres:18@sha256#image -v@sha256#" 2 "service takes a job NAME, a KIND"
  # the kit's own two names cannot name a job (the security review, SECURITY.md)
  refusal "job image local" 's/^job beta ci-only/job image local/' 2 "image is the kit's own name, so it cannot name a job."
  refusal "job base local" 's/^job beta ci-only/job base local/' 2 "base is the kit's own name, so it cannot name a job."
  # the reserved environment list, one constant (the security review, SECURITY.md)
  for reserved in ACTIONS_RUNTIME_TOKEN RUNNER_TEMP GH_TOKEN GIT_DIR SSH_AUTH_SOCK DOCKER_HOST NPM_TOKEN DEPLOY_KEY DB_PASSWORD CIKIT_TREE PATH HOME; do
    refusal "env $reserved" "s/^env alpha GO_TEST_COUNT/env alpha $reserved/" 2 "env names $reserved, which the kit reserves, so it is never passed into a job."
  done
  # CI is reserved, a rule-1 refusal naming the line (DESIGN.md §6.2, kit/README.md §2.2)
  refusal "CI=true (d): env CI" "s/^env alpha GO_TEST_COUNT/env alpha CI/" 2 "env names CI, which the kit reserves, so it is never passed into a job."
  has "CI=true (d): naming the line" "$work/o" "line $(grep -n '^env alpha GO_TEST_COUNT' "$KITT_FIX/manifest" | cut -d: -f1): env names CI"
  sed 's/^env alpha GO_TEST_COUNT/env alpha GO_TEST_COUNT MY_FLAG/' "$KITT_FIX/manifest" > "$work/m"
  rc=0; "$BASH" "$KITT_KIT/bin/check-manifest" --file "$work/m" --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "GO_TEST_COUNT and an ordinary name are accepted" 0 "$rc"
  # the facts block's names are never a TOOL or a FIELD (the security review, SECURITY.md)
  for reserved in docker image; do
    refusal "pin alpha $reserved" "s/^pin alpha go node/pin alpha go $reserved/" 2 "$reserved is the kit's own name, so it cannot name a tool."
  done
  refusal "count alpha key" 's/^count alpha unit_tests integration_tests/count alpha key/' 2 "key is the kit's own name, so it cannot name a count."
  refusal "count alpha log_sha256" 's/^count alpha unit_tests integration_tests/count alpha unit_tests log_sha256/' 2 "log_sha256 is the kit's own name, so it cannot name a count."
  refusal "a probe for the tool docker" 's/^probe go first-line go env GOVERSION/probe docker first-line docker --version/' 2 "docker is the kit's own name, so it cannot name a tool."
  sed 's/^pin alpha go node/pin alpha go node docker-cli/' "$KITT_FIX/manifest" > "$work/m"
  rc=0; "$BASH" "$KITT_KIT/bin/check-manifest" --file "$work/m" --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "pin alpha docker-cli is accepted" 0 "$rc"
  # the lint, rules 2 to 12, on a fixture repository
  fx_new lint
  rc=0; KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/check-manifest" --commit HEAD > "$work/o" 2>&1 || rc=$?
  rc_is "the fixture repository holds rules 1 to 12" 0 "$rc"
  has "and says so" "$work/o" "holds rules 1 to 12."
  lint_rule 2 "two always-on jobs" 's/^job beta ci-only/job beta always-on/' "the manifest declares 2 always-on jobs"
  lint_rule 2 "a local job with no count" 's/^count delta harnesses/# gone/' "job delta is local and has no count line."
  lint_rule 2 "the kit job with other paths" 's/^paths kitself ci/paths kitself ci tools.sh/' "the kit job kitself has paths other than exactly ci."
  lint_rule 2 "the kit job named by a pin" 's/^pin delta shellcheck python/&\npin kitself go/' "pin names the kit job kitself"
  lint_rule 3 "a job whose key lacks ci/kit" 's/^paths alpha src deploy\/tool.sh Makefile .github\/workflows\/ci.yml ci tools.sh/paths alpha src deploy\/tool.sh Makefile .github\/workflows\/ci.yml ci\/manifest ci\/adapter.sh ci\/allowed-signers ci\/image tools.sh/' "the key of alpha does not cover ci/kit"
  lint_rule 4 "a pin source its job's key does not cover" 's#^pin-source node first-line src/web/.nvmrc#pin-source node first-line elsewhere/.nvmrc#' "pin-source reads node's pin from elsewhere/.nvmrc, which the key of alpha does not cover"
  lint_rule 5 "a signers file no local key covers" 's#^signers ci/allowed-signers#signers keys/signers#' "signers names keys/signers, which no local job's key covers."
  lint_rule 6 "an escaping-read outside its job's tree" 's#^escaping-read alpha|src/a/a_test.go|#escaping-read alpha|obs/x_test.go|#' "which is not inside an escaping-tree of alpha."
  lint_rule 6 "an escaping-read whose outside path the key lacks" 's#^escaping-read alpha|src/a/a_test.go|deploy/tool.sh|#escaping-read alpha|src/a/a_test.go|docs/x.md|#' "which the key of alpha does not cover"
  lint_rule 6 "an escaping-tree that does not exist" 's#^escaping-tree beta obs#escaping-tree beta nothere#' "escaping-tree names nothere, which does not exist"
  # AC-KI-32 (docs/kit-init.md rev 2, R-2 item 1): a path of . exists at every commit
  fx_reset
  sed -e 's#^escaping-tree beta obs#escaping-tree beta .#' -e 's#^escaping-scan go src$#escaping-scan go .#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  git -C "$FX" commit -qam "rule 6 dot"
  rc=0; KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/check-manifest" --commit HEAD --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "rule 6, an escaping-tree and an escaping-scan of . (AC-KI-32)" 0 "$rc"
  hasnt "rule 6, a path of . is not called missing (AC-KI-32)" "$work/o" "names ., which does not exist at"
  lint_rule 9 "an image-path no local key covers" 's#^image-path ci/image tools.sh src/go.mod#image-path ci/image tools.sh src/go.mod extra/dir#' "image-path names extra/dir"
  lint_rule 9 "an image outside every image-path" 's#^image ci/image/Dockerfile#image ci/Dockerfile#' "image names ci/Dockerfile, which is under no image-path PATH."
  lint_rule 9 "a socket naming a CI-only job" 's#^socket delta#socket beta#' "socket names beta, which is not a local job."
  lint_rule 10 "a probe for a tool nobody pins" 's#^probe python python-minor python3#&\nprobe cosign version-flag#' "probe names cosign, which no job pins."
  lint_rule 10 "an env var a service's url-env sets" 's#^env alpha GO_TEST_COUNT#env alpha KITFIX_TEST_PG_URL#' "which a service's url-env sets."
  lint_rule 12 "a weekly minute of 0" 's#^weekly-cron 40 5#weekly-cron 0 5#' "weekly-cron runs at minute 0"
  lint_rule 12 "prune-keep-green naming a job nobody declares" 's#^prune-keep-green gate alpha delta kitself#prune-keep-green gate nobody#' "prune-keep-green names nobody"
  lint_rule 11 "an adapter that is not a file" 's#^adapter ci/adapter.sh#adapter ci/nothere.sh#' "adapter names ci/nothere.sh, which is not a file"
  # a socket job takes no install and no service (the security review, SECURITY.md)
  lint_rule 9 "an install on the socket job" 's#^cache delta gomod#&\ninstall delta npm-ci src/web#' "install names delta, which holds the socket"
  lint_rule 9 "a service on the socket job" "s#^socket delta#&\nservice delta postgres image postgres:18@sha256:$(printf 'ab%.0s' $(seq 1 32)) url-env KITFIX_DELTA_URL#" "service names delta, which holds the socket"
  # the always-on job's key covers the kit, the manifest and the workflow (the security review, SECURITY.md)
  lint_rule 3 "an always-on job whose paths are src alone" 's#^paths gate \.#paths gate src#' "the key of the always-on job gate does not cover ci/kit"
  # a pin no pin-source line and no * line covers
  lint_rule 4 "a pin with no source once the * line is gone" '/^pin-source \* /d' "pin names shellcheck for delta, which no pin-source line sources and no * line covers (rule 4)."
  # rules 7, 8 and 9's image file read the tree, not the manifest
  fx_reset
  printf '# a drift\n' >> "$FX/ci/kit/lib/keys.sh"; fx_commit drift
  rc=0; KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/check-manifest" --commit HEAD > "$work/o" 2>&1 || rc=$?
  rc_is "rule 7: a vendored ci/kit that differs from KIT-VERSION's tree" 1 "$rc"; has "rule 7 sentence" "$work/o" "where ci/KIT-VERSION names"
  rc=0; KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/check-manifest" --commit HEAD --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "rule 7 is skipped by --no-vendor-check, and says so" 0 "$rc"; has "the skip is stated" "$work/o" "rule 7 did not run"
  fx_reset
  printf '#!/bin/sh\necho different\n' > "$FX/.githooks/pre-push"; fx_commit hook
  rc=0; KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/check-manifest" --commit HEAD > "$work/o" 2>&1 || rc=$?
  rc_is "rule 8: a hook that is not the shim" 1 "$rc"; has "rule 8 sentence" "$work/o" "is not byte-equal to ci/kit/hooks/pre-push.shim (rule 8, kit/README.md §2.4)."
  fx_reset
  printf 'ARG CIKIT_BASE\nFROM ${CIKIT_BASE}\nFROM debian:trixie-slim\n' > "$FX/ci/image/Dockerfile"; fx_commit from
  rc=0; KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/check-manifest" --commit HEAD --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "rule 9: a FROM that names no digested image" 1 "$rc"; has "rule 9 FROM sentence" "$work/o" "names no digested image"
  fx_reset
  # COPY --from=, RUN --mount from= and # syntax= name a stage or a digested image (the security review, SECURITY.md)
  h64="$(printf 'ab%.0s' $(seq 1 32))"
  image_case "COPY --from= a tag" 1 "COPY --from=debian:trixie names neither an earlier stage nor a digested image (rule 9)" 'COPY --from=debian:trixie /x /x'
  image_case "RUN --mount from= a tag" 1 "names neither an earlier stage nor a digested image (rule 9)" 'RUN --mount=type=bind,from=alpine,target=/m true'
  image_case "# syntax= a tag" 1 "# syntax=docker/dockerfile:1 names no digested image" '# syntax=docker/dockerfile:1'
  image_case "COPY --from= an unknown stage name" 1 "COPY --from=tools names neither an earlier stage nor a digested image" 'COPY --from=tools /x /x'
  image_case "COPY --from= a digested image (the control)" 0 "holds rules 1 to 6 and 8 to 12" "COPY --from=debian:trixie@sha256:$h64 /x /x"
  image_case "COPY --from= an earlier stage (the control)" 0 "holds rules 1 to 6 and 8 to 12" "FROM debian@sha256:$h64 AS tools
COPY --from=tools /x /x"
  image_case "COPY --from= the stage by its index (the control)" 0 "holds rules 1 to 6 and 8 to 12" "COPY --from=0 /x /x"
  image_case "RUN --mount from= a digested image (the control)" 0 "holds rules 1 to 6 and 8 to 12" "RUN --mount=type=bind,from=alpine@sha256:$h64,target=/m true"
  image_case "# syntax= a digested frontend (the control)" 0 "holds rules 1 to 6 and 8 to 12" "# syntax=docker/dockerfile:1@sha256:$h64"
  fx_reset
}

# image_case <label> <rc> <fragment> <lines>: the image file is the base FROM line, then <lines>.
image_case() {
  local label="$1" want_rc="$2" want="$3" rc=0
  fx_reset
  printf 'ARG CIKIT_BASE\nFROM ${CIKIT_BASE}\n%s\n' "$4" > "$FX/ci/image/Dockerfile"; fx_commit image
  KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/check-manifest" --commit HEAD --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "$label" "$want_rc" "$rc"
  has "$label: the sentence" "$work/o" "$want"
}

# lint_rule <rule> <label> <sed expression> <sentence fragment>: the fixture
# repository's manifest mutated and committed; the lint exits 1 naming it.
lint_rule() {
  local rule="$1" label="$2" expr="$3" want="$4" rc=0
  fx_reset
  sed -e "$expr" "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  git -C "$FX" commit -qam "rule $rule"
  KIT_KEYS_REPO="$FX" "$BASH" "$KITT_KIT/bin/check-manifest" --commit HEAD --no-vendor-check > "$work/o" 2>&1 || rc=$?
  rc_is "rule $rule, $label" 1 "$rc"
  has "rule $rule, $label: the sentence" "$work/o" "$want"
}
