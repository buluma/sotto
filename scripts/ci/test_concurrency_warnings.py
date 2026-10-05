"""Controls for concurrency baseline matching and duplicate diagnostic output."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('concurrency', Path(__file__).with_name('check_concurrency_warnings.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ConcurrencyBaselineTests(unittest.TestCase):
    root = Path('/work/sotto')
    warning = "capture of 'value' with non-Sendable type 'Fixture' in a '@Sendable' closure"

    def line(self, path='Tests/Fixture.swift', line=10):
        return f'{self.root}/{path}:{line}:4: warning: {self.warning}\n'

    def test_duplicate_batches_count_once_but_new_sites_count_separately(self):
        actual = checker.diagnostics(self.line() * 24 + self.line(line=20), self.root)
        self.assertEqual(sum(actual.values()), 2)

    def test_dependencies_and_non_concurrency_warnings_are_excluded(self):
        log = self.line('.build/checkouts/Dependency/Sources/Fixture.swift')
        log += '/elsewhere/Sources/Fixture.swift:10:4: warning: non-Sendable type\n'
        log += f'{self.root}/Tests/Fixture.swift:10:4: warning: variable was never mutated\n'
        self.assertFalse(checker.diagnostics(log, self.root))

    def test_baseline_is_stable_when_source_lines_move(self):
        baseline = {'warnings': [{'path': 'Tests/Fixture.swift', 'message': self.warning, 'count': 1}]}
        self.assertFalse(checker.excess(checker.diagnostics(self.line(line=200), self.root), baseline))

    def test_new_diagnostic_or_new_site_exceeds_baseline(self):
        baseline = {'warnings': [{'path': 'Tests/Fixture.swift', 'message': self.warning, 'count': 1}]}
        actual = checker.diagnostics(self.line() + self.line(line=20) + self.line('Tests/New.swift'), self.root)
        self.assertEqual(sum(checker.excess(actual, baseline).values()), 2)

    def test_production_has_no_allowances(self):
        actual = checker.diagnostics(self.line('Sources/Fixture.swift'), self.root)
        self.assertEqual(sum(checker.excess(actual, {'warnings': []}).values()), 1)

    def test_region_based_isolation_checker_warnings_are_included(self):
        log = f'{self.root}/Tests/Fixture.swift:10:4: warning: pattern that the region-based isolation checker does not understand how to check\n'
        self.assertEqual(sum(checker.diagnostics(log, self.root).values()), 1)

    def test_async_lock_and_actor_warnings_are_included(self):
        log = f'{self.root}/Tests/Fixture.swift:10:4: warning: instance method lock is unavailable from asynchronous contexts\n'
        log += f'{self.root}/Tests/Fixture.swift:20:4: warning: main actor-isolated property cannot be referenced\n'
        self.assertEqual(sum(checker.diagnostics(log, self.root).values()), 2)


if __name__ == '__main__':
    unittest.main()
