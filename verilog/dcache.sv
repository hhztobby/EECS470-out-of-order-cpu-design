`include "sys_defs.svh"
`include "cpuBusIF.svh"

module dcache(
    cpuBusIF sys,
    cpuBusIF bus,
    output logic writeback_clear,
    output logic [`DCACHE_LINES-1:0][$bits(MEM_BLOCK)-1:0] dcache_mem_out,
    output DCACHE_TAG [`DCACHE_LINES-1:0] dcache_tags_out
);

    localparam MSHR_SIZE_BITS = $clog2(`MSHR_SIZE);
    // index of the MSHR
    typedef logic [MSHR_SIZE_BITS-1:0] MSHR_TAG;

    // --------------------- MemDP definitions ---------------------
    logic     [`DCACHE_INDEX_BITS-1:0]  memDP_read_index;
    logic                               memDP_write_valid;
    logic     [`DCACHE_INDEX_BITS-1:0]  memDP_write_index;
    MEM_BLOCK                           memDP_write_data;
    // memDP out
    MEM_BLOCK                           memDP_read_data;

    memDP #(
        .WIDTH     ($bits(MEM_BLOCK)),
        .DEPTH     (`DCACHE_LINES),
        .READ_PORTS(1),
        .BYPASS_EN (0))
    dcache_mem (
        .clock(sys.clock),
        .reset(sys.reset),
        .re   (1'b1),
        .raddr(memDP_read_index),
        .rdata(memDP_read_data),
        .we   (memDP_write_valid),
        .waddr(memDP_write_index),
        .wdata(memDP_write_data),
        .memData_out(dcache_mem_out)
    );

    // --------------------- memory requests ---------------------
    logic mshr_mem_req_valid, n_mshr_mem_req_valid;
    MSHR_TAG req_mshr_index, n_req_mshr_index;
    MEM_COMMAND req_mem_command, n_req_mem_command;
    MEM_BLOCK req_mem_write_data, n_req_mem_write_data;
    ADDR req_mem_addr, n_req_mem_addr;

    // --------------------- state registers ---------------------
    DCACHE_TAG [`DCACHE_LINES-1:0] dcache_tags, next_dcache_tags;
    MSHR_ENTRY [`MSHR_SIZE-1:0] mshr, next_mshr;

    assign dcache_tags_out = dcache_tags;

    // --------------------- combinational variables ---------------------
    // lsq
    logic [31:0] aligned_lsq_req_addr;
    MEM_BLOCK aligned_lsq_write_data;
    logic [63:0] aligned_lsq_write_data_mask;
    logic is_lsq_req_cache_hit, is_lsq_req_mshr_hit;
    // logic is_writing_to_memdp;
    // allocating mshr
    logic [`MSHR_SIZE-1:0] empty_mshr_bits, first_empty_mshr_bits;
    logic [`MSHR_SIZE-1:0] has_data_mshr_bits, first_has_data_mshr_bits;
    logic [`MSHR_SIZE-1:0] want_req_mshr_bits, first_want_req_mshr_bits;

    // --------------------- helper functions ---------------------
    function void alignData(
        input logic [31:0] addr,
        input MEM_BLOCK data,
        input MEM_SIZE size,
        output logic [31:0] aligned_addr,
        output MEM_BLOCK aligned_data,
        output MEM_BLOCK data_mask);
        aligned_data = '0;
        data_mask = '0;
        aligned_addr = {addr[31:3], 3'b0};
        case (size)
            BYTE: begin
                aligned_data.byte_level[addr[2:0]] = data.byte_level[0];
                data_mask.byte_level[addr[2:0]] = 8'hFF;
            end
            HALF: begin
                aligned_data.half_level[addr[2:1]] = data.half_level[0];
                data_mask.half_level[addr[2:1]] = 16'hFFFF;
            end
            WORD: begin
                aligned_data.word_level[addr[2]] = data.word_level[0];
                data_mask.word_level[addr[2]] = 32'hFFFFFFFF;
            end
            DOUBLE: begin
                aligned_data.dbbl_level = data;
                data_mask = 64'hFFFFFFFFFFFFFFFF;
            end
        endcase
    endfunction

    assign bus.dcache_mem_addr = req_mem_addr;
    assign bus.dcache_mem_command = req_mem_command;
    assign bus.dcache_mem_write_data = req_mem_write_data;

    always_comb begin
        // outputs
        n_req_mem_addr = '0;
        n_req_mem_command = MEM_NONE;
        n_req_mem_write_data = '0; 
        bus.dcache_lsq_req_state = DCACHE_LSQ_INVALID;
        bus.dcache_lsq_alloc_mshr_tag = '0;
        bus.dcache_lsq_hit_data = '0;
        bus.dcache_lsq_broadcast_valid = 1'b0;
        bus.dcache_lsq_broadcast_mshr_tag = '0;
        bus.dcache_lsq_broadcast_data = '0;
        writeback_clear = 1'b1;
        // memory requests
        // memDP inputs
        memDP_read_index = '0;
        memDP_write_valid = 1'b0;
        memDP_write_index = '0;
        memDP_write_data = '0;
        // state registers
        next_dcache_tags = dcache_tags;
        next_mshr = mshr;
        n_mshr_mem_req_valid = 1'b0;
        n_req_mshr_index = '0;
        // combinational variables
        is_lsq_req_cache_hit = 1'b0;
        is_lsq_req_mshr_hit = 1'b0;
        // is_writing_to_memdp = 1'b0;
        // is_evict_writing_to_mem = 1'b0;
        empty_mshr_bits = '0;
        first_empty_mshr_bits = '0;

        aligned_lsq_req_addr = '0;
        aligned_lsq_write_data = '0;
        aligned_lsq_write_data_mask = '0;

        has_data_mshr_bits = '0;
        first_has_data_mshr_bits = '0;
        want_req_mshr_bits = '0;
        first_want_req_mshr_bits = '0;

        alignData(
            bus.lsq_dcache_req_addr,
            bus.lsq_dcache_write_data,
            bus.lsq_dcache_req_data_size,
            aligned_lsq_req_addr,
            aligned_lsq_write_data,
            aligned_lsq_write_data_mask
        );

        for (int i = 0; i < `MSHR_SIZE; i++) begin
            if (mshr[i].state != MSHR_EMPTY || bus.lsq_dcache_req_command == MEM_STORE) begin
                writeback_clear &= 0;
            end
        end

    // --------------------- process memory feedbacks ---------------------
        if (bus.mem_read_data_tag != 0) begin
            // check if the tag is in the MSHR
            for (int i = 0; i < `MSHR_SIZE; i++) begin
                if (next_mshr[i].transac_tag == bus.mem_read_data_tag && 
                    next_mshr[i].state == MSHR_SENT_REQ) begin
                    next_mshr[i].state = MSHR_HAS_DATA;
                    // bytewise forwarding
                    for (int j = 0; j < 64; j++) begin
                        if (next_mshr[i].data_mask[j] == 1'b0) begin
                            next_mshr[i].data.dbbl_level[j] = bus.mem_read_data[j];
                            next_mshr[i].data_mask[j] = 1'b1;
                        end
                    end
                    // broadcast to lsq
                    bus.dcache_lsq_broadcast_valid = 1'b1;
                    bus.dcache_lsq_broadcast_mshr_tag = i;
                    bus.dcache_lsq_broadcast_data = next_mshr[i].data;
                end
            end
        end

        if (bus.transac_tag_dcache != 0 && mshr_mem_req_valid) begin
            next_mshr[req_mshr_index].state = MSHR_SENT_REQ;
            next_mshr[req_mshr_index].transac_tag = bus.transac_tag_dcache;
        end

    // --------------------- process lsq requests ---------------------
        // reject any invalid request - we assume this is on a mispredicted path
        if (bus.lsq_dcache_req_command != MEM_NONE && bus.lsq_dcache_req_addr < `MEM_SIZE_IN_BYTES) begin
            // check if it hits in cache
            // currently direct mapped
            if (next_dcache_tags[bus.lsq_dcache_req_addr[7:3]].valid && 
                next_dcache_tags[bus.lsq_dcache_req_addr[7:3]].tag == bus.lsq_dcache_req_addr[15:8]) begin
                bus.dcache_lsq_req_state = DCACHE_LSQ_HIT;
                is_lsq_req_cache_hit = 1'b1;
                memDP_read_index = bus.lsq_dcache_req_addr[7:3];
                bus.dcache_lsq_hit_data = memDP_read_data;
                if (bus.lsq_dcache_req_command == MEM_STORE) begin
                    // is_writing_to_memdp = 1'b1;
                    memDP_write_valid = 1'b1;
                    memDP_write_index = bus.lsq_dcache_req_addr[7:3];
                    memDP_write_data = 
                        (aligned_lsq_write_data & aligned_lsq_write_data_mask) |
                        (memDP_read_data & ~aligned_lsq_write_data_mask);
                    // evict a line
		    // don't have to evict!
                    /*if (next_dcache_tags[bus.lsq_dcache_req_addr[7:3]].valid &&
                        next_dcache_tags[bus.lsq_dcache_req_addr[7:3]].dirty) begin
                        // write to memory
                        // prioritize writing to memory, since we don't yet have a write buffer
                        // is_evict_writing_to_mem = 1'b1;
                        // since direct mapped, write back addr is just request addr
                        n_req_mem_addr = {bus.lsq_dcache_req_addr[31:3], 3'b0};
                        n_req_mem_command = MEM_STORE;
                        n_req_mem_write_data = memDP_read_data;
                    end*/
                    next_dcache_tags[bus.lsq_dcache_req_addr[7:3]].dirty = 1'b1;
                end
            end
            // check if it hits in MSHR
            for (int i = 0; i < `MSHR_SIZE; i++) begin
                if (next_mshr[i].addr[15:3] == bus.lsq_dcache_req_addr[15:3] && 
                    next_mshr[i].state != MSHR_EMPTY) begin
                    is_lsq_req_mshr_hit = 1'b1;
                    // overwrite data in mshr
                    if (bus.lsq_dcache_req_command == MEM_STORE) begin
                        next_mshr[i].data = 
                            ((aligned_lsq_write_data & aligned_lsq_write_data_mask) |
                            (next_mshr[i].data & ~aligned_lsq_write_data_mask));
                        next_mshr[i].dirty = 1'b1;
                        next_mshr[i].data_mask |= aligned_lsq_write_data_mask;
                    end
                    if (next_mshr[i].state == MSHR_HAS_DATA) begin
                        bus.dcache_lsq_req_state = DCACHE_LSQ_HIT;
                        bus.dcache_lsq_hit_data = next_mshr[i].data;
                    end else begin
                        bus.dcache_lsq_req_state = DCACHE_LSQ_PENDING;
                        bus.dcache_lsq_alloc_mshr_tag = i;
                    end
                end
            end
            // needs a new MSHR entry
            if (!is_lsq_req_cache_hit && !is_lsq_req_mshr_hit) begin
                // check if there is a free MSHR entry
                for (int i = 0; i < `MSHR_SIZE; i++) begin
                    empty_mshr_bits[i] = (next_mshr[i].state == MSHR_EMPTY);
                end
                if (empty_mshr_bits == 0) begin
                    // structural hazard
                    bus.dcache_lsq_req_state = DCACHE_LSQ_INVALID;
                end else begin
                    bus.dcache_lsq_req_state = DCACHE_LSQ_PENDING;
                    first_empty_mshr_bits = empty_mshr_bits & ~(empty_mshr_bits - 1);
                    for (int i = 0; i < `MSHR_SIZE; i++) begin
                        if (first_empty_mshr_bits[i] == 1'b1) begin
                            next_mshr[i] = {
                                MSHR_WANT_REQ,
                                4'b0, // dummy tag
                                aligned_lsq_req_addr,
                                bus.lsq_dcache_req_command == MEM_STORE ? aligned_lsq_write_data_mask : 64'b0,
                                bus.lsq_dcache_req_command == MEM_STORE ? aligned_lsq_write_data : 64'b0,
                                bus.lsq_dcache_req_command == MEM_STORE // dirty bit
                            };
                            bus.dcache_lsq_alloc_mshr_tag = i;
                        end
                    end
                end
            end
        end
    // ---------------------- requests to memory and memDP ---------------------
        for (int i = 0; i < `MSHR_SIZE; i++) begin
            has_data_mshr_bits[i] = (next_mshr[i].state == MSHR_HAS_DATA);
            want_req_mshr_bits[i] = (next_mshr[i].state == MSHR_WANT_REQ);
        end
        // put entries with state has_data to memDP
        // @TODO: optimize this, say a load has hit in cache, and 
        // the mshr is not dirty - in this case we should be able to proceed
        if (~is_lsq_req_cache_hit) begin
            first_has_data_mshr_bits = has_data_mshr_bits & ~(has_data_mshr_bits - 1);
            for (int i = 0; i < `MSHR_SIZE; i++) begin
                if (first_has_data_mshr_bits[i] == 1'b1) begin
                    next_mshr[i].state = MSHR_EMPTY;
                    memDP_read_index = next_mshr[i].addr[7:3];
                    memDP_write_valid = 1'b1;
                    memDP_write_index = next_mshr[i].addr[7:3];
                    memDP_write_data = next_mshr[i].data;
                    // evict to memory
                    if (next_dcache_tags[next_mshr[i].addr[7:3]].valid &&
                        next_dcache_tags[next_mshr[i].addr[7:3]].dirty) begin
                        // write to memory
                        // prioritize writing to memory, since we don't yet have a write buffer
                        // is_evict_writing_to_mem = 1'b1;
                        // since direct mapped, write back addr is just request addr
                        n_req_mem_addr = {16'b0, next_dcache_tags[next_mshr[i].addr[7:3]].tag, next_mshr[i].addr[7:3], 3'b0};
                        n_req_mem_command = MEM_STORE;
                        n_req_mem_write_data = memDP_read_data;
                    end
                    // set the tag
                    next_dcache_tags[next_mshr[i].addr[7:3]].valid = 1'b1;
                    next_dcache_tags[next_mshr[i].addr[7:3]].tag = next_mshr[i].addr[15:8];
                    next_dcache_tags[next_mshr[i].addr[7:3]].dirty = next_mshr[i].dirty;
                end
            end
        end
        // send a new request to memory
        first_want_req_mshr_bits = want_req_mshr_bits & ~(want_req_mshr_bits - 1);
        if (n_req_mem_command == MEM_NONE) begin
            for (int i = 0; i < `MSHR_SIZE; i++) begin
                if (first_want_req_mshr_bits[i] == 1'b1) begin
                    n_req_mem_addr = {next_mshr[i].addr[31:3], 3'b0};
                    n_req_mem_command = MEM_LOAD;
                    n_mshr_mem_req_valid = 1'b1;
                    n_req_mshr_index = i;
                end
            end
        end
    end // always_comb

    always_ff @(posedge sys.clock) begin
        if (sys.reset) begin
            dcache_tags <= '0;
            mshr <= '0;
            mshr_mem_req_valid <= 1'b0;
            req_mshr_index <= '0;
            req_mem_command <= MEM_NONE;
            req_mem_addr <= '0;
            req_mem_write_data <= '0;
        end else begin
            dcache_tags <= next_dcache_tags;
            mshr <= next_mshr;
            mshr_mem_req_valid <= n_mshr_mem_req_valid;
            req_mshr_index <= n_req_mshr_index;
            req_mem_command <= n_req_mem_command;
            req_mem_addr <= n_req_mem_addr;
            req_mem_write_data <= n_req_mem_write_data;
        end
    end

endmodule
