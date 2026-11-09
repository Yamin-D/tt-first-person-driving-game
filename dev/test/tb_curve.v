// Runs line_setup through every road row for extreme heading and position and
// every curvature, and prints h, p, kappa, s_y and Ae for each row.
`timescale 1ns/1ps
`default_nettype none

module tb_curve;
    reg clk = 0, rst_n = 0;
    reg [9:0] x = 0, y = 0;
    reg signed [7:0] h = 0;
    reg signed [8:0] p = 0;
    reg signed [3:0] kappa = 0;
    wire [10:0] z;
    wire signed [10:0] Ae;
    integer ih, ip, ik, row, k;

    line_setup dut (.clk(clk), .rst_n(rst_n), .x(x), .y(y), .h(h), .p(p),
                    .kappa(kappa), .z(z), .Ae(Ae));

    always #20 clk = ~clk;

    function signed [8:0] pick(input integer i, input integer lo, input integer hi);
        pick = (i == 0) ? lo : (i == 1) ? 0 : hi;
    endfunction

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1;
        for (ih = 0; ih < 3; ih = ih + 1)
        for (ip = 0; ip < 3; ip = ip + 1)
        for (ik = -8; ik < 8; ik = ik + 1) begin
            h = pick(ih, -101, 101);
            p = pick(ip, -162, 161);
            kappa = ik;
            for (row = 127; row <= 382; row = row + 1) begin
                y = row;
                for (k = 638; k < 666; k = k + 1) begin
                    x = k;
                    @(posedge clk); #1;
                end
                if (row >= 128)
                    $display("%0d %0d %0d %0d %0d", h, p, kappa, row - 127, Ae);
            end
        end
        $finish;
    end
endmodule
