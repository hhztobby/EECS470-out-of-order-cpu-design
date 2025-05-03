`include "sys_defs.svh"
`include "dispatcher_defs.svh"
`include "rs_defs.svh"
`include "ISA.svh"

module integrated_test;

    localparam int NUM_ENTRIES = 8;
    localparam int ALU_CNT = 2;
    localparam int MULT_CNT = 1;
    localparam int FU_CNT = 6;

    // -------------------------- inputs --------------------------
    logic clock;
    logic reset;
    F_INST [`N-1:0] finsts;
    // -------------------------- outputs --------------------------
    ADDR branch_target_pc;
    COMMIT_PACKET [`N-1:0] commit_packets;
    // -------------------------- debug outputs --------------------------
    BR_STK_ENTRY [`BR_STK_SZ-1:0] branch_stk;
    RS_ENTRY [NUM_ENTRIES-1:0] rs_entries;

    
    function automatic [31:0] tag2int(input TAG tag);
    begin
        // Perform some operations...
        tag2int = {26'b0,tag};
    end
    endfunction

    function automatic [31:0] bit2int(input logic b);
    begin
        // Perform some operations...
        bit2int = {31'b0,b};
    end
    endfunction

    function automatic [31:0] op2int(input OP_TYPE op);
    begin
        // Perform some operations...
        op2int = {29'b0,op};
    end
    endfunction

    function automatic [31:0] state2int(input ENTRY_STATE state);
    begin
        // Perform some operations...
        state2int = {31'b0,state};
    end
    endfunction

    function automatic [31:0] reg2int(input REG_IDX reg);
    begin
        // Perform some operations...
        reg2int = {27'b0,reg};
    end
    endfunction

    function automatic [31:0] branch2int(input logic [`BR_STK_SZ-1:0] b);
    begin
        // Perform some operations...
        branch2int = {(32-`BR_STK_SZ)'b0,b};
    end
    endfunction

    task print_rs;
        begin
            print_rs_header();
            for (int i = 0; i < `NUM_ENTRIES; i++) begin
                print_rs_entry(i, state2int(rs_entries[i].state), op2int(rs_entries[i].op),tag2int(rs_entries[i].src_tag_1.tag), bit2int(rs_entries[i].src_tag_1.ready), tag2int(rs_entries[i].src_tag_2.tag), bit2int(rs_entries[i].src_tag_2.ready), tag2int(rs_entries[i].dst_tag));
            end
        end
    endtask

    task print_rob;
        begin
            print_rob_header();
            for (int i = 0; i < `ROB_SIZE; i++) begin
                print_rob_entry(i, reg2int(rob_entry[i].rd), tag2int(rob_entry[i].t_new),tag2int(rob_entry[i].t_old),rob_entry[i].NPC,bit2int(rob_entry[i].halt),bit2int(rob_entry[i].illegal),bit2int(rob_entry[i].valid),bit2int(rob_entry[i].complete));
            end
        end
    endtask

    task print_free_list;
        begin
            print_free_list_header();
            
            for (int i = 0; i < `BR_STK_SZ+1; i++) begin
                //print index i
                $fdisplay("BR_STACK[%0d]:", i);
                for (int j = 0; j < `PR_CNT; j++) begin
                    print_free_list_entry(i,bit2int(fl_entry[i][j])));
                end
            end
        end
    endtask

    task print_map_table;
        begin
            print_map_table_header();
            for (int i = 0; i < `BR_STK_SZ+1; i++) begin
                for(int j = 0; j < `ARCH_COUNT; j++) begin
                    print_map_table_entry(i,tag2int(mt_entry[i][j]));
                end
            end
        end
    endtask

    task print_branch_stack;
        begin
            print_branch_stack_header();
            for (int i = 0; i < `BR_STK_SZ; i++) begin
                print_branch_stack_entry(i,branch2int(branch_stk[i].bmask),bit2int(branch_stk[i].valid),branch2int(branch_stk[i].b_idx));
            end
        end
    endtask
    integrated #(
        .NUM_ENTRIES(NUM_ENTRIES),
        .ALU_CNT(ALU_CNT),
        .MULT_CNT(MULT_CNT)
    ) integrated_inst (
        // inputs
        .clock(clock),
        .reset(reset),
        .f_inst(finsts),
        // outputs
        .cdb_branch_target_pc(branch_target_pc),
        .retired_insts(commit_packets),
        // debug
        .branch_stk(branch_stk),
        .entries_for_dispatch_num(),
        .rs_entries(rs_entries)
    );

endmodule