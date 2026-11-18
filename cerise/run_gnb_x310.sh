#!/usr/bin/env bash
# Runs the ORANSlice gNB on bare metal on a lab X310 for one experiment folder
# (experiments/<date>_<slug>/, made by cerise/new_experiment.py). Usually called
# through that folder's start_gnb.sh. See experiments/README.md.
#
#   ./cerise/run_gnb_x310.sh experiments/<date>_<slug> [extra nr-softmodem flags]
#
# Start the core first (cerise/preflight.sh checks it). Run this as your own
# user: it calls sudo for nr-softmodem itself. Press Ctrl-C to stop the gNB.
#
# Each run gets logs/<run-id>/ in the experiment folder (git-ignored), and
# logs/latest points at it:
#   gnb.log       nr-softmodem output, lines stamped with Unix seconds
#                 (date -d @<seconds>), comparable with docker logs -t
#   gnb.conf      the exact conf run (SliceConf set to the folder's rrmPolicy.json)
#   gnb.cmd       the command line
#   run_info.txt  start time, host, commit, UHD library, policy at start
#
# Env:
#   OAI_BUILD_DIR  folder holding nr-softmodem
#                  (default: <this repo>/oai_ran/cmake_targets/ran_build/build)
#   UHD_PREFIX     private UHD install the build is linked against (for example
#                  ~/uhd-4.4.0 on WS-03). Unset: the system UHD (WS-02, 4.8.0).
#                  When set, the build must resolve libuhd from ${UHD_PREFIX}/lib.
#   GNB_ARGS       softmodem flags (default: --sa -E --usrp-tx-thread-config 1).
#                  This OAI base needs --sa; -E gives the 46.08 MSps rate.
#   DRY_RUN=1      check everything and print the command without running it

set -euo pipefail

