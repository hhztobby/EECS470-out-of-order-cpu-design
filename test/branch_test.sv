`timescale 1ns/1ps
`include "sys_defs.svh"
//TODO:: CDB reg internal forwarding
module tb_branch;

  // -----------------------------------------------------
  // Input signals (adjust widths/types to match sys_defs.svh)
  // -----------------------------------------------------
  logic [31:0]     rs1;
  logic [31:0]     rs2;
  logic [2:0]      func;
  ADDR            predict_addr;logic is_halt,is_uncond_branch;

  TAG              dst_tag_in;      // e.g., logic [4:0]
  BMASK            src_bmask;       // e.g., logic [31:0]
  B_IDX            branch_idx;      // e.g., logic [4:0]
  logic            valid_in;
  ADDR             NPC;             // e.g., logic [31:0]
  DATA             offset;          // e.g., logic [31:0]

  // Misprediction control signals
  BR_RES_STATE     mis_res_state;   // e.g., enum
  B_IDX            mis_branch_idx;  // e.g., logic [4:0]

  // -----------------------------------------------------
  // Output signals
  // -----------------------------------------------------
  CDB_REG_PACKET   cdb_reg_packet;   // struct with fields inside

  // TAG              early_tag_out;      // e.g., logic [4:0]

  ADDR             branch_target_br;   // e.g., logic [31:0]
  BR_RES_STATE     branch_result_state;
  logic            branch_valid_out;
  B_IDX            branch_idx_out;     // e.g., logic [4:0]

  // -----------------------------------------------------
  // Instantiate the conditional_branch module
  // -----------------------------------------------------
  branch uut (
    // Inputs
    .rs1               (rs1),
    .rs2               (rs2),
    .func              (func),
    .predict_addr      (predict_addr),
    .dst_tag_in        (dst_tag_in),
    .src_bmask         (src_bmask),
    .branch_idx        (branch_idx),
    .valid_in          (valid_in),
    .NPC               (NPC),
    .offset            (offset),
    .mis_res_state     (mis_res_state),
    .mis_branch_idx    (mis_branch_idx),
    .is_halt           (is_halt),
    .is_uncond_branch  (is_uncond_branch),

    // Outputs
    .cdb_reg_packet    (cdb_reg_packet),

    // .early_tag_out     (early_tag_out),
    .branch_target_true_addr_out  (branch_target_br),
    .branch_result_state_out (branch_result_state),
    .branch_valid_out  (branch_valid_out),
    .branch_idx_out    (branch_idx_out)
  );

  // -----------------------------------------------------
  // Add stimulus in an initial block
  // -----------------------------------------------------

  logic clock;
  initial clock = 0;
  always #5 clock = ~clock;  // Flip clock every 5 ns => 10 ns period

  initial begin
    // Example signal initialization
    rs1            = 32'h0;
    rs2            = 32'h0;
    func           = 3'b000;
    predict_addr   = 32'h1000_0000;
    is_halt        = 0;
    is_uncond_branch = 0;
    dst_tag_in     = '0;
    src_bmask      = 4'b0;
    branch_idx     = '0;
    valid_in       = 0;
    NPC            = 32'h1000_0000;
    offset         = 8'h4;
    mis_res_state  = BR_RES_INVALID;  // Example enum value
    mis_branch_idx = '0;

    @(posedge clock)
    // Wait a bit, then change inputs to see how module responds
    @(negedge clock);
    // Testcase 1: predict correctly
    rs1           = 1;
    rs2           = 1;
    func          = 0; //  a == b 
    predict_addr  =  8'h18;
    dst_tag_in    = 1;
    src_bmask     = 4'b1110;
    branch_idx    = 1; // which branch?
    valid_in      = 1;
    NPC           = 8'h11;
    offset        = 8'h7;
    mis_res_state  = BR_RES_INVALID;  // Example enum value
    mis_branch_idx = '0;
    
    @(posedge clock);

    $display("Testcase 1: predict correctly");
    if(cdb_reg_packet.dst_bmask != 4'b1110)begin
        $display("ERROR: wrong dst_bmask: %b", cdb_reg_packet.dst_bmask);
    end
    if(branch_target_br != 32'h18) begin
        $display("ERROR: wrong branch_target_br: %h", branch_target_br);
    end
    if(branch_result_state != BR_RES_HIT) begin
        $display("ERROR: wrong branch state!");
    end
    if(branch_idx_out != 1) begin
       $display("ERROR: wrong branch idx out");
    end

    $display("Branch outputs: target=%h, state=%0d, valid=%b, idx=%0d",
      branch_target_br, branch_result_state, branch_valid_out, branch_idx_out);

    @(negedge clock);
    // Testcase 2: uncond branch
    is_uncond_branch = 1;
    valid_in         = 1;
    NPC           = 8'h11;
    offset        = 8'h7;
    $display("Testcase 2: uncond branch");
    @(posedge clock);
    $display("Results: bmask=%b, target=%h, state=%0d, idx=%0d",
      cdb_reg_packet.dst_bmask, branch_target_br, branch_result_state, branch_idx_out);

    @(negedge clock);
    // Testcase 3: is halt
    is_halt         = 1;
    is_uncond_branch= 0;
    $display("Testcase 3: is halt");
    @(posedge clock);
    $display("Results: bmask=%b, target=%h, state=%0d, valid=%b, idx=%0d",
      cdb_reg_packet.dst_bmask, branch_target_br, branch_result_state, branch_valid_out, branch_idx_out);

    @(negedge clock);

    

    // ...
     $finish;
  end

endmodule