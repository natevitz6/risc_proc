`include "system.sv"
`include "base.sv"
`include "pipe_core.sv"
`include "memory.sv"
`include "memory_io.sv"
`include "block_delay.sv"
`include "assoc_cache.sv"
`include "riscv32_vector.sv"

module top(input clk, input reset, output logic halt);

// Instruction memory connections
memory_io_req inst_mem_req;
memory_io_rsp inst_mem_rsp;

// Data memory connections
memory_io_req data_mem_req_from_cache;
memory_io_rsp data_mem_rsp_to_cache;
memory_io_req data_mem_req_from_core;
memory_io_rsp data_mem_rsp_to_core;
memory_io_req data_mem_req_from_vector;
memory_io_rsp data_mem_rsp_to_vector;
memory_io_req data_mem_req_from_proc;
memory_io_rsp data_mem_rsp_to_proc;
memory_io_req data_mem_req_from_core_delay;
memory_io_rsp data_mem_rsp_to_core_delay;
memory_io_req data_mem_req_from_l1;
memory_io_rsp data_mem_rsp_to_l1;
memory_io_req data_mem_req_from_l1_delay;
memory_io_rsp data_mem_rsp_to_l1_delay;
memory_io_req data_mem_req_from_l2;
memory_io_rsp data_mem_rsp_to_l2;
memory_io_req data_mem_req;
memory_io_rsp data_mem_rsp;

// Vector interface signals
logic        vec_inst_valid;
logic [31:0] vec_inst;
logic [31:0] rs1_data;
logic [31:0] rs2_data;
logic        vec_ready;
logic [127:0] vec_result; // Adjust VLEN as needed

core core (
    .clk(clk),
    .reset(reset),
    .reset_pc(32'h0001_0000),
    .inst_mem_req(inst_mem_req),
    .inst_mem_rsp(inst_mem_rsp),
    .data_mem_req(data_mem_req_from_core),
    .data_mem_rsp(data_mem_rsp_to_core),
    // Vector interface
    .vec_inst_valid(vec_inst_valid),
    .vec_inst(vec_inst),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .vec_ready(vec_ready),
    .vec_result(vec_result)
);

riscv32_vector #(
    .VLEN(128),
    .VREGS(32),
    .ELEM_WIDTH(32)
) vector_inst (
    .clk(clk),
    .reset(reset),
    .vec_inst_valid(vec_inst_valid),
    .vec_inst(vec_inst),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .vec_ready(vec_ready),
    .vec_result(vec_result),
    .data_mem_req(data_mem_req_from_vector),
    .data_mem_rsp(data_mem_rsp_to_vector)
);

block_delay #(
    .N(1)
) core_cache_delay (
    .clk(clk),
    .reset(reset),
    .from_core(data_mem_req_from_proc),
    .to_core(data_mem_rsp_to_proc),
    .to_memory(data_mem_req_from_core_delay),
    .from_memory(data_mem_rsp_to_core_delay)
);

assoc_cache #(
    .CACHE_SIZE_BYTES(2048),
    .BLOCK_SIZE_BYTES(32),
    .ASSOC(4)
) L1_cache (
    .clk(clk),
    .reset(reset),
    .core_req(data_mem_req_from_core_delay),    // Core -> Cache
    .core_rsp(data_mem_rsp_to_core_delay),      // Cache -> Core
    .mem_req(data_mem_req_from_l1),     // L1 -> Delay
    .mem_rsp(data_mem_rsp_to_l1)        // Delay -> L1
);

block_delay #(
    .N(5)
) L1_L2_delay (
    .clk(clk),
    .reset(reset),
    .from_core(data_mem_req_from_l1),
    .to_core(data_mem_rsp_to_l1),
    .to_memory(data_mem_req_from_l1_delay),
    .from_memory(data_mem_rsp_to_l1_delay)
);

assoc_cache #(
    .CACHE_SIZE_BYTES(8192),
    .BLOCK_SIZE_BYTES(32),
    .ASSOC(8)
) L2_cache (
    .clk(clk),
    .reset(reset),
    .core_req(data_mem_req_from_l1_delay),    // L1_delay -> L2
    .core_rsp(data_mem_rsp_to_l1_delay),      // L2 -> L1_delay
    .mem_req(data_mem_req_from_l2),     // L2 -> L2_Delay
    .mem_rsp(data_mem_rsp_to_l2)        // L2_Delay -> L2
);

