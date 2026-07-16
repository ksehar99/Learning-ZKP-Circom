# ZKP / Circom / SnarkJS — Day 2 Notes
**Topic:** IsEqual circuit — checking if two secret numbers are equal, without revealing them

---

## 1. The Circuit (`isEqual.circom`)

```circom
pragma circom 2.0.0;

template IsEqual(){
    signal input a;
    signal input b;
    signal output out;

    signal diff;
    signal inv;

    diff <== a - b;
    inv <-- diff != 0 ? 1/diff : 0;

    out <== 1 - diff*inv;

    diff * out === 0; // safety check
}

component main = IsEqual();
```

### Logic behind it
- Equal numbers → `a - b = 0`
- In field arithmetic, `0` has no inverse. So we define `inv = 0` when `diff = 0` (arbitrary but safe choice), and `inv = 1/diff` otherwise.
- Formula: `out = 1 - diff*inv`
  - If `diff = 0` → `out = 1 - (0×0) = 1` (equal)
  - If `diff ≠ 0` → `diff × inv = 1` (true inverse property) → `out = 1 - 1 = 0` (not equal)
- **Safety constraint** `diff * out === 0`: because `inv` was assigned with `<--` (no automatic constraint), a dishonest prover could plug in a wrong `inv`. This constraint forces consistency: if `diff ≠ 0`, `out` MUST be `0`; if `diff = 0`, the constraint is trivially satisfied and the formula above already pins `out = 1`.

### Why circuits need tricks like this
Circuits can't use `if/else` — they're a fixed set of equations, not a running program. Every decision (equal or not, greater or smaller, etc.) must be expressed as pure algebra. These patterns (IsZero, comparators, range checks) are **known, reusable patterns** — already implemented in `circomlib`. You don't invent them fresh each time; you learn the pattern and reuse it (like `IsZero()` in circomlib, which this circuit mirrors).

---

## 2. Full Command Pipeline

### Step 1 — Compile
```
circom isEqual.circom --r1cs --wasm --sym
```
| Part | Meaning |
|---|---|
| `circom` | the compiler |
| `isEqual.circom` | input source file |
| `--r1cs` | output: constraint system in matrix form |
| `--wasm` | output: witness calculator program |
| `--sym` | output: debug symbol/label file |

**Outputs:**
- `isEqual.r1cs` — the circuit's constraints as matrices (A, B, C) such that `A·s × B·s = C·s`, where `s` is the vector of all signals (a, b, diff, inv, out, +constant wire). Used later in trusted setup.
- `isEqual.sym` — maps signal names to their position in `s`. Debug-only, not used in proving/verifying directly.
- `isEqual_js/isEqual.wasm` — a program that, given real numbers for `a` and `b`, computes every other signal (`diff`, `inv`, `out`) that satisfies the constraints. This is the "witness calculator."
- `isEqual_js/generate_witness.js` — helper script that runs the wasm: reads `input.json`, feeds it to the wasm, writes `witness.wtns`.
- `isEqual_js/witness_calculator.js` — internal library used by `generate_witness.js` (not called directly).

**Note (Windows-specific issue we hit):** circom writes output files to the *current working directory*, not to wherever the `.circom` file lives. Always `cd` into the circuit's folder before compiling, or use `-o <folder>`.

---

### Step 2 — Input file
`input.json`:
```json
{ "a": 5, "b": 10 }
```
This supplies the **private** values. (Circom defaults all inputs to private unless declared public in `component main {public [...]}`.)

---

### Step 3 — Generate witness
```
node isEqual_js/generate_witness.js isEqual_js/isEqual.wasm input.json witness.wtns
```
| Part | Meaning |
|---|---|
| `generate_witness.js` | the script doing the work |
| `isEqual_js/isEqual.wasm` | the compiled calculator |
| `input.json` | actual secret inputs |
| `witness.wtns` | **output**: every signal's calculated value |

**What happens under the hood:** the script loads `input.json` → feeds `a`, `b` into the wasm → wasm runs the circuit's logic (`diff = a-b`, `inv = ...`, `out = 1-diff*inv`) → all resulting values (a, b, diff, inv, out, constant wire) are serialized into `witness.wtns`.

⚠️ **Important lesson learned:** if you change `input.json`, you MUST regenerate the witness before proving again — otherwise you're proving the *old* values. (We hit this bug directly: changed `b` to `10` but reused an old witness, and `public.json` still showed the old result until we regenerated it.)

