`include "sys_defs.svh"

module sq  (
	cpuBusIF sys_in,
	cpuBusIF sq_disp,
	cpuBusIF sq_rs,
	cpuBusIF sq_fu_store,
	cpuBusIF cdb_branch_in,
	cpuBusIF sq_fu_fwd,
	// you can only retire one store at a time. 
	cpuBusIF sq_rob_retire,
	cpuBusIF sq_cache
);
	SQ_ENTRY [`SQ_SZ-1:0] sq,next_sq;
	SQ_IDX		head,tail,next_head,next_tail;
	logic    [`BR_STK_SZ-1:0][`SQ_IDX_WIDTH-1:0]     tail_stack, next_tail_stack;
	logic    [$clog2(`SQ_SZ+1)-1:0]		count,next_count,tmp_count;
	logic    							can_issue_status;
	SQ_IDX		idx;

	assign tmp_count=count- sq_rob_retire.retire_store_success;
	assign sq_disp.sq_available_cnt = `SQ_SZ-1 - tmp_count;
	assign sq_disp.sq_tail_for_disp = tail;

	always_comb begin
		next_sq=sq;
		next_head=head;
		next_tail=tail;
		next_count=count;
		// initial memory port
		sq_cache.store_arbit_addr=0;
		sq_cache.store_arbit_valid=0;
		sq_cache.store_arbit_size=0;
		sq_cache.store_arbit_data=0;
		
		can_issue_status = 1;
		sq_rs.can_issue=0;
		next_tail_stack = tail_stack;
		// initial load return 
		sq_fu_fwd.fwd_data_return= 0;
		sq_fu_fwd.fwd_data_return_mask = 0;
		sq_rob_retire.retire_store_success = 0;

		// misprediction
		if (cdb_branch_in.br_res_state == BR_RES_MIS) begin
    	    next_tail=tail_stack[cdb_branch_in.br_res_idx];
    	    next_count = (next_tail >= next_head) ? next_tail - next_head : `SQ_SZ - next_head + next_tail;
    	end 

		// retire
		if(sq_rob_retire.retire_store && sq[next_head].addr_calculated && next_count > 0) begin
			sq_cache.store_arbit_addr = sq[next_head].addr;
			sq_cache.store_arbit_valid = 1;
			sq_cache.store_arbit_size = sq[next_head].size;
			sq_cache.store_arbit_data = sq[next_head].data_store;
			
			sq_rob_retire.retire_store_success = sq_cache.store_arbit_sent && (sq_cache.store_arbit_state != DCACHE_LSQ_INVALID);
			if(sq_rob_retire.retire_store_success) begin
				next_sq[next_head].addr_calculated=0;
				next_head = (next_head+1)%`SQ_SZ;
				next_count = next_count - 1;
			end
		end

		// finish execute
		if(sq_fu_store.st_sq_valid) begin
			next_sq[sq_fu_store.st_sq_pos].addr_calculated = 1;
			next_sq[sq_fu_store.st_sq_pos].data_store = sq_fu_store.st_sq_data;
			next_sq[sq_fu_store.st_sq_pos].addr = sq_fu_store.st_sq_addr;
			next_sq[sq_fu_store.st_sq_pos].size = sq_fu_store.st_sq_size;
		end

		// byte wise forwarding
		if(sq_fu_fwd.fwd_valid) begin
			for(int i=0; i<`SQ_SZ; i=i+1) begin
				idx=(i+next_head)%`SQ_SZ;
				if(sq_fu_fwd.fwd_pos==idx)break;
				if(sq[idx].addr_calculated && sq[idx].addr[31:3] == sq_fu_fwd.fwd_addr[31:3]) begin
					case (sq[idx].size)
						DOUBLE: begin sq_fu_fwd.fwd_data_return= sq[idx].data_store;
								sq_fu_fwd.fwd_data_return_mask = 8'b11111111; end
						BYTE: 	begin
								sq_fu_fwd.fwd_data_return.byte_level[sq[idx].addr[2:0]] = sq[idx].data_store[7:0];
								sq_fu_fwd.fwd_data_return_mask.byte_level[sq[idx].addr[2:0]] = 1'b1;
						end
						HALF: 	begin 
								sq_fu_fwd.fwd_data_return.half_level[sq[idx].addr[2:1]] = sq[idx].data_store[15:0];
								sq_fu_fwd.fwd_data_return_mask.half_level[sq[idx].addr[2:1]] = 2'b11;
						end
						WORD: 	begin
								sq_fu_fwd.fwd_data_return.word_level[sq[idx].addr[2]] = sq[idx].data_store[31:0];
								sq_fu_fwd.fwd_data_return_mask.word_level[sq[idx].addr[2]] = 4'b1111;
						end
						
					endcase
				end
			end
		end

		// dispatch
		for(int i=0; i<`DISPATCH_WIDTH; i=i+1) begin
			if(sq_disp.is_store[i]) begin
				next_sq[next_tail] = '0;
				next_tail = (next_tail+1)%`SQ_SZ;
				next_count = next_count + 1;
			end
			else if(sq_disp.d_br_stk_idx_valids[i]) begin
				next_tail_stack[sq_disp.d_br_stk_idxs[i]] = next_tail;
			end
		end

		// tell rs whether can issue 
		sq_rs.can_issue[next_head] = 1;
		for(int i=0; i<`SQ_SZ-1; i=i+1) begin
			if(can_issue_status==1 && next_sq[(i+next_head)%`SQ_SZ].addr_calculated==0) can_issue_status = 0;
			sq_rs.can_issue[(i+next_head+1)%`SQ_SZ] = can_issue_status;
		end

	end


	always_ff @(posedge sys_in.clock) begin
		if(sys_in.reset) begin
			sq <= '{default:0};
			head <= 0;
			tail <= 0;
			count <= 0;
			tail_stack <= '{default:0};
		end
		else begin
			// update head and tail
			head <= next_head;
			tail <= next_tail;
			sq <= next_sq;
			count <= next_count;
			tail_stack <= next_tail_stack;
		end
	end

endmodule
