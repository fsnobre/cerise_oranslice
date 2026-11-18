# CERISE tools for ORANSlice on the lab X310

Our additions to ORANSlice: the tools that create, run and record experiments, the
slice-policy template, and how the gNB conf and build differ from upstream.

- How experiments are organised: [`../experiments/README.md`](../experiments/README.md)
- Running one on WS-02, step by step: [`../docs/guide-run-on-ws02.md`](../docs/guide-run-on-ws02.md)
- Reviewing the logs: [`../docs/guide-log-review.md`](../docs/guide-log-review.md)

## Tools

| Tool | Where it runs | What it does |
|---|---|---|
| `new_experiment.py --host ws02 --slug <slug> [--set KEY=VALUE]` | laptop | Creates `experiments/<date>_<host>-<slug>/` with `README.md`, `gnb.conf` (the X310 conf below with the host's X310 address and any overrides), `rrmPolicy.json` and `start_gnb.sh`. `--dry-run` shows what it would write |
| `preflight.sh [EXP]` | gNB host | Read-only checks: no other `nr-softmodem`, X310 answers, MTU, socket buffers, CPU governor, disk, core containers healthy, AMF slice order, UPF NAT. Prints the fix for each failure |
| `run_gnb_x310.sh EXP` (via `EXP/start_gnb.sh`) | gNB host | Runs `nr-softmodem` with the experiment's conf and policy. Refuses if another `nr-softmodem` runs or the UHD library does not resolve. Logs to `EXP/logs/<run-id>/` with Unix-second stamps, plus the conf, command and `run_info.txt` |
| `set_slice_policy.py [EXP] [--dedicated N] [--min N] [--max N]` | gNB host | Shows or changes the slice policy while the gNB runs; checks it the way the gNB would, writes atomically, appends the change to `EXP/logs/policy_changes.tsv` |
| `collect_run.sh EXP [run-id]` | gNB host, before the core stops | Saves `docker logs -t` of the core, slice/DNN/NAT settings, the final policy and a log summary into the run folder |
| `summarize_gnb_log.sh LOG` | anywhere | Counts the lines a review starts from: overflows, assertions, random access, re-establishments and causes, PUSCH UL failures, policy reads, last statistics per UE |
| `rrmPolicy.json` | | Template policy copied into new experiments: SST 1 / SD FFFFFF, dedicated 5 %, min 10 %, max 100 % |

`EXP` is an experiment folder, e.g. `experiments/2026-11-18_ws02-srs0-sweep`. The
FN990 tools (`fn990_set_apn.sh`, `fn990_speedtest.sh`) live in the companion
repository `oai-rfsim-handover-testbed`, under `scripts/modem/`.

## Build

On the gNB host, in `~/cerise_oranslice`:

```bash
cd oai_ran/cmake_targets
./build_oai -w USRP --gNB
```

Dependencies are already installed on the lab hosts. Do not add `-I` there: it can
replace the shared `/usr/include/simde`. The build prints a harmless warning in
`gNB_scheduler_dlsch.c` (`sd == NULL` on an integer: a missing `sd` reads as 0 and
is mapped to FFFFFF as intended).

**Which UHD.** The UHD the build links must match the X310's FPGA image, and the
X310s are shared: never reflash them or reinstall UHD.

| Host | X310 | UHD | Status |
|---|---|---|---|
| WS-02 | `192.168.40.3`, FPGA 39.3 | system UHD 4.8.0 (`/usr/local/lib/libuhd.so.4.8.0`) | Worked on 2026-11-17 |
| WS-03 | `192.168.40.2` per earlier notes, FPGA 39.3 | private UHD 4.4.0 in `~/uhd-4.4.0` (the system 4.8 aborts with `RFNoC protocol mismatch`) | Not run with ORANSlice. The testbed recorded different addresses on 2026-11-13; run `uhd_find_devices` first |

For a private UHD (WS-03), build against it and run with `UHD_PREFIX` set:

```bash
./build_oai -c -w USRP --gNB \
  --cmake-opt "-DCMAKE_PREFIX_PATH=$HOME/uhd-4.4.0" \
  --cmake-opt "-DUHD_DIR=$HOME/uhd-4.4.0/lib/cmake/uhd"
LD_LIBRARY_PATH=$HOME/uhd-4.4.0/lib ldd ran_build/build/liboai_usrpdevif.so | grep uhd   # libuhd.so.4.4.0
UHD_PREFIX=~/uhd-4.4.0 experiments/<exp>/start_gnb.sh
```

If the build folder was configured with Ninja earlier, keep `--ninja` or use `-c`.

## The X310 conf and how it differs from upstream

Source: `oai_ran/targets/PROJECTS/GENERIC-NR-5GC/CONF/ORANSlice.gnb.sa.band78.fr1.106PRB.usrpx310.conf`
(CRLF line endings; `new_experiment.py` strips them). Experiments run a copy of it,
so change an experiment's `gnb.conf`, not this file, unless every future experiment
needs the change.

| Setting | Upstream | Now | Why |
|---|---|---|---|
| `absoluteFrequencySSB` / `dl_absoluteFrequencyPointA` | 641280 / 640008 (3619.2 MHz SSB) | 621312 / 620040 (3319.68 MHz SSB, Point A 3300.60 MHz) | The lab cell's frequency in the vanilla OAI bring-up (2026-11-12). The testbed has since moved off it: see the note below |
| `initialDLBWPcontrolResourceSetZero` | 12 | 11 | Matches the SSB offset of the lab cell |
| `ra_ResponseWindow` | 4 (sl10) | 5 (sl20) | Validated value. It is an index (0=sl1 ... 7=sl80), not a slot count |
| S-NSSAI | SST 1 with SD FFFFFF and 000002 | SST 1, SD FFFFFF only | The lab SIM uses one slice |
| `amf_ip_address`, `NETWORK_INTERFACES` | interface `demo-oai`, `/24` suffixes, IPv6 entry | AMF 192.168.70.132, gNB 192.168.70.129 | The core's Docker bridge |
| `SliceConf` | `/home/wineslab/...` | `rrmPolicy.json`; `run_gnb_x310.sh` sets the experiment's file at run time | |
| `prach_dtx_threshold` / `pucch0_dtx_threshold` | 120 / 100 | 200 / 150 | Validated values |
| `sdr_addrs` | `type=x300, addr=192.168.40.2,clock_source=...` | `addr=<X310>,send_frame_size=8000,recv_frame_size=8000` | Validated value; `new_experiment.py` sets the host's address. Clock and time stay internal |
| `tx_subdev` / `rx_subdev` | `B:0` | removed (UHD default, daughterboard A) | The validated run set no subdevice |
| `bf_weights` | 2x2 matrix | removed | One TX and one RX antenna |
| `pusch_proc_threads` | 8 | removed | Not a parameter of this OAI version |

Unchanged: `max_rxgain` 114, `att_tx`/`att_rx` 0, `do_SRS = 1`, `do_CSIRS = 1`,
`THREAD_STRUCT`. The validated vanilla run set neither `do_SRS` nor `do_CSIRS`;
`2026-11-18_ws02-srs0-sweep` tests `do_SRS = 0`.

**Carrier.** The testbed moved its cells to SSB 650016 / Point A 648744
(3731.16-3769.32 MHz) on 2026-11-16, because 621312 very likely overlaps Claro's
n78 carrier (SSB 3348.48 MHz). The lab's authorization for 3700-3800 MHz was not
confirmed as of 2026-11-18, so this conf stays on 621312 for now.

## Slice policy without an xApp

The code part of `doc/rrmPolicyJson.patch` is applied in this fork (commit
`0d22003`): the MAC re-reads `SliceConf` every 128 frames (1.28 s), so a change to
the experiment's `rrmPolicy.json` takes effect while the gNB runs. The reader was
also changed to parse the file once and free it (upstream parsed it twice and
leaked both copies every 1.28 s).

- The policy limits only the **downlink** scheduler.
- Ratios are percentages of the PRBs: `dedicated_ratio` <= `min_ratio` <=
  `max_ratio`, and the sums over all slices of `min_ratio` and of `dedicated_ratio`
  must stay at or below 100, or the gNB resets them to 0.
- A policy for an S-NSSAI that is not in the gNB conf is ignored. No `sd` key means
  FFFFFF; `sd` must be a decimal integer (a hex string is read as FFFFFF).
- After each read the gNB logs
  `Slice 1, NSSAI 1.ffffff, rrmPolicy.dedicated_ratio 5, rrmPolicy.min_ratio 10, rrmPolicy.max_ratio 100`,
  and `Error in opening rrmPolicy file` if the path is wrong.
- A second slice also needs its S-NSSAI in the gNB conf, the core and the UE.

Use `set_slice_policy.py` rather than editing the JSON: it checks the values, writes
the file in one step (the gNB never reads half a file) and records the change.

The ORANSlice E2 agent still starts: it binds UDP port 6655 and logs an
`E2 agent heartbeat` every 3 s. It does not need an E2 simulator or a RIC.
