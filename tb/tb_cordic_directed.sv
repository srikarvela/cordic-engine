// =============================================================================
// tb_cordic_directed.sv -- directed tests, independent of the MATLAB model
//
// Expected values come from the simulator's own real math ($cos, $sin, $atan2,
// $hypot), so this bench would catch an error shared by the RTL and the golden
// model. Tolerance = algorithmic bound 2^-(N-1) rad (times |v| for x/y) plus
// 3 LSB of quantisation --
// the same bound matlab/validate_models.m holds the fixed-point model to.
//
//   rotation : 0, +/-pi/6, pi/4, pi/3, pi/2, quadrant boundaries +/-1 LSB,
//              +/-pi, the +/-99.88 deg convergence limit, non-unit vectors
//   vectoring: axes, all four quadrants, tiny vectors, z offset
//   edges    : exact-zero input, +/-full-scale saturation (clamp, not wrap),
//              valid/reset behaviour, per-sample mode switching
// =============================================================================
`timescale 1ns/1ps
module tb_cordic_directed;
    parameter int N_ITER = 15;
    parameter int W      = 17;
    localparam int  F       = W - 2;
    localparam int  LATENCY = N_ITER + 6;
    localparam real PI      = 3.14159265358979323846;
    localparam real ONE     = 2.0 ** F;
    localparam real RAD     = (2.0 ** (W-1)) / PI;         // radians -> BAM
    localparam real ALG     = 2.0 ** -(N_ITER-1);           // residual angle bound, rad
    localparam real QTOL    = 3.0;                          // quantisation, x/y LSBs
    localparam int  FS      = 1 << (W-1);

    logic clk = 0, rst = 1;
    logic valid_i = 0, mode_i = 0, valid_o, mode_o;
    logic signed [W-1:0] x_i = 0, y_i = 0, z_i = 0, x_o, y_o, z_o;
    integer errors = 0, checks = 0;

    cordic_top #(.N_ITER(N_ITER), .W(W)) dut (.*);
    always #2 clk = ~clk;

    function automatic real absr(input real v); absr = (v < 0.0) ? -v : v; endfunction
    function automatic integer clampi(input real v);
        if (v > FS - 1)   clampi = FS - 1;
        else if (v < -FS) clampi = -FS;
        else              clampi = $rtoi($floor(v + 0.5));
    endfunction
    // wrap-aware BAM difference
    function automatic integer angdiff(input integer a, input integer b);
        angdiff = (a - b) % (2*FS);
        if (angdiff >=  FS) angdiff = angdiff - 2*FS;
        if (angdiff <  -FS) angdiff = angdiff + 2*FS;
    endfunction

    task automatic apply(input bit mode, input integer x, input integer y, input integer z);
        @(posedge clk);
        valid_i <= 1; mode_i <= mode; x_i <= x[W-1:0]; y_i <= y[W-1:0]; z_i <= z[W-1:0];
        @(posedge clk);
        valid_i <= 0; x_i <= 'x; y_i <= 'x; z_i <= 'x;
        repeat (LATENCY - 1) @(posedge clk);
        #1;
        if (valid_o !== 1'b1 || mode_o !== mode) begin
            errors = errors + 1;
            $display("FAIL: valid_o/mode_o wrong %0d cycles after input", LATENCY);
        end
    endtask

    task automatic check_rot(input string name, input integer x, input integer y, input integer z);
        real th, ex, ey, TOL;
        apply(0, x, y, z);
        th = z / RAD;
        TOL = ALG * $hypot(x, y) + QTOL;
        ex = x * $cos(th) - y * $sin(th);
        ey = x * $sin(th) + y * $cos(th);
        checks = checks + 1;
        if (absr(x_o - clampi(ex)) > TOL || absr(y_o - clampi(ey)) > TOL) begin
            errors = errors + 1;
            $display("FAIL rot %-22s in=(%0d,%0d,%0d) got=(%0d,%0d) exp=(%0d,%0d) tol=%0.1f",
                     name, x, y, z, x_o, y_o, clampi(ex), clampi(ey), TOL);
        end else
            $display("ok   rot %-22s -> (%0d, %0d)  err=(%0.1f, %0.1f) LSB",
                     name, x_o, y_o, x_o - ex, y_o - ey);
    endtask

    task automatic check_vec(input string name, input integer x, input integer y, input integer z);
        real mag, tolz, TOL;
        integer ez;
        apply(1, x, y, z);
        mag  = $hypot(x, y);
        TOL  = ALG * mag + QTOL;
        ez   = $rtoi($floor($atan2(y, x) * RAD + 0.5)) + z;
        // phase: algorithmic residual + QTOL LSBs of x/y noise seen from the origin
        tolz = (mag > 0.0) ? (ALG + QTOL / mag) * RAD + 2.0 : 1.0e9;
        checks = checks + 1;
        if (absr(x_o - clampi(mag)) > TOL || absr(angdiff(z_o, ez)) > tolz) begin
            errors = errors + 1;
            $display("FAIL vec %-22s in=(%0d,%0d,%0d) got mag=%0d ang=%0d exp mag=%0d ang=%0d",
                     name, x, y, z, x_o, z_o, clampi(mag), ez);
        end else
            $display("ok   vec %-22s -> mag=%0d ang=%0d  err=(%0.1f LSB, %0d BAM)",
                     name, x_o, z_o, x_o - mag, angdiff(z_o, ez));
    endtask

    integer one, q, lim;
    initial begin
        if ($test$plusargs("WAVES")) begin
            $dumpfile("build/tb_cordic_directed.vcd");
            $dumpvars(0, tb_cordic_directed);
        end
        one = 1 << F;  q = FS / 2;  lim = $rtoi(1.7432866 * RAD);
        $display("tb_cordic_directed: N_ITER=%0d W=%0d tol=%0.2e*|v| + %0.0f LSB", N_ITER, W, ALG, QTOL);
        repeat (4) @(posedge clk);

        // reset holds valid low even with valid_i high
        valid_i <= 1; repeat (LATENCY + 4) @(posedge clk);
        checks = checks + 1;
        if (valid_o !== 1'b0) begin errors = errors + 1; $display("FAIL: valid_o high during reset"); end
        valid_i <= 0; rst <= 0;
        repeat (LATENCY + 2) @(posedge clk);
        if (valid_o !== 1'b0) begin errors = errors + 1; $display("FAIL: valid_o high while idle"); end

        // ---- rotation: known angles ------------------------------------------------
        check_rot("0",              one, 0, 0);
        check_rot("+pi/6",          one, 0,  $rtoi(PI/6 * RAD));
        check_rot("-pi/6",          one, 0, -$rtoi(PI/6 * RAD));
        check_rot("+pi/4",          one, 0,  FS/4);
        check_rot("-pi/4",          one, 0, -FS/4);
        check_rot("+pi/3",          one, 0,  $rtoi(PI/3 * RAD));
        check_rot("-pi/3",          one, 0, -$rtoi(PI/3 * RAD));
        // ---- rotation: quadrant boundaries (pre-rotation decision points) ----------
        check_rot("+pi/2 - 1 LSB",  one, 0,  q - 1);
        check_rot("+pi/2",          one, 0,  q);
        check_rot("+pi/2 + 1 LSB",  one, 0,  q + 1);
        check_rot("-pi/2 + 1 LSB",  one, 0, -q + 1);
        check_rot("-pi/2",          one, 0, -q);
        check_rot("-pi/2 - 1 LSB",  one, 0, -q - 1);
        check_rot("+pi - 1 LSB",    one, 0,  FS - 1);
        check_rot("-pi",            one, 0, -FS);
        check_rot("3pi/4",          one, 0,  3*FS/4);
        check_rot("-3pi/4",         one, 0, -3*FS/4);
        // ---- rotation: at the convergence limit of the raw iterations ---------------
        check_rot("+99.88 deg limit", one, 0,  lim);
        check_rot("-99.88 deg limit", one, 0, -lim);
        // ---- rotation: general vectors, zero, 1 LSB ---------------------------------
        check_rot("(0.5,-0.25) by 2.0", one/2, -one/4, $rtoi(2.0 * RAD));
        check_rot("(-1,-1) by -pi/3",  -one, -one, -$rtoi(PI/3 * RAD));
        check_rot("exact zero",       0, 0, $rtoi(1.0 * RAD));
        check_rot("1 LSB",            1, 0, FS/4);
        // ---- rotation: saturation -- sqrt(2)*FS must clamp, not wrap ----------------
        check_rot("sat +FS diag +45", FS-1,  FS-1,  FS/4);
        check_rot("sat -FS diag +45", -FS,   -FS,   FS/4);
        check_rot("sat +FS diag -45", FS-1,  FS-1, -FS/4);
        check_rot("sat -FS diag 135", -FS,   -FS,   3*FS/4);
        check_rot("max x, no rot",    FS-1,  0,     0);
        check_rot("min x, by pi",     -FS,   0,    -FS);

        // ---- vectoring ---------------------------------------------------------------
        check_vec("+x axis",          one,  0, 0);
        check_vec("+y axis",          0,  one, 0);
        check_vec("-x axis",         -one,  0, 0);
        check_vec("-y axis",          0, -one, 0);
        check_vec("-x axis, y=-1LSB", -one, -1, 0);
        check_vec("Q1 (3,4)/5",       3*one/5,  4*one/5, 0);
        check_vec("Q2",              -3*one/5,  4*one/5, 0);
        check_vec("Q3",              -3*one/5, -4*one/5, 0);
        check_vec("Q4",               3*one/5, -4*one/5, 0);
        check_vec("small r=1/64",     one/64, -one/64, 0);
        check_vec("z offset",         one/2, one/2, FS/2);
        check_vec("exact zero",       0, 0, 0);
        check_vec("sat diag +FS",     FS-1, FS-1, 0);
        check_vec("sat diag -FS",     -FS,  -FS,  0);
        check_vec("max x only",       FS-1, 0, 0);
        check_vec("min y only",       0, -FS, 0);

        if (errors == 0) $display("TEST PASSED: %0d directed checks", checks);
        else             $display("TEST FAILED: %0d errors in %0d checks", errors, checks);
        $finish;
    end
endmodule
