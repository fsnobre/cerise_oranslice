# Experiments

One folder per experiment: `experiments/<date>_<host>-<slug>/`. The folder holds
everything needed to run it again (conf, starting policy, launcher) and the record
of what happened (its `README.md`). Run logs stay in its `logs/`, which git
ignores: the core logs hold SIM session keys.

| Experiment | Question | Status |
|---|---|---|
| [`2026-11-17_ws02-first-sweep`](2026-11-17_ws02-first-sweep/README.md) | First end-to-end ORANSlice run; does the downlink follow the slice cap? | Done: about 11 Mbit/s at 100 % and 50 %, link lost before 20 %; full log review |
| [`2026-11-18_ws02-srs0-sweep`](2026-11-18_ws02-srs0-sweep/README.md) | Does `do_SRS = 0` stabilise the link, and then does the downlink follow 100/50/20/100 %? | Planned, not run |

## Folder contents

| File | Written by | What it is |
|---|---|---|
| `README.md` | `cerise/new_experiment.py`, then us | Purpose, setup, bring-up, plan, what to look for, runs table, results, open issues |
| `gnb.conf` | `cerise/new_experiment.py` | The conf this experiment runs: the repository's X310 conf with the host's X310 address and the `--set` overrides. Change it here, never the source conf, and say why in the README |
| `rrmPolicy.json` | `cerise/new_experiment.py`, then `set_slice_policy.py` | The live slice policy. Committed at its starting value; reset it to that value after the run |
| `start_gnb.sh` | `cerise/new_experiment.py` | Runs `cerise/run_gnb_x310.sh` on this folder |
| `logs/<run-id>/` | `run_gnb_x310.sh`, `collect_run.sh`, the speed test | One folder per gNB start (git-ignored), see below |
| `logs/latest` | `run_gnb_x310.sh` | Link to the newest run |
| `logs/policy_changes.tsv` | `set_slice_policy.py` | Every policy change with its time |

A run folder `logs/<run-id>/` (the id is the gNB start time, `YYYYmmdd_HHMMSS`
host time) ends up with:

| File | From |
|---|---|
| `gnb.log`, `gnb.conf`, `gnb.cmd`, `run_info.txt` | `run_gnb_x310.sh` at start: output with Unix-second stamps, the exact conf and command, host, commit, UHD, policy at start |
| `core/*.log`, `core/state.txt` | `collect_run.sh`: `docker logs -t` of every core container (UTC), slice/DNN/NAT settings |
| `rrmPolicy_at_end.json`, `policy_changes.tsv`, `summary.txt` | `collect_run.sh` |
| `laptop/speedtest_diag_*` | `fn990_speedtest.sh --out-parent` on the laptop (copied in afterwards, step 9 of the guide) |

The first experiment (`2026-11-17_ws02-first-sweep`) predates this layout; its
`logs/` has `gnb/`, `core/`, `laptop/` and `earlier_core_logs/` instead.

## Lifecycle

1. **Plan** on the laptop:
   ```bash
   ./cerise/new_experiment.py --host ws02 --slug <slug> [--set do_SRS=0] [--date YYYY-MM-DD]
   ```
   Fill in Purpose, Plan and What to look for in its `README.md`: what question,
   which numbers or log lines answer it, and when to stop early. Add it to the
   table above. Commit and push, so the host can pull it.
2. **Run** on the host, following [`../docs/guide-run-on-ws02.md`](../docs/guide-run-on-ws02.md).
   Write down every start time and every manual step as it happens (a text
   file or the README's Runs table): `tee`'d logs from the laptop side have no
   wall-clock stamps.
3. **Collect** before stopping the core (`./cerise/collect_run.sh $EXP`), then copy
   `logs/` to the laptop with `rsync` started from the laptop.
4. **Review** with [`../docs/guide-log-review.md`](../docs/guide-log-review.md). Fill
   in Runs and Results: observed numbers only, inferred things marked as such,
   "not measured" rather than a guess. Never paste key material from core logs.
5. **Close**: reset `rrmPolicy.json` to its starting value, update the status
   here, add a section to today's `docs/handoffs/YYYY-MM-DD.md`, and move
   anything still open to `docs/README.md` (Open items).

## Rules

- One question per experiment. A different conf is a new experiment
  (`new_experiment.py` again), not an edit to a finished one's `gnb.conf`.
- Never commit anything under `logs/` (`git add` paths explicitly; `.gitignore`
  covers `experiments/*/logs/`).
- Record each policy change through `set_slice_policy.py`, so
  `policy_changes.tsv` has its time, and confirm it in `gnb.log`
  (`rrmPolicy.max_ratio N`).
- Keep the folder name's date as the planned run date; if the run slips to
  another day, keep the name and note the real date in Runs.
