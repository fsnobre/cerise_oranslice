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
2. The newest `docs/handoffs/YYYY-MM-DD.md` and the newest `results/*/README.md`.
3. `cerise/README.md`: how to build and run on the lab radio.

## Repository layout

| Path | What it is |
|---|---|
| `oai_ran/` | ORANSlice gNB source (upstream code plus our changes) |
| `oai_cn/` | upstream core material; `oai-cn5g-legacy/` holds the v1.5.1 core used so far |
| `doc/` | upstream figures and patch. Leave it as upstream; our docs go in `docs/` |
| `cerise/` | our runner (`run_gnb_x310.sh`), slice policy (`rrmPolicy.json`) and its tool (`set_slice_policy.py`) |
| `results/<date>_<host>/` | one folder per run: a `README.md` (setup, what worked, numbers, log review) and `raw/` (git-ignored) |
| `docs/` | index and daily handoffs |

## Git rules

- Remotes: `fork` = `fsnobre/cerise_oranslice` (ours; work on `main`), `origin` =
  `wineslab/ORANSlice` (upstream). **Never push to `origin`.**
- Never `git add -A` or `git add .`; stage explicit paths. Raw logs and run trees may
  be lying around.
- Do not push unless asked. Commit per completed work package.
- `results/*/raw/` is git-ignored on purpose; never force-add it.

## Secrets and privacy

- Core logs (AMF, AUSF, UDM) contain SIM session keys. They stay in `results/*/raw/`
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
| WS-03 X310 | `192.168.40.2`; `cerise/README.md` says its FPGA needs UHD 4.4.0 (not re-checked) |
| UE | Telit FN990 on the laptop (`nobre`), ModemManager + NetworkManager, interface `wwan0` |

- **The X310s and the workstations are shared with other lab members.** Do not
  reflash FPGAs, reinstall UHD or change system packages. Other users' home folders
  and trees (for example the ORANSlice tree holding the legacy core compose file on
  WS-02) are read-only for us; copy, do not edit.
- Only one gNB may use a radio at a time; check nobody else is on it first.
- `cerise/run_gnb_x310.sh` currently refuses builds not linked against UHD 4.4.0 and
  uses WS-03's X310 address, so WS-02 runs use `nr-softmodem` directly with a
  copied conf (see `results/2026-11-17_ws02/README.md`).
- Run commands output through `tee` have no wall-clock timestamps; record start times.

## Core facts (legacy OAI core v1.5.1)

- A PDU session request without an S-NSSAI gets the AMF's **first** supported slice.
  The SMF serves DNN `oai` on SST 1 / SD FFFFFF and `oai2` on SST 1 / SD 1; a mismatch
  is rejected with 5GSM cause 33. Keep SD FFFFFF first.
- The UPF NATs only `12.1.1.0/24` (DNN `oai`). DNN `oai2` addresses (12.1.2.x) leave
  untranslated and get no replies.
- The AMF container logs one hour ahead of the SMF; save logs with `docker logs -t`
  to get true UTC. The lab is UTC-3.

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

- The MAC re-reads `SliceConf` (`cerise/rrmPolicy.json`) every 128 frames (about
  1.3 s). Only this fork enables that (commit `0d22003`); upstream needs the xApp.
- The policy limits the **downlink** scheduler only. Defaults are max 100 %.
- Change it while the gNB runs with `cerise/set_slice_policy.py` (writes the file
  atomically). Record every change with its time, and reset to max 100 % after a run.
- Confirm a change in the gNB log (`Slice 1, NSSAI 1.ffffff, ... max_ratio N`).

## Validation

No test suite. Before committing changes to our files:

```bash
bash -n cerise/run_gnb_x310.sh
python3 -m py_compile cerise/set_slice_policy.py
```

Changes under `oai_ran/` need a build (`cd oai_ran/cmake_targets && ./build_oai -w USRP --gNB`)
on a lab host; say so if it was not done.

## Documentation

- Each run gets `results/<date>_<host>/README.md`; keep its log review honest:
  observed vs inferred, and "not measured" rather than guessed numbers.
- Daily work goes in `docs/handoffs/YYYY-MM-DD.md` (one per day; add `##` sections).
- Index every new doc in `docs/README.md`. Write in English.
- Journal entries: repository ID `cerise_oranslice`, `--source docs/handoffs/YYYY-MM-DD.md`.
