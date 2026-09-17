// =============================================================================
// cordic_top.sv -- pipelined CORDIC engine, rotation + vectoring
//
//   mode 0 (rotation) : (x_o, y_o) = (x, y) rotated by z      z_o -> ~0
//                       x = 1.0, y = 0  gives  x_o = cos z, y_o = sin z
//   mode 1 (vectoring): x_o = sqrt(x^2 + y^2),  y_o -> ~0,
//                       z_o = z + atan2(y, x)
//
// Formats
//   x, y : W-bit signed fixed point. The engine is format-agnostic; the golden
//          model and testbenches read it as Q2.(W-2), i.e. 1.0 == 2^(W-2).
//   z    : W-bit signed binary angle, 2^(W-1) == pi. Wraps like a real angle.
//
// Pipeline (latency N_ITER + 6, one result per clock, no back-pressure):
//   prerotate(1) -> gain_scale(3) -> N_ITER stages -> round(1) -> saturate(1)
// Round and saturate are separate registers: together they were the critical
// path (rounding carry chain into the clamp compare), ahead of any CORDIC stage.
//
// Word growth: the internal datapath is W + 1 + G bits -- one growth bit so a
// full-scale diagonal (|v| = sqrt(2) FS) cannot wrap mid-pipeline, and G guard
// LSBs (default ceil(log2 N_ITER)) that absorb the per-stage truncation noise.
// Guard bits are rounded away half-up at the output and x/y SATURATE to W
// bits; mode is sampled per transaction and travels with the data.
// =============================================================================
module cordic_top #(
    parameter int N_ITER = 15,
    parameter int W      = 17,
    parameter int G      = $clog2(N_ITER)
) (
    input  logic                clk,
    input  logic                rst,          // synchronous, clears valid bits only
    input  logic                valid_i,
    input  logic                mode_i,       // 0 rotation, 1 vectoring
    input  logic signed [W-1:0] x_i,
    input  logic signed [W-1:0] y_i,
    input  logic signed [W-1:0] z_i,
    output logic                valid_o,
    output logic                mode_o,
    output logic signed [W-1:0] x_o,
    output logic signed [W-1:0] y_o,
    output logic signed [W-1:0] z_o
);
    localparam int WI = W + 1 + G;
    localparam int WZ = W + G;

    logic                 v_pre, v_scl, v_cor, m_pre, m_scl, m_cor;
    logic signed [WI-1:0] x_pre, y_pre, x_scl, y_scl, x_cor, y_cor;
    logic signed [WZ-1:0] z_pre, z_scl, z_cor;

    cordic_prerotate #(.W(W), .G(G)) u_prerotate (
        .clk(clk), .rst(rst),
        .valid_i(valid_i), .mode_i(mode_i), .x_i(x_i), .y_i(y_i), .z_i(z_i),
        .valid_o(v_pre),   .mode_o(m_pre),  .x_o(x_pre), .y_o(y_pre), .z_o(z_pre)
    );

    cordic_gain_scale #(.N_ITER(N_ITER), .W(W), .G(G)) u_gain_scale (
        .clk(clk), .rst(rst),
        .valid_i(v_pre), .mode_i(m_pre), .x_i(x_pre), .y_i(y_pre), .z_i(z_pre),
        .valid_o(v_scl), .mode_o(m_scl), .x_o(x_scl), .y_o(y_scl), .z_o(z_scl)
    );

    cordic_pipeline #(.N_ITER(N_ITER), .WI(WI), .WZ(WZ)) u_pipeline (
        .clk(clk), .rst(rst),
        .valid_i(v_scl), .mode_i(m_scl), .x_i(x_scl), .y_i(y_scl), .z_i(z_scl),
        .valid_o(v_cor), .mode_o(m_cor), .x_o(x_cor), .y_o(y_cor), .z_o(z_cor)
    );

    // ---- output: drop guard bits (round half-up), saturate x/y, wrap z ---------
    localparam signed [W-1:0] MAX_POS = {1'b0, {(W-1){1'b1}}};
    localparam signed [W-1:0] MAX_NEG = {1'b1, {(W-1){1'b0}}};

    logic signed [WI:0] x_rnd, y_rnd, x_rq, y_rq;   // one extra bit for the rounding carry
    logic signed [WZ:0] z_rnd;
    logic signed [W-1:0] z_rq;
    logic               v_rq, m_rq;

    if (G > 0) begin : g_round
        assign x_rnd = (x_cor + (WI+1)'(1 <<< (G-1))) >>> G;
        assign y_rnd = (y_cor + (WI+1)'(1 <<< (G-1))) >>> G;
        assign z_rnd = (z_cor + (WZ+1)'(1 <<< (G-1))) >>> G;
    end else begin : g_noround
        assign x_rnd = x_cor;
        assign y_rnd = y_cor;
        assign z_rnd = z_cor;
    end

    function automatic signed [W-1:0] sat(input signed [WI:0] v);
        if      (v > $signed({{(WI+1-W){1'b0}}, MAX_POS})) sat = MAX_POS;
        else if (v < $signed({{(WI+1-W){1'b1}}, MAX_NEG})) sat = MAX_NEG;
        else                                               sat = v[W-1:0];
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            v_rq    <= 1'b0;
            valid_o <= 1'b0;
        end else begin
            v_rq    <= v_cor;
            valid_o <= v_rq;
        end

        // round
        m_rq <= m_cor;  x_rq <= x_rnd;  y_rq <= y_rnd;  z_rq <= z_rnd[W-1:0];
        // saturate
        mode_o <= m_rq;
        x_o    <= sat(x_rq);
        y_o    <= sat(y_rq);
        z_o    <= z_rq;
    end
endmodule
