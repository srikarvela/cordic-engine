// =============================================================================
// cordic_gain_scale.sv -- multiplier-free 1/K_N pre-scale
//
// N rotations stretch the vector by K_N = prod sqrt(1 + 2^-2i) ~= 1.64676.
// Compensating at the input keeps the output exact-scale without putting a
// multiplier after the pipeline. The constant C = round(2^W / K_N) is recoded
// at elaboration into canonical signed digits (no two adjacent non-zeros, so
// about W/3 terms), and the product is built from shifted copies of the input:
//
//     v * C = sum_k  digit_k * (v << k),   digit_k in {-1, 0, +1}
//
// The sum is exact (full product width), then rounded half-up back to the
// internal format -- identical to floor((v*C + 2^(W-1)) / 2^W) in the model.
// Three register stages so this block never limits Fmax: four partial sums
// (one per quarter of the digit positions -- CSD guarantees at most three
// non-zero digits in each, i.e. a single ternary-adder level), then pairwise
// adds with the rounding constant folded in, then the final add.
// =============================================================================
module cordic_gain_scale #(
    parameter int N_ITER = 15,
    parameter int W      = 17,
    parameter int G      = 4
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  valid_i,
    input  logic                  mode_i,
    input  logic signed [W+G:0]   x_i,
    input  logic signed [W+G:0]   y_i,
    input  logic signed [W+G-1:0] z_i,
    output logic                  valid_o,
    output logic                  mode_o,
    output logic signed [W+G:0]   x_o,
    output logic signed [W+G:0]   y_o,
    output logic signed [W+G-1:0] z_o
);
    `include "cordic_atan_lut.svh"

    localparam int WI = W + 1 + G;
    localparam int WZ = W + G;
    localparam int WP = WI + W + 1;                 // full product width
    localparam int ND = W + 1;                      // CSD digit positions
    localparam int K1 = ND / 4, K2 = ND / 2, K3 = (3 * ND) / 4;   // quarter splits

    // C = round_half_up(invk32 >> (32 - W)), 0 < C < 2^W
    localparam [31:0] C = (cordic_invk32(N_ITER) + (32'd1 << (31 - W))) >> (32 - W);

    // canonical-signed-digit recoding; sel = 0 -> +1 digit mask, 1 -> -1 digit mask
    function automatic [ND-1:0] csd_mask(input [31:0] cval, input bit sel);
        logic [32:0] c;
        csd_mask = '0;
        c = {1'b0, cval};
        for (int k = 0; k < ND; k++) begin
            if (c[0]) begin
                if (c[1]) begin
                    if (sel)  csd_mask[k] = 1'b1;   // ...11 -> digit -1, carry up
                    c = c + 33'd1;
                end else begin
                    if (!sel) csd_mask[k] = 1'b1;   // ...01 -> digit +1
                    c = c - 33'd1;
                end
            end
            c = c >> 1;
        end
    endfunction

    localparam [ND-1:0] CSD_POS = csd_mask(C, 1'b0);
    localparam [ND-1:0] CSD_NEG = csd_mask(C, 1'b1);

    // shift-add partial sum over digit positions [lo, hi)
    function automatic signed [WP-1:0] csd_sum(input signed [WI-1:0] v, input int lo, input int hi);
        logic signed [WP-1:0] ve;
        ve      = WP'(v);
        csd_sum = '0;
        for (int k = 0; k < ND; k++) begin          // constant bounds: synthesisable unroll
            if (k >= lo && k < hi) begin
                if (CSD_POS[k]) csd_sum = csd_sum + (ve <<< k);
                if (CSD_NEG[k]) csd_sum = csd_sum - (ve <<< k);
            end
        end
    endfunction

    logic signed [WP-1:0] x_p [0:3], y_p [0:3];     // stage 1: quarter partial sums
    logic signed [WP-1:0] x_s [0:1], y_s [0:1];     // stage 2: pairwise
    logic signed [WP-1:0] x_f, y_f;
    logic signed [WZ-1:0] z_q [0:1];
    logic [1:0]           valid_q, mode_q;

    localparam signed [WP-1:0] ROUND = WP'(1) <<< (W - 1);

    assign x_f = (x_s[0] + x_s[1]) >>> W;
    assign y_f = (y_s[0] + y_s[1]) >>> W;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_q <= '0;
            valid_o <= 1'b0;
        end else begin
            valid_q <= {valid_q[0], valid_i};
            valid_o <= valid_q[1];
        end

        // stage 1: partial products
        x_p[0] <= csd_sum(x_i, 0, K1);   x_p[1] <= csd_sum(x_i, K1, K2);
        x_p[2] <= csd_sum(x_i, K2, K3);  x_p[3] <= csd_sum(x_i, K3, ND);
        y_p[0] <= csd_sum(y_i, 0, K1);   y_p[1] <= csd_sum(y_i, K1, K2);
        y_p[2] <= csd_sum(y_i, K2, K3);  y_p[3] <= csd_sum(y_i, K3, ND);
        z_q[0] <= z_i;  mode_q[0] <= mode_i;

        // stage 2: pairwise adds, rounding constant folded in
        x_s[0] <= x_p[0] + x_p[1] + ROUND;  x_s[1] <= x_p[2] + x_p[3];
        y_s[0] <= y_p[0] + y_p[1] + ROUND;  y_s[1] <= y_p[2] + y_p[3];
        z_q[1] <= z_q[0];  mode_q[1] <= mode_q[0];

        // stage 3: final add, >> W (round half-up), back to the internal format
        x_o <= x_f[WI-1:0];  y_o <= y_f[WI-1:0];
        z_o <= z_q[1];       mode_o <= mode_q[1];
    end
endmodule
