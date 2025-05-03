`timescale 1ns/1ps
`include "sys_defs.svh"

module tb_alu;

  // Declare input signals
  DATA          opa;
  DATA          opb;
  ALU_FUNC      alu_func;
  TAG           dst_tag_in;
  BMASK         src_bmask;
  logic         valid_in;

  // Declare output signals
  CDB_REG_PACKET cdb_reg_packet;

  TAG      early_tag_out;

  // Branch misprediction signals
  BR_RES_STATE  mis_res_state;
  B_IDX         mis_branch_idx;

  // Instantiate the ALU
  alu alu_inst (
    // ALU inputs
    .opa(opa),
    .opb(opb),
    .alu_func(alu_func),
    .dst_tag_in(dst_tag_in),
    .src_bmask(src_bmask),
    .valid_in(valid_in),

    // ALU outputs
    .cdb_reg_packet(cdb_reg_packet),
    .early_tag_out(early_tag_out),

    // Branch misprediction inputs
    .mis_res_state(mis_res_state),
    .mis_branch_idx(mis_branch_idx)
  );

  // Optionally, you can add initial blocks or other test logic to stimulate
  // the inputs and observe the outputs for verification.
  logic clock;
  initial clock = 0;
  always #5 clock = ~clock;  // Flip clock every 5 ns => 10 ns period

  // ---------------------
  // ---------------------
  initial begin

    // Reset
    opa = 0 ;
    opb = 0;
    alu_func = 0;
    dst_tag_in = 0;
    src_bmask = 0;
    valid_in = 0;

    mis_res_state = BR_RES_INVALID;
    mis_branch_idx = 0;

    // Wait for a couple of clock cycles
    repeat (2) @(posedge clock);

    @(posedge clock); 

    opa = 2;
    opb = 3;
    alu_func = ALU_ADD;
    dst_tag_in = 6;
    src_bmask = 0;
    valid_in = 1;
    mis_res_state = BR_RES_INVALID;
    mis_branch_idx = 0;

    @(posedge clock)
    $display("Testcase 1: test add");
    if(cdb_reg_packet.result != 5)begin
        $display("ERROR: wrong result! dest tag: %d, result: %d", dst_tag_in, cdb_reg_packet.result);
    end
    else begin
        $display("Passed testcase 1! dest tag: %d, result: %d", dst_tag_in, cdb_reg_packet.result);
    end


    @(negedge clock);

    opa = 2;
    opb = 3;
    alu_func = ALU_ADD;
    dst_tag_in = 6;
    src_bmask = 4'b1110;
    valid_in = 1;
    mis_res_state = BR_RES_HIT;
    mis_branch_idx = 2;

    @(posedge clock);
    $display("Testcase 2: test branch");
    if(cdb_reg_packet.valid_out == 0)begin
        $display("ERROR: should be valid!!");
    end
    else if(cdb_reg_packet.dst_bmask != 4'b1010) begin
        $display("ERROR: wrong bmask");
    end
    else begin
        $display("Passed testcase 2!");
    end

    @(negedge clock);
    opa = 2;
    opb = 3;
    alu_func = ALU_ADD;
    dst_tag_in = 6;
    src_bmask = 4'b1110;
    valid_in = 1;
    mis_res_state = BR_RES_MIS;
    mis_branch_idx = 2;

    @(posedge clock);
    $display("Testcase 2: test branch");
    if(cdb_reg_packet.valid_out == 1)begin
        $display("ERROR: should be invalid!!");
    end
    else begin
        $display("Passed testcase 2!");
    end 
    #10 $finish;

  end

endmodule