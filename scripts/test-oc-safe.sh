#!/usr/bin/env bash
# Exercises scripts/oc-safe.sh against a stub cardano-cli on PATH.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OC="$ROOT/scripts/oc-safe.sh"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
printf '#!/usr/bin/env bash\necho "STUB-CLI $*"\n' > "$STUB_DIR/cardano-cli"
chmod +x "$STUB_DIR/cardano-cli"
export PATH="$STUB_DIR:$PATH"

fails=0
pass() { echo "ok   $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

allows() {
  local out rc
  out="$("$OC" "$@" 2>&1)"; rc=$?
  if [[ $rc -eq 0 && "$out" == "STUB-CLI ${*:2}" ]]; then pass "allows: $*"; else fail "allows: $* (rc=$rc out=$out)"; fi
}

refuses() {
  local out rc
  out="$("$OC" "$@" 2>&1)"; rc=$?
  if [[ $rc -eq 2 && "$out" != *STUB-CLI* ]]; then pass "refuses: $*"; else fail "refuses: $* (rc=$rc out=$out)"; fi
}

allows cardano version
allows cardano --version
allows cardano query tip --mainnet
allows cardano conway query utxo --address addr_test1xyz --testnet-magic 1
allows cardano latest query protocol-parameters --mainnet
allows cardano address info --address addr1xyz
allows cardano conway transaction view --tx-file tx.signed
allows cardano conway transaction txid --tx-file tx.signed

refuses
refuses hydra --help
refuses cardano
refuses cardano conway
refuses cardano conway transaction sign --tx-body-file tx.raw --signing-key-file payment.skey --out-file tx.signed
refuses cardano conway transaction submit --tx-file tx.signed --mainnet
refuses cardano conway transaction build --tx-in x#0 --change-address addr1xyz
refuses cardano conway transaction witness --tx-body-file tx.raw --signing-key-file payment.skey
refuses cardano conway transaction assemble --tx-body-file tx.raw --witness-file w
refuses cardano conway address key-gen --verification-key-file p.vkey --signing-key-file p.skey
refuses cardano conway stake-address key-gen --verification-key-file s.vkey --signing-key-file s.skey
refuses cardano conway node key-gen --cold-verification-key-file c.vkey
refuses cardano conway key verification-key --signing-key-file p.skey
refuses cardano conway query protocol-parameters --mainnet --out-file /etc/passwd
refuses cardano conway query protocol-parameters --mainnet --out-file=/tmp/pp.json
refuses cardano query tip --mainnet "a;b"
refuses cardano query tip --mainnet 'x$(id)'
refuses cardano query tip --mainnet 'x`id`'

# The approvals must name oc-safe by its exact path: a glob would also allowlist
# any other checkout's oc-safe.sh, whatever that copy does.
for f in openclaw/exec-approvals.template.json openclaw/EXEC_APPROVALS.md scripts/apply-approvals.sh scripts/apply-approvals.ps1; do
  if grep -n '\*.*oc-safe\.sh' "$ROOT/$f" >/dev/null; then fail "glob oc-safe pattern in $f"; else pass "no glob oc-safe pattern in $f"; fi
done

if (( fails > 0 )); then echo "$fails oc-safe check(s) failed"; exit 1; fi
echo "all oc-safe checks passed"
