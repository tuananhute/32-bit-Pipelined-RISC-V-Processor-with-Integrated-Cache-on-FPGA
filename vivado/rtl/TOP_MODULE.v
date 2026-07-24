module CPU_TOP (
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] debug_out
);

//////////////////////////////////////////////////
// IF
//////////////////////////////////////////////////
wire stall_F;
wire stall_D;
wire flush_D;
wire stall_icache;
wire flush_E;
wire stall_global;

wire [31:0] pc_target_comb;
wire        pc_src_comb;

wire [31:0] imem_addr_wire;
wire [31:0] imem_rdata_wire;

wire [31:0] if_instr_out_reg;
wire [31:0] if_next_pc_out_reg;

wire [31:0] if_pc_out;
wire [31:0] icache_instr_out;
wire        icache_miss;

//////////////////////////////////////////////////
// ID
//////////////////////////////////////////////////
wire [4:0] rs1_D;
wire [4:0] rs2_D;

wire [31:0] rs1_data_E;
wire [31:0] rs2_data_E;
wire [31:0] imm_E;
wire [31:0] pc_E;

wire [4:0] rd_E;
wire [3:0] alu_ctrl_E;

wire reg_write_E;
wire alu_src_E;

wire [2:0] load_type_E;
wire [1:0] store_type_E;

wire mem_write_E;
wire mem_read_E;

wire is_jal_E;
wire is_jalr_E;
wire is_lui_E;
wire is_auipc_E;

wire is_branch_E;
wire [2:0] branch_type_E;

wire [1:0] wb_sel_E;

wire [4:0] rs1_E;
wire [4:0] rs2_E;

//////////////////////////////////////////////////
// EX / MEM
//////////////////////////////////////////////////
wire [31:0] alu_result_M;
wire [31:0] rs2_data_M;

wire [4:0] rd_M;
wire       reg_write_M;

wire [31:0] pc_plus4_M;

wire [2:0] load_type_M;
wire [1:0] store_type_M;

wire mem_write_M;
wire mem_read_M;

wire [1:0] wb_sel_M;

wire branch_taken_E;

//////////////////////////////////////////////////
// MEM / WB
//////////////////////////////////////////////////
wire [31:0] mem_data_W;
wire [31:0] alu_result_W;
wire [31:0] pc_plus4_W;

wire [4:0] rd_W;
wire       reg_write_W;

wire [1:0] wb_sel_W;
wire       stall_MEM;

//////////////////////////////////////////////////
// WB TO ID
//////////////////////////////////////////////////
wire [31:0] write_data_W;
wire [4:0]  rd_D;
wire        reg_write_D;

//////////////////////////////////////////////////
// FORWARDING
//////////////////////////////////////////////////
wire [1:0] forwardA;
wire [1:0] forwardB;

//////////////////////////////////////////////////
// DATA CACHE
//////////////////////////////////////////////////
wire [31:0] cache_addr;
wire [31:0] cache_wdata;
wire [31:0] cache_rdata;

wire cache_mem_read;
wire cache_mem_write;
wire cache_ready;

//////////////////////////////////////////////////
// MAIN MEMORY
//////////////////////////////////////////////////
wire mem_read_out;
wire mem_write_out;

wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [31:0] mem_rdata;

wire mem_ready;


imem u_imem (
    .clk(clk),
    .reset(reset),
    .addr(imem_addr_wire),
    .instr(imem_rdata_wire)
);

