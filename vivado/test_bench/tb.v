`timescale 1ns/1ps

module tb;

reg clk;
reg reset;

// DUT
CPU_TOP dut(
    .clk(clk),
    .reset(reset)
);

// clock
always #5 clk = ~clk;

initial begin
    clk = 0;
    reset = 1;

    #20;
    reset = 0;

    #200000;
    $finish;
end

endmodule
