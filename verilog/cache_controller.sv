`include "sys_defs.svh"
`include "cpuBusIF.svh"

module cache_controller(
    cpuBusIF sys,
    cpuBusIF bus
);

    logic n_icache_granted, n_dcache_granted;

    always_comb begin
        // always prioritize dcache
        bus.transac_tag_icache = 0;
        bus.transac_tag_dcache = 0;
        bus.cache_mem_addr = 0;
        bus.cache_mem_command = MEM_NONE;
        bus.cache_mem_write_data = 0;
        n_icache_granted = 0;
        n_dcache_granted = 0;

        // requests to memory
        if (bus.dcache_mem_command != MEM_NONE) begin
            bus.cache_mem_addr = bus.dcache_mem_addr;
            bus.cache_mem_command = bus.dcache_mem_command;
            bus.cache_mem_write_data = bus.dcache_mem_write_data;
            n_dcache_granted = 1;
        end else if (bus.icache_mem_command != MEM_NONE) begin
            bus.cache_mem_addr = bus.icache_mem_addr;
            bus.cache_mem_command = bus.icache_mem_command;
            n_icache_granted = 1;
        end

        // feedback to caches
        if (n_icache_granted) begin
            bus.transac_tag_icache = bus.mem_transac_tag;
        end else if (n_dcache_granted) begin
            bus.transac_tag_dcache = bus.mem_transac_tag;
        end
    end

endmodule
