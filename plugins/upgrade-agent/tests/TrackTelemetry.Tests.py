# Copyright (c) Microsoft Corporation. All rights reserved.

"""Run with Python 3.12+: TrackTelemetry.Tests.py --shell powershell|bash.

Bash additionally accepts --parser python|regex|jq (default: python).
The selected shell/parser must exist; missing prerequisites fail, never skip.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
# This suite intentionally executes the packaged hooks.
import subprocess  # nosec B404
import sys
import tempfile
import unittest


def script_path(shell):
    root = Path(__file__).resolve().parent.parent
    suffix = "ps1" if shell == "powershell" else "sh"
    candidates = [
        root / "hooks" / "scripts",
        root / "com.github.copilot" / "hooks" / "scripts",
        root.parent / "hooks" / "scripts",
    ]
    found = [p / f"track-telemetry.{suffix}" for p in candidates
             if (p / f"track-telemetry.{suffix}").is_file()]
    if len(found) != 1:
        raise RuntimeError(f"Expected exactly one telemetry script, found {found}")
    return found[0]


class TrackTelemetryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hook tests ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.logs = self.root / "UA" / "upgrades" / "skills-loaded"
        self.parser_errors = self.root / "unexpected-parser.txt"

    def invoke(self, payload):
        env = os.environ.copy()
        env.update(TEMP=str(self.root), TMP=str(self.root),
                   TMPDIR=self.root.as_posix(), PYTHONUTF8="1")
        if OPTIONS.shell == "powershell":
            command = [OPTIONS.executable, "-NoProfile", "-NonInteractive",
                       "-ExecutionPolicy", "Bypass", "-File", str(SCRIPT)]
        else:
            # Force parser discovery without changing the real script or depending
            # on an ambient WindowsApps python3 alias / developer jq installation.
            python = shlex.quote(Path(sys.executable).as_posix())
            parser = OPTIONS.parser
            setup = f"""
