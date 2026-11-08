/*
 * Road racer, stage 1: pseudo-3D road with speed, steering and heading,
 * distant mountains, a speed bar and engine sound.
 *
 * Inputs : ui_in[0] left, ui_in[1] right, ui_in[2] accelerate, ui_in[3] brake
 * Outputs: uo_out = Tiny VGA PMOD (RGB222 + syncs)
 *          uio[0] = audio (PWM, needs an RC filter on real hardware)
 *
 * Rename the module to tt_um_<your GitHub username>_... before pushing.
 */
`default_nettype none

module tt_um_road_racer #(
    parameter WHEEL_FULL = 1        // 0: small wheel for 1x1, 1: full wheel for 1x2
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    // ---- reset, registered once: the input pin arrives late in the clock and
    // fans out to about a hundred registers, so the inside uses a flip-flop
    reg rst_q;
    always @(posedge clk)
        rst_q <= rst_n;

    // ---- timing
    wire [9:0] x, y;
    wire hsync, vsync, active, frame, line_end;
    vga_timing vga (
        .clk(clk), .rst_n(rst_q), .x(x), .y(y),
        .hsync(hsync), .vsync(vsync), .active(active), .frame(frame),
        .line_end(line_end)
    );

    // ---- buttons
    wire [3:0] btn;
    ip_input_sync #(.N(4)) sync (.clk(clk), .in(ui_in[3:0]), .out(btn));

    // ---- car state, once per frame
    wire        [7:0] v;
    wire signed [2:0] wheel;
    wire signed [7:0] h;
    wire signed [7:0] p;
    wire        [8:0] D;
    wire              offroad;
    wire signed [3:0] kappa;
    wire       [11:0] slow, onc;
    wire              clr_slow, clr_onc;
    wire              flash;
    wire        [3:0] tens, ones;
    car_state car (
        .clk(clk), .rst_n(rst_q), .frame(frame),
        .left(btn[0]), .right(btn[1]), .accel(btn[2]), .brake(btn[3]),
        .v(v), .wheel(wheel), .h(h), .p(p), .D(D), .offroad(offroad), .kappa(kappa),
        .slow(slow), .onc(onc), .clr_slow(clr_slow), .clr_onc(clr_onc), .flash(flash),
        .tens(tens), .ones(ones)
    );

    // ---- per-line values
    wire        [10:0] z;
    wire signed [10:0] Ae;
    wire        [10:0] zs;
    wire               z_latch;
    line_setup #(.Z_BITS(11)) line (
        .clk(clk), .rst_n(rst_q), .x(x), .y(y), .h(h), .p(p),
        .kappa(kappa), .z(z), .Ae(Ae), .zs(zs), .latch(z_latch)
    );

    // ---- per-pixel colour
    wire [5:0] rgb;
    pixel_colour #(.WHEEL_FULL(WHEEL_FULL)) pix (
        .clk(clk), .rst_n(rst_q), .x(x), .y(y), .active(active), .z(z[3:0]), .Ae(Ae), .h(h),
        .d_hi(D[8:5]), .wheel(wheel), .v(v), .zs(zs), .latch(z_latch),
        .zc_slow(slow[11:1]), .zc_onc(onc[11:1]), .clr_slow(clr_slow), .clr_onc(clr_onc),
        .flash(flash), .kappa(kappa), .tens(tens), .ones(ones), .rgb(rgb)
    );

    // ---- sound
    wire [7:0] sample;
    wire       audio;
    engine_audio engine (
        .clk(clk), .rst_n(rst_q), .tick(line_end), .v(v),
        .offroad(offroad | flash), .pwm_count(x[7:0]), .sample(sample), .out(audio)
    );

    // ---- outputs, registered so every pin changes on the same clock edge.
    // pixel_colour has one pipeline stage, so the syncs are delayed one clock
    // to stay lined up with the colour.
    // Tiny VGA PMOD order: {hsync, B0, G0, R0, vsync, B1, G1, R1}
    reg hsync_q, vsync_q;
    reg [7:0] vga_out;
    always @(posedge clk) begin
        hsync_q <= hsync;
        vsync_q <= vsync;
        vga_out <= {hsync_q, rgb[0], rgb[2], rgb[4], vsync_q, rgb[1], rgb[3], rgb[5]};
    end

    assign uo_out  = vga_out;
    assign uio_out = {7'b0000000, audio};
    assign uio_oe  = 8'b0000_0001;

    wire _unused = &{ena, uio_in, ui_in[7:4], D[4:0], z[10:4], slow[0], onc[0], frame, sample, 1'b0};
endmodule
