`include "sys_defs.svh"
module alu (
    // ports for calculation
    input DATA     opa,
    input DATA     opb,
    input ALU_FUNC alu_func,
    input TAG      dst_tag_in,
    input BMASK    src_bmask,
    input logic    valid_in,

    // ports for cdb reg packet
    output CDB_REG_PACKET cdb_reg_packet,

    // ports for early tag broadcast
    // output TAG      early_tag_out,
    
    // ports for branch misprediction
    input   BR_RES_STATE    mis_res_state,
    input   B_IDX           mis_branch_idx
);
    BMASK tmp_bmask;
    logic squash;
    
    always_comb begin
        case (alu_func)
            ALU_ADD:  cdb_reg_packet.result = opa + opb;
            ALU_SUB:  cdb_reg_packet.result = opa - opb;
            ALU_AND:  cdb_reg_packet.result = opa & opb;
            ALU_SLT:  cdb_reg_packet.result = signed'(opa) < signed'(opb);
            ALU_SLTU: cdb_reg_packet.result = opa < opb;
            ALU_OR:   cdb_reg_packet.result = opa | opb;
            ALU_XOR:  cdb_reg_packet.result = opa ^ opb;
            ALU_SRL:  cdb_reg_packet.result = opa >> opb[4:0];
            ALU_SLL:  cdb_reg_packet.result = opa << opb[4:0];
            ALU_SRA:  cdb_reg_packet.result = signed'(opa) >>> opb[4:0]; // arithmetic from logical shift
            // here to prevent latches:
            default:  cdb_reg_packet.result = 32'hfacebeec;
        endcase
    end
    assign cdb_reg_packet.dst_bmask = tmp_bmask;
    always_comb begin
        squash = 0;
        tmp_bmask = '0;
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
    assign cdb_reg_packet.dst_tag_out = (squash ? 0 : dst_tag_in) ;
    
    assign cdb_reg_packet.valid_out   = (squash ? 0 : valid_in);

endmodule // alu