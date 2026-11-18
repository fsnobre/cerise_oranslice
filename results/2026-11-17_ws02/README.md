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
   Connecting once avoided it. From the next run on, only NetworkManager connects
   the modem (`nmcli connection up oai`); see the log review below.
4. **Configure `wwan0`.** `mmcli` opens the session but does not configure the
   interface. At 17:30 `wwan0` was down with no address; it was set up by hand
   (`ip link set wwan0 up`, `ip addr add <session address>/30 dev wwan0`, host route
   `8.8.8.8/32 dev wwan0`). The log review below shows that NetworkManager then took
   over at 17:31:59 and configured `wwan0` itself (12.1.1.3/29), which is the address
   the working ping came from.

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
| 17:45:33 | 20 % | no result: the radio link was already lost (ping 0/20 at the start of the test) | | | |

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

## Log review (2026-11-18)

All of `raw/` read again after the run. Core times come from `docker logs -t` (UTC,
shown here in lab time); the gNB log has no timestamps, so it is ordered against the
others by its log lines.

### What worked

- **Core.** The gNB connected to the AMF; two SIMs registered: IMSI ...0777 (the
  FN990 on the laptop) and ...0776 (another modem, which registered at 17:30:24 but
  never asked for a session).
- **Data session.** IMSI ...0777, DNN `oai`, slice SST 1 / SD FFFFFF, address
  12.1.1.3, active from 17:31:59 until shutdown at 17:46. The UPF had both rules
  (uplink, and downlink to the gNB at 192.168.70.129); NAT covered 12.1.1.0/24.
  The AMF logged no signalling for it after 17:32:08: the session stayed up
  through both speed tests.
- **Slice policy.** Read the whole run without file errors (503 reads at 100 %,
  203 at 50 %, 55 at 20 %).
- **gNB process.** No crash, assertion, USRP overflow or late samples in the
  17:29:33 run (unlike 17:28).

### What did not

1. **Uplink.** 604 `Detected UL Failure on PUSCH after 10..15 PUSCH DTX` lines: the
   modem often does not transmit on its uplink grants. Matches the broken uploads.
2. **Unstable radio link.** 136 random-access attempts, 27 RRC re-establishments and
   about 20 RNTIs: the modem kept reconnecting at the radio level, which the core
   never saw. Early in the run it triggered five re-establishments in a row with
   cause **Reconfiguration Failure** (it rejected an RRC reconfiguration from this
   gNB; this conf enables `do_SRS` and `do_CSIRS`, and `do_SRS = 0` is the first
   thing to try). Later re-establishments have cause Other Failure.
3. **The lost connection started under 50 %, not 20 %.** The modem changed RNTI
   (5017 to 1e99) and went out of sync while the policy was still 50 % (uplink BLER
   0.68 at the end of that period; 0.996 and no RSRP measurements under 20 %). The
   third speed test's first step (ping 1.1.1.1 over `wwan0`) lost 20/20, so the 20 %
   value was never measured. By shutdown the modem was back in sync (downlink MCS 27,
   BLER 0).
4. **The session was set up twice at the start, by the laptop's desktop.**
   - 17:30:22: a direct ModemManager connect (not NetworkManager, not a repository
     script) set up session 12.1.1.2; `wwan0` was not configured yet.
   - 17:31:34: NetworkManager logged `op="connection-activate" name="oai2"` from
     `gnome-shell` (pid 4022): the profile `oai2` was picked in the GNOME top-bar
     menu. Its first attempts failed (`No valid data port found`) because the
     12.1.1.2 session held the data port; NetworkManager then released that session
     (UE-initiated PDU Session Release in the SMF, 17:31:34) and connected itself,
     giving 12.1.1.3/29 at 17:31:59.
   - **The APN in the NetworkManager profile did not reach the core.** The bearer
     connected on `wwan0` reported APN `oai2`, IP type `ipv4v6` (all three speed
     test logs), yet the AMF and SMF logged `Requested DNN: oai` for every request.
     The FN990 used its own context 1 (`AT+CGDCONT=1,"IP","oai"`, set with
     `scripts/modem/fn990_set_apn.sh` in the testbed repository) and ignored the APN
     it was handed; context 1 being IPv4-only also explains ModemManager's IPv6
     `CallFailed`. So the DNN is chosen on the modem, and picking a profile in GNOME
     only changes *when* a session is torn down and requested again.
   - The SMF kept a half-open session for 12.1.1.2 until shutdown, and at 17:32:08
     the modem answered a stray message for it with a 5GSM STATUS (cause 98).
     Harmless for the live session.
5. **NetworkManager autoconnect.** Before the run, profile `internet` (APN `internet`,
   autoconnect on) had tried to connect by itself about every 3 minutes from before
   17:00 until 17:27. The laptop had seven modem profiles (`default`, `ims`, two
   `internet`, `oai`, `oai2`, `openairinterface`).

### Changed on the laptop afterwards (2026-11-18)

- Deleted every NetworkManager modem profile except `oai`. To change the DNN, change
  the modem's context 1 (`fn990_set_apn.sh --apn <dnn>`), not the profile.
- `oai`: APN `oai`, autoconnect on, IPv4 automatic, **IPv6 disabled** (the core gives
  IPv4 only; ModemManager had logged `couldn't start IPv6 network: CallFailed`).
- From now on NetworkManager alone controls the modem: no `mmcli --simple-connect`,
  no manual `ip addr add`, and no picking a modem connection from the top bar during
  a run. Fresh session: `nmcli connection down oai && nmcli connection up oai`.

### What the numbers support

The two downloads show the link carried about 11 Mbit/s with the cap at 100 % or
50 %: the cap did not bind, the link did. They say nothing yet about what the policy
does; that needs a stable link and the 20 % run.

## Next steps

1. Repeat the 20 % run, then restore 100 % and run once more to show the drop comes
   from the policy. Reset the policy first: on WS-02 it was left at max 20 %.
2. Look into the uplink (PUSCH DTX, 5 PRBs) and the `pucch0_DTX` before trusting
   throughput numbers. First try: `do_SRS = 0`, against the Reconfiguration
   Failures seen in the log review.
3. On this branch: let `run_gnb_x310.sh` accept the system UHD and take the X310 address
   as a setting, so WS-02 runs need no hand-edited conf.

## Raw files

| Path | Contents |
|---|---|
| `raw/gnb/` | gNB logs `gnb_20261117_172611` (no AMF: core was down), `_172823` (ended in a USRP overflow), `_172933` (the sweep), the conf used, the policy at shutdown |
| `raw/core/` | `docker logs -t` of all 9 core containers at 17:46, and `state_at_shutdown.txt` (containers, AMF/SMF/UPF settings, UPF NAT rule, gNB process, build commit, UHD link) |
| `raw/laptop/` | ModemManager journal from 17:00, modem and `wwan0` state, the three speed test folders |
| `raw/earlier_core_logs/` | the core logs read while debugging the friend's earlier runs (18:46 UTC AMF log; runs 2–4: slice reject, 12.1.2.x NAT, duplicate session) |
