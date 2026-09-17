// =============================================================================
// cordic_stage.sv -- one registered CORDIC iteration (circular coordinates)
//
//   x' = x - d * (y >>> I)
//   y' = y + d * (x >>> I)
//   z' = z - d * atan(2^-I)
//
//   rotation  (mode 0): d = +1 when z >= 0, else -1   (drives z -> 0)
//   vectoring (mode 1): d = +1 when y <  0, else -1   (drives y -> 0)
//
// Shifts are wired (constant I), so a stage is three add/sub units and
// nothing else: no multiplier anywhere. The shift truncates toward -inf,
// which is exactly floor(v / 2^I) in matlab/cordic_fixed.m.
// =============================================================================
module cordic_stage #(
    parameter int    WI     = 22,          // x/y internal width
    parameter int    WZ     = 21,          // angle internal width (BAM: 2^(WZ-1) == pi)
    parameter int    I      = 0,           // iteration index == shift amount
    parameter [31:0] ATAN32 = 32'd0        // atan(2^-I) with pi == 2^31
) (
    input  logic                 clk,
    input  logic                 mode_i,
    input  logic signed [WI-1:0] x_i,
    input  logic signed [WI-1:0] y_i,
    input  logic signed [WZ-1:0] z_i,
    output logic                 mode_o,
    output logic signed [WI-1:0] x_o,
    output logic signed [WI-1:0] y_o,
    output logic signed [WZ-1:0] z_o
);
    // round the 32-bit constant half-up to WZ bits (same expression as the model)
    localparam [31:0]          ATAN_R = (ATAN32 + (32'd1 << (31 - WZ))) >> (32 - WZ);
    localparam signed [WZ-1:0] ATAN   = ATAN_R[WZ-1:0];

    logic                 d_neg;           // 1: d = -1
    logic signed [WI-1:0] x_sh, y_sh;

    assign d_neg = mode_i ? ~y_i[WI-1] : z_i[WZ-1];
    assign x_sh  = x_i >>> I;
    assign y_sh  = y_i >>> I;

    always_ff @(posedge clk) begin
        mode_o <= mode_i;
        x_o    <= d_neg ? x_i + y_sh : x_i - y_sh;
        y_o    <= d_neg ? y_i - x_sh : y_i + x_sh;
        z_o    <= d_neg ? z_i + ATAN : z_i - ATAN;   // wraps: BAM arithmetic is modular
    end
endmodule
