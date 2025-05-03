/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  sys_defs.svh                                        //
//                                                                     //
//  Description :  This file defines macros and data structures used   //
//                 throughout the processor.                           //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __SYS_DEFS_SVH__
`define __SYS_DEFS_SVH__

// all files should `include "sys_defs.svh" to at least define the timescale
`timescale 1ns/100ps

///////////////////////////////////
// ---- Starting Parameters ---- //
///////////////////////////////////

// some starting parameters that you should set
// this is *your* processor, you decide these values (try analyzing which is best!)

// superscalar width
// `define N 3
`define FETCH_WIDTH 4
`define DISPATCH_WIDTH 3
`define CDB_WIDTH 3
`define RETIRE_WIDTH 3

`define ICACHE_PF_BUFFER_SZ 4
`define INST_BUFFER_SZ 16
`define RS_SZ 16
// EBR
`define BR_STK_SZ 4 // branch stack size`define 
`define ROB_SIZE 32

// functional units (you should decide if you want more or fewer types of FUs)
`define NUM_FU_ALU `CDB_WIDTH
`define NUM_FU_MULT 1
`define NUM_FU (`NUM_FU_ALU+`NUM_FU_MULT+`NUM_FU_BR + `NUM_FU_LOAD_IN+`NUM_FU_STORE) // 2 ALU, 1 MULT, 1 LOAD, 1 STORE, 1 BRANCH
// `define NUM_FU_LOAD 1
`define NUM_FU_BR 1

`define NUM_FU_LOAD_IN 1
`define NUM_FU_LOAD_OUT 4
`define NUM_FU_STORE 1
`define NUM_FU_OUT (`NUM_FU_ALU+`NUM_FU_MULT+`NUM_FU_BR + `NUM_FU_LOAD_OUT+`NUM_FU_STORE)

// number of mult stages (2, 4) (you likely don't need 8)
`define MULT_STAGES 4

`define MSHR_SIZE 4 // number of outstanding memory requests

`define AR_CNT 32
`define PR_CNT 64
// each fu 2 ports, N ports for cdb retire reading data
`define PRF_READ_PORT_CNT `NUM_FU * 2 + `RETIRE_WIDTH
`define PRF_WRITE_PORT_CNT `CDB_WIDTH

// larger size requires longer time to launch
`define BHR_SIZE 8
// BTB size should be relatively small,
// as each entries stores an address...
`define BTB_BIT_NUM 8
`define RAS_SIZE 8

// tag (physical register)
typedef logic [$clog2(`PR_CNT)-1:0] TAG;
typedef struct packed {
    TAG tag;
    logic ready;
} TAG_PLUS;


typedef logic [`BR_STK_SZ-1:0] B_IDX;
typedef logic [3:0] BMASK;
typedef enum logic[2:0] {
    BR_RES_INVALID,
    BR_RES_HIT,
    BR_RES_MIS
} BR_RES_STATE;

///////////////////////////////
// ---- Basic Constants ---- //
///////////////////////////////

// NOTE: the global CLOCK_PERIOD is defined in the Makefile

// useful boolean single-bit definitions
`define FALSE 1'h0
`define TRUE  1'h1

// word and register sizes
typedef logic [31:0] ADDR;
typedef logic [31:0] DATA;
typedef logic [4:0] REG_IDX;


`define STATION_SIZE 4
`define SQ_SZ        4
`define SQ_IDX_WIDTH $clog2(`SQ_SZ)
// lsq station size
typedef logic [`SQ_IDX_WIDTH-1:0] SQ_IDX;
// the zero register
// In RISC-V, any read of this register returns zero and any writes are thrown away
`define ZERO_REG 5'd0

// Basic NOP instruction. Allows pipline registers to clearly be reset with
// an instruction that does nothing instead of Zero which is really an ADDI x0, x0, 0
`define NOP 32'h00000013

//////////////////////////////////
// ---- Memory Definitions ---- //
//////////////////////////////////

// Cache mode removes the byte-level interface from memory, so it always returns
// a double word. The original processor won't work with this defined. Your new
// processor will have to account for this effect on mem.
// Notably, you can no longer write data without first reading.
// TODO: uncomment this line once you've implemented your cache
`define CACHE_MODE

// you are not allowed to change this definition for your final processor
// the project 3 processor has a massive boost in performance just from having no mem latency
// see if you can beat it's CPI in project 4 even with a 100ns latency!
//`define MEM_LATENCY_IN_CYCLES  0
`define MEM_LATENCY_IN_CYCLES (100.0/`CLOCK_PERIOD+0.49999)
// the 0.49999 is to force ceiling(100/period). The default behavior for
// float to integer conversion is rounding to nearest

