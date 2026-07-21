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