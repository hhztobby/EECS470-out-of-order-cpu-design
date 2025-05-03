`include "cpuBusIF.svh"
`include "sys_defs.svh"

module icache_test;

    logic reset, clock;

    cpuBusIF bus(
        .reset(reset),
        .clock(clock),
    );

    icache dut(
        bus.sys_in,
        bus.icache
    );

    mem memory (
        // Inputs
        .clock            (clock),
        .proc2mem_command (bus.icache_mem_command),
        .proc2mem_addr    (bus.icache_mem_addr),
        .proc2mem_data    (),
// `ifndef CACHE_MODE
//         .proc2mem_size    (proc2mem_size),
// `endif
        // Outputs
        .mem2proc_transaction_tag (bus.transac_tag_icache),
        .mem2proc_data            (bus.mem_read_data),
        .mem2proc_data_tag        (bus.mem_read_data_tag)
    );

/*
    MEM_TAG                                                         transac_tag_icache;
    // MEM_TAG                                                         transac_tag_dcache;
    ADDR                                                            icache_mem_addr;
    MEM_COMMAND                                                     icache_mem_command;
    logic           [`ICACHE_READ_PORTS-1:0]                        fetch_read_valids;
    ADDR            [`ICACHE_READ_PORTS-1:0]                        fetch_read_addrs;
    logic           [`ICACHE_READ_PORTS-1:0]                        icache_hits;
    MEM_BLOCK       [`ICACHE_READ_PORTS-1:0]                        icache_fetch_datas;
*/

/*
// pf for prefetch
typedef enum logic [2:0] {
    PF_STATE_EMPTY,
    PF_STATE_WANT_REQ,
    PF_STATE_SENT_REQ,
    PF_STATE_HAS_DATA,
    PF_STATE_HIT
} PF_STATE;

typedef struct packed {
    PF_STATE state;
    MEM_TAG transac_tag;
    ADDR addr;
    MEM_BLOCK data;
} PF_ENTRY;
*/
    task automatic print_pf_buffer_status();
    `ifdef DEBUG
        foreach (dut.pf_buffer[i]) begin
            // print in eligible format, e.g., state to string
            $display("PF_ENTRY[%0d]: state=%s, transac_tag=%0d, addr=%0d, data=%0d", 
                i, 
                dut.pf_buffer[i].state == PF_STATE_EMPTY ? "PF_STATE_EMPTY" : (
                    dut.pf_buffer[i].state == PF_STATE_WANT_REQ ? "PF_STATE_WANT_REQ" : (
                        dut.pf_buffer[i].state == PF_STATE_SENT_REQ ? "PF_STATE_SENT_REQ" : (
                            dut.pf_buffer[i].state == PF_STATE_HAS_DATA ? "PF_STATE_HAS_DATA" : (
                                dut.pf_buffer[i].state == PF_STATE_HIT ? "PF_STATE_HIT" : "UNKNOWN"
                            )
                        )
                    )
                ),
                dut.pf_buffer[i].transac_tag, dut.pf_buffer[i].addr, dut.pf_buffer[i].data);
        end
        $display("\n");
    `endif
    endtask

    

    always #5 clock = ~clock; 
    always_ff @(negedge clock) begin
        print_pf_buffer_status();
    end

    int counter = 0;
    always @(posedge clock) begin
        counter++;
    end

    always_ff @(posedge clock) begin
    `ifdef DEBUG
        for (int i = 0; i < `ICACHE_READ_PORTS; i++) begin
            assert(reset || !bus.icache_hits[i] || (bus.icache_fetch_datas[i] == memory.unified_memory[bus.fetch_read_addrs[i] / 8])) else begin
                // display hit, data, and expected data
                $display("Addr[%0d]: got from cache = %0d, in memory = %0d", bus.fetch_read_addrs[i], bus.icache_fetch_datas[i], memory.unified_memory[bus.fetch_read_addrs[i] / 8]);
                $display("All datas got this cycle: ");
                for (int j = 0; j < `ICACHE_READ_PORTS; j++) begin
                    $display("Addr[%0d]: hit = %0d, got from cache = %0d, in memory = %0d", bus.fetch_read_addrs[j], bus.icache_hits[j], bus.icache_fetch_datas[j], memory.unified_memory[bus.fetch_read_addrs[j] / 8]);
                end
                $fatal("Cache read mismatch");
            end
        end
    `endif
    end


    int current_addr = 0;
    int hit_count = 0;

    initial begin
        $dumpfile("icache_test.vcd");
        $dumpvars(0);
        /*
for (uint32_t i = 0; i < cpu::MEM_64BIT_LINES; i++) {
	mem->unifiedMem[i] = std::bitset<64>(
		(
			((uint64_t)(2*i + 1)) << 32ULL
		)
		+ 2 * (uint64_t)i
	);
}
        */
        // initialize memory
        // logic [63:0] unified_memory [`MEM_64BIT_LINES-1:0];
        reset = 1;
        clock = 0;
        bus.fetch_read_valids = 0;
        bus.fetch_read_addrs = 0;

        @(posedge clock);
        @(negedge clock);
        reset = 0;
        for (int i = 0; i < 1000; i++) begin
            memory.unified_memory[i] = i;
        end

        while (counter < 1000) begin
            bus.fetch_read_valids = '1;
            bus.fetch_read_addrs[0] = current_addr;
            bus.fetch_read_addrs[1] = current_addr + 8;
            while (1) begin
                @(posedge clock);
                if (bus.icache_hits == 0) begin
                end else begin
                    for (int j = 0; j < `ICACHE_READ_PORTS; j++) begin
                        hit_count += bus.icache_hits[j];
                    end
                    break;
                end
            end
            @(negedge clock);
            for (int j = 0; j < `ICACHE_READ_PORTS; j++) begin
                current_addr += 8 * bus.icache_hits[j];
            end
            if (current_addr % 128 == 0) begin
                // current_addr = 0;
                current_addr += 32;
            end
        end

        $display("Fetches: %0d", counter * `ICACHE_READ_PORTS);
        $display("Hit count: %0d", hit_count);

        
        $finish;
    end

endmodule