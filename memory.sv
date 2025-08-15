`ifndef _memory_sv
`define _memory_sv

`include "system.sv"
`include "memory_io.sv"

module memory32 #(
    parameter size = 4096                       // in bytes
    ,parameter initialize_mem = 0
    ,parameter byte0 = "data0.hex"
    ,parameter byte1 = "data1.hex"
    ,parameter byte2 = "data2.hex"
    ,parameter byte3 = "data3.hex"
    ,parameter enable_rsp_addr = 1
    ) (
    input   clk
    ,input  reset

    ,input memory_io_req32  req
    ,output memory_io_rsp32 rsp
    );

    localparam size_l2 = $clog2(size);

    // Data memory
    reg [7:0]   data0[0:size/4 - 1];
    reg [7:0]   data1[0:size/4 - 1];
    reg [7:0]   data2[0:size/4 - 1];
    reg [7:0]   data3[0:size/4 - 1];

    initial begin
        for (int i = 0; i < size/4; i++) begin
            data0[i] = 8'd0;
            data1[i] = 8'd0;
            data2[i] = 8'd0;
            data3[i] = 8'd0;
        end

        if (initialize_mem) begin
            $readmemh(byte0, data0, 0);
            $readmemh(byte1, data1, 0);
            $readmemh(byte2, data2, 0);
            $readmemh(byte3, data3, 0);
        end
    end

    always @(posedge clk) begin
        rsp <= memory_io_no_rsp32;
        if (req.valid) begin
            rsp.user_tag <= req.user_tag;
            rsp.is_vector <= req.is_vector;
            if (req.is_vector) begin
                // Vector load
                if (is_any_byte32(req.do_read)) begin
                    if (enable_rsp_addr)
                        rsp.addr <= req.addr;
                    rsp.valid <= 1'b1;
                    rsp.user_tag <= req.user_tag;
                    // Read 16 bytes (128 bits) starting at req.addr, assuming alignment
                    for (int i = 0; i < 16; i++) begin
                        int idx = (req.addr + i) >> 2;
                        int byte_offset = (req.addr + i) & 32'h3; // Fix: use 32'h3 for 32-bit width
                        case (byte_offset)
                            32'h0: rsp.vector_data[i*8 +: 8] <= data0[idx];
                            32'h1: rsp.vector_data[i*8 +: 8] <= data1[idx];
                            32'h2: rsp.vector_data[i*8 +: 8] <= data2[idx];
                            32'h3: rsp.vector_data[i*8 +: 8] <= data3[idx];
                        endcase
                    end
                end
                // Vector store
                else if (is_any_byte32(req.do_write)) begin
                    if (enable_rsp_addr)
                        rsp.addr <= req.addr;
                    rsp.valid <= 1'b1;
                    rsp.user_tag <= req.user_tag;
                    // Write 16 bytes (128 bits) starting at req.addr, assuming alignment
                    for (int i = 0; i < 16; i++) begin
                        int idx = (req.addr + i) >> 2;
                        int byte_offset = (req.addr + i) & 32'h3; // Fix: use 32'h3 for 32-bit width
                        case (byte_offset)
                            32'h0: data0[idx] <= req.vector_data[i*8 +: 8];
                            32'h1: data1[idx] <= req.vector_data[i*8 +: 8];
                            32'h2: data2[idx] <= req.vector_data[i*8 +: 8];
                            32'h3: data3[idx] <= req.vector_data[i*8 +: 8];
                        endcase
                    end
                end else begin
                    rsp.valid <= 1'b0;
                end
            end
            // Scalar (normal) access
            else begin
                if (is_any_byte32(req.do_read)) begin
                    if (enable_rsp_addr)
                        rsp.addr <= req.addr;
                    rsp.valid <= 1'b1;
                    rsp.user_tag <= req.user_tag;
                    rsp.data[7:0]   <= data0[req.addr[size_l2 - 1:2]];
                    rsp.data[15:8]  <= data1[req.addr[size_l2 - 1:2]];
                    rsp.data[23:16] <= data2[req.addr[size_l2 - 1:2]];
                    rsp.data[31:24] <= data3[req.addr[size_l2 - 1:2]];
                end else if (is_any_byte32(req.do_write)) begin
                    if (enable_rsp_addr)
                        rsp.addr <= req.addr;
                    rsp.valid <= 1'b1;
                    rsp.user_tag <= req.user_tag;
                    if (req.do_write[0]) data0[req.addr[size_l2 - 1:2]] <= req.data[7:0];
                    if (req.do_write[1]) data1[req.addr[size_l2 - 1:2]] <= req.data[15:8];
                    if (req.do_write[2]) data2[req.addr[size_l2 - 1:2]] <= req.data[23:16];
                    if (req.do_write[3]) data3[req.addr[size_l2 - 1:2]] <= req.data[31:24];
                end else begin
                    rsp.valid <= 1'b0;
                end
            end
        end
    end
    /*
    always_ff @(posedge clk) begin
        if (req.addr == 32'h2fbb0) begin
            $display("----- Cycle %0t -----", $time);
            $display("MEMORY DUMP at 0x2fbb0:");
            for (int i = 0; i < 32; i = i + 1) begin
                int idx = (32'h2fbb0 + i) >> 2;
                int byte_offset = (32'h2fbb0 + i) & 32'h3;
                byte val;
                case (byte_offset)
                    32'h0: val = data0[idx];
                    32'h1: val = data1[idx];
                    32'h2: val = data2[idx];
                    32'h3: val = data3[idx];
                endcase
                $display("  [%08x] = %02x", 32'h2fbb0 + i, val);
            end
        end
    end
    

    always_ff @(posedge clk) begin
        if (req.addr == 32'h2faf0) begin
            $display("----- Cycle %0t -----", $time);
            $display("MEMORY DUMP at 0x2faf0:");
            for (int i = 0; i < 32; i = i + 1) begin
                int idx = (32'h2faf0 + i) >> 2;
                int byte_offset = (32'h2faf0 + i) & 32'h3;
                byte val;
                case (byte_offset)
                    32'h0: val = data0[idx];
                    32'h1: val = data1[idx];
                    32'h2: val = data2[idx];
                    32'h3: val = data3[idx];
                endcase
                $display("  [%08x] = %02x", 32'h2faf0 + i, val);
            end
        end
    end
    */
endmodule


`ifdef __64bit__
`define memory memory64
`else
`define memory memory32
`endif

`endif
