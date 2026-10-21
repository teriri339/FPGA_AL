"""Count completed unique regression configurations, never nested PASS lines.

Read-only. Interrupted/in-progress logs do not pass. Expected-failure baseline
experiments must not be supplied as successful extra checks.
"""
import argparse
import glob
import json
from pathlib import Path
import re


def passed(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    bad = re.search(r"(?im)^\s*#?\s*(?:\*\*\s*(?:Fatal|Error):|Errors:\s*[1-9])", text)
    return bool("PASS" in text and "End time:" in text and not bad)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", nargs="+")
    parser.add_argument("--extra", action="append", default=[], metavar="NAME=LOG")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    script = (repo / "tools/test_raw_display_features.ps1").read_text(encoding="utf-8")
    test_list = re.search(r"\[string\[\]\]\$Tests\s*=\s*@\(([^\n]+)\)", script)
    expected = set(re.findall(r"'([^']+)'", test_list[1]))
    candidates = {}
    for pattern in args.directories:
        for directory in glob.glob(pattern):
            for log in Path(directory).glob("tb_*.log"):
                candidates.setdefault(log.stem, []).append(log)
    for extra in args.extra:
        name, path = extra.split("=", 1)
        expected.add(name)
        candidates.setdefault(name, []).append(Path(path))
    good, pending = {}, []
    for name in sorted(expected):
        successful = [p for p in candidates.get(name, []) if p.is_file() and passed(p)]
        if successful:
            good[name] = str(successful[-1])
        else:
            pending.append(name)
    print(json.dumps(dict(expected=len(expected), passed=len(good), pending=pending,
                          evidence=good), ensure_ascii=False, indent=2))
    if pending:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
