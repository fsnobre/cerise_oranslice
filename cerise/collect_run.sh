#!/usr/bin/env bash
# Saves what a run review needs into the run's log folder, on the gNB host
# (which is also the core host on WS-02). Run it after Ctrl-C on the gNB and
# before stopping the core: docker logs are gone once the containers are removed.
#
#   ./cerise/collect_run.sh experiments/<date>_<slug> [run-id]   # default: logs/latest
#
# Writes into logs/<run-id>/ (git-ignored):
#   core/<container>.log   docker logs -t (UTC stamps); the AMF/AUSF/UDM logs
#                          hold SIM session keys: never commit or print them
#   core/state.txt         containers, AMF/SMF/UPF slice and DNN settings, UPF NAT
#   rrmPolicy_at_end.json  the policy file when collected
#   policy_changes.tsv     copy of the experiment's policy history
#   summary.txt            cerise/summarize_gnb_log.sh of gnb.log
# Env: DOCKER  docker command (default: docker; DOCKER='sudo docker' if needed)

set -euo pipefail

die() { echo "collect_run: $*" >&2; exit 1; }
[[ $# -ge 1 && -d "$1" ]] || die "usage: $0 experiments/<date>_<slug> [run-id]"
EXP_DIR="$(cd "$1" && pwd)"
run="${2:-latest}"
RUN_DIR="${EXP_DIR}/logs/${run}"
[[ -d "${RUN_DIR}" ]] || die "no run folder ${RUN_DIR}"
RUN_DIR="$(cd "${RUN_DIR}" && pwd -P)"
CERISE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
read -r -a docker_cmd <<<"${DOCKER:-docker}"

"${docker_cmd[@]}" ps >/dev/null 2>&1 || die "cannot run '${DOCKER:-docker} ps' (try DOCKER='sudo docker')"

mkdir -p "${RUN_DIR}/core"
containers=(mysql oai-nrf oai-udr oai-udm oai-ausf oai-amf oai-smf oai-spgwu-tiny oai-ext-dn)
for c in "${containers[@]}"; do
  if "${docker_cmd[@]}" inspect "${c}" >/dev/null 2>&1; then
    "${docker_cmd[@]}" logs -t "${c}" >"${RUN_DIR}/core/${c}.log" 2>&1
  else
    echo "  ${c}: no such container" >&2
  fi
done

{
  echo "# collected $(date --iso-8601=seconds) on $(hostname)"
  echo "== containers"
  "${docker_cmd[@]}" ps -a --format '{{.Names}} {{.Image}} {{.Status}}'
  echo "== compose file"
  "${docker_cmd[@]}" inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' oai-amf 2>/dev/null || true
  # Slice, DNN and NAT settings only: never dump whole environments or the database.
  for c in oai-amf oai-smf oai-spgwu-tiny; do
    echo "== ${c} slice/DNN settings"
    "${docker_cmd[@]}" inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "${c}" 2>/dev/null \
      | grep -E '^(SST|SD|NSSAI|DNN|TYPE|NETWORK_UE)' || true
  done
  echo "== UPF NAT rules"
  "${docker_cmd[@]}" exec oai-spgwu-tiny iptables -t nat -S POSTROUTING 2>/dev/null || echo "(not readable)"
} >"${RUN_DIR}/core/state.txt" 2>&1

cp "${EXP_DIR}/rrmPolicy.json" "${RUN_DIR}/rrmPolicy_at_end.json"
[[ -f "${EXP_DIR}/logs/policy_changes.tsv" ]] && cp "${EXP_DIR}/logs/policy_changes.tsv" "${RUN_DIR}/"
[[ -f "${RUN_DIR}/gnb.log" ]] && "${CERISE_DIR}/summarize_gnb_log.sh" "${RUN_DIR}/gnb.log" >"${RUN_DIR}/summary.txt"

if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
  chown -R "${SUDO_USER}:" "${RUN_DIR}"
fi
echo "Collected into ${RUN_DIR}:"
ls -1 "${RUN_DIR}" | sed 's/^/  /'
echo "Copy it to the laptop from the laptop (transfers start there):"
echo "  rsync -a ws02:~/cerise_oranslice/experiments/$(basename "${EXP_DIR}")/logs/ experiments/$(basename "${EXP_DIR}")/logs/"
