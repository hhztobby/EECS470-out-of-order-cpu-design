`include "sys_defs.svh"
`include "cpuBusIF.svh"
module map_table 
#(
    parameter int BR_STACK_SIZE = 4,     // Branch speculation depth, copy of map table
    parameter int PR_COUNT = 64,
    parameter int ARCH_COUNT = 32,
    // parameter PR_BITNUM = $clog2(PR_COUNT),
    localparam int BR_BITNUM = $clog2(BR_STACK_SIZE)
)
(
    cpuBusIF sys_in,
    cpuBusIF d_branch_stk_in,
    cpuBusIF etb_in,
    cpuBusIF cdb_branch_in,
    cpuBusIF mt_dispatch

    `ifdef DEBUG_SYN
    ,cpuBusIF debug_ports
    `endif
);
    TAG_PLUS [BR_STACK_SIZE - 1: 0][ARCH_COUNT-1:0] copies, next_copies; //map tables and their copies,lsb for ready bit
    TAG_PLUS [ARCH_COUNT-1:0] map_table, next_map_table; //map tables and their copies,lsb for ready bit

    `ifdef OUTPUT_MT
    logic [`BR_STK_SZ-1:0] updated_mt_indices;
    `endif

    always_comb begin
        `ifdef DEBUG_SYN
            debug_ports.dbg_mt_entries = copies[0];
            // debug_ports.dbg_mt_entries = map_table;
        `endif
        next_copies = copies;
        next_map_table = map_table;

        mt_dispatch.mt_src1_tagps = '0;
        mt_dispatch.mt_src2_tagps = '0;
        mt_dispatch.mt_dst_tags = '0;

        // process cdb
        for (int n = 0; n < `CDB_WIDTH; n++) begin
            for (int j = 0; j < ARCH_COUNT; j++) begin
                if (next_map_table[j].tag == etb_in.etb_tags[n]) begin
                    next_map_table[j].ready = 1'b1;
                end
            end
            for (int i = 0; i < BR_STACK_SIZE; i++) begin
                if (((1 << i) & etb_in.etb_bmasks[n]) == 0) begin
                    for (int j = 0; j < ARCH_COUNT; j++) begin
                        if (copies[i][j].tag == etb_in.etb_tags[n]) begin
                            next_copies[i][j].ready = 1'b1;
                        end
                    end
                end
            end
        end

        // receive tags from dispatcher
        // first update then copy
        for (int n = 0; n < `DISPATCH_WIDTH; n++) begin
            if (mt_dispatch.f_accepts[n]) begin
                // src tags
                mt_dispatch.mt_src1_tagps[n] = next_map_table[mt_dispatch.d_src1_regs[n]];
                mt_dispatch.mt_src2_tagps[n] = next_map_table[mt_dispatch.d_src2_regs[n]];
                // old dst tag
                mt_dispatch.mt_dst_tags[n] = next_map_table[mt_dispatch.d_dst_regs[n]].tag;
                // update to new dst tag
                if (mt_dispatch.d_dst_regs[n] != 0) begin
                    next_map_table[mt_dispatch.d_dst_regs[n]].tag = mt_dispatch.fl_valid_tags[n];
                    next_map_table[mt_dispatch.d_dst_regs[n]].ready = 1'b0;
                end
                // copy
                if (d_branch_stk_in.d_br_stk_idx_valids[n]) begin
                    next_copies[d_branch_stk_in.d_br_stk_idxs[n]] = next_map_table;
                end
            end
        end

        // if mis then no dispatches, so safely put it here to reduce latency
        // resolve branch
        if (cdb_branch_in.br_res_state == BR_RES_MIS) begin
            next_map_table = next_copies[cdb_branch_in.br_res_idx];
        end
    end

    always_ff @(posedge sys_in.clock) begin
        if (sys_in.reset) begin
            // Initialization
            for (int a = 0; a < ARCH_COUNT; a++) begin
                map_table[a].tag <= a;
                map_table[a].ready <= 1'b1;
            end
            for (int a = 0; a < BR_STACK_SIZE; a++) begin
                copies[a] <= '0;
            end
        end else begin
            copies <= next_copies;
            map_table <= next_map_table;
        end
    end

endmodule
