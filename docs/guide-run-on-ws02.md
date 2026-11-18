# Running an experiment on WS-02

Step by step, from a planned experiment folder to logs on the laptop. Written from
the 2026-11-17 run; the steps marked *new* use the helpers added on 2026-11-18 and
have not been run on WS-02 yet.

Read first: [`../experiments/README.md`](../experiments/README.md) (folder layout and
lifecycle) and the experiment's own `README.md` (its plan).

Who runs what: WS-02 has no passwordless sudo, so every `sudo` line is yours. Copy
logs with `rsync` started on the laptop (WS-02 cannot log in to the laptop).

## 0. Before going to the lab

- The experiment folder is committed and pushed (`git push fork main`).
- Nobody else has booked WS-02's X310. Only one gNB may use a radio.
- The FN990 is on the laptop, context 1 holds DNN `oai`
  (`AT+CGDCONT?`, or `fn990_set_apn.sh --apn oai` in the testbed repository), and
  the only NetworkManager modem profile is `oai`.

## 1. Update the clone on WS-02

```bash
ssh ws02
cd ~/cerise_oranslice
git status --short           # must be clean except ignored files
git switch main && git pull --ff-only fork main
git log -1 --oneline         # note it in the experiment's Runs table
EXP=experiments/<date>_<slug>
```

The clone was still on the deleted branch `cerise/x310-fn990` after 2026-11-17,
with `cerise/rrmPolicy.json` left at max 20 %. The first time, restore the template
and switch:

```bash
git checkout -- cerise/rrmPolicy.json      # back to max 100 %; experiments use their own copy now
git fetch --prune fork && git switch main && git branch -d cerise/x310-fn990
```

If the commit touched `oai_ran/`, rebuild (about 10 minutes; no `-I`, which can
replace the shared `/usr/include/simde`):

```bash
cd oai_ran/cmake_targets && ./build_oai -w USRP --gNB && cd ~/cerise_oranslice
```

## 2. Check the radio and the host (*new*)

```bash
./cerise/preflight.sh $EXP
```

It changes nothing. For each FAIL it prints the fix. The host tuning is lost on
every reboot; on WS-02 the X310 link is `enp2s0`:

```bash
sudo ip link set enp2s0 mtu 9000
sudo sysctl -w net.core.rmem_max=33554432 net.core.wmem_max=33554432
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

The 2026-11-17 run had a USRP overflow (`ERROR_CODE_OVERFLOW`) without this tuning.
If your user cannot run `docker`, call it as `DOCKER='sudo docker' ./cerise/preflight.sh $EXP`.

## 3. Start the core

The legacy OAI core v1.5.1. Its containers are named `oai-amf`, `oai-smf` and so on
whoever starts them, so only one such core can run on WS-02. If `preflight.sh`
shows a core already up, its `core started from` line names the compose file:
on 2026-11-17 it was another lab member's tree. Ask before stopping someone else's core.

Our copy is `oai_cn/oai-cn5g-legacy/`. Its slice settings and SIM entries match
what ran on 2026-11-17 (SD FFFFFF first, DNN `oai` on 12.1.1.0/24 with NAT, SIM
...0777 provisioned); the other tree was not re-read on 2026-11-18. The Compose
file expects the Docker network `demo-oai-public-net` to exist:

```bash
sudo docker network inspect demo-oai-public-net >/dev/null 2>&1 || \
  sudo docker network create --driver bridge --subnet 192.168.70.128/26 \
    -o com.docker.network.bridge.name=demo-oai demo-oai-public-net