die() { echo "run_gnb_x310: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: $0 experiments/<date>_<slug> [extra nr-softmodem flags]"
[[ -d "$1" ]] || die "no experiment folder at $1"
EXP_DIR="$(cd "$1" && pwd)"
shift

CERISE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${CERISE_DIR}")"
INVOKER_HOME="${HOME}"
if [[ -n "${SUDO_USER:-}" ]]; then
  INVOKER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
fi
OAI_BUILD_DIR="${OAI_BUILD_DIR:-${REPO_DIR}/oai_ran/cmake_targets/ran_build/build}"
GNB_ARGS="${GNB_ARGS:---sa -E --usrp-tx-thread-config 1}"
SRC_CONF="${EXP_DIR}/gnb.conf"
POLICY="${EXP_DIR}/rrmPolicy.json"

[[ -f "${SRC_CONF}" ]] || die "${SRC_CONF} is missing. Create experiments with cerise/new_experiment.py."
[[ -f "${POLICY}" ]] || die "${POLICY} is missing."
python3 -c 'import json, sys; json.load(open(sys.argv[1]))["rrmPolicyRatio"]' "${POLICY}" \
  || die "${POLICY} is not a valid policy file."
[[ -x "${OAI_BUILD_DIR}/nr-softmodem" ]] || die "nr-softmodem not found in ${OAI_BUILD_DIR}. Build it (cerise/README.md) or set OAI_BUILD_DIR."

# Only one gNB may use a radio. Any nr-softmodem on this host, from any user,
# is most likely on this host's X310.
if pgrep -x nr-softmodem >/dev/null; then
  ps -o user=,pid=,etime=,args= -C nr-softmodem >&2 || true
  die "an nr-softmodem is already running on this host (above). Only one gNB may use the radio."
fi

# Which UHD the radio library loads. The X310's FPGA image must match it
# (WS-03's X310 aborts with "RFNoC protocol mismatch" under UHD 4.8.0).
devif="${OAI_BUILD_DIR}/liboai_usrpdevif.so"
[[ -f "${devif}" ]] || die "${devif} is missing: the build has no USRP support (build_oai -w USRP)."
sudo_env=()
if [[ -n "${UHD_PREFIX:-}" ]]; then
  UHD_PREFIX="${UHD_PREFIX/#\~/${INVOKER_HOME}}"
  [[ -d "${UHD_PREFIX}/lib" ]] || die "UHD_PREFIX=${UHD_PREFIX} has no lib/."
  sudo_env=(env "LD_LIBRARY_PATH=${UHD_PREFIX}/lib")
  uhd_lib="$(LD_LIBRARY_PATH="${UHD_PREFIX}/lib" ldd "${devif}" 2>/dev/null | awk '/libuhd/ {print $1, $3}' || true)"
  [[ "${uhd_lib}" == *" ${UHD_PREFIX}/lib/"* ]] \
    || die "liboai_usrpdevif.so resolves UHD as '${uhd_lib:-nothing}', not from ${UHD_PREFIX}/lib. Rebuild against it (cerise/README.md)."
else
  uhd_lib="$(ldd "${devif}" 2>/dev/null | awk '/libuhd/ {print $1, $3}' || true)"
fi
[[ -n "${uhd_lib}" && "${uhd_lib}" != *"not found"* ]] || die "liboai_usrpdevif.so does not resolve libuhd ('${uhd_lib}')."

run_id="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${EXP_DIR}/logs/${run_id}"
run_conf="${RUN_DIR}/gnb.conf"
log_file="${RUN_DIR}/gnb.log"

read -r -a extra_args <<<"${GNB_ARGS}"
extra_args+=("$@")
# wall_clock stamps are Unix seconds, comparable with docker logs -t
# (date -d @<seconds>). This OAI base has no utc_time option.
cmd=(./nr-softmodem -O "${run_conf}"
  --log_config.global_log_options "level,nocolor,wall_clock" "${extra_args[@]}")

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "experiment: ${EXP_DIR}"
  echo "UHD: ${uhd_lib}"
  echo "X310: $(grep -o 'addr=[0-9.]*' "${SRC_CONF}" | head -1)"
  echo "cd ${OAI_BUILD_DIR}"
  echo "sudo ${sudo_env[*]} ${cmd[*]}"
  echo "log: ${log_file}"
  exit 0
fi

mkdir -p "${RUN_DIR}"
ln -sfn "${run_id}" "${EXP_DIR}/logs/latest"
# nr-softmodem runs from the build folder, so SliceConf must be absolute.
sed -e 's#^\([[:space:]]*SliceConf[[:space:]]*=\).*$#\1 "'"${POLICY}"'";#' "${SRC_CONF}" >"${run_conf}"
grep -q "SliceConf = \"${POLICY}\";" "${run_conf}" || die "could not set SliceConf in ${run_conf}."
echo "sudo ${sudo_env[*]} ${cmd[*]}" >"${RUN_DIR}/gnb.cmd"
{
  echo "start: $(date --iso-8601=seconds)"
  echo "host: $(hostname)"
  echo "user: ${SUDO_USER:-${USER:-unknown}}"
  echo "experiment: ${EXP_DIR#"${REPO_DIR}"/}"
  echo "commit: $(git -C "${REPO_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)$(git -C "${REPO_DIR}" status --porcelain --untracked-files=no 2>/dev/null | grep -q . && echo ' (uncommitted changes)')"
  echo "build: ${OAI_BUILD_DIR}"
  echo "uhd: ${uhd_lib}"
  echo "x310: $(grep -o 'addr=[0-9.]*' "${SRC_CONF}" | head -1)"
  echo "gnb_args: ${extra_args[*]}"
  echo "policy_at_start: $(tr -d ' \n\t' <"${POLICY}")"
} >"${RUN_DIR}/run_info.txt"

if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
  trap 'chown -R "${SUDO_USER}:" "${EXP_DIR}/logs" 2>/dev/null || true' EXIT
fi

cd "${OAI_BUILD_DIR}"
sudo -v
echo "[gnb] run ${run_id}: logging to ${log_file}"
# tee -i survives Ctrl-C, so the last lines of the log are not lost.
sudo "${sudo_env[@]}" "${cmd[@]}" 2>&1 | tee -i "${log_file}"
