#!/usr/bin/env bash
# Clone rootAVD repo (Magisk patcher for AVDs).
set -euo pipefail
RD="${ROOTAVD_DIR:-$HOME/rootAVD}"
[ -d "$RD" ] || git clone https://github.com/newbit1/rootAVD.git "$RD"
echo "rootAVD at $RD"