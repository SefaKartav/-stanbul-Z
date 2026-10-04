"""Yeni Istanbul -- SABIT kurgusal 10 x 10 km sehir haritasi (GELISTIRME ARACI).

    python fps/tools/city_design/build_fixed_city.py            # uret + yaz + rapor
    python fps/tools/city_design/build_fixed_city.py --check    # uret, YAZMA (hash/rapor)

Oyun acilisinda HICBIR SEY uretilmez: bu arac bir kez calisir ve
fps/data/map/yeni_istanbul.json dosyasini (CityGenerator bicim 3) yazar.
Tohum ve surum sabittir; ayni surum her zaman ayni dosyayi (ayni icerik
hash'i) uretir. Loot ve karsilasma tohumlari cografyadan ayridir (oyun
tarafinda bina kimligi + gun ile belirlenir).

TASARIM (belge: docs/CLAUDE_CODE_YENI_VIZYON_PROMPTU.md, bolum 1)
  * 10.000 x 10.000 m, 1 birim = 1 m. Su ~20 km2: guney denizi, sehri ikiye
    bolen bogaz (kuzeyde kara baglantisi var), tarihi yarimadayi ayiran
    halic ve dogu kiyisi. Kara ~80 km2.
  * Planlama alanlari (km2): tarihi 12, konut 22, ticaret 10, sanayi 10,
    yesil/ceper 12, kurumsal 14. Her alan birkac semte bolunur (agirlikli
    Voronoi; hedef alana yakinsatilir).
  * Kaplama (bina tabani / parsel): tarihi %45-60, konut %30-45, ticaret
    %35-50, sanayi %20-35, kampus %15-30, yesil %0-5 -- rapor olculur.
  * Kurumlar: 3 askeri alan + 8 kontrol noktasi, 4 hastane + 8 saglik ocagi,
    24 eczane, 12 okul, 2 hapishane, 8 tarihi odak (kule, kubbe, saray
    avlusu, sarnic, sur, han, kiyi konagi, meydan).
  * Gecitler: asma kopru + iki alcak iskele-kopru (bogaz), iki halic gecidi
    ve bogazin kuzeyinden kara yolu: alternatifsiz tek dar bogaz yok.
  * Sinir: haritanin 40 m kenar bandi girilemez; oyun sinira yaklasinca
    mesaj verir (sessiz gorunmez duvar yok).
"""
from __future__ import annotations

import base64
import hashlib
import heapq
import json
import math
import os
import random
import struct
import sys
import time
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FPS = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(FPS, "data", "map", "yeni_istanbul.json")

MAP_ID = "yeni_istanbul"
MAP_NAME = "Yeni İstanbul"
WORLD_VERSION = 1
SEED = 20260929
SIZE = 10000
ZR = 25                 # planlama izgarasi (m)
ZN = SIZE // ZR
LAND_RES = 2
INSIDE_RES = 4
TERRAIN_RES = 4
OR = 2                  # doluluk izgarasi (m)
ON = SIZE // OR
BORDER = 40             # girilemez kenar bandi (m)
WATER_TARGET_KM2 = 20.0

FREE, ROAD, BUILDING, BLOCKED, RESERVED = 0, 1, 2, 3, 4

# ---------------------------------------------------------------------------
# Su (analitik; vektorlu)
# ---------------------------------------------------------------------------
def cx_inlet(z):
    return 5150 + 380 * np.sin((z - 2600) / 1500.0) + 110 * np.sin(z / 410.0)


def hw_inlet(z):
    hw = 330 + 110 * np.sin(z / 700.0 + 0.8)
    t = np.clip((z - 2700) / 450.0, 0.0, 1.0)
    return hw * np.sqrt(t)


def zh_halic(x):
    return 5320 + 150 * np.sin((x - 2300) / 520.0)


def hw_halic(x):
    return (50 + 110 * np.clip((x - 2300) / 2400.0, 0.0, 1.0)) * np.sqrt(np.clip((x - 2300) / 200.0, 0.0, 1.0))


COAST_OFF = [0.0]


def coast_s(x):
    return 8950 + COAST_OFF[0] + 160 * np.sin(x / 820.0) + 80 * np.sin(x / 233.0 + 1.3) + 30 * np.sin(x / 97.0 + 0.4)


def coast_e(z):
    return 8950 + 220 * np.sin(z / 640.0) + 120 * np.sin(z / 190.0 + 2.0) + np.maximum(0.0, 5600 - z) * 1.6


def water(x, z):
    x = np.asarray(x, dtype=np.float64)
    z = np.asarray(z, dtype=np.float64)
    w = z > coast_s(x)
    w |= (z > 2700) & (np.abs(x - cx_inlet(z)) < hw_inlet(z))
    w |= (x > 2300) & (x < cx_inlet(z) + 5) & (np.abs(z - zh_halic(x)) < hw_halic(x))
    w |= x > coast_e(z)
    return w


