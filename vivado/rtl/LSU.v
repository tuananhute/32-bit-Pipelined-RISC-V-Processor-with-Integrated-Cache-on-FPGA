`timescale 1ns / 1ps

module LSU_stage (
    input  wire        clk,
    input  wire        reset,

    // ==================================================
    // INPUT TỪ EX/MEM
    // ==================================================
    input  wire [31:0] alu_result_in,
    input  wire [31:0] rs2_data_in,
    input  wire [4:0]  rd_in,
    input  wire        reg_write_in,
    input  wire [31:0] pc_plus4_in,

    input  wire        mem_read_in,
    input  wire        mem_write_in,

    input  wire [2:0]  load_type_in,
    input  wire [1:0]  store_type_in,
    input  wire [1:0]  wb_sel_in,

    // ==================================================
    // INPUT TỪ DATA CACHE
    // ==================================================
    input  wire [31:0] cache_rdata,
    input  wire        cache_ready,

    // ==================================================
    // OUTPUT SANG DATA CACHE
    // ==================================================
    output wire [31:0] cache_addr,
    output wire [31:0] cache_wdata,
    output wire        cache_mem_read,
    output wire        cache_mem_write,

    // ==================================================
    // OUTPUT SANG MEM/WB
    // ==================================================
    output reg  [31:0] mem_data_out,
    output reg  [31:0] alu_result_out,
    output reg  [4:0]  rd_out,
    output reg         reg_write_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [1:0]  wb_sel_out,

    // ==================================================
    // STALL OUTPUT
    // ==================================================
    output wire        stall_out
);

    //////////////////////////////////////////////////////
    // CACHE INTERFACE
    //////////////////////////////////////////////////////
    assign cache_addr      = alu_result_in;
    assign cache_mem_read  = mem_read_in;
    assign cache_mem_write = mem_write_in;

    //////////////////////////////////////////////////////
    // STALL
    //
    // Chỉ stall khi có lệnh Load/Store nhưng cache
    // chưa trả ready.
    //////////////////////////////////////////////////////
    assign stall_out =
        (mem_read_in || mem_write_in) &&
        !cache_ready;

    //////////////////////////////////////////////////////
    // CACHE WORD
    //////////////////////////////////////////////////////
    wire [31:0] word;

    assign word = cache_rdata;

    //////////////////////////////////////////////////////
    // LOAD DATA
    //////////////////////////////////////////////////////
    reg [31:0] load_data;

    always @(*) begin
        // Mặc định đọc nguyên word
        load_data = word;

        if (mem_read_in) begin
            case (load_type_in)

                ////////////////////////////////////////////
                // LB: Load Byte, sign extension
                ////////////////////////////////////////////
                3'b000: begin
                    case (alu_result_in[1:0])
                        2'b00:
                            load_data =
                                {{24{word[7]}}, word[7:0]};

                        2'b01:
                            load_data =
                                {{24{word[15]}}, word[15:8]};

                        2'b10:
                            load_data =
                                {{24{word[23]}}, word[23:16]};

                        2'b11:
                            load_data =
                                {{24{word[31]}}, word[31:24]};

                        default:
                            load_data = word;
                    endcase
                end

                ////////////////////////////////////////////
                // LH: Load Halfword, sign extension
                ////////////////////////////////////////////
                3'b001: begin
                    case (alu_result_in[1])
                        1'b0:
                            load_data =
                                {{16{word[15]}}, word[15:0]};

                        1'b1:
                            load_data =
                                {{16{word[31]}}, word[31:16]};

                        default:
                            load_data = word;
                    endcase
                end

                ////////////////////////////////////////////
                // LW: Load Word
                ////////////////////////////////////////////
                3'b010: begin
                    load_data = word;
                end

                ////////////////////////////////////////////
                // LBU: Load Byte, zero extension
                ////////////////////////////////////////////
                3'b100: begin
                    case (alu_result_in[1:0])
                        2'b00:
                            load_data =
                                {24'b0, word[7:0]};

                        2'b01:
                            load_data =
                                {24'b0, word[15:8]};

                        2'b10:
                            load_data =
                                {24'b0, word[23:16]};

                        2'b11:
                            load_data =
                                {24'b0, word[31:24]};

                        default:
                            load_data = word;
                    endcase
                end

                ////////////////////////////////////////////
                // LHU: Load Halfword, zero extension
                ////////////////////////////////////////////
                3'b101: begin
                    case (alu_result_in[1])
                        1'b0:
                            load_data =
                                {16'b0, word[15:0]};

                        1'b1:
                            load_data =
                                {16'b0, word[31:16]};

                        default:
                            load_data = word;
                    endcase
                end

                default: begin
                    load_data = word;
                end
            endcase
        end
    end

    //////////////////////////////////////////////////////
    // STORE DATA
    //
    // SB và SH dùng read-modify-write:
    // đọc word cũ từ cache, thay đúng byte/halfword cần ghi.
    //////////////////////////////////////////////////////
    reg [31:0] store_data;

    always @(*) begin
        // Giữ nguyên word cũ
        store_data = word;

        if (mem_write_in) begin
            case (store_type_in)

                ////////////////////////////////////////////
                // SB: Store Byte
                ////////////////////////////////////////////
                2'b00: begin
                    case (alu_result_in[1:0])
                        2'b00:
                            store_data[7:0] =
                                rs2_data_in[7:0];

                        2'b01:
                            store_data[15:8] =
                                rs2_data_in[7:0];

                        2'b10:
                            store_data[23:16] =
                                rs2_data_in[7:0];

                        2'b11:
                            store_data[31:24] =
                                rs2_data_in[7:0];

                        default:
                            store_data = word;
                    endcase
                end

                ////////////////////////////////////////////
                // SH: Store Halfword
                ////////////////////////////////////////////
                2'b01: begin
                    case (alu_result_in[1])
                        1'b0:
                            store_data[15:0] =
                                rs2_data_in[15:0];

                        1'b1:
                            store_data[31:16] =
                                rs2_data_in[15:0];

                        default:
                            store_data = word;
                    endcase
                end

                ////////////////////////////////////////////
                // SW: Store Word
                ////////////////////////////////////////////
                2'b10: begin
                    store_data = rs2_data_in;
                end

                default: begin
                    store_data = word;
                end
            endcase
        end
    end

    //////////////////////////////////////////////////////
    // WRITE DATA TO CACHE
    //////////////////////////////////////////////////////
    assign cache_wdata = store_data;

    //////////////////////////////////////////////////////
    // MEM/WB PIPELINE REGISTER
    //////////////////////////////////////////////////////
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_data_out   <= 32'b0;
            alu_result_out <= 32'b0;
            rd_out         <= 5'b0;
            reg_write_out  <= 1'b0;
            pc_plus4_out   <= 32'b0;
            wb_sel_out     <= 2'b0;
        end
        else if (!stall_out) begin
            mem_data_out   <= load_data;
            alu_result_out <= alu_result_in;
            rd_out         <= rd_in;
            reg_write_out  <= reg_write_in;
            pc_plus4_out   <= pc_plus4_in;
            wb_sel_out     <= wb_sel_in;
        end
    end

endmodule