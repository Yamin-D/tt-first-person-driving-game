// Runs the line_setup divider for every road row and prints s_y and z.
`timescale 1ns/1ps
`default_nettype none

module tb_divider;
    reg clk = 0, rst_n = 0;
    reg [9:0] x = 0, y = 0;
    wire [14:0] z;
    wire signed [10:0] Ae;
    integer s, k;

    line_setup #(.Z_BITS(15)) dut (.clk(clk), .rst_n(rst_n), .x(x), .y(y), .h(8'sd0),
                    .p(9'sd0), .kappa(4'sd0), .z(z), .Ae(Ae));

    always #20 clk = ~clk;

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1;
        for (s = 1; s <= 255; s = s + 1) begin
            y = s + 127;                     // computing z for row y + 1
            for (k = 639; k < 680; k = k + 1) begin
                x = k;
                @(posedge clk); #1;
            end
            $display("%0d %0d", s, z);
        end
        $finish;
    end
endmodule
