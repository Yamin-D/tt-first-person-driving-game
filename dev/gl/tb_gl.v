// Gate-level check, as Tiny Tapeout's GL test does it: reset for 10 clocks,
// run, and require every output bit to be 0 or 1 (no X or Z). Also compares
// the gate-level outputs with the RTL clock by clock.
`timescale 1ns/1ps
module tb_gl;
    reg clk = 0, rst_n = 0;
    reg [7:0] ui_in = 0;
    wire [7:0] uo_gl, uio_out_gl, uio_oe_gl, uo_rtl, uio_out_rtl, uio_oe_rtl;
    always #20 clk = ~clk;

    tt_um_road_racer gl (.ui_in(ui_in), .uo_out(uo_gl), .uio_in(8'd0), .uio_out(uio_out_gl),
                         .uio_oe(uio_oe_gl), .ena(1'b1), .clk(clk), .rst_n(rst_n));
    rtl_top          rtl (.ui_in(ui_in), .uo_out(uo_rtl), .uio_in(8'd0), .uio_out(uio_out_rtl),
                         .uio_oe(uio_oe_rtl), .ena(1'b1), .clk(clk), .rst_n(rst_n));

    integer n, first_x = -1, x_count = 0, mismatches = 0, first_mm = -1;
    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1;
        ui_in = 8'b0000_0100;               // hold accelerate
        for (n = 0; n < `CYCLES; n = n + 1) begin
            @(posedge clk); #1;
            if (^{uo_gl, uio_out_gl, uio_oe_gl} === 1'bx) begin
                x_count = x_count + 1;
                if (first_x < 0) first_x = n;
            end else if ({uo_gl, uio_out_gl, uio_oe_gl} !== {uo_rtl, uio_out_rtl, uio_oe_rtl}) begin
                mismatches = mismatches + 1;
                if (first_mm < 0) first_mm = n;
            end
            if (n == 99)
                $display("after 100 clocks (what the CI test checks): uo_out=%b uio_out=%b uio_oe=%b",
                         uo_gl, uio_out_gl, uio_oe_gl);
        end
        $display("clocks %0d: X/Z on outputs in %0d clocks (first at %0d); gate vs RTL mismatches %0d (first at %0d)",
                 `CYCLES, x_count, first_x, mismatches, first_mm);
        $finish;
    end
endmodule
