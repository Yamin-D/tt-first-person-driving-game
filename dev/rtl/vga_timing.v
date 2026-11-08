// 640x480 at 60 Hz from a 25 MHz clock: 800 clocks per line, 525 lines per frame.
// x and y count every clock, including blanking, so other blocks can schedule
// work at fixed positions (x = 640 starts horizontal blanking, y = 480 vertical).
`default_nettype none

module vga_timing (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [9:0] x,        // 0..799
    output reg  [9:0] y,        // 0..524
    output wire       hsync,    // active low
    output wire       vsync,    // active low
    output wire       active,   // high inside the 640x480 picture
    output reg        frame,    // one-clock pulse at the start of vertical blanking
    output reg        line_end  // one-clock pulse at x = 799 on every line
);
    always @(posedge clk) begin
        if (!rst_n) begin
            x <= 10'd0;
            y <= 10'd0;
        end else if (x == 10'd799) begin
            x <= 10'd0;
            y <= (y == 10'd524) ? 10'd0 : y + 10'd1;
        end else begin
            x <= x + 10'd1;
        end
    end

    assign hsync  = ~((x >= 10'd656) && (x < 10'd752));
    assign vsync  = ~((y >= 10'd490) && (y < 10'd492));
    assign active = (x < 10'd640) && (y < 10'd480);
    // registered strobes, decoded one clock early (see line_setup)
    always @(posedge clk) begin
        frame    <= (x == 10'd799) && (y == 10'd479);   // high at x = 0, y = 480
        line_end <= (x == 10'd798);                     // high at x = 799
    end
endmodule
