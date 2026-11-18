#!/usr/bin/env python3
"""Create experiments/<date>_<slug>/ for one ORANSlice run on a lab X310.

  ./cerise/new_experiment.py --host ws02 --slug srs0-sweep --set do_SRS=0
  ./cerise/new_experiment.py --host ws02 --slug baseline --date 2026-11-20 --dry-run

The folder gets:
  README.md        purpose, setup, bring-up, runs table, results (fill in)
  gnb.conf         the repository's X310 conf with this host's X310 address and
                   any --set overrides; edit it here, not the source conf
  rrmPolicy.json   the slice policy this experiment starts from
  start_gnb.sh     runs cerise/run_gnb_x310.sh on this folder
Run logs go to logs/<run-id>/ (git-ignored). See experiments/README.md.
"""

import argparse
import datetime as dt
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

CERISE_DIR = Path(__file__).resolve().parent
REPO_DIR = CERISE_DIR.parent
SRC_CONF = REPO_DIR / "oai_ran/targets/PROJECTS/GENERIC-NR-5GC/CONF/ORANSlice.gnb.sa.band78.fr1.106PRB.usrpx310.conf"
SRC_POLICY = CERISE_DIR / "rrmPolicy.json"

# X310 seen from each host. Only an address observed in a run belongs here.
HOSTS = {
    "ws02": {
        "label": "WS-02 (cerise-Precision-5860-Tower02, 172.16.2.210)",
        "x310": "192.168.40.3",
        "x310_note": "opened with the system UHD 4.8.0 on 2026-11-17",
        "uhd": "system UHD 4.8.0 (/usr/local/lib)",
    },
    "ws03": {
        "label": "WS-03 (cerise-Precision-5860-Tower03, 172.16.2.83)",
        "x310": None,  # not observed from this repository; pass --x310-addr
        "x310_note": "given with --x310-addr",
        "uhd": "private UHD 4.4.0 (~/uhd-4.4.0), per cerise/README.md; not re-checked",
    },
}


