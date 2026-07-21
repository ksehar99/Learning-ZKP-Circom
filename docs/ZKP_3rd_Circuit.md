# ZKP / Circom / SnarkJS — Day 3 Notes
**Topic:** RangeChecker circuit — checking if a value lies within [min, max], using circomlib comparators

---

## 1. The Circuit (`rangeChecker.circom`)

```circom
pragma circom 2.0.0;

include "circomlib/circuits/comparators.circom";

template RangeChecker(n) {
    signal input value;
    signal input min;
    signal input max;
    signal output inRange;

    // Check value >= min
    component geq = GreaterEqThan(n);
    geq.in[0] <== value;
    geq.in[1] <== min;

    // Check value <= max
    component leq = LessEqThan(n);
    leq.in[0] <== value;
    leq.in[1] <== max;

    // AND logic: both must be true (1) for inRange to be 1
    inRange <== geq.out * leq.out;
}

component main = RangeChecker(32);
```

### Why this circuit
Real-world relevance to the FYP: a door-access system might only allow entry within a specific time window (e.g. office hours). This circuit is the reusable building block for "is this value within an allowed range" — directly applicable to time-window checks later.

### Key concepts used
- **Reusing circomlib templates** instead of deriving comparator logic from scratch (`GreaterEqThan`, `LessEqThan` — both internally use the same bit-decomposition trick discussed for `LessThan`).
- **AND logic via multiplication**: when two signals are strictly 0 or 1, multiplying them reproduces AND — `1×1=1`, `1×0=0`, `0×0=0`. This is a standard circom pattern for combining boolean-like signals, since circom has no native `&&` operator on signals.
- **Template parameter `n`**: same meaning as in `LessThan(n)` — specifies bit-width for the comparison, must respect the field-size safety margin (≤252 for BN128) discussed earlier.

---

## 2. Setting Up circomlib (npm install issues + fix)

### What went wrong
`npm install circomlib` reported success (`added 1 package`) but no `node_modules` folder was actually created in the circuit's directory — likely an npm/environment quirk on this machine. `-l node_modules` therefore failed with:
```
error[P1014]: The file circomlib/circuits/comparators.circom to be included has not been found
```

### The fix that worked — direct GitHub clone
```
git clone https://github.com/iden3/circomlib.git
```
This creates a `circomlib/` folder directly inside the circuit's working directory, containing all the library's `.circom` files (comparators, Poseidon, Merkle helpers, etc. — will be reused for future circuits too).

### Compiling with a local include path
```
circom rangeChecker.circom --r1cs --wasm --sym -l .
```
| Part | Meaning |
|---|---|
| `-l .` | tells circom to treat the current directory as the base path for resolving `include` statements — so `include "circomlib/circuits/comparators.circom"` resolves to `./circomlib/circuits/comparators.circom` |

**Takeaway:** If `npm install` behaves inconsistently on Windows, cloning circomlib directly from GitHub into the working folder is a reliable fallback.

---

## 3. Full Command Pipeline (same pattern as Day 1 & 2)

```
git clone https://github.com/iden3/circomlib.git

circom rangeChecker.circom --r1cs --wasm --sym -l .

node rangeChecker_js/generate_witness.js rangeChecker_js/rangeChecker.wasm input.json witness.wtns

# Powers of Tau — reused pot12_final.ptau from Day 1/2 (copied into this folder) instead of regenerating

snarkjs groth16 setup rangeChecker.r1cs pot12_final.ptau rangeChecker_0000.zkey
snarkjs zkey contribute rangeChecker_0000.zkey rangeChecker_final.zkey --name="1st Contributor" -v
snarkjs zkey export verificationkey rangeChecker_final.zkey verification_key.json

snarkjs groth16 prove rangeChecker_final.zkey witness.wtns proof.json public.json
snarkjs groth16 verify verification_key.json public.json proof.json
```

**Reminder (learned in Day 2, applies here too):** if `input.json` changes, `witness.wtns` must be regenerated before proving again, or the old result gets re-proved/re-verified silently.

---

## 4. Comparator Concepts Covered (from Circom101, before writing this circuit)

### `assert()` in circom
Not a runtime check like in normal programming — it's a **compile-time sanity check**. E.g. `assert(n <= 252)` inside `LessThan` ensures the bit-width parameter never gets large enough to cause field wrap-around during the comparison trick.

### Why comparisons need bit-decomposition tricks
Circom cannot use `<`, `>`, `&&`, `? :` directly on signals — circuits only understand pure algebra (`+`, `-`, `*` and combinations). Every comparison must be re-expressed as an equation. The general trick (used in `LessThan`):
1. Add a fixed offset (`1 << n`) to force the subtraction into a predictable range
2. Decompose the result into bits (`Num2Bits`)
3. Read the "overflow bit" to determine the answer

This produces a clean 0/1 signal without ever using `if/else`.

### `≥` and `≤` from `<`, using the "+1" trick
For integers only: `a ≥ b ⟺ b < a+1`. This lets `GreaterEqThan`/`LessEqThan` be built by reusing `LessThan` internally with an adjusted input, instead of writing new logic from scratch.

### Field arithmetic surprises
- `1/2` in circom does **not** equal `0.5` — circom has no decimals, only integers `0` to `p-1` (where `p` is the field's large prime, fixed by the chosen curve, e.g. BN128). Division means "modular inverse": the integer that, multiplied by the divisor, gives 1 modulo `p`. So `1/2 = (p+1)/2` — a huge number close to `p/2`.
- This underlies circuits like `Sign()`, which determines whether a field element is "conceptually positive" (closer to 0) or "conceptually negative" (closer to `p`, representing values like `p - x` for some negative `x`).
- `p` itself is never written explicitly in circom code — it's fixed by the curve (bn128) and applied automatically by the compiler to every `+`, `-`, `*`, `/` operation.

### `var` vs `signal`
- `signal` = actual circuit data, part of the witness, involved in the proof. Assigned once, immutable.
- `var` = a compile-time-only helper (like a normal loop counter or temporary calculation). Never appears in the witness or the proof. Used for things like `for (var i = 0; i < n; i++)`.
- Circom has no separate `int`/`float` types — `var` is always treated as a field element, used purely to control circuit construction at compile time.

### Loops in circom
`for` loops are **unrolled at compile time** — not a runtime loop. A `for (var i=0; i<254; i++)` produces 254 separate constraints in the compiled circuit, not a single reusable loop structure. This matters for circuit size/performance (more iterations = more constraints = bigger circuit).

### General philosophy reinforced
Circuit design patterns (IsZero, comparators, range-checks, AliasCheck) are **known, reusable, audited patterns** from circomlib — not something to derive from scratch each time. The skill is knowing the pattern exists and how to import/compose it, not re-deriving the underlying algebra.

---

## 5. Test Performed

`input.json`:
```json
{ "value": 50, "min": 10, "max": 100 }
```
Expected: `inRange = 1` (50 is between 10 and 100) — confirmed via `public.json` after verify returned `OK!`.

---

## 6. Next Steps

- (Optional) One more small practice circuit combining `var` + array + loop explicitly (e.g. sum of array elements, or find max) if more repetition is wanted before moving on.
- **Poseidon hash circuit** — next major milestone, directly needed for identity commitment (`commitment = Poseidon(secret)`).
- **Merkle Tree membership circuit** — using Poseidon, the core circuit for the FYP's identity verification.
- **Nullifier circuit** — small addition for replay protection.