// =============================================================================
// cordic_pipeline.sv -- N_ITER unrolled cordic_stage instances + valid pipeline
//
// Feed-forward: no stage depends on a later one, so a new sample enters every
// clock (initiation interval 1) and latency is exactly N_ITER cycles.
// =============================================================================
module cordic_pipeline #(
    parameter int N_ITER = 15,
    parameter int WI     = 22,
    parameter int WZ     = 21
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 valid_i,
    input  logic                 mode_i,
    input  logic signed [WI-1:0] x_i,
    input  logic signed [WI-1:0] y_i,
    input  logic signed [WZ-1:0] z_i,
    output logic                 valid_o,
    output logic                 mode_o,
    output logic signed [WI-1:0] x_o,
    output logic signed [WI-1:0] y_o,
    output logic signed [WZ-1:0] z_o
);
    `include "cordic_atan_lut.svh"

    logic signed [WI-1:0] x [0:N_ITER];
    logic signed [WI-1:0] y [0:N_ITER];
    logic signed [WZ-1:0] z [0:N_ITER];
    logic [N_ITER:0]      mode;
    logic [N_ITER-1:0]    valid;

    assign x[0] = x_i;
    assign y[0] = y_i;
    assign z[0] = z_i;
    assign mode[0] = mode_i;

    for (genvar i = 0; i < N_ITER; i++) begin : g_stage
        cordic_stage #(
            .WI(WI), .WZ(WZ), .I(i), .ATAN32(cordic_atan32(i))
        ) u_stage (
            .clk(clk),
            .mode_i(mode[i]),   .x_i(x[i]),   .y_i(y[i]),   .z_i(z[i]),
            .mode_o(mode[i+1]), .x_o(x[i+1]), .y_o(y[i+1]), .z_o(z[i+1])
        );
    end

    // only the valid bits are reset; the datapath is don't-care until valid
    always_ff @(posedge clk) begin
        if (rst) valid <= '0;
        else     valid <= {valid[N_ITER-2:0], valid_i};
    end

    assign valid_o = valid[N_ITER-1];
    assign mode_o  = mode[N_ITER];
    assign x_o     = x[N_ITER];
    assign y_o     = y[N_ITER];
    assign z_o     = z[N_ITER];
endmodule