`witness.wtns` is **not private/secure** — it's plain calculated data. Privacy only comes in at the proving step.

---

### Step 4 — Trusted Setup, Phase 1 (Powers of Tau) — generic, reusable

This phase is **not tied to any specific circuit** — reused from Day 1 (`pot12_final.ptau`), just copied into this folder.

```
snarkjs powersoftau new bn128 12 pot12_0000.ptau -v
snarkjs powersoftau contribute pot12_0000.ptau pot12_0001.ptau --name="..." -v
snarkjs powersoftau prepare phase2 pot12_0001.ptau pot12_final.ptau -v
```
| Part | Meaning |
|---|---|
| `bn128` | the elliptic curve used |
| `12` | supports circuits up to 2^12 = 4096 constraints |
| `new` | creates a basic, non-random structure (unsafe alone — fully predictable) |
| `contribute` | mixes in a secret random number (from typed entropy), transforms the structure, then the secret is discarded — never stored |
| `prepare phase2` | converts the raw output into the format Phase 2 tools need (internally uses an FFT — a format-conversion algorithm, not new randomness) |

**Theory — what's actually being built:** A secret number `tau (τ)` is chosen (via the contributions). Its powers (τ¹, τ², τ³, ...) are computed and encoded as points on an elliptic curve. This is pure "raw cryptographic material" — generic, not yet linked to any circuit's logic.

**Why multiple contributors matter (real-world ceremonies):** Security depends on *at least one* contributor honestly discarding their secret number. This is "n-of-n trust" — you don't need to trust everyone, just that one participant out of many was honest. That's why real ceremonies involve hundreds/thousands of contributors. We did just one contribution ourselves — fine for learning, not for production.

**Reuse rule:** Phase 1 output is generic — the SAME `pot12_final.ptau` can be reused for any circuit as long as its constraint count fits the size limit. No need to redo Phase 1 per circuit (we reused Day 1's file here).

---

### Step 5 — Trusted Setup, Phase 2 (Groth16 setup) — circuit-specific

```
snarkjs groth16 setup isEqual.r1cs pot12_final.ptau isEqual_0000.zkey
```
| Part | Meaning |
|---|---|
| `isEqual.r1cs` | this circuit's constraints (matrices A, B, C) |
| `pot12_final.ptau` | the generic Phase 1 material |
| `isEqual_0000.zkey` | **output**: proving key material specific to this circuit |

**What happens under the hood:** the R1CS matrices are combined (multiplied/combined) with the generic elliptic curve points from Phase 1. The generic "raw material" now permanently encodes this circuit's specific structure — no longer reusable for a different circuit.

A **circuit hash** is printed — a unique fingerprint of this exact circuit. If even one constraint changes, this hash changes completely.

```
snarkjs zkey contribute isEqual_0000.zkey isEqual_final.zkey --name="1st Contributor" -v
```
Adds another random contribution (same "toxic waste" security logic as Phase 1) directly to the circuit-specific key, for extra security.

```
snarkjs zkey export verificationkey isEqual_final.zkey verification_key.json
```
| Part | Meaning |
|---|---|
| `isEqual_final.zkey` | full key material (large file) |
| `verification_key.json` | **output**: small, public-shareable extract |

**What "export" actually does:** the zkey already contains both proving-related and verification-related elliptic curve points bundled together. This command just extracts the small verification-only portion into a clean JSON — no new computation, just extraction/copying (like unzipping one folder from a larger archive).

### What proving key & verification key actually *are*
Both are **collections of points on an elliptic curve** (not hashes, not simple numbers). 
- **Proving key**: a large set of points encoding the circuit's full structure — combined with witness values (via elliptic curve scalar multiplication + point addition) to produce a proof.
- **Verification key**: a much smaller set of points, used to run a "pairing check" equation against a submitted proof.

---

### Step 6 — Generate the proof
```
snarkjs groth16 prove isEqual_final.zkey witness.wtns proof.json public.json
```
| Part | Meaning |
|---|---|
| `isEqual_final.zkey` | proving key |
| `witness.wtns` | actual calculated signal values |
| `proof.json` | **output**: the cryptographic proof (a small set of curve points, ~3 points in Groth16) |
| `public.json` | **output**: only the public signals (here: `out`) |

**Under the hood:** each witness value is combined with its corresponding proving-key point via elliptic curve scalar multiplication, then all results are summed (point addition) → produces the compact proof. Secret values (`a`, `b`, `diff`, `inv`) are never embedded recoverably in the proof — this is the "zero-knowledge" part.

---

### Step 7 — Verify
```
snarkjs groth16 verify verification_key.json public.json proof.json
```
| Part | Meaning |
|---|---|
| `verification_key.json` | small public key |
| `public.json` | public output (`out`) |
| `proof.json` | the proof to check |

**Under the hood:** a mathematical **pairing check** equation is run using these three inputs. If it holds, the proof is genuine (`OK!`). No secret values are ever seen.

### Critical clarification: what "OK!" actually means
`OK!` does **NOT** mean "a equals b." It means: **"this proof was honestly generated from a witness that satisfies all circuit constraints"** — regardless of whether the answer is `out=1` or `out=0`.

The circuit's job is only to *correctly report* whether a=b (1) or a≠b (0). Both outcomes are "valid" computations, so both verify as `OK!`. Verification checks **integrity of computation**, not a specific desired outcome. A proof would only fail verification if the witness were tampered with (e.g., forcing `out=1` when the constraints don't actually support it).

