// aiken-validator-redteam — executable multi-agent adversarial red-team for
// Plutus V3 Aiken validators. A PASSING attack test = a confirmed vulnerability.
// See SKILL.md for the methodology and verdict levels.
//
// Run:  Workflow({ scriptPath: ".../redteam-workflow.js", args: { project: "contracts" } })
// args.project    — path to the aiken project (dir with aiken.toml/validators/lib). Default ".".
// args.remoteHost — optional ssh host with aiken installed; leave null to compile locally.
//                   Set it to offload compiles when the orchestration box is memory-constrained
//                   (a large fan-out of parallel Rust/aiken compiles can OOM a small host).
export const meta = {
  name: 'aiken-validator-redteam',
  description: 'Executable multi-agent adversarial red-team for Aiken validators: every eUTxO exploit class + novel attacks, PoC as adversarial Aiken tests where a PASSING test = a confirmed vuln, then skeptic-verified.',
  phases: [{ title: 'Attack' }, { title: 'Novel' }, { title: 'Verify' }],
}

// ── configuration (via args) ────────────────────────────────────────────
const PROJECT = (args && args.project) || '.'          // local aiken project path
const REMOTE = (args && args.remoteHost) || null        // ssh host, or null = compile locally
const SCRATCH = '/tmp/aiken-redteam'                    // per-agent isolated copies

// Build the isolation + compile instructions for one agent, local or remote.
const method = (slug) => {
  const dir = `${SCRATCH}/${slug}`
  if (REMOTE) {
    return `METHODOLOGY — you are a hostile attacker trying to STEAL or DESTROY funds, NOT a reviewer.
COMPILE ON THE REMOTE HOST (${REMOTE}) — never compile on this orchestration box (a big fan-out of aiken compiles can OOM it).
1. Copy the project on ${REMOTE}: ssh ${REMOTE} 'rm -rf ${dir} && mkdir -p ${dir} && cp -r ${PROJECT} ${dir}/proj'
2. Read the validator + fixture source LOCALLY from ${PROJECT} (byte-identical to the remote copy) — validators/*.ak, lib/**/*.ak, and the test fixtures used to build transactions.
3. Write each adversarial Aiken test with the Write tool to a LOCAL temp file, then push it: scp <localfile> ${REMOTE}:${dir}/proj/lib/tests/redteam_${slug}.ak
4. Compile on ${REMOTE}: ssh ${REMOTE} 'export PATH=$HOME/.local/bin:$PATH; cd ${dir}/proj && aiken check 2>&1 | tail -50'
${SHARED_STEPS}`
  }
  return `METHODOLOGY — you are a hostile attacker trying to STEAL or DESTROY funds, NOT a reviewer.
ISOLATION (do this FIRST, so you don't collide with other attackers): make your own private copy of the aiken project:
  rm -rf ${dir} && mkdir -p ${dir} && cp -r ${PROJECT} ${dir}/proj && cd ${dir}/proj
All edits + \`aiken check\` runs happen in ${dir}/proj — NEVER touch ${PROJECT} or another agent's dir. Read the validators (validators/*.ak) + lib/**/*.ak + the test fixtures there.
${SHARED_STEPS}`
}
const SHARED_STEPS = `For EACH concrete attack: write an adversarial Aiken test in a NEW file lib/tests/redteam_<class>.ak that CONSTRUCTS the malicious transaction and calls the validator function directly. The test asserts the validator returns TRUE (attack ACCEPTED). Run \`aiken check\`.
  - A PASSING attack-test (validator returned True on a fund-stealing / invariant-breaking input) = a CONFIRMED VULNERABILITY. Capture it.
  - A FAILING/crashing attack-test (rejected) = DEFENDED. Record what you tried, then iterate.
Be CREATIVE and RELENTLESS: edge amounts, wrong indices, missing/extra outputs, malformed datums, min-utxo dust, look-alike tokens, off-by-one, wrong credentials, reordered inputs/outputs. The attacker controls the whole tx EXCEPT the spent UTxO + its real datum.
Do NOT modify validator source or existing tests — only ADD your redteam file in your own copy.
Report CONFIRMED vulnerabilities (validator+function, what it steals/breaks, the passing test) and the concrete attacks that were correctly rejected. Confirm you actually ran aiken check.`

const FIND = {
  type: 'object', additionalProperties: false,
  required: ['attackClass', 'vulnerabilities', 'defendedAttacks', 'ranAikenCheck'],
  properties: {
    attackClass: { type: 'string' }, ranAikenCheck: { type: 'boolean' },
    defendedAttacks: { type: 'array', items: { type: 'string' } },
    vulnerabilities: { type: 'array', items: {
      type: 'object', additionalProperties: false, required: ['validator', 'steals', 'attackTest'],
      properties: { validator: { type: 'string' }, steals: { type: 'string' }, attackTest: { type: 'string' } } } },
  },
}

