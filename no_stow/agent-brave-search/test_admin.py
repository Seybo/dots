"""Test admin functions with mocked commands; never invoke the admin entry point."""

from pathlib import Path
import re
import subprocess
import unittest


ADMIN = Path(__file__).resolve().parents[1] / "bin/agent-brave-search-admin"
SOURCE = ADMIN.read_text()


def function(name):
    return re.search(rf"^{name}\(\) \{{\n.*?^\}}", SOURCE, re.M | re.S).group()


class AdminTest(unittest.TestCase):
    def run_functions(self, body, mocks=""):
        script = "\n".join([
            "set -euo pipefail",
            'socket_dir=/var/tmp/agent-broker; socket_path=$socket_dir/brave-search.sock',
            'log_dir=/var/log/agent-broker/brave-search',
            'service_user=_agentbroker; service_group=staff',
            'label=local.agent-broker.brave-search; plist_path=/broker.plist',
            'repo_root=/repo; ruby_bin=mock_ruby',
            'require_root() { :; }',
            'mkdir() { printf "mkdir %s\\n" "$*"; }',
            'chown() { printf "chown %s\\n" "$*"; }',
            'chmod() { printf "chmod %s\\n" "$*"; }',
            'launchctl() { printf "launchctl %s\\n" "$*"; }',
            'sleep() { :; }',
            function("prepare_runtime_directories"),
            function("wait_for_health"),
            function("load_command"),
            mocks,
            body,
        ])
        return subprocess.run(["bash", "-c", script], capture_output=True, text=True)

    def test_load_repairs_directories_before_starting(self):
        result = self.run_functions("load_command", 'mock_ruby() { return 0; }')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            "mkdir -p /var/tmp/agent-broker /var/log/agent-broker/brave-search",
            "chown _agentbroker:staff /var/tmp/agent-broker /var/log/agent-broker/brave-search",
            "chmod 0750 /var/tmp/agent-broker /var/log/agent-broker/brave-search",
            "launchctl bootstrap system /broker.plist",
            "launchctl kickstart -k system/local.agent-broker.brave-search",
            "Broker health check passed.",
        ])
        self.assertIn("prepare_runtime_directories", function("install_broker"))

    def test_health_retries_until_ready(self):
        result = self.run_functions(
            'wait_for_health; echo "attempts=$attempt_count"',
            'attempt_count=0; mock_ruby() { attempt_count=$((attempt_count + 1)); [[ $attempt_count -eq 3 ]]; }',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("attempts=3", result.stdout)

    def test_health_failure_is_bounded_and_reported(self):
        result = self.run_functions(
            'if wait_for_health; then exit 99; fi; echo "attempts=$attempt_count"',
            'attempt_count=0; mock_ruby() { attempt_count=$((attempt_count + 1)); return 1; }',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("attempts=10", result.stdout)
        self.assertIn("stderr.log and launchd status", result.stderr)

    def test_directory_failure_prevents_start(self):
        result = self.run_functions("load_command", 'mkdir() { return 1; }')
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("bootstrap", result.stdout)

    def test_bootstrap_failure_prevents_health_check(self):
        result = self.run_functions(
            "load_command",
            'launchctl() { [[ $1 != bootstrap ]]; }; mock_ruby() { echo unexpected >&2; return 0; }',
        )
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("unexpected", result.stderr)


if __name__ == "__main__":
    unittest.main()
