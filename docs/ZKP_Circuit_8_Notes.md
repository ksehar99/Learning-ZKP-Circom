# ZKP / Circom / SnarkJS — Day 8 Notes
**Topic:** Nullifier circuit — replay-protection without revealing identity

---

## 1. The Circuit (`nullifier.circom`)

```circom
pragma circom 2.0.0;

include "circomlib/circuits/poseidon.circom";

template Nullifier() {
    signal input secret;
    signal input attemptId;
    signal output nullifierHash;

    component hasher = Poseidon(2);
    hasher.inputs[0] <== secret;
    hasher.inputs[1] <== attemptId;

    nullifierHash <== hasher.out;
}

component main {public [attemptId]} = Nullifier();
```

Structurally identical to the Poseidon Commitment circuit (Circuit 5) — just `Poseidon(2)` instead of `Poseidon(1)`, hashing `secret` together with `attemptId`.

---

## 2. Purpose — Why a Nullifier is Needed at All

Merkle membership proof (Circuit 7) proves "this is a valid member of the authorized set," but on its own it does **not** stop someone from capturing a valid proof and resubmitting it later (a replay attack) — a proof, once valid, stays mathematically valid forever unless something else changes each time.

A nullifier adds a **one-time-use tag** to each authentication attempt: `nullifier = Poseidon(secret, attemptId)`. The backend checks whether this exact nullifier has been seen before; if yes, it rejects the attempt (replay), even if the underlying Merkle proof is otherwise perfectly valid.

Since Poseidon is deterministic, the *same* `(secret, attemptId)` pair always produces the *same* nullifier — but the nullifier reveals nothing about `secret` itself (one-way hash), so replay-protection is achieved without linking the attempt back to a specific identity.

---

## 3. Critical Design Decision: What Should `attemptId` Actually Be?

This was the key design discussion for this circuit — the choice of `attemptId` determines whether the system behaves correctly or malfunctions.

### Wrong approach considered and rejected: day-based context
Using something like `attemptId = "23-July-2026"` (one nullifier per day) was initially considered as "most secure." This is **incorrect for this project's requirements**: if a person enters the building, leaves for a break, and returns the same day, the second entry would produce the *same* nullifier as the first (same secret + same day), and the system would wrongly reject a completely legitimate second entry as "already used."

**Key insight:** "Most secure" does not mean "most restrictive." A nullifier scheme is only correctly designed if it blocks exactly the malicious case (replaying a captured proof) while still allowing every legitimate case (a real person authenticating multiple times a day). A day-level nullifier fails this — it blocks legitimate repeat entries, which is a malfunction, not security.

### Correct approach: per-attempt context
`attemptId` should be unique **per individual authentication attempt** — e.g., a precise timestamp (down to seconds/milliseconds) or a random nonce generated fresh by the backend every time the sensor triggers.

With this design:
- Every real entry attempt gets its own fresh `attemptId` → its own fresh nullifier → always allowed, no matter how many times a day a legitimate person enters.
- If an attacker captures a specific proof (tied to one specific `attemptId`) and resubmits *that exact proof* later, the nullifier will match one already marked "used" → rejected.
- Two different attempts by the same person (different `attemptId`s) produce completely unrelated nullifier values — so the system still cannot link multiple visits back to the same identity, preserving anonymity across attempts.

**General principle learned:** Replay-protection means *"this specific attempt/proof cannot be resubmitted,"* not *"this identity can only ever authenticate once."* The granularity of the context value (`attemptId`) is what defines the protection window — it should match the actual attack being defended against (proof replay), not be made arbitrarily broad (e.g., a full day) just because it seems "more restrictive = more secure."

---

## 4. Public vs Private Signals in This Circuit

| Signal | Private/Public | Why |
|---|---|---|
| `secret` | Private | Identity must never be revealed |
| `attemptId` | Public (`{public [attemptId]}`) | Backend needs to see it, to check against its database of "already-used" attempt IDs/nullifiers |
| `nullifierHash` (output) | Public (automatic) | Backend needs this value to store/check for replay |

Same pattern as Circuit 7's `root` — an *input* that needs to be public requires the explicit `{public [...]}` syntax, since inputs are private by default (unlike outputs, which are public by default).

---

## 5. Test Performed

`input.json`:
```json
{
    "secret": 12345,
    "attemptId": 20260723143507
}
```

Result (`public.json`):
```json
[
 "11248372273036396289287662637695357102261715091373297083312624853329638062207",
 "20260723143507"
]
```
First value = `nullifierHash` (what the backend would store/check), second = `attemptId` (echoed back publicly). Verify returned `OK!`.

---

## 6. Where This Fits in the Backend Flow (recap, not a circom task)

At verification time (recap from earlier architecture discussion):
1. Backend generates a fresh `attemptId` the moment the sensor triggers.
2. Circuit produces `nullifierHash` alongside the Merkle membership proof.
3. Backend checks its database: has this exact `nullifierHash` been seen before? (In practice this is nearly impossible by chance since `attemptId` is fresh each time — this check mainly guards against someone deliberately resubmitting an old, captured proof+nullifier pair.)
4. If new → allow access, mark `nullifierHash` as used. If already present → reject (replay attempt).

This database check itself is ordinary backend logic (not circom) — the circuit's only job is producing the deterministic, one-way `nullifierHash`.

---

## 7. Project Status — All Three Core Circuits Now Complete

1. ✅ **Poseidon Commitment** (Circuit 5) — `secret → commitment`, used at enrollment
2. ✅ **Merkle Membership Proof** (Circuit 7) — `leaf + path → isValid` (anonymous membership check)
3. ✅ **Nullifier** (Circuit 8) — `secret + attemptId → nullifierHash` (replay protection)

Together these three circuits form the complete cryptographic core of the FYP's identity-authentication system.

## 8. Next Steps
- Consider combining all three into a single end-to-end circuit matching the real system's exact verification call (one circuit that takes secret + Merkle path + root + attemptId, and outputs both `isValid` and `nullifierHash` together).
- Backend/enrollment-side work (tree building, attemptId generation, nullifier-database checks) — separate from circom, ordinary software engineering.
- FPGA-side hashing implementation (Verilog/VHDL) — separate hardware track.
