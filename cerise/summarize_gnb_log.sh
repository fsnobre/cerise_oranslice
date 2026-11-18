#!/usr/bin/env bash
# Counts the gNB log lines a run review starts from. Read-only.
#
#   ./cerise/summarize_gnb_log.sh experiments/<exp>/logs/<run-id>/gnb.log
#
# The counts are where to look, not results: read the lines around them
# (docs/guide-log-review.md says what each one means).

set -euo pipefail

log="${1:?usage: $0 <gnb.log>}"
[[ -f "${log}" ]] || { echo "no file ${log}" >&2; exit 1; }

# Strip colour codes so the patterns match logs written with or without nocolor.
clean() { sed -e 's/\x1b\[[0-9;]*m//g' "${log}"; }
count() { clean | grep -c -- "$1" || true; }

echo "== ${log}"
echo "-- Radio and process"
printf '%-46s %s\n' \
  "USRP overflow (ERROR_CODE_OVERFLOW)" "$(count ERROR_CODE_OVERFLOW)" \
  "short reads (rx_rf: Asked for)" "$(count 'rx_rf: Asked for')" \
  "assertions" "$(count 'Assertion')" \
  "NG setup with the AMF (associated AMF)" "$(count 'associated AMF')"
echo "-- Access and link stability"
printf '%-46s %s\n' \
  "random-access attempts (Initiating RA)" "$(count 'Initiating RA procedure')" \
  "RRC re-establishments accepted" "$(count 'Accept Reestablishment Request')" \
  "UL failure on PUSCH (Detected UL Failure)" "$(count 'Detected UL Failure on PUSCH')" \
  "distinct RNTIs in UE stats" "$(clean | grep -o 'UE RNTI [0-9a-f]\{4\}' | sort -u | wc -l)"
echo "-- Re-establishment causes"
clean | grep -o 'Accept Reestablishment Request .*cause .*' | sed 's/.*cause /  /' | sort | uniq -c || echo "  none"
echo "-- Slice policy reads (max_ratio, in order: value x reads)"
clean | grep -o 'NSSAI [0-9.a-f]*, rrmPolicy.dedicated_ratio [0-9]*, rrmPolicy.min_ratio [0-9]*, rrmPolicy.max_ratio [0-9]*' \
  | awk '{k=$2" ded "$4+0" min "$6+0" max "$8+0; if (k!=prev) {if (prev!="") print "  " prev " x " n; prev=k; n=0} n++}
         END {if (prev!="") print "  " prev " x " n; else print "  no policy reads (wrong SliceConf path?)"}'
errors="$(count 'Error in opening rrmPolicy file')"
((errors)) && echo "  'Error in opening rrmPolicy file' x ${errors}"
echo "-- Last statistics of each UE that reached RRC (CU-UE-ID set)"
clean | grep -E '^UE [0-9a-f]{4}: (dlsch_rounds|ulsch_rounds)|^UE RNTI [0-9a-f]{4} ' \
  | awk '$2=="RNTI" {u=$3; if ($5!="(none)") {keep[u]=1; order[u]=++n} last[u,"a"]=$0; next}
         {u=substr($2,1,4); last[u, ($3=="dlsch_rounds")?"b":"c"]=$0}
         END {for (u in keep) out[order[u]]=u
              for (i=1; i<=n; i++) if (i in out) {u=out[i]; print "  " last[u,"a"]; print "    " last[u,"b"]; print "    " last[u,"c"]}}'
