`timescale 1ns/1ps
`include "sys_defs.svh"

module cache_arbit_test;

	// Parameters
	parameter LOAD_STATION_SIZE = 4;

	// DUT interface signals
	logic [LOAD_STATION_SIZE-1:0] load_valid_in;
	logic [LOAD_STATION_SIZE-1:0] load_sent_out;
	MEM_SIZE [LOAD_STATION_SIZE-1:0] load_size_in;
	ADDR [LOAD_STATION_SIZE-1:0] load_addr_in;

	DCACHE_LSQ_STATE load_state_out;
	CACHE_TAG load_alloc_tag_out;
	MEM_BLOCK load_hit_data_out;
	logic load_broad_valid_out;
	CACHE_TAG load_broad_tag_out;
	MEM_BLOCK load_broad_data_out;

	logic store_valid_in;
	logic store_sent_out;
	MEM_SIZE store_size_in;
	ADDR store_addr_in;
	MEM_BLOCK store_data_in;
	DCACHE_LSQ_STATE store_state_out;

	MEM_COMMAND cache_command_out;
	MEM_SIZE cache_size_out;
	ADDR cache_addr_out;
	MEM_BLOCK cache_data_out;

	DCACHE_LSQ_STATE cache_state_in;
	CACHE_TAG cache_alloc_tag_in;
	MEM_BLOCK cache_hit_data_in;
	logic cache_broad_valid_in;
	CACHE_TAG cache_broad_tag_in;
	MEM_BLOCK cache_broad_data_in;

	// Instantiate DUT
	cache_arbit #(
		.LOAD_STATION_SIZE(LOAD_STATION_SIZE)
	) dut (
		.cache_command_out(cache_command_out),
		.cache_size_out(cache_size_out),
		.cache_addr_out(cache_addr_out),
		.cache_data_out(cache_data_out),
		.load_valid_in(load_valid_in),
		.load_sent_out(load_sent_out),
		.load_size_in(load_size_in),
		.load_addr_in(load_addr_in),
		.load_state_out(load_state_out),
		.load_alloc_tag_out(load_alloc_tag_out),
		.load_hit_data_out(load_hit_data_out),
		.load_broad_valid_out(load_broad_valid_out),
		.load_broad_tag_out(load_broad_tag_out),
		.load_broad_data_out(load_broad_data_out),
		.store_valid_in(store_valid_in),
		.store_sent_out(store_sent_out),
		.store_size_in(store_size_in),
		.store_addr_in(store_addr_in),
		.store_data_in(store_data_in),
		.store_state_out(store_state_out),
		.cache_state_in(cache_state_in),
		.cache_alloc_tag_in(cache_alloc_tag_in),
		.cache_hit_data_in(cache_hit_data_in),
		.cache_broad_valid_in(cache_broad_valid_in),
		.cache_broad_tag_in(cache_broad_tag_in),
		.cache_broad_data_in(cache_broad_data_in)
	);

// Task to initialize all the input signals
task initialize_inputs();
	begin
		load_valid_in = '0;
		load_size_in = '0;
		load_addr_in = '0;
		store_valid_in = 1'b0;
		store_size_in = '0;
		store_addr_in = '0;
		store_data_in = '0;
		cache_state_in = '0;
		cache_alloc_tag_in = '0;
		cache_hit_data_in = '0;
		cache_broad_valid_in = 1'b0;
		cache_broad_tag_in = '0;
		cache_broad_data_in = '0;
	end
endtask

task print_sig();
	$display("load_valid_in: %b", load_valid_in);
	$display("load_sent_out: %b", load_sent_out);
	$display("store_valid_in: %b", store_valid_in);
	$display("store_sent_out: %b", store_sent_out);
	$display("cache_command_out: %b", cache_command_out);
	$display("------------------------------\n");
endtask

// Testbench variables
initial begin
	$display("Starting cache_arbit testbench...");

	// Initialize inputs
	initialize_inputs();
	load_valid_in = 4'b0101;
	store_valid_in = 1'b0;
	#1;
	$display("Test case 1:");print_sig();
	#1;
	
	initialize_inputs();
	load_valid_in = 4'b0010;
	store_valid_in = 1'b1;
	#1;
	$display("Test case 2:");print_sig();
	#1;

	initialize_inputs();
	load_valid_in = 4'b0000;
	store_valid_in = 1'b1;
	#1;
	$display("Test case 3:");print_sig();
	#1;




	$finish;
end

endmodule