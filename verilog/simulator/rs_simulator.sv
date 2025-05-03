`ifndef RS_SIMULATOR_SV
`define RS_SIMULATOR_SV

class rs_simulator #(
    parameter int NUM_ENTRIES = 8,
    parameter int ALU_CNT = 3,
    parameter int FU_CNT = 6
); 
    RS_ENTRY [NUM_ENTRIES-1:0] entries;
    logic reset;
    D_RS_PACKET d_rs_packet;
    TAG cdb_tag_1, cdb_tag_2;
    logic [FU_CNT-1:0] alu_avails, mul_avails, mem_avails, br_avails;
    B_IDX br_res_idx;
    BR_RES_STATE br_res_state;
    logic [FU_CNT-1:0] one_cycle_inst_gnts;

    // internal variables
    int alu_avail_num = 0;
    int alu_i = 0, alu_j = NUM_ENTRIES - 1;


    // outputs
    logic [$clog2(`N+1)-1:0] rs_spots;
    logic [FU_CNT-1:0] one_cycle_inst_reqs;
    ISS_INST_ALU [ALU_CNT-1:0] alu_insts;
    ISS_INST_MUL mul_inst;
    ISS_INST_MEM mem_inst;
    ISS_INST_BR br_inst;

    function new(int init_num_entries);
        reset();
        clear_comb();
    endfunction

    function clear_comb();
        rs_spots = 0;
        one_cycle_inst_reqs = '0;
        alu_insts = '0;
        mul_inst = '0;
        mem_inst = '0;
        br_inst = '0;
    endfunction

    function void reset();
        entries = '0;
    endfunction

    function void onComplete(TAG cdb_tag_1, cdb_tag_2);
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entries[i].state == DISPATCHED) begin
                entries[i].src_tag_1.ready |= (entries[i].src_tag_1.tag == cdb_tag_1 || entries[i].src_tag_1.tag == cdb_tag_2);
                entries[i].src_tag_2.ready |= (entries[i].src_tag_2.tag == cdb_tag_1 || entries[i].src_tag_2.tag == cdb_tag_2);
            end
        end
    endfunction

    function void onResolveBranch(BR_RES_STATE br_res_state, B_IDX br_res_idx);
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
    endfunction

    function void preIssue(logic [FU_CNT-1:0] alu_avails, mul_avails, mem_avails, br_avails);
        this.alu_avails = alu_avails;
        this.mul_avails = mul_avails;
        this.mem_avails = mem_avails;
        this.br_avails = br_avails;
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
    endfunction


    function logic [FU_CNT-1:0] get_cdb_arbiter_reqs();
        logic [FU_CNT-1:0] one_cycle_inst_reqs = '0;
        int n = 0;
        int i = 0, j = NUM_ENTRIES - 1;  
        for (i = 0, j = NUM_ENTRIES - 1; n > 0 && i <= j; ) begin
            for (; i <= j; j--) begin
                if (entries[j].state == DISPATCHED && (entries[j].src_tag_1.ready && entries[j].src_tag_2.ready)) begin
                    n--;
                    one_cycle_inst_reqs[j] = 1;
                    j--;
                    break;
                end
            end
            
            for (; n > 0 && i <= j; i++) begin
                if (entries[i].state == DISPATCHED && (entries[i].src_tag_1.ready && entries[i].src_tag_2.ready)) begin
                    n--;
                    one_cycle_inst_reqs[i] = 1;
                    i++;
                    break;
                end
            end
        end
        return one_cycle_inst_reqs;
    endfunction

    function void issue(one_cycle_inst_gnts);
        for (i = 0, j = NUM_ENTRIES - 1; alu_avail_num > 0 && i <= j; ) begin
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
    endfunction

    function ISS_INST_ALU [ALU_CNT-1:0] get_issued_alu();
        for (i = 0, j = NUM_ENTRIES - 1; alu_avail_num > 0 && i <= j; ) begin
            // display states of the entries, including state, src ready, and bmask
            // $display("Entry %0d: state: %0d,.src_tag_1_rd: %0d,.src_tag_2_rd: %0d, bmask: %0b", first, entries[first].state, entries[first].src_tag_1.ready, entries[first].src_tag_2.ready, entries[first].bmask);
            // $display("Entry %0d: state: %0d,.src_tag_1_rd: %0d,.src_tag_2_rd: %0d, bmask: %0b", second, entries[second].state, entries[second].src_tag_1.ready, entries[second].src_tag_2.ready, entries[second].bmask);
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
    endfunction

endclass



    begin
        int alu_avail_num = 0, alu_avail_num_backup = 0;
        int dis_valid_cnt = 0;
        int i = 0, j = NUM_ENTRIES - 1;  
        int alu_i = 0, alu_j = ALU_CNT - 1;
        int alu_i_backup, alu_j_backup;
        // 0 initialize all outputs
        rs_spots = 0;
        one_cycle_inst_reqs = 0;
        alu_insts = 0;
        mul_inst = 0;
        mem_inst = 0;
        br_inst = 0;
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

        alu_i_backup = alu_i;
        alu_j_backup = alu_j;
        alu_avail_num_backup = alu_avail_num;
        /* $display("ALU available: %0d", alu_avail_num);
        $display("Pre-issue: ");
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            $display("Entry %0d: state: %0d,.src_tag_1_rd: %0d,.src_tag_2_rd: %0d", i, entries[i].state, entries[i].src_tag_1.ready, entries[i].src_tag_2.ready);
        end*/

        // generating reqs
        `ifdef OUTPUT_TEST
        $display("alu avail num: %0d", alu_avail_num);
        `endif
        for (i = 0, j = NUM_ENTRIES - 1; alu_avail_num > 0 && i <= j; ) begin
            // display states of the entries, including state, src ready, and bmask
            // $display("Entry %0d: state: %0d,.src_tag_1_rd: %0d,.src_tag_2_rd: %0d, bmask: %0b", first, entries[first].state, entries[first].src_tag_1.ready, entries[first].src_tag_2.ready, entries[first].bmask);
            // $display("Entry %0d: state: %0d,.src_tag_1_rd: %0d,.src_tag_2_rd: %0d, bmask: %0b", second, entries[second].state, entries[second].src_tag_1.ready, entries[second].src_tag_2.ready, entries[second].bmask);
            for (; i <= j; j--) begin
                if (entries[j].state == DISPATCHED && (entries[j].src_tag_1.ready && entries[j].src_tag_2.ready)) begin
                    `ifdef OUTPUT_TEST
                    $display("Entry %0d requests fu %0d", j, alu_j);
                    `endif
                    alu_avail_num--;
                    alu_j--;
                    one_cycle_inst_reqs[alu_j+1] = 1;
                    j--;
                    break;
                end
            end
            
            for (; alu_avail_num > 0 && i <= j; i++) begin
                if (entries[i].state == DISPATCHED && (entries[i].src_tag_1.ready && entries[i].src_tag_2.ready)) begin
                    `ifdef OUTPUT_TEST
                    $display("Entry %0d requests fu %0d", i, alu_i);
                    `endif
                    alu_avail_num--;
                    alu_i++;
                    one_cycle_inst_reqs[alu_i-1] = 1;
                    i++;
                    break;
                end
            end
        end 

        alu_i = alu_i_backup;
        alu_j = alu_j_backup;
        alu_avail_num = alu_avail_num_backup;

        for (i = 0, j = NUM_ENTRIES - 1; alu_avail_num > 0 && i <= j; ) begin
            // display states of the entries, including state, src ready, and bmask
            // $display("Entry %0d: state: %0d,.src_tag_1_rd: %0d,.src_tag_2_rd: %0d, bmask: %0b", first, entries[first].state, entries[first].src_tag_1.ready, entries[first].src_tag_2.ready, entries[first].bmask);
            // $display("Entry %0d: state: %0d,.src_tag_1_rd: %0d,.src_tag_2_rd: %0d, bmask: %0b", second, entries[second].state, entries[second].src_tag_1.ready, entries[second].src_tag_2.ready, entries[second].bmask);
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
        
        // output rs spots
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entries[i].state == EMPTY) begin
                rs_spots++;
                if (rs_spots == `N) begin
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
        $display("Simulator: Dispatching %0d instructions", dis_valid_cnt);
        `endif

        for (i = 0, j = NUM_ENTRIES - 1; dis_valid_cnt > 0 && i <= j; ) begin
            for (; i <= j; j--) begin
                if (entries[j].state == EMPTY) begin
                    if (dis_valid_cnt == 2) begin
                        entries[j].state = DISPATCHED;
                        entries[j].inst = d_rs_packet.insts[1].inst;
                        entries[j].src_tag_1 = d_rs_packet.insts[1].inst.src1;
                        entries[j].src_tag_2 = d_rs_packet.insts[1].inst.src2;
                        entries[j].dst_tag = d_rs_packet.insts[1].inst.dst;
                        entries[j].bmask = d_rs_packet.insts[1].bmask;
                        entries[j].op = (d_rs_packet.insts[1].inst.cond_branch || d_rs_packet.insts[1].inst.uncond_branch) ? OP_TYPE_BR : (
                                    // (d_rs_packet.insts[1].inst.rd_mem || d_rs_packet.insts[1].inst.wr_mem) ? OP_TYPE_MEM : // no mem for now
                                            d_rs_packet.insts[1].inst.mult ? OP_TYPE_MUL : OP_TYPE_ALU
                                    );
                    end else if (dis_valid_cnt == 1) begin
                        entries[j].state = DISPATCHED;
                        entries[j].inst = d_rs_packet.insts[0].inst;
                        entries[j].src_tag_1 = d_rs_packet.insts[0].inst.src1;
                        entries[j].src_tag_2 = d_rs_packet.insts[0].inst.src2;
                        entries[j].dst_tag = d_rs_packet.insts[0].inst.dst;
                        entries[j].bmask = d_rs_packet.insts[0].bmask;
                        entries[j].op = (d_rs_packet.insts[0].inst.cond_branch || d_rs_packet.insts[0].inst.uncond_branch) ? OP_TYPE_BR : (
                                    // (d_rs_packet.insts[0].inst.rd_mem || d_rs_packet.insts[0].inst.wr_mem) ? OP_TYPE_MEM : // no mem for now
                                            d_rs_packet.insts[0].inst.mult ? OP_TYPE_MUL : OP_TYPE_ALU
                                    );
                    end
                    `ifdef OUTPUT_TEST
                    $display("Simulator: Dispatching instruction %0d to entry %0d", dis_valid_cnt - 1, j);
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
                        entries[i].src_tag_1 = d_rs_packet.insts[1].inst.src1;
                        entries[i].src_tag_2 = d_rs_packet.insts[1].inst.src2;
                        entries[i].bmask = d_rs_packet.insts[1].bmask;
                    end else if (dis_valid_cnt == 1) begin
                        entries[i].state = DISPATCHED;
                        entries[i].inst = d_rs_packet.insts[0].inst;
                        entries[i].src_tag_1 = d_rs_packet.insts[0].inst.src1;
                        entries[i].src_tag_2 = d_rs_packet.insts[0].inst.src2;
                        entries[i].bmask = d_rs_packet.insts[0].bmask;
                    end
                    `ifdef OUTPUT_TEST
                    $display("Simulator: Dispatching instruction %0d to entry %0d", dis_valid_cnt - 1, i);
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
    end
endtask

`endif