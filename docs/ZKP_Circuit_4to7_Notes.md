# ZKP / Circom / SnarkJS — Days 4-7 Notes
**Topics covered:** Loops+Arrays practice (CountMatches) → Poseidon Hash/Commitment → Merkle Tree Membership (single-level, then multi-level)

---

## Circuit 4: CountMatches — Loops, Arrays, Running-Sum Pattern

### The Circuit

```circom
pragma circom 2.0.0;

include "circomlib/circuits/comparators.circom";

template CountMatches(n, maxAllowed) {
    signal input arr[n];
    signal input target;

    signal output matchCount;
    signal output withinLimit;

    signal diff[n];
    signal inv[n];
    signal isMatch[n];
    signal partialSum[n+1];

    partialSum[0] <== 0;

    for (var i = 0; i < n; i++) {
        diff[i] <== arr[i] - target;
        inv[i] <-- diff[i] != 0 ? 1/diff[i] : 0;
        isMatch[i] <== 1 - diff[i]*inv[i];
        diff[i] * isMatch[i] === 0;

        partialSum[i+1] <== partialSum[i] + isMatch[i];
    }

    matchCount <== partialSum[n];

    component check = LessEqThan(8);
    check.in[0] <== partialSum[n];
    check.in[1] <== maxAllowed;
    withinLimit <== check.out;
}

component main = CountMatches(5, 2);
```

### Purpose
Counts how many times a `target` value appears in an array `arr[n]`, and checks whether that count is within an allowed maximum. Test case: `arr=[3,7,3,3,9], target=3` → `matchCount=3`, and since `3 > maxAllowed(2)` → `withinLimit=0`.

### Key concepts learned

**Signal arrays vs single signals:** `diff[n]`, `inv[n]`, `isMatch[n]` are arrays because the loop runs `n` times and each iteration needs its own independent copy — a signal can't be reassigned, so each iteration needs a fresh "slot."

**The IsEqual/IsZero pattern reused per-element:** Same `diff`/`inv`/formula/safety-check logic from the earlier IsEqual circuit, just applied inside a loop across every array element.

**Running-sum pattern (important — reused later in Merkle):** Since signals are immutable, a "running total" can't be updated in place like a normal variable (`count = count + 1`). Instead, an array of "steps" is built: `partialSum[i+1] <== partialSum[i] + isMatch[i]`, where each step depends on the previous one. `partialSum[0]` is the starting point (0), and `partialSum[n]` is the final result. This exact pattern reappears in the Merkle circuit as `levelHashes[i+1] <== hasher[i].out` — a "running hash" instead of a "running sum."

**`var` vs `signal` — refined rule:** Use `signal` when a value depends (directly or indirectly) on any `signal input` — i.e., it's runtime/witness data. Use `var` when a value only depends on compile-time constants (template parameters, loop counters) — it never touches actual input data and never appears in the witness/proof. `i` (loop counter) is `var`; `diff[i]`, `inv[i]`, `isMatch[i]` are `signal` because they derive from `arr[i]` and `target` (both signal inputs).

**When to add a `===` safety constraint — general rule:** Whenever `<--` is used (assign-only, no automatic constraint), ask "could a dishonest prover put an inconsistent value here?" If yes, add a `===` constraint that would fail if the value doesn't match what it should honestly be. This is exactly why `diff[i] * isMatch[i] === 0` exists — without it, a fake `inv[i]` could make `isMatch[i]` become some arbitrary non-0/1 value; the constraint mathematically traps this cheat (verified numerically: with a faked `inv`, the constraint no longer equals 0, so the proof becomes invalid).

**Multiple outputs are just multiple `signal output` declarations** — no special syntax needed. `public.json` will list all of them in order.

### Circomlib setup issue encountered (recurring across circuits 3-7)
`npm install circomlib` inconsistently failed to actually populate `node_modules` on this Windows setup (reported success but folder was missing). **Reliable fix used throughout:** clone directly from GitHub once, then copy the `circomlib` folder into each new circuit's directory:
```
git clone https://github.com/iden3/circomlib.git
# or, once cloned once, reuse it:
Copy-Item -Recurse "..\<some-earlier-circuit-folder>\circomlib" ".\circomlib"
```
Compile with the local include path:
```
circom <file>.circom --r1cs --wasm --sym -l .
```

---

## Circuit 5: Poseidon Commitment

### The Circuit

```circom
pragma circom 2.0.0;

include "circomlib/circuits/poseidon.circom";

template Commitment() {
    signal input secret;
    signal output commitment;

    component hasher = Poseidon(1);
    hasher.inputs[0] <== secret;

    commitment <== hasher.out;
}

component main = Commitment();
```

### Purpose
First real building block for the FYP: `commitment = Poseidon(secret)`. This is exactly the pattern used at enrollment time to register an identity without ever storing the raw secret.

### Key concepts learned

