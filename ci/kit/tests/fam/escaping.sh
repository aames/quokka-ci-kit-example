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
  # AC-KI-33 (docs/kit-init.md rev 2, R-2 item 2): no escaping-scan line is a stated pass
  sed '/^escaping-scan /d' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  esc_run "no escaping-scan line, every escaping-read keyed: a pass (AC-KI-33 i)" 0 "The manifest names no escaping-scan line, so no file was scanned and only the escaping-read lines were checked against the keys."
  has "no escaping-scan line: the pass says nothing was scanned (AC-KI-33 i)" "$work/o" "OK: no file was scanned; 3 escaping-read lines were checked, and every one is keyed."
  sed 's#^escaping-read alpha|src/a/a_test.go|deploy/tool.sh|#escaping-read alpha|src/a/a_test.go|docs/x.md|#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  esc_run "no escaping-scan line, an escaping-read the key lacks: still checked (AC-KI-33 ii)" 1 "src/a/a_test.go reads docs/x.md, which the alpha key does not cover"
  git -C "$FX" checkout -q -- ci/manifest
  sed -e '/^escaping-scan /d' -e 's#^escaping-tree delta deploy#&\nescaping-scan go deploy#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  esc_run "an escaping-scan root holding no test file is still refused (AC-KI-33 iii)" 2 "the escaping-read fence found no test files, so it would prove nothing."
  git -C "$FX" checkout -q -- ci/manifest
  # AC-KI-34 (R-2 item 3): under a tree of ., depth is counted from the path itself
  sed -e 's#^escaping-tree alpha src#&\nescaping-tree alpha .#' -e 's#^escaping-scan go src$#escaping-scan go .#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  mkdir -p "$FX/db"
  printf 'package db\n\nimport ("path/filepath")\n\nvar _ = filepath.Join("..", "..", "x")\n' > "$FX/db/x_test.go"
  esc_run "under a tree of ., db/x_test.go climbing two is a finding (AC-KI-34)" 1 "db/x_test.go builds a path out of ./"
  rm -rf "$FX/db"
  git -C "$FX" checkout -q -- ci/manifest
  # AC-KI-37 (docs/kit-init.md rev 3, R3-3): the fence's path tests hold a tree of . as every path
  # (i) a keyed escaping-read line under a tree of . is accepted
  sed -e 's#^escaping-tree alpha src#&\nescaping-tree alpha .#' -e 's#^escaping-scan go src$#escaping-scan go .#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  printf 'escaping-read alpha|db/x_test.go|deploy/tool.sh|reads the deploy helper\n' >> "$FX/ci/manifest"
  mkdir -p "$FX/db"
  printf 'package db\n\nimport ("path/filepath")\n\nvar _ = filepath.Join("..", "..", "deploy", "tool.sh")\n' > "$FX/db/x_test.go"
  esc_run "AC-KI-37 (i): a keyed escaping-read line under a tree of . is accepted" 0 "OK: "
  hasnt "AC-KI-37 (i): and is not called outside the tree" "$work/o" "is declared for job alpha but is not in"
  rm -rf "$FX/db"
  git -C "$FX" checkout -q -- ci/manifest
  # (ii) under a ts scan root of ., a file under test/ is scanned and its climb is a finding
  sed -e 's#^escaping-tree alpha src#&\nescaping-tree alpha .#' -e 's#^escaping-scan ts src/web$#escaping-scan ts .#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  mkdir -p "$FX/test"
  printf 'import { join } from "path"\nexport const p = join("..", "..", "x")\n' > "$FX/test/helper.ts"
  esc_run "AC-KI-37 (ii): under a ts scan root of ., test/helper.ts climbing out is a finding" 1 "test/helper.ts builds a path out of ./"
  rm -rf "$FX/test"
  git -C "$FX" checkout -q -- ci/manifest
  # (iii) a tree of . holding the scan root src is not declared by hand
  sed -e 's#^escaping-tree delta deploy#&\nescaping-tree alpha .#' "$FX/ci/manifest" > "$work/m" && cp "$work/m" "$FX/ci/manifest"
  esc_run "AC-KI-37 (iii): a tree of . with the scan root src inside it" 0 "OK: "
  hasnt "AC-KI-37 (iii): prints no declared-by-hand line for the tree of ." "$work/o" "tree . has no escaping-scan line"
  has "AC-KI-37 (iii) (control): a tree with no scan root is still declared by hand" "$work/o" "delta's tree deploy has no escaping-scan line"
  git -C "$FX" checkout -q -- ci/manifest
  esc_run "the default root and HEAD's dump (no --manifest-file)" 0 "OK: "
  rc=0; ( cd "$FX" && python3 "$KITT_KIT/bin/check-escaping-reads" ) > "$work/o" 2>&1 || rc=$?
  rc_is "the dump is read from HEAD in the root by the library's one parser" 0 "$rc"
  check "the fence's text names no job of any project" test "$(grep -ci 'backend\|frontend\|deployfiles\|obsharness' "$KITT_KIT/bin/check-escaping-reads")" -eq 0
}
