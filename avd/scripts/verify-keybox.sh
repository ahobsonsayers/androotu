#!/usr/bin/env bash
# Fail unless <keybox.xml> has a 4-cert chain rooted in Google's hardware root
# (Key Attestation CA1); software attestation roots are rejected.
# Usage: verify-keybox.sh <keybox.xml>
set -euo pipefail

KEYBOX="${1:?usage: verify-keybox.sh <keybox.xml>}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 - "$KEYBOX" "$tmp" <<'PYEOF'
import base64
import os
import re
import sys

xml = open(sys.argv[1]).read()
outdir = sys.argv[2]
certs = re.findall(
    r'<Certificate[^>]*>\s*-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)-----',
    xml, re.S)
if not certs:
    sys.exit("FAIL: no certificates found in keybox")
for i, body in enumerate(certs):
    der = base64.b64decode(re.sub(r'\s+', '', body))
    with open(os.path.join(outdir, f'{i}.der'), 'wb') as fh:
        fh.write(der)
print(f'chain length: {len(certs)}')
PYEOF

root=""
for f in "$tmp"/[0-9]*.der; do
  subj=$(openssl x509 -inform DER -in "$f" -noout -subject)
  issu=$(openssl x509 -inform DER -in "$f" -noout -issuer)
  echo "  $subj"
  case "$subj $issu" in
    *Software*)
      echo "FAIL: software attestation root in keybox: $f" >&2
      exit 1
      ;;
  esac
  [ "${subj#subject=}" = "${issu#issuer=}" ] && root="$subj"
done

if [ -z "$root" ]; then
  echo "FAIL: no self-signed root in keybox chain" >&2
  exit 1
fi
case "$root" in
  *"Key Attestation CA1"*)
    echo "OK: hardware root: $root"
    ;;
  *)
    echo "FAIL: unexpected root (need Key Attestation CA1): $root" >&2
    exit 1
    ;;
esac