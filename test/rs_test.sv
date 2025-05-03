`include "sys_defs.svh"
`include "rs_defs.svh"

module RS_tb;
    // Parameters
    localparam NUM_ENTRIES = 8;
    localparam ALU_CNT = 3;
    localparam FU_CNT = 6;

    // Signals
    reg clock, reset;
    reg [FU_CNT-1:0] alu_avails, mul_avails, mem_avails, br_avails;
    B_IDX br_res_idx;
    BR_RES_STATE br_res_state;
    
    // Dispatch packet
    D_RS_PACKET d_rs_packet;
    
    // CDB signals
    TAG cdb_tag_1, cdb_tag_2;

    // Outputs
    wire [1:0] spots;
    logic [FU_CNT-1:0] one_cycle_inst_reqs;
    logic [FU_CNT-1:0] one_cycle_inst_gnts;
    ISS_INST_ALU [ALU_CNT-1:0] alu_insts;
    ISS_INST_MUL mul_inst;
    ISS_INST_MEM mem_inst;
    ISS_INST_BR br_inst;
    wire [$clog2(NUM_ENTRIES+1)-1:0] slots;

    int test_id;
    RS_ENTRY [NUM_ENTRIES-1:0] entries; // for simulation
    RS_ENTRY [NUM_ENTRIES-1:0] module_entries; // for DUT

    task check_issue_num(
        input logic [$clog2(NUM_ENTRIES+1)-1:0] correct_count);
        int issued_count;
        issued_count = 0;
        for (int i = 0; i < ALU_CNT; i++)
            if (alu_insts[i].valid) issued_count++;
        assert (issued_count == correct_count) else $fatal("Test %d Failed: Incorrect ALU issue count. Expected %d, got: %d", test_id, correct_count,issued_count);
    endtask

    task invalid_inst;
        d_rs_packet.insts[0].valid=1'b0;
        d_rs_packet.insts[1].valid=1'b0;
    endtask

    task reset_sequence;
        begin
            @(negedge clock);  // Wait for the negative edge of the clock
            reset = 1;         // Assert reset
            @(negedge clock);  // Wait for the next negative edge
            reset = 0;         // Deassert reset
        end
    endtask

    task reset_cdb;
        begin
            cdb_tag_1=0;
            cdb_tag_2=0;      
        end
    endtask

    task assert_slots(input logic [$clog2(NUM_ENTRIES+1)-1:0] expected_slots);
    `ifdef DEBUG_SYN
        assert (slots == expected_slots) else $fatal("\033[1;31m@@@ Failed Test %0d\033[0m: Expected %0d slots, got %0d", test_id, expected_slots, slots);
    `endif
    endtask

    task display_test_res(logic passed);
    begin
        if (passed) begin
            $display("\033[1;32m@@@ Passed Test %0d\033[0m", test_id);
        end else begin
            $fatal("\033[1;31m@@@ FailedTest %0d Failed\033[0m", test_id);
        end
    end
    endtask

    // --------------------------- Random Generator ---------------------------
    task random_alu;
        begin
            alu_avails = $urandom_range(0, 6'b111);
        end
    endtask

    task random_cdb;
        begin
            cdb_tag_1 = $urandom_range(0, 3'b111);
            cdb_tag_2 = $urandom_range(0, 3'b111);
        end
    endtask

    task automatic random_resolved_br;
        begin
            int index = $urandom_range(0, 4);
            if (index == 4) br_res_idx = 0;
            else br_res_idx = 1 << index;
            br_res_state = $urandom_range(0, 2); // invalid, hit, mis
        end
    endtask


    // --------------------------- Cycle-accurate Simulator ---------------------------
    task automatic simulate(ref RS_ENTRY [NUM_ENTRIES-1:0] entries);
        begin
            int alu_avail_num = 0;
            int dis_valid_cnt = 0;
            int i = 0, j = NUM_ENTRIES - 1;  
            int alu_i = 0, alu_j = ALU_CNT - 1;
            // C: complete broadcast
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                if (entries[i].state == DISPATCHED) begin
                    entries[i].src_tag_1.ready |= (entries[i].src_tag_1.tag == cdb_tag_1 || entries[i].src_tag_1.tag == cdb_tag_2);
                    entries[i].src_tag_2.ready |= (entries[i].src_tag_2.tag == cdb_tag_1 || entries[i].src_tag_2.tag == cdb_tag_2);
                end
            end
            // EX: branch resolution
            if (br_res_state == BR_RES_MIS) begin
                for (int i = 0; i < NUM_ENTRIES; i++) begin
                    if (entries[i].state == DISPATCHED && (entries[i].bmask & br_res_idx) != 0) begin
                        entries[i].state = EMPTY;
                    end
                end
            end else if (br_res_state == BR_RES_HIT) begin
                for (int i = 0; i < NUM_ENTRIES; i++) begin
                    if (entries[i].state == DISPATCHED) begin
                        entries[i].bmask &= ~br_res_idx;
                    end
                end
            end
            // issue
            for (int i = 0; i < FU_CNT; i++) begin
                if (alu_avails[i]) begin
                    alu_avail_num++;
                    alu_j = i;
                end
            end
            for (int i = 0; i < FU_CNT; i++) begin
                if (alu_avails[i]) begin
                    alu_i = i;
                    break;
                end
            end
            /* $display("ALU available: %0d", alu_avail_num);
            $display("Pre-issue: ");
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                $display("Entry %0d: state: %0d, src_tag_1_rd: %0d, src_tag_2_rd: %0d", i, entries[i].state, entries[i].src_tag_1.ready, entries[i].src_tag_2.ready);
            end*/

            for (i = 0, j = NUM_ENTRIES - 1; alu_avail_num > 0 && i <= j; ) begin
                // display states of the entries, including state, src ready, and bmask
                // $display("Entry %0d: state: %0d, src_tag_1_rd: %0d, src_tag_2_rd: %0d, bmask: %0b", first, entries[first].state, entries[first].src_tag_1.ready, entries[first].src_tag_2.ready, entries[first].bmask);
                // $display("Entry %0d: state: %0d, src_tag_1_rd: %0d, src_tag_2_rd: %0d, bmask: %0b", second, entries[second].state, entries[second].src_tag_1.ready, entries[second].src_tag_2.ready, entries[second].bmask);
                for (; i <= j; j--) begin
                    if (entries[j].state == DISPATCHED && (entries[j].src_tag_1.ready && entries[j].src_tag_2.ready)) begin
                        `ifdef OUTPUT_TEST
                        $display("Entry %0d gets fu %0d", j, alu_j);
                        `endif
                        alu_avail_num--;
                        alu_j--; // not granted, cannot actually issue
                        if (one_cycle_inst_gnts[alu_j+1] != 0) begin
                            entries[j].state = EMPTY;
                            `ifdef OUTPUT_TEST
                            $display("Issuing instruction from entry %0d", j);
                            `endif
                        end else begin
                            `ifdef OUTPUT_TEST
                            $display("Entry %0d is ready for issue, but not granted by cdb arbiter", j);
                            `endif
                        end
                        j--;
                        break;
                    end
                end
                
                for (; alu_avail_num > 0 && i <= j; i++) begin
                    if (entries[i].state == DISPATCHED && (entries[i].src_tag_1.ready && entries[i].src_tag_2.ready)) begin
                        `ifdef OUTPUT_TEST
                        $display("Entry %0d gets fu %0d", i, alu_i);
                        `endif
                        alu_avail_num--;
                        alu_i++; // not granted, cannot actually issue
                        if (one_cycle_inst_gnts[alu_i-1] != 0) begin
                            entries[i].state = EMPTY;
                            `ifdef OUTPUT_TEST
                            $display("Issuing instruction from entry %0d", i);
                            `endif
                        end else begin
                            `ifdef OUTPUT_TEST
                            $display("Entry %0d is ready for issue, but not granted by cdb arbiter", i);
                            `endif
                        end
                        i++;
                        break;
                    end
                end
            end
            
            // dispatch
            for (i = 0; i < 2; i++) begin
                if (d_rs_packet.insts[i].valid) begin
                    dis_valid_cnt++;
                end
            end
            `ifdef OUTPUT_TEST
            $display("Dispatching %0d instructions", dis_valid_cnt);
            `endif

            for (i = 0, j = NUM_ENTRIES - 1; dis_valid_cnt > 0 && i <= j; ) begin
                for (; i <= j; j--) begin
                    if (entries[j].state == EMPTY) begin
                        if (dis_valid_cnt == 2) begin
                            entries[j].state = DISPATCHED;
                            entries[j].inst = d_rs_packet.insts[1].inst;
                            entries[j].src_tag_1 = d_rs_packet.insts[1].src_1;
                            entries[j].src_tag_2 = d_rs_packet.insts[1].src_2;
                            entries[j].bmask = d_rs_packet.insts[1].bmask;
                        end else if (dis_valid_cnt == 1) begin
                            entries[j].state = DISPATCHED;
                            entries[j].inst = d_rs_packet.insts[0].inst;
                            entries[j].src_tag_1 = d_rs_packet.insts[0].src_1;
                            entries[j].src_tag_2 = d_rs_packet.insts[0].src_2;
                            entries[j].bmask = d_rs_packet.insts[0].bmask;
                        end
                        `ifdef OUTPUT_TEST
                        $display("Dispatching instruction %0d to entry %0d", dis_valid_cnt - 1, j);
                        `endif
                        dis_valid_cnt--;
                        break;
                    end
                end
                
                for (; dis_valid_cnt > 0 && i <= j; i++) begin
                    if (entries[i].state == EMPTY) begin
                        if (dis_valid_cnt == 2) begin
                            entries[i].state = DISPATCHED;
                            entries[i].inst = d_rs_packet.insts[1].inst;
                            entries[i].src_tag_1 = d_rs_packet.insts[1].src_1;
                            entries[i].src_tag_2 = d_rs_packet.insts[1].src_2;
                            entries[i].bmask = d_rs_packet.insts[1].bmask;
                        end else if (dis_valid_cnt == 1) begin
                            entries[i].state = DISPATCHED;
                            entries[i].inst = d_rs_packet.insts[0].inst;
                            entries[i].src_tag_1 = d_rs_packet.insts[0].src_1;
                            entries[i].src_tag_2 = d_rs_packet.insts[0].src_2;
                            entries[i].bmask = d_rs_packet.insts[0].bmask;
                        end
                        `ifdef OUTPUT_TEST
                        $display("Dispatching instruction %0d to entry %0d", dis_valid_cnt - 1, i);
                        `endif
                        dis_valid_cnt--;
                        break;
                    end
                end
            end

            // broadcast CDB again to handle newly dispatched instructions src tags
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                if (entries[i].state == DISPATCHED) begin
                    entries[i].src_tag_1.ready |= (entries[i].src_tag_1.tag == cdb_tag_1 || entries[i].src_tag_1.tag == cdb_tag_2);
                    entries[i].src_tag_2.ready |= (entries[i].src_tag_2.tag == cdb_tag_1 || entries[i].src_tag_2.tag == cdb_tag_2);
                end
            end
            `ifdef OUTPUT_TEST
            $display("Simulation for current cycle ends. ----------------------------------------------------------------------------");
            `endif
        end
    endtask

    task compare_result(ref RS_ENTRY [NUM_ENTRIES-1:0] entries, int cycle);
        `ifndef SYNTHESIZE // unfortunately synthesis tool doesn't support references like module_entries[i]
        int i = 0, j = 0;
        for (i = 0; i < NUM_ENTRIES; i++) begin
            assert ((entries[i].state == module_entries[i].state) && (entries[i].state == EMPTY || 
                    (entries[i].src_tag_1.tag == module_entries[i].src_tag_1.tag &&
                    entries[i].src_tag_1.ready == module_entries[i].src_tag_1.ready &&
                    entries[i].src_tag_2.tag == module_entries[i].src_tag_2.tag &&
                    entries[i].src_tag_2.ready == module_entries[i].src_tag_2.ready &&
                    entries[i].bmask == module_entries[i].bmask))
                )
            else begin
                @(posedge clock); // for display rs
                // print RS_ENTRY comparisons:
                for (j = 0; j < NUM_ENTRIES; j++) begin
                    $display("Entry %0d (simulated vs dut): ", j);
                    $display("  State: %0d vs %0d", entries[j].state, module_entries[j].state);
                    $display("  Src_1: %0d vs %0d", entries[j].src_tag_1.tag, module_entries[j].src_tag_1.tag);
                    $display("  Src_1 Ready: %0d vs %0d", entries[j].src_tag_1.ready, module_entries[j].src_tag_1.ready);
                    $display("  Src_2: %0d vs %0d", entries[j].src_tag_2.tag, module_entries[j].src_tag_2.tag);
                    $display("  Src_2 Ready: %0d vs %0d", entries[j].src_tag_2.ready, module_entries[j].src_tag_2.ready);
                    $display("  Bmask: %0b vs %0b", entries[j].bmask, module_entries[j].bmask);
                end
                $fatal("\033[1;31m@@@ Failed: Entry %0d state mismatch at cycle %0d. \033[0m", i, cycle);
            end
        end
        `endif
    endtask

    // we limit the tag range
    // otherwise issue rate could be too low...
    function automatic DIS_INST random_alu_dis_ins();
        begin
            DIS_INST dis_inst;
            dis_inst.valid = $urandom_range(0, 1'b1);
            dis_inst.inst.opcode = $urandom_range(0, 4'b1111);
            dis_inst.inst.dst_tag = $urandom_range(0, 3'b111);
            dis_inst.inst.op_type = OP_TYPE_ALU;
            dis_inst.src_1.tag = $urandom_range(0, 3'b111);
            dis_inst.src_1.ready = dis_inst.src_1.tag == 0 ? 1'b1: $urandom_range(0, 1'b1);
            dis_inst.src_2.tag = $urandom_range(0, 3'b111);
            dis_inst.src_2.ready = dis_inst.src_2.tag == 0 ? 1'b1: $urandom_range(0, 1'b1);
            dis_inst.bmask = $urandom_range(0, 4'b1111);
            if (br_res_state == BR_RES_MIS && (br_res_idx & dis_inst.bmask) != 0) begin 
                dis_inst.valid = 1'b0;
            end else if (br_res_state == BR_RES_HIT) begin
                br_res_idx &= ~dis_inst.bmask;
            end
            return dis_inst;
        end
    endfunction

    // Instantiate the Reservation Station module
    rs #(
        .FU_CNT(FU_CNT),
        .NUM_ENTRIES(NUM_ENTRIES),
        .ALU_CNT(ALU_CNT)
    ) dut (
        .clock(clock),
        .reset(reset),
        .d_rs_packet(d_rs_packet),
        .cdb_tag_1(cdb_tag_1),
        .cdb_tag_2(cdb_tag_2),
        .alu_avails(alu_avails),
        .mul_avails(mul_avails),
        .mem_avails(mem_avails),
        .br_avails(br_avails),
        .br_res_idx(br_res_idx),
        .br_res_state(br_res_state),
        .spots(spots),
        .one_cycle_inst_reqs(one_cycle_inst_reqs),
        .one_cycle_inst_gnts(one_cycle_inst_gnts),
        .alu_insts(alu_insts),
        .mul_inst(mul_inst),
        .mem_inst(mem_inst),
        .br_inst(br_inst)
`ifdef DEBUG_SYN
        , .entries_for_dispatch_num(slots)
        , .debug_rs_entries(module_entries)
`endif
    );
    // Clock Generation
    always #5 clock = ~clock; // 10ns clock period

    // Testbench Procedure
    initial begin
        `ifndef DEBUG_SYN
            $display("\033[1;33mWARNING: Your are running testbench without DEBUG_SYN. Test results can be incomplete/inaccurate. \033[0m");
        `endif
        $dumpfile("rs_test.vcd");
        $dumpvars(0, RS_tb);
        // Initialize signals
        clock = 0;
        reset = 1;
        d_rs_packet = '{insts: '{default: '0}};
        alu_avails = 6'b000001;  // Only 1 ALU available
        mul_avails = 6'b001000;  // MUL available
        mem_avails = 6'b010000;  // MEM available
        br_avails  = 6'b100000;  // BR available
        br_res_idx = '0;
        br_res_state = BR_RES_INVALID;
        cdb_tag_1 = 0;
        cdb_tag_2 = 0;
        one_cycle_inst_gnts = '1;

        // Apply Reset
        reset_sequence;
        // ---------------- Test 1: Instruction should not issue when ready bit is 0 ----------------
        test_id = 1;
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0101, dst_tag: 3, op_type: OP_TYPE_ALU}, src_1: '{tag:4, ready:1'b1}, src_2: '{tag:10, ready:1'b0}, bmask: 4'b1100};
        
        reset_cdb;


        alu_avails = 6'b000001;  // 1 ALU available
        @(posedge clock);

        assert_slots(NUM_ENTRIES);

        if (!alu_insts[0].valid) 
            display_test_res(1);
        else 
            display_test_res(0);

        // ---------------- Test 2: Dispatch 2 ALUs, now with 2 ALUs available ----------------
        // $display("Test 2: Dispatch 2 ALUs, now with 2 ALUs available");
        test_id = 2;
        invalid_inst;
        reset_sequence;

        cdb_tag_1 = 5;
        alu_avails = 6'b000111;  // all ALUs available
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b1}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b1}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b0010};
        @(posedge clock);
        // dispatch cycle
        invalid_inst;
        @(posedge clock);
        check_issue_num(8'b00000010);

        assert_slots(NUM_ENTRIES);
        display_test_res(1);

        // ---------------- Test 3: Dispatch 2 ALUs but only 1 ALU is available ----------------
        test_id = 3;
        reset_sequence;

        alu_avails = 6'b000001;  // Only 1 ALU available
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b1}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b1}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b0010};
        @(posedge clock);
        invalid_inst;
        @(negedge clock);
        check_issue_num(8'b00000001);

        assert_slots(NUM_ENTRIES-1);
        // @(posedge clock);
        @(negedge clock);
        check_issue_num(8'b00000001);

        // @(posedge clock);
        @(negedge clock);
        check_issue_num(8'b00000000);
        @(posedge clock);

        display_test_res(1);
        // ---------------- Test 4: CDB Updates, check instruction issue ----------------
        test_id = 4;
        reset_sequence;

        alu_avails = 6'b000111;  // 3 ALU available
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b1}, src_2: '{tag:3,ready: 1'b0}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b0}, src_2: '{tag:3,ready: 1'b0}, bmask: 4'b0010};
        @(negedge clock)

        check_issue_num(8'b00000000);

        assert_slots(NUM_ENTRIES-2);
        invalid_inst;
        // @(negedge clock);

        @(negedge clock);
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b1}, src_2: '{tag:3,ready: 1'b0}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b1}, src_2: '{tag:3,ready: 1'b0}, bmask: 4'b0010};
        //try change from ready=0 to 1
        // @(negedge clock);
        @(negedge clock);
        cdb_tag_1 = 3;  // Mark src_1 as ready
        cdb_tag_2 = 4;  // Mark src_2 as ready
        @(posedge clock);
        check_issue_num(8'b00000011);

        assert_slots(NUM_ENTRIES-1);
        display_test_res(1);

        // ---------------- Test 5: Dispatch 2 ALUs and an unissued in RS, now with 3 ALUs available ----------------
        test_id = 5;
        reset_sequence;

        cdb_tag_1 = 5;
        alu_avails = 6'b000111;  // 3 ALUs available
        d_rs_packet.insts[0] = '{valid: 0, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b1}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b1}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b0010};
        @(negedge clock)
        @(posedge clock);
        check_issue_num(8'b00000001);

        assert_slots(NUM_ENTRIES);
        display_test_res(1);
        
        // ---------------- Test 6: mispredicted test ----------------
        test_id = 6;
        reset_sequence;

        alu_avails = 6'b000111;  // 3 ALUs available
        cdb_tag_1 = 2;
        cdb_tag_2 = 4;
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b0}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b0}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b0010};
        @(negedge clock);
        invalid_inst;
        reset_cdb;

        @(posedge clock);
        check_issue_num(8'b00000010);

        assert_slots(NUM_ENTRIES);
        display_test_res(1);

        // ---------------- Test 7: mispredicted test ----------------
        test_id = 7;
        reset_sequence;
        br_res_state = BR_RES_INVALID;
        alu_avails = 6'b000111;  // 3 ALUs available
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b1}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b1000};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b1}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b0011};
        @(posedge clock);
        @(negedge clock);
        d_rs_packet.insts[0].valid = 0;
        d_rs_packet.insts[1].valid = 0;
        br_res_idx = 4'b0010;
        br_res_state = BR_RES_MIS;
        @(posedge clock);
        check_issue_num(8'b00000001);

        assert_slots(NUM_ENTRIES);
        display_test_res(1);


        // ---------------- Test 8: Dispatch 8 entries and see whether it's full ----------------
        test_id = 8;
        reset_sequence;

        br_res_idx = 4'b0000;

        reset_cdb;

        alu_avails = 6'b000111;  // 3 ALUs available

        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b0}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b0}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b0010};
        @(negedge clock);
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b0}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b0}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b1010};
        @(negedge clock);
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b0}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b0}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b0011};
        @(negedge clock);
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b0}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b0}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b1110};
        @(negedge clock);
        invalid_inst;
        @(negedge clock);

        @(posedge clock);
        assert_slots(0);

        assert (spots == 2'b00) else display_test_res(0);
        display_test_res(1);
        
        test_id = 9;

        @(negedge clock);
        br_res_idx = 4'b0001;
        br_res_state = BR_RES_MIS;
        cdb_tag_1 = 2;

        @(posedge clock);
        assert_slots(5);
        check_issue_num(0);
        assert (spots == 2'b10) else display_test_res(0);
        display_test_res(1);



        // ---------------- Test 10: If branch correctly predicted, the issued inst will clear the corresponding bmask ----------------
        reset_sequence;
        
        reset_cdb;

        alu_avails = 6'b000111;  // 3 ALUs available

        br_res_state = BR_RES_INVALID;
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b0}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b0}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b0010};
        @(negedge clock);
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b0}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b0}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b1010};
        @(negedge clock);
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b0}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:6,ready: 1'b0}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b0001};
        @(negedge clock);
        d_rs_packet.insts[0] = '{valid: 1, inst: '{opcode: 4'b0001, dst_tag: 1, op_type: OP_TYPE_ALU}, src_1: '{tag:2,ready: 1'b0}, src_2: '{tag:3,ready: 1'b1}, bmask: 4'b0001};
        d_rs_packet.insts[1] = '{valid: 1, inst: '{opcode: 4'b0010, dst_tag: 2, op_type: OP_TYPE_ALU}, src_1: '{tag:4,ready: 1'b0}, src_2: '{tag:5,ready: 1'b1}, bmask: 4'b1110};
        @(negedge clock);
        invalid_inst;
        br_res_state = BR_RES_HIT;
        cdb_tag_1 = 4;
        br_res_idx = 4'b0010;

        @(posedge clock);
        test_id=10;
        check_issue_num(8'b00000011);
        assert(alu_insts[0].bmask[1]==0&&alu_insts[0].bmask[1]==0&&alu_insts[2].bmask[1]==0)else  display_test_res(0);
        display_test_res(1);

        // ---------------- Random Integrated - 1 ----------------、
        `ifdef OUTPUT_TEST
        $display("\033[1;34m------------------------------------- Random Integrated Test Begins -----------------------------------------\033[0m");
        `endif
        /*$display({"\033[1;31m!!!You should not run this if you are synthesizing. \n", 
                "To disable, define SYNTHESIZE macro (e.g., in rs_defs.svg).\033[0m"}); // it's elaboration time error, so unfortunately no way to warn the user*/
        test_id = 101;
        reset_sequence;
        reset_cdb;
        
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            entries[i].state = EMPTY;
            entries[i].src_tag_1.tag = 0;
            entries[i].src_tag_1.ready = 0;
            entries[i].src_tag_2.tag = 0;
            entries[i].src_tag_2.ready = 0;
            entries[i].bmask = 4'b0000;
        end

        @(negedge clock);
        for (int i = 0; i < 10000; i++) begin
            random_alu;
            random_cdb;
            random_resolved_br;
            d_rs_packet.insts[0] = random_alu_dis_ins();
            d_rs_packet.insts[1] = random_alu_dis_ins();
            d_rs_packet.insts[0].valid |= d_rs_packet.insts[1].valid; // the second cannot be valid if the first is not
            one_cycle_inst_gnts = $urandom_range(0, {ALU_CNT{1'b1}});
            // valid, src 1, ready 1, src 2, ready 2, bmask
            `ifdef OUTPUT_TEST
            $display("Dis inst 1 status: %0d, src_1: %0d, ready_1: %0d, src_2: %0d, ready_2: %0d, bmask: %0b", d_rs_packet.insts[0].valid, d_rs_packet.insts[0].src_1.tag, d_rs_packet.insts[0].src_1.ready, d_rs_packet.insts[0].src_2.tag, d_rs_packet.insts[0].src_2.ready, d_rs_packet.insts[0].bmask);
            $display("Dis inst 2 status: %0d, src_1: %0d, ready_1: %0d, src_2: %0d, ready_2: %0d, bmask: %0b", d_rs_packet.insts[1].valid, d_rs_packet.insts[1].src_1.tag, d_rs_packet.insts[1].src_1.ready, d_rs_packet.insts[1].src_2.tag, d_rs_packet.insts[1].src_2.ready, d_rs_packet.insts[1].bmask);
            // cdb status
            $display("CDB tag 1: %0d, tag 2: %0d", cdb_tag_1, cdb_tag_2);
            // br status
            $display("BR res idx: %0b, state: %0d", br_res_idx, br_res_state);
            // one_cycle_inst_gnts status
            $display("One cycle inst gnts: %0b", one_cycle_inst_gnts);
            `endif
            @(posedge clock);
            simulate(entries);
            @(negedge clock);
            compare_result(entries, i);
        end

        display_test_res(1);

        // ---------------- Test Completion ----------------

        $display("@@@ Passed ALL TESTS");
        $finish;
    end
endmodule
