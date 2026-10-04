"""Ham OSM onbellegi -> KORIDOR haritasi (Maltepe-Besiktas), bicim v3.

YALNIZCA GELISTIRME ARACIDIR.

NEDEN KORIDOR?
    "Maltepe'den Besiktas'a" bir dikdortgen olarak alinirsa ~200 milyon
    sutunluk bir alan eder; cogu Atasehir gibi kapsam disi ic bolgelerdir.
    Harita kiyi OMURGASI boyunca belirli genislikte bir koridordur. Koridor
    disi oyunda gorunmez sinirdir ve harita ekraninda soluk gosterilir.

BICIM v3 (25 Eylul 2026) -- GERCEK OLCEK
    * 1 oyun birimi = 1 gercek metre (scale 1.0). Koordinat donusumu tek
      yerde: tools/geo.py + src/core/geo_transform.gd, haritada "transform".
      Eski 0.65 haritalarinin parametreleri data/map/legacy_transforms.json.
    * Binalar libosmium alanlarindan: dis halka "poly", ic avlular "holes".
      Ic avlu bina hacmiyle doldurulmaz.
    * building:part ust binaya baglanir, ayri bina olarak yazilmaz; parcanin
      kat/yukseklik bilgisi ust binanin yuksekligini belirler.
    * Kat sayisi kaynagi acikca isaretlenir: height_source =
      osm_levels | osm_height | osm_parts | neighbours | class_estimate;
      height_conf = high | medium | low. Tahmin gercek olcu gibi sunulmaz.
    * Yol genisligi: OSM width > lanes x 3.2 > yol tipi tablosu.
    * Dogrulama raporu: fps/docs/reports/harita_raporu.json (+ .md):
      kaynak/cikti bina kimlik farki ve eleme gerekceleri, 250 m hucre ve
      semt karsilastirmasi, yol agi bilesenleri/uzunluklari, gercek
      koordinatli mesafe ciftleri ve Kadikoy-Bostanci rota olcumu.

Kullanim:
    python fps/tools/build_corridor.py --id maltepe_besiktas
"""

from __future__ import annotations

import argparse
import base64
import heapq
import json
import math
import struct
import sys
import time
import zlib
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from build_map import AREA_KINDS, ROADS, classify, load_classes, point_in_polygon, polygon_area  # noqa: E402
from geo import GeoTransform, haversine  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path(__file__).parent / "cache" / "osm_raw.json"
REPORT_DIR = ROOT / "docs" / "reports"
MAP_FORMAT = 3
MIN_EXTRACTOR = 2

# Omurga (enlem, boylam): kiyi boyunca Maltepe -> Uskudar -> kopru -> Besiktas.
SPINE = [
    (40.9215, 29.1330), (40.9330, 29.1170), (40.9450, 29.1060), (40.9560, 29.0930),
    (40.9625, 29.0780), (40.9695, 29.0640), (40.9760, 29.0470), (40.9840, 29.0330),
    (40.9905, 29.0250), (40.9990, 29.0200), (41.0130, 29.0110), (41.0250, 29.0140),
    (41.0340, 29.0250), (41.0400, 29.0400), (41.0455, 29.0343), (41.0510, 29.0286),
    (41.0470, 29.0180), (41.0430, 29.0060),
]
MAJOR_BRIDGE = "15 Temmuz"
BRIDGE_DECK_WIDTH = 33.4  # gercek tabliye genisligi (m)
SCENERY_M = 150.0         # koridor disinda GORUNEN ama girilemeyen serit (m)
MAP_RES = 4               # harita ekrani goruntusu: piksel basina m
FLOOR_M = 3.0             # OSM height -> kat donusumu (gercek kat yuksekligi)
DRIVABLE = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
            "living_street", "service", "motorway_link", "trunk_link", "primary_link", "secondary_link",
            "tertiary_link"}
CLASS_BASE_LEVELS = {"residential": 5, "market": 4, "pharmacy": 5, "civic": 4, "religious": 2, "garage": 1,
                     "industrial": 2, "workshop": 3, "hospital": 6, "police": 3, "electronics": 4,
                     "military": 3, "derelict": 3}
# Rapor icin bilinen noktalar (enlem, boylam).
PLACES = {
    "Kadikoy iskele meydani": (40.9918, 29.0240), "Bostanci sahil": (40.9562, 29.0936),
    "Uskudar meydan": (41.0257, 29.0150), "Besiktas iskele": (41.0425, 29.0070),
    "Maltepe sahil": (40.9270, 29.1310), "Moda burnu": (40.9790, 29.0260),
    "Caddebostan": (40.9665, 29.0640), "Haydarpasa gari": (40.9969, 29.0190),
}
DISTANCE_PAIRS = [
    ("Kadikoy iskele meydani", "Bostanci sahil"), ("Kadikoy iskele meydani", "Uskudar meydan"),
    ("Uskudar meydan", "Besiktas iskele"), ("Maltepe sahil", "Bostanci sahil"),
    ("Moda burnu", "Caddebostan"), ("Haydarpasa gari", "Kadikoy iskele meydani"),
]


def pack(array: np.ndarray) -> str:
    return base64.b64encode(zlib.compress(array.astype(np.uint8).tobytes(), 9)).decode("ascii")


def png_base64(rgb: np.ndarray) -> str:
    """Bagimliliksiz PNG yazici (Pillow gerekmez): RGB8, filtre yok."""
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[i].tobytes() for i in range(h))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    return base64.b64encode(png).decode("ascii")


