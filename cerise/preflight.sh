#!/usr/bin/env bash
# Read-only checks on the gNB host before a run. Changes nothing; prints the
# command that fixes each failed check (most need sudo, which you run).
#
#   ./cerise/preflight.sh [experiments/<date>_<slug>]
#
# With an experiment folder, the X310 address comes from its gnb.conf.
# Env: DOCKER  docker command (default: docker; use DOCKER='sudo docker' if
#              your user is not in the docker group)
#
# Exit status: 0 when nothing failed (warnings allowed), 1 otherwise.

set -uo pipefail

DOCKER="${DOCKER:-docker}"
read -r -a docker_cmd <<<"${DOCKER}"
fails=0
ok() { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }

x310=""
if [[ $# -ge 1 ]]; then
  [[ -f "$1/gnb.conf" ]] || { echo "no gnb.conf in $1" >&2; exit 1; }
  x310="$(grep -o 'addr=[0-9.]*' "$1/gnb.conf" | head -1 | cut -d= -f2)"
fi

echo "Radio"
if pgrep -x nr-softmodem >/dev/null; then
  fail "an nr-softmodem is running: $(ps -o user=,pid=,etime= -C nr-softmodem | tr -s ' ' | tr '\n' ';')"
else
  ok "no nr-softmodem running on this host"
fi
if [[ -n "${x310}" ]]; then
  if ping -c1 -W1 "${x310}" >/dev/null 2>&1; then
    ok "X310 ${x310} answers ping"
  else
    fail "X310 ${x310} does not answer ping (cable, address or interface down)"
  fi
  route="$(ip -4 route get "${x310}" 2>/dev/null | head -1)"
  dev="$(grep -o 'dev [^ ]*' <<<"${route}" | cut -d' ' -f2)"
  if [[ "${route}" == *" via "* ]]; then
    fail "X310 ${x310} is routed through a gateway (${route}): no direct 10 GbE link to it on this host"
  elif [[ -n "${dev}" ]]; then
    mtu="$(cat "/sys/class/net/${dev}/mtu" 2>/dev/null || echo 0)"
    if ((mtu >= 9000)); then
      ok "${dev} MTU ${mtu}"
    else
      fail "${dev} MTU ${mtu}; the conf sends 8000-byte frames. Fix: sudo ip link set ${dev} mtu 9000"
    fi
  fi
else
  warn "no experiment folder given: X310 and MTU not checked"
fi

echo "Host tuning (lost on reboot)"
for key in net.core.rmem_max net.core.wmem_max; do
  value="$(sysctl -n "${key}" 2>/dev/null || echo 0)"
  if ((value >= 33554432)); then
    ok "${key} ${value}"
  else
    fail "${key} ${value}. Fix: sudo sysctl -w ${key}=33554432"
  fi
done
governors="$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
if [[ -z "${governors}" ]]; then
  warn "CPU governor not readable"
elif [[ "${governors}" == *performance* && "${governors}" != *powersave* && "${governors}" != *schedutil* && "${governors}" != *ondemand* ]]; then
  ok "CPU governor:${governors}"
else
  warn "CPU governor:${governors} (USRP overflow seen on 2026-11-17). Fix: echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
fi
avail_gb="$(df -BG --output=avail / | tail -1 | tr -dc '0-9')"
if ((avail_gb < 2)); then
  fail "/ has ${avail_gb} GB free; logs may not fit"
elif ((avail_gb < 5)); then
  warn "/ has ${avail_gb} GB free"
else
  ok "/ has ${avail_gb} GB free"
fi

echo "Core (legacy OAI v1.5.1)"
if ! "${docker_cmd[@]}" ps >/dev/null 2>&1; then
  fail "cannot run '${DOCKER} ps' (try DOCKER='sudo docker')"
else
  for c in mysql oai-nrf oai-udr oai-udm oai-ausf oai-amf oai-smf oai-spgwu-tiny oai-ext-dn; do
    state="$("${docker_cmd[@]}" inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "${c}" 2>/dev/null)"
    case "${state}" in
      "running healthy" | "running ") ok "${c} ${state}" ;;
      "") fail "${c} does not exist (core not started)" ;;
      *) fail "${c} ${state}" ;;
    esac
  done
  compose="$("${docker_cmd[@]}" inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' oai-amf 2>/dev/null)"
  [[ -n "${compose}" ]] && ok "core started from ${compose}"
  env_of() { "${docker_cmd[@]}" inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2>/dev/null; }
  sd0="$(env_of oai-amf | sed -n 's/^SD_0=//p')"
  if [[ "${sd0^^}" == "0XFFFFFF" ]]; then
    ok "AMF first slice SD FFFFFF"
  elif [[ -n "${sd0}" ]]; then
    fail "AMF first slice SD ${sd0}: sessions without an S-NSSAI get it and DNN oai is rejected (cause 33). Put SD FFFFFF first"
  fi
  nat="$(env_of oai-spgwu-tiny | sed -n 's/^NETWORK_UE_IP=//p')"
  [[ -n "${nat}" ]] && ok "UPF NATs ${nat} (only DNN oai, 12.1.1.x, has internet)"
fi

echo
if ((fails)); then
  echo "${fails} check(s) failed."
  exit 1
fi
echo "Ready."
