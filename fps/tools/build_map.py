"""Ham OSM onbellegi -> oyun haritasi (fps/data/map/<id>.json).

YALNIZCA GELISTIRME ARACIDIR; oyun calisirken bu betige ihtiyac duymaz.

SIKISTIRILMIS OLCEK (belgenin 7. bolumu)
    Gercek cografi iliskiler (kiyi, sokak dizilimi, meydanlar) KORUNUR ama
    konumlar `scale` ile kucultulur: 0.75 -> 1 oyun metresi = 1.33 gercek
    metre. Sokak GENISLIKLERI olceklenmez; yol tipine gore FPS'te okunur
    sabit genislik alir (ara sokak 7 m + kaldirim). Bina YUKSEKLIKLERI de
    olceklenmez (kat x 3 m). Oran haritaya yazilir: OSM metresi ile oyun
    metresi arasindaki donusum kayitlidir.

VERI OLMAYAN SEYLER TAHMINDIR ve oyle isaretlenir:
    * `building:levels` yoksa kat sayisi sinif + tohumdan tahmin edilir
      (`est: true`).
    * OSM'de yukseklik modeli (DEM) yoktur; arazi egimi kiyiya uzakliktan
      TAHMIN edilir (`height_estimated: true`).

Kullanim:
    python fps/tools/build_map.py --id kadikoy --center 40.9895 29.0258 --real-size 400 --scale 0.75
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import sys
import zlib
from collections import deque
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path(__file__).parent / "cache" / "osm_raw.json"
GENERATOR_VERSION = 3

# Oyun metresi: yol tipi -> (asfalt genisligi, kaldirim genisligi, zemin)
ROADS = {
    "motorway": (16, 0, "asphalt"), "trunk": (14, 2, "asphalt"), "primary": (12, 2.5, "asphalt"),
    "secondary": (10, 2, "asphalt"), "tertiary": (9, 2, "asphalt"),
    "motorway_link": (8, 0, "asphalt"), "trunk_link": (8, 0, "asphalt"),
    "primary_link": (8, 1.5, "asphalt"), "secondary_link": (8, 1.5, "asphalt"),
    "tertiary_link": (7, 1.5, "asphalt"),
    "unclassified": (7, 1.5, "asphalt"), "residential": (7, 1.5, "asphalt"),
    "living_street": (6, 1, "cobblestone"), "service": (5, 0, "asphalt"),
    "pedestrian": (7, 0, "cobblestone"), "footway": (3, 0, "cobblestone"),
    "path": (2.5, 0, "cobblestone"), "cycleway": (3, 0, "asphalt"), "steps": (3, 0, "cobblestone"),
}
AREA_KINDS = {
    ("leisure", "park"): "park", ("leisure", "garden"): "park", ("landuse", "grass"): "grass",
    ("landuse", "recreation_ground"): "park", ("landuse", "cemetery"): "cemetery",
    ("amenity", "grave_yard"): "cemetery", ("natural", "wood"): "forest",
    ("landuse", "forest"): "forest", ("natural", "scrub"): "grass",
    ("natural", "water"): "water", ("landuse", "reservoir"): "water",
    ("amenity", "parking"): "parking", ("man_made", "pier"): "pier",
    ("leisure", "pitch"): "pitch", ("place", "square"): "plaza", ("highway", "pedestrian"): "plaza",
    ("landuse", "construction"): "construction",
}


def load_classes() -> dict[str, str]:
    """building_classes.json'daki osm_tags -> sinif (oyunla AYNI tablo)."""
    data = json.loads((ROOT / "data" / "world" / "building_classes.json").read_text(encoding="utf-8"))
    table = {}
    for class_id, entry in data.items():
        for tag in entry.get("osm_tags", []):
            table[tag] = class_id
    return table


def classify(tags: dict, table: dict[str, str]) -> str:
    # Ozel etiketler building=* etiketinden ONCELIKLIDIR (Python ile ayni sira).
    for key in ("military", "amenity", "shop", "craft", "healthcare", "office", "man_made"):
        value = tags.get(key)
        if value is not None and f"{key}={value}" in table:
            return table[f"{key}={value}"]
    for key in ("building", "landuse", "abandoned"):
        value = tags.get(key)
        if value is not None and f"{key}={value}" in table:
            return table[f"{key}={value}"]
    return ""


def point_in_polygon(x: float, z: float, poly: list) -> bool:
    inside = False
    count = len(poly)
    j = count - 1
    for i in range(count):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / ((zj - zi) or 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def polygon_area(poly: list) -> float:
    return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                   for i in range(len(poly)))) * 0.5


