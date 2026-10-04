"""Tek koordinat donusumu: cografi (enlem/boylam) <-> oyun metresi.

Oyunun GDScript karsiligi: fps/src/core/geo_transform.gd. Iki taraf AYNI
formulu ve AYNI parametreleri (harita JSON'undaki "transform") kullanir.

    x = (lon - min_lon) * m_lon * scale        (dogu +)
    z = (max_lat - lat) * m_lat * scale        (guney +, Godot'ta -Z kuzey)
    m_lon = 111320 * cos(lat0),  m_lat = 110540

Surum 1: eski sikistirilmis haritalar (scale 0.65), parametreleri kayit
gocunde okunur (data/map/legacy_transforms.json).
Surum 2: 1 oyun birimi = 1 gercek metre (scale 1.0).

Hata butcesi: 16 km'lik koridorda esdikdortgen izdusumun enlem boyunca
cos(lat) farkindan dogan olcek hatasi ~%0.1'dir (bkz. distance_report).
"""

from __future__ import annotations

import math

M_LAT = 110540.0
EARTH_R = 6371008.8
TRANSFORM_VERSION = 2


class GeoTransform:
    def __init__(self, min_lon: float, max_lat: float, lat0: float, scale: float = 1.0,
                 version: int = TRANSFORM_VERSION):
        self.min_lon = min_lon
        self.max_lat = max_lat
        self.lat0 = lat0
        self.scale = scale
        self.version = version
        if version >= 2:
            # Surum 2: enleme bagli derece uzunlugu (WGS84 serisi). 41 derecede
            # m_lat ~111055 m; sabit 110540 (ekvator) kuzey-guneyde %0.46 hata
            # veriyordu.
            phi = math.radians(lat0)
            self.m_lat = 111132.954 - 559.822 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
            self.m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi) + 0.118 * math.cos(5 * phi)
        else:
            self.m_lon = 111320.0 * math.cos(math.radians(lat0))
            self.m_lat = M_LAT

    def forward(self, lon: float, lat: float) -> tuple[float, float]:
        return ((lon - self.min_lon) * self.m_lon * self.scale, (self.max_lat - lat) * self.m_lat * self.scale)

    def inverse(self, x: float, z: float) -> tuple[float, float]:
        """-> (lon, lat)"""
        return (x / (self.m_lon * self.scale) + self.min_lon, self.max_lat - z / (self.m_lat * self.scale))

    def to_dict(self) -> dict:
        return {"version": self.version, "kind": "equirectangular", "min_lon": self.min_lon, "max_lat": self.max_lat,
                "lat0": self.lat0, "scale": self.scale, "m_lon": self.m_lon, "m_lat": self.m_lat}

    @staticmethod
    def from_dict(data: dict) -> "GeoTransform":
        return GeoTransform(float(data["min_lon"]), float(data["max_lat"]), float(data["lat0"]),
                            float(data.get("scale", 1.0)), int(data.get("version", TRANSFORM_VERSION)))


def haversine(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_R * math.asin(math.sqrt(a))
