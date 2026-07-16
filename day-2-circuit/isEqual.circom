pragma circom 2.0.0;

template IsEqual(){
    signal input a;
    signal input b;
    signal output out;

    signal diff;
    signal inv;

    diff <== a - b;
    inv <-- diff != 0 ? 1 / diff : 0;

    out <== 1 - diff*inv;

    diff * out === 0; // safety check
} 

component main = IsEqual();