**Why Poseidon over SHA256 inside circuits:** SHA256 relies on bit-level operations (XOR, shifts, AND/OR) which are cheap for a CPU but expensive in R1CS — each bit-operation needs to be simulated through multiple multiplication-constraints, since XOR has no native field-arithmetic equivalent. A single SHA256 hash can cost ~20,000+ constraints. Poseidon is designed from the ground up to use only field-native operations (addition, and exponentiation like `x^5`), costing roughly 150-300 constraints for the same security purpose — a 10-100x reduction.

**How Poseidon works internally (concept-level only, not required to derive):** A "sponge construction" — input values enter a state, which passes through several rounds of an S-box (`x^5`) and a fixed matrix-multiplication ("mixing"), until the output is unrecoverable back to the input. Implementation details are abstracted away by the `Poseidon()` template — never needs to be derived manually, only imported/called (`circomlib` uses audited, standard rounds/constants).

**`Poseidon(n)` — meaning of `n`:** Purely how many inputs get hashed together in one call, not a "quality" or randomness setting. `Poseidon(1)` hashes a single value (used here for `commitment`); `Poseidon(2)` hashes two values together (used in the Merkle circuit, to combine two child-hashes into a parent).

**Determinism — a hash function is not random.** Poseidon (like any hash function) is a fixed mathematical formula applied to fixed internal constants: same input → always the exact same output, on any machine, any time. This is essential for the whole identity system to work — the commitment computed at enrollment must exactly match the one recomputed at verification time for the same secret, or the system could never recognize a legitimate person.

**Signal-name matching input.json:** `input.json` keys must exactly match `signal input` names in the circuit (e.g. `{"secret": 12345}` matches `signal input secret;`) — a mismatch causes witness-generation errors.

### Test performed
`secret = 12345` → produced a large, deterministic hash value in `public.json`; verify returned `OK!`. Re-running with the exact same secret reproduces the identical hash (confirmed conceptually — same input, same fixed computation, same output).

---

## Circuit 6: Single-Level Merkle Combination

### The Circuit

```circom
pragma circom 2.0.0;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/mux1.circom";

template MerkleLevel() {
    signal input leaf;
    signal input sibling;
    signal input isLeft;   // 0 or 1
    signal output root;

    component leftMux = Mux1();
    component rightMux = Mux1();

    leftMux.c[0] <== sibling;
    leftMux.c[1] <== leaf;
    leftMux.s <== isLeft;

    rightMux.c[0] <== leaf;
    rightMux.c[1] <== sibling;
    rightMux.s <== isLeft;

    component hasher = Poseidon(2);
    hasher.inputs[0] <== leftMux.out;
    hasher.inputs[1] <== rightMux.out;

    root <== hasher.out;
}

component main = MerkleLevel();
```

### Purpose
A single Merkle-tree "level" combination: given a leaf and its sibling, plus a bit indicating which side the leaf sits on, compute the parent hash — the fundamental operation repeated at every level of a real Merkle tree.

### Key concepts learned

**Mux1 (multiplexer) — how signal-based "if/else" actually works:** Circom's `if/else` keyword only works on `var` conditions decided at compile time — it cannot branch on `signal` values (like `isLeft`), because the circuit's shape is permanently fixed at compile time, before any actual input value exists. To make a decision based on a runtime signal, `Mux1` is used instead, implementing the choice with pure algebra:
```
out = c[0] + s*(c[1] - c[0])
```
If `s=0` → `out=c[0]`; if `s=1` → `out=c[1]`. No branching, just arithmetic — the same philosophy as the `IsZero`/`IsEqual` trick.

**Two Mux components needed, one for each "slot":** `leftMux` decides what goes in the left position of the pair (sibling if leaf is on the left, or leaf itself if leaf is on the right); `rightMux` decides the opposite for the right position. Together they route `leaf` and `sibling` into the correct order before hashing, based purely on the `isLeft` signal.

**Privacy is automatic by default — no extra syntax needed:** All `signal input`s (`leaf`, `sibling`, `isLeft`) are private by default in circom; nothing needed to be explicitly hidden. The `signal output root` is public automatically. This exactly matched the privacy requirement (leaf, sibling, and position should never be revealed) without any special declarations — default circom behavior already aligned with the project's needs at this stage (before `root` became an *input* in Circuit 7).

**Soundness demonstrated in practice (not just theory):** During testing, a digit was accidentally altered in a copy-pasted `public.json` value between two verify runs. The second verification immediately failed (`[ERROR] snarkJS: Invalid proof`) — direct, practical confirmation that even a single-digit tamper is caught by the pairing-check math, exactly as the theoretical "soundness" discussion predicted.

---

## Circuit 7: Multi-Level Merkle Proof (full membership check)

### The Circuit

