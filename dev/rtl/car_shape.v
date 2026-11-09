// The shape of one upright car in the current row and column: a cuboid. s is
// the car's base row. The road and cars are 1.5 x wider than s, so S = 1.5 s:
// the rear face is S/2 wide, with lamps at the outer sixteenths and a window
// band above them. The side panel lies just beyond the rear face and stops at
// the road's ground line for this row, so it vanishes when the car is straight
// ahead. Purely combinational, in stage 2 of pixel_colour.
`default_nettype none

module car_shape (
    input  wire [7:0] s,
    input  wire       rows,      // this row is inside the car, registered
    input  wire       window,    // this row is in the window band, registered
    input  wire [10:0] u,        // columns from the rear face's near edge, registered
    input  wire       road_side, // on this car's side of the road centre
    input  wire [9:0] d,         // |x - road centre| for this row
    input  wire [7:0] col_a,     // 3 s_y / 8, registered
    input  wire [8:0] col_b,     // 9 s_y / 8, registered
    output wire [1:0] kind,      // 0 none, 1 body, 2 glass, 3 lamp
    output wire       side
);
    wire [8:0] big   = {1'b0, s} + {2'b00, s[7:1]};     // S
    wire [7:0] half  = big[8:1];
    wire [7:0] w     = {2'b00, big[8:3]};
    wire [7:0] w2    = {3'b000, big[8:4]};              // lamp width
    wire [7:0] h_w   = half - w2;
    wire [8:0] h_p   = {1'b0, half} + {1'b0, w};

    // everything is measured from the rear face's near edge
    wire        neg  = u[10];
    wire        near = (u[10:8] == 3'b000);      // 0 .. 255
    wire [7:0]  ul   = u[7:0];

    wire lt_half = near & (ul < half);
    wire lamp    = (ul < w2) | (ul >= h_w);

    assign kind = !(rows & lt_half) ? 2'd0 :
                  window ? (lamp ? 2'd1 : 2'd2) : (lamp ? 2'd3 : 2'd1);

    wire inner = neg & (u[9:8] == 2'b11) & (~ul < w) & (d >= {2'b00, col_a});
    wire outer = near & ~lt_half & ({1'b0, ul} < h_p) & (d < {1'b0, col_b});
    assign side = rows & road_side & (inner | outer);
endmodule