class Raster:
    """Harita ekrani icin numpy tabanli basit cizici (piksel = MAP_RES m)."""

    def __init__(self, w: int, h: int):
        self.img = np.zeros((h, w, 3), dtype=np.float32)
        self.w, self.h = w, h

    def _box(self, xs, zs, pad: float = 0.0):
        x0 = max(0, int(min(xs) - pad))
        x1 = min(self.w - 1, int(max(xs) + pad))
        z0 = max(0, int(min(zs) - pad))
        z1 = min(self.h - 1, int(max(zs) + pad))
        if x1 < x0 or z1 < z0:
            return None
        px, pz = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(z0, z1 + 1) + 0.5)
        return x0, z0, px, pz

    def polygon(self, poly, color) -> None:
        pts = [(x / MAP_RES, z / MAP_RES) for x, z in poly]
        box = self._box([p[0] for p in pts], [p[1] for p in pts])
        if box is None:
            return
        x0, z0, px, pz = box
        inside = np.zeros(px.shape, dtype=bool)
        for (xi, zi), (xj, zj) in zip(pts, pts[1:] + pts[:1]):
            crosses = (zi > pz) != (zj > pz)
            x_at = (xj - xi) * (pz - zi) / ((zj - zi) or 1e-9) + xi
            inside ^= crosses & (px < x_at)
        view = self.img[z0:z0 + px.shape[0], x0:x0 + px.shape[1]]
        if inside.any():
            view[inside] = color
        else:  # pikselden kucuk yapi: yine de bir nokta
            cx, cz = int(sum(p[0] for p in pts) / len(pts)), int(sum(p[1] for p in pts) / len(pts))
            if 0 <= cx < self.w and 0 <= cz < self.h:
                self.img[cz, cx] = color

    def stroke(self, a, b, half_m: float, color) -> None:
        ax, az, bx, bz = a[0] / MAP_RES, a[1] / MAP_RES, b[0] / MAP_RES, b[1] / MAP_RES
        half = max(0.7, half_m / MAP_RES)
        box = self._box([ax, bx], [az, bz], half + 1)
        if box is None:
            return
        x0, z0, px, pz = box
        dx, dz = bx - ax, bz - az
        t = np.clip(((px - ax) * dx + (pz - az) * dz) / max(1e-9, dx * dx + dz * dz), 0.0, 1.0)
        near = np.hypot(px - (ax + t * dx), pz - (az + t * dz)) <= half
        self.img[z0:z0 + px.shape[0], x0:x0 + px.shape[1]][near] = color


def resample(pts: list, count: int) -> np.ndarray:
    """Cizgiyi yay uzunluguna gore esit aralikli `count` noktaya boler."""
    p = np.array(pts, dtype=np.float64)
    seg = np.hypot(*(p[1:] - p[:-1]).T)
    cum = np.concatenate(([0.0], np.cumsum(seg)))
    targets = np.linspace(0.0, cum[-1], count)
    return np.stack([np.interp(targets, cum, p[:, 0]), np.interp(targets, cum, p[:, 1])], axis=1)


def rle_rows(mask: np.ndarray) -> list:
    """Her satir: [ilk deger, run1, run2, ...]."""
    rows = []
    for row in mask:
        values = row.astype(np.int8)
        changes = np.flatnonzero(np.diff(values)) + 1
        bounds = np.concatenate(([0], changes, [len(values)]))
        rows.append([int(values[0])] + [int(b - a) for a, b in zip(bounds[:-1], bounds[1:])])
    return rows


def number(text) -> float | None:
    """'21', '21 m', '21,5' -> float; olcu degilse None."""
    if text is None:
        return None
    value = str(text).lower().replace("m", "").replace(",", ".").strip()
    try:
        result = float(value.split(";")[0])
    except ValueError:
        return None
    return result if math.isfinite(result) and result >= 0 else None


def wavefront_distance(sea: np.ndarray, step: float, cap: float) -> np.ndarray:
    """Denize 4-komsu (Manhattan) uzaklik, numpy dalga cephesi. `cap` otesi cap."""
    dist = np.full(sea.shape, cap, dtype=np.float32)
    dist[sea] = 0.0
    reached = sea.copy()
    frontier = sea.copy()
    k = 0
    while frontier.any() and (k + 1) * step < cap:
        k += 1
        grown = np.zeros_like(frontier)
        grown[1:, :] |= frontier[:-1, :]
        grown[:-1, :] |= frontier[1:, :]
        grown[:, 1:] |= frontier[:, :-1]
        grown[:, :-1] |= frontier[:, 1:]
        grown &= ~reached
        dist[grown] = k * step
        reached |= grown
        frontier = grown
    return dist


