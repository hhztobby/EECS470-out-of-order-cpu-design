`timescale 1ns/1ps
`include "sys_defs.svh"

// Always modified input at negedge
// Check register  at negedge
// Check comb logic at posedge 
// ------------|               |-------------|(reg, input)
//             |---------------|(comb)       |------------------|


task display_rob(
  input ROB_ENTRY [`ROB_SIZE-1:0] dbg_rob,
  input logic [$clog2(`ROB_SIZE)-1:0] dbg_head,
  input logic [$clog2(`ROB_SIZE)-1:0] dbg_tail
);
  integer i;
  
  // 打印表头
  $display("\n===========================================================================");
  $display("|  Index  |  t_new  |  t_old  |  Complete  |  Head/Tail  |");
  $display("===========================================================================");
  
  // 遍历 `ROB` 并打印每一行数据
  for (i = 0; i < `ROB_SIZE; i = i + 1) begin
    $display("|   %2d    |   %2d    |   %2d    |     %1d      |     %s     |", 
             i, dbg_rob[i].t_new, dbg_rob[i].t_old, dbg_rob[i].complete,
             (i == dbg_head&&i == dbg_tail)?"ht":(i == dbg_head) ? "h" : (i == dbg_tail) ? "t" : " ");
  end
  
  $display("===========================================================================");
endtask

module rob_tb;
  
  // 时钟和复位
  logic clock, reset;

  // ------------- dispatch -------------
  logic         [1:0] available_cnt;    
  ROB_ENTRY     [1:0] dispatch_entry;  
  logic         [1:0] dispatch_valid;
  logic         [1:0] is_branch;  
  B_IDX         [1:0] disp_branch_index;  

  // ------------- complete -------------
  TAG           [1:0] CDB_tag;  

  // ------------- retire -------------
  TAG           [1:0] old_tag_to_FL;  
  TAG           [1:0] t_new_to_prf;  
  DATA          [1:0] data_from_prf;  
  COMMIT_PACKET [1:0] retired_insts;  

  // ------------- branch -------------
  TAG                 br_tag;  

  // ------------- debug -------------
  ROB_ENTRY     [`ROB_SIZE-1:0] dbg_rob;  
  logic         [$clog2(`ROB_SIZE)-1:0] dbg_head, dbg_tail;  

  // DUT 实例化
  rob #(.ROB_SIZE(`ROB_SIZE))uut (
    .clock(clock),
    .reset(reset),
    // ------------- dispatch -------------
    .available_cnt(available_cnt),
    .dispatch_entry(dispatch_entry),
    .dispatch_valid(dispatch_valid),


    // ------------- retire -------------
    .CDB_tag(CDB_tag),
    .old_tag_to_FL(old_tag_to_FL),
    .t_new_to_prf(t_new_to_prf),
    .data_from_prf(data_from_prf),
    .retired_insts(retired_insts),

    // ------------- retire -------------
    .br_tag(br_tag),

    // ------------- debug -------------
    .dbg_rob(dbg_rob),
    .dbg_head(dbg_head),
    .dbg_tail(dbg_tail)
  );

  // ---------------------
  // 4) Clock generation
  // ---------------------
  initial clock = 0;
  always #5 clock = ~clock;  // Flip clock every 5 ns => 10 ns period

  // ---------------------
  // 5) Main Test Sequence
  // ---------------------
  initial begin
    // (1) Generate waveform file (optional)
    $dumpfile("rob.vcd");
    $dumpvars(0, rob_tb);

    // (2) Reset
    reset = 1;
    dispatch_valid[0] = 0;
    dispatch_valid[1] = 0;
    dispatch_entry[0] = '{default:0};
    dispatch_entry[1] = '{default:0};
    br_tag = 0;
    CDB_tag[0] = 0;
    CDB_tag[1] = 0;

    // Wait for a couple of clock cycles
    repeat (2) @(posedge clock);
    reset = 0;
    $display("[TIME %t] De-assert reset", $time);

    // (3) Wait for one clock cycle before starting tests
    @(posedge clock); 

    // ---------------------------------
    // TestCase 1: No dispatch (valid1=0, valid2=0)
    // ---------------------------------
    $display("\n[TIME %t] TestCase1: No dispatch", $time);
    dispatch_valid[0] = 0;
    dispatch_valid[1] = 0;
    @(posedge clock); // Wait one cycle
    // Check available_cnt
    $display("[TIME %t] available_cnt=%0d", $time, available_cnt);

    // ---------------------------------
    // TestCase 2: Dispatch a single instruction
    // ---------------------------------
    $display("\n[TIME %t] TestCase2: Single dispatch (valid1=1, valid2=0)", $time);
    dispatch_valid[0] = 1;
    dispatch_valid[1] = 0;
    dispatch_entry[0] = '{ 
      rd       : 5'd1,
      t_new    : 5'd2,
      t_old    : 5'd3,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };

    @(posedge clock); // Wait one cycle to write into ROB
    @(negedge clock); // modify input at negedge 

    // check reg output
    $display("[TIME %t] available_cnt=%0d (Should decrement by 1)", $time, available_cnt);
    // display_rob(dbg_rob, dbg_head, dbg_tail);
    
    // ---------------------------------
    // TestCase 3: Dispatch two instructions
    // ---------------------------------
    $display("\n$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$[TIME %t] TestCase3: Double dispatch (valid1=1, valid2=1)", $time);
    dispatch_valid[0] = 1;
    dispatch_valid[1] = 1;
    dispatch_entry[0] = '{ 
      rd       : 5'd4,
      t_new    : 5'd5,
      t_old    : 5'd6,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };
    dispatch_entry[1] = '{ 
      rd       : 5'd7,
      t_new    : 5'd8,
      t_old    : 5'd9,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };

    @(posedge clock);
    $display("[TIME %t] available_cnt=%0d (Should decrement by 2)", $time, available_cnt);
    @(negedge clock);

    // display_rob(dbg_rob, dbg_head, dbg_tail);

    // ------------ Expected Output ------------

    // At present ROB 
    //  t_new   //  t_old   //  Complete    //
    //  p2      //  p3      //  0           //
    //  p5      //  p6      //  0           //
    //  p8      //  p9      //  0           //

    // ------------       END       ------------

    // ---------------------------------
    // Continue to Dispatch two instructions
    // ---------------------------------
    $display("\n$$$$$$$$$$$$$$$$$$$$$$$$$$$$$[TIME %t] Continue to Dispatch two instructions", $time);
    dispatch_valid[0] = 1;
    dispatch_valid[1] = 1;
    dispatch_entry[0] = '{ 
      rd       : 5'd10,
      t_new    : 5'd11,
      t_old    : 5'd12,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };
    dispatch_entry[1] = '{ 
      rd       : 5'd13,
      t_new    : 5'd14,
      t_old    : 5'd15,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };

    @(posedge clock);
    $display("[TIME %t] available_cnt=%0d (Should be 2)", $time, available_cnt);
    @(negedge clock);

    // display_rob(dbg_rob, dbg_head, dbg_tail);

    // ------------ Expected Output ------------

    // At present ROB 
    //  t_new   //  t_old   //  Complete    //
    //  p2      //  p3      //  0           //
    //  p5      //  p6      //  0           //
    //  p8      //  p9      //  0           //
    //  p11     //  p12     //  0           //
    //  p14     //  p15     //  0           //

    // ------------       END       ------------
    
    // ---------------------------------
    // Continue to Dispatch two instructions
    // ---------------------------------
    $display("\n[TIME %t] Continue to Dispatch two instructions", $time);
    dispatch_valid[0] = 1;
    dispatch_valid[1] = 1;
    dispatch_entry[0] = '{ 
      rd       : 5'd16,
      t_new    : 5'd17,
      t_old    : 5'd18,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };
    dispatch_entry[1] = '{ 
      rd       : 5'd19,
      t_new    : 5'd20,
      t_old    : 5'd21,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };

    @(posedge clock);
    $display("[TIME %t] available_cnt=%0d (Should be 1)", $time, available_cnt);
    @(negedge clock);

    // display_rob(dbg_rob, dbg_head, dbg_tail);

    // ------------ Expected Output ------------

    // At present ROB 
    //  t_new   //  t_old   //  Complete    //
    //  p2      //  p3      //  0           //
    //  p5      //  p6      //  0           //
    //  p8      //  p9      //  0           //
    //  p11     //  p12     //  0           //
    //  p14     //  p15     //  0           //
    //  p17     //  p18     //  0           //
    //  p20     //  p21     //  0           //

    // ------------       END       ------------

    // ---------------------------------
    // TestCase 4: completes p5, dispatch 1
    // ---------------------------------
    $display("\n$$$$$$$$$$$$$$$$$$$$$$[TIME %t] TestCase4: completes p5, dispatch 1", $time);
    dispatch_valid[0] = 1;
    dispatch_valid[1] = 0;
    dispatch_entry[0] = '{ 
      rd       : 5'd22,
      t_new    : 5'd23,
      t_old    : 5'd24,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };

    CDB_tag[0] = 5'd5;

    @(posedge clock);
    $display("[TIME %t] available_cnt=%0d (Should decrement by 2)", $time, available_cnt);
    @(negedge clock);


    // display_rob(dbg_rob, dbg_head, dbg_tail);

    // ------------ Expected Output ------------

    //  t_new   //  t_old   //  Complete    //
    //  p2      //  p3      //  0           //
    //  p5      //  p6      //  1           //
    //  p8      //  p9      //  0           //
    //  p11     //  p12     //  0           //
    //  p14     //  p15     //  0           //
    //  p17     //  p18     //  0           //
    //  p20     //  p21     //  0           //
    //  p23     //  p24     //  0           //

    // ------------       END       ------------


    // ---------------------------------
    // TestCase 5: complete p2, p11
    // ---------------------------------
    $display("\n[TIME %t] TestCase 5: complete p2, p11", $time);

    dispatch_valid[0] = 0;
    dispatch_valid[1] = 0;
    CDB_tag[0] = 5'd2;
    CDB_tag[1] = 5'd11;
    @(posedge clock);
    $display("[TIME %t] available_cnt=%0d (Should be 0)", $time, available_cnt);
    @(negedge clock);

    CDB_tag[0] = 0;
    CDB_tag[1] = 0;
    // Check results

    // display_rob(dbg_rob, dbg_head, dbg_tail);
    // ------------ Expected Output ------------

    //  t_new   //  t_old   //  Complete    //
    //  p2      //  p3      //  1           // head tail
    //  p5      //  p6      //  1           //
    //  p8      //  p9      //  0           //
    //  p11     //  p12     //  1           //
    //  p14     //  p15     //  0           //
    //  p17     //  p18     //  0           //
    //  p20     //  p21     //  0           //
    //  p23     //  p24     //  0           // 

    // ------------       END       ------------


    // ---------------------------------
    // TestCase 6: Retire p2, p5, dispatch 2 inst
    // If the head points to two completed entries, both can be retired
    // Check if available_cnt increases
    // ---------------------------------
    $display("\n[TIME %t] TestCase6: Retire p2, p5, dispatch 2 inst", $time);
    dispatch_valid[0] = 1;
    dispatch_valid[1] = 1;
    dispatch_entry[0] = '{ 
      rd       : 5'd25,
      t_new    : 5'd26,
      t_old    : 5'd27,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };
    dispatch_entry[1] = '{ 
      rd       : 5'd28,
      t_new    : 5'd29,
      t_old    : 5'd30,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };

    @(posedge clock);
    $display("[TIME %t] After retire, available_cnt=%0d (Should be 2)", $time, available_cnt);
    @(negedge clock);

    display_rob(dbg_rob, dbg_head, dbg_tail);
    $display("head: %d ", dbg_head);
    if (dbg_head != 3'd2) begin
        $display("Error: wrong head pointer!");
    end
    $display("tail: %d ", dbg_tail);
    if (dbg_tail != 3'd2) begin
        $display("Error: wrong tail pointer!");
    end


    // ------------ Expected Output ------------

    //  t_new   //  t_old   //  Complete    //
    //  p26     //  p27     //  0           //
    //  p29     //  p30     //  0           //  
    //  p8      //  p9      //  0           //  head tail
    //  p11     //  p12     //  1           //
    //  p14     //  p15     //  0           //
    //  p17     //  p18     //  0           //
    //  p20     //  p21     //  0           //
    //  p23     //  p24     //  0           //

    // ------------       END       ------------

    // ---------------------------------
    // TestCase 7: complete p8
    // If the head points to two completed entries, both can be retired
    // Check if available_cnt increases
    // ---------------------------------
    $display("\n[TIME %t] TestCase7: complete p8", $time);
    dispatch_valid[0] = 0;
    dispatch_valid[1] = 0;
    CDB_tag[0] = 5'd8;

    @(posedge clock);
    $display("[TIME %t] After retire, available_cnt=%0d (Should be 0), count= %0d", $time, available_cnt, uut.count);
    @(negedge clock);

    display_rob(dbg_rob, dbg_head, dbg_tail);

    // ------------ Expected Output ------------

    //  t_new   //  t_old   //  Complete    //
    //  p26     //  p27     //  0           //
    //  p29     //  p30     //  0           //  
    //  p8      //  p9      //  1           //  head tail
    //  p11     //  p12     //  1           //
    //  p14     //  p15     //  0           //
    //  p17     //  p18     //  0           //
    //  p20     //  p21     //  0           //
    //  p23     //  p24     //  0           //

    // ------------       END       ------------

    // ---------------------------------
    // TestCase 8: retire 2, and dispatch branch and one instruction, complete p14, p17
    // If the head points to two completed entries, both can be retired
    // Check if available_cnt increases
    // ---------------------------------
    $display("\n[TIME %t] TestCase 8: retire 2, and dispatch branch and one instruction, complete p14, p17", $time);
    dispatch_valid[0] = 1;
    dispatch_valid[1] = 1;
    dispatch_entry[0] = '{ 
      rd       : 5'd1,
      t_new    : 5'd2,
      t_old    : 5'd3,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };
    dispatch_entry[1] = '{ 
      rd       : 5'd4,
      t_new    : 5'd5,
      t_old    : 5'd5,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };
    CDB_tag[0] = 5'd14;
    CDB_tag[1] = 5'd17;

    @(posedge clock);
    $display("[TIME %t] After retire, available_cnt=%0d (Should be 2)", $time, available_cnt);
    @(negedge clock);

    display_rob(dbg_rob, dbg_head, dbg_tail);
    $display("head: %d ", dbg_head);
    if (dbg_head != 3'd4) begin
        $display("Error: wrong head pointer!");
    end
    $display("tail: %d ", dbg_tail);
    if (dbg_tail != 3'd4) begin
        $display("Error: wrong tail pointer!");
    end

    // // ------------ Expected Output ------------

    // //  t_new   //  t_old   //  Complete    //
    // //  p26     //  p27     //  0           //
    // //  p29     //  p30     //  0           //  
    // //  p2      //  p3      //  0           //  branch enter 
    // //  p5      //  p6      //  0           //  
    // //  p14     //  p15     //  1           //  head tail
    // //  p17     //  p18     //  1           //
    // //  p20     //  p21     //  0           //
    // //  p23     //  p24     //  0           //

    // // ------------       END       ------------


    // ---------------------------------
    // TestCase 9: Retire p14, p17, dispatch 2 inst
    // If the head points to two completed entries, both can be retired
    // Check if available_cnt increases
    // ---------------------------------
    $display("\n[TIME %t] TestCase 9: Retire p14, p17, dispatch 2 inst", $time);
    dispatch_valid[0] = 1;
    dispatch_valid[1] = 1;
    dispatch_entry[0] = '{ 
      rd       : 5'd7,
      t_new    : 5'd8,
      t_old    : 5'd9,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };
    dispatch_entry[1] = '{ 
      rd       : 5'd10,
      t_new    : 5'd11,
      t_old    : 5'd12,
      complete : 1'b0,
      NPC      : 32'h0,
      halt     : 1'b0,
      illegal  : 1'b0,
      valid    : 1'b1
    };

    @(posedge clock);
        $display("[TIME %t] After retire, available_cnt=%0d (Should be 2)", $time, available_cnt);
    @(negedge clock);


    display_rob(dbg_rob, dbg_head, dbg_tail);

    // ------------ Expected Output ------------

    //  t_new   //  t_old   //  Complete    //
    //  p26     //  p27     //  0           //
    //  p29     //  p30     //  0           //  
    //  p2      //  p3      //  0           //  branch enter 
    //  p5      //  p6      //  0           //
    //  p8      //  p9      //  0           //  
    //  p11     //  p12     //  0           //
    //  p20     //  p21     //  0           //  head tail
    //  p23     //  p24     //  0           //

    // ------------       END       ------------


    // ---------------------------------
    // TestCase 10: branch resolution
    // If the head points to two completed entries, both can be retired
    // Check if available_cnt increases
    // ---------------------------------
    $display("\n[TIME %t] TestCase 10: branch resolution", $time);
    dispatch_valid[0] = 0;
    dispatch_valid[1] = 0;
    br_tag = 5'd11;

    @(posedge clock);
        $display("[TIME %t] After retire, available_cnt=%0d (Should be 0)", $time, available_cnt);
    @(negedge clock);


    display_rob(dbg_rob, dbg_head, dbg_tail);

    // ------------ Expected Output ------------

    //  t_new   //  t_old   //  Complete    //
    //  p26     //  p27     //  0           //
    //  p29     //  p30     //  0           //  
    //  p       //  p       //  0           //  tail
    //  p       //  p       //  0           //
    //  p       //  p       //  0           //  
    //  p       //  p       //  0           //
    //  p20     //  p21     //  0           //  head
    //  p23     //  p24     //  0           //

    // ------------       END       ------------


    // /*
    // // ---------------------------------
    // // TestCase 7: Branch misprediction
    // // Suppose br_tag=11 => indicates a branch with misprediction
    // // The ROB should adjust tail and clear entries after that point
    // // Also dispatch 1, complete 1 (branch), retire 1 in this cycle
    // // ---------------------------------
    // $display("\n[TIME %t] TestCase7: Branch misprediction with br_tag=11", $time);

    // br_tag = 5'd11;  

    // dispatch_valid[0] = 0;
    // dispatch_valid[1] = 0;
    // dispatch_entry[0] = '{ 
    //   rd       : 5'd10,
    //   t_new    : 5'd11,
    //   t_old    : 5'd12,
    //   complete : 1'b0
    // };

    // FU_to_ROB_finish[0] = 1;
    // FU_to_ROB_tag[0]    = 5'd11;

    // @(posedge clock);
    // br_tag = 0;

    // // Reset signals
    // dispatch_valid[0] = 0;
    // dispatch_valid[1] = 0;
    // dispatch_entry[0] = '{default:0};

    // FU_to_ROB_finish[0] = 0;
    // FU_to_ROB_tag[0]    = 5'd0;

    // @(posedge clock);
    // $display("[TIME %t] After misprediction, head/tail and available_cnt=%0d", $time, available_cnt);
    // */
    // // ---------------------------------
    // // All tests completed
    // // ---------------------------------
    $display("\n[TIME %t] All tests completed!", $time);
    #10 $finish;
  end

endmodule