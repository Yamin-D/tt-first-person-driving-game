// Feeds car_state one frame pulse per line of script.txt (4 bits: L R A B)
// and prints the state after each pulse.
`timescale 1ns/1ps
`default_nettype none

module tb_car_state;
    reg clk = 0, rst_n = 0, frame = 0;
    reg left = 0, right = 0, accel = 0, brake = 0;
    wire [7:0] v;
    wire signed [2:0] wheel;
    wire signed [7:0] h;
    wire signed [7:0] p;
    wire [8:0] D;
    wire offroad;
    wire signed [3:0] kappa;
    wire [11:0] slow, onc;
    wire [3:0] tens, ones;
    integer fd, code;
    reg [3:0] keys;

    car_state dut (.clk(clk), .rst_n(rst_n), .frame(frame),
                   .left(left), .right(right), .accel(accel), .brake(brake),
                   .v(v), .wheel(wheel), .h(h), .p(p), .p2(), .D(D), .offroad(offroad), .kappa(kappa),
                   .slow(slow), .onc(onc), .tens(tens), .ones(ones));

    always #20 clk = ~clk;

    initial begin
        fd = $fopen("script.txt", "r");
        repeat (6) @(posedge clk);
        rst_n = 1;
        while (!$feof(fd)) begin
            code = $fscanf(fd, "%b\n", keys);
            {left, right, accel, brake} = keys;
            @(posedge clk); #1 frame = 1;
            @(posedge clk); #1 frame = 0;
            repeat (9) @(posedge clk); #1;      // all the steps, including traffic and collision
            $display("%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", v, wheel, h, dut.P, D, offroad, kappa, dut.track, slow, onc, dut.crash, tens, ones);
        end
        $finish;
    end
endmodule
