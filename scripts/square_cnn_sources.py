#!/usr/bin/env python3
"""Emit file list for SQuARE low-precision CNN overlays.

Usage:
 python scripts/square_cnn_sources.py --dataset CIFAR_10 --format posit4
 python scripts/square_cnn_sources.py --dataset MNIST --format fp4

Use emitted files in place of matching legacy conv source files. The entire
legacy SoC project needs its vendor BRAM/IP wrappers and other source files.
"""
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parent.parent
CNN = ROOT / 'rtl' / 'cnn_transprecision'
COMPUTE = ROOT / 'rtl' / 'compute'
OVERLAYS = {
    'MNIST': ['Conv2D_1'],
    'CIFAR_10': ['Conv2D_1', 'Conv2D_2', 'Conv2D_3'],
}
FORMATS = {'posit4': (0, 0), 'fp4': (1, 0), 'fp2-e1m0': (2, 0),
           'fp2-e0m1': (2, 1), 'dp2-e1m0': (3, 0), 'dp2-e0m1': (3, 1)}

ap = argparse.ArgumentParser()
ap.add_argument('--dataset', choices=OVERLAYS, required=True)
ap.add_argument('--format', choices=FORMATS, required=True)
ap.add_argument('--filelist', type=Path, default=None)
args = ap.parse_args()
files = [COMPUTE / m for m in ('posit4_es1_pp.v', 'fp4_e2m1_pp.v', 'fp2_pp.v')]
files += [CNN / m for m in ('square_lowp_product.sv', 'square_cnn_processing_element.sv')]
files += [CNN / 'overlays' / args.dataset / (layer+'.sv') for layer in OVERLAYS[args.dataset]]
manifest = '\n'.join(str(p) for p in files)+'\n'
if args.filelist:
    args.filelist.parent.mkdir(parents=True, exist_ok=True)
    args.filelist.write_text(manifest)
else:
    print(manifest,end='')
print(f'# To use: set SQUARE_FORMAT={FORMATS[args.format][0]}, '
      f'SQUARE_FP2_FORMAT={FORMATS[args.format][1]} '
      f'on CNN conv module parameters (or use defparam/generic map).',
      file=__import__('sys').stderr)
