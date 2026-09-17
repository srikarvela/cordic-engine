function validate_models()
%VALIDATE_MODELS  Oracle integrity: float vs. ideal math, then fixed vs. float.
%
% The fixed-point model is only allowed to judge the RTL after it has itself
% been checked against an independent reference.  Any violated bound errors
% out, which stops `make matlab` before vectors are exported.
    rng(1);
    M  = 20000;
    th = (rand(M,1)*2 - 1) * pi;
    r  = 0.1 + 0.9*rand(M,1);
    px = r .* cos(th);  py = r .* sin(th);

    fprintf('--- float CORDIC vs sin/cos/atan2/hypot (algorithmic error, bound 2^-(N-1)) ---\n');
    for N = [8 12 16 20]
        [c, s] = cordic_float(0, ones(M,1), zeros(M,1), th, N);
        [m, ~, p] = cordic_float(1, px, py, zeros(M,1), N);
        e_rot = max(abs([c - cos(th); s - sin(th)]));
        e_mag = max(abs(m - hypot(px, py)));
        e_ph  = max(abs(angle(exp(1j*(p - atan2(py, px))))));
        bound = 2^-(N-1);
        fprintf('N=%2d  sin/cos %.3e  mag %.3e  phase %.3e  (bound %.3e)\n', N, e_rot, e_mag, e_ph, bound);
        assert(e_rot < bound && e_mag < bound && e_ph < bound, 'float model out of bound at N=%d', N);
    end

    fprintf('--- fixed vs ideal math (bound: algorithmic 2^-(N-1) + 3 LSB quantisation) ---\n');
    % Not compared sample-by-sample against cordic_float: once the residual is
    % near zero the two models legitimately take different +/- decisions, and
    % each lands within the algorithmic bound on opposite sides of the truth.
    for cfg = [8 12; 12 16; 16 20; 20 24; 16 16; 12 24]'
        N = cfg(1); W = cfg(2); F = W - 2;
        zq = round(th / pi * 2^(W-1));  zq(zq == 2^(W-1)) = -2^(W-1);
        tq = zq * pi / 2^(W-1);
        xq = round(px * 2^F);  yq = round(py * 2^F);
        [ci, si]     = cordic_fixed(0, 2^F*ones(M,1), zeros(M,1), zq, N, W);
        [mi, ~, pii] = cordic_fixed(1, xq, yq, zeros(M,1), N, W);
        e_rot = max(abs([ci - cos(tq)*2^F; si - sin(tq)*2^F]));              % x/y LSBs
        e_mag = max(abs(mi - hypot(xq, yq)));
        % phase: scale by radius (small vectors amplify the 3 LSB of x/y noise)
        e_ph  = max(abs(angle(exp(1j*(pii*pi/2^(W-1) - atan2(yq, xq))))) .* hypot(xq, yq));
        bound = 2^-(N-1) * 2^F + 3;
        fprintf('N=%2d W=%2d  sin/cos %7.2f  mag %5.2f  phase*r %7.2f  (LSB, bound %.2f)\n', ...
                N, W, e_rot, e_mag, e_ph, bound);
        assert(max([e_rot e_mag e_ph]) < bound, 'fixed model out of bound at N=%d W=%d', N, W);
    end

    fprintf('--- saturation: overflow must clamp, never wrap ---\n');
    W = 16; N = 12; big = 2^(W-1) - 1;
    % full-scale diagonal rotated by +45 deg lands on the y axis at sqrt(2)*FS
    [~, yo] = cordic_fixed(0, [big; -big-1], [big; -big-1], [2^(W-3); 2^(W-3)], N, W);
    assert(yo(1) == big && yo(2) == -big-1, 'rotation overflow must saturate at both rails');
    [m, ~] = cordic_fixed(1, [big; -big-1], [big; -big-1], [0; 0], N, W);
    assert(all(m == big), 'vectoring magnitude sqrt(2)*FS must saturate high');
    fprintf('validate_models: PASS\n');
end
