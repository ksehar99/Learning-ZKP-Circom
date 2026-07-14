pragma circom 2.0.0;

template Multiplier() {
    signal input a;        // value can b assigned only once to signal, cant change
    signal input b;        // input are he values came from outside of the circuit
    signal output c;       // vlues that are produced by the circuit

    c <== a * b;           // doing 2 things, 1.assigning ab to c, 2.defining the constraint
}
// <-- only assign value
// === sirf constraint check krta

component main = Multiplier();

// public input verifier or prover dono ko pta hota hai.. 
// private input sirf prover ko.. verifier ko sirf ye pta chlta hai k prover k pass koi valid value things
// Hidden constant wire: so that, when constant is required in equation, we'll write 1*5... b/c iski value always 1 hoti.. so it is simply a mathematcall need, nothing else