def ring_area_m2(ring: list) -> float:
    """Enlem/boylam halkasinin alani (halkanin kendi enleminde yerel izdusum)."""
    lat0 = sum(p[1] for p in ring) / len(ring)
    mx = 111320.0 * math.cos(math.radians(lat0))
    pts = [(lon * mx, lat * 110540.0) for lon, lat in ring]
    return polygon_area(pts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--id", default="maltepe_besiktas")
    parser.add_argument("--name", default="Maltepe - Besiktas")
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--corridor-m", type=float, default=850.0, help="omurgadan her iki yana gercek metre")
    parser.add_argument("--spawn", type=float, nargs=2, default=(40.9910, 29.0250))
    parser.add_argument("--cache", type=Path, default=CACHE)
    args = parser.parse_args()
    started = time.time()
    raw = json.loads(args.cache.read_text(encoding="utf-8"))
    if int(raw.get("extractor_version", 1)) < MIN_EXTRACTOR:
        print(f"HATA: onbellek eski cikarici surumunden ({raw.get('extractor_version', 1)}). "
              "Once: python fps/tools/osm_extract.py turkey-260909.osm.pbf", file=sys.stderr)
        return 2

    lats = [p[0] for p in SPINE]
    lons = [p[1] for p in SPINE]
    lat0 = (min(lats) + max(lats)) / 2
    pad_lat = args.corridor_m / 110540.0
    pad_lon = args.corridor_m / (111320.0 * math.cos(math.radians(lat0)))
    min_lat, max_lat = min(lats) - pad_lat, max(lats) + pad_lat
    min_lon, max_lon = min(lons) - pad_lon, max(lons) + pad_lon
    lon0 = (min_lon + max_lon) / 2
    geo = GeoTransform(min_lon, max_lat, lat0, args.scale)
    scale = args.scale
    width = int(math.ceil(geo.forward(max_lon, min_lat)[0]))
    height = int(math.ceil(geo.forward(max_lon, min_lat)[1]))

    def project(lon: float, lat: float) -> tuple[float, float]:
        x, z = geo.forward(lon, lat)
        return (round(x, 2), round(z, 2))

    spine = np.array([project(lon, lat) for lat, lon in SPINE])
    half = args.corridor_m * scale
    print(f"alan {width} x {height} m (olcek {scale}), koridor yari genisligi {half:.0f} m", flush=True)

    # --- koridor maskesi (4 m) ---
    res_in = 4
    gw, gh = width // res_in + 1, height // res_in + 1
    xs = (np.arange(gw) + 0.5) * res_in
    zs = (np.arange(gh) + 0.5) * res_in
    X, Z = np.meshgrid(xs, zs)
    dist = np.full(X.shape, np.inf, dtype=np.float32)
    for a, b in zip(spine[:-1], spine[1:]):
        ab = b - a
        t = np.clip(((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / max(1e-6, ab @ ab), 0.0, 1.0)
        d = np.hypot(X - (a[0] + t * ab[0]), Z - (a[1] + t * ab[1])).astype(np.float32)
        dist = np.minimum(dist, d)
    del X, Z
    inside = dist <= half
    scenery = dist <= half + SCENERY_M * scale
    print(f"koridor: {inside.mean() * 100:.1f}% kutunun, manzara dahil {scenery.mean() * 100:.1f}%", flush=True)

    def inside_at(x: float, z: float, mask: np.ndarray = scenery) -> bool:
        i, j = int(z // res_in), int(x // res_in)
        return 0 <= i < gh and 0 <= j < gw and bool(mask[i, j])

    # --- kara maskesi (2 m): kiyi cizgisi bariyeri + deniz taskini ---
    res = 2
    lw, lh = width // res + 1, height // res + 1
    barrier = np.zeros((lh, lw), dtype=bool)
    coast = [f for f in raw["features"] if f["kind"] == "coastline"]
    for f in coast:
        pts = [project(lon, lat) for lon, lat in f["points"]]
        for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
            steps = int(max(abs(x1 - x0), abs(z1 - z0)) / res * 2) + 1
            for s in range(steps + 1):
                t = s / steps
                x = int((x0 + (x1 - x0) * t) / res)
                z = int((z0 + (z1 - z0) * t) / res)
                if 0 <= x < lw and 0 <= z < lh:
                    barrier[z, x] = True
                    if x + 1 < lw:
                        barrier[z, x + 1] = True
    # DENIZ TESPITI: bagli bolge etiketleme + oylama (bkz. v2 aciklamasi:
    # OSM kurali kara solda / deniz sagda; en az 5 tohumun oyladigi ve bilinen
    # kara noktasi icermeyen bolgeler denizdir).
    labels = np.zeros(barrier.shape, dtype=np.int32)
    votes: dict[int, int] = {}
    next_label = 1

    def flood(sx: int, sz: int, label: int) -> None:
        stack = [(sx, sz)]
        while stack:
            x, z = stack.pop()
            if not (0 <= x < lw and 0 <= z < lh) or labels[z, x] or barrier[z, x]:
                continue
            row_b = barrier[z]
            row_l = labels[z]
            left = x
            while left > 0 and not row_b[left - 1] and not row_l[left - 1]:
                left -= 1
            right = x
            while right < lw - 1 and not row_b[right + 1] and not row_l[right + 1]:
                right += 1
            labels[z, left:right + 1] = label
            for nz in (z - 1, z + 1):
                if 0 <= nz < lh:
                    open_cells = np.flatnonzero(~barrier[nz, left:right + 1] & (labels[nz, left:right + 1] == 0))
                    if open_cells.size:
                        breaks = np.flatnonzero(np.diff(open_cells) > 1)
                        starts = np.concatenate(([open_cells[0]], open_cells[breaks + 1]))
                        stack.extend((left + int(s), nz) for s in starts)

    for f in coast:
        pts = [project(lon, lat) for lon, lat in f["points"]]
        for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
            dx, dz = x1 - x0, z1 - z0
            length = math.hypot(dx, dz)
            if length < 8.0:
                continue
            nx, nz = -dz / length, dx / length
            cx, cz = int(((x0 + x1) / 2 + nx * 3.0) / res), int(((z0 + z1) / 2 + nz * 3.0) / res)
            if not (0 <= cx < lw and 0 <= cz < lh) or barrier[cz, cx]:
                continue
            if labels[cz, cx] == 0:
                flood(cx, cz, next_label)
                next_label += 1
            votes[int(labels[cz, cx])] = votes.get(int(labels[cz, cx]), 0) + 1
    known_land = [(40.9895, 29.0270), (41.0430, 29.0070), (40.9600, 29.0950), (41.0255, 29.0170),
                  (40.9300, 29.1350), (40.9760, 29.0550)]
    land_labels = set()
    for lat, lon in known_land:
        x, z = project(lon, lat)
        cx, cz = int(x / res), int(z / res)
        if 0 <= cx < lw and 0 <= cz < lh:
            if labels[cz, cx] == 0 and not barrier[cz, cx]:
                flood(cx, cz, next_label)
                next_label += 1
            land_labels.add(int(labels[cz, cx]))
    sea_labels = [label for label, count in votes.items() if count >= 5 and label not in land_labels]
    print(f"bolge: {next_label - 1}, deniz oylanan: {len(sea_labels)}", flush=True)
    sea = np.isin(labels, sea_labels)
    del labels
    land = ~sea
    print(f"deniz: {sea.mean() * 100:.1f}%", flush=True)
    checks = []
    for label, lat, lon, expect_land in (("Kadikoy carsi", 40.9895, 29.0270, True), ("Besiktas", 41.0430, 29.0070, True),
                                         ("Bostanci", 40.9600, 29.0950, True), ("Uskudar", 41.0255, 29.0170, True),
                                         ("Bogaz (kopru alti)", 41.0460, 29.0340, False), ("Marmara", 40.9400, 29.0700, False)):
        x, z = project(lon, lat)
        value = bool(land[min(lh - 1, int(z / res)), min(lw - 1, int(x / res))])
        status = "OK" if value == expect_land else "HATA"
        checks.append({"place": label, "expected_land": expect_land, "land": value, "ok": value == expect_land})
        print(f"  {status} {label}: {'kara' if value else 'deniz'}")

    # --- arazi (4 m, yarim metre): kiyiya uzaklik (TAHMIN; OSM'de DEM yok) ---
    land4 = land[::2, ::2][:gh, :gw]
    if land4.shape != (gh, gw):
        padded = np.ones((gh, gw), dtype=bool)
        padded[:land4.shape[0], :land4.shape[1]] = land4
        land4 = padded
    far = wavefront_distance(~land4, float(res_in), 280.0)
    terrain = np.clip(2 + np.floor(far / 10.0), 2, 28).astype(np.uint8)
    terrain[~land4] = 0

    def terrain_at(x: float, z: float) -> int:
        i, j = min(gh - 1, max(0, int(z // res_in))), min(gw - 1, max(0, int(x // res_in)))
        return int(terrain[i, j])

    # --- ozellikler ---
    table = load_classes()
    buildings, parts, roads, areas, pois, bridges = [], [], [], [], [], []
    source_buildings: dict[str, dict] = {}     # kimlik -> {area_m2, reason}
    tunnels = 0
    for f in raw["features"]:
        kind, tags = f["kind"], f["tags"]
        pts = [project(lon, lat) for lon, lat in f["points"]]
        if kind == "poi":
            if inside_at(*pts[0]):
                pois.append({"p": pts[0], "tags": tags})
            continue
        if kind == "road" and tags.get("bridge") not in (None, "no") and MAJOR_BRIDGE in tags.get("name", ""):
            bridges.append({"name": tags.get("name"), "pts": pts, "layer": tags.get("layer", "1")})
            continue
        if kind in ("building", "building_part"):
            if len(pts) < 3:
                continue
            area = polygon_area(pts)
            cx = sum(p[0] for p in pts) / len(pts)
            cz = sum(p[1] for p in pts) / len(pts)
            holes = [[project(lon, lat) for lon, lat in hole] for hole in f.get("holes", [])]
            if kind == "building_part":
                if inside_at(cx, cz):
                    parts.append({"id": f["id"], "tags": tags, "poly": pts, "c": (cx, cz)})
                continue
            if not inside_at(cx, cz):
                continue           # koridor + manzara serididisi: kaynak kumesinde de yok
            src_area = ring_area_m2(f["points"]) - sum(ring_area_m2(h) for h in f.get("holes", []))
            entry = {"area_m2": round(src_area, 1), "reason": ""}
            source_buildings[f["id"]] = entry
            if area < 6.0 * scale * scale:
                entry["reason"] = "ayak izi 6 m2'den kucuk (kulube/pano)"
                continue
            buildings.append({"osm": f["id"], "tags": tags, "poly": pts, "holes": holes,
                              "centroid": (cx, cz), "src_area": src_area})
            continue
        if not any(inside_at(x, z) for x, z in pts):
            continue
        if kind == "road":
            highway = tags.get("highway", "")
            if highway not in ROADS:
                continue
            if tags.get("tunnel") in ("yes", "building_passage", "culvert"):
                tunnels += 1
                continue
            w, sw, surface = ROADS[highway]
            width_tag = number(tags.get("width"))
            lanes = number(tags.get("lanes"))
            if width_tag and 2.0 <= width_tag <= 40.0:
                w = width_tag
            elif lanes and highway in ("primary", "secondary", "trunk", "tertiary", "motorway"):
                w = max(w, min(24.0, lanes * 3.2))
            layer = tags.get("layer", "0")
            roads.append({"id": f["id"], "type": highway, "w": round(float(w), 1), "sw": sw, "surface": surface,
                          "pts": pts, "src": f["points"], "bridge": tags.get("bridge") not in (None, "no"),
                          "layer": int(layer) if str(layer).lstrip("-").isdigit() else 0, "name": tags.get("name", "")})
        elif kind == "area":
            for (k, v), area_kind in AREA_KINDS.items():
                if tags.get(k) == v:
                    if len(pts) >= 3:
                        areas.append({"kind": area_kind, "poly": pts, "name": tags.get("name", "")})
                    break
    print(f"{len(buildings)} bina, {len(parts)} bina parcasi, {len(roads)} yol, {len(areas)} alan, "
          f"{len(pois)} nokta, {len(bridges)} buyuk kopru yolu", flush=True)

    # --- izgara indeksi (32 m) ---
    for b in buildings:
        b["class"] = classify(b["tags"], table)
        xs_ = [p[0] for p in b["poly"]]
        zs_ = [p[1] for p in b["poly"]]
        b["box"] = (min(xs_), min(zs_), max(xs_), max(zs_))
    grid: dict[tuple[int, int], list[int]] = {}
    for i, b in enumerate(buildings):
        for gx in range(int(b["box"][0] // 32), int(b["box"][2] // 32) + 1):
            for gz in range(int(b["box"][1] // 32), int(b["box"][3] // 32) + 1):
                grid.setdefault((gx, gz), []).append(i)

    def building_containing(x: float, z: float) -> int:
        for i in grid.get((int(x // 32), int(z // 32)), []):
            b = buildings[i]
            x0, z0, x1, z1 = b["box"]
            if x0 <= x <= x1 and z0 <= z <= z1 and point_in_polygon(x, z, b["poly"]) \
                    and not any(point_in_polygon(x, z, hole) for hole in b["holes"]):
                return i
        return -1

    # Dukkan noktalari -> bina (zemin kat isletmesi; ust katlar konut kalabilir).
    assigned = 0
    for poi in pois:
        cls = classify(poi["tags"], table)
        if not cls:
            continue
        i = building_containing(*poi["p"])
        if i >= 0:
            b = buildings[i]
            b.setdefault("ground_uses", [])
            if cls not in b["ground_uses"]:
                b["ground_uses"].append(cls)
            if b["class"] in ("", "residential", "civic"):
                b["class"] = cls
                b.setdefault("shop_name", poi["tags"].get("name", ""))
                assigned += 1

    # Bina parcalari -> ust bina.
    orphan_parts = []
    for part in parts:
        i = building_containing(*part["c"])
        if i < 0:
            orphan_parts.append(part["id"])
            continue
        buildings[i].setdefault("parts", []).append(part)

    # --- kat sayisi: kaynak olcu > parca > komsuluk > sinif tahmini ---
    def measured_levels(tags: dict) -> tuple[int | None, str, dict]:
        conflict = {}
        levels = number(tags.get("building:levels"))
        h = number(tags.get("height"))
        roof_h = number(tags.get("roof:height")) or 0.0
        if levels is not None and levels >= 1:
            count = int(round(levels))
            if h is not None and count > 0:
                per = (h - roof_h) / count
                if per < 2.2 or per > 5.0:
                    conflict = {"height": h, "levels": count, "per_level_m": round(per, 2),
                                "policy": "kat sayisi (building:levels) esas alindi; yukseklik raporlandi"}
            return count, "osm_levels", conflict
        if h is not None and h > 0:
            return max(1, int(round((h - roof_h) / FLOOR_M))), "osm_height", conflict
        return None, "", conflict

    conflicts = []
    known_grid: dict[tuple[int, int], list[int]] = {}
    for b in buildings:
        levels, source, conflict = measured_levels(b["tags"])
        if levels is None and b.get("parts"):
            part_levels = [measured_levels(p["tags"])[0] for p in b["parts"]]
            part_levels = [lv for lv in part_levels if lv]
            if part_levels:
                levels, source = max(part_levels), "osm_parts"
        if conflict:
            conflicts.append({"id": b["osm"], **conflict})
        b["levels"] = min(40, levels) if levels else None
        b["height_source"] = source
        if levels:
            cx, cz = b["centroid"]
            known_grid.setdefault((int(cx // 100), int(cz // 100)), []).append(b["levels"])
    for b in buildings:
        if b["levels"] is not None:
            b["height_conf"] = "high"
            continue
        seed = (int(b["osm"].lstrip("wr").split("#")[0]) * 2654435761) & 0xFFFF
        cx, cz = b["centroid"]
        near = []
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                near.extend(known_grid.get((int(cx // 100) + dx, int(cz // 100) + dz), []))
        cls = b["class"] or "residential"
        if len(near) >= 4 and cls in ("residential", "market", "pharmacy", "electronics", "civic"):
            near.sort()
            median = near[len(near) // 2]
            b["levels"] = max(1, min(30, median + (seed % 3) - 1))
            b["height_source"] = "neighbours"
            b["height_conf"] = "medium"
        else:
            base = CLASS_BASE_LEVELS.get(cls, 4)
            b["levels"] = max(1, base + (seed % 3) - 1)
            b["height_source"] = "class_estimate"
            b["height_conf"] = "low"

    out_buildings = []
    for b in buildings:
        tags = b["tags"]
        x0, z0, x1, z1 = b["box"]
        base_half = min(terrain_at(x, z) for x, z in b["poly"] + [((x0 + x1) / 2, (z0 + z1) / 2)])
        entry = {
            "id": b["osm"], "class": b["class"] or "residential", "levels": b["levels"],
            "est": b["height_source"] in ("neighbours", "class_estimate"),
            "height_source": b["height_source"], "height_conf": b["height_conf"],
            "poly": b["poly"], "base_half": max(2, base_half), "name": tags.get("name", b.get("shop_name", "")),
            "roof": tags.get("roof:shape", ""), "historic": "historic" in tags,
        }
        if b["holes"]:
            entry["holes"] = b["holes"]
        if b.get("ground_uses"):
            entry["ground_uses"] = b["ground_uses"]
        if b.get("parts"):
            entry["parts"] = len(b["parts"])
        min_level = number(tags.get("building:min_level"))
        if min_level:
            entry["min_level"] = int(min_level)
        out_buildings.append(entry)

    # --- koridor siniri bina ve sokak kesmesin ---
    # Omurgaya uzaklik bandi sokaklari ve binalari ortasindan kesiyordu
    # (gorunmez duvar bir dairenin icinden gecebiliyordu). Koridora DEGEN her
    # bina ayak izi (+4 m) ve koridordan cikan her yol parcasi (+genislik)
    # butun olarak koridora katilir; sinir bina/sokak aralarindan gecer.
    grown = 0

    def mark_box(x0: float, z0: float, x1: float, z1: float) -> int:
        i0, i1 = max(0, int(z0 // res_in)), min(gh - 1, int(z1 // res_in))
        j0, j1 = max(0, int(x0 // res_in)), min(gw - 1, int(x1 // res_in))
        if i1 < i0 or j1 < j0:
            return 0
        block = inside[i0:i1 + 1, j0:j1 + 1]
        added = int((~block).sum())
        inside[i0:i1 + 1, j0:j1 + 1] = True
        return added

    for b in out_buildings:
        xs_ = [p[0] for p in b["poly"]]
        zs_ = [p[1] for p in b["poly"]]
        x0, z0, x1, z1 = min(xs_) - 4, min(zs_) - 4, max(xs_) + 4, max(zs_) + 4
        i0, i1 = max(0, int(z0 // res_in)), min(gh - 1, int(z1 // res_in))
        j0, j1 = max(0, int(x0 // res_in)), min(gw - 1, int(x1 // res_in))
        if i1 >= i0 and j1 >= j0 and inside[i0:i1 + 1, j0:j1 + 1].any() and not inside[i0:i1 + 1, j0:j1 + 1].all():
            grown += mark_box(x0, z0, x1, z1)
    for road in roads:
        pad = road["w"] / 2 + road["sw"] + 2
        for a, c in zip(road["pts"], road["pts"][1:]):
            ina = inside_at(a[0], a[1], inside)
            inc = inside_at(c[0], c[1], inside)
            if ina != inc and math.dist(a, c) < 80.0:
                steps = max(1, int(math.dist(a, c) / 2))
                for s in range(steps + 1):
                    px = a[0] + (c[0] - a[0]) * s / steps
                    pz = a[1] + (c[1] - a[1]) * s / steps
                    grown += mark_box(px - pad, pz - pad, px + pad, pz + pad)
    # Yeni katilan alan manzara maskesinde de olmali (uretilsin).
    scenery |= inside
    print(f"koridor siniri bina/sokak butunlugu icin {grown * res_in * res_in / 1e4:.1f} ha genisletildi", flush=True)

    # --- buyuk kopru: iki yon yolunun ORTA HATTI + kule konumlari ---
    decks = []
    if bridges:
        a = bridges[0]["pts"]
        mid = resample(a, 41)
        if len(bridges) >= 2:
            b = bridges[1]["pts"]
            if math.dist(b[0], a[0]) > math.dist(b[-1], a[0]):
                b = b[::-1]
            mid = (mid + resample(b, 41)) / 2.0
        length = float(np.hypot(*(mid[1:] - mid[:-1]).T).sum())
        samples = resample(mid.tolist(), int(length) + 1)
        wet = [not land[min(lh - 1, int(z / res)), min(lw - 1, int(x / res))] for x, z in samples]
        if any(wet):
            step = length / (len(samples) - 1)
            first = wet.index(True) * step
            last = (len(wet) - 1 - wet[::-1].index(True)) * step
            towers = [max(10.0, first - 3.0), min(length - 10.0, last + 3.0)]
            decks.append({"name": bridges[0]["name"], "pts": [[round(float(x), 2), round(float(z), 2)] for x, z in mid],
                          "half": round(BRIDGE_DECK_WIDTH * 0.5 * scale, 2), "length": round(length, 2),
                          "towers": [round(t, 1) for t in towers],
                          "end_half": [terrain_at(*mid[0]), terrain_at(*mid[-1])]})
            print(f"kopru: {length:.0f} m, kuleler {towers[0]:.0f} / {towers[1]:.0f} m, ana aciklik {towers[1] - towers[0]:.0f} m")

    # --- harita ekrani goruntusu ---
    mw, mh = int(math.ceil(width / MAP_RES)), int(math.ceil(height / MAP_RES))
    raster = Raster(mw, mh)
    step_land = MAP_RES // res

    def fit(src: np.ndarray, fill) -> np.ndarray:
        out = np.full((mh, mw), fill, dtype=src.dtype)
        part = src[:mh, :mw]
        out[:part.shape[0], :part.shape[1]] = part
        return out

    land_m = fit(land[::step_land, ::step_land], False)
    terrain_m = fit(terrain, 0).astype(np.float32)
    inside_m = fit(inside, False)
    raster.img[:] = np.array([0.32, 0.31, 0.29], dtype=np.float32) * (1.0 + (terrain_m - 6.0) * 0.012)[..., None]
    area_colors = {"park": (0.26, 0.42, 0.22), "grass": (0.3, 0.44, 0.24), "pitch": (0.28, 0.46, 0.26),
                   "forest": (0.2, 0.34, 0.18), "cemetery": (0.3, 0.38, 0.28), "plaza": (0.46, 0.44, 0.41),
                   "parking": (0.3, 0.3, 0.32), "construction": (0.42, 0.34, 0.26), "water": (0.14, 0.26, 0.36)}
    for area in areas:
        if area["kind"] in area_colors:
            raster.polygon(area["poly"], area_colors[area["kind"]])
    class_colors = {k: tuple(c / 255.0 for c in v["color"]) for k, v in
                    json.loads((ROOT / "data" / "world" / "building_classes.json").read_text(encoding="utf-8")).items()
                    if isinstance(v, dict) and "color" in v}
    for b in out_buildings:
        raster.polygon(b["poly"], class_colors.get(b["class"], (0.45, 0.42, 0.4)))
        for hole in b.get("holes", []):
            raster.polygon(hole, (0.36, 0.35, 0.33))
    for road in roads:
        if road["sw"] > 0:
            for p, q in zip(road["pts"], road["pts"][1:]):
                raster.stroke(p, q, road["w"] / 2 + road["sw"], (0.55, 0.53, 0.5))
    for road in roads:
        color = (0.2, 0.2, 0.22) if road["surface"] == "asphalt" else (0.42, 0.4, 0.37)
        for p, q in zip(road["pts"], road["pts"][1:]):
            raster.stroke(p, q, road["w"] / 2, color)
    raster.img[~land_m] = (0.14, 0.26, 0.36)
    for area in areas:
        if area["kind"] == "pier":
            raster.polygon(area["poly"], (0.48, 0.36, 0.24))
    for deck in decks:
        for p, q in zip(deck["pts"], deck["pts"][1:]):
            raster.stroke(p, q, deck["half"], (0.64, 0.64, 0.66))
    raster.img[~inside_m] *= 0.45           # girilemeyen bolge soluk
    map_png = png_base64((np.clip(raster.img, 0.0, 1.0) * 255).astype(np.uint8))

    named = [{"name": p["tags"]["name"], "p": p["p"], "kind": p["tags"].get("amenity") or p["tags"].get("historic")
              or p["tags"].get("tourism") or p["tags"].get("shop")} for p in pois
             if p["tags"].get("name") and any(k in p["tags"] for k in ("amenity", "historic", "tourism", "shop"))]
    # --- su noktalari (hayatta kalma): OSM cesme/icme suyu, cami sadirvani,
    # suyu olmayan buyuk parka el pompasi. Hepsi KIRLI su verir (sehir
    # sebekesi aritmiyor); aritma oyuncunun isidir.
    water_points = []
    for p in pois:
        t = p["tags"]
        kind = ""
        if t.get("amenity") == "drinking_water":
            kind = "icme_suyu"
        elif t.get("amenity") in ("fountain", "water_point") or t.get("historic") in ("fountain", "sebil"):
            kind = "cesme"
        if kind and inside_at(*p["p"], inside):
            water_points.append({"p": p["p"], "kind": kind, "name": t.get("name", ""), "src": "osm"})
    for b in out_buildings:
        if b["class"] == "religious":
            # Sadirvan caminin DISINDA, bir cephenin 2.5 m onunde (harita
            # adiminda bulunur; oyunda sutun sutun arama takilma yapiyordu).
            poly = b["poly"]
            spot = None
            area_sign = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                            for i in range(len(poly)))
            best_len = 0.0
            for i in range(len(poly)):
                a, c2 = poly[i], poly[(i + 1) % len(poly)]
                ex, ez = c2[0] - a[0], c2[1] - a[1]
                length = math.hypot(ex, ez)
                if length < 3.0 or length <= best_len:
                    continue
                # Dis normal (halka yonune gore).
                nx, nz = (ez / length, -ex / length) if area_sign > 0 else (-ez / length, ex / length)
                px, pz = (a[0] + c2[0]) / 2 + nx * 2.5, (a[1] + c2[1]) / 2 + nz * 2.5
                if building_containing(px, pz) >= 0 or not inside_at(px, pz, inside):
                    continue
                gi, gj = min(lh - 1, max(0, int(pz / res))), min(lw - 1, max(0, int(px / res)))
                if not land[gi, gj]:
                    continue
                spot, best_len = (px, pz), length
            if spot is not None:
                water_points.append({"p": [round(spot[0], 2), round(spot[1], 2)], "kind": "sadirvan",
                                     "name": b.get("name", ""), "src": "cami", "building": b["id"]})
    for area in areas:
        if area["kind"] != "park" or polygon_area(area["poly"]) < 2500.0:
            continue
        cx = sum(q[0] for q in area["poly"]) / len(area["poly"])
        cz = sum(q[1] for q in area["poly"]) / len(area["poly"])
        if not inside_at(cx, cz, inside) or not point_in_polygon(cx, cz, area["poly"]):
            continue
        if any(math.dist((cx, cz), w["p"]) < 250.0 for w in water_points):
            continue
        water_points.append({"p": [round(cx, 2), round(cz, 2)], "kind": "el_pompasi", "name": area.get("name", ""),
                             "src": "park"})
    print(f"su noktasi: {len(water_points)} "
          f"({sum(1 for w in water_points if w['src'] == 'osm')} OSM, "
          f"{sum(1 for w in water_points if w['src'] == 'cami')} sadirvan, "
          f"{sum(1 for w in water_points if w['src'] == 'park')} park pompasi)", flush=True)

    spawn = list(project(args.spawn[1], args.spawn[0]))
    counts: dict[str, int] = {}
    for b in out_buildings:
        counts[b["class"]] = counts.get(b["class"], 0) + 1
    road_out = [{k: v for k, v in r.items() if k not in ("src", "id")} for r in roads]
    result = {
        "map_id": args.id, "name": args.name, "format": MAP_FORMAT,
        "scale": scale, "transform": geo.to_dict(),
        "center": {"lat": (min_lat + max_lat) / 2, "lon": lon0},
        "bbox": {"min_lat": min_lat, "max_lat": max_lat, "min_lon": min_lon, "max_lon": max_lon},
        "size": [width, height], "license": "Harita verisi (c) OpenStreetMap katkicilari, ODbL 1.0",
        "source": {"file": raw.get("source"), "sha256": raw.get("source_sha256"),
                   "extractor_version": raw.get("extractor_version")},
        "height_estimated": True,
        "land_res": res, "land_rle": rle_rows(land),
        "inside_res": res_in, "inside_rle": rle_rows(inside),
        "terrain_res": res_in, "terrain_size": [gw, gh], "terrain_grid": pack(terrain),
        "buildings": out_buildings, "roads": road_out, "areas": areas, "pois": named, "bridges": bridges,
        "bridge_decks": decks, "map_image": {"res": MAP_RES, "png": map_png},
        "spine": spine.tolist(), "spawn": spawn, "water_points": water_points, "places": {k: list(project(v[1], v[0])) for k, v in PLACES.items()},
        "stats": {"buildings": len(out_buildings), "classes": counts, "roads": len(roads), "areas": len(areas),
                  "pois_assigned": assigned, "sea_fraction": round(float(sea.mean()), 3), "bridges": len(bridges),
                  "corridor_fraction": round(float(inside.mean()), 3), "map_png_kb": len(map_png) * 3 // 4 // 1024},
    }
    out = ROOT / "data" / "map" / f"{args.id}.json"
    out.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{out} ({out.stat().st_size / 1e6:.1f} MB) -- {result['stats']}", flush=True)

    write_report(args, raw, geo, out_buildings, source_buildings, buildings, roads, decks, conflicts, orphan_parts,
                 tunnels, checks, inside, res_in, width, height, time.time() - started)
    return 0


# ---------------------------------------------------------------------------
# Dogrulama raporu
# ---------------------------------------------------------------------------
def road_graph(roads: list, allowed) -> tuple[dict, dict]:
    """Dugum = kaynak koordinat (7 hane). Kenar: (kaynak m, oyun m)."""
    graph: dict[tuple, list] = {}
    game_pos: dict[tuple, tuple] = {}
    for road in roads:
        if not allowed(road):
            continue
        for (a, b), (ga, gb) in zip(zip(road["src"], road["src"][1:]), zip(road["pts"], road["pts"][1:])):
            ka, kb = tuple(a), tuple(b)
            src_len = haversine(a[0], a[1], b[0], b[1])
            game_len = math.dist(ga, gb)
            graph.setdefault(ka, []).append((kb, src_len, game_len))
            graph.setdefault(kb, []).append((ka, src_len, game_len))
            game_pos[ka] = tuple(ga)
            game_pos[kb] = tuple(gb)
    return graph, game_pos


def components(graph: dict) -> list:
    seen, comps = set(), []
    for start in graph:
        if start in seen:
            continue
        stack, comp = [start], []
        seen.add(start)
        while stack:
            node = stack.pop()
            comp.append(node)
            for nxt, _, _ in graph[node]:
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        comps.append(comp)
    comps.sort(key=len, reverse=True)
    return comps


def shortest(graph: dict, start, goal) -> tuple[float, float]:
    """Kaynak metre uzerinden Dijkstra; ayni yolun oyun uzunlugu da doner."""
    best = {start: 0.0}
    game = {start: 0.0}
    heap = [(0.0, start)]
    while heap:
        d, node = heapq.heappop(heap)
        if node == goal:
            return d, game[node]
        if d > best.get(node, math.inf):
            continue
        for nxt, src_len, game_len in graph[node]:
            nd = d + src_len
            if nd < best.get(nxt, math.inf):
                best[nxt] = nd
                game[nxt] = game[node] + game_len
                heapq.heappush(heap, (nd, nxt))
    return math.inf, math.inf


def nearest_node(nodes, lon: float, lat: float):
    return min(nodes, key=lambda n: haversine(lon, lat, n[0], n[1]))


def write_report(args, raw, geo, out_buildings, source_buildings, buildings, roads, decks, conflicts, orphan_parts,
                 tunnels, checks, inside, res_in, width, height, seconds) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    out_ids = {b["id"] for b in out_buildings}
    accepted = {k for k, v in source_buildings.items() if not v["reason"]}
    missing = sorted(accepted - out_ids)
    extra = sorted(out_ids - set(source_buildings))
    reasons: dict[str, int] = {}
    for info in source_buildings.values():
        if info["reason"]:
            reasons[info["reason"]] = reasons.get(info["reason"], 0) + 1

    # 250 m hucreler (yalnizca girilebilir koridor): kaynak alani (yerel
    # izdusum, halka enleminde) ile oyun alani (ayak izi - avlu).
    cells: dict[tuple[int, int], dict] = {}
    for b in buildings:
        cx, cz = b["centroid"]
        i, j = int(cz // res_in), int(cx // res_in)
        if not (0 <= i < inside.shape[0] and 0 <= j < inside.shape[1] and inside[i, j]):
            continue
        key = (int(cx // 250), int(cz // 250))
        cell = cells.setdefault(key, {"n_src": 0, "n_out": 0, "area_src": 0.0, "area_out": 0.0})
        cell["n_src"] += 1
        cell["area_src"] += b["src_area"]
        if b["osm"] in out_ids:
            cell["n_out"] += 1
            cell["area_out"] += polygon_area(b["poly"]) - sum(polygon_area(h) for h in b["holes"])
    worst = 0.0
    for cell in cells.values():
        if cell["area_src"] > 0:
            cell["area_diff_pct"] = round(abs(cell["area_out"] - cell["area_src"]) / cell["area_src"] * 100, 3)
            worst = max(worst, cell["area_diff_pct"])
        cell["area_src"] = round(cell["area_src"])
        cell["area_out"] = round(cell["area_out"])

    # Semtler: en yakin bolge merkezi.
    regions = json.loads((ROOT / "data" / "city" / "regions.json").read_text(encoding="utf-8"))
    district: dict[str, dict] = {}
    for b in buildings:
        lon, lat = geo.inverse(*b["centroid"])
        best = min((rid for rid in regions if "lat" in regions[rid]),
                   key=lambda rid: haversine(lon, lat, regions[rid]["lon"], regions[rid]["lat"]))
        entry = district.setdefault(regions[best]["name"], {"n_src": 0, "n_out": 0, "area_src": 0.0})
        entry["n_src"] += 1
        entry["area_src"] += b["src_area"]
        entry["n_out"] += 1 if b["osm"] in out_ids else 0
    for entry in district.values():
        entry["area_src"] = round(entry["area_src"])

    # Yol agi
    walk_graph, _ = road_graph(roads, lambda r: True)
    drive_graph, _ = road_graph(roads, lambda r: r["type"] in DRIVABLE)
    comps = components(walk_graph)
    src_total = sum(haversine(a[0], a[1], b[0], b[1]) for r in roads for a, b in zip(r["src"], r["src"][1:]))
    game_total = sum(math.dist(a, b) for r in roads for a, b in zip(r["pts"], r["pts"][1:]))

    # Mesafe ciftleri: kus ucusu (haversine) vs oyun koordinati.
    pairs = []
    for a, b in DISTANCE_PAIRS:
        (la, oa), (lb, ob) = PLACES[a], PLACES[b]
        real = haversine(oa, la, ob, lb)
        game = math.dist(geo.forward(oa, la), geo.forward(ob, lb))
        # Ters donusum dogrulamasi (yuvarlama hatasi).
        back = geo.inverse(*geo.forward(oa, la))
        pairs.append({"from": a, "to": b, "real_m": round(real, 1), "game_m": round(game, 1),
                      "error_pct": round(abs(game - real) / real * 100, 3),
                      "inverse_error_m": round(haversine(oa, la, back[0], back[1]), 4)})

    # Kadikoy -> Bostanci rota (en buyuk bilesende).
    routes = {}
    for label, graph in (("yuruyus", walk_graph), ("surus", drive_graph)):
        comp = set(components(graph)[0]) if graph else set()
        if not comp:
            continue
        la, oa = PLACES["Kadikoy iskele meydani"]
        lb, ob = PLACES["Bostanci sahil"]
        start = nearest_node(comp, oa, la)
        goal = nearest_node(comp, ob, lb)
        src_len, game_len = shortest(graph, start, goal)
        routes[label] = {"start": list(start), "goal": list(goal),
                         "start_snap_m": round(haversine(oa, la, start[0], start[1]), 1),
                         "goal_snap_m": round(haversine(ob, lb, goal[0], goal[1]), 1),
                         "source_m": round(src_len, 1), "game_m": round(game_len, 1),
                         "diff_pct": round(abs(game_len - src_len) / max(1.0, src_len) * 100, 3)}

    levels_hist: dict[int, int] = {}
    sources: dict[str, int] = {}
    tall = []
    for b in out_buildings:
        levels_hist[b["levels"]] = levels_hist.get(b["levels"], 0) + 1
        sources[b["height_source"]] = sources.get(b["height_source"], 0) + 1
        # Oyun kat yuksekligi 4 m (1 m doseme + 3 m net tavan).
        if b["levels"] * 4 + b["base_half"] * 0.5 > 96:
            tall.append({"id": b["id"], "levels": b["levels"], "source": b["height_source"],
                         "top_m": b["levels"] * 4 + b["base_half"] * 0.5})
    report = {
        "generated": time.strftime("%Y-%m-%d %H:%M"), "seconds": round(seconds),
        "source": {"file": raw.get("source"), "sha256": raw.get("source_sha256"),
                   "extractor_version": raw.get("extractor_version"), "bbox": raw.get("bbox")},
        "map": {"id": args.id, "format": MAP_FORMAT, "size_m": [width, height], "transform": geo.to_dict(),
                "corridor_half_m": args.corridor_m, "scenery_m": SCENERY_M},
        "land_checks": checks,
        "buildings": {"source_in_scope": len(source_buildings), "accepted": len(accepted), "output": len(out_ids),
                      "missing_from_output": missing[:200], "missing_count": len(missing),
                      "unexpected_in_output": extra[:200], "excluded_by_reason": reasons,
                      "with_courtyard": sum(1 for b in out_buildings if b.get("holes")),
                      "from_relations": sum(1 for b in out_buildings if b["id"].startswith("r")),
                      "with_parts": sum(1 for b in out_buildings if b.get("parts")),
                      "orphan_parts": len(orphan_parts)},
        "cells_250m": {"count": len(cells), "worst_area_diff_pct": worst,
                       "cells": [{"cell": list(k), **v} for k, v in sorted(cells.items())]},
        "districts": district,
        "heights": {"sources": sources, "levels_histogram": dict(sorted(levels_hist.items())),
                    "conflicts": conflicts[:100], "conflict_count": len(conflicts),
                    "above_96m": tall[:50], "above_96m_count": len(tall),
                    "policy": "building:levels > height/3 m > building:part > komsu olculu binalarin medyani (+-1) > "
                              "sinif tabani (+-1). roof:height kat sayisina eklenmez."},
        "roads": {"segments_source_m": round(src_total), "segments_game_m": round(game_total),
                  "length_diff_pct": round(abs(game_total - src_total) / max(1.0, src_total) * 100, 3),
                  "components": len(comps), "largest_component_nodes": len(comps[0]) if comps else 0,
                  "small_components": sum(1 for c in comps if len(c) < 10),
                  "bridges_small": sum(1 for r in roads if r["bridge"]), "tunnels_skipped": tunnels,
                  "major_bridge_deck": decks[0]["length"] if decks else None},
        "distance_pairs": pairs, "kadikoy_bostanci_route": routes,
    }
    (REPORT_DIR / "harita_raporu.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    lines = [
        f"# Harita dogrulama raporu ({report['generated']})", "",
        f"Kaynak: `{raw.get('source')}` SHA-256 `{raw.get('source_sha256')}`, cikarici v{raw.get('extractor_version')}.",
        f"Harita: {width} x {height} m, olcek {geo.scale}, donusum v{geo.version}.", "",
        "## Binalar", "",
        f"- Kapsamdaki kaynak bina: {len(source_buildings)}; kabul: {len(accepted)}; ciktida: {len(out_ids)}; "
        f"ciktida eksik: {len(missing)}; beklenmeyen: {len(extra)}.",
        f"- Eleme gerekceleri: {reasons}.",
        f"- Avlulu: {report['buildings']['with_courtyard']}, relation kaynakli: {report['buildings']['from_relations']}, "
        f"parcali: {report['buildings']['with_parts']}.",
        f"- 250 m hucre: {len(cells)} hucre, en kotu alan farki %{worst}.", "",
        "## Yukseklik", "", f"- Kaynaklar: {sources}.", f"- Celisen etiket: {len(conflicts)}; 96 m ustu: {len(tall)}.", "",
        "## Mesafeler", "", "| Nereden | Nereye | Gercek m | Oyun m | Hata % |", "|---|---|---:|---:|---:|",
    ]
    for p in pairs:
        lines.append(f"| {p['from']} | {p['to']} | {p['real_m']} | {p['game_m']} | {p['error_pct']} |")
    lines += ["", "## Kadikoy -> Bostanci rota", ""]
    for label, r in routes.items():
        lines.append(f"- {label}: kaynak {r['source_m']} m, oyun {r['game_m']} m, fark %{r['diff_pct']} "
                     f"(baslangic {r['start_snap_m']} m, bitis {r['goal_snap_m']} m yola baglandi).")
    lines += ["", f"Yol agi: {report['roads']}"]
    (REPORT_DIR / "harita_raporu.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"rapor: {REPORT_DIR / 'harita_raporu.md'}")


if __name__ == "__main__":
    sys.exit(main())
