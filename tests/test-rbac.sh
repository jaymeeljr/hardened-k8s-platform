#!/usr/bin/env bash
# Verifies least-privilege RBAC by impersonating each role.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "== RBAC least privilege =="

dev() { kubectl auth can-i "$@" -n platform --as=alice --as-group=platform-developers; }
ci()  { kubectl auth can-i "$@" -n platform --as=ci-deployer; }

expect_ok   "developer can list pods"            dev list pods
expect_ok   "developer can read logs"            dev get pods/log
expect_fail "developer cannot read secrets"      dev get secrets
expect_fail "developer cannot exec into pods"    dev create pods/exec
expect_fail "developer cannot delete deployments" dev delete deployments
expect_ok   "CI can update deployments"          ci update deployments
expect_fail "CI cannot read secrets"             ci get secrets
expect_fail "CI cannot exec into pods"           ci create pods/exec
expect_fail "CI cannot modify RBAC"              ci create rolebindings

summary "RBAC"
