`include "sys_defs.svh"
`include "cpuBusIF.svh"

module freelist 
#(
    parameter BR_STACK_SIZE = 4,     // Branch speculation depth
    parameter PR_COUNT = 64, 
    parameter ARCH_COUNT = 32
)
(
    cpuBusIF sys_in,
    cpuBusIF d_branch_stk_in,
    cpuBusIF cdb_branch_in,
    cpuBusIF fl_dispatch,
    cpuBusIF fl_retire
);

    logic [PR_COUNT-1:0] freelist, next_freelist;
    logic [BR_STACK_SIZE-1:0][PR_COUNT-1:0] copies, next_copies;

    // logic [PR_COUNT-1:0] dst_tags_gnt;
    logic [`DISPATCH_WIDTH-1:0][PR_COUNT-1:0] dst_tags_gnt_bus;

    logic [PR_COUNT-1:0] fl_for_sel;

    // for manual psel
    logic [PR_COUNT-1:0] psel_mask;

    always_comb begin
        next_freelist = freelist;
        next_copies = copies;
        fl_dispatch.fl_valid_tags = '0;

        dst_tags_gnt_bus = '0;

        // tag selection
        fl_for_sel = next_freelist;

        // manual psel
        for (int n = 0; n < `DISPATCH_WIDTH; n++) begin
            psel_mask = (fl_for_sel & (~(fl_for_sel - 1'b1)));
            for (int i = 0; i < PR_COUNT; i++) begin
                if (psel_mask[i]) begin
                    dst_tags_gnt_bus[n][i] = 1'b1;
                    fl_for_sel[i] = 1'b0;
                end
            end
        end

        for (int n = 0; n < `DISPATCH_WIDTH; n++) begin
            for (int i = 0; i < PR_COUNT; i++) begin
                if (dst_tags_gnt_bus[n][i]) begin
                    fl_dispatch.fl_valid_tags[n] = i;
                end
            end
        end

        // update according to dispatch logic
        for (int n = 0; n < `DISPATCH_WIDTH; n++) begin
            if (fl_dispatch.f_accepts[n]) begin
                for (int i = 0; i < PR_COUNT; i++) begin
                    if (dst_tags_gnt_bus[n][i]) begin
                        next_freelist[i] = 1'b0;
                        if (d_branch_stk_in.d_br_stk_idx_valids[n]) begin
                            next_copies[d_branch_stk_in.d_br_stk_idxs[n]] = next_freelist;
                        end
                    end
                end
            end
        end

        // retire
        // put it here to reduce latency
        for (int n = 0; n < `RETIRE_WIDTH; n++) begin
            if (fl_retire.retire_old_tags[n] != 0) begin
                next_freelist[fl_retire.retire_old_tags[n]] = 1'b1;
                for (int i = 0; i < BR_STACK_SIZE; i++) begin
                    next_copies[i][fl_retire.retire_old_tags[n]] = 1'b1;
                end
            end
        end

        // note: we can put branch res safely here, because if mispredicts,
        // there will be no dispatches
        // hopefully this reduces latency
        // branch resolution
        if (cdb_branch_in.br_res_state == BR_RES_MIS) begin
            next_freelist = next_copies[cdb_branch_in.br_res_idx];
        end
    end

    always_ff @(posedge sys_in.clock) begin
        if (sys_in.reset) begin
            // zero is NEVER available!
            // initially, first ARCH_COUNT registers are NOT available
            for (int i = 0; i < ARCH_COUNT; i++) begin
                freelist[i] <= 1'b0;
            end
            for (int i = ARCH_COUNT; i < PR_COUNT; i++) begin
                freelist[i] <= 1'b1;
            end
            copies <= '0; // left uninitialized
        end else begin
            freelist <= next_freelist;
            copies <= next_copies;
        end
    end
endmodule
