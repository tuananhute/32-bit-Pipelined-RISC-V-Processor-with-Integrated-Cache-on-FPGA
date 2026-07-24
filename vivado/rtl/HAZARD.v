module hazard_unit(
    input miss,

    // ===== FROM ID =====
    input [4:0] rs1_D,
    input [4:0] rs2_D,

    // ===== FROM EX =====
    input [4:0] rd_E,
    input mem_read_E,
    input is_jal_E,
    input is_jalr_E,
    input is_branch_E,
    input branch_taken_E,

    // ===== FROM MEM =====
    input [4:0] rd_M,
    input reg_write_M,

    // ===== FROM WB =====
    input [4:0] rd_W,
    input reg_write_W,

    // ===== FROM EX =====
    input [4:0] rs1_E,
    input [4:0] rs2_E,

    // ===== CACHE =====
    input stall_mem,
    output stall_icache,
    // ===== OUTPUT =====
    output stall_F,
    output stall_D,
    output flush_D,
    output flush_E,
    output [1:0] forwardA,
    output [1:0] forwardB,
    output stall_global
);

//////////////////////////////////////////////////
// 1. FORWARDING
//////////////////////////////////////////////////
assign forwardA =
    (reg_write_M && (rd_M != 0) && (rd_M == rs1_E)) ? 2'b10 :
    (reg_write_W && (rd_W != 0) && (rd_W == rs1_E)) ? 2'b01 :
    2'b00;

assign forwardB =
    (reg_write_M && (rd_M != 0) && (rd_M == rs2_E)) ? 2'b10 :
    (reg_write_W && (rd_W != 0) && (rd_W == rs2_E)) ? 2'b01 :
    2'b00;


//////////////////////////////////////////////////
// 2. LOAD-USE
//////////////////////////////////////////////////
wire load_use_hazard =
    mem_read_E &&(rd_E != 0) &&
((rd_E == rs1_D) || (rd_E == rs2_D));


//////////////////////////////////////////////////
// 3. CONTROL HAZARD
//////////////////////////////////////////////////


assign stall_global = load_use_hazard || stall_mem;
assign stall_F = stall_global;
assign stall_D = stall_global;
//////////////////////////////////////////////////
// 5. FLUSH (KHÔNG DELAY REG)
//////////////////////////////////////////////////


wire control_hazard;

assign control_hazard =
    (is_branch_E && branch_taken_E) ||
    is_jal_E ||
    is_jalr_E;

assign flush_D = control_hazard;

assign stall_icache = miss && !control_hazard && !stall_mem;
assign flush_E =
    control_hazard ||
    (load_use_hazard && !stall_mem);

endmodule