#!/usr/bin/env python3
"""Exercise the shared project lock with synthetic commands, without Ghidra."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest


WRAPPER = Path(__file__).with_name("with-project-lock.py")


@unittest.skipIf(sys.platform == "win32", "The wrapper uses POSIX fcntl locks")
class ProjectLockTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.lock = self.root / "nested" / "project.lock"
        self.processes = []
        self.child_groups = []

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)
        for group in self.child_groups:
            try:
                os.killpg(group, signal.SIGTERM)
            except ProcessLookupError:
                pass
        # Tree fixtures share stdout with their descendants. EOF confirms they
        # have exited before their temporary files are removed, even on failure.
        for process in self.processes:
            try:
                process.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                for group in self.child_groups:
                    try:
                        os.killpg(group, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                process.communicate(timeout=2)
        self.temporary.cleanup()

    def command(self, *arguments):
        return [sys.executable, str(WRAPPER), "--lock", str(self.lock), *arguments]

    def wait_for(self, condition, explanation):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(0.01)
        self.fail(explanation)

    def start_launcher_and_descendant(self):
        """A shell-like launcher that retains inherited descriptors in its child."""
        descendant = self.root / "descendant.py"
        descendant.write_text(textwrap.dedent("""\
            from pathlib import Path
            import signal
            import sys
            import time
            root = Path(sys.argv[1])
            def terminate(signum, frame):
                (root / "descendant.terminated").touch()
                sys.exit(0)
            signal.signal(signal.SIGTERM, terminate)
            (root / "descendant.ready").touch()
            deadline = time.monotonic() + 8
            while not (root / "release").exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            """), encoding="utf-8")
        launcher = self.root / "launcher.py"
        launcher.write_text(textwrap.dedent("""\
            import os
            from pathlib import Path
            import subprocess
            import sys
            import time
            root = Path(sys.argv[1])
            (root / "launcher.pid").write_text(str(os.getpid()))
            child = subprocess.Popen([sys.executable, str(root / "descendant.py"), str(root)],
                                     close_fds=False)
            deadline = time.monotonic() + 3
            while not (root / "descendant.ready").exists():
                if time.monotonic() >= deadline:
                    sys.exit(46)
                time.sleep(0.01)
            (root / "launcher.ready").touch()
            sys.exit(child.wait())
            """), encoding="utf-8")
        log = (self.root / "launcher.stderr").open("w")
        self.addCleanup(log.close)
        process = subprocess.Popen(
            self.command("--", sys.executable, str(launcher), str(self.root)),
            stdout=subprocess.PIPE, stderr=log,
        )
        self.processes.append(process)
        self.wait_for(lambda: (self.root / "launcher.pid").exists() and
                      (self.root / "launcher.pid").read_text().strip(),
                      "Launcher did not start")
        self.child_groups.append(int((self.root / "launcher.pid").read_text()))
        self.wait_for(lambda: (self.root / "launcher.ready").exists(),
                      "Descendant did not become ready")
        return process

    def test_simultaneous_commands_do_not_overlap(self):
        child = self.root / "child.py"
        child.write_text(textwrap.dedent("""\
            import json
            import os
            from pathlib import Path
            import sys
            import time

            root, name = Path(sys.argv[1]), sys.argv[2]
            active = root / "active"
            try:
                fd = os.open(active, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            except FileExistsError:
                sys.exit(41)  # Another child is still in the critical section.
            os.close(fd)
            def record(event):
                entry = {"child": name, "event": event, "at": time.monotonic_ns()}
                with (root / "events.jsonl").open("a") as stream:
                    stream.write(json.dumps(entry) + "\\n")
            try:
                record("start")
                (root / (name + ".started")).touch()
                deadline = time.monotonic() + 5
                while not (root / "release").exists():
                    if time.monotonic() >= deadline:
                        sys.exit(45)
                    time.sleep(0.01)
                record("end")
            finally:
                active.unlink()
            """), encoding="utf-8")

        with (self.root / "first.stderr").open("w") as first_log, \
                (self.root / "second.stderr").open("w") as second_log:
            first = subprocess.Popen(
                self.command("--", sys.executable, str(child), str(self.root), "first"),
                stdout=subprocess.PIPE, stderr=first_log, text=True,
            )
            self.processes.append(first)
            self.wait_for(lambda: (self.root / "first.started").exists(),
                          "First child did not enter the critical section")
            second = subprocess.Popen(
                self.command("--", sys.executable, str(child), str(self.root), "second"),
                stdout=subprocess.PIPE, stderr=second_log, text=True,
            )
            self.processes.append(second)
            self.wait_for(
                lambda: "Waiting for project lock:" in
                (self.root / "second.stderr").read_text(),
                "Second wrapper did not reach its lock request",
            )
            time.sleep(0.15)
            self.assertIsNone(second.poll(), "Second command should still be waiting")
            self.assertFalse((self.root / "second.started").exists())
            (self.root / "release").touch()
            first.communicate(timeout=5)
            second.communicate(timeout=5)

        self.assertEqual(first.returncode, 0, (self.root / "first.stderr").read_text())
        self.assertEqual(second.returncode, 0, (self.root / "second.stderr").read_text())
        events = [json.loads(line) for line in (self.root / "events.jsonl").read_text().splitlines()]
        self.assertEqual([(entry["child"], entry["event"]) for entry in events],
                         [("first", "start"), ("first", "end"),
                          ("second", "start"), ("second", "end")])
        self.assertLess(events[1]["at"], events[2]["at"])

    def test_exit_status_and_child_stdout_are_preserved(self):
        for status in (0, 7, 42):
            with self.subTest(status=status):
                result = subprocess.run(
                    self.command("--", sys.executable, "-c",
                                 f"import sys; print('child output'); sys.exit({status})"),
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(result.stdout, "child output\n")
        # The final success also proves that an earlier failure released the lock.
        result = subprocess.run(
            self.command("--", sys.executable, "-c", "pass"),
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_command_is_rejected_before_lock_creation(self):
        for arguments in ((), ("--",)):
            with self.subTest(arguments=arguments):
                result = subprocess.run(self.command(*arguments),
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 2)
                self.assertIn("a command is required after --", result.stderr)
                self.assertFalse(self.lock.exists())

    def test_sigterm_reaches_descendant_and_preserves_signal_exit_status(self):
        process = self.start_launcher_and_descendant()
        process.terminate()
        self.assertEqual(process.wait(timeout=5), 128 + signal.SIGTERM)
        self.wait_for(lambda: (self.root / "descendant.terminated").exists(),
                      "SIGTERM did not reach the launcher's descendant")

    def test_abrupt_wrapper_exit_keeps_lock_while_child_runs(self):
        process = self.start_launcher_and_descendant()
        process.kill()  # SIGKILL cannot be handled or forwarded by the wrapper.
        self.assertEqual(process.wait(timeout=5), -signal.SIGKILL)
        second_marker = self.root / "second.started"
        with (self.root / "second.stderr").open("w") as log:
            second = subprocess.Popen(
                self.command("--", sys.executable, "-c",
                             "from pathlib import Path; import sys; Path(sys.argv[1]).touch()",
                             str(second_marker)),
                stdout=subprocess.DEVNULL, stderr=log,
            )
            self.processes.append(second)
            self.wait_for(
                lambda: "Waiting for project lock:" in
                (self.root / "second.stderr").read_text(),
                "Second wrapper did not reach its lock request",
            )
            time.sleep(0.15)
            self.assertIsNone(second.poll(), "Surviving child must still hold the lock")
            self.assertFalse(second_marker.exists())
            (self.root / "release").touch()
            self.assertEqual(second.wait(timeout=5), 0)
        self.assertTrue(second_marker.exists())


if __name__ == "__main__":
    unittest.main()
