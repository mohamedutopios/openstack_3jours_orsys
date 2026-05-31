#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$HOME/kolla-venv/bin/activate"
INVENTORY="${INVENTORY:-./multinode}"
kolla-ansible -i "$INVENTORY" prechecks
