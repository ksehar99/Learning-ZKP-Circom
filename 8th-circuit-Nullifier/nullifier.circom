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