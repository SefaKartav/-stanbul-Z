"""OSM ham cikarimi: Turkiye .pbf -> Maltepe-Besiktas kutusunun ham ozellikleri.

YALNIZCA GELISTIRME ARACIDIR. Oyun calisirken Python'a ya da OSM dosyasina
bagli degildir; bu aracin ciktisini `build_corridor.py` oyunun okudugu
JSON haritaya cevirir.

CIKARICI SURUMU 2 (25 Eylul 2026)
    * GEOMETRIK KESISIM: bir yol/cizgi, kose noktalarindan biri kutunun
      icinde olmasa da bir KENARI kutuyu kesiyorsa alinir. v1 yalnizca
      "en az bir dugumu icerde" olanlari aliyordu; kutu sinirini gecen uzun
      yollar ve buyuk binalar kayboluyordu.
    * ALANLAR libosmium'un alan birlestiricisinden gelir: kapali way VE
      multipolygon relation'lar ayni yoldan, DIS ve IC halkalariyla. Ic avlu
      (inner ring) bina hacmiyle doldurulmaz.
    * Kimlik turu ayrilir: "w123" way, "r456" relation. Ayni binanin hem way
      hem alan olarak iki kez sayilmasi yapisal olarak engellenir (binalar
      YALNIZCA alan akisindan alinir).
    * `building:part` ayri tur ("building_part"): ust bina ile parcalari iki
      ayri bina gibi ust uste sayilmaz; harita adiminda parcalarin yukseklik
      bilgisi ust binaya aktarilir.
    * Gerekli etiketler korunur: height, min_height, building:levels,
      building:min_level, roof:height, roof:levels, layer, bridge, tunnel,
      width, lanes ...
    * Onbellek basligi: kaynak dosya SHA-256 + cikarici surumu. Harita
      adimi uyusmayan onbellegi reddeder.
    * Birlestirilemeyen (bozuk) multipolygon relation'lar sebebiyle raporlanir.

Kullanim:
    python fps/tools/osm_extract.py turkey-260909.osm.pbf
    (cikti: fps/tools/cache/osm_raw.json + osm_extract_report.json)

Gereksinim: pyosmium >= 4 (pip install osmium). Oyun paketine girmez.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import sys
import time
from pathlib import Path

EXTRACTOR_VERSION = 2

# Maltepe - Besiktas ve 15 Temmuz Sehitler Koprusu. Karakoy/Galata ikinci
# genisleme onerisi oldugu icin batida biraz pay birakildi.
DEFAULT_BBOX = (28.965, 40.905, 29.145, 41.062)

ROAD_TYPES = {
    "motorway", "trunk", "primary", "secondary", "tertiary", "unclassified",
    "residential", "living_street", "service", "pedestrian", "footway",
    "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link",
    "steps", "path", "cycleway",
}
AREA_KEYS = {
    ("leisure", "park"), ("leisure", "garden"), ("landuse", "grass"),
    ("landuse", "recreation_ground"), ("landuse", "cemetery"), ("amenity", "grave_yard"),
    ("natural", "wood"), ("landuse", "forest"), ("natural", "scrub"),
    ("natural", "water"), ("landuse", "reservoir"), ("amenity", "parking"),
    ("man_made", "pier"), ("landuse", "construction"), ("leisure", "pitch"),
    ("amenity", "school"), ("amenity", "hospital"), ("landuse", "railway"),
    ("place", "square"), ("highway", "pedestrian"),
}
KEEP_TAGS = {
    "building", "building:part", "building:levels", "building:min_level", "height", "min_height",
    "roof:shape", "roof:height", "roof:levels", "name", "amenity", "shop",
    "craft", "healthcare", "office", "man_made", "military", "landuse", "abandoned",
    "historic", "tourism", "leisure", "natural", "highway", "bridge", "layer", "lanes",
    "width", "tunnel", "religion", "building:material", "place", "area", "type", "level",
    "surface", "oneway", "junction",
}
POI_KEYS = ("amenity", "shop", "craft", "healthcare", "office", "military", "historic", "tourism")


def ascii_path(path: Path) -> str:
    """osmium Turkce karakterli yolu okuyamiyor: Windows 8.3 kisa yolu."""
    text = str(path)
    if text.isascii():
        return text
    buffer = ctypes.create_unicode_buffer(512)
    if ctypes.windll.kernel32.GetShortPathNameW(text, buffer, 512):
        return buffer.value
    return text


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            block = handle.read(8 * 1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


class Box:
    def __init__(self, min_lon: float, min_lat: float, max_lon: float, max_lat: float):
        self.x0, self.y0, self.x1, self.y1 = min_lon, min_lat, max_lon, max_lat

    def contains(self, lon: float, lat: float) -> bool:
        return self.x0 <= lon <= self.x1 and self.y0 <= lat <= self.y1

    def segment_hits(self, ax: float, ay: float, bx: float, by: float) -> bool:
        """Liang-Barsky: [a, b] dogru parcasi kutuyu kesiyor mu?"""
        if self.contains(ax, ay) or self.contains(bx, by):
            return True
        dx, dy = bx - ax, by - ay
        t0, t1 = 0.0, 1.0
        for p, q in ((-dx, ax - self.x0), (dx, self.x1 - ax), (-dy, ay - self.y0), (dy, self.y1 - ay)):
            if p == 0.0:
                if q < 0.0:
                    return False
                continue
            r = q / p
            if p < 0.0:
                if r > t1:
                    return False
                t0 = max(t0, r)
            else:
                if r < t0:
                    return False
                t1 = min(t1, r)
        return t0 <= t1

    def line_hits(self, points: list) -> bool:
        if any(self.contains(lon, lat) for lon, lat in points):
            return True
        return any(self.segment_hits(a[0], a[1], b[0], b[1]) for a, b in zip(points, points[1:]))

    def ring_hits(self, ring: list) -> bool:
        """Halka kutuyu kesiyor ya da kutuyu tamamen iceriyor mu?"""
        if self.line_hits(ring + ring[:1]):
            return True
        # Kutu halkanin tamamen icindeyse hicbir kenar kesismez.
        return point_in_ring((self.x0 + self.x1) / 2, (self.y0 + self.y1) / 2, ring)


def point_in_ring(x: float, y: float, ring: list) -> bool:
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def ring_points(ring) -> list:
    points = []
    for node in ring:
        location = node.location
        if location.valid():
            points.append([round(location.lon, 7), round(location.lat, 7)])
    if len(points) >= 2 and points[0] == points[-1]:
        points.pop()
    return points


def area_kind(tags) -> str:
    if "building" in tags and tags.get("building") != "no":
        return "building"
    if "building:part" in tags and tags.get("building:part") != "no":
        return "building_part"
    if any(tags.get(k) == v for k, v in AREA_KEYS):
        return "area"
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pbf", type=Path)
    parser.add_argument("--bbox", type=float, nargs=4, default=list(DEFAULT_BBOX),
                        metavar=("MIN_LON", "MIN_LAT", "MAX_LON", "MAX_LAT"))
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "cache" / "osm_raw.json")
    args = parser.parse_args()
    try:
        import osmium
    except ImportError:
        print("HATA: pyosmium kurulu degil (pip install osmium).", file=sys.stderr)
        return 2
    if not args.pbf.is_file():
        print(f"HATA: {args.pbf} bulunamadi.", file=sys.stderr)
        return 2

    started = time.time()
    print("kaynak ozeti (SHA-256) hesaplaniyor...", flush=True)
    source_hash = file_sha256(args.pbf)
    print(f"  {source_hash} ({time.time() - started:.0f} sn)", flush=True)
    box = Box(*args.bbox)

    features: list[dict] = []
    counts: dict[str, int] = {}
    rejected: list[dict] = []
    relation_candidates: dict[int, dict] = {}   # bina/alan etiketli multipolygon relation -> bilgi
    relation_areas: set[int] = set()

    def keep(tags) -> dict:
        return {t.k: t.v for t in tags if t.k in KEEP_TAGS or t.k.startswith("name")}

    def count(kind: str) -> None:
        counts[kind] = counts.get(kind, 0) + 1

    area_filter = osmium.filter.KeyFilter("building", "building:part", "landuse", "leisure", "natural",
                                          "amenity", "man_made", "place", "highway")
    source = osmium.io.File(ascii_path(args.pbf))   # bicim uzantidan (pbf / osm)
    processor = osmium.FileProcessor(source).with_locations().with_areas(area_filter)
    for entity in processor:
        if entity.is_node():
            tags = entity.tags
            if not any(k in tags for k in POI_KEYS):
                continue
            location = entity.location
            if not location.valid() or not box.contains(location.lon, location.lat):
                continue
            features.append({"id": "n%d" % entity.id, "kind": "poi", "tags": keep(tags),
                             "points": [[round(location.lon, 7), round(location.lat, 7)]]})
            count("poi")
            continue
        if entity.is_relation():
            tags = entity.tags
            if tags.get("type") in ("multipolygon", "building") and area_kind(tags):
                relation_candidates[entity.id] = {"id": "r%d" % entity.id, "kind": area_kind(tags),
                                                  "name": tags.get("name", ""), "members": len(entity.members)}
            continue
        if entity.is_area():
            tags = entity.tags
            kind = area_kind(tags)
            if not kind:
                continue
            orig = entity.orig_id()
            ident = ("w%d" if entity.from_way() else "r%d") % orig
            outers, inners = [], []
            try:
                for outer in entity.outer_rings():
                    ring = ring_points(outer)
                    if len(ring) < 3:
                        continue
                    outers.append(ring)
                    for inner in entity.inner_rings(outer):
                        hole = ring_points(inner)
                        if len(hole) >= 3:
                            inners.append(hole)
            except osmium.InvalidLocationError:
                rejected.append({"id": ident, "reason": "gecersiz dugum konumu"})
                continue
            if not entity.from_way():
                relation_areas.add(orig)      # birlesti (kutu disi olsa da)
            if not outers:
                rejected.append({"id": ident, "reason": "dis halka yok"})
                continue
            if not any(box.ring_hits(ring) for ring in outers):
                continue
            # Birden fazla dis halkali relation: her dis halka ayri bir kayit
            # (kimlik ...#k). Ic halkalar kendi dis halkasina atanir.
            if len(outers) == 1:
                features.append({"id": ident, "kind": kind, "tags": keep(tags), "points": outers[0],
                                 "holes": inners})
                count(kind)
            else:
                for k, outer in enumerate(outers):
                    holes = [h for h in inners if point_in_ring(h[0][0], h[0][1], outer)]
                    if not box.ring_hits(outer):
                        continue
                    features.append({"id": "%s#%d" % (ident, k), "kind": kind, "tags": keep(tags),
                                     "points": outer, "holes": holes})
                    count(kind)
            continue
        # WAY: yalnizca cizgisel ozellikler (bina/alan alan akisindan gelir).
        way = entity
        tags = way.tags
        kind = ""
        if tags.get("highway") in ROAD_TYPES and tags.get("area") != "yes":
            kind = "road"
        elif tags.get("natural") == "coastline":
            kind = "coastline"
        elif tags.get("railway") in ("rail", "subway", "light_rail", "tram"):
            kind = "rail"
        if not kind:
            continue
        points = []
        try:
            for node in way.nodes:
                location = node.location
                if location.valid():
                    points.append([round(location.lon, 7), round(location.lat, 7)])
        except osmium.InvalidLocationError:
            rejected.append({"id": "w%d" % way.id, "reason": "gecersiz dugum konumu"})
            continue
        if len(points) < 2 or not box.line_hits(points):
            continue
        features.append({"id": "w%d" % way.id, "kind": kind, "tags": keep(tags), "points": points})
        count(kind)

    # Birlestirilemeyen relation'lar: kutuya yakin olup olmadigini bilemeyiz
    # (geometrisi kurulamadi); yine de sayi ve kimlik raporlanir.
    broken = [info for rid, info in relation_candidates.items() if rid not in relation_areas]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "source": args.pbf.name, "source_sha256": source_hash, "extractor_version": EXTRACTOR_VERSION,
        "bbox": args.bbox, "extracted_at": time.strftime("%Y-%m-%d %H:%M"),
        "license": "(c) OpenStreetMap katkicilari, ODbL 1.0",
        "features": features,
    }
    args.out.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    report = {
        "source": args.pbf.name, "source_sha256": source_hash, "extractor_version": EXTRACTOR_VERSION,
        "bbox": args.bbox, "counts": counts, "seconds": round(time.time() - started),
        "relation_candidates_total": len(relation_candidates),
        "relation_areas_in_box": len(relation_areas),
        "note": "Relation adaylari TUM Turkiye icindir; kutudaki relation alanlari relation_areas_in_box sayisidir.",
        "rejected": rejected[:500], "rejected_count": len(rejected),
        "unassembled_relations_sample": broken[:200], "unassembled_relations_total": len(broken),
    }
    (args.out.parent / "osm_extract_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=1),
                                                            encoding="utf-8")
    print(f"{len(features)} ozellik {counts} -> {args.out} "
          f"({args.out.stat().st_size / 1e6:.1f} MB, {time.time() - started:.0f} sn); "
          f"reddedilen {len(rejected)}, birlestirilemeyen relation (Turkiye geneli) {len(broken)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
