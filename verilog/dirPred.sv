`include "sys_defs.svh"
`include "cpuBusIF.svh"

module dirPred(
    input logic clock, reset,
    // recover info
    input logic is_dir_mis,
    input logic [$clog2(`BR_STK_SZ)-1:0] br_res_idx,
    input ADDR mis_inst_pc,
    input logic br_res_is_cond,
    input logic is_actual_taken,
    // prediction info
    input logic should_copy_ebr,
    input logic fetch_is_cond,
    input logic [$clog2(`BR_STK_SZ)-1:0] fetch_bindex,
    input ADDR  fetch_pc,
    // output
    output logic is_pred_taken
);

    localparam int PHT_SIZE = 1 << `BHR_SIZE;
    // gshare predictor
    // @note: we first make the prediction, then recover from the table

    logic [`BHR_SIZE-1:0] bhr, next_bhr;
    logic [`BR_STK_SZ-1:0][`BHR_SIZE-1:0] bhr_copies, next_bhr_copies;

    logic [PHT_SIZE-1:0][1:0] pht, next_pht;
    // this might not be necessary
    logic [`BR_STK_SZ-1:0][PHT_SIZE-1:0][1:0] pht_copies, next_pht_copies;

    // combinational logics
    logic [`BHR_SIZE-1:0] pht_index, recover_pht_index;

    always_comb begin
        next_bhr = bhr;
        next_pht = pht;
        next_bhr_copies = bhr_copies;
        next_pht_copies = pht_copies;
        is_pred_taken = 0;
        recover_pht_index = 0;
        // branch resolution
        // put this at the end to reduce latency
        if (is_dir_mis) begin
            // recover from the table
            next_bhr = bhr_copies[br_res_idx];
            next_pht = pht_copies[br_res_idx];
            // update the prediction table
            recover_pht_index = next_bhr ^ mis_inst_pc[`BHR_SIZE-1:0];
            if (br_res_is_cond) begin
                // update
                if (is_actual_taken && next_pht[recover_pht_index] != 2'b11) begin
                    next_pht[recover_pht_index] = next_pht[recover_pht_index] + 1;
                end else if (!is_actual_taken && next_pht[recover_pht_index] != 2'b00) begin
                    next_pht[recover_pht_index] = next_pht[recover_pht_index] - 1;
                end
                next_bhr = {next_bhr[`BHR_SIZE-2:0], is_actual_taken};
            end
        end
        pht_index = next_bhr ^ fetch_pc[`BHR_SIZE-1:0];
        // make a prediction & update registers
        if (should_copy_ebr) begin
            next_bhr_copies[fetch_bindex] = next_bhr;
            next_pht_copies[fetch_bindex] = next_pht;
        end
        if (fetch_is_cond) begin
            is_pred_taken = (next_pht[pht_index] == 2'b11) || (next_pht[pht_index] == 2'b10);
            if (is_pred_taken && next_pht[pht_index] != 2'b11) begin
                next_pht[pht_index] = next_pht[pht_index] + 1;
            end else if (!is_pred_taken && next_pht[pht_index] != 2'b00) begin
                next_pht[pht_index] = next_pht[pht_index] - 1;
            end
            next_bhr = {next_bhr[`BHR_SIZE-2:0], is_pred_taken};
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            bhr <= '0;
            pht <= '0;
            bhr_copies <= '0;
            pht_copies <= '0;
        end else begin
            bhr <= next_bhr;
            pht <= next_pht;
            bhr_copies <= next_bhr_copies;
            pht_copies <= next_pht_copies;
        end
    end

endmodule