icache_4way u_icache_4way (
    .clk(clk),
    .reset(reset),

    .pc(if_pc_out),               // t? IF

    .flush_icache(1'b0),

    .instr(icache_instr_out),     // sang IF
    .miss(icache_miss),           // sang IF + hazard

    .imem_addr(imem_addr_wire),
    .imem_rdata(imem_rdata_wire)
);
    IF_stage u_IF_stage (
    .clk(clk),
    .reset(reset),

    .stall_F(stall_F),
    .stall_D(stall_D),
    .flush_D(flush_D),
    .stall_icache(stall_icache),

    .pc_branch(pc_target_comb),
    .pc_control(pc_src_comb),

    .pc_out(if_pc_out),

    .instr_in(icache_instr_out),
    .miss_in(icache_miss),

    .instr_out(if_instr_out_reg),
    .next_pc_out(if_next_pc_out_reg)
);

// =====================================================
// ID STAGE
// =====================================================
ID_stage ID (
    .clk(clk),//
    .reset(reset),//
    .instr_in(if_instr_out_reg),//
    .pc_in(if_next_pc_out_reg),//

    .stall_D(stall_D),//
    .flush_E(flush_E),//

    .reg_write_wb(reg_write_D),
    .rd_wb(rd_W),
    .write_data_wb(write_data_W),

    .rs1_out(rs1_D),
    .rs2_out(rs2_D),

    .rs1_E_out(rs1_E),
    .rs2_E_out(rs2_E),

    .rs1_data_out(rs1_data_E),
    .rs2_data_out(rs2_data_E),

    .imm_out(imm_E),
    .rd_out(rd_E),
    .alu_ctrl_out(alu_ctrl_E),
    .reg_write_out(reg_write_E),
    .alu_src_out(alu_src_E),
    .pc_out(pc_E),

    .is_jal_out(is_jal_E),
    .is_jalr_out(is_jalr_E),
    .is_lui_out(is_lui_E),
    .is_auipc_out(is_auipc_E),

    .load_type_out(load_type_E),
    .store_type_out(store_type_E),
    .mem_write_out(mem_write_E),
    .mem_read_out(mem_read_E),

    .wb_sel_out(wb_sel_E),

    .is_branch_out(is_branch_E),
    .branch_type_out(branch_type_E)
);

// =====================================================
// EX STAGE (?? FIX QUAN TR?NG)
// =====================================================
EX_stage u_EX_stage (
    .clk(clk),
    .reset(reset),
    .stall_global(stall_MEM),
    .rs1_data_in(rs1_data_E),
    .rs2_data_in(rs2_data_E),
    .imm_in(imm_E),
    .rd_in(rd_E),

    .alu_ctrl_in(alu_ctrl_E),
    .reg_write_in(reg_write_E),
    .load_type_in(load_type_E),
    .store_type_in(store_type_E),
    .alu_src_in(alu_src_E),
    .pc_in(pc_E),

    .is_jal_in(is_jal_E),
    .is_jalr_in(is_jalr_E),
    .is_lui_in(is_lui_E),
    .is_auipc_in(is_auipc_E),

    .mem_write_in(mem_write_E),
    .mem_read_in(mem_read_E),

    .is_branch_in(is_branch_E),
    .branch_type_in(branch_type_E),

    .wb_sel_in(wb_sel_E),

    .forwardA(forwardA),
    .forwardB(forwardB),

    .alu_result_M(alu_result_M),
    .mem_data_M(mem_data_W),
    .pc_plus4_M(pc_plus4_M),
    .wb_sel_M(wb_sel_M),

    .write_data_W(write_data_W),

    .alu_result_out(alu_result_M),
    .rs2_data_out(rs2_data_M),
    .rd_out(rd_M),

    .reg_write_out(reg_write_M),
    .pc_plus4_out(pc_plus4_M),

    .load_type_out(load_type_M),
    .store_type_out(store_type_M),

    .mem_write_out(mem_write_M),
    .mem_read_out(mem_read_M),

    .wb_sel_out(wb_sel_M),

    // ?? QUAN TR?NG NH?T (FIX DELAY)
    .pc_target_out(pc_target_comb),
    .pc_src_out(pc_src_comb),

    .branch_taken_E(branch_taken_E)



// 
);
// =====================================================
// MEM STAGE
// =====================================================
LSU_stage u_LSU_stage (
    .clk(clk),
    .reset(reset),

    // Từ EX/MEM
    .alu_result_in(alu_result_M),
    .rs2_data_in(rs2_data_M),
    .rd_in(rd_M),
    .reg_write_in(reg_write_M),
    .pc_plus4_in(pc_plus4_M),

    .mem_read_in(mem_read_M),
    .mem_write_in(mem_write_M),

    .load_type_in(load_type_M),
    .store_type_in(store_type_M),
    .wb_sel_in(wb_sel_M),

    // Từ cache
    .cache_rdata(cache_rdata),
    .cache_ready(cache_ready),

    // Sang cache
    .cache_addr(cache_addr),
    .cache_wdata(cache_wdata),
    .cache_mem_read(cache_mem_read),
    .cache_mem_write(cache_mem_write),

    // Sang WB
    .mem_data_out(mem_data_W),
    .alu_result_out(alu_result_W),
    .rd_out(rd_W),
    .reg_write_out(reg_write_W),
    .pc_plus4_out(pc_plus4_W),
    .wb_sel_out(wb_sel_W),

    // Stall
    .stall_out(stall_MEM)
);

// =====================================================
// WB
// =====================================================
WB_stage WB (
    .reset(reset),

    .mem_data_in(mem_data_W),
    .alu_result_in(alu_result_W),
    .pc_plus4_in(pc_plus4_W),

    .rd_in(rd_W),
    .reg_write_in(reg_write_W),
    .wb_sel_in(wb_sel_W),

    .write_data_out(write_data_W),

    .rd_out(rd_D),
    .reg_write_out(reg_write_D)
);

// =====================================================
// CACHE
// =====================================================
data_cache_2way_fast DCACHE (
    .clk(clk),
    .reset(reset),

    .addr(cache_addr),
    .wdata(cache_wdata),

    .mem_read(cache_mem_read),
    .mem_write(cache_mem_write),
   
    .rdata(cache_rdata),
    .ready(cache_ready),

    .mem_read_out(mem_read_out),
    .mem_write_out(mem_write_out),

    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .mem_ready(mem_ready)
);

// =====================================================
// MAIN MEMORY
// =====================================================
main_memory u_main_memory (
    .clk(clk),
   .reset(reset),
    .mem_read(mem_read_out),
    .mem_write(mem_write_out),

    .addr(mem_addr),
    .wdata(mem_wdata),
    .rdata(mem_rdata),
    .ready(mem_ready)
//


);

// =====================================================
// HAZARD
// =====================================================
hazard_unit HZ (
    .rs1_D(rs1_D),
    .rs2_D(rs2_D),

    .rd_E(rd_E),
    .mem_read_E(mem_read_E),

    .rd_M(rd_M),
    .reg_write_M(reg_write_M),

    .rd_W(rd_W),
    .reg_write_W(reg_write_W),

    .rs1_E(rs1_E),
    .rs2_E(rs2_E),

    .stall_mem(stall_MEM),
    .branch_taken_E(branch_taken_E),
    .is_jal_E(is_jal_E),
    .is_jalr_E(is_jalr_E),
    .stall_F(stall_F),
    .stall_D(stall_D),
    .flush_D(flush_D),
    .flush_E(flush_E),

    .forwardA(forwardA),
    .forwardB(forwardB),
//


.is_branch_E(is_branch_E),
    .miss(icache_miss),
    .stall_icache(stall_icache),
.stall_global(stall_global)
);
assign debug_out = {
    29'b0,
    icache_miss,
    stall_icache,
    stall_global
};

endmodule