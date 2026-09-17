% make matlab: oracle check -> LUT header -> quantisation sweep -> golden vectors
validate_models();
gen_atan_lut();
op = sweep_quantization();
export_vectors(op);
