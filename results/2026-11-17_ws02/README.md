# 2026-11-17: ORANSlice on WS-02 with the FN990, and a first slice-policy sweep

First end-to-end data with this branch's ORANSlice gNB: the lab FN990, plugged into
the laptop, reached the internet through the gNB on WS-02 and the legacy OAI core
on WS-02. A download sweep over the slice policy started but was cut short.

Raw logs are in `raw/` (git-ignored: the core logs hold the SIM's session keys).
Times are lab time (UTC-3) unless marked UTC. The legacy AMF container logs one hour
ahead of the SMF.

## Setup

| Item | Value |
|---|---|
| gNB host | WS-02 (`cerise-Precision-5860-Tower02`, 172.16.2.210) |
| gNB code | this repository, branch `cerise/x310-fn990` at `1deca0a`, cloned to `~/cerise_oranslice` on WS-02 |
| Build | `cd oai_ran/cmake_targets && ./build_oai -w USRP --gNB` (no `-I`: dependencies were already installed, and `-I` can replace the shared `/usr/include/simde`) |
| UHD | system UHD 4.8.0, `/usr/local/lib/libuhd.so.4.8.0`, for both `liboai_usrpdevif.so` and `uhd_usrp_probe` |
| X310 | `192.168.40.3`, FPGA 39.3, two UBX-160 v2. Opens with UHD 4.8.0 on WS-02 (on WS-03 the README says FPGA 39.3 needs UHD 4.4.0; not re-checked) |
| gNB conf | `ORANSlice.gnb.sa.band78.fr1.106PRB.usrpx310.conf` with two changes, saved as `raw/gnb/gnb_ws02.conf`: `addr=192.168.40.3` and an absolute `SliceConf` to `cerise/rrmPolicy.json`. Internal clock and time |
| Run command | `sudo ./nr-softmodem -O <conf> --sa -E --usrp-tx-thread-config 1`, output through `tee` (no wall-clock timestamps in the log) |
| Core | legacy OAI core v1.5.1 on WS-02 (`docker-compose-legacy.yml` in another user's ORANSlice tree), AMF 192.168.70.132, gNB 192.168.70.129 on bridge `demo-oai` |
| UE | Telit FN990 (lab SIM) on the laptop, ModemManager, `wwan0` |

`cerise/run_gnb_x310.sh` was not used: it refuses builds not linked against UHD 4.4.0,
and the conf names WS-03's X310 address.

## What had to change to get data

1. **AMF slice order.** The AMF supported SST 1 / SD 1 and SST 1 / SD FFFFFF. A PDU
   session request without an S-NSSAI got the first one (SD 1), but the SMF serves
   DNN `oai` only on SD FFFFFF: PDU Session Establishment Reject, 5GSM cause 33.
   Swapping the order (SD FFFFFF first) fixed it.
2. **UE address inside the UPF's NAT range.** The UPF (`NETWORK_UE_NAT_OPTION=yes`)
   NATs only `12.1.1.0/24`; with the SIM on DNN `oai2` the UE got 12.1.2.x and its
   traffic left WS-02 untranslated. With DNN `oai` the UE gets 12.1.1.x.
3. **No duplicate session.** In one run the modem released its session 100 ms after
   the accept and asked again; the gNB never answered the second PDU Session Resource
   Setup (session ID 1 still held from the first), and the AMF later lost the session.
   Connecting once (`mmcli -m any --simple-connect="apn=oai,ip-type=ipv4"`) avoided it.
4. **Configure `wwan0`.** `mmcli` opens the session but nothing configured the
   interface on the laptop (NetworkManager does not manage the modem there):
   `ip link set wwan0 up`, `ip addr add <session address>/30 dev wwan0`, and a host
   route `8.8.8.8/32 dev wwan0` to keep the laptop's default routes.

Result: `ping -I wwan0 8.8.8.8`, 5/5, average 30.7 ms (the core alone reached 8.8.8.8
in about 18 ms).

## Slice-policy sweep (downlink only)

The MAC re-reads `cerise/rrmPolicy.json` about every 1.3 s (`set_slice_policy.py`
changes it while the gNB runs). The policy only limits the downlink scheduler.
One slice, SST 1 / SD FFFFFF, dedicated 5 %, min 10 %.

| Speed test (laptop) | max_ratio | Download median (3 × 20 MB) | Range | Upload | Ping average |
|---|---|---|---|---|---|
| 17:36:10 | 100 % | 10.79 Mbit/s | 9.87–12.88 | 0.22 Mbit/s once, then 2 failed | 31.1 ms |
| 17:41:33 | 50 % | 11.22 Mbit/s | 10.75–13.25 | 0.24 Mbit/s once, then 2 failed | 31.4 ms |
| 17:45:33 | 20 % | no result: the connection dropped during the test | | | |

The gNB log confirms each change (`Slice 1, NSSAI 1.ffffff, ... max_ratio N`: 503 reads
at 100, 203 at 50, 55 at 20 until shutdown).

Reading: halving the cap did not change the download, so at 50 % the radio link, not
the policy, was the limit. 20 % (about 21 of 106 PRBs) is the first value expected to
bind; it still has to be measured. For comparison, vanilla OAI on WS-03 gave about
82 Mbit/s down and 3.3 Mbit/s up with the same modem (2026-11-12).

## Problems seen

- **Low downlink rate.** Downlink MCS mostly 6–9 earlier in the run, retransmissions
  and many `pucch0_DTX` (the gNB misses the UE's HARQ feedback). At the end:
  `dlsch_rounds 2281/167/64/47, dlsch_errors 41, pucch0_DTX 290`, RSRP −79 dBm.
- **Upload broken.** Every speed test's first upload ran at about 0.2 Mbit/s until the
  120 s timeout, the other two transferred nothing. End of run:
  `ulsch_rounds 4130/727/228/15, ulsch_DTX 1131`, MCS 9, SNR 21 dB, 5 PRBs, and
  `Detected UL Failure on PUSCH after 12..14 PUSCH DTX`. Not related to the policy.
- **USRP overflow.** The 17:28 run ended with `ERROR_CODE_OVERFLOW` and
  `rx_rf: Asked for 23040 samples, got 17812`. Before long runs on WS-02: `enp2s0`
  MTU 9000, `net.core.rmem_max`/`wmem_max` 33554432, CPU governor `performance`.
- **One UE with failing downlink feedback.** In the 17:29 run, UE `0fce` (−80 dBm) had
  most downlink transmissions fail all four rounds (`pucch0_DTX` 50) while UE `3d8b`
  (−93 dBm) was clean. Which modem was which was not established.
- **Disk.** WS-02's `/` is at 100 % (about 3.5 GB free).

## Next steps

1. Repeat the 20 % run, then restore 100 % and run once more to show the drop comes
   from the policy. Reset the policy first: on WS-02 it was left at max 20 %.
2. Look into the uplink (PUSCH DTX, 5 PRBs) and the `pucch0_DTX` before trusting
   throughput numbers.
3. On this branch: let `run_gnb_x310.sh` accept the system UHD and take the X310 address
   as a setting, so WS-02 runs need no hand-edited conf.

## Raw files

| Path | Contents |
|---|---|
| `raw/gnb/` | gNB logs `gnb_20261117_172611` (no AMF: core was down), `_172823` (ended in a USRP overflow), `_172933` (the sweep), the conf used, the policy at shutdown |
| `raw/core/` | `docker logs -t` of all 9 core containers at 17:46, and `state_at_shutdown.txt` (containers, AMF/SMF/UPF settings, UPF NAT rule, gNB process, build commit, UHD link) |
| `raw/laptop/` | ModemManager journal from 17:00, modem and `wwan0` state, the three speed test folders |
| `raw/earlier_core_logs/` | the core logs read while debugging the friend's earlier runs (18:46 UTC AMF log; runs 2–4: slice reject, 12.1.2.x NAT, duplicate session) |