// Universal eUTxO fund-loss vectors. Edit .focus to match the contract's redeemers/datums.
const CLASSES = [
  { key: 'double_sat', focus: 'DOUBLE SATISFACTION: one output satisfying TWO+ script inputs (two positions / position+fee counting the same payout), esp. in a batched multi-action tx.' },
  { key: 'value_underpay', focus: 'VALUE UNDERPAYMENT / ROUNDING: pay owner/fee/vault LESS than owed; ratio floor/ceil; mint value from nowhere; a partial action releasing more than the ratio allows; 0/negative amounts.' },
  { key: 'mint_integrity', focus: 'MINT-POLICY / TOKEN INTEGRITY: mint EXTRA tokens under a policy; WRONG token names (not the hash of the datum they attest); create-without-burn on close; leak a policy token to a non-script output; net-zero cheats.' },
  { key: 'auth', focus: 'AUTHORIZATION BYPASS: cancel/close/reprice/update WITHOUT the owner credential; key-vs-script cred confusion; spoof the owner via a permissionless stake script (withdraw-zero); missing signatory.' },
  { key: 'index', focus: 'INDEX MANIPULATION: wrong input/output index so an *_at lookup resolves a DIFFERENT input/output; reorder to shift indices; out-of-range → crash-open vs fail-closed.' },
  { key: 'continuation', focus: 'CONTINUATION INTEGRITY: continuation output to a WRONG address; tamper an immutable datum field; bypass value conservation via a 2nd output / token substitution / negatives.' },
  { key: 'terms', focus: 'TERM CORRUPTION: re-quote a position to adverse economic terms while value+owner+pair stay pinned (the value check passes), then let a PERMISSIONLESS action drain via the counterparty path — a cross-redeemer composition the per-redeemer checks miss.' },
  { key: 'receipt', focus: 'PROOF/RECEIPT TOKEN FORGERY: mint a proof token with NO real action; attributes not matching the enforced amounts; multiple proofs per action; duplicate-claim guards defeated by padding claims.' },
  { key: 'refscript', focus: 'REFERENCE SCRIPT ABUSE: spend with a WRONG/attacker ref script; reference-input disjointness tricks; forged spend script + real policy reference; inline-script substitution.' },
  { key: 'composed', focus: 'COMPOSED MULTI-ACTION: siphon value between positions in one tx; index collisions across a batch; mix action types; one payout covering two positions.' },
  { key: 'directional', focus: 'TWO-WAY/AMM DIRECTIONAL: fill at a BETTER-than-set price; asymmetric take draining one reserve; price rational overflow/rounding; min-take bypass.' },
  { key: 'datum_decode', focus: 'DATUM DECODE / MALFORMED: unexpected constructor / extra fields / wrong types as state or continuation; force crash-OPEN; InlineDatum vs DatumHash confusion; wrong version tag.' },
  { key: 'time', focus: 'TIME / VALIDITY-RANGE: act past a validity/deadline; unbounded validity accepted; upper bound > deadline; time × partials/re-quotes/two-way; None edge.' },
  { key: 'oracle_premium', focus: 'ORACLE / COVERAGE PREMIUM: underpay a premium; skip/wrong vault; premium rounding to 0; a path not enforcing the oracle/coverage. (Skip if the contract has no oracle.)' },
]

phase('Attack')
const res = await parallel(CLASSES.map((c) => () =>
  agent(`ADVERSARIAL RED-TEAM (audit-grade). Attack class: ${c.key}.\n${c.focus}\n\n${method(c.key)}`,
    { label: `attack:${c.key}`, phase: 'Attack', schema: FIND, effort: 'high' })))
const found = res.filter(Boolean)
const rawVulns = found.flatMap((r) => (r.vulnerabilities || []).map((v) => ({ ...v, attackClass: r.attackClass })))
log(`Attack: ${found.length}/${CLASSES.length} ran; aiken-check-run=${found.filter((r) => r.ranAikenCheck).length}; ${rawVulns.length} vuln claims`)

phase('Novel')
const novel = await parallel([1, 2, 3].map((n) => () =>
  agent(`NOVEL/CREATIVE attacker #${n} (audit-grade). Per-class red-team is done; find what single-class attackers MISS: COMBINE primitives + invent emergent attacks. Seeds (go beyond): multi-tx sequences (create→re-quote→act→cancel leaks); cross-validator in one tx; economic (grief a party to a loss, force a stale-price action, min-utxo ratchet); policy-vs-script-hash parameterization mismatch; footgun stake creds combined with any path; batch with mixed action types + a hostile extra output.\n${method('novel_' + n)} Return schema with attackClass="novel_${n}".`,
    { label: `novel:${n}`, phase: 'Novel', schema: FIND, effort: 'high' })))
const novelVulns = novel.filter(Boolean).flatMap((r) => (r.vulnerabilities || []).map((v) => ({ ...v, attackClass: r.attackClass })))