// memory tags represent a unique id for outstanding mem transactions
// 0 is a sentinel value and is not a valid tag
`define NUM_MEM_TAGS 15
typedef logic [3:0] MEM_TAG;

// icache definitions
`define ICACHE_LINES 32
`define ICACHE_LINE_BITS $clog2(`ICACHE_LINES)

`define ICACHE_READ_PORTS `FETCH_WIDTH / 2
`define ICACHE_INDEX_BITS `ICACHE_LINE_BITS
// using 16 bits of the address for cache: 
// 8(tag) + 5(index, 32 lines) + 3(offset, 8 bytes per line)
`define ICACHE_TAG_BITS 16 - 3 - `ICACHE_LINE_BITS

// dcache definitions
`define DCACHE_LINES 32
`define DCACHE_LINE_BITS $clog2(`DCACHE_LINES)
`define DCACHE_INDEX_BITS `DCACHE_LINE_BITS
`define DCACHE_TAG_BITS 16 - 3 - `DCACHE_LINE_BITS

`define MSHR_SIZE 4

`define MEM_SIZE_IN_BYTES (64*1024)
`define MEM_64BIT_LINES   (`MEM_SIZE_IN_BYTES/8)

// A memory or cache block
typedef union packed {
    logic [7:0][7:0]  byte_level;
    logic [3:0][15:0] half_level;
    logic [1:0][31:0] word_level;
    logic      [63:0] dbbl_level;
} MEM_BLOCK;

typedef union packed{
    logic [7:0]         byte_level;
    logic [3:0][1:0]    half_level;
    logic [1:0][3:0]    word_level;
    // logic [7:0]         dbbl_level;
}LOAD_MASK;

typedef enum logic [1:0] {
    BYTE   = 2'h0,
    HALF   = 2'h1,
    WORD   = 2'h2,
    DOUBLE = 2'h3
} MEM_SIZE;

// Memory bus commands
typedef enum logic [1:0] {
    MEM_NONE   = 2'h0,
    MEM_LOAD   = 2'h1,
    MEM_STORE  = 2'h2
} MEM_COMMAND;

// icache tag struct
typedef struct packed {
    logic [`ICACHE_TAG_BITS-1:0]   tag;
    logic                          valid;
} ICACHE_TAG;

typedef enum logic [1:0] {
    DCACHE_LSQ_INVALID,
    DCACHE_LSQ_PENDING,
    DCACHE_LSQ_HIT
} DCACHE_LSQ_STATE;

