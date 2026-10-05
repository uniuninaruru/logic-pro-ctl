#!/usr/bin/env python3
"""A model of how /ati's `c` colours are packed, ported from the instructions (SA-REMOTE-TRACKTYPE-001).

Two pieces are modelled, both read from Logic 12.3.1 (6682), arm64:

  hsv_to_rgba   FUN_017e5998 (0x017e5998). Input: a hue (ushort), two signed bytes and an alpha.
                Output: R, G, B in [0, 1] and the alpha unchanged. Two per-hue tables of 360 doubles
                (0x01d434f8 and 0x01d44038) correct the saturation and the brightness.
  pack_rgba     the packing at 0x01697144..0x0169716c: every component times 255.0, truncated toward
                zero (fcvtzs), low byte kept, in the order R, G, B, A.

The tables are read from the image file (`load_tables`) or passed in. Nothing here runs Logic code.
A result is a static prediction, not a captured value.
"""
import struct
from typing import Sequence, Tuple

TABLE1_ADDRESS = 0x01D434F8
TABLE2_ADDRESS = 0x01D44038
HUES = 360


def load_tables(image) -> Tuple[Sequence[float], Sequence[float]]:
    """Both per-hue tables from a binary_anchors.Image."""
    first = struct.unpack(f"<{HUES}d", image.read(TABLE1_ADDRESS, HUES * 8))
    second = struct.unpack(f"<{HUES}d", image.read(TABLE2_ADDRESS, HUES * 8))
    return first, second


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def hsv_to_rgba(hue: int, saturation_byte: int, brightness_byte: int, alpha: float,
                table1: Sequence[float], table2: Sequence[float]) -> Tuple[float, float, float, float]:
    """FUN_017e5998. The two bytes are signed (ldrsb); a hue above 359 counts as 0."""
    index = hue if 0 <= hue <= 0x167 else 0
    saturation = _clamp((1.0 - (table1[index] + -1.0)) * saturation_byte, 0.0, 100.0)
    brightness = _clamp(table2[index] * brightness_byte, 0.0, 100.0)
    s = _clamp(float(int(saturation)), 0.0, 100.0) / 100.0   # fcvtzs w10, d0
    v = _clamp(float(int(brightness)), 0.0, 100.0) / 100.0   # fcvtzs w9, d1
    if s == 0.0:
        return (v, v, v, alpha)
    scaled = _clamp(float(index), 0.0, 359.0) / 359.0 * 6.0
    if scaled == 6.0:
        scaled = 0.0
    sector = int(scaled)
    fraction = scaled - sector
    p = v * (1.0 - s)
    q = v * (1.0 - s * fraction)
    t = v * (1.0 - s * (1.0 - fraction))
    r, g, b = {0: (v, t, p), 1: (q, v, p), 2: (p, v, t), 3: (p, q, v), 4: (t, p, v)}.get(sector, (v, p, q))
    return (r, g, b, alpha)


def pack_rgba(rgba: Sequence[float]) -> bytes:
    """The 4 bytes of one `c` colour: trunc(x * 255.0) & 0xff in the order R, G, B, A."""
    return bytes(int(component * 255.0) & 0xFF for component in rgba)


def default_icon_tint(table1: Sequence[float], table2: Sequence[float]) -> bytes:
    """FUN_00d358a0 for colour index -1 or 0: hue 212, bytes 55 and 100 (0x643700d4), alpha 1.0."""
    return pack_rgba(hsv_to_rgba(0x00D4, 0x37, 0x64, 1.0, table1, table2))