// Skeptic-verify EVERY claim — per-class AND novel. A claim survives only if an
// independent agent reproduces validator acceptance of a real fund-loss, and
// classifies the deployment precondition (permissionless vs footgun-only).
phase('Verify')
const allClaims = [...rawVulns, ...novelVulns]
const verified = await parallel(allClaims.map((v, i) => () => {
  const dir = `${SCRATCH}/verify_${i}`
  const setup = REMOTE
    ? `Reproduce on ${REMOTE} (do NOT compile locally): ssh ${REMOTE} 'rm -rf ${dir} && mkdir -p ${dir} && cp -r ${PROJECT} ${dir}/proj'; read source LOCALLY from ${PROJECT}; write your test to a local temp file, scp it to ${REMOTE}:${dir}/proj/lib/tests/redteam_verify_${i}.ak, then ssh ${REMOTE} 'export PATH=$HOME/.local/bin:$PATH; cd ${dir}/proj && aiken check 2>&1 | tail -40'.`
    : `Reproduce locally in your OWN copy: rm -rf ${dir} && mkdir -p ${dir} && cp -r ${PROJECT} ${dir}/proj && cd ${dir}/proj; write your OWN adversarial test in lib/tests/ and run \`aiken check\`.`
  return agent(`Skeptic verify of a claimed Aiken validator VULNERABILITY (${v.attackClass}).
${setup}
Confirm the validator ACTUALLY returns True (accepts) on this fund-stealing input AND it is a genuine on-chain fund-loss/invariant-break — NOT a fixture artifact, NOT an already-rejected case.
LEDGER CONSISTENCY (critical for any TIME / validity-range / deadline finding): the ledger only includes a tx when the real slot s satisfies s ∈ [lower_bound, upper_bound]. So if the validator also bounds the range width (e.g. hi - lo <= max_skew), then hi is within max_skew of the real slot and CANNOT be fast-forwarded to an arbitrary future (e.g. near expiry) while other datum timestamps sit near real time. A unit test that calls the validator directly can present a validity range the ledger would never include; a "vulnerability" that only accepts because the datum's timestamps and the [lo,hi] range describe timelines that cannot COEXIST on one real chain (e.g. spend records stamped seconds ago but hi set years ahead) is a UNIT-TEST ARTIFACT — REFUTE it. Before CONFIRMING a time-based finding, reproduce it under a SINGLE consistent real timeline: every timestamp the validator itself stamps (e.g. a record's `at`) equals the `hi` of the tx that created it, each such tx's real slot lies in its own [lo,hi], and every [lo,hi] respects the width bound. If it no longer accepts under that discipline, it is REFUTED.
Classify the DEPLOYMENT PRECONDITION: does the drain work against the protocol default (the owner's own verification-key credential authorizes) → "permissionless" (protocol-wide, HIGH); or ONLY when a position was deployed behind a shared/permissionless stake SCRIPT any third party can satisfy → "footgun-only" (the default is safe; the code's auth guarantee is overstated).
Validator ${v.validator} | Steals ${v.steals}\nClaimed test: ${v.attackTest}
CONFIRMED only if you reproduce acceptance of a real theft/loss; else REFUTED. Set precondition to "permissionless" | "footgun-only" | "n/a".`,
    { label: `verify:${v.attackClass}:${i}`, phase: 'Verify', effort: 'high', schema: { type: 'object', additionalProperties: false, required: ['verdict', 'precondition', 'why'], properties: { verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED'] }, precondition: { type: 'string', enum: ['permissionless', 'footgun-only', 'n/a'] }, why: { type: 'string' } } } })
    .then((r) => ({ ...v, ...r }))
}))
const confirmed = verified.filter(Boolean).filter((v) => v.verdict === 'CONFIRMED')
const permissionless = confirmed.filter((v) => v.precondition === 'permissionless')
const footgunOnly = confirmed.filter((v) => v.precondition === 'footgun-only')
log(`Verify: ${confirmed.length} CONFIRMED of ${allClaims.length} (${permissionless.length} permissionless, ${footgunOnly.length} footgun-only)`)

return {
  classesRun: found.map((r) => ({ class: r.attackClass, ran: r.ranAikenCheck, defended: (r.defendedAttacks || []).length, vulns: (r.vulnerabilities || []).length })),
  confirmedVulns: confirmed.map((v) => ({ class: v.attackClass, validator: v.validator, steals: v.steals, precondition: v.precondition, why: v.why })),
  refutedClaims: verified.filter(Boolean).filter((v) => v.verdict === 'REFUTED').map((v) => ({ class: v.attackClass, why: v.why })),
  verdict: permissionless.length > 0
    ? 'RED — permissionless drain/forgery confirmed, fix before mainnet'
    : footgunOnly.length > 0
      ? 'AMBER — protocol default safe; footgun-only findings confirmed (harden and/or enforce the safe deployment + fix overstated comments)'
      : 'GREEN — no confirmed vuln across all classes + novel round',
}
