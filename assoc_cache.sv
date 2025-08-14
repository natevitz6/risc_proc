`ifndef _ASSOC_CACHE_SV
`define _ASSOC_CACHE_SV

`include "system.sv"
`include "memory_io.sv"

module assoc_cache #(
    parameter int CACHE_SIZE_BYTES = 2048,
    parameter int BLOCK_SIZE_BYTES = 32,
    parameter int ASSOC           = 4
) (
    input  logic clk,
    input  logic reset,
    input  memory_io_req core_req,
    output memory_io_rsp core_rsp,
    output memory_io_req mem_req,
    input  memory_io_rsp mem_rsp
);

    // Derived parameters
    localparam int NUM_SETS       = CACHE_SIZE_BYTES / (BLOCK_SIZE_BYTES * ASSOC);
    localparam int SET_IDX_BITS   = $clog2(NUM_SETS);
    localparam int BLOCK_OFF_BITS = $clog2(BLOCK_SIZE_BYTES);
    localparam int TAG_BITS       = 32 - SET_IDX_BITS - BLOCK_OFF_BITS;
    localparam int WAY_IDX_BITS   = $clog2(ASSOC);

    typedef logic [BLOCK_OFF_BITS-1:0] block_off_t;
    typedef logic [SET_IDX_BITS-1:0]   set_idx_t;
    typedef logic [TAG_BITS-1:0]       tag_val_t;
    typedef logic [WAY_IDX_BITS-1:0]   way_idx_t;

    typedef struct packed {
        logic                 valid;
        logic                 dirty;
        tag_val_t             tag_val;
        logic [255:0]         data; // 32 bytes = 256 bits
        way_idx_t           lru;  // 2 bits for LRU (0 = MRU, 3 = LRU)
    } cache_line_t;

    cache_line_t cache [NUM_SETS][ASSOC];

    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        LOOKUP,
        MISS_WRITEBACK,
        MISS_WRITEBACK_WAIT,
        MISS_START_FILL,
        MISS_FILL_WAIT,
        MISS_FILL_DONE
    } cache_state_t;
    cache_state_t state, next_state;

    // Block fill signals
    logic [255:0] block_buffer, block_buffer_next;
    logic [2:0] word_cnt, word_cnt_next;
    logic [31:0] block_base_addr, block_base_addr_next;

    // Write-back signals
    logic [2:0] wb_word_cnt, wb_word_cnt_next;
    logic [31:0] wb_addr, wb_addr_next;
    logic wb_active, wb_active_next;

    // Core response logic
    logic core_rsp_valid_q, core_rsp_valid_d;
    logic [31:0] core_rsp_data_q, core_rsp_data_d;
    logic [31:0] core_rsp_addr_q, core_rsp_addr_d;
    logic [`user_tag_size-1:0] core_rsp_user_tag_q, core_rsp_user_tag_d;

    // Core request logic
    logic [31:0] pending_addr, pending_addr_next;
    logic [31:0] pending_data, pending_data_next;
    logic [3:0]  pending_do_write, pending_do_write_next;
    logic [`user_tag_size-1:0] pending_user_tag, pending_user_tag_next;
    logic        pending_valid, pending_valid_next;

    assign core_rsp = '{
        addr: core_rsp_addr_q,
        data: core_rsp_data_q,
        valid: core_rsp_valid_q,
        ready: 1'b1,
        dummy: 2'b00,
        user_tag: core_rsp_user_tag_q
    };

    // Memory request logic
    memory_io_req mem_req_r;
    assign mem_req = mem_req_r;

    // Address breakdown for core_req and pending_addr
    wire [BLOCK_OFF_BITS-1:0] block_off = pending_addr[BLOCK_OFF_BITS-1:0];
    wire [SET_IDX_BITS-1:0]   set_idx   = pending_addr[BLOCK_OFF_BITS + SET_IDX_BITS - 1:BLOCK_OFF_BITS];
    wire [TAG_BITS-1:0]       tag_val   = pending_addr[31:BLOCK_OFF_BITS + SET_IDX_BITS];

    // Hit/miss, LRU, and cache write signals
    logic hit;
    way_idx_t hit_way, replace_way, lru_way;

    // Cache write enables and data
    logic cache_write_en;
    logic [SET_IDX_BITS-1:0] cache_write_set;
    way_idx_t cache_write_way;
    cache_line_t cache_write_line;

    // LRU update enables and data
    way_idx_t lru_next [NUM_SETS][ASSOC];

    // Combinational logic for hit/miss, LRU, and next actions
    always_comb begin
        // Defaults
        hit = 1'b0;
        hit_way = '0;
        lru_way = '0;
        replace_way = '0;
        cache_write_en = 1'b0;
        cache_write_set = set_idx;
        cache_write_way = '0;
        cache_write_line = '0;
        wb_word_cnt_next = wb_word_cnt;
        wb_addr_next = wb_addr;
        wb_active_next = wb_active;
        pending_addr_next      = pending_addr;
        pending_data_next      = pending_data;
        pending_do_write_next  = pending_do_write;
        pending_user_tag_next  = pending_user_tag;
        pending_valid_next     = pending_valid;

        // Hit detection and block_data
        for (int i = 0; i < ASSOC; i++) begin
            if (cache[set_idx][i].valid && cache[set_idx][i].tag_val == tag_val) begin
                hit = 1'b1;
                hit_way = way_idx_t'(i);
            end
        end

        // LRU replacement
        for (int i = 0; i < ASSOC; i++) begin
            if (cache[set_idx][i].lru == way_idx_t'(ASSOC-1))
                lru_way = way_idx_t'(i);
        end
        replace_way = lru_way;

        // Default assignments for next state and outputs
        next_state = state;
        mem_req_r = memory_io_no_req;
        core_rsp_valid_d = 1'b0;
        core_rsp_data_d = 32'b0;
        core_rsp_addr_d = 32'b0;
        core_rsp_user_tag_d = core_req.user_tag;
        block_buffer_next = block_buffer;
        word_cnt_next = word_cnt;
        block_base_addr_next = block_base_addr;

        for (int s = 0; s < NUM_SETS; s++) begin
            for (int w = 0; w < ASSOC; w++) begin
                lru_next[s][w] = cache[s][w].lru;
            end
        end

        // FSM
        case (state)
            IDLE: begin
                if (core_req.valid) begin
                    next_state = LOOKUP;
                    // Save the request immediately
                    pending_addr_next      = core_req.addr;
                    pending_data_next      = core_req.data;
                    pending_do_write_next  = core_req.do_write;
                    pending_user_tag_next  = core_req.user_tag;
                    pending_valid_next     = 1'b1;
                end else begin
                    pending_valid_next = 1'b0;
                end
            end
            LOOKUP: begin
                if (hit) begin
                    // Read or write hit
                    cache_write_en = 1'b0;
                    cache_write_line = cache[set_idx][hit_way];
                    if (pending_do_write_next != 4'b0000) begin
                        cache_write_en = 1'b1;
                        cache_write_set = set_idx;
                        cache_write_way = hit_way;
                        for (int i = 0; i < 4; i++) begin
                            if (pending_do_write_next[i])
                                cache_write_line.data[block_off*8 + i*8 +: 8] = pending_data_next[i*8 +: 8];
                        end
                        cache_write_line.dirty = 1'b1;
                    end
                    // On a hit in LOOKUP state
                    for (int w = 0; w < ASSOC; w++) begin
                        if (way_idx_t'(w) == hit_way) begin
                            // MRU gets 0
                            lru_next[set_idx][w] = '0;
                        end
                        else if (cache[set_idx][w].lru < cache[set_idx][hit_way].lru) begin
                            // Ways less recently used than the hit are bumped up
                            lru_next[set_idx][w] = cache[set_idx][w].lru + 1;
                        end
                    end
                    // Respond to core
                    core_rsp_valid_d = 1'b1;
                    core_rsp_data_d = cache_write_line.data[block_off*8 +: 32];
                    core_rsp_addr_d = pending_addr_next;
                    next_state = IDLE;
                    pending_valid_next = 1'b0;
                end else begin
                    // Miss: check if replacement way is dirty
                    if (cache[set_idx][replace_way].valid && cache[set_idx][replace_way].dirty) begin
                        // Start write-back FSM
                        wb_word_cnt_next = 0;
                        wb_addr_next = {cache[set_idx][replace_way].tag_val, set_idx, {BLOCK_OFF_BITS{1'b0}}};
                        wb_active_next = 1'b1;
                        next_state = MISS_WRITEBACK;
                    end else begin
                        // No write-back needed, start block fill
                        block_buffer_next = 0;
                        word_cnt_next = 0;
                        block_base_addr_next = {pending_addr_next[31:5], 5'b0};
                        next_state = MISS_START_FILL;
                    end
                end
            end
            MISS_WRITEBACK: begin
                // Issue write for current word of dirty block
                mem_req_r = '{
                    addr: wb_addr,
                    data: cache[set_idx][replace_way].data[wb_word_cnt*32 +: 32],
                    do_read: 4'b0000,
                    do_write: 4'b1111,
                    valid: 1'b1,
                    dummy: 3'b000,
                    user_tag: pending_user_tag_next
                };
                next_state = MISS_WRITEBACK_WAIT;
            end
            MISS_WRITEBACK_WAIT: begin
                if (mem_rsp.valid) begin
                    if (wb_word_cnt < 7) begin
                        wb_word_cnt_next = wb_word_cnt + 1;
                        wb_addr_next = wb_addr + 32'd4;
                        next_state = MISS_WRITEBACK;
                    end else begin
                        // Done with write-back, start block fill
                        wb_word_cnt_next = 0;
                        wb_addr_next = 0;
                        wb_active_next = 0;
                        block_buffer_next = 0;
                        word_cnt_next = 0;
                        block_base_addr_next = {pending_addr_next[31:5], 5'b0};
                        next_state = MISS_START_FILL;
                    end
                end
            end
            MISS_START_FILL: begin
                mem_req_r = '{
                    addr: block_base_addr,
                    data: 32'b0,
                    do_read: 4'b1111,
                    do_write: 4'b0000,
                    valid: 1'b1,
                    dummy: 3'b000,
                    user_tag: pending_user_tag_next
                };
                next_state = MISS_FILL_WAIT;
            end
            MISS_FILL_WAIT: begin
                if (mem_rsp.valid) begin
                    block_buffer_next = block_buffer;
                    block_buffer_next[word_cnt*32 +: 32] = mem_rsp.data;
                    if (word_cnt < 7) begin
                        word_cnt_next = word_cnt + 1;
                        mem_req_r = '{
                            addr: block_base_addr + (32'(word_cnt_next) << 2),
                            data: 32'b0,
                            do_read: 4'b1111,
                            do_write: 4'b0000,
                            valid: 1'b1,
                            dummy: 3'b000,
                            user_tag: pending_user_tag_next
                        };
                        next_state = MISS_FILL_WAIT;
                    end else begin
                        next_state = MISS_FILL_DONE;
                    end
                end
            end
            MISS_FILL_DONE: begin
                // Fill the cache line
                cache_write_en = 1'b1;
                cache_write_set = set_idx;
                cache_write_way = replace_way;
                cache_write_line = cache[set_idx][replace_way];
                cache_write_line.valid = 1'b1;
                cache_write_line.dirty = 1'b0;
                cache_write_line.tag_val = tag_val;
                cache_write_line.data = block_buffer;
                for (int w = 0; w < ASSOC; w++) begin
                    if (way_idx_t'(w) == replace_way) begin
                        lru_next[set_idx][w] = '0;
                    end
                    else if (cache[set_idx][w].lru < cache[set_idx][replace_way].lru) begin
                        lru_next[set_idx][w] = cache[set_idx][w].lru + 1;
                    end
                end
                // If this was a write, perform the write now using pending values
                if (pending_do_write != 4'b0000) begin
                    for (int i = 0; i < 4; i++) begin
                        if (pending_do_write[i])
                            cache_write_line.data[pending_addr[4:0]*8 + i*8 +: 8] = pending_data[i*8 +: 8];
                    end
                    cache_write_line.dirty = 1'b1;
                end
                // Respond to core with the correct data (read or write)
                core_rsp_valid_d = 1'b1;
                core_rsp_data_d = cache_write_line.data[pending_addr[4:0]*8 +: 32];
                core_rsp_addr_d = pending_addr;
                core_rsp_user_tag_d = pending_user_tag;
                next_state = IDLE;
                pending_valid_next = 1'b0;
            end
            default: next_state = IDLE;
        endcase
    end

    // Sequential: update cache and state
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            core_rsp_valid_q <= 1'b0;
            for (int i = 0; i < NUM_SETS; i++)
                for (int j = 0; j < ASSOC; j++)
                    cache[i][j] = '{valid: 0, dirty: 0, tag_val: 0, data: 0, lru: way_idx_t'(j)};
            block_buffer <= 0;
            word_cnt <= 0;
            block_base_addr <= 0;
            wb_word_cnt <= 0;
            wb_addr <= 0;
            wb_active <= 0;
            core_rsp_data_q <= 0;
            core_rsp_addr_q <= 0;
            core_rsp_user_tag_q <= 0;
            pending_addr      <= 0;
            pending_data      <= 0;
            pending_do_write  <= 0;
            pending_user_tag  <= 0;
            pending_valid     <= 0;
        end else begin
            state <= next_state;
            core_rsp_valid_q <= core_rsp_valid_d;
            core_rsp_data_q <= core_rsp_data_d;
            core_rsp_addr_q <= core_rsp_addr_d;
            core_rsp_user_tag_q <= core_rsp_user_tag_d;
            block_buffer <= block_buffer_next;
            word_cnt <= word_cnt_next;
            block_base_addr <= block_base_addr_next;
            wb_word_cnt <= wb_word_cnt_next;
            wb_addr <= wb_addr_next;
            wb_active <= wb_active_next;
            pending_addr      <= pending_addr_next;
            pending_data      <= pending_data_next;
            pending_do_write  <= pending_do_write_next;
            pending_user_tag  <= pending_user_tag_next;
            pending_valid     <= pending_valid_next;
            // Write to cache if enabled
            if (cache_write_en)
                cache[cache_write_set][cache_write_way] <= cache_write_line;
            // LRU update if enabled
            for (int s = 0; s < NUM_SETS; s++) begin
                for (int w = 0; w < ASSOC; w++) begin
                    cache[s][w].lru = lru_next[s][w];
                end
            end

            // Debug output
            //$display("[CACHE] Cycle %0t | State: %0d | core_rsp: valid=%0b addr=%08x data=%08x\n",
                //$time, state, core_rsp_valid_q, core_rsp_addr_q, core_rsp_data_q);
            if (core_req.valid) begin
                $display("[CACHE_REQ] core_req.addr=%08x | tag=%d | set_idx=%d | block_off=%d\n",
                    core_req.addr,
                    core_req.addr[31:BLOCK_OFF_BITS + SET_IDX_BITS],
                    core_req.addr[BLOCK_OFF_BITS + SET_IDX_BITS - 1:BLOCK_OFF_BITS],
                    core_req.addr[BLOCK_OFF_BITS-1:0]
                );
            end
            if (core_rsp_valid_q) begin
                $display("[CACHE_RSP] core_rsp.addr=%08x | rsp_data=%08x\n",
                    core_rsp_addr_q,
                    core_rsp_data_q
                );
            end
            
        end
    end

endmodule

`endif