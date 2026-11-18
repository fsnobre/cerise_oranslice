# 2026-11-18_ws02-srs0-sweep

Created 2026-11-18T09:01:24-03:00 with `./cerise/new_experiment.py --host ws02 --slug srs0-sweep --set do_SRS=0`
(repository `2478932` with uncommitted changes).

## Purpose

Two questions, in order:

1. **Does `do_SRS = 0` stabilise the radio link?** On 2026-11-17
   ([`../2026-11-17_ws02-first-sweep/`](../2026-11-17_ws02-first-sweep/README.md))
   the FN990 rejected an RRC reconfiguration from this gNB five times in a row
   (re-establishment cause Reconfiguration Failure), the gNB logged 604 PUSCH UL
   failures, and the link was lost while the policy was still at 50 %. That conf
   had `do_SRS = 1`; the vanilla OAI run that reached about 82 Mbit/s with the same
   modem (2026-11-12) did not set it. This experiment changes only `do_SRS`.
2. **If the link holds: does the downlink follow the slice cap?** Repeat the sweep
   that was cut short: max 100 %, 50 %, 20 %, then 100 % again, one speed test each.
   20 % (about 21 of 106 PRBs) is the first value expected to bind; the return to
   100 % shows that a drop comes from the policy and not from the link getting worse.

Answered by: question 1 by the re-establishment causes and UL failure counts
against 2026-11-17; question 2 by the four download medians.

## Setup

| Item | Value |
|---|---|
| gNB host | WS-02 (cerise-Precision-5860-Tower02, 172.16.2.210) |
| X310 | `192.168.40.3` (opened with the system UHD 4.8.0 on 2026-11-17) |
| UHD | system UHD 4.8.0 (/usr/local/lib) |
| gNB build | `~/cerise_oranslice` at the commit above; record `git -C ~/cerise_oranslice log -1 --oneline` on the host |
| gNB conf | `gnb.conf`: the repository conf (sha256 `dc04c227e53f`) with X310 address `192.168.40.3`, `do_SRS = 0` |
| Slice policy | `rrmPolicy.json` at start: SST 1: dedicated 5 %, min 10 %, max 100 % |
| Core | legacy OAI core v1.5.1, `oai_cn/oai-cn5g-legacy/` (AMF 192.168.70.132, gNB 192.168.70.129) |
| UE | Telit FN990 on the laptop, SIM ...0777, DNN `oai` from modem context 1, NetworkManager profile `oai` |

## Bring-up

Step by step in [`docs/guide-run-on-ws02.md`](../../docs/guide-run-on-ws02.md). In short, on the gNB host:

```bash
cd ~/cerise_oranslice && git pull --ff-only
EXP=experiments/2026-11-18_ws02-srs0-sweep
./cerise/preflight.sh $EXP               # radio free, host tuning, core
$EXP/start_gnb.sh                        # Ctrl-C to stop
./cerise/set_slice_policy.py $EXP --max 50   # second terminal, while it runs
./cerise/collect_run.sh $EXP             # after Ctrl-C, before stopping the core
```

## Plan for the run

1. Start the gNB, connect the FN990 once (`nmcli connection up oai`), check
   `ping -I wwan0 -c 5 8.8.8.8`. Write the start time in Runs.
2. **Idle check, 5 minutes**, no traffic but a slow ping
   (`ping -I wwan0 -i 2 8.8.8.8`). If the gNB log shows `Reconfiguration Failure`
   or new RNTIs for the FN990 here, stop: question 1 is answered (no) and the sweep
   would measure the link, not the policy.
3. **Sweep**, at each step: set the policy, wait 5 s, confirm the gNB read it,
   run the speed test into this folder:
   ```bash
   # WS-02, second terminal
   ./cerise/set_slice_policy.py $EXP --max 50
   grep -a max_ratio $EXP/logs/latest/gnb.log | tail -1     # must show max_ratio 50
   # laptop, from the cerise_oranslice checkout
   ../oai-rfsim-handover-testbed/scripts/modem/fn990_speedtest.sh \
     --out-parent experiments/2026-11-18_ws02-srs0-sweep/logs/laptop --label "srs0 max 50"
   ```
   Order: 100 (the start value: no change, just the test), 50, 20, 100.
4. Reset to max 100 % (`--max 100`), Ctrl-C the gNB, `./cerise/collect_run.sh $EXP`,
   stop the core, copy the logs to the laptop (guide, step 9).

## What to look for

`./cerise/summarize_gnb_log.sh $EXP/logs/latest/gnb.log`, compared with 2026-11-17
(sweep log `gnb_20261117_172933`):

| Check | 2026-11-17 (`do_SRS = 1`) | Better if |
|---|---|---|
| Re-establishments accepted | 9 (5 Reconfiguration Failure, 4 Other Failure) | 0 Reconfiguration Failure |
| `Detected UL Failure on PUSCH` | 604 | far fewer |
| Random-access attempts | 136 | a handful (one per connect) |
| Upload in the speed test | 0.2 Mbit/s once, then failures | completes |
| Download at max 100 % | 10.8 Mbit/s median | near the vanilla 82 Mbit/s |
| Policy reads | 100 → 50 → 20, all read | 100 → 50 → 20 → 100, all read |

Also: `pucch0_DTX` and `ulsch_DTX` in the FN990's last statistics, and any
`ERROR_CODE_OVERFLOW` (host tuning).

## Runs

Times are lab time (UTC-3). Log folders are `logs/<run-id>/` (git-ignored).

| Run ID | Start | What changed | Result |
|---|---|---|---|

## Results

Observed numbers only; mark anything inferred, and write "not measured" rather than guess.

## Open issues

- **Carrier.** This conf still uses SSB ARFCN 621312 (carrier 3300.60-3338.76 MHz).
  On 2026-11-16 the testbed moved its cells off this carrier because it very likely
  overlaps Claro's n78 carrier (SSB 3348.48 MHz, 100 MHz wide, strong at the lab);
  see `oai-rfsim-handover-testbed`, `experiments/2026-11-17_x310-two-cell-a3/NOTES.md`.
  Interference would also explain an unstable link, so if `do_SRS = 0` does not
  help, the carrier is the next suspect. Moving to 650016 / 648744 needs the lab's
  authorization for 3700-3800 MHz first (not confirmed as of 2026-11-18).
- **Which X310 is at 192.168.40.3 from WS-02.** It opened with UHD 4.8.0 on
  2026-11-17, but the testbed's profile records `uhd_find_devices` on WS-02 finding
  192.168.40.2 on 2026-11-13. Run `uhd_find_devices` on WS-02 and note the result
  in Runs.
