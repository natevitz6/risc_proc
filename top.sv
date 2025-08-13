`include "system.sv"
`include "base.sv"
`include "pipe_core.sv"
`include "memory.sv"
`include "memory_io.sv"
`include "block_delay.sv"
`include "assoc_cache.sv"
/*
`include "sequential_prefetcher.sv"
`include "stride_prefetcher.sv"
`include "correlation_prefetcher.sv"
*/
module top(input clk, input reset, output logic halt);

// Instruction memory connections
memory_io_req inst_mem_req;
memory_io_rsp inst_mem_rsp;

// Data memory connections
memory_io_req data_mem_req_from_cache;
memory_io_rsp data_mem_rsp_to_cache;
memory_io_req data_mem_req_from_core;
memory_io_rsp data_mem_rsp_to_core;
memory_io_req data_mem_req_from_pf;
memory_io_rsp data_mem_rsp_to_pf;
memory_io_req data_mem_req;
memory_io_rsp data_mem_rsp;

core core (
    .clk(clk),
    .reset(reset),
    .reset_pc(32'h0001_0000),
    .inst_mem_req(inst_mem_req),
    .inst_mem_rsp(inst_mem_rsp),
    .data_mem_req(data_mem_req_from_core),
    .data_mem_rsp(data_mem_rsp_to_core)
);


assoc_cache assoc_cache (
    .clk(clk),
    .reset(reset),
    .core_req(data_mem_req_from_core),    // Core -> Cache
    .core_rsp(data_mem_rsp_to_core),      // Cache -> Core
    .mem_req(data_mem_req),       // Cache -> Memory
    .mem_rsp(data_mem_rsp)      // Memory -> Cache
);

/*
block_delay #(
    .N(3)
) delay (
    .clk(clk),
    .reset(reset),
    .from_core(data_mem_req_from_cache),
    .to_core(data_mem_rsp_to_cache),
    .to_memory(data_mem_req),
    .from_memory(data_mem_rsp)
);


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


/*
always_ff @(posedge clk) begin
    if (data_mem_req.valid && data_mem_req.do_write != 0)
        $display("%x write: %x do_write: %x data: %x", inst_mem_req.addr, data_mem_req.addr, data_mem_req.do_write, data_mem_req.data);
    if (data_mem_req.valid && data_mem_req.do_read != 0)
        $display("%x read: %x do_read:", inst_mem_req.addr, data_mem_req.addr, data_mem_req.do_read);

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
