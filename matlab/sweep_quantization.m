function op = sweep_quantization()
%SWEEP_QUANTIZATION  Error surface over (N iterations, W word length).
%
% For every N = 8..20 and W = 12..24 the bit-exact fixed-point model is run
% over a full-circle sweep and compared against ideal math:
%   rotation  : x = 1.0, y = 0, z = theta   -> (cos, sin)
%   vectoring : unit-radius points          -> (magnitude, atan2)
% The input angle/vector is quantised FIRST and the truth is computed from the
% quantised input, so the numbers are the engine's own error, not the error of
% representing the stimulus.
%
% Outputs docs/error_curves.png, docs/quantization_sweep.csv and returns the
% chosen operating point.
    Ns = 8:20;  Ws = 12:24;  M = 4096;
    TARGET = 1e-4;                       % spec: max error of sin, cos, magnitude AND phase (rad)

    emax = zeros(numel(Ns), numel(Ws));  erms = emax;  emag = emax;  eph = emax;
    for a = 1:numel(Ns)
        for b = 1:numel(Ws)
            [emax(a,b), erms(a,b), emag(a,b), eph(a,b)] = run_cfg(Ns(a), Ws(b), [], M);
        end
    end

    % guard-bit ablation at a fixed W: is ceil(log2 N) actually needed / enough?
    Wg = 16; Gs = 0:6; Ng = [12 16];
    eg = zeros(numel(Ng), numel(Gs));
    for a = 1:numel(Ng), for g = 1:numel(Gs)
        eg(a,g) = run_cfg(Ng(a), Wg, Gs(g), M);
    end, end

    % ---- operating point: cheapest datapath meeting the spec -----------------
    % area proxy = adder bits in the iteration array: N stages * 3 adders * (W+G)
    [WW, NN] = meshgrid(Ws, Ns);
    cost = NN .* 3 .* (WW + ceil(log2(NN)));
    worst = max(cat(3, emax, emag, eph), [], 3);
    cost(worst > TARGET) = inf;
    [~, k] = min(cost(:));
    op = struct('N', NN(k), 'W', WW(k), 'G', ceil(log2(NN(k))), ...
                'emax', emax(k), 'erms', erms(k), 'eph', eph(k), 'emag', emag(k), 'target', TARGET);
    fprintf('operating point: N=%d W=%d G=%d  sin/cos max %.3e rms %.3e  mag %.3e  phase %.3e (spec %.1e)\n', ...
            op.N, op.W, op.G, op.emax, op.erms, op.emag, op.eph, TARGET);

    % ---- CSV -------------------------------------------------------------------
    f = fopen(fullfile('..', 'docs', 'quantization_sweep.csv'), 'w');
    fprintf(f, 'N,W,G,max_err_sincos,rms_err_sincos,max_err_mag,max_err_phase_rad\n');
    for a = 1:numel(Ns), for b = 1:numel(Ws)
        fprintf(f, '%d,%d,%d,%.6e,%.6e,%.6e,%.6e\n', Ns(a), Ws(b), ceil(log2(Ns(a))), ...
                emax(a,b), erms(a,b), emag(a,b), eph(a,b));
    end, end
    fclose(f);

    % ---- plots -----------------------------------------------------------------
    fig = figure('Visible', 'off', 'Position', [0 0 1500 900], 'Color', 'w');
    try, theme(fig, 'light'); catch, end          % R2025a+: ignore the desktop dark theme
    subplot(2,2,1);
    imagesc(Ws, Ns, log2(emax)); set(gca, 'YDir', 'normal'); cb = colorbar;
    cb.Label.String = 'log_2(max |error|)'; hold on;
    contour(Ws, Ns, worst, [TARGET TARGET], 'w-', 'LineWidth', 2);
    plot(op.W, op.N, 'rp', 'MarkerSize', 16, 'MarkerFaceColor', 'r');
    xlabel('word length W (bits)'); ylabel('iterations N');
    title(sprintf('sin/cos max error surface  (white: %.0e spec, star: N=%d, W=%d)', TARGET, op.N, op.W));

    subplot(2,2,2);
    sel = [12 14 16 18 20 24];
    for w = sel, semilogy(Ns, emax(:, Ws == w), '-o', 'DisplayName', sprintf('W=%d', w)); hold on; end
    semilogy(Ns, 2.^-(Ns-1), 'k--', 'LineWidth', 1.5, 'DisplayName', 'algorithmic 2^{-(N-1)}');
    yline(TARGET, 'r:', 'spec', 'HandleVisibility', 'off');
    grid on; xlabel('iterations N'); ylabel('max |sin/cos error|'); legend('Location', 'southwest');
    title('Error vs iterations: one bit per stage until the word length floors it');

    subplot(2,2,3);
    for n = [8 12 16 20], semilogy(Ws, erms(Ns == n, :), '-s', 'DisplayName', sprintf('N=%d', n)); hold on; end
    semilogy(Ws, 2.^-(Ws-2) / sqrt(12), 'k--', 'LineWidth', 1.5, 'DisplayName', 'ideal LSB/\surd12');
    grid on; xlabel('word length W (bits)'); ylabel('RMS sin/cos error'); legend('Location', 'southwest');
    title('RMS error vs word length');

    subplot(2,2,4);
    lsb = 2^-(Wg-2);
    for a = 1:numel(Ng), plot(Gs, eg(a,:) / lsb, '-o', 'DisplayName', sprintf('N=%d, W=%d', Ng(a), Wg)); hold on; end
    for a = 1:numel(Ng), xline(ceil(log2(Ng(a))), 'k:', 'HandleVisibility', 'off'); end
    grid on; xlabel('guard bits G'); ylabel('max error (output LSBs)'); legend;
    title('Guard-bit ablation (dotted: G = ceil(log_2 N))');

    exportgraphics(fig, fullfile('..', 'docs', 'error_curves.png'), 'Resolution', 130);
    fprintf('wrote docs/error_curves.png, docs/quantization_sweep.csv\n');
    disp(array2table(eg / lsb, 'VariableNames', compose('G%d', Gs), 'RowNames', compose('N%d', Ng)));
end

function [emax, erms, emag, eph] = run_cfg(N, W, G, M)
    if isempty(G), G = ceil(log2(N)); end
    F  = W - 2;
    k  = (0:M-1)';
    zq = round((k / M * 2 - 1) * 2^(W-1));              % full circle, W-bit BAM
    tq = zq * pi / 2^(W-1);
    [c, s] = cordic_fixed(0, 2^F * ones(M,1), zeros(M,1), zq, N, W, G);
    e = [c / 2^F - cos(tq); s / 2^F - sin(tq)];
    emax = max(abs(e));  erms = sqrt(mean(e.^2));

    th = (k + 0.5) / M * 2*pi - pi;
    xq = round(cos(th) * 2^F);  yq = round(sin(th) * 2^F);
    [m, ~, p] = cordic_fixed(1, xq, yq, zeros(M,1), N, W, G);
    emag = max(abs(m - hypot(xq, yq))) / 2^F;
    eph  = max(abs(angle(exp(1j * (p * pi / 2^(W-1) - atan2(yq, xq))))));
end