def main() -> int:
    parser = argparse.ArgumentParser(description="OSM onbellegi -> oyun haritasi")
    parser.add_argument("--id", required=True)
    parser.add_argument("--name", default="")
    parser.add_argument("--center", type=float, nargs=2, required=True, metavar=("LAT", "LON"))
    parser.add_argument("--real-size", type=float, nargs="+", required=True,
                        help="gercek metre: tek deger kare, iki deger genislik yukseklik")
    parser.add_argument("--scale", type=float, default=0.75)
    parser.add_argument("--spawn", type=float, nargs=2, metavar=("LAT", "LON"))
    parser.add_argument("--sea-seed", type=float, nargs=2, action="append", metavar=("LAT", "LON"),
                        help="denizde oldugu bilinen nokta (birden fazla verilebilir)")
    parser.add_argument("--cache", type=Path, default=CACHE)
    args = parser.parse_args()

    raw = json.loads(args.cache.read_text(encoding="utf-8"))
    lat0, lon0 = args.center
    real_w = args.real_size[0]
    real_h = args.real_size[1] if len(args.real_size) > 1 else real_w
    scale = args.scale
    width = int(round(real_w * scale))
    height = int(round(real_h * scale))
    sys.path.insert(0, str(Path(__file__).parent))
    from geo import GeoTransform
    probe = GeoTransform(lon0, lat0, lat0, scale)
    geo = GeoTransform(lon0 - (width / 2.0) / (probe.m_lon * scale), lat0 + (height / 2.0) / (probe.m_lat * scale),
                       lat0, scale)

    def project(lon: float, lat: float) -> tuple[float, float]:
        # Oyun: x dogu, z GUNEY (Godot'ta -Z kuzeydir). (0,0) sol ust kose.
        x, z = geo.forward(lon, lat)
        return (round(x, 2), round(z, 2))

    def inside(p, margin: float = 0.0) -> bool:
        return -margin <= p[0] <= width + margin and -margin <= p[1] <= height + margin

    table = load_classes()
    buildings, roads, areas, pois, coast = [], [], [], [], []
    for feature in raw["features"]:
        kind = feature["kind"]
        tags = feature["tags"]
        points = [project(lon, lat) for lon, lat in feature["points"]]
        if kind == "poi":
            if inside(points[0]):
                pois.append({"p": points[0], "tags": tags})
            continue
        if not any(inside(p, 40.0) for p in points):
            continue
        if kind == "building":
            if len(points) >= 4 and points[0] == points[-1]:
                points = points[:-1]
            if len(points) < 3 or polygon_area(points) < 6.0 * scale * scale:
                continue
            holes = [[project(lon, lat) for lon, lat in hole] for hole in feature.get("holes", [])]
            buildings.append({"osm": feature["id"], "tags": tags, "poly": points, "holes": holes})
        elif kind == "road":
            highway = tags.get("highway", "")
            if highway not in ROADS or tags.get("tunnel") in ("yes", "building_passage"):
                continue
            w, sw, surface = ROADS[highway]
            lanes = tags.get("lanes")
            if lanes and lanes.isdigit() and highway in ("primary", "secondary", "trunk", "tertiary"):
                w = max(w, min(22, int(lanes) * 3.2))
            roads.append({"type": highway, "w": w, "sw": sw, "surface": surface, "pts": points,
                          "bridge": tags.get("bridge") == "yes", "layer": int(tags.get("layer", "0") or 0)
                          if str(tags.get("layer", "0")).lstrip("-").isdigit() else 0,
                          "name": tags.get("name", "")})
        elif kind == "coastline":
            coast.append(points)
        elif kind == "area":
            for (k, v), area_kind in AREA_KINDS.items():
                if tags.get(k) == v:
                    if len(points) >= 4 and points[0] == points[-1]:
                        points = points[:-1]
                    if len(points) >= 3:
                        areas.append({"kind": area_kind, "poly": points, "name": tags.get("name", "")})
                    break

    # --- dukkan noktalarini binalara ata ---
    for building in buildings:
        building["class"] = classify(building["tags"], table)
    assigned = 0
    for poi in pois:
        cls = classify(poi["tags"], table)
        if not cls:
            continue
        x, z = poi["p"]
        for building in buildings:
            poly = building["poly"]
            xs = [p[0] for p in poly]
            zs = [p[1] for p in poly]
            if min(xs) <= x <= max(xs) and min(zs) <= z <= max(zs) and point_in_polygon(x, z, poly):
                # Ayni binada birden fazla dukkan: nadir sinif kazansin
                # (eczane > market > apartman).
                if building["class"] in ("", "residential", "civic"):
                    building["class"] = cls
                    building.setdefault("shop_name", poi["tags"].get("name", ""))
                    assigned += 1
                break

    # --- kara/deniz maskesi (1 m) ---
    barrier = np.zeros((height, width), dtype=bool)
    for line in coast:
        for (x0, z0), (x1, z1) in zip(line, line[1:]):
            steps = int(max(abs(x1 - x0), abs(z1 - z0)) * 2) + 1
            for s in range(steps + 1):
                t = s / steps
                x = int(x0 + (x1 - x0) * t)
                z = int(z0 + (z1 - z0) * t)
                for dx, dz in ((0, 0), (1, 0), (0, 1)):
                    if 0 <= x + dx < width and 0 <= z + dz < height:
                        barrier[z + dz, x + dx] = True
    sea = np.zeros((height, width), dtype=bool)
    seeds = []
    for lat, lon in (args.sea_seed or []):
        x, z = project(lon, lat)
        seeds.append((int(x), int(z)))
    queue = deque(s for s in seeds if 0 <= s[0] < width and 0 <= s[1] < height and not barrier[s[1], s[0]])
    for x, z in queue:
        sea[z, x] = True
    while queue:
        x, z = queue.popleft()
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, nz = x + dx, z + dz
            if 0 <= nx < width and 0 <= nz < height and not sea[nz, nx] and not barrier[nz, nx]:
                sea[nz, nx] = True
                queue.append((nx, nz))
    # Kiyi cizgisi hucreleri: denize komsuysa deniz sayilir (rihtim kenari).
    land = ~sea
    sea_fraction = float(sea.mean())

    # --- arazi yuksekligi (TAHMIN): kiyidan uzaklastikca yavasca yukselir ---
    # Yarim metre biriminde. 20 m'de 1 m: kaldirimlar (yarim blok) ile ayni
    # ritimde yukselir, yurunen egimde hic tam blokluk basamak olusmaz.
    dist = np.full((height, width), 1e9, dtype=np.float32)
    dq = deque()
    zs, xs = np.nonzero(sea)
    for z, x in zip(zs.tolist(), xs.tolist()):
        dist[z, x] = 0.0
        dq.append((x, z))
    if not dq:
        dist[:] = 200.0
    while dq:
        x, z = dq.popleft()
        d = dist[z, x] + 1.0
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, nz = x + dx, z + dz
            if 0 <= nx < width and 0 <= nz < height and dist[nz, nx] > d:
                dist[nz, nx] = d
                dq.append((nx, nz))
    half = np.clip(2 + np.floor(dist / 10.0), 2, 24).astype(np.uint8)
    half[sea] = 0

    def pack(array: np.ndarray) -> str:
        return base64.b64encode(zlib.compress(array.astype(np.uint8).tobytes(), 9)).decode("ascii")

    # --- binalar: kat ve yukseklik ---
    out_buildings = []
    for index, building in enumerate(buildings):
        tags = building["tags"]
        levels = tags.get("building:levels", "")
        estimated = True
        if levels.replace(".", "").isdigit():
            levels = max(1, min(40, int(float(levels))))
            estimated = False
        else:
            h = tags.get("height", "").replace("m", "").strip()
            if h.replace(".", "").isdigit():
                levels = max(1, int(float(h) / 3.0))
                estimated = False
            else:
                seed = (int(str(building["osm"]).lstrip("wr").split("#")[0]) * 2654435761) & 0xFFFF
                base = {"residential": 5, "market": 4, "pharmacy": 5, "civic": 4, "religious": 2,
                        "garage": 1, "industrial": 2, "workshop": 3, "hospital": 6, "police": 3}.get(
                    building["class"] or "residential", 4)
                levels = max(1, base + (seed % 3) - 1)
        ident = building["osm"] if isinstance(building["osm"], str) else "w%d" % building["osm"]
        entry = {
            "id": ident, "class": building["class"] or "residential",
            "levels": levels, "est": estimated, "poly": building["poly"],
            "height_source": "class_estimate" if estimated else "osm_levels",
            "name": tags.get("name", building.get("shop_name", "")),
            "roof": tags.get("roof:shape", ""), "historic": "historic" in tags,
            "religion": tags.get("religion", "") if tags.get("building") in ("mosque", "church") or
            tags.get("amenity") == "place_of_worship" else "",
        }
        if building["holes"]:
            entry["holes"] = building["holes"]
        out_buildings.append(entry)

    named = []
    for poi in pois:
        name = poi["tags"].get("name", "")
        if name and any(k in poi["tags"] for k in ("amenity", "historic", "tourism")):
            named.append({"name": name, "p": poi["p"], "kind": poi["tags"].get("amenity") or
                          poi["tags"].get("historic") or poi["tags"].get("tourism")})

    spawn = [width / 2.0, height / 2.0]
    if args.spawn:
        spawn = list(project(args.spawn[1], args.spawn[0]))

    counts: dict[str, int] = {}
    for b in out_buildings:
        counts[b["class"]] = counts.get(b["class"], 0) + 1
    result = {
        "map_id": args.id, "name": args.name or args.id, "generator_version": GENERATOR_VERSION,
        "scale": scale, "transform": geo.to_dict(), "center": {"lat": lat0, "lon": lon0}, "size": [width, height],
        "real_size_m": [real_w, real_h],
        "license": "Harita verisi (c) OpenStreetMap katkicilari, ODbL 1.0",
        "height_estimated": True,
        "land": pack(land), "terrain_half_m": pack(half),
        "buildings": out_buildings, "roads": roads, "areas": areas, "pois": named,
        "spawn": spawn,
        "stats": {"buildings": len(out_buildings), "classes": counts, "roads": len(roads),
                  "areas": len(areas), "pois_assigned": assigned, "sea_fraction": round(sea_fraction, 3)},
    }
    out = ROOT / "data" / "map" / f"{args.id}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{out} ({out.stat().st_size / 1024:.0f} KB) {width}x{height} oyun m -- {result['stats']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