block_delay #(
    .N(20)
) L2_mem_delay (
    .clk(clk),
    .reset(reset),
    .from_core(data_mem_req_from_l2),
    .to_core(data_mem_rsp_to_l2),
    .to_memory(data_mem_req),
    .from_memory(data_mem_rsp)
);

/*
always_ff @(posedge clk) begin
    if (!reset && inst_mem_req.do_read != 0) begin
        //$display("[%d] inst address: %x", inst_mem_req.user_tag, inst_mem_req.addr);
    end
    if (!reset && (data_mem_req.do_read != 0 || data_mem_req.do_write != 0)) begin
        $display("[%d] data address: %x r=%x w=%x v=%x", data_mem_req.user_tag, data_mem_req.addr,
            data_mem_req.do_read, data_mem_req.do_write, data_mem_req.data );
    end
end
*/

`memory #(
    .size(32'h0001_0000)
    ,.initialize_mem(true)
    ,.byte0("code0.hex")
    ,.byte1("code1.hex")
    ,.byte2("code2.hex")
    ,.byte3("code3.hex")
    ,.enable_rsp_addr(true)
    ) code_mem (
    .clk(clk)
    ,.reset(reset)
    ,.req(inst_mem_req)
    ,.rsp(inst_mem_rsp)
    );

`memory #(
    .size(32'h0001_0000)
    ,.initialize_mem(true)
    ,.byte0("data0.hex")
    ,.byte1("data1.hex")
    ,.byte2("data2.hex")
    ,.byte3("data3.hex")
    ,.enable_rsp_addr(true)
    ) data_mem (
    .clk(clk)
    ,.reset(reset)
    ,.req(data_mem_req)
    ,.rsp(data_mem_rsp)
    );

// Arbitration state to track which module issued the last memory request
typedef enum logic [1:0] {
    MEM_IDLE,
    MEM_CORE,
    MEM_VECTOR
} mem_owner_t;

mem_owner_t mem_owner, mem_owner_next;

// Arbitration logic for data memory requests to block_delay
always_comb begin
    // Default: no request
    data_mem_req_from_proc = memory_io_no_req;
    mem_owner_next = MEM_IDLE;

    if (data_mem_req_from_core.valid) begin
        data_mem_req_from_proc = data_mem_req_from_core;
        mem_owner_next = MEM_CORE;
    end else if (data_mem_req_from_vector.valid) begin
        data_mem_req_from_proc = data_mem_req_from_vector;
        mem_owner_next = MEM_VECTOR;
    end
end

// Track which module should receive the response
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        mem_owner <= MEM_IDLE;
    end else begin
        // Only update owner when a request is issued
        if (data_mem_req_from_proc.valid)
            mem_owner <= mem_owner_next;
        // Otherwise, keep previous owner until response is received
    end
end

// Route the memory response from block_delay to the correct module
always_comb begin
    data_mem_rsp_to_core   = memory_io_no_rsp;
    data_mem_rsp_to_vector = memory_io_no_rsp;

    if (data_mem_rsp_to_proc.valid) begin
        case (mem_owner)
            MEM_CORE:   data_mem_rsp_to_core   = data_mem_rsp_to_proc;
            MEM_VECTOR: data_mem_rsp_to_vector = data_mem_rsp_to_proc;
            default:    ; // No response routed
        endcase
    end
end

/*
always_ff @(posedge clk) begin
    if (data_mem_req.valid && data_mem_req.do_write != 0)
        $display("[MEMORY] %x write: %x do_write: %x data: %x", inst_mem_req.addr, data_mem_req.addr, data_mem_req.do_write, data_mem_req.data);
    if (data_mem_req.valid && data_mem_req.do_read != 0)
        $display("[MEMORY] %x read: %x do_read:", inst_mem_req.addr, data_mem_req.addr, data_mem_req.do_read);

end
*/
always_ff @(posedge clk) begin
    if (data_mem_req_from_core.valid && data_mem_req_from_core.addr == `word_address_size'h0002_FFF8 &&
        data_mem_req_from_core.do_write != {(`word_address_size/8){1'b0}}) begin
        $write("%c", data_mem_req_from_core.data[7:0]);
    end
end

always_ff @(posedge clk) begin
    //$display("Total accesses: %d", total_accesses);
    if (data_mem_req_from_core.valid && data_mem_req_from_core.addr == `word_address_size'h0002_FFFC &&
        data_mem_req_from_core.do_write != {(`word_address_size/8){1'b0}})
        halt <= true;
end

endmodule