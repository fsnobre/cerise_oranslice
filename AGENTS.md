# AGENTS.md — CERISE fork of ORANSlice

This is the CERISE lab's fork of [ORANSlice](https://github.com/wineslab/ORANSlice)
(OAI gNB about 2024.w28 with RAN slicing, plus the OAI cores it ships). Here we run
ORANSlice on the lab's USRP X310 with the Telit FN990 and measure what the slice
policy does. Rules for every coding agent working here. Codex reads this file
directly; Claude Code loads it because the repository has no `CLAUDE.md` (do not add
one).

**Scope.** Slicing on X310 + FN990 only. Handover experiments, the RFsim stacks
and the monitoring dashboard belong to the companion repository
`oai-rfsim-handover-testbed` (`../oai-rfsim-handover-testbed`). Do not carry its
container names, subnets, commands or dashboard rules over here: several facts
differ between the two setups (core version, subnets, UHD, X310 address, host).

## Start here

1. `docs/README.md`: index of every document, and the open items.
2. The newest `docs/handoffs/YYYY-MM-DD.md`, then `experiments/README.md` (workflow and
   the table of experiments) and the newest experiment's `README.md`.
3. `cerise/README.md`: the tools, the build, the conf and the slice policy.
   `docs/guide-run-on-ws02.md` and `docs/guide-log-review.md`: running and reviewing.

## Repository layout

| Path | What it is |
|---|---|
| `oai_ran/` | ORANSlice gNB source (upstream code plus our changes) |
| `oai_cn/` | upstream core material; `oai-cn5g-legacy/` holds the v1.5.1 core used so far |
| `doc/` | upstream figures and patch. Leave it as upstream; our docs go in `docs/` |
| `cerise/` | our tools: `new_experiment.py`, `preflight.sh`, `run_gnb_x310.sh`, `set_slice_policy.py`, `collect_run.sh`, `summarize_gnb_log.sh`, and the policy template `rrmPolicy.json` |
| `experiments/<date>_<host>-<slug>/` | one folder per experiment: `README.md` (purpose, plan, runs, results, review), `gnb.conf`, `rrmPolicy.json`, `start_gnb.sh`, and `logs/` (git-ignored) |
| `docs/` | index and daily handoffs |

## Git rules

- Remotes: `fork` = `fsnobre/cerise_oranslice` (ours; work on `main`), `origin` =
  `wineslab/ORANSlice` (upstream). **Never push to `origin`.**
- Never `git add -A` or `git add .`; stage explicit paths. Raw logs and run trees may
  be lying around.
- Do not push unless asked. Commit per completed work package.
- `experiments/*/logs/` is git-ignored on purpose; never force-add it.

## Secrets and privacy

- Core logs (AMF, AUSF, UDM) contain SIM session keys. They stay in `experiments/*/logs/`
  and are never committed or printed. When quoting core logs, do not print key,
  `Kamf`/`Knas`/`K_gNB`/RES values.
- Refer to SIMs by the last digits of the IMSI (`...0777`). No IMEIs, ICCIDs or
  device serials in committed files.

## Hosts and radio (lab facts; ask the user when unsure)

| Item | Value |
|---|---|
| WS-02 | `ssh ws02` (felipe@172.16.2.210). No passwordless sudo: the user runs `sudo` commands. `/` is nearly full (about 3.5 GB free on 2026-11-17) |
| WS-02 clone | `~/cerise_oranslice`, built with `./build_oai -w USRP --gNB` against the system UHD 4.8.0 (`/usr/local/lib/libuhd.so.4.8.0`) |
| WS-02 X310 | `192.168.40.3`, FPGA 39.3, opens with UHD 4.8.0 |
| WS-03 X310 | `192.168.40.2` per earlier notes, FPGA needs UHD 4.4.0 (not re-checked). The testbed's profile records the opposite pairing (`uhd_find_devices` on 2026-11-13: WS-02 sees .2, WS-03 sees .3); `.3` from WS-02 is the only observation from this repository. Check with `uhd_find_devices` before using WS-03 |
| UE | Telit FN990 on the laptop (`nobre`), ModemManager + NetworkManager, interface `wwan0` |

- **The X310s and the workstations are shared with other lab members.** Do not
  reflash FPGAs, reinstall UHD or change system packages. Other users' home folders
  and trees (for example the ORANSlice tree holding the legacy core compose file on
  WS-02) are read-only for us; copy, do not edit.
