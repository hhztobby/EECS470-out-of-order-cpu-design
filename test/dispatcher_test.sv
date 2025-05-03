`ifndef RS_SIMULATOR_SV
`define RS_SIMULATOR_SV

`include "sys_defs.svh"
`include "dispatcher_defs.svh"
`include "ISA.svh"

/*
module dispatcher (
    input logic clock, reset, 
    // f_inst[0] is earlier in program order than f_inst[1]
    input F_INST [`N-1:0] f_inst,
    // which ones do we accept for dispatching
    output logic [`N-1:0] f_accept,

    // pass N*2 src arch reg, expecting N*2 physical regs (tags)
    output REG_IDX [`N-1:0][1:0] src_regs_to_mt,
    // use tag_plus as they may be ready
    input TAG_PLUS [`N-1:0][1:0] src_tags_from_mt,
    // pass N dest arch reg, expecting N pr
    // which will be passed to ROB as T_old
    output REG_IDX [`N-1:0] dst_regs_to_mt,
    input TAG [`N-1:0] dst_tags_from_mt,
    // update the tag mapping in Map Table, grabbed from free list
    output TAG [`N-1:0] new_dst_tags_to_mt,
    // EBR: which branch stack is allocated
    // shared with fl
    // output logic [`N-1:0] [$clog2(`BR_STK_SZ)-1:0] br_stk_idx_to_mt,
    // output logic [`N-1:0] br_stk_idx_valid_to_mt, //

    // query how many free PRs are there
    input TAG [`N-1:0] free_tags_from_fl, // 0 means no more available PR
    // output logic [`N-1:0] used_spots_to_fl, // use f_accept instead

    // EBR: which branch stack is allocated
    output logic [`N-1:0] [$clog2(`BR_STK_SZ)-1:0] dispatch_br_stk_idx,
    output logic [`N-1:0] dispatch_br_stk_idx_valid,
    
    input logic [$clog2(`N+1)-1:0] free_spots_num_from_rob,
    // output logic [`N-1:0] used_spots_to_rob, // use f_accept instead
    output ROB_ENTRY [`N-1:0] rob_entry_to_rob,

    input [$clog2(`N+1)-1:0] free_spots_num_from_rs,
    output D_RS_PACKET d_rs_packet,

    input B_IDX resolved_branch,
    input BR_RES_STATE br_res_state // branch result: a hit or a mispredict
)
*/

