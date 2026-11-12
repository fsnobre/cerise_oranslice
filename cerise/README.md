# ORANSlice on the CERISE X310 with the Telit FN990

This folder runs the ORANSlice gNB with the settings that brought the lab FN990
up on vanilla OAI on WS-03 on 2026-11-12 (registration, PDU session on DNN
`oai`, about 80 Mbit/s down and 3 Mbit/s up). The full record of that run is in
the `oai-rfsim-handover-testbed` repository:
`docs/en/report-usrp-x310-fn990-bringup.md` and
`experiments/2026-11-06_x310-fn990-single-cell/`.

ORANSlice itself has not yet been run with these settings.

## What changed from upstream ORANSlice

The gNB conf is
`oai_ran/targets/PROJECTS/GENERIC-NR-5GC/CONF/ORANSlice.gnb.sa.band78.fr1.106PRB.usrpx310.conf`.

| Setting | Upstream | Now | Why |
|---|---|---|---|
| `absoluteFrequencySSB` / `dl_absoluteFrequencyPointA` | 641280 / 640008 (3619.2 MHz SSB) | 621312 / 620040 (3319.68 MHz SSB, Point A 3300.60 MHz) | The lab cell's frequency. The old comment claimed 3319.68 MHz for 641280, which is wrong. |
| `initialDLBWPcontrolResourceSetZero` | 12 | 11 | Matches the SSB offset of the lab cell |
| `ra_ResponseWindow` | 4 (sl10) | 5 (sl20) | Validated value. It is an index (0=sl1 ... 7=sl80), not a slot count: the `10` used on WS-03 before made the gNB abort |
| S-NSSAI | SST 1 with SD FFFFFF and 000002 | SST 1, SD FFFFFF only | The testbed core and the lab SIM use one slice |
| `amf_ip_address`, `NETWORK_INTERFACES` | interface `demo-oai`, `/24` suffixes, IPv6 entry | AMF 192.168.70.132, gNB 192.168.70.129 | The testbed core's Docker bridge |
| `SliceConf` | `/home/wineslab/...` | `rrmPolicy.json`, set to `cerise/rrmPolicy.json` by the run script | |
| `prach_dtx_threshold` / `pucch0_dtx_threshold` | 120 / 100 | 200 / 150 | Validated values |
| `sdr_addrs` | `type=x300, addr=192.168.40.2,clock_source=...` | `addr=192.168.40.2,send_frame_size=8000,recv_frame_size=8000` | Validated value. Clock and time stay internal through `clock_src`/`time_src` |
| `tx_subdev` / `rx_subdev` | `B:0` | removed (UHD default) | The validated run set no subdevice |
| `bf_weights` | 2x2 matrix | removed (default) | One TX and one RX antenna |
| `pusch_proc_threads` | 8 | removed | Not a parameter of this OAI version |

Unchanged: `max_rxgain` 114, `att_tx`/`att_rx` 0, `do_SRS = 1`, `do_CSIRS = 1`,
`THREAD_STRUCT`. The validated vanilla run did not set `do_SRS` or `do_CSIRS`.
If the FN990 registers but the uplink misbehaves, try `do_SRS = 0` first.

`oai_cn/oai_slicing_usrpX310.conf`, an older duplicate of this conf with the
same wrong frequency, was deleted.

## 1. UHD 4.4.0

The shared X310 at `192.168.40.2` has FPGA 39.3 and opens only with UHD 4.4.0.
The system UHD (4.8 on WS-03) aborts with an "RFNoC protocol mismatch". Do not
reflash the radio: other people use it. Use the private UHD build in
`~/uhd-4.4.0` (the build steps are in the testbed's experiment `NOTES.md`).

```bash
LD_LIBRARY_PATH=$HOME/uhd-4.4.0/lib ~/uhd-4.4.0/bin/uhd_usrp_probe --args "addr=192.168.40.2"
```

## 2. Build ORANSlice against UHD 4.4.0

The ORANSlice build used on WS-03 before was linked against the system UHD
4.8.0, which cannot open this X310. Install protobuf-c as in the top-level
README, then build clean with the private UHD on the CMake path:

```bash
cd oai_ran/cmake_targets
./build_oai -I -w USRP                      # first time only: dependencies
./build_oai -c -w USRP --gNB \
  --cmake-opt "-DCMAKE_PREFIX_PATH=$HOME/uhd-4.4.0" \
  --cmake-opt "-DUHD_DIR=$HOME/uhd-4.4.0/lib/cmake/uhd"
LD_LIBRARY_PATH=$HOME/uhd-4.4.0/lib ldd ran_build/build/liboai_usrpdevif.so | grep uhd
# must show libuhd.so.4.4.0 => /home/<user>/uhd-4.4.0/lib/...
```

If the build folder was configured earlier with Ninja, either keep `--ninja` or
use `-c` without it, as above. `run_gnb_x310.sh` refuses to start a build that
does not resolve `libuhd.so.4.4.0` from `~/uhd-4.4.0/lib`.

## 3. Core

Use the testbed's core, not `oai_cn/oai-cn5g-legacy`. The legacy core's SMF
(v1.5.1) has the IPv4v6 bug, and the database it mounted on WS-03 had no entry
for the lab SIM. The testbed's core has the FN990 subscriber (IMSI
001010000010776, DNN `oai`, SST 1, SD FFFFFF). From an experiment folder made
by the testbed's generator:

```bash
cd <testbed checkout>   # oai-rfsim-handover-testbed
python3 scripts/create_experiment.py profiles/x310-single-cell.yaml --slug oranslice-x310
cd experiments/<date>_oranslice-x310
./start_core.sh
```

Do not run that folder's `start_gnb.sh`: it starts the vanilla OAI gNB.

## 4. gNB

Host setup, as in the validated run:

```bash
sudo ip link set <10gbe-iface> mtu 9000
sudo sysctl -w net.core.rmem_max=33554432 net.core.wmem_max=33554432
```

Then, from this repository:

```bash
DRY_RUN=1 ./cerise/run_gnb_x310.sh   # print the command, check the UHD link
./cerise/run_gnb_x310.sh
```

The script copies the conf to `cerise/logs/gnb_<time>.conf` with `SliceConf`
pointing at `cerise/rrmPolicy.json`, and logs to `cerise/logs/gnb_<time>.log`
with Unix-second timestamps (`date -d @<seconds>` converts them). It runs
`nr-softmodem --sa -E --usrp-tx-thread-config 1`. Override with `GNB_ARGS`,
`OAI_BUILD_DIR` or `UHD_PREFIX`.

## 5. Slice policy (no xApp)

Without an xApp, the slice policy comes from `cerise/rrmPolicy.json`. The code
part of `doc/rrmPolicyJson.patch` is applied on this branch: the MAC re-reads
the file every 128 frames (1.28 s), so edits to it take effect while the gNB
runs. The patch's own `oai_ran/rrmPolicy.json` (three slices) was not added;
`run_gnb_x310.sh` points `SliceConf` at `cerise/rrmPolicy.json` instead. The
reader was also changed to parse the file once and free it, since upstream
parsed it twice and leaked both copies every 1.28 s.

The file holds one policy for SST 1 / SD FFFFFF (no `sd` key means FFFFFF).
Ratios are percentages of the PRBs: `dedicated_ratio` <= `min_ratio` <=
`max_ratio`, and the sums over all slices of `min_ratio` and of
`dedicated_ratio` must stay at or below 100, or the gNB resets them to 0. A
policy for an S-NSSAI that is not in the gNB conf is ignored. After each read the
gNB logs a `Slice <n>, NSSAI 1.ffffff, rrmPolicy.dedicated_ratio ...` line per
slice (not yet checked how slices are counted with a single S-NSSAI), and
`Error in opening rrmPolicy file` if the path is wrong.

To change the policy, while the gNB runs or before, use the helper. It checks
the values as above and replaces the file in one step, so the gNB never reads a
half-written file. Editing the JSON by hand also works, but nothing checks it,
and `sd` must be a decimal integer (a hex string is read as FFFFFF):

```bash
./cerise/set_slice_policy.py                                # show the policy
./cerise/set_slice_policy.py --min 20 --max 50              # SST 1 / SD FFFFFF
./cerise/set_slice_policy.py --dedicated 10 --min 30 --max 100
```

`--sst`/`--sd` select another slice and `--remove` deletes one. A second slice
also needs its S-NSSAI in the gNB conf, the core and the UE.

The ORANSlice E2 agent still starts: it binds UDP port 6655 and logs an
`E2 agent heartbeat` every 3 s. It does not need an E2 simulator or a RIC.

## Not known yet

- Which X310 daughterboard (A or B) carries the antennas. The validated run used
  the default (A). If nothing is heard, ask before switching to `B:0`.
- Whether ORANSlice's 2024.w28 OAI base accepts every remaining setting with this
  UE. It has to be run to find out.