- Only one gNB may use a radio at a time; check nobody else is on it first.
- Carrier: our conf uses SSB ARFCN 621312 (3300.60-3338.76 MHz), which very likely
  overlaps Claro's n78 carrier (SSB 3348.48 MHz). The testbed moved to 650016 / 648744
  (3731.16-3769.32 MHz) on 2026-11-16, but the lab's authorization for 3700-3800 MHz
  is unconfirmed. Do not change the carrier without the user's go-ahead.
- Every run goes through an experiment folder (`cerise/new_experiment.py`, then the
  folder's `start_gnb.sh`); see `experiments/README.md`. Do not run `nr-softmodem`
  by hand with a copied conf (that was the 2026-11-17 workaround).
- The gNB log carries Unix-second stamps; the laptop side (`tee`, speed tests) does
  not always. Record start times and manual steps as they happen.
- WS-02 was not reachable over SSH from the laptop on 2026-11-18 (timeout); it may
  be off or off the lab network. Do not assume it is up.

## Core facts (legacy OAI core v1.5.1)

- A PDU session request without an S-NSSAI gets the AMF's **first** supported slice.
  The SMF serves DNN `oai` on SST 1 / SD FFFFFF and `oai2` on SST 1 / SD 000002 (our
  `oai_cn/oai-cn5g-legacy/` compose, and the settings recorded at shutdown on
  2026-11-17); a mismatch is rejected with 5GSM cause 33. Keep SD FFFFFF first
  (`cerise/preflight.sh` checks it).
- The UPF NATs only `12.1.1.0/24` (DNN `oai`). DNN `oai2` addresses (12.1.2.x) leave
  untranslated and get no replies.
- The core containers run with `TZ=Europe/Paris`, so their own stamps are UTC+1 (the
  "AMF one hour ahead"); use the `docker logs -t` column (UTC). The lab is UTC-3.
- Only one legacy core can run per host (fixed container names). On 2026-11-17 the
  one on WS-02 came from another lab member's tree; ours is `oai_cn/oai-cn5g-legacy/`.

## Modem facts (FN990)

- **The DNN comes from the modem's context 1** (`AT+CGDCONT=1,"IP","oai"`), not from
  the NetworkManager profile: on 2026-11-17 the bearer reported APN `oai2` and the
  core still saw DNN `oai`. Set it with `scripts/modem/fn990_set_apn.sh` in the
  testbed repository (single copy there; do not duplicate it here).
- On the laptop, only the NetworkManager profile `oai` exists (autoconnect on, IPv6
  disabled). NetworkManager alone connects the modem: `nmcli connection up oai`,
  fresh session with `down` then `up`. No `mmcli --simple-connect`, no manual
  `ip addr add`, no picking connections from the GNOME menu during a run: each of
  these tears down the session and starts another.
- Speed tests: `scripts/modem/fn990_speedtest.sh` in the testbed repository; its
  output folder is copied into the run's `raw/laptop/`.

## Slice policy

- The MAC re-reads `SliceConf` (the experiment's `rrmPolicy.json`, set by
  `run_gnb_x310.sh`) every 128 frames (about 1.3 s). Only this fork enables that
  (commit `0d22003`); upstream needs the xApp.
- The policy limits the **downlink** scheduler only. Defaults are max 100 %.
- Change it while the gNB runs with `cerise/set_slice_policy.py EXP ...` (writes the
  file atomically and appends the change with its time to `EXP/logs/policy_changes.tsv`).
  Reset to the experiment's starting values after a run.
- Confirm a change in the gNB log (`Slice 1, NSSAI 1.ffffff, ... max_ratio N`).

## Validation

No test suite. Before committing changes to our files:

```bash
for f in cerise/*.sh experiments/*/start_gnb.sh; do bash -n "$f" || echo "FAIL $f"; done
python3 -m py_compile cerise/*.py
./cerise/new_experiment.py --host ws02 --slug check --dry-run
```

`cerise/summarize_gnb_log.sh` can be checked against
`experiments/2026-11-17_ws02-first-sweep/logs/gnb/gnb_20261117_172933.log` where that
folder exists (9 re-establishments, 604 UL failures, policy 100/50/20).

Changes under `oai_ran/` need a build (`cd oai_ran/cmake_targets && ./build_oai -w USRP --gNB`)
on a lab host; say so if it was not done.

## Documentation

- Each experiment's `README.md` holds its plan, runs, results and log review (method:
  `docs/guide-log-review.md`); keep it honest: observed vs inferred, and "not
  measured" rather than guessed numbers. List every experiment in `experiments/README.md`.
- Daily work goes in `docs/handoffs/YYYY-MM-DD.md` (one per day; add `##` sections).
- Index every new doc in `docs/README.md`. Write in English.
- Journal entries: repository ID `cerise_oranslice`, `--source docs/handoffs/YYYY-MM-DD.md`.
