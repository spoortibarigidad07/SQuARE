#!/usr/bin/env python3
"""Lightweight structural checks of SQuARE PE overlays, not an RTL compiler."""
from pathlib import Path
import re
r = Path(__file__).resolve().parents[2]
files = [
    ('MNIST', 'Conv2D_1', 9),
    ('CIFAR_10', 'Conv2D_1', 27),
    ('CIFAR_10', 'Conv2D_2', 288),
    ('CIFAR_10', 'Conv2D_3', 576),
]
for ds, layer, count in files:
    path = r / 'rtl' / 'cnn_transprecision' / 'overlays' / ds / (layer + '.sv')
    s = path.read_text()
    assert s.count('square_cnn_processing_element #(') == 1, path
    assert 'parameter integer SQUARE_FORMAT' in s, path
    assert 'parameter integer SQUARE_FP2_FORMAT' in s, path
    for var in ('a_in', 'b_in'):
        assert re.search(r'\b' + var + r'\s*\[0:' + str(count-1) + r'\]', s), (path, var)
    assert re.search(r'(?:pe|pe_idx)\s*<\s*' + str(count) + r'\s*;', s), path
    print('checked',ds,layer,'PEs',count)
assert 'square_systolic_array' in (r/'rtl/cnn_transprecision/square_systolic_variants.sv').read_text()
print('PASS: source layout and overlay PE dimension checks')
