`include "sys_defs.svh"
module branch (// TODO: NEED TO CONSIDER JALR JAL , make sure it works
    input DATA  rs1,
    input DATA  rs2,
    input [2:0] func, // Which branch condition to check
    input ADDR  predict_addr,
    input TAG   dst_tag_in,
    input BMASK src_bmask,
    input B_IDX branch_idx,
    input logic valid_in,
    input logic is_uncond_branch,
    // input logic is_jal,
    input logic is_jalr,
    input logic is_halt,

    // input of offset and address
    input ADDR  PC,
    input DATA  offset,// type is not certain

    // misprediction control
    input   BR_RES_STATE    mis_res_state,
    input   B_IDX           mis_branch_idx,

    // output for cdb normal packet
    output CDB_REG_PACKET cdb_reg_packet,

    // output for early tag broadcast
    // output TAG  early_tag_out,

    // output for cdb branch result packet
    output ADDR  branch_target_true_addr_out, // always the correct next pc, no matter prediction. 
    output BR_RES_STATE  branch_result_state_out, // 
    output logic branch_valid_out,
    output B_IDX branch_idx_out,
    output logic is_branch_taken_out
);
    logic tmp_take,squash;
    BMASK tmp_bmask;


    always_comb begin
        squash = 0;
        tmp_bmask = src_bmask;
        // for different br res state, we need to modify the bmask
        case (mis_res_state)
            BR_RES_HIT: tmp_bmask =src_bmask & ~(mis_branch_idx);
            BR_RES_MIS: begin
                // don't use clog2, use for loop to decode the idx
                for (int i = 0; i < `BR_STK_SZ; i++) begin
                    if (mis_branch_idx[i]) begin
                        squash = src_bmask[i];
                    end
                end
            end
            default: tmp_bmask = src_bmask;
        endcase
    end
    always_comb begin
        tmp_take = 0;
        if(is_uncond_branch) begin // unconditional
            tmp_take = `TRUE;
        end
        else if (is_halt) begin   // halt, assume no change in pc
            tmp_take = `FALSE;
        end
        else begin
        case (func)
            3'b000:  tmp_take = signed'(rs1) == signed'(rs2); // BEQ
            3'b001:  tmp_take = signed'(rs1) != signed'(rs2); // BNE
            3'b100:  tmp_take = signed'(rs1) <  signed'(rs2); // BLT
            3'b101:  tmp_take = signed'(rs1) >= signed'(rs2); // BGE
            3'b110:  tmp_take = rs1 < rs2;                    // BLTU
            3'b111:  tmp_take = rs1 >= rs2;                   // BGEU
            default: tmp_take = `FALSE;
        endcase
        end

        branch_target_true_addr_out = PC + (tmp_take ? signed'(offset) : 4);
        if (is_jalr) begin
            branch_target_true_addr_out = (rs1 + signed'(offset)) & 32'hFFFFFFFE;
        end
    end

    assign cdb_reg_packet.dst_tag_out = (squash ? 0 : dst_tag_in);
    assign cdb_reg_packet.result = is_uncond_branch ? PC + 4 : 0;
    assign cdb_reg_packet.valid_out = (squash ? 0 : valid_in);
    assign cdb_reg_packet.dst_bmask = tmp_bmask;

    assign branch_valid_out = cdb_reg_packet.valid_out;
    assign branch_idx_out = branch_idx;
    assign branch_result_state_out = ((!valid_in||is_halt||squash)? BR_RES_INVALID :(branch_target_true_addr_out==predict_addr)?BR_RES_HIT:BR_RES_MIS);
    assign is_branch_taken_out = valid_in & tmp_take;
    // if this is halt, then the branch result is invalid
endmodule // conditional_branch
