`include "sys_defs.svh"

module load_station (
	// Control signalq
    input  logic 						clock,reset,
	// branch resolution
	input  BR_RES_STATE 				mis_res_state,
    input  B_IDX						mis_branch_idx,
    // ports with issue
    input  DATA 						opa,opb,
    input  TAG 							dst_tag_in,
    input  BMASK 						bmask_in,
	input  logic 						src_vld,
    input  SQ_IDX						st_pos_in,
	input  MEM_SIZE						mem_size_in,
	input  logic 						is_unsigned,

	output logic 						src_rdy, 
    // Forwarding with sq
	output ADDR							addr_fwd,
	output logic 						valid_fwd,
	output SQ_IDX						st_pos_fwd,

    input  MEM_BLOCK 					data_fwd_in,
	input  LOAD_MASK					mask_fwd_in,
    // ports with cache
	output ADDR [`STATION_SIZE-1:0] 	cache_addr_out,
	output logic [`STATION_SIZE-1:0] 	cache_valid_out,
	output MEM_SIZE [`STATION_SIZE-1:0] cache_size_out,

	input  logic [`STATION_SIZE-1:0] 	cache_sent,
	input  DCACHE_LSQ_STATE 				cache_state,
	input  CACHE_TAG 						cache_alloc_tag,
	input  MEM_BLOCK 						cache_hit_data,
	input  logic 							cache_broad_valid,
	input  CACHE_TAG 						cache_broad_tag,
	input  MEM_BLOCK 						cache_broad_data,

	// ports for arbit
	output TAG [`STATION_SIZE-1:0] 		arbit_tag_out,
	input  logic [`STATION_SIZE-1:0] 	arbit_gnt,

	// ports for cdb
	output CDB_REG_PACKET [`STATION_SIZE-1:0] cdb_reg_packet
);
	LOAD_STATION_ENTRY [`STATION_SIZE-1:0]   lq,next_lq;
	ADDR tmp_addr;
	logic [`STATION_SIZE-1:0] issue_gnt,can_accept_issue,squash;
	logic fwd_all_hit;

	assign tmp_addr = opa + opb;
	`ifdef DEBUG
	assign dbg_lq = lq;
	`endif

	
	always_comb begin
		next_lq = lq;
		src_rdy = 0;
		addr_fwd = '0;
		st_pos_fwd = '0;
		valid_fwd = 0;
		cache_valid_out = '0;
		cache_addr_out = '0;
		cache_size_out = '0;
		arbit_tag_out = '0;
		cdb_reg_packet = '0;
		can_accept_issue = '0;
		fwd_all_hit = '0;
		squash = '0;

		// issue gnt logic: Determine which entries are idle or complete and grant issue to the first available one
		issue_gnt = '0; // Initialize all grants to 0
		for (int i = 0; i < `STATION_SIZE; i++) begin
			if (lq[i].state == IDLE || lq[i].state == COMPLETE) can_accept_issue[i] = 1;
		end
		casez (can_accept_issue)
				4'b1???: issue_gnt = 4'b1000;
				4'b01??: issue_gnt = 4'b0100;
				4'b001?: issue_gnt = 4'b0010;
				4'b0001: issue_gnt = 4'b0001;
				default: issue_gnt = 4'b0;
		endcase
		src_rdy = issue_gnt != 0;
		for (int i = 0; i < `STATION_SIZE; i++) begin
			case (lq[i].state)
				IDLE: begin
					if (issue_gnt[i]&&src_vld) begin
						next_lq[i].state = WAIT_FWD;
						next_lq[i].addr = tmp_addr < `MEM_SIZE_IN_BYTES ? tmp_addr : '0;
						next_lq[i].dst_tag = dst_tag_in;
						next_lq[i].bmask = bmask_in;
						next_lq[i].st_pos = st_pos_in;
						next_lq[i].mem_size = mem_size_in;
						next_lq[i].is_unsigned = is_unsigned;
						// src_rdy = 1;
					end
				end

				WAIT_FWD: begin
					// output to fwd
					valid_fwd = 1;
					addr_fwd = lq[i].addr;
					st_pos_fwd = lq[i].st_pos;
					// output to cache
					cache_valid_out[i] = 1;
					cache_addr_out[i] = lq[i].addr;
					cache_size_out[i] = lq[i].mem_size;
					// save the fwd data
					next_lq[i].data = data_fwd_in;
					next_lq[i].load_mask = mask_fwd_in;
					// check if fwd is fully hit
					case(lq[i].mem_size)
						BYTE:begin if(mask_fwd_in.byte_level[lq[i].addr[2:0]]=='b1)fwd_all_hit=1; end
						HALF:begin if(mask_fwd_in.half_level[lq[i].addr[2:1]]=='b11)fwd_all_hit=1; end
						WORD:begin if(mask_fwd_in.word_level[lq[i].addr[2]]=='b1111)fwd_all_hit=1; end
						DOUBLE:begin if(mask_fwd_in=='b11111111)fwd_all_hit=1; end
					endcase

					if(fwd_all_hit) begin
						next_lq[i].state = ARBIT;
					end 
					else if (cache_sent[i]) begin
						case(cache_state)
							DCACHE_LSQ_HIT: begin
								// Combine data from sq and cache based on mask_fwd_in
								for (int j = 0; j < 8;j++) begin
									if (next_lq[i].load_mask[j]==0) next_lq[i].data[j*8 +: 8] = cache_hit_data[j*8 +: 8]; // Use byte from cache
								end
								next_lq[i].state = ARBIT;
							end
							DCACHE_LSQ_PENDING: begin 
								next_lq[i].cache_tag = cache_alloc_tag;
								next_lq[i].state = WAIT_CACHE; 
							end
							DCACHE_LSQ_INVALID: next_lq[i].state = WAIT_SEND;
						endcase
					end else begin
						next_lq[i].state = WAIT_SEND;
					end
				end

				WAIT_SEND: begin
					cache_valid_out[i] = 1;
					cache_addr_out[i] = lq[i].addr;
					cache_size_out[i] = lq[i].mem_size;
					if (cache_sent[i]) begin
						case (cache_state)
							DCACHE_LSQ_HIT: begin
								// Combine data from sq and cache based on mask_fwd_in
								for (int j = 0; j < 8;j++) begin
									if (next_lq[i].load_mask[j]==0) next_lq[i].data[j*8 +: 8] = cache_hit_data[j*8 +: 8]; // Use byte from cache
								end
								next_lq[i].state = ARBIT;
							end
							DCACHE_LSQ_PENDING: begin 
								next_lq[i].cache_tag = cache_alloc_tag;
								next_lq[i].state = WAIT_CACHE; 
							end
							DCACHE_LSQ_INVALID: next_lq[i].state = WAIT_SEND;
						endcase
					end
				end

				WAIT_CACHE: begin
					if (cache_broad_valid && cache_broad_tag == lq[i].cache_tag) begin
						for (int j = 0; j < 8;j++) begin
							if (next_lq[i].load_mask[j]==0) next_lq[i].data[j*8 +: 8] = cache_broad_data[j*8 +: 8]; // Use byte from cache
						end
						next_lq[i].state = ARBIT;
					end
				end

				ARBIT: begin
					arbit_tag_out[i] = lq[i].dst_tag;
					if (arbit_gnt[i]) begin
						next_lq[i].state = COMPLETE;
					end
				end

				COMPLETE: begin

					case (lq[i].mem_size)
						BYTE:   begin cdb_reg_packet[i].result = {24'b0,lq[i].data.byte_level[lq[i].addr[2:0]]}; 
								if(lq[i].is_unsigned==0)  cdb_reg_packet[i].result[31:8]={(24){cdb_reg_packet[i].result[7]}};
						end
						HALF:   begin cdb_reg_packet[i].result = {16'b0,lq[i].data.half_level[lq[i].addr[2:1]]}; 
								if(lq[i].is_unsigned==0)  cdb_reg_packet[i].result[31:16]={(16){cdb_reg_packet[i].result[15]}};
						end
						WORD:   cdb_reg_packet[i].result = {lq[i].data.word_level[lq[i].addr[2]]};
						default: cdb_reg_packet[i].result = '0;
					endcase
					cdb_reg_packet[i].dst_tag_out = lq[i].dst_tag;
					cdb_reg_packet[i].valid_out = 1;
					cdb_reg_packet[i].dst_bmask = lq[i].bmask;
					
					 //{lq[i].dst_tag, cache_hit_data};
					if (src_vld&& issue_gnt[i]) begin
						next_lq[i].state = WAIT_FWD;
						next_lq[i].addr = tmp_addr < `MEM_SIZE_IN_BYTES ? tmp_addr : '0;
						next_lq[i].dst_tag = dst_tag_in;
						next_lq[i].bmask = bmask_in;
						next_lq[i].st_pos = st_pos_in;
						next_lq[i].mem_size = mem_size_in;
						next_lq[i].is_unsigned = is_unsigned;
					end else begin
						next_lq[i].state = IDLE;
						next_lq[i].st_pos = '0;
						next_lq[i].cache_tag = '0;
					end
				end

				default: next_lq[i].state = IDLE;
			endcase
			case (mis_res_state)
    		    BR_RES_HIT: begin 
					next_lq[i].bmask = next_lq[i].bmask & ~(mis_branch_idx); squash[i]=0;
					cdb_reg_packet[i].dst_bmask = lq[i].bmask& ~(mis_branch_idx);
				end
    		    BR_RES_MIS: begin
    		        for (int j = 0; j < `BR_STK_SZ; j++) begin
    		            if (mis_branch_idx[j]) begin
    		                squash[i] = next_lq[i].bmask[j];
    		            end
    		        end
					if(squash[i]) begin 
						cdb_reg_packet[i].dst_tag_out = '0;
						arbit_tag_out[i] = 0;
						next_lq[i] = '0;
					end
    		    end
				BR_RES_INVALID:squash[i]=0;
				default: squash[i]=0;
    		endcase
		end
	end

	// Sequential logic
	always_ff @(posedge clock) begin
		
		if (reset) begin
			lq <= '0;
		end else begin
			lq <= next_lq;
		end
	end


endmodule 