```circom
pragma circom 2.0.0;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/mux1.circom";
include "circomlib/circuits/comparators.circom";

template MerkleProof(depth) {
    signal input leaf;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    signal input root;
    signal output isValid;

    signal levelHashes[depth+1];
    levelHashes[0] <== leaf;

    component leftMux[depth];
    component rightMux[depth];
    component hasher[depth];

    for (var i = 0; i < depth; i++) {
        leftMux[i] = Mux1();
        rightMux[i] = Mux1();
        hasher[i] = Poseidon(2);

        leftMux[i].c[0] <== pathElements[i];
        leftMux[i].c[1] <== levelHashes[i];
        leftMux[i].s <== pathIndices[i];

        rightMux[i].c[0] <== levelHashes[i];
        rightMux[i].c[1] <== pathElements[i];
        rightMux[i].s <== pathIndices[i];

        hasher[i].inputs[0] <== leftMux[i].out;
        hasher[i].inputs[1] <== rightMux[i].out;

        levelHashes[i+1] <== hasher[i].out;
    }

    component eq = IsEqual();
    eq.in[0] <== levelHashes[depth];
    eq.in[1] <== root;
    isValid <== eq.out;
}

component main {public [root]} = MerkleProof(3);
```

### Purpose — the FYP's core circuit
Given a `leaf` (identity commitment), its Merkle `pathElements` (siblings) and `pathIndices` (left/right positions) at every level, plus a publicly-known `root`, this proves: **"I know a leaf whose path leads to this exact root" — without revealing the leaf, its path, or its position in the tree.** This is the anonymous membership-verification mechanism the whole door-access system depends on.

### Key concepts learned

**Component arrays (`component leftMux[depth];`):** A new syntax pattern — since the loop must create a fresh, independent `Mux1`/`Poseidon` component on every iteration (they can't be reused across iterations), an array of component "slots" is declared, then each slot is individually initialized inside the loop using `=` (not `<==` — `=` instantiates a component, `<==` only assigns values to signals):
```circom
leftMux[i] = Mux1();
```

**"Running hash" — same pattern as CountMatches' running sum:** `levelHashes[0] <== leaf` is the starting point; each iteration computes the next level's combined hash: `levelHashes[i+1] <== hasher[i].out`. The final value `levelHashes[depth]` is the fully computed root, built up level-by-level exactly like `partialSum` was built up match-by-match in Circuit 4.

**Reusing the single-level logic inside the loop:** Circuit 6's exact `leftMux`/`rightMux`/`hasher` logic is repeated per level, with one change: instead of always using `leaf` as one side of the Mux, iteration `i` uses `levelHashes[i]` (the leaf on the first iteration, the growing combined-hash on every iteration after).

**Explicit public declaration — `{public [root]}` — first time this syntax was needed:** All prior circuits only had public *outputs* (automatically public). Here, `root` is an **input**, and — unlike outputs — inputs are private by default, so making one public requires the explicit syntax:
```circom
component main {public [root]} = MerkleProof(3);
```
This is the general rule: use `{public [...]}` only when a specific *input* needs to be publicly visible; outputs never need this since they're public by default already.

**Practical workflow for finding the correct root during testing:** Since the actual computed root isn't known in advance, the circuit was first run with a dummy `root` (e.g. `0`) to confirm `isValid=0` as expected. A temporary `computedRoot` output signal was added (`computedRoot <== levelHashes[depth];`) to reveal what the circuit actually computed, that value was copied (as a **string**, to preserve precision for such a large number) into `input.json`'s `root` field, and the circuit was re-run — this time `isValid=1`, with `root` and `computedRoot` matching exactly, confirming the whole membership-check pipeline works end-to-end.

### What this circuit does NOT do (important scope clarification)
This circuit only **verifies** a given path against a given root — it does **not** build the Merkle tree itself. In a real system:
- **Building the tree** (collecting all enrolled commitments, computing every level, producing the root) happens in normal backend code (JavaScript, using a library like `circomlibjs` or `merkletreejs`) — entirely outside circom, done once at enrollment/whenever the authorized list changes.
- **Retrieving a specific leaf's path** (siblings + indices) at verification time is also backend work — the backend looks up the stored path for that person and feeds it into this circuit.
- **Circom's job is strictly the verification step** — confirming a given path is consistent with a given root. This is the correct, minimal scope for the ZK circuit; everything else is ordinary software engineering handled by the backend/enrollment system.

---

## Overall Flow Recap (Circuits 4→7)

```
Circuit 4 (CountMatches)
   → practiced: arrays, loops, running-sum pattern, var vs signal, safety-constraints
   → these patterns directly reused in Circuit 7's "running hash"

Circuit 5 (Poseidon Commitment)
   → secret → commitment (Poseidon(1))
   → this IS the enrollment-time commitment generation for the FYP

Circuit 6 (Single Merkle Level)
   → leaf + sibling + isLeft → parent hash (Poseidon(2) + Mux1)
   → introduced Mux1 as the way to do signal-based conditional logic

Circuit 7 (Multi-Level Merkle Proof)
   → leaf + full path (array) + public root → isValid
   → combines everything: loops+arrays (from Ckt 4), Poseidon (from Ckt 5),
     Mux1-based level combination (from Ckt 6), plus explicit public-input syntax
   → THIS is the FYP's core identity-verification circuit
```

## Next Steps
- **Nullifier circuit** (small, Poseidon(2)-based, for replay protection) — deferred, to be done later.
- Consider combining Commitment + Merkle Proof (+ eventually Nullifier) into a single end-to-end circuit matching the real system's exact verification call.
- Backend/enrollment-side tree-building (JavaScript, outside circom) — separate piece of work, not a circom task.
