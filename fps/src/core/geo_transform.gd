class_name GeoTransform
extends RefCounted
## Tek koordinat donusumu: cografi (enlem/boylam) <-> oyun metresi.
##
## Python karsiligi: fps/tools/geo.py -- AYNI formul, AYNI parametreler
## (harita JSON'undaki "transform"):
##     x = (lon - min_lon) * m_lon * scale,   z = (max_lat - lat) * m_lat * scale
##     surum 1: m_lon = 111320 cos(lat0), m_lat = 110540 (eski)
##     surum 2: enleme bagli WGS84 derece uzunluklari (hassas)
## Surum 1: eski sikistirilmis haritalar (scale 0.65); "transform" alani
## yoktu, parametreler bbox/center/scale'den turetilir. Surum 2: 1:1.
## Kayit gocu eski kaydin konumunu eski donusumle cografi koordinata, oradan
## yeni haritaya tasir (rastgele 1/0.65 carpimi farkli kokende yanlis olurdu).

const M_LAT := 110540.0
const EARTH_R := 6371008.8

var version := 2
var min_lon := 0.0
var max_lat := 0.0
var lat0 := 41.0
var scale := 1.0
var m_lon := 111320.0 * cos(deg_to_rad(41.0))
var m_lat := M_LAT


static func make(p_min_lon: float, p_max_lat: float, p_lat0: float, p_scale: float, p_version: int = 2) -> GeoTransform:
	var t := GeoTransform.new()
	t.min_lon = p_min_lon
	t.max_lat = p_max_lat
	t.lat0 = p_lat0
	t.scale = p_scale
	t.version = p_version
	if p_version >= 2:
		# Surum 2: enleme bagli derece uzunlugu (WGS84 serisi; tools/geo.py ile ayni).
		var phi := deg_to_rad(p_lat0)
		t.m_lat = 111132.954 - 559.822 * cos(2.0 * phi) + 1.175 * cos(4.0 * phi)
		t.m_lon = 111412.84 * cos(phi) - 93.5 * cos(3.0 * phi) + 0.118 * cos(5.0 * phi)
	else:
		t.m_lon = 111320.0 * cos(deg_to_rad(p_lat0))
		t.m_lat = M_LAT
	return t


static func from_dict(data: Dictionary) -> GeoTransform:
	return make(float(data.get("min_lon", 0.0)), float(data.get("max_lat", 0.0)), float(data.get("lat0", 41.0)),
		float(data.get("scale", 1.0)), int(data.get("version", 2)))


static func from_map(data: Dictionary) -> GeoTransform:
	## Harita JSON'u: v3 "transform" tasir; eski koridor (v2) bbox + scale
	## ile ayni donusumu kullaniyordu (lat0 = omurga kutusunun ortasi).
	if data.has("transform"):
		return from_dict(data.transform)
	var bbox: Dictionary = data.get("bbox", {})
	var center: Dictionary = data.get("center", {})
	var s := float(data.get("scale", 1.0))
	if not bbox.is_empty():
		# build_corridor v2: lat0 = omurga enlemlerinin ortasi = (min+max)/2 (pay simetrik).
		return make(float(bbox.min_lon), float(bbox.max_lat), (float(bbox.min_lat) + float(bbox.max_lat)) * 0.5, s, 1)
	if not center.is_empty() and data.has("size"):
		# build_map (v1 kucuk harita): merkez haritanin ortasinda.
		var la := float(center.lat)
		var lo := float(center.lon)
		var mlon := 111320.0 * cos(deg_to_rad(la))
		var half_w := float(data.size[0]) * 0.5
		var half_h := float(data.size[1]) * 0.5
		return make(lo - half_w / (mlon * s), la + half_h / (M_LAT * s), la, s, 1)
	return GeoTransform.new()


func forward(lon: float, lat: float) -> Vector2:
	## (lon, lat) -> oyun (x, z)
	return Vector2((lon - min_lon) * m_lon * scale, (max_lat - lat) * m_lat * scale)


func inverse(p: Vector2) -> Vector2:
	## oyun (x, z) -> (lon, lat)
	return Vector2(p.x / (m_lon * scale) + min_lon, max_lat - p.y / (m_lat * scale))


func to_dict() -> Dictionary:
	return {"version": version, "kind": "equirectangular", "min_lon": min_lon, "max_lat": max_lat,
		"lat0": lat0, "scale": scale, "m_lon": m_lon, "m_lat": m_lat}


static func haversine(a: Vector2, b: Vector2) -> float:
	## a, b: (lon, lat) derece. Buyuk daire uzakligi (m).
	var p1 := deg_to_rad(a.y)
	var p2 := deg_to_rad(b.y)
	var dp := p2 - p1
	var dl := deg_to_rad(b.x - a.x)
	var s := sin(dp * 0.5) * sin(dp * 0.5) + cos(p1) * cos(p2) * sin(dl * 0.5) * sin(dl * 0.5)
	return 2.0 * EARTH_R * asin(sqrt(s))