typedef struct packed {
    logic [`DCACHE_TAG_BITS-1:0]   tag;
    logic                          valid;
    logic                          dirty;
} DCACHE_TAG;

typedef enum logic [1:0] {
    MSHR_EMPTY,
    MSHR_WANT_REQ,
    MSHR_SENT_REQ,
    MSHR_HAS_DATA
} MSHR_STATE;

typedef struct packed {
    MSHR_STATE state;
    MEM_TAG transac_tag;
    // aligned addr
    ADDR addr;
    // only masked bits are valid
    logic [63:0] data_mask;
    MEM_BLOCK data;
    logic dirty;
} MSHR_ENTRY;

///////////////////////////////
// ---- Exception Codes ---- //
///////////////////////////////

/**
 * Exception codes for when something goes wrong in the processor.
 * Note that we use HALTED_ON_WFI to signify the end of computation.
 * It's original meaning is to 'Wait For an Interrupt', but we generally
 * ignore interrupts in 470
 *
 * This mostly follows the RISC-V Privileged spec
 * except a few add-ons for our infrastructure
 * The majority of them won't be used, but it's good to know what they are
 */

typedef enum logic [3:0] {
    INST_ADDR_MISALIGN  = 4'h0,
    INST_ACCESS_FAULT   = 4'h1,
    ILLEGAL_INST        = 4'h2,
    BREAKPOINT          = 4'h3,
    LOAD_ADDR_MISALIGN  = 4'h4,
    LOAD_ACCESS_FAULT   = 4'h5,
    STORE_ADDR_MISALIGN = 4'h6,
    STORE_ACCESS_FAULT  = 4'h7,
    ECALL_U_MODE        = 4'h8,
    ECALL_S_MODE        = 4'h9,
    NO_ERROR            = 4'ha, // a reserved code that we use to signal no errors
    ECALL_M_MODE        = 4'hb,
    INST_PAGE_FAULT     = 4'hc,
    LOAD_PAGE_FAULT     = 4'hd,
    HALTED_ON_WFI       = 4'he, // 'Wait For Interrupt'. In 470, signifies the end of computation
    STORE_PAGE_FAULT    = 4'hf
} EXCEPTION_CODE;

///////////////////////////////////
// ---- Instruction Typedef ---- //
///////////////////////////////////

// from the RISC-V ISA spec
typedef union packed {
    logic [31:0] inst;
    struct packed {
        logic [6:0] funct7;
        logic [4:0] rs2; // source register 2
        logic [4:0] rs1; // source register 1
        logic [2:0] funct3;
        logic [4:0] rd; // destination register
        logic [6:0] opcode;
    } r; // register-to-register instructions
    struct packed {
        logic [11:0] imm; // immediate value for calculating address
        logic [4:0]  rs1; // source register 1 (used as address base)
        logic [2:0]  funct3;
        logic [4:0]  rd;  // destination register
        logic [6:0]  opcode;
    } i; // immediate or load instructions
    struct packed {
        logic [6:0] off; // offset[11:5] for calculating address
        logic [4:0] rs2; // source register 2
        logic [4:0] rs1; // source register 1 (used as address base)
        logic [2:0] funct3;
        logic [4:0] set; // offset[4:0] for calculating address
        logic [6:0] opcode;
    } s; // store instructions
    struct packed {
        logic       of;  // offset[12]
        logic [5:0] s;   // offset[10:5]
        logic [4:0] rs2; // source register 2
        logic [4:0] rs1; // source register 1
        logic [2:0] funct3;
        logic [3:0] et;  // offset[4:1]
        logic       f;   // offset[11]
        logic [6:0] opcode;
    } b; // branch instructions
    struct packed {
        logic [19:0] imm; // immediate value
        logic [4:0]  rd; // destination register
        logic [6:0]  opcode;
    } u; // upper-immediate instructions
    struct packed {
        logic       of; // offset[20]
        logic [9:0] et; // offset[10:1]
        logic       s;  // offset[11]
        logic [7:0] f;  // offset[19:12]
        logic [4:0] rd; // destination register
        logic [6:0] opcode;
    } j;  // jump instructions

// extensions for other instruction types
`ifdef ATOMIC_EXT
    struct packed {
        logic [4:0] funct5;
        logic       aq;
        logic       rl;
        logic [4:0] rs2;
        logic [4:0] rs1;
        logic [2:0] funct3;
        logic [4:0] rd;
        logic [6:0] opcode;
    } a; // atomic instructions
`endif
`ifdef SYSTEM_EXT
    struct packed {
        logic [11:0] csr;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [4:0]  rd;
        logic [6:0]  opcode;
    } sys; // system call instructions
`endif

} INST; // instruction typedef, this should cover all types of instructions

////////////////////////////////////////
// ---- Datapath Control Signals ---- //
////////////////////////////////////////

// ALU opA input mux selects
typedef enum logic [1:0] {
    OPA_IS_RS1  = 2'h0,
    OPA_IS_NPC  = 2'h1,
    OPA_IS_PC   = 2'h2,
    OPA_IS_ZERO = 2'h3
} ALU_OPA_SELECT;

// ALU opB input mux selects
typedef enum logic [3:0] {
    OPB_IS_RS2    = 4'h0,
    OPB_IS_I_IMM  = 4'h1,
    OPB_IS_S_IMM  = 4'h2,
    OPB_IS_B_IMM  = 4'h3,
    OPB_IS_U_IMM  = 4'h4,
    OPB_IS_J_IMM  = 4'h5
} ALU_OPB_SELECT;

// ALU function code
typedef enum logic [3:0] {
    ALU_ADD     = 4'h0,
    ALU_SUB     = 4'h1,
    ALU_SLT     = 4'h2,
    ALU_SLTU    = 4'h3,
    ALU_AND     = 4'h4,
    ALU_OR      = 4'h5,
    ALU_XOR     = 4'h6,
    ALU_SLL     = 4'h7,
    ALU_SRL     = 4'h8,
    ALU_SRA     = 4'h9
} ALU_FUNC;

// MULT funct3 code
// we don't include division or rem options
typedef enum logic [2:0] {
    M_MUL,
    M_MULH,
    M_MULHSU,
    M_MULHU
} MULT_FUNC;

////////////////////////////////
// ---- Datapath Packets ---- //
////////////////////////////////

/**
 * Packets are used to move many variables between modules with
 * just one datatype, but can be cumbersome in some circumstances.
 *
 * Define new ones in project 4 at your own discretion
 */

/**
 * IF_ID Packet:
 * Data exchanged from the IF to the ID stage
 */
typedef struct packed {
    INST  inst;
    ADDR  PC;
    ADDR  NPC; // PC + 4
    logic valid;
} IF_ID_PACKET;

/**
 * ID_EX Packet:
 * Data exchanged from the ID to the EX stage
 */
typedef struct packed {
    INST inst;
    ADDR PC;
    ADDR NPC; // PC + 4

    DATA rs1_value; // reg A value
    DATA rs2_value; // reg B value

    ALU_OPA_SELECT opa_select; // ALU opa mux select (ALU_OPA_xxx *)
    ALU_OPB_SELECT opb_select; // ALU opb mux select (ALU_OPB_xxx *)

    REG_IDX  dest_reg_idx;  // destination (writeback) register index
    ALU_FUNC alu_func;      // ALU function select (ALU_xxx *)
    logic    mult;          // Is inst a multiply instruction?
    logic    rd_mem;        // Does inst read memory?
    logic    wr_mem;        // Does inst write memory?
    logic    cond_branch;   // Is inst a conditional branch?
    logic    uncond_branch; // Is inst an unconditional branch?
    logic    halt;          // Is this a halt?
    logic    illegal;       // Is this instruction illegal?
    logic    csr_op;        // Is this a CSR operation? (we only used this as a cheap way to get return code)

    logic    valid;
} ID_EX_PACKET;

/**
 * EX_MEM Packet:
 * Data exchanged from the EX to the MEM stage
 */
typedef struct packed {
    DATA alu_result;
    ADDR NPC;

    logic    take_branch; // Is this a taken branch?
    // Pass-through from decode stage
    DATA     rs2_value;
    logic    rd_mem;
    logic    wr_mem;
    REG_IDX  dest_reg_idx;
    logic    halt;
    logic    illegal;
    logic    csr_op;
    logic    rd_unsigned; // Whether proc2Dmem_data is signed or unsigned
    MEM_SIZE mem_size;
    logic    valid;
} EX_MEM_PACKET;

/**
 * MEM_WB Packet:
 * Data exchanged from the MEM to the WB stage
 *
 * Does not include data sent from the MEM stage to memory
 */
typedef struct packed {
    DATA    result;
    ADDR    NPC;
    REG_IDX dest_reg_idx; // writeback destination (ZERO_REG if no writeback)
    logic   take_branch;
    logic   halt;    // not used by wb stage
    logic   illegal; // not used by wb stage
    logic   valid;
} MEM_WB_PACKET;

/**
 * Commit Packet:
 * This is an output of the processor and used in the testbench for counting
 * committed instructions
 *
 * It also acts as a "WB_PACKET", and can be reused in the final project with
 * some slight changes
 */
typedef struct packed {
    ADDR    NPC;
    DATA    data;
    REG_IDX reg_idx;
    logic   halt;
    logic   illegal;
    logic   valid;
} COMMIT_PACKET;

typedef struct packed {
    logic valid;
    ADDR  target;
} BTB_ENTRY;

// fetch
typedef struct packed {
    logic valid;
    INST inst;
    ADDR PC;
    ADDR NPC;
    logic is_cond;
    logic is_uncond;
    logic is_func_call;
    logic is_return;
    // logic is_predicted_taken;
    ADDR predicted_addr; // for branch instruction
    BMASK bmask;
    B_IDX bindex;
} F_INST;


// dispatch
typedef struct packed {
    // From IF -------------------------------------------------------
    INST inst;
    ADDR PC; // for branch calculation
    ADDR NPC; // PC + 4, for wb
    ADDR predicted_addr; // for branch instruction

    // DATA rs1_value; // we don't yet have the values...
    // DATA rs2_value; // reg B value
    // Gathered by dispatcher ----------------------------------------
    TAG_PLUS src1, src2;
    TAG dst;
    REG_IDX  dest_reg_idx;  // destination (writeback) register index

    // From decoder --------------------------------------------------
    ALU_OPA_SELECT opa_select; // ALU opa mux select (ALU_OPA_xxx *)
    ALU_OPB_SELECT opb_select; // ALU opb mux select (ALU_OPB_xxx *)

    ALU_FUNC alu_func;      // ALU function select (ALU_xxx *)
    logic    mult;          // Is inst a multiply instruction?
    logic    rd_mem;        // Haven't yet dealt with mem
    logic    wr_mem;      
    logic    cond_branch;   // This type goes to branch unit 
    logic    uncond_branch; // This type goes to ALU and broadcasts CDB
    logic    halt;          // Forward all the way down to retire
    logic    illegal;       // All the way down to retire
    // logic    is_jal;
    logic    is_jalr;
    // Not sure what this is for, so comment it out
    // logic    csr_op;        // Is this a CSR operation? (we only used this as a cheap way to get return code)
} DECODED_INST;

typedef struct packed {
    logic valid; // used to find available entries
    BMASK bmask; // which (other) branch(es) this entry is dependent on?
    B_IDX b_idx; // which branch does this entry represent
} BR_STK_ENTRY;

// pf for prefetch
typedef enum logic [2:0] {
    PF_STATE_EMPTY,
    PF_STATE_WANT_REQ,
    PF_STATE_SENT_REQ,
    PF_STATE_HAS_DATA,
    PF_STATE_HIT
} PF_STATE;

typedef struct packed {
    PF_STATE state;
    MEM_TAG transac_tag;
    ADDR addr;
    MEM_BLOCK data;
} PF_ENTRY;

typedef struct packed {
    logic valid;
    DECODED_INST inst;
    BMASK bmask; // every instruction has a bmask, indicating which branches it is dependent on
    B_IDX br_idx; // only valid (not 0) for branch instruction; one-hot
    SQ_IDX st_pos;
} DIS_INST;

typedef struct packed {
    DIS_INST [`DISPATCH_WIDTH-1:0] insts;
} D_RS_PACKET;

