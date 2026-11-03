#!/usr/bin/env python3
"""THE HOST RULE OF kit-init AS A SYNTAX-TREE TEST (docs/kit-init.md section 8;
AC-KI-2, AC-KI-3). Reads the file named on the command line and prints one line
per finding; exit 0 with none, 1 with any.

  AC-KI-2  the source parses with ast.parse(..., feature_version=(3, 9)), so a
           construct newer than Python 3.9 cannot slip in on a newer Python;
  AC-KI-3  every call that starts a process is subprocess.run, its first
           argument is a list whose first element is "git", "docker",
           "ssh-keygen", "bash" or sys.executable, and none passes shell=.
           A call to os.system, os.popen, os.exec*, os.spawn*, os.posix_spawn,
           or to a subprocess function other than run, is a finding too.

Standard library only; it must itself run on the oldest Python it judges.
"""
import ast
import sys

ALLOWED = ("git", "docker", "ssh-keygen", "bash")
OTHER_SPAWNS = ("system", "popen", "execl", "execle", "execlp", "execlpe", "execv", "execve", "execvp",
                "execvpe", "spawnl", "spawnle", "spawnlp", "spawnlpe", "spawnv", "spawnve", "spawnvp",
                "spawnvpe", "posix_spawn", "posix_spawnp")
SUBPROCESS_OTHERS = ("Popen", "call", "check_call", "check_output", "getoutput", "getstatusoutput")


def dotted(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


def findings(source, name):
    out = []
    try:
        tree = ast.parse(source, filename=name, feature_version=(3, 9))
    except SyntaxError as e:
        return ["%s:%s: does not parse as Python 3.9: %s" % (name, e.lineno, e.msg)], 0
    runs = 0
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        target = dotted(node.func)
        if target == "subprocess.run":
            runs += 1
            first = node.args[0] if node.args else None
            if not isinstance(first, ast.List) or not first.elts:
                out.append("%s:%d: subprocess.run is not given a list" % (name, node.lineno))
            else:
                head = first.elts[0]
                ok = (isinstance(head, ast.Constant) and head.value in ALLOWED) or dotted(head) == "sys.executable"
                if not ok:
                    out.append("%s:%d: subprocess.run starts with something other than git, docker, ssh-keygen, "
                               "bash or sys.executable" % (name, node.lineno))
            for kw in node.keywords:
                if kw.arg == "shell" or kw.arg is None:
                    out.append("%s:%d: subprocess.run passes %s" % (name, node.lineno, kw.arg or "**kwargs"))
        elif target.startswith("subprocess.") and target.split(".", 1)[1] in SUBPROCESS_OTHERS:
            out.append("%s:%d: %s starts a process outside subprocess.run" % (name, node.lineno, target))
        elif target.startswith("os.") and target.split(".", 1)[1] in OTHER_SPAWNS:
            out.append("%s:%d: %s starts a process outside subprocess.run" % (name, node.lineno, target))
    return out, runs


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: hostrule.py <python file>\n")
        return 2
    with open(argv[1], encoding="utf-8") as f:
        source = f.read()
    found, runs = findings(source, argv[1])
    for line in found:
        print(line)
    if not found:
        print("OK: parses as Python 3.9; %d subprocess.run calls, every one a list starting with an allowed "
              "executable, none with shell" % runs)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