def git(*args):
    try:
        return subprocess.run(["git", "-C", str(REPO_DIR), *args], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def apply_set(text, key, value):
    """Replace the value of one `key = ...;` line; the key must occur exactly once."""
    pattern = re.compile(r"^(\s*" + re.escape(key) + r"\s*=\s*)[^;]*;", re.MULTILINE)
    matches = pattern.findall(text)
    if len(matches) != 1:
        raise SystemExit(f"--set {key}: found {len(matches)} '{key} = ...;' lines in the conf, need exactly 1")
    return pattern.sub(lambda m: m.group(1) + value + ";", text)


def build_conf(x310, overrides):
    text = SRC_CONF.read_text().replace("\r", "")
    text, n = re.subn(r"addr=192\.168\.40\.\d+", f"addr={x310}", text)
    if n != 1:
        raise SystemExit(f"expected one X310 address in {SRC_CONF.name}, found {n}")
    for key, value in overrides:
        text = apply_set(text, key, value)
    header = (
        "# Written by cerise/new_experiment.py from\n"
        f"# {SRC_CONF.relative_to(REPO_DIR)}\n"
        "# This is the conf the experiment runs: edit it here and record why in README.md.\n"
        "# run_gnb_x310.sh points SliceConf at this folder's rrmPolicy.json at run time.\n"
    )
    return header + text


README = """# {name}

Created {created} with `{command}`
(repository `{commit}`{dirty}).

## Purpose

TODO: the question this experiment answers, and what result would answer it.

## Setup

| Item | Value |
|---|---|
| gNB host | {host_label} |
| X310 | `{x310}` ({x310_note}) |
| UHD | {uhd} |
| gNB build | `~/cerise_oranslice` at the commit above; record `git -C ~/cerise_oranslice log -1 --oneline` on the host |
| gNB conf | `gnb.conf`: the repository conf (sha256 `{conf_sha}`) with {changes} |
| Slice policy | `rrmPolicy.json` at start: {policy} |
| Core | legacy OAI core v1.5.1, `oai_cn/oai-cn5g-legacy/` (AMF 192.168.70.132, gNB 192.168.70.129) |
| UE | Telit FN990 on the laptop, SIM ...0777, DNN `oai` from modem context 1, NetworkManager profile `oai` |

## Bring-up

Step by step in [`docs/guide-run-on-ws02.md`](../../docs/guide-run-on-ws02.md). In short, on the gNB host:

```bash
cd ~/cerise_oranslice && git pull --ff-only
EXP=experiments/{name}
./cerise/preflight.sh $EXP               # radio free, host tuning, core
$EXP/start_gnb.sh                        # Ctrl-C to stop
./cerise/set_slice_policy.py $EXP --max 50   # second terminal, while it runs
./cerise/collect_run.sh $EXP             # after Ctrl-C, before stopping the core
```

## What to look for

TODO: the log lines or numbers that decide the question
(`./cerise/summarize_gnb_log.sh` counts the usual ones).

## Runs

Times are lab time (UTC-3). Log folders are `logs/<run-id>/` (git-ignored).

| Run ID | Start | What changed | Result |
|---|---|---|---|

## Results

Observed numbers only; mark anything inferred, and write "not measured" rather than guess.

## Open issues
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", required=True, choices=sorted(HOSTS), help="gNB host")
    parser.add_argument("--slug", required=True, help="short name, e.g. srs0-sweep (the host is prefixed)")
    parser.add_argument("--date", default=dt.date.today().isoformat(), help="planned run date (default: today)")
    parser.add_argument("--x310-addr", help="X310 address (default: the host's known one)")
    parser.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                        help="override one conf setting, e.g. do_SRS=0 (repeatable; the key must occur once)")
    parser.add_argument("--dry-run", action="store_true", help="print what would be written")
    args = parser.parse_args()

    host = HOSTS[args.host]
    x310 = args.x310_addr or host["x310"]
    if not x310:
        parser.error(f"no known X310 address for {args.host}: pass --x310-addr (check with uhd_find_devices on the host)")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", args.slug):
        parser.error("--slug: lower-case letters, digits and dashes only")
    dt.date.fromisoformat(args.date)

    overrides = []
    for item in args.set:
        key, sep, value = item.partition("=")
        if not sep or not key.strip() or not value.strip():
            parser.error(f"--set {item!r}: use KEY=VALUE")
        overrides.append((key.strip(), value.strip()))

    name = f"{args.date}_{args.host}-{args.slug}"
    out = REPO_DIR / "experiments" / name
    if out.exists():
        parser.error(f"{out.relative_to(REPO_DIR)} already exists")

    conf = build_conf(x310, overrides)
    changes = ", ".join([f"X310 address `{x310}`"] + [f"`{k} = {v}`" for k, v in overrides])
    policy = ", ".join(
        f"SST {p['sst']}: dedicated {p['dedicated_ratio']} %, min {p['min_ratio']} %, max {p['max_ratio']} %"
        for p in json.loads(SRC_POLICY.read_text())["rrmPolicyRatio"]
    )
    commit = git("rev-parse", "--short", "HEAD") or "unknown"
    dirty = " with uncommitted changes" if git("status", "--porcelain", "--untracked-files=no") else ""
    readme = README.format(
        name=name,
        created=dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        command="./cerise/new_experiment.py " + " ".join(sys.argv[1:]),
        commit=commit,
        dirty=dirty,
        host_label=host["label"],
        x310=x310,
        x310_note=host["x310_note"] if not args.x310_addr else "given with --x310-addr",
        uhd=host["uhd"],
        conf_sha=hashlib.sha256(SRC_CONF.read_bytes()).hexdigest()[:12],
        changes=changes,
        policy=policy,
    )
    start = (
        "#!/usr/bin/env bash\n"
        "# Runs the ORANSlice gNB with this folder's gnb.conf and rrmPolicy.json.\n"
        "# Logs go to logs/<run-id>/. Env and options: cerise/run_gnb_x310.sh.\n"
        'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
        'exec "${here}/../../cerise/run_gnb_x310.sh" "${here}" "$@"\n'
    )

    if args.dry_run:
        print(f"would create {out.relative_to(REPO_DIR)}/ with README.md, gnb.conf, rrmPolicy.json, start_gnb.sh")
        print(f"conf changes: {changes}")
        return 0

    out.mkdir(parents=True)
    (out / "README.md").write_text(readme)
    (out / "gnb.conf").write_text(conf)
    shutil.copyfile(SRC_POLICY, out / "rrmPolicy.json")
    (out / "start_gnb.sh").write_text(start)
    (out / "start_gnb.sh").chmod(0o755)
    print(f"created {out.relative_to(REPO_DIR)}/")
    print(f"conf changes: {changes}")
    print("next: fill in Purpose and What to look for in its README.md, commit, then run it on the host")
    return 0


if __name__ == "__main__":
    sys.exit(main())