cd oai_cn/oai-cn5g-legacy && sudo docker compose -f docker-compose-legacy.yml up -d && cd ~/cerise_oranslice
sudo docker ps --format '{{.Names}} {{.Status}}'      # wait until all are healthy
./cerise/preflight.sh $EXP                             # core section all ok
```

(The upstream `restart_cn.sh` also adds 12.1.2.1 on the UPF's `tun0`, which only
DNN `oai2` needs; `oai2` has no NAT, so we do not use it.)

## 4. Start the gNB

```bash
DRY_RUN=1 $EXP/start_gnb.sh     # checks build, UHD, policy file; prints the command
$EXP/start_gnb.sh               # Ctrl-C to stop; logs to $EXP/logs/<run-id>/
```

`run_gnb_x310.sh` refuses to start while any `nr-softmodem` runs on the host. In
the log, check:

- `associated AMF` (NG setup done). If missing, the core was not up: Ctrl-C, start
  the core, start the gNB again (this OAI version does not retry reliably).
- `rrmPolicy.max_ratio 100` lines every 1.3 s. `Error in opening rrmPolicy file`
  means the path is wrong.

Write the run ID and start time in the experiment's Runs table.

## 5. Connect the FN990 (laptop)

```bash
nmcli connection up oai
ip -4 addr show wwan0          # 12.1.1.x
ping -I wwan0 -c 5 8.8.8.8
```

Connect once. Do not use `mmcli --simple-connect`, `ip addr add`, or the GNOME
network menu during a run: each tears down the session and starts another (that
happened on 2026-11-17). For a fresh session: `nmcli connection down oai && nmcli connection up oai`.

## 6. Measure (laptop and WS-02)

Speed test on the laptop, into the experiment's log folder:

```bash
cd ~/Documents/repos/cerise_oranslice
../oai-rfsim-handover-testbed/scripts/modem/fn990_speedtest.sh \
  --out-parent experiments/<date>_<slug>/logs/laptop --label "<what is set>"
```

Policy changes on WS-02, in a second terminal (*new*: the folder argument and the
history file):

```bash
./cerise/set_slice_policy.py $EXP                  # show
./cerise/set_slice_policy.py $EXP --max 50         # change; appended to logs/policy_changes.tsv
grep -a max_ratio $EXP/logs/latest/gnb.log | tail -1   # confirm the gNB read it
```

The policy limits only the downlink scheduler. Follow the experiment's plan for
the order and the waits.

## 7. Stop and collect (*new*)

1. Reset the policy: `./cerise/set_slice_policy.py $EXP --max 100` (or the
   README's starting values).
2. Ctrl-C the gNB.
3. Before stopping the core (its logs go with the containers):
   ```bash
   ./cerise/collect_run.sh $EXP          # or DOCKER='sudo docker' ./cerise/collect_run.sh $EXP
   ```
4. Stop the core: `(cd oai_cn/oai-cn5g-legacy && sudo docker compose -f docker-compose-legacy.yml down)`.
   Leave another member's core running if it was theirs.

## 8. Laptop side

Save the ModemManager journal for the run window (it showed the duplicate session
on 2026-11-17):

```bash
mkdir -p experiments/<date>_<slug>/logs/laptop
journalctl -u ModemManager -u NetworkManager --since "<start time>" \
  > experiments/<date>_<slug>/logs/laptop/modem_journal.log
```

## 9. Copy to the laptop

```bash
cd ~/Documents/repos/cerise_oranslice
rsync -a ws02:~/cerise_oranslice/experiments/<date>_<slug>/logs/ experiments/<date>_<slug>/logs/
```

The laptop's `logs/laptop/` and WS-02's `logs/<run-id>/` do not overlap, so the
copy merges them. Then review: [`guide-log-review.md`](guide-log-review.md).

## When something fails

| Symptom | Where to look |
|---|---|
| `RFNoC protocol mismatch` at gNB start | Build linked to a UHD that does not match the X310's FPGA. On WS-02 the system UHD 4.8.0 worked with 192.168.40.3 |
| gNB never logs `associated AMF` | Core not up or not healthy; restart the gNB after the core |
| PDU Session Establishment Reject, 5GSM cause 33 | AMF's first slice is not SD FFFFFF (`preflight.sh` checks it) |
| UE gets 12.1.2.x, no internet | Modem context 1 is not `oai` (UPF NATs only 12.1.1.0/24) |
| Two sessions at the start | Something besides `nmcli connection up oai` connected the modem |
| `ERROR_CODE_OVERFLOW`, `rx_rf: Asked for ... got ...` | Host tuning (step 2) |
| Speed test cannot reach anything, gNB shows `Detected UL Failure on PUSCH` | Radio link lost; see the experiment's open issues |