module dispatcher_test;
    // tb inputs
    logic clock, reset;
    F_INST [`N-1:0] f_inst;
    TAG_PLUS [`N-1:0][1:0] src_tags_from_mt;
    TAG [`N-1:0] dst_tags_from_mt;
    TAG [`N-1:0] free_tags_from_fl;
    logic [$clog2(`N+1)-1:0] free_spots_num_from_rob;
    logic [$clog2(`N+1)-1:0] free_spots_num_from_rs;
    B_IDX resolved_branch;
    BR_RES_STATE br_res_state;
    ADDR PC = 0;

    // tb outputs
    logic [`N-1:0] f_accept;
    REG_IDX [`N-1:0][1:0] src_regs_to_mt;
    REG_IDX [`N-1:0] dst_regs_to_mt;
    TAG [`N-1:0] new_dst_tags_to_mt;
    logic [`N-1:0] [$clog2(`BR_STK_SZ)-1:0] dispatch_br_stk_idx;
    logic [`N-1:0] dispatch_br_stk_idx_valid;
    ROB_ENTRY [`N-1:0] rob_entry_to_rob;
    D_RS_PACKET d_rs_packet;

    // debug outputs
    BR_STK_ENTRY [`BR_STK_SZ-1:0] branch_stk;

    // simulator outputs
    BR_STK_ENTRY [`BR_STK_SZ-1:0] sim_branch_stk, comb_sim_branch_stk;
    logic [`N-1:0] sim_f_accept;
    REG_IDX [`N-1:0][1:0] sim_src_regs_to_mt;
    REG_IDX [`N-1:0] sim_dst_regs_to_mt;
    TAG [`N-1:0] sim_new_dst_tags_to_mt;
    logic [`N-1:0] [$clog2(`BR_STK_SZ)-1:0] sim_dispatch_br_stk_idx;
    logic [`N-1:0] sim_dispatch_br_stk_idx_valid;
    ROB_ENTRY [`N-1:0] sim_rob_entry_to_rob;
    D_RS_PACKET sim_d_rs_packet;

    // testbench specific
    int test_id = 0;
    B_IDX br_stk_idx_1, br_stk_idx_2;

    task automatic reset_dut;
        begin
            @(negedge clock);
            reset = 1;
            @(negedge clock);
            reset = 0;
        end
    endtask

    task automatic test_assert(input logic condition);
        begin
            if (!condition) begin
                $fatal("\033[1;31m@@@ Failed Test %0d\033[0m", test_id);
            end
        end
    endtask

    task test_passed();
        begin
            $display("\033[1;32m@@@ Passed Test %0d\033[0m", test_id);
        end
    endtask

    task set_spots_full();
        begin
            free_tags_from_fl[0] = 1;
            free_tags_from_fl[1] = 2;
            free_spots_num_from_rob = 2;
            free_spots_num_from_rs = 2;
        end
    endtask

    `include "simulator/if_simulator.sv"
    

    function automatic int get_br_stack_occupied_num();
        int i;
        int num = 0;
        for (i = 0; i < `BR_STK_SZ; i++) begin
            if (branch_stk[i].valid) begin
                num++;
            end
        end
        return num;
    endfunction

    task automatic print_br_stack();
    `ifdef OUTPUT_TEST
        for (int i = 0; i < `BR_STK_SZ; i++) begin
            $display("branch_stk[%0d]: valid = %0b, bmask = %0b, b_idx = %0b", i, branch_stk[i].valid, branch_stk[i].bmask, branch_stk[i].b_idx);
        end
    `endif
    endtask

    `include "simulator/dispatch_simulator.sv"

    task automatic compare_dispatch(int i);
        int sim_branch_stk_occupied_num = 0, branch_stk_occupied_num = 0;
        begin
            // compare simulation results with actual results
            // print both results and fatal if mismatch
        `ifdef OUTPUT_TEST
            for (int j = 0; j < `BR_STK_SZ; j++) begin
                $display("sim_branch_stk[%0d]: valid = %0b, bmask = %0b, b_idx = %0b", j, sim_branch_stk[j].valid, sim_branch_stk[j].bmask, sim_branch_stk[j].b_idx);
            end
            for (int j = 0; j < `BR_STK_SZ; j++) begin
                $display("branch_stk[%0d]: valid = %0b, bmask = %0b, b_idx = %0b", j, branch_stk[j].valid, branch_stk[j].bmask, branch_stk[j].b_idx);
            end
        `endif
            if (sim_f_accept != f_accept) begin
                $display("\033[1;31m@@@ Failed: f_accept mismatch\033[0m");
                $display("Expected: %b", sim_f_accept);
                $display("Actual:   %b", f_accept);
                $fatal;
            end
            if (sim_branch_stk != branch_stk) begin
                $display("\033[1;31m@@@ Failed: branch_stk mismatch\033[0m");
                $fatal;
            end

            for (int i = 0; i < `N; i++) begin
                if (sim_d_rs_packet.insts[i].valid != d_rs_packet.insts[i].valid) begin
                    $display("\033[1;31m@@@ Failed: d_rs_packet[%0d].valid mismatch\033[0m", i);
                    $fatal;
                end
                if (sim_d_rs_packet.insts[i].valid) begin
                    if (sim_d_rs_packet.insts[i] != d_rs_packet.insts[i]) begin
                        $display("\033[1;31m@@@ Failed: d_rs_packet[%0d] mismatch\033[0m", i);
                        $display("sim_d_rs_packet[%0d]: valid = %0b, inst = %0b, bmask = %0b, br_idx = %0b", i, sim_d_rs_packet.insts[i].valid, sim_d_rs_packet.insts[i].inst, sim_d_rs_packet.insts[i].bmask, sim_d_rs_packet.insts[i].br_idx);
                        $display("d_rs_packet[%0d]: valid = %0b, inst = %0b, bmask = %0b, br_idx = %0b", i, d_rs_packet.insts[i].valid, d_rs_packet.insts[i].inst, d_rs_packet.insts[i].bmask, d_rs_packet.insts[i].br_idx);
                        $fatal;
                    end
                end
            end

            for (int i = 0; i < `N; i++) begin
                if (f_accept[i] && (rob_entry_to_rob[i] != sim_rob_entry_to_rob[i])) begin
                    $display("\033[1;31m@@@ Failed: rob_entry_to_rob[%0d] mismatch\033[0m", i);
                    // print rob entry in eligible format
                    $display("sim_rob_entry_to_rob[%0d]: rd = %0d, t_new = %0d, t_old = %0d, NPC = %0d, halt = %0b, illegal = %0b, valid = %0b, complete = %0b", i, sim_rob_entry_to_rob[i].rd, sim_rob_entry_to_rob[i].t_new, sim_rob_entry_to_rob[i].t_old, sim_rob_entry_to_rob[i].NPC, sim_rob_entry_to_rob[i].halt, sim_rob_entry_to_rob[i].illegal, sim_rob_entry_to_rob[i].valid, sim_rob_entry_to_rob[i].complete);
                    $display("rob_entry_to_rob[%0d]: rd = %0d, t_new = %0d, t_old = %0d, NPC = %0d, halt = %0b, illegal = %0b, valid = %0b, complete = %0b", i, rob_entry_to_rob[i].rd, rob_entry_to_rob[i].t_new, rob_entry_to_rob[i].t_old, rob_entry_to_rob[i].NPC, rob_entry_to_rob[i].halt, rob_entry_to_rob[i].illegal, rob_entry_to_rob[i].valid, rob_entry_to_rob[i].complete);
                    $fatal;
                end
            end

            test_assert(sim_src_regs_to_mt == src_regs_to_mt);
            test_assert(sim_dst_regs_to_mt == dst_regs_to_mt);
            test_assert(sim_new_dst_tags_to_mt == new_dst_tags_to_mt);
            test_assert(sim_dispatch_br_stk_idx == dispatch_br_stk_idx);
            test_assert(sim_dispatch_br_stk_idx_valid == dispatch_br_stk_idx_valid);
            $display("---------------------------- Cycle %0d passes ----------------------------", i);
        end
    endtask
        

    dispatcher dut (
        .clock(clock),
        .reset(reset),
        .f_inst(f_inst),
        .f_accept(f_accept),
        .src_regs_to_mt(src_regs_to_mt),
        .src_tags_from_mt(src_tags_from_mt),
        .dst_regs_to_mt(dst_regs_to_mt),
        .dst_tags_from_mt(dst_tags_from_mt),
        .new_dst_tags_to_mt(new_dst_tags_to_mt),
        .free_tags_from_fl(free_tags_from_fl),
        .dispatch_br_stk_idx(dispatch_br_stk_idx),
        .dispatch_br_stk_idx_valid(dispatch_br_stk_idx_valid),
        .free_spots_num_from_rob(free_spots_num_from_rob),
        .rob_entry_to_rob(rob_entry_to_rob),
        .free_spots_num_from_rs(free_spots_num_from_rs),
        .d_rs_packet(d_rs_packet),
        .resolved_branch(resolved_branch),
        .br_res_state(br_res_state),
        .branch_stk(branch_stk)
    );

    always #5 clock = ~clock;

    initial begin
        clock = 0;
        // initialize every input to 0
        f_inst = '0;
        src_tags_from_mt = '0;
        dst_tags_from_mt = '0;
        free_tags_from_fl = '0;
        free_spots_num_from_rob = 0;
        free_spots_num_from_rs = 0;
        resolved_branch = 0;
        br_res_state = BR_RES_INVALID;
        reset_dut;

        $display("-------------------------------- Test 1 - Basic Functionality --------------------------------");
        test_id = 1;
        @(negedge clock);
        f_inst[0].valid = 0;
        f_inst[1].valid = 0;
        @(posedge clock);
        test_assert(f_accept[0] == 0);
        test_assert(f_accept[1] == 0);

        @(negedge clock);
        f_inst[0].valid = 1;
        f_inst[1].valid = 1;
        set_spots_full();
        @(posedge clock);
        test_assert(f_accept[0] == 1);
        test_assert(f_accept[1] == 1);

        @(negedge clock);
        free_spots_num_from_rs = 1;
        @(posedge clock);
        test_assert(f_accept[0] == 1);
        test_assert(f_accept[1] == 0);

        @(negedge clock);
        free_spots_num_from_rs = 0;
        @(posedge clock);
        test_assert(f_accept[0] == 0);
        test_assert(f_accept[1] == 0);

        test_passed;
        
        $display("-------------------------------- Test 2 - Branch Resolution No Branch Dispatch --------------------------------");
        reset_dut;
        set_spots_full();
        test_id = 2;
        @(negedge clock);
        f_inst[0].valid = 1;
        f_inst[1].valid = 1;
        @(posedge clock);
        test_assert(f_accept[0] == 1);
        test_assert(f_accept[1] == 1);
        @(negedge clock);
        br_res_state = BR_RES_MIS;
        resolved_branch = 1;
        @(posedge clock);
        test_assert(f_accept[0] == 0);
        test_assert(f_accept[1] == 0);
        test_passed;
        br_res_state = BR_RES_INVALID;

        $display("-------------------------------- Test 3 - Branch Stack - Dispatch --------------------------------");
        reset_dut;
        set_spots_full();
        test_id = 3;
        @(negedge clock);
        f_inst[0].valid = 1;
        f_inst[1].valid = 1;
        f_inst[0].inst = generate_beq(1, 2, 0);
        f_inst[1].inst = '0;
        @(posedge clock);
        test_assert(f_accept[0] == 1);
        test_assert(f_accept[1] == 1);
        @(negedge clock);
        test_assert(get_br_stack_occupied_num() == 1);
        @(negedge clock);
        test_assert(get_br_stack_occupied_num() == 2);
        @(negedge clock);
        test_assert(get_br_stack_occupied_num() == 3);
        f_inst[1].inst = generate_beq(3, 4, 0);
        @(posedge clock);
        test_assert(f_accept[0] == 1);
        test_assert(f_accept[1] == 0); // branch stack structural hazard
        @(negedge clock);
        test_assert(get_br_stack_occupied_num() == 4);
        f_inst[1].inst = '0;
        @(posedge clock);
        test_assert(f_accept[0] == 0);
        test_assert(f_accept[1] == 0);
        @(negedge clock);
        f_inst[0].inst = '0;
        @(posedge clock);
        test_assert(f_accept[0] == 1);
        test_assert(f_accept[1] == 1);

        test_passed;
        f_inst = '0;

        $display("-------------------------------- Test 4 - Branch Stack - Dispatch and Resolve Hit --------------------------------");
        reset_dut;
        set_spots_full();
        test_id = 4;

        @(negedge clock);
        f_inst[0].valid = 1;
        f_inst[1].valid = 1;
        f_inst[0].inst = generate_beq(1, 2, 0);
        f_inst[1].inst = generate_beq(3, 4, 0);
        @(posedge clock);
        test_assert(dispatch_br_stk_idx_valid == 2'b11);
        br_stk_idx_1 = (1 << dispatch_br_stk_idx[0]);
        br_stk_idx_2 = (1 << dispatch_br_stk_idx[1]);
        f_inst[0].inst = '0;
        f_inst[1].inst = '0;
        @(negedge clock);
        print_br_stack();
        test_assert(get_br_stack_occupied_num() == 2);
        br_res_state = BR_RES_HIT;
        resolved_branch = br_stk_idx_1;
        @(negedge clock);
        test_assert(get_br_stack_occupied_num() == 1);
        @(negedge clock);
        test_assert(get_br_stack_occupied_num() == 1);



        $display("-------------------------------- Test 5 - Branch Stack - Dispatch and Resolve Mispredict --------------------------------");

        reset_dut;
        set_spots_full();
        test_id = 5;

        @(negedge clock);
        f_inst[0].valid = 1;
        f_inst[1].valid = 1;
        f_inst[0].inst = generate_beq(1, 2, 0);
        f_inst[1].inst = generate_beq(3, 4, 0);
        @(posedge clock);
        test_assert(dispatch_br_stk_idx_valid == 2'b11);
        br_stk_idx_1 = (1 << dispatch_br_stk_idx[0]);
        br_stk_idx_2 = (1 << dispatch_br_stk_idx[1]);
        f_inst[0].inst = '0;
        f_inst[1].inst = '0;
        @(negedge clock);
        print_br_stack();
        test_assert(get_br_stack_occupied_num() == 2);
        br_res_state = BR_RES_MIS;
        resolved_branch = br_stk_idx_1;
        @(negedge clock);
        test_assert(get_br_stack_occupied_num() == 0);

        $display("-------------------------------- Test 100 - Integrated --------------------------------");
        reset_dut;
        set_spots_full();
        test_id = 100;

        sim_branch_stk = '0;
        comb_sim_branch_stk = '0;
        sim_f_accept = '0;
        sim_src_regs_to_mt = '0;
        sim_dst_regs_to_mt = '0;
        sim_new_dst_tags_to_mt = '0;
        sim_dispatch_br_stk_idx = '0;
        sim_dispatch_br_stk_idx_valid = '0;
        sim_rob_entry_to_rob = '0;
        sim_d_rs_packet = '0;

        for (int i = 0; i < 10000; i++) begin
            f_inst[0].valid = 1;
            f_inst[1].valid = 1;
            f_inst[0].inst = generate_random_inst();
            f_inst[1].inst = generate_random_inst();
            f_inst[0].PC = PC;
            PC += 4;
            f_inst[0].NPC = PC;
            f_inst[1].PC = PC;
            PC += 4;
            f_inst[1].NPC = PC;
            
            resolved_branch = (1 << $urandom_range(0, `BR_STK_SZ-1));
            br_res_state = $urandom_range(0, 2);
        `ifdef OUTPUT_TEST
            // display br res state and spots
            case (br_res_state)
                0: $display("BR_RES_INVALID");
                1: $display("BR_RES_HIT");
                2: $display("BR_RES_MIS");
                default: $display("BR_RES_ERROR");
            endcase
            $display("resolved_branch: %0d", resolved_branch);
            $display("free_spots_num_from_rob: %0d", free_spots_num_from_rob);
            $display("free_spots_num_from_rs: %0d", free_spots_num_from_rs);
            print_br_stack();
        `endif
            @(posedge clock);
            dispatch_simulate(
                comb_sim_branch_stk,
                clock, reset,
                f_inst,
                src_tags_from_mt,
                dst_tags_from_mt,
                free_tags_from_fl,
                free_spots_num_from_rob,
                free_spots_num_from_rs,
                resolved_branch,
                br_res_state,
                // outputs
                sim_f_accept,
                sim_src_regs_to_mt,
                sim_dst_regs_to_mt,
                sim_new_dst_tags_to_mt,
                sim_dispatch_br_stk_idx,
                sim_dispatch_br_stk_idx_valid,
                sim_rob_entry_to_rob,
                sim_d_rs_packet
            );
            // compare combinational logic here
            compare_dispatch(i);
            // compare register after some delay, or directly at next cycle
            sim_branch_stk = comb_sim_branch_stk;
        end


        $display("-------------------------------- Test 101 - Integrated 2 --------------------------------");
        reset_dut;
        // set_spots_full();
        test_id = 101;

        sim_branch_stk = '0;
        comb_sim_branch_stk = '0;
        sim_f_accept = '0;
        sim_src_regs_to_mt = '0;
        sim_dst_regs_to_mt = '0;
        sim_new_dst_tags_to_mt = '0;
        sim_dispatch_br_stk_idx = '0;
        sim_dispatch_br_stk_idx_valid = '0;
        sim_rob_entry_to_rob = '0;
        sim_d_rs_packet = '0;

        for (int i = 0; i < 10000; i++) begin
            free_tags_from_fl[0] = $urandom_range(0, 1);
            free_tags_from_fl[1] = free_tags_from_fl[0] ? $urandom_range(0, 1) : 0;
            free_spots_num_from_rob = $urandom_range(0, 2);
            free_spots_num_from_rs = $urandom_range(0, 2);
            f_inst[0].valid = $urandom_range(0, 1);
            f_inst[1].valid = $urandom_range(0, 1) && f_inst[0].valid;
            f_inst[0].inst = generate_random_inst();
            f_inst[1].inst = generate_random_inst();
            f_inst[0].PC = PC;
            PC += 4;
            f_inst[0].NPC = PC;
            f_inst[1].PC = PC;
            PC += 4;
            f_inst[1].NPC = PC;
            
            resolved_branch = (1 << $urandom_range(0, `BR_STK_SZ-1));
            br_res_state = $urandom_range(0, 2);
        `ifdef OUTPUT_TEST
            // display br res state and spots
            case (br_res_state)
                0: $display("BR_RES_INVALID");
                1: $display("BR_RES_HIT");
                2: $display("BR_RES_MIS");
                default: $display("BR_RES_ERROR");
            endcase
            $display("resolved_branch: %0d", resolved_branch);
            $display("free_spots_num_from_rob: %0d", free_spots_num_from_rob);
            $display("free_spots_num_from_rs: %0d", free_spots_num_from_rs);
            print_br_stack();
        `endif
            @(posedge clock);
            dispatch_simulate(
                comb_sim_branch_stk,
                clock, reset,
                f_inst,
                src_tags_from_mt,
                dst_tags_from_mt,
                free_tags_from_fl,
                free_spots_num_from_rob,
                free_spots_num_from_rs,
                resolved_branch,
                br_res_state,
                // outputs
                sim_f_accept,
                sim_src_regs_to_mt,
                sim_dst_regs_to_mt,
                sim_new_dst_tags_to_mt,
                sim_dispatch_br_stk_idx,
                sim_dispatch_br_stk_idx_valid,
                sim_rob_entry_to_rob,
                sim_d_rs_packet
            );
            // compare combinational logic here
            compare_dispatch(i);
            // compare register after some delay, or directly at next cycle
            sim_branch_stk = comb_sim_branch_stk;
        end

        $display("\033[1;32m@@@ Passed ALL Tests!\033[0m");
        $finish;
    end

endmodule;

`endif