// assume multiple ALUs and all others single
typedef enum logic[2:0] {
    OP_TYPE_NOP,
    OP_TYPE_ALU,
    OP_TYPE_MUL,
    OP_TYPE_LOAD,
    OP_TYPE_STORE,
    OP_TYPE_BR,
    OP_TYPE_HALT
} RS_OP_TYPE;

typedef enum logic [1:0] {EMPTY, DISPATCHED} RS_ENTRY_STATE;

typedef struct packed {
    DECODED_INST inst;
    RS_ENTRY_STATE state;
    RS_OP_TYPE op;
    TAG dst_tag;
    TAG_PLUS src_tag_1, src_tag_2;
    BMASK bmask; // early branch resolution
    B_IDX bindex; // for branch only, otherwise 0
    SQ_IDX st_pos;
    logic load_can_issue;
} RS_ENTRY;

typedef struct packed {
    logic valid;
    // whatever ALU needs for execution
    ALU_FUNC alu_func;
    ADDR PC;
    ADDR NPC;
    TAG src1;
    TAG src2;
    INST inst;
    ALU_OPA_SELECT opa_select; // ALU opa mux select (ALU_OPA_xxx *)
    ALU_OPB_SELECT opb_select; // ALU opb mux select (ALU_OPB_xxx *)
    // this tells issue reg to fetch data from cdb reg or prf
    logic src1_in_cdb;
    logic src2_in_cdb;
    TAG dst;
    BMASK bmask;
} ISS_INST_ALU;

