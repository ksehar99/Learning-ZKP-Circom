# ZKP / Circom / SnarkJS — Day 1 Notes
**Topic:** Multiplier circuit — full Groth16 pipeline (compile → witness → proof → verify)

---

## 1. Core Idea (yaad rakhne wali ek line)

Circom mein code "run" nahi hota — tum bas equations (constraints) define karte ho jo secret aur public numbers ke beech relationship batate hain. Phir prove karte ho "mujhe aise numbers pata hain jo ye equations satisfy karte hain" — bina wo numbers reveal kiye.

---

## 2. Tools Installed

| Tool | Version | Kaam |
|---|---|---|
| Node.js | v24.17.0 | JS runtime |
| circom | 2.2.3 | Circuit compiler |
| snarkjs | 0.7.6 | Proof system (setup, prove, verify) |

⚠️ Note: circom Windows pe npm se install nahi hota properly — GitHub release se `.exe` download karke PATH mein manually add kiya (System Environment Variables → User Path → New).

---

## 3. Circuit Code (`multiplier.circom`)

```circom
pragma circom 2.0.0;

template Multiplier() {
    signal input a;
    signal input b;
    signal output c;

    c <== a * b;
}

component main = Multiplier();
```

### Syntax breakdown
- `pragma circom 2.0.0;` → version declaration, sirf formality, koi logic nahi.
- `template` → function jaisa — ek blueprint/reusable logic block.
- `signal` → circom ka "variable", lekin ek baar assign hone ke baad **change nahi ho sakta** (wire jaisa).
  - `signal input` → circuit ke bahar se aane wali value.
  - `signal output` → circuit se bahar jaane wali value.
- `<==` → **do kaam ek sath**: value assign bhi karta hai AUR wo constraint bhi permanently lock karta hai (proof ke waqt yehi check hota hai).
- `<--` → sirf assign karta hai, constraint nahi banata (advanced cases mein use hota hai, manually `===` ke saath).
- `===` → sirf constraint banata hai, assign nahi karta.
- `component main = Multiplier();` → template ko "call" karna, jaise `main()` function — har circuit mein sirf ek hota hai.

### Public vs Private input
- **Private input** → sirf prover ko pata hota hai (default in circom).
- **Public input/output** → verifier ko bhi pata hota hai, proof check karte waqt use hota hai.
- Is example mein: `a`, `b` = private, `c` = public output.

### Hidden constant wire
- Circuit equations linear-algebra (matrix) form mein represent hoti hain. Constants (jaise `+5`) ko represent karne ke liye system ek fixed wire rakhta hai jiski value hamesha `1` hoti hai. Purely internal, ignore kar sakte ho.

---

## 4. Full Pipeline — Commands Used

### Step 1 — Compile circuit
```
circom multiplier.circom --r1cs --wasm --sym
```
Output: `multiplier.r1cs` (constraint system), `multiplier_js/multiplier.wasm` (witness calculator), `multiplier.sym` (debug labels).

### Step 2 — Input file
`input.json`:
```json
{ "a": 3, "b": 4 }
```

### Step 3 — Generate witness
```
node multiplier_js/generate_witness.js multiplier_js/multiplier.wasm input.json witness.wtns
```
Witness = saari signals ki calculated values (a=3, b=4, c=12, + constant wire).

### Step 4 — Powers of Tau (Phase 1 — generic, reusable for any circuit up to size limit)
```
snarkjs powersoftau new bn128 12 pot12_0000.ptau -v
snarkjs powersoftau contribute pot12_0000.ptau pot12_0001.ptau --name="First contribution" -v
snarkjs powersoftau prepare phase2 pot12_0001.ptau pot12_final.ptau -v
```

### Step 5 — Circuit-specific setup (Phase 2 — Groth16)
```
snarkjs groth16 setup multiplier.r1cs pot12_final.ptau multiplier_0000.zkey
snarkjs zkey contribute multiplier_0000.zkey multiplier_final.zkey --name="1st Contributor" -v
snarkjs zkey export verificationkey multiplier_final.zkey verification_key.json
```
Output: `multiplier_final.zkey` (proving key), `verification_key.json` (verification key).

### Step 6 — Generate proof
```
snarkjs groth16 prove multiplier_final.zkey witness.wtns proof.json public.json
```
Output: `proof.json` (the ZK proof), `public.json` (only public values — in our case just `["12"]`, NOT a or b).

### Step 7 — Verify proof
```
snarkjs groth16 verify verification_key.json public.json proof.json
```
Result: **OK!** ✅

---

## 5. Confirmed: Zero-Knowledge Worked

`public.json` content:
```json
["12"]
```
Verifier ko sirf `c = 12` dikha — `a` aur `b` (3, 4) kabhi reveal nahi hue. Proof ne sirf ye confirm kiya "prover ke paas valid a, b hain" — bina unhe batae.

---

## 6. Concept Map (poora flow)

```
Circuit (.circom)
   │  circom compile
   ▼
R1CS (.r1cs)  +  WASM calculator
   │
   ├── R1CS ──┐
   │          ▼
   │   Powers of Tau (.ptau) ──► Groth16 Setup ──► zkey (proving + verification key)
   │
   └── WASM + input.json ──► Witness (.wtns)

zkey + Witness ──► PROOF (proof.json + public.json)

Verification Key + public.json + proof.json ──► VERIFY ──► OK!
```

---

## 7. Next Steps (for identity project)

Same exact pipeline reuse hoga, bas circuit logic change hoga:
1. Poseidon hash circuit (identity commitment banane ke liye) — circomlib se
2. Merkle tree membership proof circuit (check karna ki commitment tree mein hai)
3. Nullifier circuit (double-use rokne ke liye, bina identity link kiye)

Recommended videos (for revision):
- "How to create Zero-Knowledge Proofs (ZKPs) using Circom and snark.js" — https://www.youtube.com/watch?v=ZuwUFN7m4AY
- Official circom tutorial (text): https://github.com/iden3/circom/blob/master/TUTORIAL.md
