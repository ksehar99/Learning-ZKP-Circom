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

    // If isLeft = 1: leaf goes left, sibling goes right
    // If isLeft = 0: sibling goes left, leaf goes right

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