# shellcheck shell=bash disable=SC2154,SC2034,SC2016,SC2086
# K-escaping (kit/README.md §6.2; DESIGN.md §5.1): the declaration rules
# for any language; the Go and TypeScript scanners on the planted cases (a planted
# ../../../x read, declared, and the same text in a comment).
esc_run() { # esc_run <label> <want rc> <fragment>: the fence on $FX with its manifest
  local rc=0
  python3 "$KITT_KIT/bin/check-escaping-reads" --root "$FX" --manifest-file "$FX/ci/manifest" > "$work/o" 2>&1 || rc=$?
  rc_is "$1" "$2" "$rc"
  [ -z "$3" ] || has "$1: the sentence" "$work/o" "$3"
}
fam_escaping() {
  fx_new esc
  esc_run "the fixture repository: every escaping test declared and keyed" 0 "OK: "
  has "and the fence says what it cannot see" "$work/o" "This fence scans Go and TypeScript only"
  printf 'package a\n\nimport ("path/filepath")\n\nvar _ = filepath.Join("..", "..", "..", "etc", "x")\n' > "$FX/src/a/b_test.go"
  esc_run "a planted ../../../ read in a Go test, undeclared" 1 "src/a/b_test.go builds a path out of src/ and is not declared by an escaping-read line"
  printf 'package a\n\n// filepath.Join("..", "..", "..", "etc", "x") and repoRoot, in prose\n/* repoRoot too */\nvar _ = 1\n' > "$FX/src/a/b_test.go"
  esc_run "the same text in a comment" 0 "OK: "
  printf 'package a\n\nconst up = ".."\n\nvar _ = filepath.Join(up, up, "x")\n' > "$FX/src/a/b_test.go"
  esc_run "a climb through a name bound to ..: two uses climb two" 1 "src/a/b_test.go builds a path out of src/"
  printf 'package a\n\nvar _ = repoRoot\n' > "$FX/src/a/b_test.go"
  esc_run "a repository-root helper" 1 "src/a/b_test.go builds a path out of src/"
  rm -f "$FX/src/a/b_test.go"
  # a test file directly in its tree is depth zero, so one .. leaves it (v1.0.0-rc.2)
  printf 'package src\n\nimport ("path/filepath")\n\nvar _ = filepath.Join("..", "web", "x")\n' > "$FX/src/top_test.go"
  esc_run "a test directly in its tree climbing one .. out, undeclared" 1 "src/top_test.go builds a path out of src/ and is not declared by an escaping-read line"
  has "and it is counted from depth zero" "$work/o" "src/top_test.go:5: a path call climbs 1 \`..\` from 0 below src/"
  printf 'package src\n\nimport ("path/filepath")\n\nvar _ = filepath.Join("web", "x")\n' > "$FX/src/top_test.go"
  esc_run "the same test reading inside its tree" 0 "OK: "
  rm -f "$FX/src/top_test.go"
  printf 'import { join } from "path"\nconst p = join(process.cwd(), "..", "x")\n' > "$FX/src/web/y.test.ts"
  esc_run "a TypeScript test climbing from the tree" 1 "src/web/y.test.ts builds a path out of src/"
  printf '// join(process.cwd(), "..", "x") and repoRoot\nexport const y = 1\n' > "$FX/src/web/y.test.ts"
  esc_run "a TypeScript comment" 0 "OK: "
  rm -f "$FX/src/a/b_test.go" "$FX/src/web/y.test.ts"
  # the declaration rules, which hold for any language
  sed 's#^escaping-read alpha|src/a/a_test.go|deploy/tool.sh|#escaping-read alpha|src/a/a_test.go|docs/x.md|#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  esc_run "a declared outside path the job's key does not cover" 1 "src/a/a_test.go reads docs/x.md, which the alpha key does not cover"
  git -C "$FX" checkout -q -- ci/manifest
  sed 's#^escaping-read alpha|src/web/x.test.ts|NONE|#escaping-read alpha|src/gone_test.go|NONE|#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  esc_run "a declaration of a file that does not exist" 1 "is declared by an escaping-read line but does not exist"
  git -C "$FX" checkout -q -- ci/manifest
  sed 's#^escaping-read alpha|src/a/a_test.go|deploy/tool.sh|#escaping-read gate|src/a/a_test.go|deploy/tool.sh|#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  esc_run "a declaration for a job that is not local or ci-only" 1 "which is not a local or ci-only job"
  git -C "$FX" checkout -q -- ci/manifest
  esc_run "the default root and HEAD's dump (no --manifest-file)" 0 "OK: "
  rc=0; ( cd "$FX" && python3 "$KITT_KIT/bin/check-escaping-reads" ) > "$work/o" 2>&1 || rc=$?
  rc_is "the dump is read from HEAD in the root by the library's one parser" 0 "$rc"
  check "the fence's text names no job of any project" test "$(grep -ci 'backend\|frontend\|deployfiles\|obsharness' "$KITT_KIT/bin/check-escaping-reads")" -eq 0
}
