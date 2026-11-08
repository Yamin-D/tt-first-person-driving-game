// Drives engine_audio with one tick per clock. Every 525 ticks (one frame of
// lines) it loads the next speed and off-road flag from speeds.txt, and prints
// the sample after every tick.
`timescale 1ns/1ps
`default_nettype none

module tb_audio;
    reg clk = 0, rst_n = 0, tick = 0, offroad = 0;
    reg [7:0] v = 0;
    wire [7:0] sample;
    wire out;
    integer fd, code, n, vv, oo;

    engine_audio dut (.clk(clk), .rst_n(rst_n), .tick(tick), .v(v),
                      .offroad(offroad), .pwm_count(8'd0), .sample(sample), .out(out));

    always #20 clk = ~clk;

    initial begin
        fd = $fopen("speeds.txt", "r");
        repeat (2) @(posedge clk);
        rst_n = 1;
        while (!$feof(fd)) begin
            code = $fscanf(fd, "%d %d\n", vv, oo);
            v = vv; offroad = oo;
            for (n = 0; n < 525; n = n + 1) begin
                tick = 1;
                @(posedge clk); #1;
                $display("%0d", sample);
            end
        end
        $finish;
    end
endmodule