---

## 3. Soundness — could a wrong witness accidentally produce a valid proof?

Theoretically not impossible, but the probability is **negligible** (astronomically small, e.g. ~1 in 2^128) — grounded in hard mathematical problems on elliptic curves (like the discrete logarithm problem). The specific pairing-check equation is so tightly tied to the actual witness values that a mismatched witness will not satisfy it except by a chance so small it's treated as zero in practical security terms.

---

## 4. Full File Flow Diagram

```
isEqual.circom
     │ circom compile (--r1cs --wasm --sym)
     ▼
isEqual.r1cs        isEqual_js/isEqual.wasm       isEqual.sym
     │                     │ (+ input.json)              (debug only)
     │                     ▼
     │              witness.wtns
     │                     │
     ▼                     │
pot12_final.ptau           │
     │ (Phase 1, reused from Day 1)
     ▼
groth16 setup ──► isEqual_0000.zkey
     │ zkey contribute
     ▼
isEqual_final.zkey ──► export verificationkey ──► verification_key.json
     │                                                    │
     └──────────────┐                                     │
                     ▼                                     │
     (isEqual_final.zkey + witness.wtns)                   │
                     │ groth16 prove                       │
                     ▼                                     │
          proof.json + public.json                         │
                     │                                     │
                     └──────────────► groth16 verify ◄──────┘
                                            │
                                           OK!
```

---

## 5. Tests Performed

| a | b | Expected out | Got out | Verify |
|---|---|---|---|---|
| 5 | 5 | 1 (equal) | 1 | OK! |
| 5 | 10 | 0 (not equal) | 0 | OK! |

Both directions of the circuit's logic confirmed correct.

---

## 6. Key Takeaways / Lessons Learned Today

1. Circuits express logic as **pure algebra** — no if/else, so tricks like the IsZero pattern are needed for conditional-style checks.
2. `<==` assigns **and** constrains; `<--` only assigns (needs a manual `===` safety check afterward) — this is a common security pitfall if forgotten.
3. **Phase 1 (Powers of Tau)** is generic and reusable across circuits; **Phase 2 (zkey)** is circuit-specific and must be redone for every new circuit.
4. Proving key & verification key are elliptic curve point sets, not hashes or plain numbers.
5. **Always regenerate the witness after changing inputs** — a stale witness silently produces stale (wrong) results.
6. `OK!` on verify = "computation was honest," not "the answer was yes." Check `public.json` for the actual answer.
7. Windows: circom writes outputs to the current directory — `cd` into the circuit folder before compiling; PowerShell may block `snarkjs.ps1` (`Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` fixes this, or just use `cmd`).

---

## 7. Next Steps (Project Direction)

Same exact pipeline will be reused for:
1. **Poseidon hash circuit** — for identity commitment (`commitment = Poseidon(secret)`), using circomlib's ready-made `Poseidon()` template (not derived from scratch — reused like `IsZero()`).
2. **Merkle tree membership circuit** — proving a commitment is a leaf in a tree, without revealing which leaf or the secret.
3. **Nullifier circuit** — preventing double-use of an identity without linking back to it.
