#!/usr/bin/env python3
"""Bygger addon'ens egne teksturer.

    python3 scripts/byg-masker.py

Skriver i D2Map/Media, alle som 32-bit, ukomprimeret TGA (det format, alle
WoW-klienter kan læse):

  mask-round.tga, mask-square.tga   128 x 128. Maskerne, der giver automappet
      bløde kanter. Alfa er 1 i midten og falder blødt til 0 ved kanten.
      Farvekanalerne får samme værdi som alfa, så masken virker, uanset om
      klienten læser alfa eller lysstyrke.
  dot.tga   32 x 32. Prikken i guidens vej: en hvid skive med sort kant. Hvid
      tager den farve, addon'en giver den (grøn, gul), og sort bliver ved med
      at være sort – så prikken kan ses på både lyst og mørkt terræn.
"""
import math
import pathlib
import struct

STR = 128                      # skal være en toerpotens
MAPPE = pathlib.Path(__file__).resolve().parent.parent / "D2Map" / "Media"


def blød(t: float) -> float:
    """Smoothstep: 0 → 0, 1 → 1, uden knæk i enderne."""
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def rund(x: float, y: float) -> float:
    """Cirkel: helt synlig ud til 72 % af radius, væk ved 97 %."""
    r = math.hypot(x, y)
    return 1 - blød((r - 0.72) / (0.97 - 0.72))


def firkant(x: float, y: float) -> float:
    """Firkant med runde hjørner (superellipse): synlig til 82 %, væk ved 97 %."""
    r = (abs(x) ** 6 + abs(y) ** 6) ** (1 / 6)
    return 1 - blød((r - 0.82) / (0.97 - 0.82))


def prik(x: float, y: float) -> tuple[float, float]:
    """Hvid skive (ca. 60 % af radius) med sort kant (ud til ca. 95 %). Giver (lysstyrke, alfa)."""
    r = math.hypot(x, y)
    lys = 1 - blød((r - 0.56) / 0.12)          # hvid kerne, blød overgang til sort
    alfa = 1 - blød((r - 0.86) / 0.12)         # kanten falder ud mod ingenting
    return lys, alfa


def skriv(navn: str, form, str_: int = STR) -> None:
    # 18 bytes hoved: ingen id, ingen palet, type 2 (ukomprimeret true-color),
    # 32 bit pr. pixel, 8 alfa-bit, første række øverst (0x20).
    hoved = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, str_, str_, 32, 0x28)
    pixels = bytearray()
    for række in range(str_):
        for kol in range(str_):
            # pixlens midte i koordinater fra -1 til 1
            x = (kol + 0.5) / str_ * 2 - 1
            y = (række + 0.5) / str_ * 2 - 1
            værdi = form(x, y)
            if isinstance(værdi, tuple):           # (lysstyrke, alfa)
                lys, a = round(255 * værdi[0]), round(255 * værdi[1])
            else:                                  # maske: farve = alfa
                lys = a = round(255 * værdi)
            pixels += bytes((lys, lys, lys, a))    # B, G, R, A
    MAPPE.mkdir(parents=True, exist_ok=True)
    (MAPPE / navn).write_bytes(hoved + bytes(pixels))
    print(f"Skrev {MAPPE / navn} ({len(hoved) + len(pixels)} bytes)")


skriv("mask-round.tga", rund)
skriv("mask-square.tga", firkant)
skriv("dot.tga", prik, 32)
