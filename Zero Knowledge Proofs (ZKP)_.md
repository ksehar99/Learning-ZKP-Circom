# Zero Knowledge Proofs (ZKP):

# Basic Understanding:

* CIRCOM language used to code ZK-circuits of SNARK, similar in syntax as Cpp or JS, we code it like this (out \<== in1 \* in2; )   
  * Easy language can be learnt in 2/3 days  
  * Only use for designing circuits(math architecture)   
  * It can’t generate or verify proof by itself  
* Watch youtube videos for (`Circom tutorial for beginners` ) then do work…   
* Two main things  
  * Proof generation (Snark js \- heavy math) \- user of the system generate it  
  * Proof verification (math check \- if proof.json \== SC data)- deployed SC will verify it  
* [Snark.js](http://Snark.js) take that circuit design and do actual cryptography  
1. **Start trusted setup** – groth16 require cryptographic keys (Proving key aur Verification key ) – commands are in sanrk js  
2. **Generate Proof:** connect/calculate/multiply.. User input to circuit and make a file prooj.json  
3.  Already give a verifier.sol \- no need to writesolidity complex code for verification..   
* For Blockchain we will be needed to see gas efficient approaches   
  * SNARK is more gas efficient then STARK  
  * Best SNARK algo is Groth16  
  * Limitation of SNARK: required Trusted setup  
* Currently project is talking about a single user entry – ZK-Gate system but if we move towards ZK-Blockchain there is a single proof of  multiple entries \- but it will need the GPUS and FPGAs  
* Cairo is the most used language for STARKS \- complete general purpose language  
* Noir is the easiest one it gives the opportunity to write code once and then use any of the network like SNARK or STARK on it..

# CPU-FPGA Coordination Delay:

## ZKP on hardware approach:

* For multiplication if we send the number on fpga from computer then send back the result on computer – it will add alot of delay (UART/SPI overhead)  
* For this we can use batch processing technique also called Coarse-Grained Acceleration  (multiple numbers send together to FPGA and it will process them parallely)

## ZKP on Computer Approach

* If we use PCIe or high speed DMA controller instead or UART, can significantly reduce the time delay

# Full zk-SNARK on FPGA 

* ### **Math in verilog:** 

  * Convert groth16 prover code in verilog, means MSM (Multi-Scalar Multiplication) aur NTT (Number Theoretic Transform) algos state machine will  have to be written in verilog

* ### **Data Storage:**

  * To Store SNARK verification/ proving keys(large in size), FPGA need to be connected with the External DDR RAM  
  * Will need a FPGA with specific DDR3 or DDR4 chip on it.. \- along with it Verilog mein MIG block lgana hoga

# Full zk-STARK on FPGA (The Practical Way) 

* **Execution Trace:** Table created in FPGA internal memory for storing data of each step  
* **Hashing Engine (The core):** 4 or 8 parallel SHA cores, these cores will take the traces nd made the merkle tree   
* STARK only contains hashes..

# Zk-Rollups:

* Take rolls of transactions make one proof and send to ethereum..   
* Layer 2 application  
* Staknet is Layer 2 zk-rollup network use stark proofs and based on Ethereum chian  
* What we are currently working on is.. Single-Application ZK-Rollup Architecture \- but it will be layer 1 network  
* Snark js etc directly supports layer 1, is stage pr layer 2 pr jane se software system complex hoga

# Practical Approach

* Called as SNARK-friendly-STARK or STARK prover with SNARK wrapper   
* FPGA will generate STARK proof (large in size)  
* PC pr CIRCOM/SNARK jS ka circuit banega jo is large proof ko compress kre  
* Then smaller snark proof BLockhian pr deploy hoa.. Gas efficient  
* It is  a real world approach used by polygon zero, bujoom(zksync)  
* It will make a proof of a proof – also called recursive zero knowledge proof