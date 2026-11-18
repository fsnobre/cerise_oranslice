#!/usr/bin/env python3
"""Set the PRB ratios of one slice in an experiment's rrmPolicy.json.

The gNB re-reads the file every 128 frames (1.28 s), so a change takes effect
while it runs. This tool checks the values the way the gNB would and replaces
the file atomically, so the gNB never reads a half-written file. Every change
is appended, with its time, to logs/policy_changes.tsv beside the file.

  EXP=experiments/2026-11-19_ws02-srs0-sweep
  ./cerise/set_slice_policy.py $EXP                       # show the current policy
  ./cerise/set_slice_policy.py $EXP --max 50              # SST 1 / SD FFFFFF
  ./cerise/set_slice_policy.py $EXP --dedicated 10 --min 30 --max 100
  ./cerise/set_slice_policy.py $EXP --sst 1 --sd 000002 --min 10 --max 40

The target is an experiment folder or a policy file; without one it is
cerise/rrmPolicy.json, the template new experiments start from.

Ratios are percentages of the cell's PRBs (0-100):
  dedicated  PRBs reserved for the slice even when it has no traffic
  min        PRBs guaranteed to the slice when it has traffic
  max        upper limit for the slice
The gNB requires dedicated <= min <= max for each slice, and the sums of min and
of dedicated over all slices at or below 100 (otherwise it resets them to 0).
A slice that is not in the gNB conf's snssaiList is ignored by the gNB.
"""

import argparse
import datetime as dt
import json
import os
import sys
import tempfile
from pathlib import Path

DEFAULT_FILE = Path(__file__).resolve().parent / "rrmPolicy.json"
SD_DEFAULT = 0xFFFFFF


def ratio(text):
    value = int(text)
    if not 0 <= value <= 100:
        raise argparse.ArgumentTypeError("must be between 0 and 100")
    return value


def slice_key(entry):
    # The gNB reads a missing "sd" (or 0) as FFFFFF.
    return int(entry["sst"]), int(entry.get("sd", 0)) or SD_DEFAULT


def describe(entries):
    for e in entries:
        sst, sd = slice_key(e)
        print(f"SST {sst} SD {sd:06X}: dedicated {e['dedicated_ratio']}%, min {e['min_ratio']}%, max {e['max_ratio']}%")


def check(entries):
    errors = []
    seen = set()
    for e in entries:
        key = slice_key(e)
        if key in seen:
            errors.append(f"SST {key[0]} SD {key[1]:06X} appears twice")
        seen.add(key)
        d, lo, hi = e["dedicated_ratio"], e["min_ratio"], e["max_ratio"]
        if not d <= lo <= hi:
            errors.append(f"SST {key[0]} SD {key[1]:06X}: need dedicated <= min <= max, got {d} / {lo} / {hi}")
    for field in ("min_ratio", "dedicated_ratio"):
        total = sum(e[field] for e in entries)
        if total > 100:
            errors.append(f"sum of {field} over all slices is {total}, above 100")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", nargs="?", type=Path, default=DEFAULT_FILE,
                        help="experiment folder or policy file (default: %(default)s)")
    parser.add_argument("--sst", type=int, default=1)
    parser.add_argument("--sd", default="FFFFFF", help="hex slice differentiator (default FFFFFF)")
    parser.add_argument("--dedicated", type=ratio)
    parser.add_argument("--min", type=ratio)
    parser.add_argument("--max", type=ratio)
    parser.add_argument("--remove", action="store_true", help="remove this slice's entry")
    args = parser.parse_args()

    args.file = args.target / "rrmPolicy.json" if args.target.is_dir() else args.target
    if not args.file.exists():
        parser.error(f"no policy file at {args.file}")
    print(f"{args.file}:")
    data = json.loads(args.file.read_text())
    entries = data["rrmPolicyRatio"]

    if args.dedicated is None and args.min is None and args.max is None and not args.remove:
        describe(entries)
        return 0

    sd = int(args.sd, 16)
    key = (args.sst, sd)
    current = next((e for e in entries if slice_key(e) == key), None)
    if args.remove:
        entries = [e for e in entries if slice_key(e) != key]
    else:
        if current is None:
            current = {"sst": args.sst, "dedicated_ratio": 0, "min_ratio": 0, "max_ratio": 100}
            if sd != SD_DEFAULT:
                current["sd"] = sd  # the gNB reads sd as an integer, not a hex string
            entries.append(current)
        for field, value in (("dedicated_ratio", args.dedicated), ("min_ratio", args.min), ("max_ratio", args.max)):
            if value is not None:
                current[field] = value

    errors = check(entries)
    if errors:
        print("Not written:\n  " + "\n  ".join(errors), file=sys.stderr)
        return 1

    data["rrmPolicyRatio"] = entries
    # Write a temporary file next to the target and rename it over the target.
    fd, tmp = tempfile.mkstemp(dir=args.file.parent, prefix=".rrmPolicy.", suffix=".json")
    with os.fdopen(fd, "w") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, args.file)
    describe(entries)
    record(args.file, entries, "remove" if args.remove else "set", key)
    return 0


def record(policy_file, entries, action, key):
    """Append the change and the resulting policy to logs/policy_changes.tsv."""
    history = policy_file.parent / "logs" / "policy_changes.tsv"
    history.parent.mkdir(exist_ok=True)
    new = not history.exists()
    with history.open("a") as handle:
        if new:
            handle.write("time\taction\tslice\tpolicy_after (sst/sd dedicated/min/max %)\n")
        now = dt.datetime.now().astimezone().isoformat(timespec="seconds")
        after = "; ".join(
            f"{slice_key(e)[0]}/{slice_key(e)[1]:06X} {e['dedicated_ratio']}/{e['min_ratio']}/{e['max_ratio']}" for e in entries
        )
        handle.write(f"{now}\t{action}\t{key[0]}/{key[1]:06X}\t{after}\n")
    print(f"recorded in {history}")


if __name__ == "__main__":
    sys.exit(main())
