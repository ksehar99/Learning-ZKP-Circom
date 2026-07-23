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
    signal count[n+1];

    count[0] <== 0;

    for (var i = 0; i < n; i++) {
        diff[i] <== arr[i] - target;
        inv[i] <-- diff[i] != 0 ? 1/diff[i] : 0;
        isMatch[i] <== 1 - diff[i]*inv[i];
        diff[i] * isMatch[i] === 0;

        count[i+1] <== count[i] + isMatch[i];
    }

    matchCount <== count[n];   // NAYA: seedha count assign kar do

    component check = LessEqThan(8);
    check.in[0] <== count[n];
    check.in[1] <== maxAllowed;
    withinLimit <== check.out;
}

component main = CountMatches(5, 2);