unexpected_parser() {{
    printf '%s must not run in {parser} mode\\n' "$1" >> {shlex.quote(self.parser_errors.as_posix())}
    return 127
}}
python3() {{ {python + ' "$@"' if parser == 'python' else 'unexpected_parser python3'}; }}
jq() {{ {'builtin command jq "$@"' if parser == 'jq' else 'unexpected_parser jq'}; }}
command() {{
    case "$*" in
        '-v python3') {'return 0' if parser == 'python' else 'return 1'} ;;
        '-v jq') {'builtin command -v jq' if parser == 'jq' else 'return 1'} ;;
        *) builtin command "$@" ;;
    esac
}}
export -f python3 jq command unexpected_parser
exec bash "$1"
"""
            command = [OPTIONS.executable, "--noprofile", "--norc", "-c",
                       setup, "telemetry-tests", SCRIPT.as_posix()]
        text = payload if isinstance(payload, str) else json.dumps(payload)
        # Executable is explicitly resolved; fixture JSON goes to stdin, not shell code.
        with subprocess.Popen(  # nosec B603
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8",
            cwd=self.root, env=env,
            start_new_session=os.name != "nt",
        ) as process:
            try:
                stdout, stderr = process.communicate(text, timeout=15)
            except subprocess.TimeoutExpired:
                if os.name == "nt":
                    taskkill = Path(os.environ["SystemRoot"]) / "System32" / "taskkill.exe"
                    cleanup = [str(taskkill), "/PID", str(process.pid), "/T", "/F"]
                    # Only the process tree just created by this test is terminated.
                    subprocess.run(cleanup,  # nosec B603
                                   capture_output=True, timeout=10, check=True)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)
                self.fail("Telemetry hook exceeded its 15-second test deadline")
        self.assertEqual(0, process.returncode, stderr)
        self.assertEqual({"continue": True}, json.loads(stdout), (stdout, stderr))
        if self.parser_errors.exists():
            self.fail(self.parser_errors.read_text(encoding="utf-8"))
        return stderr

    def assert_log(self, skill="test-skill", session="session-1", count=1):
        files = list(self.logs.glob("*")) if self.logs.exists() else []
        expected = self.logs / f"progressive-loads-{session}.txt"
        self.assertEqual([expected], files)
        data = expected.read_bytes()
        text = data.decode("utf-16") if data.startswith((b"\xff\xfe", b"\xfe\xff")) else data.decode("utf-8-sig")
        lines = text.splitlines()
        self.assertEqual(count, len(lines))
        for line in lines:
            self.assertRegex(line, rf"^\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}(?:\.\d{{3}})?, {re.escape(skill)}$")

    def assert_no_log(self):
        self.assertEqual([], list(self.root.rglob("progressive-loads-*")))

    def test_host_input_shapes(self):
        count = 0
        for tool in ("read_file", "view", "Read"):
            for key in ("file_path", "filePath", "path"):
                with self.subTest(tool=tool, key=key):
                    self.invoke({"tool_name": tool,
                                 "tool_input": {key: "/cache/upgrade/dotnet/skills/lazy/test-skill/SKILL.md"},
                                 "session_id": "session-1"})
                    count += 1
                    self.assert_log(count=count)

    def test_camel_case_input_uses_unknown_session(self):
        # The registered PascalCase event uses session_id; legacy sessionId
        # is not consumed by these scripts.
        self.invoke({"toolName": "view", "toolArgs": {
            "path": "/cache/upgrade/skills/test-skill/SKILL.md"}, "sessionId": "session-1"})
        self.assert_log(session="unknown")

    def test_known_skill_layouts(self):
        prefixes = ("/cache/upgrade/skills",
                    "/cache/upgrade/dotnet/skills",
                    "/cache/upgrade/partner-extension/skills",
                    "/cache/extensions/ms-dotnettools.upgrade-agent-1.2.3/skills")
        count = 0
        for prefix in prefixes:
            for group in ("", "lazy/", "scenarios/nested/"):
                for windows in (False, True):
                    path = f"{prefix}/{group}test-skill/SKILL.md"
                    if windows:
                        path = "C:" + path.replace("/", "\\")
                    with self.subTest(path=path):
                        self.invoke({"tool_name": "view", "tool_input": {"path": path},
                                     "session_id": "session-1"})
                        count += 1
                        self.assert_log(count=count)

    def test_noop_inputs(self):
        for payload in ("", " ", "{invalid", "null", "[]", "{}",
                        {"tool_name": "view"},
                        {"tool_name": "edit", "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"}},
                        {"tool_name": "view", "tool_input": {"path": "/repo/SKILL.md"}},
                        {"tool_name": "view", "tool_input": {"path": "/cache/unrelated/skills/test-skill/SKILL.md"}},
                        {"tool_name": "view", "tool_input": {"path": "/cache/upgrade/skills/test-skill/ref/guide.md"}}):
            with self.subTest(payload=payload):
                self.invoke(payload)
                self.assert_no_log()

    def test_unknown_session_and_append(self):
        payload = {"tool_name": "view", "tool_input": {"path": "/cache/upgrade/skills/lazy/test-skill/SKILL.md"}}
        self.invoke(payload)
        self.invoke(payload)
        self.assert_log(session="unknown", count=2)

    def test_log_directory_failure_does_not_block(self):
        (self.root / "UA").write_text("not a directory", encoding="utf-8")
        self.invoke({"tool_name": "view", "tool_input": {"path": "/cache/upgrade/skills/lazy/test-skill/SKILL.md"}})
        self.assert_no_log()

    def test_log_append_failure_does_not_block(self):
        self.logs.mkdir(parents=True)
        (self.logs / "progressive-loads-session-1.txt").mkdir()
        self.invoke({"tool_name": "view", "session_id": "session-1",
                     "tool_input": {"path": "/cache/upgrade/skills/lazy/test-skill/SKILL.md"}})
        target = self.logs / "progressive-loads-session-1.txt"
        self.assertEqual([target], list(self.logs.iterdir()))
        self.assertTrue(target.is_dir())
        self.assertEqual([], list(target.iterdir()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shell", choices=("powershell", "bash"), required=True)
    parser.add_argument("--executable")
    parser.add_argument("--parser", choices=("python", "regex", "jq"), default="python")
    OPTIONS, remaining = parser.parse_known_args()
    OPTIONS.executable = shutil.which(OPTIONS.executable or OPTIONS.shell)
    if not OPTIONS.executable:
        parser.error(f"{OPTIONS.shell} executable is required")
    if OPTIONS.shell == "bash" and OPTIONS.parser == "jq":
        # Resolved shell executable with a constant prerequisite check, no fixture input.
        subprocess.run([OPTIONS.executable, "-c", "command -v jq"],  # nosec B603
                       check=True, timeout=10)
    SCRIPT = script_path(OPTIONS.shell)
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
