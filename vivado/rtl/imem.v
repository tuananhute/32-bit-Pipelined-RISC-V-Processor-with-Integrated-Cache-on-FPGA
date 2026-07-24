module imem (
    input  clk,
    input  reset,
    input  [31:0] addr,
    output reg [31:0] instr
);
    (* ram_style = "block" *)
    reg [31:0] mem [0:255];

    initial begin
        $readmemh("file_instruction.txt", mem);
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            instr <= 32'h00000013; // NOP (RISC-V)
        end
        else begin
            instr <= mem[addr[9:2]]; // word-aligned
        end
    end

endmodule
