`ifndef _RISCV32_VECTOR_SV
`define _RISCV32_VECTOR_SV

`include "riscv32_common.sv"

// Enum for supported vector operations (expand as needed)
typedef enum logic [3:0] {
    VOP_NONE   = 4'd0,
    VOP_VADD   = 4'd1,
    VOP_VSUB   = 4'd2,
    VOP_VAND   = 4'd3,
    VOP_VOR    = 4'd4,
    VOP_VXOR   = 4'd5,
    VOP_VLOAD  = 4'd6,
    VOP_VSTORE = 4'd7
    // Add more as needed
} vec_op_t;

// funct6 field per RVV spec (bits 31:26)
typedef enum logic [5:0] {
    VF6_VADD   = 6'b000000,
    VF6_VSUB   = 6'b000010,
    VF6_VAND   = 6'b001001,
    VF6_VOR    = 6'b001010,
    VF6_VXOR   = 6'b001011
    // Extend as needed for more RVV ops
} vec_funct6_t;

typedef enum logic [2:0] {
    VF3_OPV     = 3'b000
    // Most base vector ALU ops use funct3=000
    // Extend as needed for loads/stores with element width encodings
} vec_funct3_t;

typedef enum logic [6:0] {
    VOPCODE_VECTOR_ALU   = 7'b1010111,
    VOPCODE_VECTOR_LOAD  = 7'b0000111,
    VOPCODE_VECTOR_STORE = 7'b0100111
    // Add more as needed
} vec_opcode_t;

typedef logic [4:0] vec_reg_t;

module riscv32_vector #(
    parameter int VLEN = 128,
    parameter int VREGS = 32,
    parameter int ELEM_WIDTH = 32
) (
    input  logic clk,
    input  logic reset,
    // Interface to core
    input  logic        vec_inst_valid,
    input  logic [31:0] vec_inst,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    output logic        vec_ready,
    output logic [VLEN-1:0] vec_result,
    // Unified memory interface
    output memory_io_req  data_mem_req,
    input  memory_io_rsp  data_mem_rsp
);

    // Vector register file
    logic [VLEN-1:0] vregfile [VREGS-1:0];

    // Control and configuration registers
    logic [31:0] vl;   // Vector length
    logic [2:0] sew;   // Selected element width

    // Decoded instruction fields
    vec_opcode_t  vec_opcode;
    vec_reg_t     vd, vs1, vs2;
    vec_funct3_t  vec_funct3;
    vec_funct6_t  vec_funct6;
    vec_op_t      vec_op;

    // ALU result (combinational)
    logic [VLEN-1:0] alu_result;

    // FSM for memory handshaking
    typedef enum logic [1:0] {
        VEC_IDLE,
        VEC_MEM_REQ,
        VEC_MEM_WAIT
    } vec_mem_state_t;
    vec_mem_state_t mem_state, mem_state_next;

    // Memory request struct
    memory_io_req mem_req_reg;

    logic instr_valid_latch;

    always_ff @(posedge clk) begin
        if (reset) begin
            instr_valid_latch <= 0;
        end else if (vec_inst_valid) begin
            instr_valid_latch <= 1;
        end else if (vec_ready) begin
            instr_valid_latch <= 0;
        end
    end

    // Decode logic for vector instructions
    always_comb begin
        // Extract fields and cast to enums
        vec_opcode  = vec_opcode_t'(vec_inst[6:0]);
        vd          = vec_inst[11:7];
        vec_funct3  = vec_funct3_t'(vec_inst[14:12]);
        vs1         = vec_inst[19:15];
        vs2         = vec_inst[24:20];
        vec_funct6  = vec_funct6_t'(vec_inst[31:26]);

        vec_op = VOP_NONE;

        if (vec_opcode == VOPCODE_VECTOR_ALU && vec_funct3 == VF3_OPV) begin
            case (vec_funct6)
                VF6_VADD:  vec_op = VOP_VADD;
                VF6_VSUB:  vec_op = VOP_VSUB;
                VF6_VAND:  vec_op = VOP_VAND;
                VF6_VOR:   vec_op = VOP_VOR;
                VF6_VXOR:  vec_op = VOP_VXOR;
                default:   vec_op = VOP_NONE;
            endcase
        end else if (vec_opcode == VOPCODE_VECTOR_LOAD) begin
            vec_op = VOP_VLOAD;
        end else if (vec_opcode == VOPCODE_VECTOR_STORE) begin
            vec_op = VOP_VSTORE;
        end

        // Combinational ALU logic
        alu_result = '0;
        case (vec_op)
            VOP_VADD: for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] +
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            VOP_VSUB: for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] -
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            VOP_VAND: for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] &
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            VOP_VOR:  for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] |
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            VOP_VXOR: for (int i = 0; i < VLEN/ELEM_WIDTH; i++)
                alu_result[i*ELEM_WIDTH +: ELEM_WIDTH] = vregfile[vs1][i*ELEM_WIDTH +: ELEM_WIDTH] ^
                                                        vregfile[vs2][i*ELEM_WIDTH +: ELEM_WIDTH];
            default: alu_result = '0;
        endcase

        // Default memory request struct
        mem_req_reg = memory_io_no_req;

        // FSM next-state logic
        mem_state_next = mem_state;
        case (mem_state)
            VEC_IDLE: begin
                if (vec_inst_valid && vec_op == VOP_VLOAD)
                    mem_state_next = VEC_MEM_REQ;
                else if (vec_inst_valid && vec_op == VOP_VSTORE)
                    mem_state_next = VEC_MEM_REQ;
            end
            VEC_MEM_REQ: begin
                mem_state_next = VEC_MEM_WAIT;
            end
            VEC_MEM_WAIT: begin
                if (data_mem_rsp.valid && data_mem_rsp.is_vector && vec_op == VOP_VLOAD)
                    mem_state_next = VEC_IDLE;
                else if (vec_op == VOP_VSTORE)
                    mem_state_next = VEC_IDLE;
            end
            default: mem_state_next = VEC_IDLE;
        endcase

        // Fill memory request struct for vector operations
        if (mem_state == VEC_MEM_REQ && vec_op == VOP_VLOAD) begin
            mem_req_reg.valid        = 1'b1;
            mem_req_reg.addr         = rs1_data;
            mem_req_reg.do_read      = 4'b1111;
            mem_req_reg.do_write     = 4'b0000;
            mem_req_reg.is_vector    = 1'b1;
            mem_req_reg.vector_data  = '0;
            mem_req_reg.data         = 32'b0;
        end else if (mem_state == VEC_MEM_REQ && vec_op == VOP_VSTORE) begin
            mem_req_reg.valid        = 1'b1;
            mem_req_reg.addr         = rs1_data;
            mem_req_reg.do_read      = 4'b0000;
            mem_req_reg.do_write     = 4'b1111;
            mem_req_reg.is_vector    = 1'b1;
            mem_req_reg.vector_data  = vregfile[vs2];
            mem_req_reg.data         = 32'b0;
        end
    end

    // Write-back logic (clocked)
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            vec_ready      <= 1'b0;
            vec_result     <= '0;
            mem_state      <= VEC_IDLE;
        end else begin
            mem_state      <= mem_state_next;
            vec_ready      <= 1'b0;

            if (instr_valid_latch) begin
                // ALU operations: ready immediately
                if (vec_op inside {VOP_VADD, VOP_VSUB, VOP_VAND, VOP_VOR, VOP_VXOR}) begin
                    vregfile[vd] <= alu_result;
                    vec_result   <= alu_result;
                    vec_ready    <= 1'b1;
                    $display("[VECTOR] ALU result: v%0d <= %h", vd, alu_result);
                end
            end

            // Vector load FSM
            if (mem_state == VEC_MEM_WAIT && vec_op == VOP_VLOAD && data_mem_rsp.valid && data_mem_rsp.is_vector) begin
                vregfile[vd]  <= data_mem_rsp.vector_data;
                vec_result    <= data_mem_rsp.vector_data;
                vec_ready     <= 1'b1;
                $display("[VECTOR] VLOAD complete: v%0d <= %h", vd, data_mem_rsp.vector_data);
            end

            // Vector store FSM
            if (mem_state == VEC_MEM_WAIT && vec_op == VOP_VSTORE) begin
                vec_ready     <= 1'b1; // Ready after store request
                $display("[VECTOR] VSTORE complete: addr=%h data[0]=%0d", rs1_data, vregfile[vs2][0 +: ELEM_WIDTH]);
            end
        end
    end

    // Assign memory request output
    assign data_mem_req = mem_req_reg;

    always_ff @(posedge clk or posedge reset) begin
    // ...existing functional logic...

    // --- Extensive debug print block ---
    if (!reset) begin
        $display("----- [VECTOR CYCLE %0t] -----", $time);
        $display("[VECTOR] Incoming: vec_inst_valid=%0d | vec_inst=%08h | rs1_data=%08h | rs2_data=%08h", 
            vec_inst_valid, vec_inst, rs1_data, rs2_data);
        $display("[VECTOR] Decoded: opcode=%02x | vd=%0d | vs1=%0d | vs2=%0d | funct3=%03b | funct6=%06b | vec_op=%0d", 
            vec_opcode, vd, vs1, vs2, vec_funct3, vec_funct6, vec_op);

        // Print destination vector register contents (first 4 elements)
        $display("[VECTOR] vregfile[vd=%0d] = ", vd);
        for (int i = 0; i < VLEN/ELEM_WIDTH; i++) begin
            $write("%08x ", vregfile[vd][i*ELEM_WIDTH +: ELEM_WIDTH]);
        end
        $write("\n");

        // Print outgoing memory request
        if (mem_req_reg.valid) begin
            $display("[VECTOR] MemReq: addr=%08h | do_read=%b | do_write=%b | is_vector=%0d", 
                mem_req_reg.addr, mem_req_reg.do_read, mem_req_reg.do_write, mem_req_reg.is_vector);
            if (mem_req_reg.is_vector && mem_req_reg.do_write != 0) begin
                $display("[VECTOR] MemReq vector_data:");
                for (int i = 0; i < VLEN/ELEM_WIDTH; i++) begin
                    $write("%08x ", mem_req_reg.vector_data[i*ELEM_WIDTH +: ELEM_WIDTH]);
                end
                $write("\n");
            end
        end

        // Print incoming memory response
        if (data_mem_rsp.valid) begin
            $display("[VECTOR] MemResp: addr=%08h | is_vector=%0d", data_mem_rsp.addr, data_mem_rsp.is_vector);
            if (data_mem_rsp.is_vector) begin
                $display("[VECTOR] MemResp vector_data:");
                for (int i = 0; i < VLEN/ELEM_WIDTH; i++) begin
                    $write("%08x ", data_mem_rsp.vector_data[i*ELEM_WIDTH +: ELEM_WIDTH]);
                end
                $write("\n");
            end else begin
                $display("[VECTOR] MemResp data=%08x", data_mem_rsp.data);
            end
        end

        // Print operation status
        $display("[VECTOR] FSM state: %0d | next_state: %0d | vec_ready=%0d", mem_state, mem_state_next, vec_ready);

        // Print ALU result if valid
        if (instr_valid_latch && (vec_op inside {VOP_VADD, VOP_VSUB, VOP_VAND, VOP_VOR, VOP_VXOR})) begin
            $display("[VECTOR] ALU result:");
            for (int i = 0; i < VLEN/ELEM_WIDTH; i++) begin
                $write("%08x ", alu_result[i*ELEM_WIDTH +: ELEM_WIDTH]);
            end
            $write("\n");
        end

        // Print vector load/store completion
        if (mem_state == VEC_MEM_WAIT && vec_op == VOP_VLOAD && data_mem_rsp.valid && data_mem_rsp.is_vector) begin
            $display("[VECTOR] VLOAD complete: v%0d <= ", vd);
            for (int i = 0; i < VLEN/ELEM_WIDTH; i++) begin
                $write("%08x ", data_mem_rsp.vector_data[i*ELEM_WIDTH +: ELEM_WIDTH]);
            end
            $write("\n");
        end
        if (mem_state == VEC_MEM_WAIT && vec_op == VOP_VSTORE) begin
            $display("[VECTOR] VSTORE complete: addr=%08h data[0]=%08x", rs1_data, vregfile[vs2][0 +: ELEM_WIDTH]);
        end

        $display("-------------------------------\n");
    end
end

endmodule

`endif