typedef struct packed {
    logic valid;
    TAG src1;
    TAG src2;
    // this tells issue reg to fetch data from cdb reg or prf
    logic src1_in_cdb;
    logic src2_in_cdb;
    TAG dst;
    MULT_FUNC mult_func;
    BMASK bmask;
} ISS_INST_MUL;

/*typedef struct packed {
    logic valid;
    DECODED_INST inst;
    BMASK bmask;
} ISS_INST_MEM;*/

typedef struct packed {
    // currently doesn't support jalr!
    logic valid;
    ADDR predicted_addr;
    B_IDX bindex; 
    BMASK bmask;
    TAG src1, src2;
    logic src1_in_cdb, src2_in_cdb;
    TAG dst;
    ADDR PC;
    logic [2:0] branch_func;
    DATA offset;
    logic is_uncond_branch;
    logic is_halt; // we let br unit handle wfi
    logic is_jal;
    logic is_jalr;
} ISS_INST_BR;

typedef struct packed {
    logic valid;
    INST inst;
    TAG src1, src2;
    logic src1_in_cdb, src2_in_cdb;
    TAG dst;
    MEM_SIZE size;
    SQ_IDX st_pos;
    BMASK bmask;
    logic is_unsigned;
} ISS_INST_MEM;

typedef struct packed {
    logic   valid;
    DATA    data1, data2;
    BMASK   bmask;
    TAG     dst_tag;
    logic [3:0] func;
} EX_INST_ARITH; // for both add and mult

