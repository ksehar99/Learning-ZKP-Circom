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
    signal output computedRoot;

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
    computedRoot <== levelHashes[depth];

}


component main {public [root]} = MerkleProof(3);