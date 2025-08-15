`ifndef _riscv_multicycle
`define _riscv_multicycle

`include "base.sv"
`include "system.sv"
`include "riscv32_common.sv"
`include "memory.sv"
`include "memory_io.sv"

module core (
    input logic       clk,
    input logic       reset,
    input logic       [`word_address_size-1:0] reset_pc,
    output memory_io_req   inst_mem_req,
    input  memory_io_rsp   inst_mem_rsp,
    output memory_io_req   data_mem_req,
    input  memory_io_rsp   data_mem_rsp,
    output logic        vec_inst_valid,
    output logic [31:0] vec_inst,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data,
    input  logic        vec_ready,
    input  logic [127:0] vec_result);


// =========================
// === Instruction Fetch ===
// =========================
int instruction_count;
word_address    pc, next_pc;
instr32         instruction_read;

// ==========================
// === Instruction Decode ===
// ==========================

tag        rs1, rs2;      // Source register tags
tag        wbs;           // Write-back destination register
word       wbd;           // Write-back data
logic      wbv;           // Write-back valid flag
word       imm;           // Decoded immediate
funct3     f3;            // Function 3 bits
funct7     f7;            // Function 7 bits
opcode_q   op_q;          // Instruction type opcode
opcode op;
instr_format format;      // Instruction format (R/I/S/etc.)
bool       is_memory_op;
word_address if_id_pc;
instr32    if_id_instr;

logic is_vector_op; 
// ===========================
// === ID/EX Pipeline Regs ===
// ===========================

tag        id_ex_rs1, id_ex_rs2;
tag        id_ex_wbs;
word       id_ex_rd1, id_ex_rd2;
word       id_ex_imm;
funct3     id_ex_f3;
funct7     id_ex_f7;
opcode_q   id_ex_op_q;
instr_format id_ex_format;
bool       id_ex_wbv;
word_address id_ex_pc;
instr32    id_ex_instr;

// ============================
// === EX/MEM Pipeline Regs ===
// ============================

word       ex_mem_exec_result;
tag        ex_mem_wbs;
bool       ex_mem_wbv; 
opcode_q   ex_mem_op_q;
funct3     ex_mem_f3;
word_address ex_mem_pc;
word       ex_mem_rd1, ex_mem_rd2;
instr32    ex_mem_instr;

// ============================
// === MEM/WB Pipeline Regs ===
// ============================

word       mem_wb_exec_result;
word       mem_wb_wbd;
tag        mem_wb_wbs;
bool       mem_wb_wbv;
opcode_q   mem_wb_op_q;
funct3     mem_wb_f3;
instr32    mem_wb_instr;
word_address mem_wb_pc;
word mem_wb_rsp_data;
logic mem_wb_rsp_valid;

// ==========================
// === Register File ===
// ==========================

word       reg_file[0:31];

// =================================
// === Forwarding + Hazard Logic ===
// =================================

logic forward_a, forward_b;
word forward_data_a, forward_data_b;
logic memory_stage_complete;
logic branch_taken, jump_taken;
logic mem_stall, mem_req_sent;

assign mem_stall = ((ex_mem_op_q == q_load) || (ex_mem_op_q == q_store)) && (data_mem_rsp.valid != true); 

always_ff @(posedge clk) begin
    mem_req_sent <= mem_stall;
end

// ========================================
// === Instruction Memory Request Logic ===
// ========================================

always_comb begin
    inst_mem_req = memory_io_no_req;
    inst_mem_req.addr = next_pc;
    inst_mem_req.valid = inst_mem_rsp.ready;
    inst_mem_req.do_read[3:0] = 4'b1111;
    instruction_read = shuffle_store_data(inst_mem_rsp.data, inst_mem_rsp.addr);
end

// ==========================
// === Instruction Decode ===
// ==========================

always_comb begin
    rs1     = decode_rs1(if_id_instr);
    rs2     = decode_rs2(if_id_instr);
    wbs     = decode_rd(if_id_instr);
    f3      = decode_funct3(if_id_instr);
    op_q    = decode_opcode_q(if_id_instr);
    format  = decode_format(op_q);
    imm     = decode_imm(if_id_instr, format);
    wbv     = decode_writeback(op_q);
    f7      = decode_funct7(if_id_instr, format);
    op = decode_opcode(if_id_instr);
    is_vector_op = decode_vector_op(op);
    vec_inst_valid = is_vector_op;
    vec_inst       = if_id_instr;
    rs1_data       = reg_file[rs1];
    rs2_data       = reg_file[rs2];
end


