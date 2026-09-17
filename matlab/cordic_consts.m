function c = cordic_consts()
%CORDIC_CONSTS  Shared integer constants for the fixed-point model and the RTL.
%
%   c.atan32(i+1) = round(atan(2^-i) / pi * 2^31),  i = 0..31   (BAM: pi == 2^31)
%   c.invk32(N)   = round(2^32 / K_N),  K_N = prod_{i<N} sqrt(1 + 2^-2i)
%
% gen_atan_lut.m writes exactly these integers into rtl/cordic_atan_lut.svh,
% so the model and the hardware round from the same source constants.
    i = 0:31;
    c.atan32 = round(atan(2.^-i) / pi * 2^31);
    K = cumprod(sqrt(1 + 2.^(-2*i)));
    c.invk32 = round(2^32 ./ K);
    c.K = K;
end
