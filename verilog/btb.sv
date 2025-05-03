`include "sys_defs.svh"
`include "cpuBusIF.svh"

module btb(
    input logic clock, reset,
    input logic is_br_resolved_taken,
    input ADDR br_inst_pc,
    input ADDR br_target_pc,
    input ADDR fetch_pc,
    output ADDR pred_target_pc
);

    localparam int BTB_SIZE = 1 << `BTB_BIT_NUM;

    BTB_ENTRY [BTB_SIZE-1:0] entries, next_entries;

    always_comb begin
        next_entries = entries;
        pred_target_pc = fetch_pc + 4;
        
        // prediction
        if (entries[fetch_pc[`BTB_BIT_NUM-1:0]].valid) begin
            pred_target_pc = entries[fetch_pc[`BTB_BIT_NUM-1:0]].target;
        end

        // branch resolution
        if (is_br_resolved_taken) begin
            next_entries[br_inst_pc[`BTB_BIT_NUM-1:0]].valid = 1;
            next_entries[br_inst_pc[`BTB_BIT_NUM-1:0]].target = br_target_pc;
        end
    end

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            entries <= '0;
        end else begin
            entries <= next_entries;
        end
    end

endmodule
