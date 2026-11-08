// Car state, updated once per frame on the frame pulse.
//   v      speed, 0..192
//   wheel  wheel angle, -2..2, centres itself when no steering button is held
//   h      heading in pixels (f * psi), stops growing past +/-96
//   P      sideways position with 6 fraction bits; p = P >>> 6, road edge at |p| = 64,
//          stops moving outwards past |p| = 96
//   D      distance travelled, 9 bits, wraps (only its top bits are used)
//   track  counts D wrapping; its top 4 bits are the track segment
//   kappa  road curvature, moves one step towards the segment's value per wrap
// Matches Car.frame() in road_model.py.
`default_nettype none

module car_state (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              frame,
    input  wire              left,
    input  wire              right,
    input  wire              accel,
    input  wire              brake,
    output reg         [7:0] v,
    output reg  signed [2:0] wheel,
    output reg  signed [7:0] h,
    output wire signed [7:0] p,
    output reg         [8:0] D,
    output reg               offroad,
    output reg  signed [3:0] kappa
);
    localparam [7:0] V_MAX = 8'd192;

    reg signed [13:0] P;
    reg        [2:0]  n;          // frame counter for coasting drag

    assign p = P[13:6];           // same as P >>> 6
    // |p| >= 72 without working out |p|: compare against constants. Registered:
    // P changes only on step_p, long before the next frame pulse reads it.
    always @(posedge clk)
        offroad <= (p >= 8'sd72) || (p <= -8'sd72);

    // ---- speed: one small signed step, one adder, clamp at zero
    reg signed [3:0] d;
    always @(*) begin
        if (offroad && v > 8'd96) d = brake ? -4'sd4 : -4'sd2;   // grass drag
        else if (accel)           d = (v == V_MAX) ? 4'sd0 : 4'sd1;
        else if (brake)           d = -4'sd4;
        else if (n == 3'd0)       d = -4'sd1;
        else                      d = 4'sd0;
    end
    // The step is registered every clock; its inputs (buttons, v, n, offroad)
    // are all steady before the frame pulse, so the pulse just adds it.
    reg signed [3:0] d_q;
    always @(posedge clk)
        d_q <= d;
    wire signed [8:0] v_sum = $signed({1'b0, v}) + {{5{d_q[3]}}, d_q};
    wire        [7:0] v1    = v_sum[8] ? 8'd0 : v_sum[7:0];

    // ---- wheel angle
    reg signed [2:0] wheel1;
    always @(*) begin
        if (left && !right)       wheel1 = (wheel == -3'sd2) ? -3'sd2 : wheel - 3'sd1;
        else if (right && !left)  wheel1 = (wheel ==  3'sd2) ?  3'sd2 : wheel + 3'sd1;
        else if (wheel[2])        wheel1 = wheel + 3'sd1;
        else if (wheel != 3'sd0)  wheel1 = wheel - 3'sd1;
        else                      wheel1 = 3'sd0;
    end

    // The update is spread over three clocks so each clock has one adder:
    //   frame     speed, wheel and frame counter
    //   step_k    (the speed factor k is registered from the new speed)
    //   step_h    heading, from the registered speed factor and wheel
    //   step_p    position and distance, from the registered heading
    // This gives exactly the same result as doing it all at once, in the same
    // order as road_model.py, and it is all done within 4 clocks of the pulse.
    reg step_k, step_h, step_p;

    // ---- the track: 16 segments of 64 wraps of D (see TRACK in road_model.py)
    reg        [9:0] track;
    reg signed [3:0] target;
    always @(*) begin
        case (track[9:6])
            4'd2, 4'd3:   target =  4'sd5;
            4'd5, 4'd6:   target = -4'sd6;
            4'd8:         target =  4'sd7;
            4'd9:         target = -4'sd8;
            4'd11, 4'd12: target = -4'sd5;
            4'd13:        target =  4'sd6;
            default:      target =  4'sd0;
        endcase
    end
    wire [9:0] D_sum = {1'b0, D} + {2'b00, v};

    // ---- speed factor 0, 1 or 2: multiplying by it is a shift
    reg k1, k2;                   // registered: v changes only on the frame pulse
    always @(posedge clk) begin
        k1 <= v[6] & ~v[7];       // 64 <= v < 128
        k2 <= v[7];               // v >= 128
    end

    // limits: value >= 96 or value <= -97, from the top three bits only
    function at_limit(input [2:0] top, input step_neg, input step_zero);
        at_limit = !step_zero && (step_neg ? (top == 3'b100) : (top == 3'b011));
    endfunction

    // heading: h + wheel*k, held once it passes +/-96
    wire signed [7:0] w8  = {{5{wheel[2]}}, wheel};
    // a hard bend, |kappa| >= 4, pushes the heading outwards
    wire              push  = kappa[2] ^ kappa[3];
    wire signed [7:0] steer = !push ? w8 : kappa[3] ? w8 + 8'sd1 : w8 - 8'sd1;
    wire signed [7:0] dh  = k2 ? (steer <<< 1) : (k1 ? steer : 8'sd0);
    wire              h_stop = at_limit(h[7:5], steer[7], (steer == 8'sd0) || !(k1 || k2));
    wire signed [7:0] h1  = h_stop ? h : h + dh;

    // position: P + h*k, held once |p| passes 96
    wire signed [13:0] h14   = {{6{h[7]}}, h};
    wire signed [13:0] dP    = k2 ? (h14 <<< 1) : (k1 ? h14 : 14'sd0);
    wire               P_stop = at_limit(P[13:11], h[7], (h == 8'sd0) || !(k1 || k2));
    wire signed [13:0] P1    = P_stop ? P : P + dP;

    always @(posedge clk) begin
        if (!rst_n) begin
            v      <= 8'd0;
            wheel  <= 3'sd0;
            h      <= 8'sd0;
            P      <= 14'sd0;
            D      <= 9'd0;
            track  <= 10'd0;
            kappa  <= 4'sd0;
            n      <= 3'd0;
            step_k <= 1'b0;
            step_h <= 1'b0;
            step_p <= 1'b0;
        end else begin
            step_k <= frame;
            step_h <= step_k;
            step_p <= step_h;
            if (frame) begin
                v     <= v1;
                wheel <= wheel1;
                n     <= n + 3'd1;
            end
            if (step_h)
                h <= h1;
            if (step_p) begin
                P <= P1;
                D <= D_sum[8:0];
                if (D_sum[9]) begin
                    track <= track + 10'd1;
                    if (kappa != target)
                        kappa <= (kappa < target) ? kappa + 4'sd1 : kappa - 4'sd1;
                end
            end
        end
    end
endmodule
