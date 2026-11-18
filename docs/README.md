# Documentation index

Rules for agents and the lab facts they rely on: [`../AGENTS.md`](../AGENTS.md).

## Guides

| Document | What it covers |
|---|---|
| [`../cerise/README.md`](../cerise/README.md) | Build and run ORANSlice on the CERISE X310 with the FN990: UHD, core, gNB, slice policy |
| [`../README.md`](../README.md) | Upstream ORANSlice overview (framework, xApp, build) |

## Run records

| Run | Result |
|---|---|
| [`../results/2026-11-17_ws02/README.md`](../results/2026-11-17_ws02/README.md) | First end-to-end data on WS-02: about 11 Mbit/s down at max 100 % and 50 %, upload broken, 20 % not measured; full log review |

## Handoffs

| Date | Topic |
|---|---|
| [`handoffs/2026-11-18.md`](handoffs/2026-11-18.md) | Log review of the 2026-11-17 run, laptop modem cleanup, repository set up for agents |

## Related

- `oai-rfsim-handover-testbed` (companion repository): handover work, the FN990
  scripts (`scripts/modem/`), and the vanilla OAI X310 bring-up
  (`docs/en/report-usrp-x310-fn990-bringup.md`).

## Open items

1. On WS-02: switch `~/cerise_oranslice` to `main`
   (`git fetch --prune && git switch main && git branch -d cerise/x310-fn990`) and
   reset the slice policy to max 100 % (left at 20 % on 2026-11-17).
2. Stabilise the radio link before measuring: try `do_SRS = 0` (Reconfiguration
   Failures), then look at the uplink PUSCH DTX and `pucch0_DTX`.
3. Repeat the sweep (100 %, 50 %, 20 %, back to 100 %) on a stable link.
4. Let `cerise/run_gnb_x310.sh` accept the system UHD and take the X310 address as a
   setting.
5. Before long runs on WS-02: `enp2s0` MTU 9000, `rmem_max`/`wmem_max` 33554432, CPU
   governor `performance` (USRP overflow on 2026-11-17).
