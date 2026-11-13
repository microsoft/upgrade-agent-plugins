# Copyright (c) Microsoft Corporation. All rights reserved.

"""Run with Python 3.12+: TrackTelemetry.Tests.py --shell powershell|bash.

Bash additionally accepts --parser python|regex|jq (default: python).
Add --wrapper to exercise hooks.json commands instead of the scripts directly.
The selected shell/parser must exist; missing prerequisites fail, never skip.
"""

import argparse
from datetime import datetime, timezone
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
        self.root = Path(self.temp.name).resolve()
        self.logs = self.root / "UA" / "upgrades" / "skills-loaded"
        self.parser_errors = self.root / "unexpected-parser.txt"
        self.parser_calls = self.root / "parser-calls.txt"

    def invoke(self, payload, plugin_root=None, wrapper=None,
               execution_policy="Bypass", command_prefix="", bash_host="bash",
               build_phase=None, command_finally="", new_console=False):
        wrapper = OPTIONS.wrapper if wrapper is None else wrapper
        env = os.environ.copy()
        env.update(TEMP=str(self.root), TMP=str(self.root),
                   TMPDIR=self.root.as_posix(), PYTHONUTF8="1",
                   DOTNET_UPGRADEASSISTANT_DIAGNOSTICS_ROOT_PATH="")
        installed_root = SCRIPT.parent.parent.parent
        if installed_root.name == "com.github.copilot":
            installed_root = installed_root.parent
        if plugin_root == "":
            env.pop("PLUGIN_ROOT", None)
        else:
            env["PLUGIN_ROOT"] = str(plugin_root or installed_root)
        if wrapper:
            config_paths = (SCRIPT.parent.parent / "hooks.json",
                            installed_root / "hooks.json")
            config = next((p for p in config_paths if p.is_file()), None)
            if config is None:
                raise RuntimeError(f"No hooks.json found in {config_paths}")
            group = "PreToolUse" if build_phase == "pre" else "PostToolUse"
            script_name = "track-build-telemetry" if build_phase else "track-telemetry"
            hook = next(h for h in json.loads(config.read_text(encoding="utf-8"))["hooks"][group]
                        if f"/{script_name}.sh" in h["bash"])
        if OPTIONS.shell == "powershell":
            command = [OPTIONS.executable, "-NoProfile", "-NonInteractive",
                       "-ExecutionPolicy", execution_policy]
            if wrapper:
                body = hook["powershell"]
                if command_finally:
                    body = "try { " + body + " } finally { " + command_finally + " }"
                command += ["-Command", command_prefix + body]
            else:
                command += ["-File", str(SCRIPT)]
        else:
            # Force parser discovery without changing the real script or depending
            # on an ambient WindowsApps python3 alias / developer jq installation.
            python = shlex.quote(Path(sys.executable).as_posix())
            parser = "python" if build_phase else OPTIONS.parser
            setup = f"""
unexpected_parser() {{
    printf '%s must not run in {parser} mode\\n' "$1" >> {shlex.quote(self.parser_errors.as_posix())}
    return 127
}}
python3() {{
    {'printf "python3\\n" >> ' + shlex.quote(self.parser_calls.as_posix()) + '; ' + python + ' "$@"' if parser == 'python' else 'unexpected_parser python3'}
}}
jq() {{
    {'printf "jq\\n" >> ' + shlex.quote(self.parser_calls.as_posix()) + '; builtin command jq "$@"' if parser == 'jq' else 'unexpected_parser jq'}
}}
command() {{
    case "$*" in
        '-v python3') {'return 0' if parser == 'python' else 'return 1'} ;;
        '-v jq') {'builtin command -v jq' if parser == 'jq' else 'return 1'} ;;
        *) builtin command "$@" ;;
    esac
}}
export -f python3 jq command unexpected_parser
exec {shlex.quote(bash_host)} {"-c " if wrapper else ""}"$1"
"""
            command = [OPTIONS.executable, "--noprofile", "--norc", "-c",
                       setup, "telemetry-tests",
                       command_prefix + hook["bash"] if wrapper else SCRIPT.as_posix()]
        text = payload if isinstance(payload, str) else json.dumps(payload)
        startupinfo = None
        if os.name == "nt" and new_console:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startupinfo.wShowWindow = subprocess.SW_HIDE
        # Executable is explicitly resolved; fixture JSON goes to stdin, not shell code.
        with subprocess.Popen(  # nosec B603
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8",
            cwd=self.root, env=env,
            start_new_session=os.name != "nt",
            creationflags=subprocess.CREATE_NEW_CONSOLE if os.name == "nt" and new_console else 0,
            startupinfo=startupinfo,
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

    def assert_log(self, skill="test-skill", session="session-1", count=1,
                   encoding="utf-8-sig"):
        files = list(self.logs.glob("*")) if self.logs.exists() else []
        expected = self.logs / f"progressive-loads-{session}.txt"
        self.assertEqual([expected], files)
        data = expected.read_bytes()
        text = data.decode("utf-16") if data.startswith((b"\xff\xfe", b"\xfe\xff")) else data.decode(encoding)
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
                self.assertFalse(self.logs.exists())

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

    def test_wrapper_rejects_non_skill_reads_without_running_script(self):
        plugin = self.root / "plugin"
        namespace = ("com.github.copilot",) if SCRIPT.parent.parent.parent.name == "com.github.copilot" else ()
        script = plugin.joinpath(*namespace, "hooks", "scripts", SCRIPT.name)
        script.parent.mkdir(parents=True)
        script.write_text("exit 91\n", encoding="utf-8")
        for path in ("/repo/Example.cs",
                     r"C:\Users\lonitra\Source\Repos\Example.cs",
                     r"C:\users\lonitra\Source\Repos\Example.cs",
                     r"C:\repo\upgrade\Example.cs",
                     r"C:\repo\utils\Example.cs"):
            with self.subTest(path=path):
                self.invoke({"tool_name": "view", "tool_input": {"path": path}},
                            plugin_root=plugin, wrapper=True)
        self.assert_no_log()
        self.assertFalse(self.logs.exists())

    def test_wrapper_preserves_escaped_skill_filename(self):
        if OPTIONS.shell == "bash" and OPTIONS.parser == "regex":
            return
        payload = {"tool_name": "view", "session_id": "session-1",
                   "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"}}
        self.invoke(payload, wrapper=True)
        self.assert_log()
        for count, filename in enumerate((r"\u0053KILL.md",
                                          r"\u0053\u004b\u0049\u004c\u004c\u002e\u006d\u0064"), 2):
            self.invoke(json.dumps(payload).replace("SKILL.md", filename), wrapper=True)
            self.assert_log(count=count)

    def test_powershell_wrapper_runs_in_host_process(self):
        if OPTIONS.shell != "powershell":
            return
        plugin = self.root / "plugin O'Brien"
        namespace = ("com.github.copilot",) if SCRIPT.parent.parent.parent.name == "com.github.copilot" else ()
        script = plugin.joinpath(*namespace, "hooks", "scripts", SCRIPT.name)
        script.parent.mkdir(parents=True)
        outer = self.root / "outer-pid.txt"
        inner = self.root / "inner-pid.txt"
        payload_copy = self.root / "payload.txt"

        def ps_path(path):
            return "'" + str(path).replace("'", "''") + "'"

        script.write_text(
            "param([string]$HookInputJson)\n"
            f"[IO.File]::WriteAllText({ps_path(inner)}, [string][Diagnostics.Process]::GetCurrentProcess().Id)\n"
            f"[IO.File]::WriteAllText({ps_path(payload_copy)}, $HookInputJson)\n"
            "[Console]::Out.WriteLine('{\"continue\":true}')\n",
            encoding="utf-8")
        payload = {"tool_name": "view", "session_id": "session-1",
                   "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"},
                   "untrusted": "'; throw 'payload must not execute"}
        self.invoke(payload, plugin_root=plugin, wrapper=True,
                    execution_policy="Restricted",
                    command_prefix=f"[IO.File]::WriteAllText({ps_path(outer)}, [string][Diagnostics.Process]::GetCurrentProcess().Id); ")
        self.assertEqual(outer.read_text(), inner.read_text())
        self.assertEqual(json.dumps(payload), payload_copy.read_text(encoding="utf-8-sig"))

    def test_bash_wrapper_runs_in_host_process(self):
        if OPTIONS.shell != "bash":
            return
        plugin = self.root / "plugin O'Brien"
        namespace = ("com.github.copilot",) if SCRIPT.parent.parent.parent.name == "com.github.copilot" else ()
        script = plugin.joinpath(*namespace, "hooks", "scripts", SCRIPT.name)
        script.parent.mkdir(parents=True)
        outer = self.root / "outer-pid.txt"
        inner = self.root / "inner-pid.txt"
        payload_copy = self.root / "payload.txt"
        # $$ alone is inherited by subshells. Include the subshell level for
        # Bash 3.2, and use BASHPID where available, without spawning a probe.
        record_pid = "printf '%s' \"${BASHPID:-$$}:$BASH_SUBSHELL\" > "
        script.write_text(
            record_pid + shlex.quote(inner.as_posix()) + "\n"
            "printf '%s' \"$1\" > " + shlex.quote(payload_copy.as_posix()) + "\n"
            "echo '{\"continue\":true}'\nexit 0\n", encoding="utf-8")
        payload = {"tool_name": "view", "session_id": "session-1",
                   "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"},
                   "untrusted": "'; $(exit 91); `exit 92`"}
        self.invoke(payload, plugin_root=plugin, wrapper=True,
                    command_prefix=record_pid + shlex.quote(outer.as_posix()) + "; ")
        self.assertEqual(outer.read_text(), inner.read_text())
        self.assertEqual(json.dumps(payload), payload_copy.read_text(encoding="utf-8"))

    def test_bash_wrapper_replaces_non_bash_host(self):
        if OPTIONS.shell != "bash":
            return
        # Unset BASH_VERSION to exercise the replacement branch even when
        # Git for Windows supplies Bash as its sh executable.
        plugin = self.root / "plugin"
        namespace = ("com.github.copilot",) if SCRIPT.parent.parent.parent.name == "com.github.copilot" else ()
        script = plugin.joinpath(*namespace, "hooks", "scripts", SCRIPT.name)
        script.parent.mkdir(parents=True)
        outer = self.root / "outer-pid.txt"
        inner = self.root / "inner-pid.txt"
        bash_version = self.root / "bash-version.txt"
        argument_count = self.root / "argument-count.txt"
        payload_copy = self.root / "payload.txt"
        script.write_text(
            f"printf '%s' \"$$\" > {shlex.quote(inner.as_posix())}\n"
            f"printf '%s' \"$BASH_VERSION\" > {shlex.quote(bash_version.as_posix())}\n"
            f"printf '%s' \"$#\" > {shlex.quote(argument_count.as_posix())}\n"
            f"cat > {shlex.quote(payload_copy.as_posix())}\n"
            "echo '{\"continue\":true}'\n", encoding="utf-8")
        payload = {"tool_name": "view", "session_id": "session-1",
                   "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"}}
        record_outer_pid = f"printf '%s' \"$$\" > {shlex.quote(outer.as_posix())}; "
        self.invoke(payload, plugin_root=plugin, wrapper=True, bash_host="sh",
                    command_prefix=record_outer_pid + "unset BASH_VERSION; ")
        self.assertEqual(outer.read_text(), inner.read_text())
        self.assertTrue(bash_version.read_text())
        self.assertEqual("0", argument_count.read_text())
        self.assertEqual(json.dumps(payload) + "\n", payload_copy.read_text(encoding="utf-8"))

    def test_bash_wrapper_disables_posix_mode_before_reading_fields(self):
        if OPTIONS.shell != "bash":
            return
        self.invoke({"tool_name": "view", "session_id": "session-1",
                     "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"}},
                    wrapper=True,
                    command_prefix=(
                        "set -o posix; "
                        "read() { if [ -o posix ]; then "
                        "echo 'POSIX mode is still enabled' >&2; exit 91; fi; "
                        "builtin read \"$@\"; }; "))
        self.assert_log()

    def test_bash_wrapper_preserves_large_payloads(self):
        if OPTIONS.shell != "bash":
            return
        payload = {"tool_name": "view", "session_id": "session-1",
                   "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"},
                   "untrusted": "'; $(exit 91); `exit 92` " + "x" * (256 * 1024)}
        for count, prefix in enumerate(("", "unset BASH_VERSION; "), 1):
            with self.subTest(non_bash=bool(prefix)):
                self.invoke(payload, wrapper=True, command_prefix=prefix)
                self.assert_log(count=count)

    def test_powershell_wrapper_logs_under_restricted_policy(self):
        if OPTIONS.shell != "powershell":
            return
        if os.name == "nt":
            self.assert_script_file_blocked(SCRIPT, "Restricted")
        self.invoke({"tool_name": "view", "session_id": "session-1",
                     "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"}},
                    wrapper=True, execution_policy="Restricted")
        self.assert_log()

    def test_powershell_wrapper_logs_skill_reads_across_cultures(self):
        if OPTIONS.shell != "powershell":
            return
        cases = (("tr-TR", "SKILL.md"), ("tr-TR", "SkIlL.md"),
                 ("tr-TR", "SK\u0131LL.md"), ("en-US", "SK\u0130LL.md"))
        for count, (culture, filename) in enumerate(cases, 1):
            with self.subTest(culture=culture, filename=filename):
                prefix = ("[Threading.Thread]::CurrentThread.CurrentCulture = "
                          f"[Globalization.CultureInfo]::GetCultureInfo('{culture}'); ")
                payload = {"tool_name": "view", "session_id": "session-1",
                           "tool_input": {"path": f"/cache/upgrade/skills/test-skill/{filename}"}}
                self.invoke(json.dumps(payload, ensure_ascii=False),
                            wrapper=True, command_prefix=prefix)
                self.assert_log(count=count)

    def test_powershell_wrappers_preserve_console_encoding_and_utf8_input(self):
        if OPTIONS.shell != "powershell" or os.name != "nt":
            return
        code_page = self.root / "console-code-page.txt"
        prefix = (
            "Add-Type 'using System.Runtime.InteropServices; "
            "public static class HookConsoleProbe { "
            "[DllImport(\"kernel32.dll\")] public static extern bool SetConsoleCP(uint cp); "
            "[DllImport(\"kernel32.dll\")] public static extern uint GetConsoleCP(); }'; "
            "if (-not [HookConsoleProbe]::SetConsoleCP(437)) "
            "{ throw 'Could not set the private console code page' }; ")
        finalizer = (
            "[IO.File]::WriteAllText('"
            + str(code_page).replace("'", "''")
            + "', [string][HookConsoleProbe]::GetConsoleCP())")
        for phase in (None, "pre", "post"):
            with self.subTest(phase=phase):
                payload = {"tool_name": "shell", "tool_input": {"command": "dotnet build"}}
                if phase is None:
                    payload = {"tool_name": "view", "session_id": "session-1",
                               "tool_input": {"path": "/cache/upgrade/skills/caf\u00e9/SKILL.md"}}
                self.invoke(json.dumps(payload, ensure_ascii=False), wrapper=True,
                            build_phase=phase, command_prefix=prefix, command_finally=finalizer,
                            new_console=True)
                self.assertEqual("437", code_page.read_text(encoding="utf-8-sig"))
                if phase is None:
                    # Windows PowerShell's Add-Content defaults to the ANSI code page.
                    encoding = ("mbcs" if Path(OPTIONS.executable).name.lower() == "powershell.exe"
                                else "utf-8-sig")
                    self.assert_log(skill="caf\u00e9", encoding=encoding)

    def test_powershell_wrapper_logs_marked_script_under_remote_signed(self):
        if OPTIONS.shell != "powershell" or os.name != "nt":
            return
        plugin = self.root / "plugin"
        namespace = ("com.github.copilot",) if SCRIPT.parent.parent.parent.name == "com.github.copilot" else ()
        script = plugin.joinpath(*namespace, "hooks", "scripts", SCRIPT.name)
        script.parent.mkdir(parents=True)
        shutil.copyfile(SCRIPT, script)
        marker = Path(str(script) + ":Zone.Identifier")
        try:
            marker.write_text("[ZoneTransfer]\nZoneId=3\n", encoding="ascii")
            self.assert_script_file_blocked(script, "RemoteSigned")
            self.invoke({"tool_name": "view", "session_id": "session-1",
                         "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"}},
                        plugin_root=plugin, wrapper=True, execution_policy="RemoteSigned")
            self.assert_log()
        finally:
            marker.unlink(missing_ok=True)

    def assert_script_file_blocked(self, script, policy):
        # Negative control: prove this policy blocks file invocation on this machine.
        result = subprocess.run(  # nosec B603
            [OPTIONS.executable, "-NoProfile", "-NonInteractive",
             "-ExecutionPolicy", policy, "-File", str(script)],
            input="", capture_output=True, text=True, encoding="utf-8", timeout=15)
        self.assertNotEqual(0, result.returncode, result.stdout)
        self.assertRegex(result.stderr,
                         r"(?i)PSSecurityException|UnauthorizedAccess|running scripts is disabled|not digitally signed")

    def test_wrapper_missing_plugin_is_noop(self):
        payload = {"tool_name": "view",
                   "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"}}
        for root in ("", self.root / "missing plugin"):
            with self.subTest(root=root):
                self.invoke(payload, plugin_root=root, wrapper=True)
                self.assert_no_log()

    def test_bash_uses_one_parser_for_skill_read(self):
        if OPTIONS.shell != "bash" or OPTIONS.parser == "regex":
            return
        self.invoke({"tool_name": "view", "session_id": "session-1",
                     "tool_input": {"path": "/cache/upgrade/skills/test-skill/SKILL.md"}})
        self.assert_log()
        self.assertEqual([OPTIONS.parser if OPTIONS.parser == "jq" else "python3"],
                         self.parser_calls.read_text(encoding="utf-8").splitlines())

    def test_build_wrappers_reject_irrelevant_payloads_without_running_script(self):
        plugin = self.root / "plugin"
        namespace = ("com.github.copilot",) if SCRIPT.parent.parent.parent.name == "com.github.copilot" else ()
        script = plugin.joinpath(*namespace, "hooks", "scripts",
                                 "track-build-telemetry." + SCRIPT.suffix[1:])
        script.parent.mkdir(parents=True)
        script.write_text("exit 91\n", encoding="utf-8")
        for phase in ("pre", "post"):
            for command in ("git status", r"Get-Content C:\Users\dev\utils\Example.cs",
                            "dotnet test App.sln"):
                with self.subTest(phase=phase, command=command):
                    self.invoke({"tool_name": "shell", "tool_input": {"command": command}},
                                plugin_root=plugin, wrapper=True, build_phase=phase)
        self.assertFalse((self.root / "UA").exists())

    def test_build_wrappers_run_in_host_process_and_preserve_input(self):
        plugin = self.root / "plugin O'Brien"
        namespace = ("com.github.copilot",) if SCRIPT.parent.parent.parent.name == "com.github.copilot" else ()
        script = plugin.joinpath(*namespace, "hooks", "scripts",
                                 "track-build-telemetry." + SCRIPT.suffix[1:])
        script.parent.mkdir(parents=True)
        outer, inner = self.root / "outer.txt", self.root / "inner.txt"
        copied, phase_file = self.root / "payload.txt", self.root / "phase.txt"
        if OPTIONS.shell == "powershell":
            def quoted(path):
                return "'" + str(path).replace("'", "''") + "'"
            pid = "[string][Diagnostics.Process]::GetCurrentProcess().Id"
            prefix = f"[IO.File]::WriteAllText({quoted(outer)}, {pid}); "
            script.write_text(
                "param([string]$Phase, [string]$HookInputJson)\n"
                f"[IO.File]::WriteAllText({quoted(inner)}, {pid})\n"
                f"[IO.File]::WriteAllText({quoted(copied)}, $HookInputJson)\n"
                f"[IO.File]::WriteAllText({quoted(phase_file)}, $Phase)\n"
                "[Console]::Out.WriteLine('{\"continue\":true}')\n", encoding="utf-8")
        else:
            pid = "printf '%s' \"${BASHPID:-$$}:$BASH_SUBSHELL\" > "
            prefix = pid + shlex.quote(outer.as_posix()) + "; "
            script.write_text(
                pid + shlex.quote(inner.as_posix()) + "\n"
                "printf '%s' \"$2\" > " + shlex.quote(copied.as_posix()) + "\n"
                "printf '%s' \"$1\" > " + shlex.quote(phase_file.as_posix()) + "\n"
                "echo '{\"continue\":true}'\nexit 0\n", encoding="utf-8")
        payload = {"tool_name": "shell", "tool_input": {"command": "dotnet build"},
                   "untrusted": "'; $(exit 91); `exit 92`"}
        for phase in ("pre", "post"):
            self.invoke(payload, plugin_root=plugin, wrapper=True, build_phase=phase,
                        execution_policy="Restricted", command_prefix=prefix)
            self.assertEqual(outer.read_text(), inner.read_text())
            self.assertEqual(json.dumps(payload), copied.read_text(encoding="utf-8-sig"))
            self.assertEqual(phase, phase_file.read_text(encoding="utf-8-sig"))

    def test_build_wrappers_preserve_correlated_records_and_escaped_commands(self):
        session = "11111111-1111-1111-1111-111111111111"
        workspace = self.root / "user"
        workspace.mkdir()
        observations = self.root / "UA" / "upgrades" / "build-observations"
        routes = observations / "routes"
        routes.mkdir(parents=True)
        route = routes / f"{session}.json"
        commands = ("dotnet build App.csproj", "MSBuild.exe App.csproj",
                    r"dotnet \u0062\u0075\u0069\u006c\u0064 App.csproj")
        prefixes = ("", "unset BASH_VERSION; ") if OPTIONS.shell == "bash" else ("",)
        count = 0
        for prefix in prefixes:
            for command in commands:
                # Refresh the short-lived route for slower policy/interpreter runs.
                route.write_text(json.dumps({
                    "sessionId": session, "workspaceRoots": [str(workspace)],
                    "updatedUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")}), encoding="utf-8")
                args = {"command": command}
                pre = {"sessionId": session, "cwd": str(workspace),
                       "toolCalls": [{"id": f"call-{count}", "name": "shell", "args": args}]}
                post = {"sessionId": session, "cwd": str(workspace),
                        "timestamp": count, "toolName": "shell", "toolArgs": args,
                        "toolResult": {"exitCode": 1, "textResultForLlm": "error CS1002: expected ;"},
                        "padding": "x" * (256 * 1024)}
                for phase, payload in (("pre", pre), ("post", post)):
                    text = json.dumps(payload)
                    if "\\u0062" in command:
                        serialized_command = json.dumps(command)
                        text = text.replace(serialized_command,
                                            serialized_command.replace("\\\\u", "\\u"))
                    self.assertEqual(str(workspace), json.loads(text)["cwd"])
                    self.invoke(text, wrapper=True, build_phase=phase, command_prefix=prefix)
                lines = [json.loads(line) for line in
                         (observations / f"build-observations-{session}.jsonl").read_text(
                             encoding="utf-8-sig").splitlines()]
                count += 1
                self.assertEqual(count * 2, len(lines))
                started, completed = lines[-2:]
                self.assertEqual("started", started["recordKind"])
                self.assertEqual("completed", completed["recordKind"])
                self.assertEqual(started["attemptId"], completed["attemptId"])
                self.assertEqual(started["startedAtUtc"], completed["startedAtUtc"])
                timestamp = datetime.fromisoformat(completed["startedAtUtc"].replace("Z", "+00:00"))
                self.assertIsNotNone(timestamp.tzinfo)
                self.assertLess(abs((datetime.now(timezone.utc) - timestamp).total_seconds()), 60)
                self.assertEqual(session, completed["sessionId"])
                self.assertEqual("failed", completed["outcome"])
                self.assertEqual(["CS1002"], completed["errorDiagnosticCodes"])
                self.assertEqual([str(workspace / "App.csproj")], completed["targetPaths"])

    def test_build_wrapper_invalid_payload_writes_sanitized_diagnostic(self):
        sensitive_command = "dotnet build customer-secret.sln"
        self.invoke('{"command":' + json.dumps(sensitive_command),
                    wrapper=True, build_phase="pre")
        observations = self.root / "UA" / "upgrades" / "build-observations"
        text = (observations / "hook-diagnostics.jsonl").read_text(encoding="utf-8-sig")
        diagnostic = json.loads(text)
        self.assertEqual("unhandledException", diagnostic["eventName"])
        self.assertEqual("pre", diagnostic["phase"])
        self.assertTrue(diagnostic["exceptionType"])
        self.assertNotIn(sensitive_command, text)
        self.assertFalse((observations / "state").exists())

    def test_build_wrappers_missing_plugin_is_noop(self):
        for phase in ("pre", "post"):
            for root in ("", self.root / "missing"):
                self.invoke({"tool_name": "shell", "tool_input": {"command": "dotnet build"}},
                            wrapper=True, build_phase=phase, plugin_root=root)
        self.assertFalse((self.root / "UA").exists())

    def test_json_parser_preserves_field_boundaries(self):
        if OPTIONS.shell != "bash" or OPTIONS.parser == "regex":
            return
        # A newline split would shift the path into the session field.
        self.invoke({"tool_name": "view\n/cache/upgrade/skills/test-skill/SKILL.md",
                     "session_id": "session-1",
                     "tool_input": {"path": "session-1"}})
        self.assert_no_log()
        self.invoke({"tool_name": "view\0/cache/upgrade/skills/test-skill/SKILL.md\0session-1",
                     "tool_input": {"path": "/repo/Example.cs"}})
        self.assert_no_log()
        self.invoke({"tool_name": "view", "session_id": "session-1",
                     "tool_input": {"path": "/cache/upgrade/skills/a skill/SKILL.md"}})
        self.assert_log(skill="a skill")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shell", choices=("powershell", "bash"), required=True)
    parser.add_argument("--executable")
    parser.add_argument("--parser", choices=("python", "regex", "jq"), default="python")
    parser.add_argument("--wrapper", action="store_true")
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
