"""Reject new first-party concurrency diagnostics; duplicate batch output counts once."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re

DIAGNOSTIC = re.compile(r"(?P<path>[^\s]+\.swift):(?P<line>\d+):(?P<column>\d+): warning: (?P<message>.+)")
CONCURRENCY = re.compile(r"Sendable|\bsending\b|data races|actor.isolated|concurrency.safe|unavailable from asynchronous contexts|concurrently.executing|region-based isolation|error in the Swift 6 language mode")


def diagnostics(log, root):
    root = root.resolve()
    found = set()
    for match in DIAGNOSTIC.finditer(log):
        path = Path(match['path'])
        if path.is_absolute():
            try:
                path = path.relative_to(root)
            except ValueError:
                continue
        if not path.parts or path.parts[0] not in ('Sources', 'Tests'):
            continue
        message = match['message'].strip()
        if CONCURRENCY.search(message):
            found.add((path.as_posix(), match['line'], match['column'], message))
    return Counter((path, message) for path, _, _, message in found)


def excess(actual, baseline):
    allowed = {(entry['path'], entry['message']): entry['count'] for entry in baseline['warnings']}
    return {key: count - allowed.get(key, 0) for key, count in actual.items()
            if count > allowed.get(key, 0)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--baseline', type=Path, default=Path(__file__).with_name('concurrency-warning-baseline.json'))
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text())
    if baseline.get('schemaVersion') != 1:
        parser.error('unsupported concurrency baseline schema')
    # Production diagnostics must never be grandfathered into the fixture baseline.
    if any(not entry['path'].startswith('Tests/') or entry['count'] <= 0 for entry in baseline['warnings']):
        parser.error('baseline permits only positive counts of test fixture warnings')
    actual = diagnostics(args.log.read_text(errors='replace'), args.root)
    regressions = excess(actual, baseline)
    for (path, message), count in sorted(regressions.items()):
        print(f'{path}: {count} new concurrency diagnostic(s): {message}')
    print(f'Concurrency diagnostics: {sum(actual.values())} distinct, {sum(regressions.values())} beyond baseline')
    return bool(regressions)


if __name__ == '__main__':
    raise SystemExit(main())
