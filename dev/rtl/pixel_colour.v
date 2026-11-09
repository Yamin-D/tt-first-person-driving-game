// Colour of the pixel at (x, y), in two pipeline stages so that each clock
// has only part of the work (the slow corner of GF180 needs this):
//   stage 1  |x - centre|, the mountain test and the speed-bar test, registered
//   stage 2  compare against the road widths and choose the colour
// rgb therefore belongs to the pixel one clock earlier than (x, y); the top
// level delays the syncs by the same clock. Per pixel there are only small
// adders, comparators and multiplexers. rgb is {R1,R0,G1,G0,B1,B0}.
// Layout: sky 0-127, horizon 128, road 129-351, dashboard 352-479, chosen so
// that s_y and the region tests are bit slices of y.
`default_nettype none

module pixel_colour #(parameter WHEEL_FULL = 0) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire        [9:0]  x,
    input  wire        [9:0]  y,
    input  wire               active,
    input  wire        [3:0]  z,       // low bits of this line's depth, from line_setup
    input  wire signed [10:0] Ae,      // x - centre = x + Ae, set in blanking
    input  wire signed [7:0]  h,       // heading in pixels
    input  wire        [3:0]  d_hi,    // distance >> 5
    input  wire signed [2:0]  wheel,   // wheel angle, -2..2
    input  wire        [7:0]  v,       // speed, for the digits
    input  wire        [10:0] zs,      // next row's depth (with latch)
    input  wire               latch,
    input  wire        [10:0] zc_slow, // depth of each car
    input  wire        [10:0] zc_onc,
    input  wire               clr_slow,// a car respawned
    input  wire               clr_onc,
    input  wire               flash,   // crash stop
    input  wire signed [3:0]  kappa,   // road curvature
    input  wire        [3:0]  tens,    // score
    input  wire        [3:0]  ones,
    output reg         [5:0]  rgb
);
    // colours, RR_GG_BB
    localparam [5:0] SKY0     = 6'b00_00_01;   // a sunset
    localparam [5:0] SKY1     = 6'b01_00_10;
    localparam [5:0] SKY2     = 6'b11_01_01;
    localparam [5:0] SKY3     = 6'b11_10_00;
    localparam [5:0] SKY4     = 6'b11_11_01;
    localparam [5:0] MOUNTAIN = 6'b01_00_01;
    localparam [5:0] DASH_COL = 6'b01_01_01;
    localparam [5:0] COCKPIT  = 6'b00_00_01;
    localparam [5:0] MIRROR   = 6'b10_10_10;
    localparam [5:0] VENT_COL = 6'b10_10_10;
    localparam [5:0] SLOW_BODY = 6'b00_01_11;
    localparam [5:0] SLOW_LAMP = 6'b11_00_00;
    localparam [5:0] ONC_BODY  = 6'b11_11_11;
    localparam [5:0] ONC_LAMP  = 6'b11_11_00;
    localparam [5:0] SLOW_GLASS = 6'b10_01_01;
    localparam [5:0] ONC_GLASS  = 6'b10_01_00;
    localparam [5:0] SLOW_SIDE = 6'b00_00_01;
    localparam [5:0] ONC_SIDE  = 6'b01_01_01;
    localparam [5:0] PANEL_COL = 6'b00_00_00;
    localparam [5:0] BAR_COL  = 6'b11_10_00;
    localparam [5:0] LINE_COL = 6'b11_11_11;
    localparam [5:0] TARMAC0  = 6'b01_01_01;
    localparam [5:0] TARMAC1  = 6'b10_10_10;
    localparam [5:0] KERB0    = 6'b11_11_11;
    localparam [5:0] KERB1    = 6'b11_00_00;
    localparam [5:0] GRASS0   = 6'b00_10_00;
    localparam [5:0] GRASS1   = 6'b01_10_00;
    localparam [5:0] WHEEL0   = 6'b00_00_00;
    localparam [5:0] WHEEL1   = 6'b10_10_10;

    // ---- regions, as bit slices of y (y < 480)
    // Stage 2 works on the pixel one clock earlier, so it can use a local copy
    // of y. That takes most of the load off the y counter.
    // The wheel and the digits never touch column 0, so they can use a copy too.
    // y_w is stored inverted, or synthesis would merge the two copies into one.
    reg [9:0] y_q, y_wn;
    wire [9:0] y_w = ~y_wn;
    always @(posedge clk) begin
        y_q  <= y;
        y_wn <= ~y;
    end
    wire sky  = (y_q[9:7] == 3'b000);                 // y < 128
    wire dash = y_q[8] & (y_q[7] | (y_q[6] & y_q[5]));// y >= 352
    wire [7:0] s_y = {~y_q[7], y_q[6:0]};             // y - 128, valid on road rows
    wire [7:0] s_now = {~y[7], y[6:0]};               // the same one clock sooner

    // ---- road geometry for this line (w = s_y)
    wire [8:0] kerb_w = {1'b0, s_y} + {4'b0000, s_y[7:3]};
    wire [3:0] dash_w = {1'b0, s_y[7:5]} + 4'd1;

    wire signed [10:0] dx = $signed({1'b0, x}) + Ae;    // x - centre
    wire        [9:0]  d  = dx[10] ? ~dx[9:0] : dx[9:0]; // |dx|, or |dx| - 1 when negative

    wire [3:0] band   = z[3:0] + d_hi;
    wire       stripe = band[3] & (s_y[7:5] != 3'b000);  // no stripes for s_y < 32

    // ---- mountains: a triangle wave indexed by x + h, so they slide as you turn
    wire [6:0] u      = x[6:0] + h[6:0];
    wire [4:0] tri_w  = u[5] ? ~u[4:0] : u[4:0];
    wire [5:0] mh     = {1'b0, tri_w} + (u[6] ? {2'b00, tri_w[4:1]} : 6'd0);
    wire       peak   = ({1'b0, ~y[6:0]} < {2'b00, mh});  // 127 - y < height

    // ---- traffic. Scanning down, the last row with z >= zc is a car's base. Its Ae and s_y are stored there, and
    // the next frame draws from them, so the car is upright: one width and one
    // position for all its rows. Written only at the base row, so no second copy.
    reg on_slow, on_onc;
    reg signed [10:0] ae_slow, ae_onc;
    reg        [7:0]  s_slow, s_onc;
    wire on_slow_next = (zs >= zc_slow);
    wire on_onc_next  = (zs >= zc_onc);
    reg  base_ok, cap_slow, cap_onc;
    always @(posedge clk) begin
        base_ok  <= (y >= 10'd129) && (y <= 10'd382);   // rows 1..254
        cap_slow <= latch && base_ok && on_slow && !on_slow_next;
        cap_onc  <= latch && base_ok && on_onc  && !on_onc_next;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            on_slow <= 1'b0;
            on_onc  <= 1'b0;
            s_slow  <= 8'd0;
            s_onc   <= 8'd0;
            ae_slow <= 11'd0;
            ae_onc  <= 11'd0;
        end else begin
            if (latch) begin
                on_slow <= on_slow_next;
                on_onc  <= on_onc_next;
            end
            if (cap_slow) begin
                ae_slow <= Ae;
                s_slow  <= s_y;
            end
            if (cap_onc) begin
                ae_onc <= Ae;
                s_onc  <= s_y;
            end
            if (clr_slow) s_slow <= 8'd0;
            if (clr_onc)  s_onc  <= 8'd0;
        end
    end

    // Each car's column offset from the near edge of its rear face, with one
    // adder: the slow car (right of its reference) is x + Ae - s/4, and the
    // oncoming car is ~(x + Ae + s/4). Both constants change only at the base row.
    reg signed [10:0] k_slow, k_onc;
    always @(posedge clk) begin
        k_slow <= ae_slow - $signed({5'b00000, s_slow[7:2]});
        k_onc  <= ae_onc  + $signed({5'b00000, s_onc[7:2]});
    end
    wire [10:0] u_slow =   $signed({1'b0, x}) + k_slow;
    wire [10:0] u_onc  = ~($signed({1'b0, x}) + k_onc);
    reg  [10:0] u_slow_q, u_onc_q;
    // row tests for the next pixel stage, from y one clock sooner
    reg rows_slow_q, rows_onc_q, win_slow_q, win_onc_q;
    reg [7:0] col_b_q;
    wire [8:0] top_slow = {2'b00, s_slow[7:1]} + {4'b0000, s_slow[7:3]};
    wire [8:0] top_onc  = {2'b00, s_onc[7:1]}  + {4'b0000, s_onc[7:3]};
    always @(posedge clk) begin
        rows_slow_q <= ({1'b0, s_now} >= top_slow) && (s_now <= s_slow);
        rows_onc_q  <= ({1'b0, s_now} >= top_onc)  && (s_now <= s_onc);
        win_slow_q  <= ({1'b0, s_now} < top_slow + {4'b0000, s_slow[7:3]});
        win_onc_q   <= ({1'b0, s_now} < top_onc  + {3'b000, s_onc[7:2]});
        col_b_q     <= {1'b0, s_now[7:1]} + {2'b00, s_now[7:2]};
    end

    wire [7:0] col_a  = {2'b00, s_y[7:2]};

    // ---- score, on the dashboard
    wire [1:0] score_code;
    score_display score (.clk(clk), .v(v), .x(x), .y(y_w), .tens(tens), .ones(ones), .code(score_code));

    // ---- static interior
    wire [2:0] inner_code;
    interior cockpit (.x(x), .y(y), .code(inner_code));

    // ---- steering wheel, drawn over everything else
    // The angle comes from far across the chip and only changes in vertical
    // blanking, so a local copy takes that distance off the per-pixel path.
    reg signed [2:0] angle;
    always @(posedge clk)
        angle <= wheel;
    wire [1:0] wheel_code;
    steering_wheel #(.FULL(WHEEL_FULL)) steer (
        .clk(clk), .x(x), .y(y_w), .w(angle), .code(wheel_code)
    );

    // ---- stage 1 registers. Everything else used below depends only on y,
    // or changes only during blanking, so it is the same for the pixel one
    // clock earlier (at a line change that pixel is in blanking anyway).
    reg [9:0] d_q;
    reg [1:0] wheel_q;
    reg [2:0] inner_q;
    reg [1:0] score_q;
    reg       left_q;
    reg       peak_q, active_q, dither_q;
    always @(posedge clk) begin
        d_q      <= d;
        left_q   <= dx[10];
        u_slow_q   <= u_slow;
        u_onc_q    <= u_onc;
        score_q  <= score_code;
        inner_q  <= inner_code;
        wheel_q  <= WHEEL_FULL ? wheel_code : {1'b0, wheel_code[0]};
        peak_q   <= peak;
        dither_q <= y[4] & (x[0] ^ y[0]);       // checkerboard in each band's lower half
        active_q <= active;
    end

    // ---- stage 2
    // when the road curves, its last rows are grass: it bends out of sight
    reg curved;
    always @(posedge clk)
        curved <= (kappa[2:0] ^ {3{kappa[3]}}) != 3'd0;
    wire near_horizon = (s_y[7:4] == 4'd0) & (~s_y[3] | (s_y[2:0] == 3'd0));
    wire [1:0] slow_kind;       // 0 none, 1 body, 3 lamp
    wire [1:0] onc_kind;
    wire       slow_side, onc_side;
    car_shape shape_slow (.s(s_slow), .rows(rows_slow_q), .window(win_slow_q), .u(u_slow_q),
                          .road_side(~left_q), .d(d_q), .col_a(col_a), .col_b(col_b_q),
                          .kind(slow_kind), .side(slow_side));
    car_shape shape_onc  (.s(s_onc), .rows(rows_onc_q), .window(win_onc_q), .u(u_onc_q),
                          .road_side(left_q), .d(d_q), .col_a(col_a), .col_b(col_b_q),
                          .kind(onc_kind), .side(onc_side));
    always @(*) begin
        if (!active_q)
            rgb = 6'b00_00_00;
        else if (wheel_q != 2'd0)
            rgb = (wheel_q == 2'd1) ? WHEEL0 : (wheel_q == 2'd2) ? BAR_COL : WHEEL1;
        else if (score_q == 2'd2)
            rgb = BAR_COL;
        else if (score_q == 2'd1)
            rgb = PANEL_COL;
        else if (inner_q == 3'd1 || inner_q == 3'd3)
            rgb = COCKPIT;
        else if (inner_q == 3'd2)
            rgb = MIRROR;
        else if (inner_q == 3'd5)
            rgb = VENT_COL;
        else if (inner_q == 3'd4)
            rgb = PANEL_COL;
        else if (sky)
            rgb = peak_q ? MOUNTAIN :
                  (y_q[6:5] == 2'd0) ? (dither_q ? SKY1 : SKY0) :
                  (y_q[6:5] == 2'd1) ? (dither_q ? SKY2 : SKY1) :
                  (y_q[6:5] == 2'd2) ? (dither_q ? SKY3 : SKY2) :
                                       (dither_q ? SKY4 : SKY3);
        else if (dash)
            rgb = DASH_COL;
        else if ((s_y == 8'd0) || (near_horizon && curved))
            rgb = GRASS0;
        else if (onc_kind != 2'd0)
            rgb = (onc_kind == 2'd1) ? ONC_BODY : (onc_kind == 2'd2) ? ONC_GLASS : ONC_LAMP;
        else if (onc_side)
            rgb = ONC_SIDE;
        else if (slow_kind != 2'd0)
            rgb = (slow_kind == 2'd1) ? SLOW_BODY : (slow_kind == 2'd2) ? SLOW_GLASS : SLOW_LAMP;
        else if (slow_side)
            rgb = SLOW_SIDE;
        else if (stripe && d_q < {6'd0, dash_w})
            rgb = LINE_COL;
        else if (d_q < {2'b00, s_y})
            rgb = stripe ? TARMAC1 : TARMAC0;
        else if (d_q < {1'b0, kerb_w})
            rgb = stripe ? KERB1 : KERB0;
        else
            rgb = stripe ? GRASS1 : GRASS0;

        // side window: the world, with each colour channel halved
        if (inner_q == 3'd6 && active_q)
            rgb = {1'b0, rgb[5], 1'b0, rgb[3], 1'b0, rgb[1]};
        if (flash && active_q)
            rgb[5:4] = 2'b11;
    end
    wire _unused = &{h[7], band[2:0], 1'b0};
endmodule
