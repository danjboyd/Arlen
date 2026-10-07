#!/usr/bin/env python3
"""Checks for the xctest flake-hunting passthroughs and the no-retry policy.

ITERATIONS / UNTIL_FAILURE reach the vendored runner as -test-iterations /
-run-tests-until-failure. -retry-tests-on-failure must stay out of the build
and CI wiring: a retried pass hides the races and lifecycle bugs the
sanitizer and reliability lanes exist to catch (issue #113).
"""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
RETRY_FLAG = "-retry-tests-on-failure"


# Prints, without running it, the runner command a filtered unit run would use.
# The probe target has no prerequisites, so this needs no build, GNUstep
# environment, or checked-out submodule (`make -n` would still recurse into the
# vendored runner's build).
PROBE = ("arlen-repetition-probe: ; @:$(info $(call xctest_run,$(UNIT_TEST_BUNDLE))"
         " $(call xctest_filter_args,$(UNIT_TEST_TARGET_NAME)))")


def runner_command(*args):
    env = {key: value for key, value in os.environ.items()
           if key not in ("ITERATIONS", "UNTIL_FAILURE", "TEST", "SKIP_TEST", "MAKEFLAGS")}
    return subprocess.run(["make", "--no-print-directory", "--eval", PROBE,
                           "arlen-repetition-probe", *args], cwd=ROOT, env=env,
                          capture_output=True, text=True, timeout=60, check=False)


class RepetitionPassthroughTests(unittest.TestCase):
    def test_iterations_and_until_failure_reach_the_runner(self):
        result = runner_command("TEST=Foo/testBar", "ITERATIONS=25", "UNTIL_FAILURE=1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-test-iterations 25 -run-tests-until-failure", result.stdout)
        self.assertIn("-only-testing:ArlenUnitTests/Foo/testBar", result.stdout)

    def test_default_run_does_not_repeat(self):
        result = runner_command()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("-test-iterations", result.stdout)
        self.assertNotIn("-run-tests-until-failure", result.stdout)

    def test_invalid_values_are_rejected(self):
        for args in (("ITERATIONS=0",), ("ITERATIONS=many",), ("UNTIL_FAILURE=yes",),
                     ("ITERATIONS=3", "ARLEN_USE_VENDORED_XCTEST=0")):
            with self.subTest(args=args):
                result = runner_command(*args)
                self.assertNotEqual(result.returncode, 0, result.stdout)


class NoRetryPolicyTests(unittest.TestCase):
    def test_build_and_ci_wiring_never_retries_failed_tests(self):
        paths = [ROOT / "GNUmakefile"]
        paths += sorted((ROOT / ".github/workflows").glob("*.yml"))
        paths += sorted((ROOT / "tools/ci").glob("*.sh"))
        paths += [path for path in sorted((ROOT / "tools/ci").glob("*.py"))
                  if path.name != Path(__file__).name]
        offenders = [str(path.relative_to(ROOT)) for path in paths
                     if RETRY_FLAG in path.read_text(encoding="utf-8")]
        self.assertEqual(offenders, [], f"{RETRY_FLAG} is not allowed in build or CI wiring")


if __name__ == "__main__":
    unittest.main()