typedef struct packed {
    logic   valid;
    ADDR    predicted_addr;
    // logic   is_predicted_taken;
    B_IDX   bindex;
    BMASK   bmask;
    DATA    data1, data2;
    TAG     dst_tag;
    ADDR    PC;
    logic [2:0] branch_func;
    DATA    offset;
    logic   is_uncond_branch;
    logic   is_halt; // we let br unit handle wfi
    logic   is_jalr;
} EX_INST_BRANCH;

typedef struct packed {
    DATA    data_in, opa, opb;
    TAG     dst_tag;
    BMASK   bmask;
    logic   valid;
    MEM_SIZE size;
    SQ_IDX st_pos;
    logic   is_unsigned;
} EX_INST_MEM;


// definition for ROB. 
typedef struct packed {
    // logic available;     // is_available
    REG_IDX rd;         // dest_reg
    TAG t_new;          // tag_new
    TAG t_old;          // tag_old
    ADDR NPC;
    logic halt;
    logic illegal;
    logic store;
    logic valid;        // above four are given by dispatch, no modify
    logic complete;     // is_complete
} ROB_ENTRY;

typedef struct packed {
    DATA     result;
    TAG      dst_tag_out;
    BMASK    dst_bmask;
    logic    valid_out;
} CDB_REG_PACKET;

typedef struct packed {
    MEM_BLOCK     data_store;
    ADDR          addr;
    MEM_SIZE      size;
    // TAG           tag;
    // BMASK         bmask;
    logic         addr_calculated;
} SQ_ENTRY;

typedef logic [$clog2(`MSHR_SIZE)-1:0] CACHE_TAG;

typedef enum logic [2:0] {
		IDLE,          // Idle state
		WAIT_FWD,      // Waiting for forwarding
		WAIT_SEND,     // Waiting to send request
		WAIT_CACHE,     // Waiting for data from memory
		ARBIT,         // Arbitration state
		COMPLETE       // Completion state
} LOAD_STATE;

typedef struct packed {
    // logic 					valid;        // Is the entry in use
    DATA 					addr;      // The address of the load
	MEM_BLOCK   			data;         // The actual data
    TAG 					dst_tag;      // The destination tag
    BMASK     				bmask;    // Possibly needed mask bits

	MEM_SIZE 				mem_size;
    SQ_IDX 					st_pos;       // store queue index or related
    logic                   is_unsigned;
	
	CACHE_TAG 				cache_tag;
	LOAD_MASK 				load_mask;
	LOAD_STATE 				state;        // The current state of the load
    // logic   				data_ready;   // comb, Data is available    
} LOAD_STATION_ENTRY;

`endif // __SYS_DEFS_SVH__
