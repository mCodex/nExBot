"""Require per-package test coverage from the first-party Rust LCOV report."""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--branches", action="store_true")
    args = parser.parse_args()

    rust = Path(__file__).resolve().parents[1] / "rust"
    roots = {
        package.name: package
        for folder in ("apps", "crates")
        for package in (rust / folder).iterdir()
        if (package / "Cargo.toml").is_file()
    }
    if not roots:
        parser.error("no Rust packages found")

    totals = {name: dict.fromkeys(("LF", "LH", "BRF", "BRH"), 0) for name in roots}
    target = None

    for line in args.report.read_text().splitlines():
        if line.startswith("SF:"):
            source = Path(line[3:])
            candidates = (source, rust / source, rust.parent / source)
            target = next(
                (
                    name
                    for name, package in roots.items()
                    if any(candidate.is_relative_to(package / "src") for candidate in candidates)
                ),
                None,
            )
        elif line == "end_of_record":
            target = None
        elif target is not None:
            key, _, value = line.partition(":")
            if key in totals[target]:
                totals[target][key] += int(value)

    failed = False
    for package, count in sorted(totals.items()):
        dimensions = [("line", "LH", "LF")]
        if args.branches and package in {"nexbot-engine", "nexbot-updater"}:
            dimensions.append(("branch", "BRH", "BRF"))

        for dimension, numerator, denominator in dimensions:
            hit, found = count[numerator], count[denominator]
            percent = 100 * hit / found if found else 0
            print(f"{package} {dimension} coverage: {percent:.2f}% ({hit}/{found})")
            if found == 0 or hit * 10 < found * 9:
                failed = True

    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
