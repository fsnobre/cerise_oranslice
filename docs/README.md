# Documentation index

Rules for agents and the lab facts they rely on: [`../AGENTS.md`](../AGENTS.md).

## Workflow

Plan an experiment with `cerise/new_experiment.py`, run it on the host with the
guide, collect, review, then record it in the experiment's README and the day's
handoff. Details: [`../experiments/README.md`](../experiments/README.md).

## Guides

| Document | What it covers |
|---|---|
| [`../experiments/README.md`](../experiments/README.md) | Experiment folders: layout, lifecycle, rules, and the table of all experiments |
| [`guide-run-on-ws02.md`](guide-run-on-ws02.md) | Running an experiment on WS-02 step by step: clone, preflight, core, gNB, FN990, measurements, collection, copy to the laptop |
| [`guide-log-review.md`](guide-log-review.md) | Reviewing a run: one clock for all logs, what each gNB count means, core and laptop checks, privacy, write-up |
| [`../cerise/README.md`](../cerise/README.md) | Our tools, the build (which UHD on which host), the X310 conf and its changes from upstream, the slice policy |
| [`../README.md`](../README.md) | Upstream ORANSlice overview (framework, xApp, build) |

## Experiments

| Experiment | Result |
|---|---|
| [`2026-11-17_ws02-first-sweep`](../experiments/2026-11-17_ws02-first-sweep/README.md) | First end-to-end data on WS-02: about 11 Mbit/s down at max 100 % and 50 %, upload broken, 20 % not measured; full log review |
| [`2026-11-18_ws02-srs0-sweep`](../experiments/2026-11-18_ws02-srs0-sweep/README.md) | Planned: `do_SRS = 0` against the unstable link, then the 100/50/20/100 % sweep |

## Handoffs

| Date | Topic |
|---|---|
| [`handoffs/2026-11-18.md`](handoffs/2026-11-18.md) | Log review of the 2026-11-17 run, laptop modem cleanup, repository set up for agents; experiments workflow, tools and guides |

## Related

- `oai-rfsim-handover-testbed` (companion repository): handover work, the FN990
  scripts (`scripts/modem/`), the vanilla OAI X310 bring-up
  (`docs/report-usrp-x310-fn990-bringup.md`), and the experiment workflow this
  repository's is modelled on (lighter here: no profiles, one cell, one host).

## Open items

1. On WS-02: switch `~/cerise_oranslice` to `main`
   (`git fetch --prune fork && git switch main && git branch -d cerise/x310-fn990`) and
   reset the slice policy to max 100 % (`cerise/rrmPolicy.json` was left at 20 % on
   2026-11-17; experiments now use their own copy). WS-02 did not answer SSH on 2026-11-18.
2. Run [`2026-11-18_ws02-srs0-sweep`](../experiments/2026-11-18_ws02-srs0-sweep/README.md):
   `do_SRS = 0` first, the sweep only if the link holds.
3. If the link stays unstable: the carrier (621312 likely overlaps Claro's n78
   carrier). Moving to 650016 needs the lab's authorization for 3700-3800 MHz.
4. Confirm which X310 WS-02 sees (`uhd_find_devices`): this repository used
   192.168.40.3, the testbed recorded 192.168.40.2 on 2026-11-13.
5. Host tuning on WS-02 before long runs (`cerise/preflight.sh` checks it): `enp2s0`
   MTU 9000, `rmem_max`/`wmem_max` 33554432, CPU governor `performance`.
6. The new tools (`preflight.sh`, `run_gnb_x310.sh` with an experiment folder,
   `collect_run.sh`) have not run on WS-02 yet; check them on the first run.
