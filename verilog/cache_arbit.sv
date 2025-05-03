`include "sys_defs.svh"

module cache_arbit (
	cpuBusIF arbit_dcache,
	cpuBusIF arbit_load,
	cpuBusIF arbit_store
);
	// Internal signals
	logic [`STATION_SIZE-1:0] load_grant; // Grant signals for load requests
	logic       store_grant; // Grant signal for store request
	// Success outputs
	assign arbit_load.load_arbit_sent = load_grant;
	assign arbit_store.store_arbit_sent = store_grant;
	// Priority selection logic
	always_comb begin
		load_grant = 4'b0;
		store_grant = 1'b0;
		if (|arbit_load.load_arbit_valid) begin
			
			// Grant to the first load request based on priority
			casez (arbit_load.load_arbit_valid)
				4'b1???: load_grant = 4'b1000;
				4'b01??: load_grant = 4'b0100;
				4'b001?: load_grant = 4'b0010;
				4'b0001: load_grant = 4'b0001;
				default: load_grant = 4'b0;
			endcase
		end else if (arbit_store.store_arbit_valid) begin
			// Grant to the store request if no load requests
			store_grant = 1'b1;
		end
	end
	// link output to cache
	always_comb begin
		// Default values for cache outputs
		arbit_dcache.lsq_dcache_req_command = '0;
		arbit_dcache.lsq_dcache_req_data_size = '0;
		arbit_dcache.lsq_dcache_req_addr = '0;
		arbit_dcache.lsq_dcache_write_data = '0;

		if (|load_grant) begin
			// If a load request is granted, link the corresponding load signals to cache
			arbit_dcache.lsq_dcache_req_command = MEM_LOAD;
			case (load_grant)
				4'b1000: begin
					arbit_dcache.lsq_dcache_req_data_size = arbit_load.load_arbit_size[3];
					arbit_dcache.lsq_dcache_req_addr = arbit_load.load_arbit_addr[3];
				end
				4'b0100: begin
					arbit_dcache.lsq_dcache_req_data_size = arbit_load.load_arbit_size[2];
					arbit_dcache.lsq_dcache_req_addr = arbit_load.load_arbit_addr[2];
				end
				4'b0010: begin
					arbit_dcache.lsq_dcache_req_data_size = arbit_load.load_arbit_size[1];
					arbit_dcache.lsq_dcache_req_addr = arbit_load.load_arbit_addr[1];
				end
				4'b0001: begin
					arbit_dcache.lsq_dcache_req_data_size = arbit_load.load_arbit_size[0];
					arbit_dcache.lsq_dcache_req_addr = arbit_load.load_arbit_addr[0];
				end
				default: begin
					// Default case to avoid latches
					arbit_dcache.lsq_dcache_req_command = '0;
					arbit_dcache.lsq_dcache_req_data_size = '0;
					arbit_dcache.lsq_dcache_req_addr = '0;
				end
			endcase
		end else if (store_grant) begin
			// If a store request is granted, link the store signals to cache
			arbit_dcache.lsq_dcache_req_command = MEM_STORE;
			arbit_dcache.lsq_dcache_req_data_size = arbit_store.store_arbit_size;
			arbit_dcache.lsq_dcache_req_addr = arbit_store.store_arbit_addr;
			arbit_dcache.lsq_dcache_write_data = arbit_store.store_arbit_data;
		end
	end
	// link cache input to load and store. no logic needed
	assign arbit_load.load_arbit_state = arbit_dcache.dcache_lsq_req_state;
	assign arbit_load.load_arbit_alloc_tag = arbit_dcache.dcache_lsq_alloc_mshr_tag;
	assign arbit_load.load_arbit_hit_data = arbit_dcache.dcache_lsq_hit_data;
	assign arbit_load.load_arbit_broad_valid = arbit_dcache.dcache_lsq_broadcast_valid;
	assign arbit_load.load_arbit_broad_tag = arbit_dcache.dcache_lsq_broadcast_mshr_tag;
	assign arbit_load.load_arbit_broad_data = arbit_dcache.dcache_lsq_broadcast_data;

	assign arbit_store.store_arbit_state = arbit_dcache.dcache_lsq_req_state;


endmodule