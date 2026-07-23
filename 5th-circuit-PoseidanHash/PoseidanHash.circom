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