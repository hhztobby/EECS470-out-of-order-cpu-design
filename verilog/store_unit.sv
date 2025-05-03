`include "sys_defs.svh"
module store_unit (
    input DATA 		st_data_in,
    input DATA     	opa,
    input DATA    	opb,
    input TAG      	dst_tag_in,
    input BMASK    	src_bmask,
    input logic    	st_valid_in,
    input SQ_IDX 	st_pos_in,
	input MEM_SIZE  st_size_in,

	// output to store queue. 
	output   logic 								st_valid_out,
	output   MEM_BLOCK 							st_data_out,
	output   ADDR 								st_addr_out,
	output   MEM_SIZE 							st_size_out,
	output   SQ_IDX			                    st_pos_out,
	// output to cdb reg
	output CDB_REG_PACKET cdb_reg_packet,
	
	// misprediction
    input   BR_RES_STATE    mis_res_state,
    input   B_IDX           mis_branch_idx
);
    BMASK tmp_bmask;
    logic squash;

    always_comb begin
        squash = 0;
        tmp_bmask = '0;

        case (mis_res_state)
            BR_RES_HIT: tmp_bmask = src_bmask & ~mis_branch_idx;
            BR_RES_MIS: begin
                for (int i = 0; i < `BR_STK_SZ; i++) begin
                    if (mis_branch_idx[i]) begin
                        squash = src_bmask[i];
                    end
                end
            end
            default: tmp_bmask = src_bmask;
        endcase
    end
	assign st_valid_out   	= (squash ? 0 : st_valid_in);
    assign st_data_out 		=  {32'b0,st_data_in};
	assign st_addr_out 		= opa + opb;
	assign st_size_out 		= st_size_in;
	assign st_pos_out 		= st_pos_in;

	assign cdb_reg_packet.result = st_data_in;
	assign cdb_reg_packet.dst_bmask = tmp_bmask;
	assign cdb_reg_packet.valid_out   = st_valid_in;
	assign cdb_reg_packet.dst_tag_out = (squash ? 0 : dst_tag_in);
endmodule
