# Reviewing a run's logs

How to go from `experiments/<exp>/logs/<run-id>/` to the Runs and Results sections
of the experiment's README. Written from the 2026-11-17 review
([`../experiments/2026-11-17_ws02-first-sweep/README.md`](../experiments/2026-11-17_ws02-first-sweep/README.md),
section "Log review"), which found most of what is listed here.

## Privacy first

The AMF, AUSF and UDM logs contain SIM session keys. They stay in `logs/` (git-ignored).
When quoting any core log in a README, handoff or chat:

- do not print key, `Kamf`, `Knas`, `K_gNB`, RES/XRES, RAND, AUTN or OPc values;
- refer to SIMs by the last digits of the IMSI (`...0777`);
- prefer counts and short, filtered lines over whole log sections, for example
  `grep -a ... | sed -E 's/00101[0-9]{6}/.../g'`.

## 1. Put every log on one clock

| Log | Time stamps | Convert |
|---|---|---|
| `gnb.log` (from `run_gnb_x310.sh`) | Unix seconds at the start of each line (`wall_clock`) | `date -d @<seconds> '+%F %T'` |
| `gnb_*.log` of 2026-11-17 (plain `nr-softmodem \| tee`) | none: frame/slot numbers only | order against the core by events (NG setup, registration, PDU session) |
| `core/*.log` (`docker logs -t`) | first column, UTC (`...Z`) | lab time is UTC-3 |
| same, the core's own stamp in `[...]` | the container's `TZ=Europe/Paris` (UTC+1): "the AMF logs one hour ahead" | use the `docker logs -t` column instead |
| `laptop/modem_journal.log` | host local time (lab time) | |
| speed test `log.txt` | host local time | |
| `policy_changes.tsv`, `run_info.txt` | ISO 8601 with offset | |

Write all times in the README in lab time and say so once at the top.

## 2. gNB

```bash
./cerise/summarize_gnb_log.sh experiments/<exp>/logs/<run-id>/gnb.log
```

(`collect_run.sh` already saved it as `summary.txt`.) What each count means, with the
2026-11-17 sweep value for scale:

| Count | Meaning | 2026-11-17 |
|---|---|---|
| USRP overflow, short reads | Host could not keep up with the radio. Check the host tuning | 0 (1 in the earlier 17:28 run) |
| Assertions | gNB stopped on an internal check. Read the lines before it | 0 |
| `associated AMF` | NG setup with the core succeeded | 1 |
| Random-access attempts | Each connect, re-establishment or lost sync starts one. Many attempts for one UE means an unstable link | 136 |
| Re-establishments accepted, and their causes | The UE lost the link and came back. `Reconfiguration Failure`: it rejected an RRC reconfiguration from this gNB (conf problem). `Other Failure`: radio link failure | 9 (5 Reconfiguration, 4 Other) |
| `Detected UL Failure on PUSCH` | The UE did not transmit on 10-15 uplink grants in a row (gNB saw DTX) | 604 |
| Distinct RNTIs | Every new access gets a new RNTI; one UE should keep one | 22 |
| Policy reads | Each `max_ratio` value and how many 1.28 s reads it held. A missing step means the file was not read | 100 x 503, 50 x 203, 20 x 55 |
| Last statistics per UE | `dlsch_rounds a/b/c/d`: transmissions needing 1-4 rounds (good link: b, c, d small). `pucch0_DTX`: HARQ feedback the gNB missed. `ulsch_DTX`, BLER, MCS, `NPRB`, SNR, RSRP | FN990 ended at DL MCS 27, UL 5 PRB, `ulsch_DTX 1131` |

Then read the lines around the counts that matter for the experiment's question:

```bash
L=experiments/<exp>/logs/<run-id>/gnb.log
grep -a -n 'Accept Reestablishment Request' $L                    # when, which cause
grep -a -n -B5 'Detected UL Failure on PUSCH' $L | less
grep -a -n 'max_ratio' $L | awk -F'max_ratio ' '{print $2}' | uniq -c   # policy steps
grep -a -n -E 'UE RNTI [0-9a-f]{4} .*(in-sync|out-of-sync)' $L | less   # sync and RSRP over time
```

To tell which RNTI was the FN990: the CU-UE-ID and the time of its first access
against the AMF's registration of `...0777`. With two modems registered, say which
RNTIs are not established rather than guess.

## 3. Core

```bash
C=experiments/<exp>/logs/<run-id>/core
grep -a -E 'Requested DNN|Use first Requested S-NSSAI|Establishment Reject|5GSM cause' $C/oai-amf.log $C/oai-smf.log
grep -a 'UE IPv4 Address' $C/oai-smf.log                      # session addresses (12.1.1.x expected)
grep -a -c -i 'Registration Complete' $C/oai-amf.log
cat $C/state.txt                                               # slices, DNNs, NAT rule at collection
```

What to establish: which SIMs registered (last digits), each PDU session's DNN,
slice, address and its start and end, rejects and their causes, and whether the AMF
logged anything for the session during the measurements (on 2026-11-17 it did not:
the radio-level re-establishments never reached the core).

## 4. Laptop

- `laptop/speedtest_diag_*/summary.txt` and `results.csv`: the numbers for the
  Results table. Report the median and range of the downloads and say how many
  uploads completed. The test starts with a ping to 1.1.1.1; 0 % received means the
  link was already down and the test measured nothing.
- `laptop/modem_journal.log`: who connected the modem and when. Any connect not
  from `nmcli connection up oai` (GNOME's `connection-activate` from `gnome-shell`,
  a direct ModemManager connect) explains a duplicate or replaced session.
- The bearer's reported APN does not show the DNN; the AMF's `Requested DNN` does.

## 5. Write it up

In the experiment's README:

- **Runs**: run ID, start (lab time), what changed (conf, policy steps with times
  from `policy_changes.tsv`), outcome in one line.
- **Results**: a table per question with observed numbers. Mark inferences
  ("inferred from ...") and write "not measured" for missing points.
- **Log review**: what worked, what did not, each with the evidence (counts, times,
  short quoted lines without key material).
- Compare with the previous experiment where the question builds on it.

Then the handoff section for the day, and the experiment table in
[`../experiments/README.md`](../experiments/README.md).
