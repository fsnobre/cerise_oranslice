#!/usr/bin/env bash
# Runs the ORANSlice gNB with this folder's gnb.conf and rrmPolicy.json.
# Logs go to logs/<run-id>/. Env and options: cerise/run_gnb_x310.sh.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${here}/../../cerise/run_gnb_x310.sh" "${here}" "$@"