always_ff @(posedge clk) begin
    if (reset) begin
        for (int i = 0; i <= 31; i++) begin
            reg_file[i] <= 32'd0;
        end
    end else begin
        if (rs1 == mem_wb_wbs && rs1 != 0 && !mem_stall && mem_wb_instr != 32'h00000013)
            id_ex_rd1 <= wbd;
        else if (!mem_stall)
            id_ex_rd1 <= reg_file[rs1];

        if (rs2 == mem_wb_wbs && rs2 != 0 && !mem_stall && mem_wb_instr != 32'h00000013)
            id_ex_rd2 <= wbd;
        else if (!mem_stall)
            id_ex_rd2 <= reg_file[rs2];

        if (mem_wb_wbv && mem_wb_wbs != `tag_size'd0 && 
            (mem_wb_op_q != q_load || mem_wb_rsp_valid) && !mem_req_sent)
             reg_file[mem_wb_wbs] <= wbd;
    end
end


// =======================
// === Execution Stage ===
// =======================

ext_operand exec_result_comb;
always_comb begin
    
    exec_result_comb = execute(
        cast_to_ext_operand(forward_data_a),   // rd1
        cast_to_ext_operand(forward_data_b),   // rd2
        cast_to_ext_operand(id_ex_imm),        // imm
        id_ex_pc,
        id_ex_op_q,
        id_ex_f3,
        id_ex_f7
    );
end

// ===========================
// === Memory Access Logic ===
// ===========================

logic [3:0] mem_mask;
memory_op mem_op;
always_comb begin
    mem_op = cast_to_memory_op(ex_mem_f3);
    mem_mask = memory_mask(mem_op);

    data_mem_req = memory_io_no_req;

    if (data_mem_rsp.ready && !mem_req_sent) begin
        if (ex_mem_op_q == q_store) begin
            data_mem_req.addr = ex_mem_exec_result[`word_address_size - 1:0];
            data_mem_req.valid = true;
            //Without cache
            //data_mem_req.do_write = shuffle_store_mask(mem_mask, ex_mem_exec_result);
            //data_mem_req.data = shuffle_store_data(ex_mem_rd2, ex_mem_exec_result);

            //With cache
            data_mem_req.do_write = mem_mask;
            data_mem_req.data     = ex_mem_rd2;
        end else if (ex_mem_op_q == q_load) begin
            data_mem_req.addr = ex_mem_exec_result[`word_address_size - 1:0];
            data_mem_req.valid = true;
            data_mem_req.do_read = shuffle_store_mask(mem_mask, ex_mem_exec_result);
        end
    end
end

// =================================
// === Write-back Data Selection ===
// =================================

always_comb begin
    wbd = mem_wb_exec_result;

    if (mem_wb_op_q == q_load) begin
        //With cache
        wbd = extract_load_data(mem_wb_rsp_data, mem_wb_exec_result, cast_to_memory_op(mem_wb_f3));

        //Without cache
        //wbd = subset_load_data(shuffle_load_data(mem_wb_rsp_data, mem_wb_exec_result), cast_to_memory_op(mem_wb_f3));
    end
end

// =============================
// === Data Forwarding Logic ===
// =============================

always_comb begin
    forward_a = ((id_ex_rs1 == ex_mem_wbs && ex_mem_wbv != 0) || (id_ex_rs1 == mem_wb_wbs && mem_wb_wbv != 0)) && (id_ex_rs1 != 0);
    forward_b = ((id_ex_rs2 == ex_mem_wbs && ex_mem_wbv != 0) || (id_ex_rs2 == mem_wb_wbs && mem_wb_wbv != 0)) && (id_ex_rs2 != 0);

    if (forward_a) begin
        if (id_ex_rs1 == ex_mem_wbs)
            forward_data_a = ex_mem_exec_result;
        else
            forward_data_a = wbd;
    end else begin
        forward_data_a = id_ex_rd1;
    end

    if (forward_b) begin
        if (id_ex_rs2 == ex_mem_wbs)
            forward_data_b = ex_mem_exec_result;
        else
            forward_data_b = wbd;
    end else
        forward_data_b = id_ex_rd2;
end

// =============================
// === Load-Use Hazard Stall ===
// =============================

logic stall_pipeline;
logic vector_stall;
always_comb begin
    vector_stall = is_vector_op && !vec_ready;
    stall_pipeline = vector_stall || ((id_ex_op_q == q_load) &&
                    ((id_ex_wbs == rs1 && rs1 != 0) ||
                    (id_ex_wbs == rs2 && rs2 != 0)));
end

// =============================
// === Branch and Jump Logic ===
// =============================

always_comb begin
    branch_taken = 0;
    jump_taken = 0;

    if (id_ex_op_q == q_branch) begin
        branch_taken = take_branch(forward_data_a, forward_data_b, id_ex_f3);
    end

    if (id_ex_op_q == q_jal || id_ex_op_q == q_jalr)
        jump_taken = true;
end

// =========================
// === PC Update Control ===
// =========================

always_comb begin
    if (reset)
        next_pc = reset_pc;
    else if (stall_pipeline || mem_stall)
        next_pc = pc;
    else if (branch_taken)
        next_pc = id_ex_pc + id_ex_imm;
    else if (jump_taken)
        next_pc = (id_ex_op_q == q_jalr) ? forward_data_a : (id_ex_pc + id_ex_imm);
    else
        next_pc = pc + 4;
end

always_ff @(posedge clk) begin
    if (reset)
        pc <= reset_pc;
    else
        pc <= next_pc;
end

// =================================
// === Pipeline Register Updates ===
// =================================

always_ff @(posedge clk) begin
    if (reset) begin
        if_id_instr <= 32'h00000013;
        if_id_pc <= reset_pc;

        id_ex_op_q <= q_op_imm;
        id_ex_wbv <= 0;
        id_ex_pc <= reset_pc;
        id_ex_instr <= 32'h00000013;
        id_ex_rs1 <= 0;
        id_ex_rs2 <= 0;
        id_ex_wbs <= 0;
        id_ex_imm <= 0;
        id_ex_f3 <= 0;
        id_ex_f7 <= 0;

        ex_mem_exec_result <= 0;
        ex_mem_wbs <= 0;
        ex_mem_wbv <= 0;
        ex_mem_op_q <= q_op_imm;
        ex_mem_f3 <= 0;
        ex_mem_instr <= 32'h00000013;
        ex_mem_pc <= reset_pc;
        ex_mem_rd1 <= 0;
        ex_mem_rd2 <= 0;

        mem_wb_pc <= reset_pc;
        mem_wb_exec_result <= 0;
        mem_wb_wbs <= 0;
        mem_wb_wbv <= 0;
        mem_wb_op_q <= q_op_imm;
        mem_wb_f3 <= 0;
        mem_wb_instr <= 32'h00000013;

    end else begin
        if ((branch_taken || jump_taken) && (!mem_stall)) begin
            if_id_instr <= 32'h00000013;
            if_id_pc <= reset_pc;
        end else if (!stall_pipeline && !mem_stall && inst_mem_rsp.valid) begin
            if_id_instr <= instruction_read;
            if_id_pc <= pc;
        end

        if ((stall_pipeline || branch_taken || jump_taken) && !mem_stall) begin
            id_ex_op_q <= q_op_imm;
            id_ex_wbv <= 0;
            id_ex_pc <= reset_pc;
            id_ex_instr <= 32'h00000013;
            id_ex_rs1 <= 0;
            id_ex_rs2 <= 0;
            id_ex_wbs <= 0;
            id_ex_imm <= 0;
            id_ex_f3 <= 0;
            id_ex_f7 <= 0;
        end else if (!mem_stall) begin
            id_ex_rs1 <= rs1;
            id_ex_rs2 <= rs2;
            id_ex_wbs <= wbs;
            id_ex_imm <= imm;
            id_ex_f3 <= f3;
            id_ex_f7 <= f7;
            id_ex_op_q <= op_q;
            id_ex_format <= format;
            id_ex_wbv <= wbv;
            id_ex_instr <= if_id_instr;
            id_ex_pc <= if_id_pc;
        end
        
        if (!mem_stall) begin
            ex_mem_exec_result <= exec_result_comb[`word_size-1:0];
            ex_mem_wbs <= id_ex_wbs;
            ex_mem_wbv <= id_ex_wbv;
            ex_mem_op_q <= id_ex_op_q;
            ex_mem_f3 <= id_ex_f3;
            ex_mem_instr <= id_ex_instr;
            ex_mem_pc <= id_ex_pc;
            if (forward_a)
                ex_mem_rd1 <= forward_data_a;
            else 
                ex_mem_rd1 <= id_ex_rd1;
            if (forward_b)
                ex_mem_rd2 <= forward_data_b;
            else 
                ex_mem_rd2 <= id_ex_rd2;
        end

        if (!mem_stall) begin
            mem_wb_pc <= ex_mem_pc;
            mem_wb_exec_result <= ex_mem_exec_result;
            mem_wb_wbs <= ex_mem_wbs;
            mem_wb_wbv <= ex_mem_wbv;
            mem_wb_op_q <= ex_mem_op_q;
            mem_wb_f3 <= ex_mem_f3;
            mem_wb_instr <= ex_mem_instr;
            mem_wb_rsp_data <= data_mem_rsp.data;
            mem_wb_rsp_valid <= data_mem_rsp.valid;
        end
    end
end


always_ff @(posedge clk) begin
    if (reset) begin
        instruction_count <= 0;
    end
    
    instruction_count <= instruction_count + 1;
    /*
    if (data_mem_req.valid && data_mem_req.addr == `word_address_size'h0002_FFFC &&
        data_mem_req.do_write != {(`word_address_size/8){1'b0}}) begin
        $display("Cycle count: %d\n", instruction_count);
    end
    */
    /*
    if (instruction_count == 1175) begin
        //$display("----- Cycle %0t -----", $time);
        $finish;
    end
    */
    
    if (data_mem_req.valid && !reset) begin
        $display("----- Cycle %0t -----", $time);
        if (data_mem_req.do_write != 0)
            $display("WRITE: addr=%08x data=%08x pc=%08h\n", data_mem_req.addr, data_mem_req.data, ex_mem_pc);
        else if (data_mem_req.do_read != 0) 
            $display("READ: addr=%08x data=%08x pc=%08h\n", data_mem_req.addr, data_mem_req.data, ex_mem_pc);
    end
    
    if (data_mem_rsp.valid && !reset) begin
        $display("----- Cycle %0t -----", $time);
        $display("RESPONSE : addr=%08x data=%08x pc=%08h\n", data_mem_rsp.addr, data_mem_rsp.data, ex_mem_pc);
    end
    
    if (!reset) begin
        $display("forwA %08h, forwB %08h, imm %08h, pc %08h, op_q %0d, f3 %0d, f7 %0d",    
            forward_data_a, forward_data_b, id_ex_imm, id_ex_pc, id_ex_op_q, id_ex_f3, id_ex_f7);
        $display("forwA %d, forwB %d", forward_a, forward_b);
        $display("id_ex_rd1 %08h, id_ex_rd2 %08h", id_ex_rd1, id_ex_rd2);
        $display("ex_mem_rd1 %08h, ex_mem_rd2 %08h", ex_mem_rd1, ex_mem_rd2);
    end
    
    if (!reset) begin
        $display("----- Cycle %0t -----", $time);
        
        $display("IF  : PC = %08h | INSTR = %08h", pc, instruction_read);

        $display("ID  : PC = %08h | INSTR = %08h | rs1 = x%0d = %08x | rs2 = x%0d = %08x | wbs = x%0d | imm = %0d | op_q = %0d",
            if_id_pc, if_id_instr,
            rs1, reg_file[rs1],
            rs2, reg_file[rs2],
            wbs, imm, op_q);

        $display("EX  : PC = %08h | INSTR = %08h | rs1 = x%0d = %08x | rs2 = x%0d = %08x | wbs = x%0d | imm = %0d | result = %08x | fwd_a = %0d | fwd_b = %0d",
            id_ex_pc, id_ex_instr,
            id_ex_rs1, reg_file[id_ex_rs1],
            id_ex_rs2, reg_file[id_ex_rs2],
            id_ex_wbs, id_ex_imm,
            exec_result_comb[`word_size-1:0],
            forward_a, forward_b);

        $display("MEM : PC = %08h | INSTR = %08h | wbs = x%0d | mem_addr = %08x | wbv = %08x | result %08x",
            ex_mem_pc, ex_mem_instr, ex_mem_wbs, data_mem_req.addr, ex_mem_wbv, ex_mem_exec_result);

        $display("WB  : PC = %08h | INSTR = %08h | wbs = x%0d | wbd = %08x | wbv = %08x",
            mem_wb_pc, mem_wb_instr, mem_wb_wbs, wbd, mem_wb_wbv);

        $display("MemReq : addr = %08x | data = %08x", data_mem_req.addr, data_mem_req.data);
        $display("MemResp: addr = %08x | data = %08x", data_mem_rsp.addr, data_mem_rsp.data);

        $display("ra: %08x   sp: %08x", reg_file[1], reg_file[2]); // x1 = ra, x2 = sp

        $display("t0: %08x  t1: %08x  t2: %08x  t3: %08x", 
            reg_file[5], reg_file[6], reg_file[7], reg_file[28]); // t0-t3 = x5–x7, x28

        $display("t4: %08x  t5: %08x  t6: %08x", 
            reg_file[29], reg_file[30], reg_file[31]); // t4–t6 = x29–x31

        $display("s0: %08x  s1: %08x  s2: %08x  s3: %08x  s4: %08x  s5: %08x", 
            reg_file[8], reg_file[9], reg_file[18], reg_file[19], reg_file[20], reg_file[21]); // s0–s5 = x8, x9, x18–x21

        $display("a0: %08x  a1: %08x  a2: %08x  a3: %08x  a4: %08x  a5: %08x", 
            reg_file[10], reg_file[11], reg_file[12], reg_file[13], reg_file[14], reg_file[15]); // a0–a5 = x10–x15

        $display("Control: mem_stall = %0d | mem_req_sent = %0d | branch_taken = %0d | jump_taken = %0d | stall_pipeline = %0d",
            mem_stall, mem_req_sent, branch_taken, jump_taken, stall_pipeline);
        
        $display("-------------------------------\n");   
        
    end   
    
    
end

endmodule
`endif
