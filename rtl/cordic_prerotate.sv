// =============================================================================
// cordic_prerotate.sv -- quadrant reduction into the CORDIC convergence range
//
// The iterations can only absorb sum(atan(2^-i)) ~= 99.88 degrees, so inputs
// outside +/-90 degrees are first rotated by exactly +/-90 -- a swap and a
// negate, no arithmetic on the magnitude:
//
//   rotation : z in [ pi/2,  pi)  -> (x,y) = (-y, x), z -= pi/2
//              z in [-pi, -pi/2)  -> (x,y) = ( y,-x), z += pi/2
//   vectoring: x < 0, y <  0      -> (x,y) = (-y, x), z -= pi/2
//              x < 0, y >= 0      -> (x,y) = ( y,-x), z += pi/2
//
// With a binary angle the rotation-mode test is just the top two bits of z.
// Inputs are widened to the internal format first (1 growth bit + G guard
// bits), so negating the most-negative input cannot overflow.
// =============================================================================
module cordic_prerotate #(
    parameter int W = 17,
    parameter int G = 4
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    valid_i,
    input  logic                    mode_i,          // 0 rotation, 1 vectoring
    input  logic signed [W-1:0]     x_i,
    input  logic signed [W-1:0]     y_i,
    input  logic signed [W-1:0]     z_i,
    output logic                    valid_o,
    output logic                    mode_o,
    output logic signed [W+G:0]     x_o,
    output logic signed [W+G:0]     y_o,
    output logic signed [W+G-1:0]   z_o
);
    localparam int WI = W + 1 + G;
    localparam int WZ = W + G;
    localparam signed [WZ-1:0] HALF_PI = {2'b01, {(WZ-2){1'b0}}};

    logic signed [WI-1:0] xe, ye;
    logic signed [WZ-1:0] ze;
    logic                 rot_p90, rot_n90;

    assign xe = {x_i[W-1], x_i, {G{1'b0}}};
    assign ye = {y_i[W-1], y_i, {G{1'b0}}};
    assign ze = {z_i, {G{1'b0}}};

    assign rot_p90 = mode_i ? (x_i[W-1] &  y_i[W-1]) : (z_i[W-1:W-2] == 2'b01);
    assign rot_n90 = mode_i ? (x_i[W-1] & ~y_i[W-1]) : (z_i[W-1:W-2] == 2'b10);

    always_ff @(posedge clk) begin
        if (rst) valid_o <= 1'b0;
        else     valid_o <= valid_i;

        mode_o <= mode_i;
        x_o    <= rot_p90 ? -ye : rot_n90 ?  ye : xe;
        y_o    <= rot_p90 ?  xe : rot_n90 ? -xe : ye;
        z_o    <= rot_p90 ? ze - HALF_PI : rot_n90 ? ze + HALF_PI : ze;
    end
endmodule
