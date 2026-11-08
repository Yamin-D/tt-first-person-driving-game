// Colour of the pixel at (x, y), in two pipeline stages so that each clock
// has only part of the work (the slow corner of GF180 needs this):
//   stage 1  |x - centre|, the mountain test and the speed-bar test, registered
//   stage 2  compare against the road widths and choose the colour
// rgb therefore belongs to the pixel one clock earlier than (x, y); the top
// level delays the syncs by the same clock. Per pixel there are only small
// adders, comparators and multiplexers. rgb is {R1,R0,G1,G0,B1,B0}.
// Layout: sky 0-127, horizon 128, road 129-383, dashboard 384-479, chosen so
// that s_y and the region tests are bit slices of y.
`default_nettype none

module pixel_colour #(parameter WHEEL_FULL = 0) (
    input  wire               clk,
    input  wire        [9:0]  x,
    input  wire        [9:0]  y,
    input  wire               active,
    input  wire        [3:0]  z,       // low bits of this line's depth, from line_setup
    input  wire signed [16:0] A,       // ((h - 320) << 6) + p * s_y
    input  wire signed [7:0]  h,       // heading in pixels
    input  wire        [3:0]  d_hi,    // distance >> 5
    input  wire        [7:0]  v,       // speed, for the bar
    input  wire signed [2:0]  wheel,   // wheel angle, -2..2
    output reg         [5:0]  rgb
);
    // colours, RR_GG_BB
    localparam [5:0] SKY0     = 6'b00_00_10;
    localparam [5:0] SKY1     = 6'b00_01_10;
    localparam [5:0] SKY2     = 6'b00_01_11;
    localparam [5:0] SKY3     = 6'b01_10_11;
    localparam [5:0] MOUNTAIN = 6'b01_01_10;
    localparam [5:0] DASH_COL = 6'b01_00_01;
    localparam [5:0] BAR_COL  = 6'b11_10_00;
    localparam [5:0] LINE_COL = 6'b11_11_11;
    localparam [5:0] TARMAC0  = 6'b01_01_01;
    localparam [5:0] TARMAC1  = 6'b10_10_10;
    localparam [5:0] KERB0    = 6'b11_11_11;
    localparam [5:0] KERB1    = 6'b11_00_00;
    localparam [5:0] GRASS0   = 6'b00_10_00;
    localparam [5:0] GRASS1   = 6'b00_11_00;
    localparam [5:0] WHEEL0   = 6'b00_00_00;
    localparam [5:0] WHEEL1   = 6'b10_10_10;

    // ---- regions, as bit slices of y (y < 480)
    wire sky  = (y[9:7] == 3'b000);                 // y < 128
    wire dash = y[8] & y[7];                        // y >= 384
    wire [7:0] s_y = {~y[7], y[6:0]};               // y - 128, valid on road rows

    // ---- road geometry for this line (w = s_y)
    wire [8:0] kerb_w = {1'b0, s_y} + {4'b0000, s_y[7:3]};
    wire [3:0] dash_w = {1'b0, s_y[7:5]} + 4'd1;

    wire signed [10:0] a6 = A[16:6];                // A >>> 6
    wire signed [10:0] dx = $signed({1'b0, x}) + a6;    // x - centre
    wire        [9:0]  d  = dx[10] ? ~dx[9:0] : dx[9:0]; // |dx|, or |dx| - 1 when negative

    wire [3:0] band   = z[3:0] + d_hi;
    wire       stripe = band[3] & (s_y[7:5] != 3'b000);  // no stripes for s_y < 32

    // ---- mountains: a triangle wave indexed by x + h, so they slide as you turn
    wire [6:0] u      = x[6:0] + h[6:0];
    wire [4:0] tri_w  = u[5] ? ~u[4:0] : u[4:0];
    wire [5:0] mh     = {1'b0, tri_w} + (u[6] ? {2'b00, tri_w[4:1]} : 6'd0);
    wire       peak   = ({1'b0, ~y[6:0]} < {2'b00, mh});  // 127 - y < height

    // ---- speed bar: vertical, columns 64-95, v/2 rows up from the bottom row.
    // Only used on dashboard rows, where 479 - y = 95 - y[6:0] is this slice.
    wire [6:0] up     = {~y[6] & ~y[5], ~y[6] & y[5], ~y[4:0]};
    wire       in_bar = (x[9:5] == 5'b00010) && (up < v[7:1]);

    // ---- steering wheel, drawn over everything else
    wire [1:0] wheel_code;
    steering_wheel #(.FULL(WHEEL_FULL)) steer (
        .x(x), .y(y), .w(wheel), .code(wheel_code)
    );

    // ---- stage 1 registers. Everything else used below depends only on y,
    // or changes only during blanking, so it is the same for the pixel one
    // clock earlier (at a line change that pixel is in blanking anyway).
    reg [9:0] d_q;
    reg [1:0] wheel_q;
    reg       peak_q, in_bar_q, active_q;
    always @(posedge clk) begin
        d_q      <= d;
        wheel_q  <= WHEEL_FULL ? wheel_code : {1'b0, wheel_code[0]};
        peak_q   <= peak;
        in_bar_q <= in_bar;
        active_q <= active;
    end

    // ---- stage 2
    always @(*) begin
        if (!active_q)
            rgb = 6'b00_00_00;
        else if (wheel_q != 2'd0)
            rgb = (wheel_q == 2'd1) ? WHEEL0 : (wheel_q == 2'd2) ? BAR_COL : WHEEL1;
        else if (sky)
            rgb = peak_q ? MOUNTAIN :
                  (y[6:5] == 2'd0) ? SKY0 :
                  (y[6:5] == 2'd1) ? SKY1 :
                  (y[6:5] == 2'd2) ? SKY2 : SKY3;
        else if (dash)
            rgb = in_bar_q ? BAR_COL : DASH_COL;
        else if (s_y == 8'd0)
            rgb = GRASS0;
        else if (stripe && d_q < {6'd0, dash_w})
            rgb = LINE_COL;
        else if (d_q < {2'b00, s_y})
            rgb = stripe ? TARMAC1 : TARMAC0;
        else if (d_q < {1'b0, kerb_w})
            rgb = stripe ? KERB1 : KERB0;
        else
            rgb = stripe ? GRASS1 : GRASS0;
    end
    wire _unused = &{A[5:0], h[7], band[2:0], 1'b0};
endmodule
