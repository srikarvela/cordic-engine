// =============================================================================
// tb_cordic_sweep.sv -- full-range sweep, bit-exact against the MATLAB golden
//
// Replays tb/vectors/cordic_N<N>_W<W>.csv (written by matlab/export_vectors.m)
// through cordic_top, one vector per clock with random bubbles on valid_i, and
// requires every output word to equal the fixed-point model exactly -- no
// tolerance. Also writes build/cordic_hw_N<N>_W<W>.csv so matlab/diff_cordic.py
// can repeat the comparison outside the simulator.
//
//   iverilog ... -Ptb_cordic_sweep.N_ITER=15 -Ptb_cordic_sweep.W=17
// =============================================================================
`timescale 1ns/1ps
module tb_cordic_sweep;
    parameter int N_ITER = 15;
    parameter int W      = 17;
    localparam int MAXV    = 65536;
    localparam int LATENCY = N_ITER + 6;

    logic clk = 0, rst = 1;
    logic valid_i = 0, mode_i = 0, valid_o, mode_o;
    logic signed [W-1:0] x_i = 0, y_i = 0, z_i = 0, x_o, y_o, z_o;

    cordic_top #(.N_ITER(N_ITER), .W(W)) dut (.*);

    always #2 clk = ~clk;

    integer v_mode [0:MAXV-1], v_x [0:MAXV-1], v_y [0:MAXV-1], v_z [0:MAXV-1];
    integer e_x [0:MAXV-1], e_y [0:MAXV-1], e_z [0:MAXV-1];
    integer sent_cycle [0:MAXV-1];
    integer nvec = 0, sent = 0, recv = 0, errors = 0, cycle = 0;
    integer fd, fo, rc, seq;
    string  vec_path, out_path;
    reg [8*64-1:0] header;

    // ---- checker ------------------------------------------------------------------
    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (!rst && valid_o) begin
            if (recv >= sent) begin
                errors = errors + 1;
                $display("FAIL: valid_o with nothing outstanding (cycle %0d)", cycle);
            end else begin
                if (x_o !== e_x[recv][W-1:0] || y_o !== e_y[recv][W-1:0] ||
                    z_o !== e_z[recv][W-1:0] || mode_o !== v_mode[recv][0]) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("MISMATCH seq=%0d mode=%0d in=(%0d,%0d,%0d) hw=(%0d,%0d,%0d) golden=(%0d,%0d,%0d)",
                                 recv, v_mode[recv], v_x[recv], v_y[recv], v_z[recv],
                                 x_o, y_o, z_o, e_x[recv], e_y[recv], e_z[recv]);
                end
                if (cycle - sent_cycle[recv] != LATENCY) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("FAIL: seq=%0d latency %0d, expected %0d", recv, cycle - sent_cycle[recv], LATENCY);
                end
                $fdisplay(fo, "%0d,%0d,%0d,%0d", recv, x_o, y_o, z_o);
                recv = recv + 1;
            end
        end
    end

    // ---- stimulus -----------------------------------------------------------------
    initial begin
        if ($test$plusargs("WAVES")) begin
            $dumpfile("build/tb_cordic_sweep.vcd");
            $dumpvars(0, tb_cordic_sweep);
        end
        vec_path = $sformatf("tb/vectors/cordic_N%0d_W%0d.csv", N_ITER, W);
        out_path = $sformatf("build/cordic_hw_N%0d_W%0d.csv", N_ITER, W);
        fd = $fopen(vec_path, "r");
        if (fd == 0) begin
            $display("FAIL: cannot open %s (run `make matlab`)", vec_path);
            $finish;
        end
        rc = $fgets(header, fd);
        while (!$feof(fd) && nvec < MAXV) begin
            rc = $fscanf(fd, "%d,%d,%d,%d,%d,%d,%d,%d\n", seq, v_mode[nvec], v_x[nvec], v_y[nvec],
                         v_z[nvec], e_x[nvec], e_y[nvec], e_z[nvec]);
            if (rc == 8) nvec = nvec + 1;
        end
        $fclose(fd);
        fo = $fopen(out_path, "w");
        $fdisplay(fo, "seq,xo,yo,zo");
        $display("tb_cordic_sweep: N_ITER=%0d W=%0d, %0d vectors from %s", N_ITER, W, nvec, vec_path);

        repeat (4) @(posedge clk);
        rst <= 0;
        @(posedge clk);
        while (sent < nvec) begin
            // back-to-back for the first half (II = 1), random bubbles after
            if (sent < nvec / 2 || ($urandom % 4) != 0) begin
                valid_i <= 1;
                mode_i  <= v_mode[sent][0];
                x_i     <= v_x[sent][W-1:0];
                y_i     <= v_y[sent][W-1:0];
                z_i     <= v_z[sent][W-1:0];
                sent_cycle[sent] = cycle + 1;
                sent = sent + 1;
            end else begin
                valid_i <= 0;
                x_i     <= $urandom;          // garbage on bubbles must not leak out
                y_i     <= $urandom;
                z_i     <= $urandom;
            end
            @(posedge clk);
        end
        valid_i <= 0;
        repeat (LATENCY + 8) @(posedge clk);
        $fclose(fo);

        if (recv != nvec) begin
            errors = errors + 1;
            $display("FAIL: received %0d of %0d results", recv, nvec);
        end
        if (errors == 0 && nvec > 0)
            $display("TEST PASSED: %0d/%0d vectors bit-exact, latency %0d cycles, II = 1", recv, nvec, LATENCY);
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end
endmodule
