function [xo, yo, zo] = cordic_float(mode, x, y, z, N)
%CORDIC_FLOAT  Floating-point CORDIC reference (circular coordinates).
%
%   mode : 0 = rotation  (rotate (x,y) by z;      z -> 0)
%          1 = vectoring (rotate (x,y) onto +x;   z -> z + atan2(y,x))
%   x, y : real vectors          z : angle in radians, any value
%   N    : iteration count
%
% Structure mirrors the hardware one-for-one: quadrant pre-rotation, 1/K_N
% pre-scale, N shift-add iterations.  Only the arithmetic is ideal (double),
% so the difference between this and sin/cos/atan2/hypot is the pure
% algorithmic (finite-N) error, and the difference between this and
% cordic_fixed is the pure quantization error.
    x = x(:); y = y(:); z = z(:); mode = mode(:) .* ones(size(x));
    z = mod(z + pi, 2*pi) - pi;                       % [-pi, pi)

    % quadrant pre-rotation into the convergence range (|angle| <= ~99.88 deg)
    rot = (mode == 0); vec = ~rot;
    qp = (rot & z >=  pi/2) | (vec & x < 0 & y <  0); % rotate by +90: (x,y)->(-y,x)
    qn = (rot & z <  -pi/2) | (vec & x < 0 & y >= 0); % rotate by -90: (x,y)->(y,-x)
    [x, y] = deal(x.*~(qp|qn) - y.*qp + y.*qn, y.*~(qp|qn) + x.*qp - x.*qn);
    z = z - (pi/2)*(qp & rot) + (pi/2)*(qn & rot) ...
          - (pi/2)*(qp & vec) + (pi/2)*(qn & vec);

    c = cordic_consts();
    x = x / c.K(N);  y = y / c.K(N);                  % gain pre-scale

    for i = 0:N-1
        d = rot .* (2*(z >= 0) - 1) + vec .* (2*(y < 0) - 1);
        [x, y] = deal(x - d .* y * 2^-i, y + d .* x * 2^-i);
        z = z - d * atan(2^-i);
    end
    xo = x; yo = y; zo = mod(z + pi, 2*pi) - pi;
end