def water_km2(res=ZR):
    c = (np.arange(SIZE // res) + 0.5) * res
    X, Z = np.meshgrid(c, c)
    return water(X, Z).sum() * res * res / 1e6


def tune_water():
    lo, hi = -900.0, 900.0
    for _ in range(40):
        mid = (lo + hi) / 2
        COAST_OFF[0] = mid
        a = water_km2()
        if a > WATER_TARGET_KM2:
            lo = mid          # daha fazla su -> kiyiyi guneye it
        else:
            hi = mid
    COAST_OFF[0] = round((lo + hi) / 2, 1)
    return water_km2()


# ---------------------------------------------------------------------------
# Semtler
# ---------------------------------------------------------------------------
ZONES = {
    "historic": {"label": "Tarihî merkez", "target": 12.0},
    "residential": {"label": "Konut", "target": 22.0},
    "commercial": {"label": "Ticaret", "target": 10.0},
    "industrial": {"label": "Sanayi ve lojistik", "target": 10.0},
    "green": {"label": "Yeşil ve çeper", "target": 12.0},
    "institutional": {"label": "Kurumsal ve karma", "target": 14.0},
}

# kimlik, ad, alan, merkez, hedef km2 (alan hedeflerinin toplami = alan hedefi)
DISTRICTS = [
    ("surdibi", "Surdibi", "historic", (2550, 7500), 3.0),
    ("kubbealti", "Kubbealtı", "historic", (3650, 7700), 3.2),
    ("saraykapi", "Saraykapı", "historic", (4350, 8450), 2.6),
    ("sarniconu", "Sarnıçönü", "historic", (3450, 6300), 3.2),
    ("carsibasi", "Çarşıbaşı", "commercial", (6050, 6500), 3.6),
    ("hanlar", "Hanlar", "commercial", (3300, 4600), 3.2),
    ("rihtim", "Rıhtım", "commercial", (6500, 8300), 3.2),
    ("martikoy", "Martıköy", "residential", (1150, 8200), 3.2),
    ("cinarlibahce", "Çınarlıbahçe", "residential", (1350, 6200), 3.4),
    ("lalezar", "Lalezar", "residential", (2150, 3500), 3.2),
    ("kestanelik", "Kestanelik", "residential", (7300, 5300), 3.3),
    ("bademlik", "Bademlik", "residential", (7900, 7000), 3.0),
    ("ayvazdere", "Ayvazdere", "residential", (8500, 3700), 3.0),
    ("serinyali", "Serinyalı", "residential", (550, 4300), 2.9),
    ("tersane", "Tersane", "industrial", (5950, 4000), 3.4),
    ("demirhane", "Demirhane", "industrial", (8700, 2000), 3.3),
    ("liman", "Liman", "industrial", (8300, 8500), 3.3),
    ("kisla", "Kışla", "institutional", (1300, 1800), 3.6),
    ("sifahane", "Şifahane", "institutional", (4450, 2350), 3.4),
    ("mektepler", "Mektepler", "institutional", (7200, 2650), 3.4),
    ("kalebend", "Kalebend", "institutional", (9250, 5400), 3.6),
    ("korubasi", "Korubaşı", "green", (5600, 1100), 4.5),
    ("sirtlar", "Sırtlar", "green", (2700, 900), 3.8),
    ("kayalik", "Kayalık", "green", (9300, 700), 3.7),
]

STREET = {   # (aralik A, aralik B, genislik, kaldirim, yuzey, tip, kivrim genligi, kivrim dalga boyu)
    "historic": (62, 78, 5.0, 1.5, "cobblestone", "residential", 5.0, 95.0),
    "residential": (84, 112, 7.0, 2.0, "asphalt", "residential", 3.0, 160.0),
    "commercial": (78, 96, 9.0, 3.0, "asphalt", "tertiary", 0.0, 1.0),
    "industrial": (160, 130, 10.0, 1.0, "asphalt", "service", 0.0, 1.0),
    "institutional": (150, 150, 7.0, 2.0, "asphalt", "service", 0.0, 1.0),
    "green": (340, 340, 4.0, 0.0, "cobblestone", "path", 8.0, 220.0),
}

# (cephe min/max, bosluk min/max, derinlik min/max, kat secenekleri, ikinci sira olasiligi)
TYPOLOGY = {
    "historic": ((13, 22), (0, 1.0), (12, 16), [2, 3, 3, 3, 4, 4], 0.5),
    "residential": ((16, 26), (3, 6), (12, 17), [4, 5, 5, 6, 6, 7, 8], 0.5),
    "commercial": ((18, 34), (1, 3), (15, 24), [3, 4, 5, 6, 7, 8, 9], 0.6),
    "industrial": ((24, 48), (18, 30), (18, 30), [1, 2, 2, 3], 0.1),
    "institutional": ((24, 44), (12, 20), (15, 24), [2, 3, 3, 4], 0.12),
    "green": ((8, 12), (45, 90), (8, 10), [1, 2], 0.0),
}

CLASS_MIX = {
    "historic": [("residential", 70), ("market", 22), ("civic", 5), ("workshop", 3)],
    "residential": [("residential", 93), ("market", 4), ("derelict", 3)],
    "commercial": [("market", 45), ("residential", 25), ("electronics", 8), ("workshop", 5), ("garage", 5), ("civic", 12)],
    "industrial": [("industrial", 50), ("workshop", 25), ("garage", 20), ("derelict", 5)],
    "institutional": [("civic", 70), ("residential", 20), ("police", 10)],
    "green": [("residential", 80), ("derelict", 20)],
}


def stable_hash(text: str) -> int:
    """Surecten bagimsiz karma (Python hash() her calistirmada tuzlanir)."""
    return zlib.crc32(text.encode("utf-8")) & 0xFFFFFFFF


def pick(rng, table):
    total = sum(w for _, w in table)
    r = rng.random() * total
    for k, w in table:
        r -= w
        if r <= 0:
            return k
    return table[-1][0]


# ---------------------------------------------------------------------------
# Yardimcilar
# ---------------------------------------------------------------------------
def b64deflate(raw: bytes) -> str:
    return base64.b64encode(zlib.compress(raw, 9)).decode("ascii")


def rle_rows(mask: np.ndarray) -> list:
    rows = []
    for row in mask:
        row = row.astype(np.int8)
        first = int(row[0])
        change = np.flatnonzero(np.diff(row)) + 1
        edges = np.concatenate(([0], change, [row.size]))
        runs = np.diff(edges).tolist()
        rows.append([first] + [int(r) for r in runs])
    return rows


def rot(a):
    return math.cos(a), math.sin(a)


def rect_poly(cx, cz, a, hx, hz):
    c, s = rot(a)
    pts = []
    for lx, lz in [(-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)]:
        pts.append([round(cx + lx * c - lz * s, 2), round(cz + lx * s + lz * c, 2)])
    return pts


def octagon(cx, cz, r, a=0.0):
    return [[round(cx + r * math.cos(a + k * math.pi / 4 + math.pi / 8), 2),
             round(cz + r * math.sin(a + k * math.pi / 4 + math.pi / 8), 2)] for k in range(8)]


def poly_area(poly):
    s = 0.0
    for i in range(len(poly)):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % len(poly)]
        s += x1 * z2 - x2 * z1
    return abs(s) * 0.5


class Grid:
    """2 m doluluk izgarasi + 25 m semt izgarasi + arazi."""

    def __init__(self):
        self.occ = np.zeros((ON, ON), dtype=np.uint8)
        self.district = np.zeros((ZN, ZN), dtype=np.int16) - 1
        self.dist_water = None
        self.terrain = None     # 4 m izgara, yarim metre

    # --- dolu hucre testleri ---
    def rect_cells(self, cx, cz, a, hx, hz, pad=0.0):
        c, s = rot(a)
        ex = abs(hx * c) + abs(hz * s) + pad
        ez = abs(hx * s) + abs(hz * c) + pad
        x0 = max(0, int((cx - ex) // OR))
        x1 = min(ON - 1, int((cx + ex) // OR))
        z0 = max(0, int((cz - ez) // OR))
        z1 = min(ON - 1, int((cz + ez) // OR))
        if x1 < x0 or z1 < z0:
            return None
        xs = (np.arange(x0, x1 + 1) + 0.5) * OR
        zs = (np.arange(z0, z1 + 1) + 0.5) * OR
        X, Z = np.meshgrid(xs, zs)
        dx = X - cx
        dz = Z - cz
        lu = dx * c + dz * s
        lv = -dx * s + dz * c
        m = (np.abs(lu) <= hx + pad) & (np.abs(lv) <= hz + pad)
        return (slice(z0, z1 + 1), slice(x0, x1 + 1), m)

    def rect_free(self, cx, cz, a, hx, hz, pad=0.0):
        cells = self.rect_cells(cx, cz, a, hx, hz, pad)
        if cells is None:
            return False
        zs, xs, m = cells
        if m.shape != self.occ[zs, xs].shape:
            return False
        return not np.any(self.occ[zs, xs][m] != FREE)

    def mark_rect(self, cx, cz, a, hx, hz, value, pad=0.0, only_free=False):
        cells = self.rect_cells(cx, cz, a, hx, hz, pad)
        if cells is None:
            return
        zs, xs, m = cells
        view = self.occ[zs, xs]
        if only_free:
            m = m & (view == FREE)
        view[m] = value

    def mark_segment(self, a, b, r, value):
        x0 = max(0, int((min(a[0], b[0]) - r) // OR))
        x1 = min(ON - 1, int((max(a[0], b[0]) + r) // OR))
        z0 = max(0, int((min(a[1], b[1]) - r) // OR))
        z1 = min(ON - 1, int((max(a[1], b[1]) + r) // OR))
        if x1 < x0 or z1 < z0:
            return
        xs = (np.arange(x0, x1 + 1) + 0.5) * OR
        zs = (np.arange(z0, z1 + 1) + 0.5) * OR
        X, Z = np.meshgrid(xs, zs)
        ax, az = a
        bx, bz = b
        vx, vz = bx - ax, bz - az
        ll = vx * vx + vz * vz
        if ll < 1e-6:
            t = np.zeros_like(X)
        else:
            t = np.clip(((X - ax) * vx + (Z - az) * vz) / ll, 0.0, 1.0)
        d = np.hypot(X - (ax + t * vx), Z - (az + t * vz))
        view = self.occ[z0:z1 + 1, x0:x1 + 1]
        m = (d <= r) & (view != BLOCKED)
        view[m] = np.maximum(view[m], value) if value != ROAD else np.where(view[m] == BUILDING, BUILDING, ROAD)

    # --- sorgular ---
    def district_at(self, x, z):
        ix, iz = int(x // ZR), int(z // ZR)
        if 0 <= ix < ZN and 0 <= iz < ZN:
            return int(self.district[iz, ix])
        return -1

    def occ_at(self, x, z):
        ix, iz = int(x // OR), int(z // OR)
        if 0 <= ix < ON and 0 <= iz < ON:
            return int(self.occ[iz, ix])
        return BLOCKED

    def terrain_half(self, x, z):
        """CityGenerator._terrain_at ile ayni cift dogrusal okuma."""
        t = self.terrain
        n = t.shape[0]
        fx = (x + 0.5) / TERRAIN_RES - 0.5
        fz = (z + 0.5) / TERRAIN_RES - 0.5
        ix, iz = math.floor(fx), math.floor(fz)
        tx, tz = fx - ix, fz - iz

        def g(i, k):
            return float(t[min(max(k, 0), n - 1), min(max(i, 0), n - 1)])
        top = g(ix, iz) + (g(ix + 1, iz) - g(ix, iz)) * tx
        bot = g(ix, iz + 1) + (g(ix + 1, iz + 1) - g(ix, iz + 1)) * tx
        return max(2, int(round(top + (bot - top) * tz)))


# ---------------------------------------------------------------------------
# Uretim
# ---------------------------------------------------------------------------
class City:
    def __init__(self):
        self.rng = random.Random(SEED)
        self.g = Grid()
        self.roads = []
        self.buildings = []
        self.areas = []
        self.pois = []
        self.water_points = []
        self.places = {}
        self.place_names = {}
        self.reserved = []          # [(cx, cz, a, hx, hz)]
        self.bridge_decks = []
        self.bridges_meta = []
        self.spine = []
        self.stats = {}
        self.district_angle = {}
        self.log = []

    def say(self, text):
        self.log.append(text)
        print(text, flush=True)

    # --- 1. su ve kara ---
    def build_water(self):
        a = tune_water()
        self.say(f"su: {a:.2f} km2 (guney kiyisi kaydirma {COAST_OFF[0]} m)")
        c = (np.arange(ZN) + 0.5) * ZR
        X, Z = np.meshgrid(c, c)
        self.water_z = water(X, Z)
        # 2 m kara maskesi (satir satir; bellek)
        land = np.zeros((SIZE // LAND_RES, SIZE // LAND_RES), dtype=bool)
        xs = (np.arange(SIZE // LAND_RES) + 0.5) * LAND_RES
        for r in range(land.shape[0]):
            z = (r + 0.5) * LAND_RES
            land[r] = ~water(xs, np.full_like(xs, z))
        self.land2 = land
        # doluluk: su + 8 m kiyi payi + kenar bandi
        wmask = ~land
        dil = wmask.copy()
        for _ in range(4):
            d = dil.copy()
            d[1:, :] |= dil[:-1, :]
            d[:-1, :] |= dil[1:, :]
            d[:, 1:] |= dil[:, :-1]
            d[:, :-1] |= dil[:, 1:]
            dil = d
        self.g.occ[dil] = BLOCKED
        b = (BORDER + 20) // OR
        self.g.occ[:b, :] = BLOCKED
        self.g.occ[-b:, :] = BLOCKED
        self.g.occ[:, :b] = BLOCKED
        self.g.occ[:, -b:] = BLOCKED
        self.stats["water_km2"] = round(float(a), 2)
        self.stats["land_km2"] = round(100.0 - float(a), 2)

    def distance_to_water(self):
        """25 m izgarada suya uzaklik (m): cok kaynakli Dijkstra."""
        dist = np.full((ZN, ZN), np.inf)
        heap = []
        for iz, ix in zip(*np.nonzero(self.water_z)):
            dist[iz, ix] = 0.0
            heap.append((0.0, int(iz), int(ix)))
        heapq.heapify(heap)
        steps = [(-1, 0, ZR), (1, 0, ZR), (0, -1, ZR), (0, 1, ZR),
                 (-1, -1, ZR * 1.4142), (-1, 1, ZR * 1.4142), (1, -1, ZR * 1.4142), (1, 1, ZR * 1.4142)]
        while heap:
            d, iz, ix = heapq.heappop(heap)
            if d > dist[iz, ix]:
                continue
            for dz, dx, w in steps:
                nz, nx = iz + dz, ix + dx
                if 0 <= nz < ZN and 0 <= nx < ZN and d + w < dist[nz, nx]:
                    dist[nz, nx] = d + w
                    heapq.heappush(heap, (d + w, nz, nx))
        dist[np.isinf(dist)] = 4000.0
        self.g.dist_water = dist

    # --- 2. semtler ---
    def assign_districts(self):
        land = ~self.water_z
        c = (np.arange(ZN) + 0.5) * ZR
        X, Z = np.meshgrid(c, c)
        centers = np.array([d[3] for d in DISTRICTS], dtype=np.float64)
        targets = np.array([d[4] for d in DISTRICTS]) * 1600.0     # hucre sayisi
        # Toplam kara alani hedef toplamindan farkliysa oranla.
        targets *= land.sum() / targets.sum()
        weights = np.zeros(len(DISTRICTS))
        # Semt siniri duz cizgi olmasin: kararli dalgalanma.
        wob = 70 * np.sin(X / 310.0) * np.cos(Z / 270.0) + 45 * np.sin((X + Z) / 190.0)
        for it in range(90):
            best = None
            best_cost = None
            for i, (cx, cz) in enumerate(centers):
                cost = np.hypot(X - cx, Z - cz) + wob * (1 if i % 2 else -1) - weights[i]
                if best is None:
                    best = np.zeros_like(cost, dtype=np.int16)
                    best_cost = cost
                else:
                    m = cost < best_cost
                    best[m] = i
                    best_cost = np.where(m, cost, best_cost)
            best[~land] = -1
            counts = np.array([(best == i).sum() for i in range(len(DISTRICTS))])
            err = targets - counts
            if np.abs(err).max() < 0.03 * targets.max():
                break
            weights += np.clip(err / 1600.0 * 55.0, -60, 60)
        self.g.district = best
        zone_area = {}
        for i, d in enumerate(DISTRICTS):
            a = counts[i] * ZR * ZR / 1e6
            zone_area[d[2]] = zone_area.get(d[2], 0.0) + a
        self.stats["district_km2"] = {d[0]: round(counts[i] * ZR * ZR / 1e6, 2) for i, d in enumerate(DISTRICTS)}
        self.stats["zone_km2"] = {k: round(v, 2) for k, v in zone_area.items()}
        self.say("alanlar (km2): " + ", ".join(f"{k} {v:.1f}" for k, v in zone_area.items()))
        rng = random.Random(SEED + 1)
        for i, d in enumerate(DISTRICTS):
            base = {"historic": 0.25, "commercial": 0.0, "industrial": 0.12}.get(d[2], 0.0)
            self.district_angle[i] = base + rng.uniform(-0.45, 0.45)

    # --- 3. arazi ---
    def build_terrain(self):
        n = SIZE // TERRAIN_RES
        c = (np.arange(n) + 0.5) * TERRAIN_RES
        X, Z = np.meshgrid(c, c)
        # suya uzaklik: 25 m izgaradan cift dogrusal
        dw = self.g.dist_water
        fx = X / ZR - 0.5
        fz = Z / ZR - 0.5
        ix = np.clip(np.floor(fx).astype(int), 0, ZN - 2)
        iz = np.clip(np.floor(fz).astype(int), 0, ZN - 2)
        tx = np.clip(fx - ix, 0, 1)
        tz = np.clip(fz - iz, 0, 1)
        dist_m = (dw[iz, ix] * (1 - tx) * (1 - tz) + dw[iz, ix + 1] * tx * (1 - tz)
                  + dw[iz + 1, ix] * (1 - tx) * tz + dw[iz + 1, ix + 1] * tx * tz)
        h = 1.3 + 19.0 * (1 - np.exp(-dist_m / 650.0))
        hills = [(2500, 7200, 13, 380), (3300, 6900, 11, 320), (3900, 7500, 9, 300), (3000, 8200, 10, 350),
                 (4200, 8000, 8, 280), (3500, 6100, 12, 360), (2600, 6300, 9, 300),
                 (5600, 1100, 24, 900), (2500, 900, 20, 800), (9000, 800, 18, 700),
                 (1500, 6000, 7, 700), (7600, 6800, 8, 700), (7800, 3500, 9, 800), (1200, 3000, 9, 700)]
        for hx, hz, amp, r in hills:
            h += amp * np.exp(-((X - hx) ** 2 + (Z - hz) ** 2) / (2 * r * r))
        h += 0.8 * np.sin(X / 170.0) * np.sin(Z / 210.0) + 0.5 * np.sin((X - Z) / 90.0)
        # Sanayi ve liman: duz rihtimlar.
        dg = self.g.district
        dz_ix = np.clip((Z // ZR).astype(int), 0, ZN - 1)
        dx_ix = np.clip((X // ZR).astype(int), 0, ZN - 1)
        dist_idx = dg[dz_ix, dx_ix]
        flat = np.zeros_like(h, dtype=bool)
        for i, d in enumerate(DISTRICTS):
            if d[2] == "industrial":
                flat |= dist_idx == i
        flat_h = 1.3 + 5.0 * (1 - np.exp(-dist_m / 300.0))
        h = np.where(flat, flat_h, h)
        # kiyi cizgisinde kara en az 1 m
        half = np.clip(np.round(h * 2.0), 2, 250).astype(np.uint8)
        self.g.terrain = half
        self.stats["terrain_m"] = [round(float(h.min()), 1), round(float(h.max()), 1)]

    # --- 4. ayrilmis kompleks alanlari ---
    def reserve(self, cx, cz, a, hx, hz):
        self.reserved.append((cx, cz, a, hx, hz))
        # 5 m pay: sokak kompleksin kenarina yapismaz, bina sirasi da.
        self.g.mark_rect(cx, cz, a, hx, hz, RESERVED, pad=5.0, only_free=True)

    def in_reserved(self, x, z, pad=0.0):
        for cx, cz, a, hx, hz in self.reserved:
            c, s = rot(a)
            dx, dz = x - cx, z - cz
            if abs(dx * c + dz * s) <= hx + pad and abs(-dx * s + dz * c) <= hz + pad:
                return True
        return False

    def fits(self, cx, cz, a, hx, hz):
        """Kompleks icin: tamamen karada, sinir bandinda degil, baska ayrilmis alanla ortusmuyor."""
        return self.g.rect_free(cx, cz, a, hx, hz, pad=4.0)

    def place_reserved(self, name, near, a, hx, hz, search=600, step=40, district=None):
        best = None
        cands = []
        for dz in range(-search, search + 1, step):
            for dx in range(-search, search + 1, step):
                cands.append((dx * dx + dz * dz, dx, dz))
        cands.sort()
        for _, dx, dz in cands:
            x, z = near[0] + dx, near[1] + dz
            if district is not None and self.g.district_at(x, z) != district:
                continue
            if self.fits(x, z, a, hx, hz):
                best = (x, z)
                break
        if best is None:
            raise RuntimeError(f"kompleks sigmadi: {name} {near}")
        self.reserve(best[0], best[1], a, hx, hz)
        return best

    # --- 5. yollar ---
    def add_road(self, pts, w, sw, surface, rtype, name=""):
        if len(pts) < 2:
            return
        length = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))
        if length < 30:
            return
        road = {"type": rtype, "w": w, "sw": sw, "surface": surface,
                "pts": [[round(p[0], 2), round(p[1], 2)] for p in pts]}
        if name:
            road["name"] = name
        self.roads.append(road)
        r = w * 0.5 + sw
        for i in range(len(pts) - 1):
            self.g.mark_segment(pts[i], pts[i + 1], r, ROAD)

    def trace(self, points, ok, min_len=40):
        """Ornek nokta dizisini gecerli kosulara gore parcalara boler."""
        runs = []
        cur = []
        for p in points:
            if ok(p):
                cur.append(p)
            else:
                if len(cur) >= 2:
                    runs.append(cur)
                cur = []
        if len(cur) >= 2:
            runs.append(cur)
        out = []
        for run in runs:
            length = sum(math.hypot(run[i + 1][0] - run[i][0], run[i + 1][1] - run[i][1]) for i in range(len(run) - 1))
            if length >= min_len:
                out.append(run)
        return out

    def open_ground(self, p, margin=0.0):
        x, z = p
        if x < BORDER + 25 or z < BORDER + 25 or x > SIZE - BORDER - 25 or z > SIZE - BORDER - 25:
            return False
        v = self.g.occ_at(x, z)
        return v != BLOCKED and v != RESERVED

    def build_arterials(self):
        rng = random.Random(SEED + 7)
        self.art_x = [700 + i * 1150 for i in range(9)]
        self.art_z = [600 + j * 1150 for j in range(9)]
        for x0 in self.art_x:
            ph = rng.uniform(0, 6.28)
            pts = [(x0 + 35 * math.sin(z / 900.0 + ph), float(z)) for z in range(0, SIZE + 1, 20)]
            for run in self.trace(pts, lambda p: self.open_ground(p, 6)):
                self.add_road(run, 12.0, 3.0, "asphalt", "primary")
        for z0 in self.art_z:
            ph = rng.uniform(0, 6.28)
            straight = abs(z0 - self.bridge_z) < 1
            pts = [(float(x), z0 + (0 if straight else 35 * math.sin(x / 900.0 + ph))) for x in range(0, SIZE + 1, 20)]
            for run in self.trace(pts, lambda p: self.open_ground(p, 6)):
                self.add_road(run, 12.0, 3.0, "asphalt", "primary")
        # Kiyi caddeleri: bogazin iki yakasi, halic, guney ve dogu kiyisi.
        zs = np.arange(2750, 9400, 20.0)
        for side in (-1, 1):
            pts = [(float(cx_inlet(z) + side * (hw_inlet(z) + 34)), float(z)) for z in zs]
            for run in self.trace(pts, lambda p: self.open_ground(p, 6)):
                self.add_road(run, 10.0, 3.0, "asphalt", "secondary")
        xs = np.arange(2350, 5600, 20.0)
        for side in (-1, 1):
            pts = [(float(x), float(zh_halic(x) + side * (hw_halic(x) + 30))) for x in xs]
            for run in self.trace(pts, lambda p: self.open_ground(p, 6)):
                self.add_road(run, 9.0, 3.0, "asphalt", "secondary")
        xs = np.arange(0, SIZE + 1, 20.0)
        pts = [(float(x), float(coast_s(x) - 42)) for x in xs]
        for run in self.trace(pts, lambda p: self.open_ground(p, 6)):
            self.add_road(run, 10.0, 3.0, "asphalt", "secondary")
        zs = np.arange(0, SIZE + 1, 20.0)
        pts = [(float(coast_e(z) - 42), float(z)) for z in zs]
        for run in self.trace(pts, lambda p: self.open_ground(p, 6)):
            self.add_road(run, 10.0, 3.0, "asphalt", "secondary")
        # Harita omurgasi (olcum senaryosu): dogu yakasi kiyidan kuzeye, kopruden batiya.
        self.spine = [[6300.0, 8600.0], [6200.0, 7400.0], [6100.0, 6350.0], [6000.0, 5200.0],
                      [5900.0, float(self.bridge_z)], [4200.0, float(self.bridge_z)], [3000.0, 4600.0],
                      [3000.0, 3500.0], [3000.0, 2300.0]]

    def build_streets(self):
        rng = random.Random(SEED + 11)
        for i, d in enumerate(DISTRICTS):
            zone = d[2]
            sa, sb, w, sw, surface, rtype, amp, lam = STREET[zone]
            ang = self.district_angle[i]
            ux, uz = math.cos(ang), math.sin(ang)
            vx, vz = -uz, ux
            cells = np.argwhere(self.g.district == i)
            if cells.size == 0:
                continue
            pts_c = (cells[:, ::-1] + 0.5) * ZR
            cxm, czm = pts_c.mean(axis=0)
            lu = (pts_c[:, 0] - cxm) * ux + (pts_c[:, 1] - czm) * uz
            lv = (pts_c[:, 0] - cxm) * vx + (pts_c[:, 1] - czm) * vz
            for fam, spacing, lo_p, hi_p, lo_t, hi_t, dx, dz, nx, nz in [
                ("A", sa, lv.min(), lv.max(), lu.min(), lu.max(), ux, uz, vx, vz),
                ("B", sb, lu.min(), lu.max(), lv.min(), lv.max(), vx, vz, ux, uz),
            ]:
                k = lo_p - spacing
                while k <= hi_p + spacing:
                    k += spacing * rng.uniform(0.85, 1.15)
                    ph = rng.uniform(0, 6.28)
                    samples = []
                    t = lo_t - 60
                    while t <= hi_t + 60:
                        off = k + amp * math.sin(t / lam + ph)
                        samples.append((cxm + t * dx + off * nx, czm + t * dz + off * nz))
                        t += 8.0
                    # Semt disina en fazla ~24 m tasar: komsu semtin sokagina baglanir.
                    inside = [self.g.district_at(p[0], p[1]) == i for p in samples]
                    ok_mask = []
                    for j in range(len(samples)):
                        near_in = any(inside[max(0, j - 3):j + 4])
                        ok_mask.append(near_in and self.open_ground(samples[j]))
                    runs = []
                    cur = []
                    for j, p in enumerate(samples):
                        if ok_mask[j]:
                            cur.append(p)
                        else:
                            if len(cur) >= 2:
                                runs.append(cur)
                            cur = []
                    if len(cur) >= 2:
                        runs.append(cur)
                    for run in runs:
                        simp = run[::3]
                        if simp[-1] != run[-1]:
                            simp.append(run[-1])
                        self.add_road(simp, w, sw, surface, rtype)

    # --- 6. binalar ---
    def add_building(self, poly, cls, levels, extra=None, mark=True, pad=1.0, rect=None):
        bid = "y%06d" % len(self.buildings)
        base = min(self.g.terrain_half(p[0], p[1]) for p in poly)
        cxp = sum(p[0] for p in poly) / len(poly)
        czp = sum(p[1] for p in poly) / len(poly)
        base = min(base, self.g.terrain_half(cxp, czp))
        b = {"id": bid, "class": cls, "levels": int(levels), "est": False, "height_source": "design",
             "poly": poly, "base_half": int(base), "name": "", "roof": "", "historic": False}
        if extra:
            b.update(extra)
        self.buildings.append(b)
        if mark and rect is not None:
            cx, cz, a, hx, hz = rect
            self.g.mark_rect(cx, cz, a, hx, hz, BUILDING, pad=pad)
        return b

    def try_rect(self, cx, cz, a, hx, hz, pad):
        if not self.g.rect_free(cx, cz, a, hx, hz, pad=pad):
            return False
        return True

    def fill_streets(self):
        """Sokak boyunca cephe dizisi (+ bazen arka sira): avlulu adalar."""
        rng = random.Random(SEED + 23)
        towers_left = 26
        for road in list(self.roads):
            pts = road["pts"]
            mid = pts[len(pts) // 2]
            di = self.g.district_at(mid[0], mid[1])
            if di < 0:
                continue
            zone = DISTRICTS[di][2]
            (fmin, fmax), (gmin, gmax), (dmin, dmax), lv, second = TYPOLOGY[zone]
            reach = road["w"] * 0.5 + road["sw"]
            # Cephe dizisi BUTUN cizgi boyunca yurur (kisa ornek parcalarina
            # bolunseydi 24 m'den uzun cephe hic sigmazdi).
            cum = [0.0]
            for s in range(len(pts) - 1):
                cum.append(cum[-1] + math.hypot(pts[s + 1][0] - pts[s][0], pts[s + 1][1] - pts[s][1]))
            L = cum[-1]
            if L < 10:
                continue

            def at(t):
                k = 0
                while k < len(pts) - 2 and cum[k + 1] < t:
                    k += 1
                seg = max(1e-6, cum[k + 1] - cum[k])
                u = min(1.0, max(0.0, (t - cum[k]) / seg))
                ax, az = pts[k]
                bx, bz = pts[k + 1]
                return ax + (bx - ax) * u, az + (bz - az) * u, (bx - ax) / seg, (bz - az) / seg
            for side in (1, -1):
                t = rng.uniform(1.0, 6.0)
                while t < L - 4:
                    f = rng.uniform(fmin, fmax)
                    depth = rng.uniform(dmin, dmax)
                    levels = rng.choice(lv)
                    tower = zone == "commercial" and di == 4 and towers_left > 0 and rng.random() < 0.07
                    if tower:
                        f = depth = rng.uniform(20, 26)
                        levels = rng.randint(12, 18)
                    if t + f > L + 4:
                        break
                    px, pz, ux, uz = at(t + f * 0.5)
                    nx, nz = -uz, ux
                    ang = math.atan2(uz, ux)
                    setback = rng.uniform(0.6, 1.6) if zone != "green" else rng.uniform(6, 14)
                    off = reach + setback + depth * 0.5
                    cx = px + nx * side * off
                    cz = pz + nz * side * off
                    pad = 0.0 if zone == "historic" else 1.0
                    if self.g.district_at(cx, cz) == di and self.try_rect(cx, cz, ang, f * 0.5, depth * 0.5, pad):
                        cls = pick(rng, CLASS_MIX[zone])
                        extra = {}
                        if zone == "historic" and rng.random() < 0.25:
                            extra["facade"] = "limestone"
                        self.add_building(rect_poly(cx, cz, ang, f * 0.5, depth * 0.5), cls, levels, extra,
                                          rect=(cx, cz, ang, f * 0.5, depth * 0.5), pad=pad)
                        if tower:
                            towers_left -= 1
                        # Arka sira (avlu arkasi): yalniz genis adalarda.
                        if rng.random() < second:
                            d2 = rng.uniform(dmin, dmax)
                            gap = rng.uniform(5, 9)
                            off2 = off + depth * 0.5 + gap + d2 * 0.5
                            cx2 = px + nx * side * off2
                            cz2 = pz + nz * side * off2
                            if self.g.district_at(cx2, cz2) == di and self.try_rect(cx2, cz2, ang, f * 0.5, d2 * 0.5, 1.0):
                                self.add_building(rect_poly(cx2, cz2, ang, f * 0.5, d2 * 0.5), pick(rng, CLASS_MIX[zone]),
                                                  max(1, levels - rng.randint(0, 2)), {},
                                                  rect=(cx2, cz2, ang, f * 0.5, d2 * 0.5), pad=1.0)
                        t += f + rng.uniform(gmin, gmax)
                    else:
                        t += 4.0

    # --- 7. ozel kompleksler ---
    def complex_buildings(self, cx, cz, a, parts, cls, extra=None):
        """parts: [(yerel x, yerel z, yari x, yari z, kat)] -> bina listesi."""
        c, s = rot(a)
        out = []
        for lx, lz, hx, hz, lvl in parts:
            px = cx + lx * c - lz * s
            pz = cz + lx * s + lz * c
            out.append(self.add_building(rect_poly(px, pz, a, hx, hz), cls, lvl, dict(extra or {}),
                                         rect=(px, pz, a, hx, hz), pad=0.5))
        return out

    def area_rect(self, kind, cx, cz, a, hx, hz, name=""):
        area = {"kind": kind, "poly": rect_poly(cx, cz, a, hx, hz)}
        if name:
            area["name"] = name
        self.areas.append(area)
        return area

    def poi(self, kind, name, p, buildings=(), extra=None):
        e = {"name": name, "p": [round(p[0], 2), round(p[1], 2)], "kind": kind}
        ids = [b["id"] for b in buildings]
        if ids:
            e["buildings"] = ids
        if extra:
            e.update(extra)
        self.pois.append(e)
        return e

    def wall_ring(self, cx, cz, a, hx, hz, gate_side="south", gate=14.0):
        """Kompleks cevre duvari (dolu, 4 m) -- bir kapi acikligi birakilir."""
        c, s = rot(a)
        segs = []
        t = 1.0
        for side, (x0, z0, x1, z1) in {"north": (-hx, -hz, hx, -hz), "south": (-hx, hz, hx, hz),
                                       "west": (-hx, -hz, -hx, hz), "east": (hx, -hz, hx, hz)}.items():
            L = math.hypot(x1 - x0, z1 - z0)
            ux, uz = (x1 - x0) / L, (z1 - z0) / L
            pieces = [(0.0, L)]
            if side == gate_side:
                pieces = [(0.0, L * 0.5 - gate * 0.5), (L * 0.5 + gate * 0.5, L)]
            for p0, p1 in pieces:
                if p1 - p0 < 2:
                    continue
                mx = x0 + ux * (p0 + p1) * 0.5
                mz = z0 + uz * (p0 + p1) * 0.5
                wx = cx + mx * c - mz * s
                wz = cz + mx * s + mz * c
                hl = (p1 - p0) * 0.5
                ang = a + math.atan2(uz, ux)
                segs.append(self.add_building(rect_poly(wx, wz, ang, hl, t), "fortification", 1,
                                              {"solid": True, "facade": "concrete"},
                                              rect=(wx, wz, ang, hl, t), pad=0.0))
        return segs

    def gate_point(self, cx, cz, a, hx, hz, side="south", out=10.0):
        c, s = rot(a)
        lx, lz = {"south": (0, hz + out), "north": (0, -hz - out), "west": (-hx - out, 0), "east": (hx + out, 0)}[side]
        return (cx + lx * c - lz * s, cz + lx * s + lz * c)

    def nearest_street_side(self, cx, cz, a, hx, hz):
        """Kompleksin hangi kenari yola en yakin (kapi oraya)."""
        best, best_d = "south", 1e9
        for side in ("south", "north", "west", "east"):
            gx, gz = self.gate_point(cx, cz, a, hx, hz, side, out=6.0)
            for r in range(0, 60, 4):
                hit = False
                for ddx, ddz in ((r, 0), (-r, 0), (0, r), (0, -r)):
                    if self.g.occ_at(gx + ddx, gz + ddz) == ROAD:
                        hit = True
                        break
                if hit:
                    if r < best_d:
                        best, best_d = side, r
                    break
        return best

    def access_road(self, gate, w=7.0):
        """Kapidan en yakin yola kisa baglanti."""
        gx, gz = gate
        best = None
        for r in range(4, 260, 4):
            for k in range(16):
                ang = k * math.pi / 8
                x, z = gx + r * math.cos(ang), gz + r * math.sin(ang)
                if self.g.occ_at(x, z) == ROAD:
                    best = (x, z)
                    break
            if best:
                break
        if best:
            self.add_road([(gx, gz), best], w, 1.5, "asphalt", "service")

    def build_specials(self):
        rng = random.Random(SEED + 31)
        D = {d[0]: i for i, d in enumerate(DISTRICTS)}
        ang = self.district_angle
        self.complex_list = []
        # --- askeri alanlar (3) ---
        mil = [("Kışla Garnizonu", "kisla", (1250, 1750), 150, 115), ("Liman Komutanlığı", "liman", (8750, 8350), 125, 95),
               ("Kayalık Radar Üssü", "kayalik", (9150, 900), 130, 100)]
        for name, dist, near, hx, hz in mil:
            a = ang[D[dist]]
            cx, cz = self.place_reserved(name, near, a, hx, hz, district=None)
            self.complex_list.append(("military", name, cx, cz, a, hx, hz))
        # --- hapishaneler (2) ---
        for name, dist, near, hx, hz in [("Kalebend Cezaevi", "kalebend", (9250, 5500), 110, 95),
                                         ("Demirhane Tutukevi", "demirhane", (9150, 2800), 100, 85)]:
            a = ang[D[dist]]
            cx, cz = self.place_reserved(name, near, a, hx, hz)
            self.complex_list.append(("prison", name, cx, cz, a, hx, hz))
        # --- hastaneler (4) ---
        for name, dist, near in [("Şifahane Devlet Hastanesi", "sifahane", (4250, 2200)),
                                 ("Kuzey Eğitim Hastanesi", "sifahane", (4950, 2650)),
                                 ("Çarşıbaşı Hastanesi", "carsibasi", (6300, 6900)),
                                 ("Lalezar Hastanesi", "lalezar", (2000, 3700))]:
            a = ang[D[dist]]
            cx, cz = self.place_reserved(name, near, a, 72, 55)
            self.complex_list.append(("hospital", name, cx, cz, a, 72, 55))
        # --- okullar (12) ---
        school_names = ["Martı İlkokulu", "Çınar Ortaokulu", "Lalezar Lisesi", "Kestane Koleji", "Badem İlkokulu",
                        "Ayvaz Ortaokulu", "Serinyalı Lisesi", "Mektepler Fen Lisesi", "Mektepler Sanat Okulu",
                        "Hanlar Ticaret Lisesi", "Rıhtım İlkokulu", "Sarnıç Ortaokulu"]
        school_zones = [D["martikoy"], D["cinarlibahce"], D["lalezar"], D["kestanelik"], D["bademlik"], D["ayvazdere"],
                        D["serinyali"], D["mektepler"], D["mektepler"], D["hanlar"], D["rihtim"], D["sarniconu"]]
        placed = []
        for name, di in zip(school_names, school_zones):
            cells = np.argwhere(self.g.district == di)
            r2 = random.Random(stable_hash(name))
            order = list(range(len(cells)))
            r2.shuffle(order)
            a = ang[di]
            done = False
            for idx in order[:4000]:
                iz, ix = cells[idx]
                x, z = (ix + 0.5) * ZR, (iz + 0.5) * ZR
                if self.g.dist_water[iz, ix] < 60 or any(math.hypot(x - px, z - pz) < 650 for px, pz in placed):
                    continue
                if self.fits(x, z, a, 52, 36):
                    self.reserve(x, z, a, 52, 36)
                    placed.append((x, z))
                    self.complex_list.append(("school", name, x, z, a, 52, 36))
                    done = True
                    break
            if not done:
                raise RuntimeError("okul sigmadi: " + name)
        # --- tarihi odaklar (8) ---
        hist = [("tower", "Martı Kulesi", "sarniconu", (3500, 6150), 34, 34),
                ("dome", "Büyük Kubbe", "kubbealti", (3650, 7600), 80, 66),
                ("palace", "Saray Avlusu", "saraykapi", (4300, 8420), 70, 56),
                ("cistern", "Yeraltı Sarnıcı", "sarniconu", (3100, 6750), 34, 28),
                ("han", "Kapalı Han", "kubbealti", (4050, 7250), 48, 38),
                ("square", "Sultan Meydanı", "surdibi", (2900, 7050), 76, 52)]
        for kind, name, dist, near, hx, hz in hist:
            a = ang[D[dist]]
            cx, cz = self.place_reserved(name, near, a, hx, hz)
            self.complex_list.append(("historic_" + kind, name, cx, cz, a, hx, hz))
        # Kiyi konagi: bogazin bati kiyisinda, suya bakan.
        z_y = 8050.0
        x_y = float(cx_inlet(z_y) - hw_inlet(z_y) - 30)
        cx, cz = self.place_reserved("Kıyı Konağı", (x_y, z_y), 0.0, 22, 14, search=300, step=10)
        self.complex_list.append(("historic_yali", "Kıyı Konağı", cx, cz, 0.0, 22, 14))
        # Spawn meydani (Rihtim iskele meydani): bogazin dogu kiyisi, agzina yakin.
        z_s = 8250.0
        x_s = float(cx_inlet(z_s) + hw_inlet(z_s) + 90)
        cx, cz = self.place_reserved("Rıhtım İskele Meydanı", (x_s, z_s), 0.0, 50, 36, search=400, step=10)
        self.complex_list.append(("spawn_square", "Rıhtım İskele Meydanı", cx, cz, 0.0, 50, 36))

    def build_complex_contents(self):
        rng = random.Random(SEED + 41)
        for kind, name, cx, cz, a, hx, hz in self.complex_list:
            side = self.nearest_street_side(cx, cz, a, hx, hz)
            if kind not in ("military", "prison", "historic_yali"):
                # Acik kompleks (meydan, avlu, kampus): kenarindan yola baglanti.
                self.access_road(self.gate_point(cx, cz, a, hx, hz, side, out=6.0))
            if kind == "military":
                self.area_rect("parking", cx, cz, a, hx - 2, hz - 2)
                bs = self.complex_buildings(cx, cz, a, [(-hx * 0.45, -hz * 0.5, 34, 8, 2), (hx * 0.35, -hz * 0.5, 30, 8, 2),
                                                        (-hx * 0.45, hz * 0.05, 18, 12, 3), (hx * 0.45, hz * 0.2, 26, 18, 2),
                                                        (0.0, hz * 0.55, 16, 10, 1)], "military")
                self.wall_ring(cx, cz, a, hx, hz, side)
                self.poi("military", name, (cx, cz), bs)
                self.access_road(self.gate_point(cx, cz, a, hx, hz, side, out=4.0))
                self.checkpoint_near(self.gate_point(cx, cz, a, hx, hz, side, out=16.0), name + " Kontrol Noktası")
            elif kind == "prison":
                self.area_rect("plaza", cx, cz, a, hx - 2, hz - 2)
                bs = self.complex_buildings(cx, cz, a, [(-hx * 0.4, -hz * 0.35, 30, 8, 3), (hx * 0.4, -hz * 0.35, 30, 8, 3),
                                                        (-hx * 0.4, hz * 0.2, 30, 8, 3), (hx * 0.45, hz * 0.3, 14, 10, 2),
                                                        (0.0, hz * 0.62, 18, 8, 2)], "prison")
                self.wall_ring(cx, cz, a, hx, hz, side, gate=10.0)
                self.poi("prison", name, (cx, cz), bs)
                self.access_road(self.gate_point(cx, cz, a, hx, hz, side, out=4.0))
            elif kind == "hospital":
                self.area_rect("plaza", cx, cz, a, hx - 1, hz - 1)
                bs = self.complex_buildings(cx, cz, a, [(0.0, -hz * 0.25, 40, 16, rng.randint(5, 7)),
                                                        (hx * 0.55, hz * 0.35, 16, 12, 3)], "hospital")
                self.area_rect("parking", *self._local(cx, cz, a, -hx * 0.45, hz * 0.45), a, 22, 14)
                self.poi("hospital", name, (cx, cz), bs)
                self.water_points.append({"p": [round(cx, 2), round(cz + 0.0, 2)], "kind": "icme_suyu", "name": name, "src": "design"})
            elif kind == "school":
                self.area_rect("pitch", *self._local(cx, cz, a, hx * 0.35, 0.0), a, 22, 15)
                bs = self.complex_buildings(cx, cz, a, [(-hx * 0.45, 0.0, 12, 30, 3), (hx * 0.2, -hz * 0.72, 18, 7, 2)],
                                            "school")
                self.poi("school", name, (cx, cz), bs)
            elif kind == "historic_tower":
                self.area_rect("plaza", cx, cz, a, hx, hz)
                b = self.add_building(octagon(cx, cz, 8.0, a), "fortification", 14,
                                      {"historic": True, "solid": True, "name": name},
                                      rect=(cx, cz, a, 8, 8), pad=0.5)
                self.poi("historic", name, (cx, cz), [b], {"family": "tower"})
                self.water_points.append({"p": [round(cx + 14, 2), round(cz + 14, 2)], "kind": "cesme", "name": name, "src": "design"})
            elif kind == "historic_dome":
                self.area_rect("plaza", cx, cz, a, hx, hz)
                dome = self.add_building(octagon(cx, cz, 26.0, a), "religious", 6, {"historic": True, "name": name},
                                         rect=(cx, cz, a, 26, 26), pad=0.5)
                ms = []
                for lx, lz in ((-34, -34), (34, -34), (-34, 34), (34, 34)):
                    px, pz = self._local(cx, cz, a, lx, lz)
                    ms.append(self.add_building(octagon(px, pz, 2.6, a), "fortification", 14,
                                                {"historic": True, "solid": True}, rect=(px, pz, a, 2.6, 2.6), pad=0.3))
                self.poi("historic", name, (cx, cz), [dome] + ms, {"family": "dome"})
                self.water_points.append({"p": [round(cx, 2), round(cz + 40, 2)], "kind": "sadirvan", "name": name, "src": "design"})
            elif kind == "historic_palace":
                self.area_rect("park", cx, cz, a, hx - 20, hz - 16)
                bs = self.complex_buildings(cx, cz, a, [(0.0, -hz + 10, hx, 10, 3), (-hx + 10, 4, 10, hz - 12, 3),
                                                        (hx - 10, 4, 10, hz - 12, 3)], "civic",
                                            {"historic": True, "name": name})
                self.poi("historic", name, (cx, cz), bs, {"family": "palace"})
                self.water_points.append({"p": [round(cx, 2), round(cz, 2)], "kind": "sadirvan", "name": name, "src": "design"})
            elif kind == "historic_cistern":
                self.area_rect("plaza", cx, cz, a, hx, hz)
                bs = self.complex_buildings(cx, cz, a, [(0.0, 0.0, 22, 16, 1)], "civic", {"facade": "limestone", "name": name})
                self.poi("historic", name, (cx, cz), bs, {"family": "cistern"})
                self.water_points.append({"p": [round(cx + 26, 2), round(cz, 2)], "kind": "el_pompasi", "name": name, "src": "design"})
            elif kind == "historic_han":
                self.area_rect("plaza", cx, cz, a, hx, hz)
                poly = rect_poly(cx, cz, a, 38, 28)
                hole = rect_poly(cx, cz, a, 14, 9)
                b = self.add_building(poly, "market", 2, {"facade": "limestone", "holes": [hole], "name": name},
                                      rect=(cx, cz, a, 38, 28), pad=0.5)
                self.poi("historic", name, (cx, cz), [b], {"family": "han"})
            elif kind == "historic_square":
                self.area_rect("plaza", cx, cz, a, hx, hz, name=name)
                b = self.add_building(rect_poly(cx, cz, a, 2.0, 2.0), "fortification", 5, {"historic": True, "solid": True},
                                      rect=(cx, cz, a, 2, 2), pad=0.3)
                self.poi("historic", name, (cx, cz), [b], {"family": "square"})
                for lx in (-40, 40):
                    px, pz = self._local(cx, cz, a, lx, 0)
                    self.water_points.append({"p": [round(px, 2), round(pz, 2)], "kind": "cesme", "name": name, "src": "design"})
            elif kind == "historic_yali":
                b = self.add_building(rect_poly(cx, cz, 0.0, 15, 7), "residential", 3,
                                      {"facade": "wood_old", "name": name}, rect=(cx, cz, 0.0, 15, 7), pad=0.5)
                # iskele: konaktan suya
                px = float(cx_inlet(cz) - hw_inlet(cz) + 30)
                self.areas.append({"kind": "pier", "poly": rect_poly((cx + 15 + px) * 0.5, cz, 0.0, max(8.0, (px - cx - 15) * 0.5), 4)})
                self.poi("historic", name, (cx, cz), [b], {"family": "waterfront_mansion"})
            elif kind == "spawn_square":
                self.area_rect("plaza", cx, cz, a, hx, hz, name=name)
                self.water_points.append({"p": [round(cx - 12, 2), round(cz, 2)], "kind": "cesme", "name": "Rıhtım", "src": "design"})
                # Vapur iskelesi: meydandan bogaza.
                shore = float(cx_inlet(cz) + hw_inlet(cz))
                self.areas.append({"kind": "pier", "poly": rect_poly((cx - hx + shore - 40) * 0.5, cz, 0.0,
                                                                     max(10.0, (cx - hx - shore + 40) * 0.5), 7)})
                self.poi("ferry_terminal", "Rıhtım İskelesi", (shore - 20, cz))
                self.spawn = (cx + 8, cz + 6)
                self.places["rihtim_iskele"] = [round(cx, 2), round(cz, 2)]

    def _local(self, cx, cz, a, lx, lz):
        c, s = rot(a)
        return (cx + lx * c - lz * s, cz + lx * s + lz * c)

    def checkpoint_near(self, p, name):
        """Kucuk kontrol binasi (kapi/kopru basi): yola degil, yanina."""
        for r in range(0, 90, 3):
            for k in range(12):
                ang = k * math.pi / 6
                x, z = p[0] + r * math.cos(ang), p[1] + r * math.sin(ang)
                if self.g.rect_free(x, z, 0.0, 5, 4, pad=1.0):
                    b = self.add_building(rect_poly(x, z, 0.0, 5, 4), "checkpoint", 1, {"name": name},
                                          rect=(x, z, 0.0, 5, 4), pad=1.0)
                    self.poi("checkpoint", name, (x, z), [b])
                    return b
        raise RuntimeError("kontrol noktasi sigmadi: " + name)

    # --- 8. kopruler ve iskeleler ---
    def plan_bridge(self):
        self.bridge_z = 4050.0
        z = self.bridge_z
        xw = float(cx_inlet(z) - hw_inlet(z))
        xe = float(cx_inlet(z) + hw_inlet(z))
        ramp = 280.0
        a = (xw - ramp, z)
        b = (xe + ramp, z)
        length = b[0] - a[0]
        pts = [[round(a[0] + length * k / 12.0, 2), z] for k in range(13)]
        self.bridge_decks.append({"name": "Martı Köprüsü", "pts": pts, "half": 9.0, "towers": [round(ramp - 6, 1), round(length - ramp + 6, 1)]})
        self.bridges_meta.append({"name": "Martı Köprüsü", "pts": [list(a), list(b)], "layer": "1"})
        # Kopru izi: bina ve sokak yok (kule ve rampa ayaklari). Iki uctaki
        # ilk 30 m zemin seviyesindedir: yaklasim yolu oraya baglanir.
        self.g.mark_segment((a[0] + 30, z), (b[0] - 30, z), 9 + 6, BLOCKED)
        self.bridge_ends = (a, b)

    def build_piers(self):
        # Bogazda iki alcak gecit (iskele-kopru) ve halicte iki gecit.
        for z in (6350.0, 7500.0):
            x0 = float(cx_inlet(z) - hw_inlet(z) - 14)
            x1 = float(cx_inlet(z) + hw_inlet(z) + 14)
            self.areas.append({"kind": "pier", "poly": rect_poly((x0 + x1) * 0.5, z, 0.0, (x1 - x0) * 0.5, 8), "name": "İskele Geçidi"})
            self.poi("bridge", "Alçak Geçit", ((x0 + x1) * 0.5, z))
            self.pier_ends = getattr(self, "pier_ends", []) + [(x0 - 10, z), (x1 + 10, z)]
        for x in self.art_x:
            if 2350 < x < float(cx_inlet(5320)) - 200:
                zc = float(zh_halic(x))
                hw = float(hw_halic(x))
                self.areas.append({"kind": "pier", "poly": rect_poly(x, zc, 0.0, 8, hw + 14), "name": "Haliç Geçidi"})
                self.poi("bridge", "Haliç Geçidi", (x, zc))
        # Vapur iskeleleri
        for name, x in (("Martıköy İskelesi", 1300.0), ("Saraykapı İskelesi", 4150.0), ("Liman İskelesi", 7900.0)):
            zc = float(coast_s(x))
            self.areas.append({"kind": "pier", "poly": rect_poly(x, zc + 20, 0.0, 7, 38)})
            self.poi("ferry_terminal", name, (x, zc + 10))

    def bridge_checkpoints(self):
        a, b = self.bridge_ends
        self.checkpoint_near((a[0] - 30, a[1] + 26), "Martı Köprüsü Batı Kontrolü")
        self.checkpoint_near((b[0] + 30, b[1] + 26), "Martı Köprüsü Doğu Kontrolü")
        e = self.pier_ends
        self.checkpoint_near((e[0][0] - 20, e[0][1] + 22), "Alçak Geçit Batı Kontrolü")
        self.checkpoint_near((e[1][0] + 20, e[1][1] + 22), "Alçak Geçit Doğu Kontrolü")
        # Kuzey kara yolu (bogazin ucu)
        self.checkpoint_near((float(cx_inlet(2600)), 2500.0), "Kuzey Yol Kontrolü")

    # --- 9. sur ---
    def build_walls(self):
        """Kara Surlari: Surdibi'nin batisinda kuzey-guney hat; yol gecen yerde kapi."""
        di = [d[0] for d in DISTRICTS].index("surdibi")
        cells = np.argwhere(self.g.district == di)
        xs = (cells[:, 1] + 0.5) * ZR
        x_line = float(np.percentile(xs, 12))
        z0 = float(((cells[:, 0] + 0.5) * ZR).min()) + 60
        z1 = float(((cells[:, 0] + 0.5) * ZR).max()) - 60
        z = z0
        n = 0
        walls = []
        while z < z1:
            x = x_line + 18 * math.sin(z / 260.0)
            if self.g.district_at(x, z) == di:
                if n % 5 == 0:
                    if self.g.rect_free(x, z, 0.0, 6, 6, pad=0.5):
                        walls.append(self.add_building(rect_poly(x, z, 0.0, 6, 6), "fortification", 5,
                                                       {"historic": True, "solid": True}, rect=(x, z, 0.0, 6, 6), pad=0.5))
                elif self.g.rect_free(x, z, 0.0, 2.2, 12, pad=0.2):
                    walls.append(self.add_building(rect_poly(x, z, 0.0, 2.2, 12), "fortification", 3,
                                                   {"historic": True, "solid": True}, rect=(x, z, 0.0, 2.2, 12), pad=0.2))
            z += 24.0
            n += 1
        if walls:
            self.poi("historic", "Kara Surları", (x_line, (z0 + z1) * 0.5), walls[:12], {"family": "wall"})

    # --- 10. donusturulen kurumlar ---
    def convert(self, cls, count, zones, spacing, near_first=None, size=(80, 600), levels=None, name_fmt=""):
        rng = random.Random(SEED + stable_hash(cls) % 1000)
        cands = []
        for i, b in enumerate(self.buildings):
            if b["class"] not in ("residential", "market", "civic") or b.get("solid") or b.get("historic") or b.get("name"):
                continue
            area = poly_area(b["poly"])
            if not size[0] <= area <= size[1]:
                continue
            cxp = sum(p[0] for p in b["poly"]) / len(b["poly"])
            czp = sum(p[1] for p in b["poly"]) / len(b["poly"])
            di = self.g.district_at(cxp, czp)
            if di < 0 or DISTRICTS[di][2] not in zones:
                continue
            cands.append((i, cxp, czp))
        rng.shuffle(cands)
        chosen = []
        if near_first is not None:
            cands.sort(key=lambda c: abs(math.hypot(c[1] - near_first[0], c[2] - near_first[1]) - near_first[2]))
        for i, x, z in cands:
            if len(chosen) >= count:
                break
            if any(math.hypot(x - px, z - pz) < spacing for _, px, pz in chosen):
                continue
            chosen.append((i, x, z))
            if near_first is not None:
                near_first = None
                rng.shuffle(cands)
        out = []
        for n, (i, x, z) in enumerate(chosen):
            b = self.buildings[i]
            b["class"] = cls
            if levels:
                b["levels"] = min(b["levels"], levels)
            if name_fmt:
                b["name"] = name_fmt % (n + 1) if "%d" in name_fmt else name_fmt
            out.append(b)
        if len(out) < count:
            raise RuntimeError(f"{cls}: {len(out)}/{count}")
        return out

    # --- 11. alanlar (yesil, mezarlik, meydan) ---
    def build_areas(self):
        rng = random.Random(SEED + 53)
        green = {i for i, d in enumerate(DISTRICTS) if d[2] == "green"}
        step = 100
        for iz in range(0, SIZE, step):
            for ix in range(0, SIZE, step):
                cx, cz = ix + step / 2, iz + step / 2
                di = self.g.district_at(cx, cz)
                if di < 0:
                    continue
                sub = self.g.occ[iz // OR:(iz + step) // OR, ix // OR:(ix + step) // OR]
                if sub.size == 0:
                    continue
                free = (sub == FREE).mean()
                if di in green and free > 0.75:
                    kind = "forest" if DISTRICTS[di][0] in ("korubasi", "sirtlar") else ("park" if rng.random() < 0.5 else "grass")
                    self.areas.append({"kind": kind, "poly": rect_poly(cx, cz, 0.0, step / 2 - 1, step / 2 - 1)})
                elif di not in green and free > 0.92 and rng.random() < 0.6:
                    self.areas.append({"kind": "park" if rng.random() < 0.6 else "grass",
                                       "poly": rect_poly(cx, cz, 0.0, step / 2 - 2, step / 2 - 2)})
        # Mezarliklar (2) ve pazar meydanlari
        for name, near in (("Surdibi Mezarlığı", (2350, 8200)), ("Kestanelik Mezarlığı", (7600, 4700))):
            for r in range(0, 600, 20):
                done = False
                for k in range(16):
                    x = near[0] + r * math.cos(k * math.pi / 8)
                    z = near[1] + r * math.sin(k * math.pi / 8)
                    if self.g.rect_free(x, z, 0.0, 45, 35, pad=2):
                        self.areas.append({"kind": "cemetery", "poly": rect_poly(x, z, 0.0, 45, 35), "name": name})
                        self.g.mark_rect(x, z, 0.0, 45, 35, RESERVED)
                        done = True
                        break
                if done:
                    break

    # --- 12. su noktalari ve adlandirilmis yerler ---
    def street_fountains(self):
        rng = random.Random(SEED + 61)
        placed = [tuple(w["p"]) for w in self.water_points]
        for road in self.roads:
            if road["sw"] < 1.5:
                continue
            pts = road["pts"]
            mid = pts[len(pts) // 2]
            di = self.g.district_at(mid[0], mid[1])
            if di < 0 or DISTRICTS[di][2] not in ("residential", "historic", "commercial"):
                continue
            ax, az = pts[0]
            bx, bz = pts[1]
            L = math.hypot(bx - ax, bz - az)
            if L < 20:
                continue
            nx, nz = -(bz - az) / L, (bx - ax) / L
            off = road["w"] * 0.5 + road["sw"] * 0.5
            x, z = ax + (bx - ax) * 0.5 + nx * off, az + (bz - az) * 0.5 + nz * off
            if any(math.hypot(x - px, z - pz) < 330 for px, pz in placed):
                continue
            if self.g.occ_at(x, z) == BUILDING:
                continue
            placed.append((x, z))
            self.water_points.append({"p": [round(x, 2), round(z, 2)], "kind": rng.choice(["cesme", "cesme", "icme_suyu"]),
                                      "name": "", "src": "design"})

    def name_places(self):
        """Gorev capalari: yeni sabit POI kimlikleri (eski gercek adlarin yerine)."""
        def find(zone_district, prefer):
            di = [d[0] for d in DISTRICTS].index(zone_district)
            cells = np.argwhere(self.g.district == di)
            best, best_d = None, 1e18
            for iz, ix in cells:
                x, z = (ix + 0.5) * ZR, (iz + 0.5) * ZR
                if self.g.occ_at(x, z) not in (FREE, ROAD):
                    continue
                d = math.hypot(x - prefer[0], z - prefer[1])
                if d < best_d:
                    best, best_d = (x, z), d
            return [round(best[0], 2), round(best[1], 2)]
        self.places["feneralti_burnu"] = find("rihtim", (7200, float(coast_s(7200)) - 60))
        self.places["liman_gari"] = find("liman", (7800, 8300))
        self.places["carsibasi_meydan"] = find("carsibasi", (5900, 5900))
        self.places["saraykapi_iskele"] = find("saraykapi", (4150, float(coast_s(4150)) - 50))
        self.places["bademlik_sahil"] = find("bademlik", (float(coast_e(7200)) - 80, 7200))
        self.places["kalebend_sahil"] = find("kalebend", (float(coast_e(6200)) - 80, 6200))
        self.places["martikoy_sahil"] = find("martikoy", (1100, float(coast_s(1100)) - 60))
        self.place_names = {
            "rihtim_iskele": "Rıhtım İskele Meydanı", "feneralti_burnu": "Feneraltı Burnu", "liman_gari": "Liman Garı",
            "carsibasi_meydan": "Çarşıbaşı Meydanı", "saraykapi_iskele": "Saraykapı İskelesi",
            "bademlik_sahil": "Bademlik Sahili", "kalebend_sahil": "Kalebend Sahili", "martikoy_sahil": "Martıköy Sahili",
        }
        # Semt adlari haritada (buyuk harf etiket).
        for i, d in enumerate(DISTRICTS):
            cells = np.argwhere(self.g.district == i)
            if cells.size:
                c = (cells[:, ::-1] + 0.5).mean(axis=0) * ZR
                self.pois.append({"name": d[1], "p": [round(float(c[0]), 2), round(float(c[1]), 2)], "kind": "district"})

    # --- 13. harita goruntusu ---
    def map_image(self, res=4):
        n = SIZE // res
        img = np.zeros((n, n, 3), dtype=np.uint8)
        zone_col = {"historic": (176, 160, 132), "residential": (150, 146, 136), "commercial": (160, 150, 140),
                    "industrial": (138, 136, 130), "green": (96, 128, 86), "institutional": (142, 150, 150)}
        dg = self.g.district
        idx = dg[np.clip((np.arange(n) * res) // ZR, 0, ZN - 1)][:, np.clip((np.arange(n) * res) // ZR, 0, ZN - 1)]
        for i, d in enumerate(DISTRICTS):
            img[idx == i] = zone_col[d[2]]
        land = self.land2[::res // LAND_RES, ::res // LAND_RES][:n, :n]
        img[~land] = (46, 82, 108)
        occ = self.g.occ[::res // OR, ::res // OR][:n, :n]
        img[(occ == ROAD) & land] = (70, 70, 74)

        def fill_poly(poly, col):
            xs = [p[0] / res for p in poly]
            zs = [p[1] / res for p in poly]
            x0, x1 = max(0, int(min(xs))), min(n - 1, int(max(xs)) + 1)
            z0, z1 = max(0, int(min(zs))), min(n - 1, int(max(zs)) + 1)
            if x1 < x0 or z1 < z0:
                return
            X, Z = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(z0, z1 + 1) + 0.5)
            inside = np.zeros_like(X, dtype=bool)
            m = len(xs)
            j = m - 1
            for i in range(m):
                cond = ((zs[i] > Z) != (zs[j] > Z)) & (X < (xs[j] - xs[i]) * (Z - zs[i]) / (zs[j] - zs[i] + 1e-9) + xs[i])
                inside ^= cond
                j = i
            view = img[z0:z1 + 1, x0:x1 + 1]
            view[inside] = col
        area_col = {"park": (86, 124, 74), "forest": (64, 102, 60), "grass": (104, 136, 88), "cemetery": (90, 110, 86),
                    "plaza": (178, 170, 156), "parking": (96, 96, 100), "pitch": (92, 140, 84), "pier": (130, 104, 76)}
        for a in self.areas:
            fill_poly(a["poly"], area_col.get(a["kind"], (120, 120, 120)))
        cls_col = {"residential": (196, 180, 160), "market": (214, 188, 132), "civic": (170, 180, 196), "hospital": (224, 120, 120),
                   "pharmacy": (120, 200, 140), "school": (230, 200, 90), "military": (110, 130, 90), "prison": (120, 100, 110),
                   "police": (110, 130, 170), "checkpoint": (200, 90, 60), "fortification": (200, 190, 160),
                   "religious": (230, 220, 190), "industrial": (150, 150, 158), "workshop": (160, 150, 140),
                   "garage": (150, 140, 130), "electronics": (170, 170, 200), "clinic": (220, 160, 160), "derelict": (120, 112, 104)}
        for b in self.buildings:
            fill_poly(b["poly"], cls_col.get(b["class"], (180, 170, 160)))
        return png_rgb(img)

    # --- toplu ---
    def run(self):
        t0 = time.time()
        self.build_water()
        self.distance_to_water()
        self.assign_districts()
        self.build_terrain()
        self.plan_bridge()
        self.build_specials()
        self.build_arterials()
        self.build_piers()
        self.build_streets()
        self.say(f"yollar: {len(self.roads)}  ({time.time() - t0:.1f} sn)")
        self.build_complex_contents()
        self.bridge_checkpoints()
        self.build_walls()
        self.fill_streets()
        self.say(f"binalar: {len(self.buildings)}  ({time.time() - t0:.1f} sn)")
        sp = self.spawn
        ph = self.convert("pharmacy", 1, ("commercial", "residential", "historic"), 0, near_first=(sp[0], sp[1], 260),
                          size=(90, 700), name_fmt="Rıhtım Eczanesi")
        ph += self.convert("pharmacy", 23, ("commercial", "residential", "historic"), 360, size=(90, 700),
                           name_fmt="Eczane %d")
        for b in ph:
            c = poly_centroid(b["poly"])
            self.poi("pharmacy", b["name"], c, [b])
        cl = self.convert("clinic", 8, ("residential", "commercial", "historic"), 850, size=(180, 900),
                          name_fmt="Sağlık Ocağı %d", levels=3)
        for b in cl:
            self.poi("clinic", b["name"], poly_centroid(b["poly"]), [b])
        self.build_areas()
        self.street_fountains()
        self.name_places()
        self.check_counts()
        self.coverage()
        self.say(f"tamam ({time.time() - t0:.1f} sn)")

    def check_counts(self):
        need = {"military": 3, "checkpoint": 8, "hospital": 4, "clinic": 8, "pharmacy": 24, "school": 12, "prison": 2}
        have = {}
        for p in self.pois:
            have[p["kind"]] = have.get(p["kind"], 0) + 1
        fam = sorted({p.get("family") for p in self.pois if p["kind"] == "historic"})
        self.stats["poi_counts"] = have
        self.stats["historic_families"] = fam
        for k, v in need.items():
            if have.get(k, 0) != v:
                raise RuntimeError(f"POI sayisi {k}: {have.get(k, 0)} != {v}")
        if len(fam) != 8:
            raise RuntimeError(f"tarihi odak aileleri: {fam}")
        # dogus mesafeleri
        sp = self.spawn
        def nearest(kind):
            ds = [math.hypot(p["p"][0] - sp[0], p["p"][1] - sp[1]) for p in self.pois if p["kind"] == kind]
            return round(min(ds), 1) if ds else None
        wd = min(math.hypot(w["p"][0] - sp[0], w["p"][1] - sp[1]) for w in self.water_points)
        self.stats["spawn"] = {"p": [round(sp[0], 1), round(sp[1], 1)], "water_m": round(wd, 1), "pharmacy_m": nearest("pharmacy"),
                               "clinic_m": nearest("clinic"), "school_m": nearest("school"), "hospital_m": nearest("hospital")}
        # buyuk hedefler arasi mesafe (askeri, hastane, hapishane, tarihi)
        big = [p for p in self.pois if p["kind"] in ("military", "hospital", "prison", "historic")]
        nn = []
        for p in big:
            ds = [math.hypot(p["p"][0] - q["p"][0], p["p"][1] - q["p"][1]) for q in big if q is not p]
            nn.append(min(ds))
        self.stats["big_target_nn_m"] = [round(min(nn)), round(float(np.median(nn))), round(max(nn))]
        # mahalle kesif noktalari (eczane, okul, saglik ocagi, cesme, dukkan) arasi medyan
        small = [p["p"] for p in self.pois if p["kind"] in ("pharmacy", "school", "clinic", "checkpoint")] + \
                [w["p"] for w in self.water_points]
        nn2 = []
        for p in small:
            ds = [math.hypot(p[0] - q[0], p[1] - q[1]) for q in small if q is not p]
            nn2.append(min(ds))
        self.stats["neighborhood_poi_nn_m"] = [round(float(np.percentile(nn2, 10))), round(float(np.median(nn2))),
                                               round(float(np.percentile(nn2, 90)))]

    def coverage(self):
        """Kaplama: bina tabani / parsel (yol ve su payi disi) -- alan bazinda."""
        occ = self.g.occ
        zone_of = np.full((ZN, ZN), -1, dtype=np.int16)
        zone_ids = list(ZONES)
        for i, d in enumerate(DISTRICTS):
            zone_of[self.g.district == i] = zone_ids.index(d[2])
        idx = np.clip((np.arange(ON) * OR) // ZR, 0, ZN - 1)
        zmap = zone_of[idx][:, idx]
        bld_area = {z: 0.0 for z in zone_ids}
        for b in self.buildings:
            c = poly_centroid(b["poly"])
            di = self.g.district_at(c[0], c[1])
            if di < 0:
                continue
            a = poly_area(b["poly"])
            for h in b.get("holes", []):
                a -= poly_area(h)
            bld_area[DISTRICTS[di][2]] += a
        cov = {}
        for k, z in enumerate(zone_ids):
            parcel = ((zmap == k) & (occ != ROAD) & (occ != BLOCKED)).sum() * OR * OR
            cov[z] = round(bld_area[z] / max(1.0, parcel) * 100.0, 1)
        self.stats["coverage_pct"] = cov
        self.stats["buildings"] = len(self.buildings)
        self.stats["roads"] = len(self.roads)
        self.stats["areas"] = len(self.areas)
        self.stats["water_points"] = len(self.water_points)
        self.stats["road_km"] = round(sum(sum(math.hypot(r["pts"][i + 1][0] - r["pts"][i][0], r["pts"][i + 1][1] - r["pts"][i][1])
                                              for i in range(len(r["pts"]) - 1)) for r in self.roads) / 1000.0, 1)
        self.say("kaplama %: " + json.dumps(cov, ensure_ascii=False))

    def to_json(self):
        land_rle = rle_rows(self.land2)
        n_in = SIZE // INSIDE_RES
        inside = np.zeros((n_in, n_in), dtype=bool)
        b = BORDER // INSIDE_RES
        inside[b:n_in - b, b:n_in - b] = True
        grid_bytes = (self.g.district + 1).astype(np.uint8).tobytes()
        districts = []
        for i, d in enumerate(DISTRICTS):
            cells = np.argwhere(self.g.district == i)
            c = (cells[:, ::-1] + 0.5).mean(axis=0) * ZR if cells.size else np.array(d[3])
            districts.append({"id": d[0], "name": d[1], "zone": d[2], "center": [round(float(c[0]), 1), round(float(c[1]), 1)],
                              "area_km2": round(cells.shape[0] * ZR * ZR / 1e6, 2)})
        data = {
            "map_id": MAP_ID, "name": MAP_NAME, "format": 3, "world_version": WORLD_VERSION, "seed": SEED,
            "fictional": True, "scale": 1.0,
            "license": "Özgün tasarım (Istanbul-Z). Gerçek harita verisi içermez.",
            "size": [SIZE, SIZE], "border": BORDER,
            "land_res": LAND_RES, "land_rle": land_rle,
            "inside_res": INSIDE_RES, "inside_rle": rle_rows(inside),
            "terrain_res": TERRAIN_RES, "terrain_size": [self.g.terrain.shape[1], self.g.terrain.shape[0]],
            "terrain_grid": b64deflate(self.g.terrain.tobytes()),
            "buildings": self.buildings, "roads": self.roads, "areas": self.areas, "pois": self.pois,
            "bridges": self.bridges_meta, "bridge_decks": self.bridge_decks,
            "spine": self.spine, "spawn": [round(self.spawn[0], 2), round(self.spawn[1], 2)],
            "water_points": self.water_points, "places": self.places, "place_names": self.place_names,
            "districts": districts, "zones": {k: v["label"] for k, v in ZONES.items()},
            "district_grid": {"res": ZR, "size": [ZN, ZN], "data": b64deflate(grid_bytes)},
            "stats": self.stats,
        }
        h = hashlib.sha256()
        for key in ("buildings", "roads", "pois", "areas", "places"):
            h.update(json.dumps(data[key], sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
        data["content_hash"] = h.hexdigest()
        data["map_image"] = {"res": 4, "png": base64.b64encode(self.map_image(4)).decode("ascii")}
        return data


def poly_centroid(poly):
    return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))


def png_rgb(img: np.ndarray) -> bytes:
    h, w, _ = img.shape
    raw = b"".join(b"\x00" + img[r].tobytes() for r in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    city = City()
    city.run()
    data = city.to_json()
    print("icerik hash:", data["content_hash"])
    print(json.dumps(data["stats"], ensure_ascii=False, indent=1))
    if "--check" in sys.argv:
        return
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print("yazildi:", OUT, round(os.path.getsize(OUT) / 1e6, 1), "MB")


if __name__ == "__main__":
    main()
