// The shape of one upright car in the current row and column: a cuboid. s is
// the car's base row; its rear face is s/2 wide and 3s/8 tall, with lamps at
// the outer eighths. The side panel lies just beyond the rear face and stops at
// the road's ground line for this row, so it vanishes when the car is straight
// ahead. Purely combinational, in stage 2 of pixel_colour.
`default_nettype none

module car_shape (
    input  wire [7:0] s,
    input  wire       rows,      // this row is inside the car, registered
    input  wire [10:0] u,        // columns from the rear face's near edge, registered
    input  wire       road_side, // on this car's side of the road centre
    input  wire [9:0] d,         // |x - road centre| for this row
    input  wire [7:0] col_a,     // s_y / 4
    input  wire [7:0] col_b,     // 3 s_y / 4, registered
    output wire [1:0] kind,      // 0 none, 1 body, 3 lamp
    output wire       side
);
    wire [7:0] half  = {1'b0, s[7:1]};
    wire [7:0] w     = {3'b000, s[7:3]};
    wire [7:0] h_w   = half - w;
    wire [8:0] h_p   = {1'b0, half} + {1'b0, w};

    // everything is measured from the rear face's near edge
    wire        neg  = u[10];
    wire        near = (u[10:8] == 3'b000);      // 0 .. 255
    wire [7:0]  ul   = u[7:0];

    wire lt_half = near & (ul < half);
    wire lamp    = (ul < w) | (ul >= h_w);

    assign kind = {rows & lt_half & lamp, rows & lt_half};

    wire inner = neg & (u[9:8] == 2'b11) & (~ul < w) & (d >= {2'b00, col_a});
    wire outer = near & ~lt_half & ({1'b0, ul} < h_p) & (d < {2'b00, col_b});
    assign side = rows & road_side & (inner | outer);
endmodule
