function [xo, yo, zo] = cordic_fixed(mode, x, y, z, N, W, G)
%CORDIC_FIXED  Bit-exact fixed-point model of rtl/cordic_top.sv.
%
%   mode    : 0 rotation / 1 vectoring (scalar or per-sample vector)
%   x, y    : W-bit signed integers (interpret as Q(W-F).F, default F = W-2)
%   z       : W-bit signed binary angle (BAM): 2^(W-1) == pi, wraps naturally
%   N, W, G : iterations, word length, guard bits (default G = ceil(log2(N)))
%
% All values are integer-valued doubles; every intermediate stays below 2^53
% (asserted), so double arithmetic is exact and floor(v / 2^k) is exactly the
% hardware's arithmetic right shift.
%
% Hardware behaviour reproduced here, step for step:
%   1. sign-extend into the internal format: W + 1 (growth) + G (guard) bits
%   2. quadrant pre-rotation (negate/swap only)
%   3. 1/K_N pre-scale: exact product with a W-bit constant, round half-up
%   4. N iterations: truncating arithmetic shifts, add/sub, angle wraps
%   5. output: drop guard bits round-half-up, SATURATE x/y to W bits, wrap z
    if nargin < 7, G = ceil(log2(N)); end
    assert(W + G <= 29 && N <= 32, 'constants are 32-bit: need W+G <= 29, N <= 32');
    assert(2*W + G - 1 < 53, 'pre-scale product would exceed double precision');
    x = x(:); y = y(:); z = z(:); mode = mode(:) .* ones(size(x));
    rot = (mode == 0); vec = ~rot;
    c  = cordic_consts();
    WZ = W + G;                                   % internal angle width
    wrapz = @(v) mod(v + 2^(WZ-1), 2^WZ) - 2^(WZ-1);
    rhu   = @(v, s) floor((v + (s > 0) * 2^(max(s,1)-1)) / 2^s);   % round half-up >> s

    % 1. internal format
    x = x * 2^G;  y = y * 2^G;  q = 2^(WZ-2);     % q == pi/2
    z = z * 2^G;

    % 2. quadrant pre-rotation
    qp = (rot & z >=  q) | (vec & x < 0 & y <  0);   % (x,y) -> (-y, x)
    qn = (rot & z <  -q) | (vec & x < 0 & y >= 0);   % (x,y) -> ( y,-x)
    [x, y] = deal(x.*~(qp|qn) - y.*qp + y.*qn, y.*~(qp|qn) + x.*qp - x.*qn);
    z = wrapz(z - q*(qp & rot) + q*(qn & rot) - q*(qp & vec) + q*(qn & vec));

    % 3. gain pre-scale by C / 2^W ~= 1/K_N
    C = rhu(c.invk32(N), 32 - W);
    x = rhu(x * C, W);  y = rhu(y * C, W);

    % 4. iterations
    for i = 0:N-1
        A = rhu(c.atan32(i+1), 32 - WZ);
        d = rot .* (2*(z >= 0) - 1) + vec .* (2*(y < 0) - 1);
        [x, y] = deal(x - d .* floor(y / 2^i), y + d .* floor(x / 2^i));
        z = wrapz(z - d * A);
        assert(all(abs(x) < 2^(W+G)) && all(abs(y) < 2^(W+G)), 'internal overflow');
    end

    % 5. output quantisation
    sat = @(v) min(max(v, -2^(W-1)), 2^(W-1) - 1);
    xo = sat(rhu(x, G));  yo = sat(rhu(y, G));
    zo = mod(rhu(z, G) + 2^(W-1), 2^W) - 2^(W-1);
end
