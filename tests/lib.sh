# shellcheck shell=bash
# Shared helpers for the security test suites.
PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

# expect_ok "description" command...   -> command must succeed
expect_ok() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

# expect_fail "description" command...  -> command must fail
expect_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

summary() {
  echo
  echo "$1: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
