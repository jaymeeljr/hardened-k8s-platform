#!/usr/bin/env bash
# Simulates an attacker opening a shell in the API pod and checks that Falco
# raises the custom alert.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "== Falco runtime detection =="

kubectl -n platform exec deploy/api -- sh -c 'id; cat /etc/os-release >/dev/null' >/dev/null 2>&1

found=1
for _ in $(seq 1 12); do
  if kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=-1 2>/dev/null \
      | grep -q "Shell spawned in hardened namespace"; then
    found=0; break
  fi
  sleep 5
done

if [ "$found" -eq 0 ]; then
  pass "Falco alerted on shell spawned in api pod"
  kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=-1 \
    | grep "Shell spawned in hardened namespace" | head -1
else
  fail "Falco alerted on shell spawned in api pod"
fi

summary "Falco"
