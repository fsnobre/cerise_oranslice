#!/usr/bin/env bash
# Runs the ORANSlice gNB on bare metal on the CERISE X310 with the lab FN990 as
# the UE. Settings: oai_ran/targets/PROJECTS/GENERIC-NR-5GC/CONF/
# ORANSlice.gnb.sa.band78.fr1.106PRB.usrpx310.conf. See cerise/README.md.
#
# Start the core first (start_core.sh of an oai-rfsim-handover-testbed
# experiment folder). Run this as your own user: it calls sudo for
# nr-softmodem itself. Press Ctrl-C to stop the gNB.
#
# Env:
#   OAI_BUILD_DIR  folder holding nr-softmodem
#                  (default: <this repo>/oai_ran/cmake_targets/ran_build/build)
#   UHD_PREFIX     private UHD the build is linked against (default ~/uhd-4.4.0).
#                  The shared X310's FPGA opens only with UHD 4.4.0.
#   GNB_ARGS       softmodem flags (default: --sa -E --usrp-tx-thread-config 1).
#                  This OAI base needs --sa. -E gives the 46.08 MSps rate used in
#                  the validated vanilla OAI run.
#   DRY_RUN=1      print the command instead of running it

set -euo pipefail

CERISE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${CERISE_DIR}")"
INVOKER_HOME="${HOME}"
if [[ -n "${SUDO_USER:-}" ]]; then
  INVOKER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
fi
OAI_BUILD_DIR="${OAI_BUILD_DIR:-${REPO_DIR}/oai_ran/cmake_targets/ran_build/build}"
UHD_PREFIX="${UHD_PREFIX:-${INVOKER_HOME}/uhd-4.4.0}"
GNB_ARGS="${GNB_ARGS:---sa -E --usrp-tx-thread-config 1}"
SRC_CONF="${REPO_DIR}/oai_ran/targets/PROJECTS/GENERIC-NR-5GC/CONF/ORANSlice.gnb.sa.band78.fr1.106PRB.usrpx310.conf"
POLICY="${CERISE_DIR}/rrmPolicy.json"
RUN_DIR="${CERISE_DIR}/logs"

die() { echo "$*" >&2; exit 1; }

[[ -x "${OAI_BUILD_DIR}/nr-softmodem" ]] || die "nr-softmodem not found in ${OAI_BUILD_DIR}. Build it first (cerise/README.md) or set OAI_BUILD_DIR."
[[ -d "${UHD_PREFIX}/lib" ]] || die "No UHD at ${UHD_PREFIX}/lib. Build UHD 4.4.0 there or set UHD_PREFIX."

# The radio library must load the UHD 4.4.0 library. A build linked against the
# system UHD (for example libuhd.so.4.8.0) fails on this X310 with an
# "RFNoC protocol mismatch", so refuse to start it.
devif="${OAI_BUILD_DIR}/liboai_usrpdevif.so"
[[ -f "${devif}" ]] || die "${devif} is missing: the build has no USRP support (build_oai -w USRP)."
uhd_lib="$(LD_LIBRARY_PATH="${UHD_PREFIX}/lib" ldd "${devif}" | awk '/libuhd/ {print $1, $3}')"
case "${uhd_lib}" in
  "libuhd.so.4.4.0 ${UHD_PREFIX}/lib/"*) ;;
  *) die "liboai_usrpdevif.so resolves UHD as '${uhd_lib:-nothing}', not UHD 4.4.0 in ${UHD_PREFIX}/lib. Rebuild against it (cerise/README.md)." ;;
esac

mkdir -p "${RUN_DIR}"
stamp="$(date +%Y%m%d_%H%M%S)"
run_conf="${RUN_DIR}/gnb_${stamp}.conf"
log_file="${RUN_DIR}/gnb_${stamp}.log"

# Keep the exact conf beside its log, with SliceConf pointing at this folder's
# policy file (nr-softmodem runs from the build folder, so a relative path
# would not find it). The source conf has CRLF line endings.
sed -e 's#^\([[:space:]]*SliceConf[[:space:]]*=\).*$#\1 "'"${POLICY}"'";#' "${SRC_CONF}" | tr -d '\r' >"${run_conf}"
grep -q "SliceConf = \"${POLICY}\";" "${run_conf}" || die "Could not set SliceConf in ${run_conf}."

read -r -a extra_args <<<"${GNB_ARGS}"
# wall_clock stamps are Unix seconds, comparable with the core logs
# (date -d @<seconds>). This OAI base has no utc_time option.
cmd=(./nr-softmodem -O "${run_conf}"
  --log_config.global_log_options "level,nocolor,wall_clock" "${extra_args[@]}")
sudo_env=(env "LD_LIBRARY_PATH=${UHD_PREFIX}/lib")

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  rm -f "${run_conf}"
  echo "cd ${OAI_BUILD_DIR}"
  echo "sudo ${sudo_env[*]} ${cmd[*]}"
  echo "log: ${log_file}"
  exit 0
fi

echo "sudo ${sudo_env[*]} ${cmd[*]}" >"${RUN_DIR}/gnb_${stamp}.cmd"
if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
  trap 'chown "${SUDO_USER}:" "${RUN_DIR}" "${log_file}" "${run_conf}" "${RUN_DIR}/gnb_${stamp}.cmd" 2>/dev/null || true' EXIT
fi

cd "${OAI_BUILD_DIR}"
sudo -v
echo "[gnb] Logging to ${log_file}"
sudo "${sudo_env[@]}" "${cmd[@]}" 2>&1 | tee -i "${log_file}"
