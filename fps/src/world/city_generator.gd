class_name CityGenerator
extends RefCounted
## Gercek OSM verisinden (fps/data/map/<id>.json) voxel sehir uretir.
##
## Uretim chunk chunk ve ISTEK UZERINE yapilir; oyun acilisinda butun
## sehir islenmez. Her sutun (x, z) icin once bir "sutun bilgisi" hesaplanir
## (zemin yuksekligi, yuzey, bina, agac) ve onbellege alinir; chunk bu
## bilgiden doldurulur. Is parcacigi guvenlidir: harita verisi salt
## okunurdur, sutun onbellegi Mutex ile korunur.
##
## ONCELIK: deniz > yol > kaldirim > bina > alan (park, meydan) > zemin.
## Yol binadan once geldigi icin sikistirilmis olcekte bile sokaklar ACIK
## kalir; sokaga tasan bina parcasi kesilir.
##
## BINA ICI (uretici surumu 2): girilebilir binalarda InteriorPlanner'in
## deterministik plani voxel'e cevrilir -- zemin kat ve (merdivenli
## yerlesimlerde) 1. kat odalari, ic duvarlar, kapi aciklik ve merdiven.
## Mobilya ve kapilar GIZLI KATI hucrelerdir (mesh'e girmez; carpisma, mermi,
## gorus ve yol bulma okur). Ulasilamayan ust katlar ve plansiz binalar eskisi
## gibi DOLU malzeme hacmidir; cephe kirilinca arkadaki yapi gorunur.
## (Eski "tasarlanmis oda yoktur" karari 23 Eylul 2026'da kaldirildi.)
##
## HARITA BICIMLERI
##   v1 (kadikoy): 1 m cozunurlukte tam kara/arazi dizileri. Kucuk haritalar.
##   v2 (maltepe_besiktas koridoru): 8 x 10 km kutu; 1 m'lik dizi 84 milyon
##     hucre ederdi. Kara maskesi 2 m'de satir RLE'si, arazi 4 m izgarasi
##     (cift dogrusal okunur), bina tabanlari onceden hesaplanmis. Koridor
##     disi VoxelWorld sinir maskesiyle girilemez ama manzara olarak uretilir.
##
## 15 TEMMUZ SEHITLER KOPRUSU (yalnizca v2)
##   Tek tabliye (orta refuj, serit cizgileri, 2 m korkuluk) ve kiyilarda iki
##   celik kule. Tabliye karadan rampa ile kalkar; alcak rampanin alti dolgu,
##   yuksek kisim ayaklidir. Deniz ustunde ayak YOKTUR (asma kopru). Tabliye
##   ve kuleler voxel'dir: vurulabilir, delinebilir, onarilabilir. Ana halat,
##   askilar ve uzak siluet voxel degildir (bkz. BridgeDecor).

const GENERATOR_VERSION := 3  # 3: gercek olcek (1:1), butun katlar + merdiven cekirdegi, avlu
                               # 2: girilebilir bina icleri (1 -> 2 kayit gocu tanimli)
const SEA_FLOOR := -7
const WATER_TOP := -1          # su yuzeyi y=0'da (hucre -1'in ustu)
const FLOOR_HEIGHT := 4        # butun katlar: 1 m doseme + 3 m net tavan
const SKY_BASE := 40           # binasiz sutunda uretilen en yuksek hucre (arazi + agac + ziplama payi)
const DECK_Y := 30             # kopru tabliyesinin deniz ustundeki yurume yuksekligi
const TOWER_TOP := 68
const HANGER_EVERY := 6.0
const PIER_EVERY := 24.0
const COLUMN_CACHE := 90000    # sutun onbellegi nesil boyu (bkz. column_info)
const PLAN_CACHE := 600        # ic plan onbellegi nesil boyu

var data: Dictionary = {}
var map_id := ""
var format := 1
var width := 0
var height := 0
var m: Dictionary = {}         # malzeme kimligi -> indeks
var land := PackedByteArray()
var terrain := PackedByteArray()
var buildings: Array = []      # yuklenmis bina kayitlari (bkz. _prepare_buildings)
var roads: Array = []          # [{a, b, half, sidewalk, surface, type}] segmentler
var areas: Array = []
var bridges: Array = []        # hazirlanmis buyuk kopru tabliyeleri (v2)
var _building_tiles: Dictionary = {}   # Vector2i(tile) -> [bina indeksi]
var _road_tiles: Dictionary = {}
var _area_tiles: Dictionary = {}
var _columns: Dictionary = {}          # Vector2i -> sutun bilgisi (genc nesil)
var _columns_old: Dictionary = {}      # onceki nesil (bkz. column_info)
var _mutex := Mutex.new()
var _plans: Dictionary = {}            # bina indeksi -> ic plan (genc nesil)
var _plans_old: Dictionary = {}
var _plan_mutex := Mutex.new()
var palette: Array = []                # cephe malzemeleri (agirlikli)
var real_scale := false               # 1:1 harita: bina ayak izi yola karsi oncelikli
var max_top := 0                       # en yuksek bina/kule hucresi (dinamik dikey sinir)
var geo := GeoTransform.new()    # cografi <-> oyun metresi (harita "transform")

# --- v2 ---
var land_res := 1
var _land_rows: Array = []             # satir -> PackedInt32Array (kumulatif run sonlari)
var _land_first := PackedByteArray()   # satirin ilk degeri
var inside_res := 4
var _inside_rows: Array = []
var _inside_first := PackedByteArray()
var terrain_res := 1
var terrain_w := 0
var terrain_h := 0

# --- sabit tasarim haritasi (yeni_istanbul): semt izgarasi ---
var districts: Array = []              # [{id, name, zone, center, area_km2}]
var district_res := 25
var district_n := 0
var _district_grid := PackedByteArray()  # hucre -> semt indeksi + 1 (0 = su)
var border := 0                          # girilemez kenar bandi (m); 0 = eski harita

const TILE := 16


func _init(materials: BlockMaterials, map_path: String) -> void:
	for id: String in materials.defs:
		m[id] = materials.index_of(id)
	AssetLibrary.count()          # manifest/metadata ANA is parcaciginda yuklensin
	var errors: Array = []
	var raw: Variant = ContentValidator.load_json(map_path, errors)
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("Harita yuklenemedi: %s %s" % [map_path, errors])
		return
	data = raw
	map_id = str(data.get("map_id", "bilinmeyen"))
	format = int(data.get("format", 1))
	width = int(data.size[0])
	height = int(data.size[1])
	geo = GeoTransform.from_map(data)
	real_scale = float(data.get("scale", 0.65)) >= 0.99
	if format >= 2:
		land_res = int(data.get("land_res", 2))
		_land_first = _decode_rle(data.get("land_rle", []), _land_rows)
		inside_res = int(data.get("inside_res", 4))
		_inside_first = _decode_rle(data.get("inside_rle", []), _inside_rows)
		terrain_res = int(data.get("terrain_res", 4))
		terrain_w = int(data.terrain_size[0])
		terrain_h = int(data.terrain_size[1])
		terrain = _unpack(data.get("terrain_grid", ""), terrain_w * terrain_h)
	else:
		land = _unpack(data.get("land", ""), width * height)
		terrain = _unpack(data.get("terrain_half_m", ""), width * height)
	districts = data.get("districts", [])
	border = int(data.get("border", 0))
	var grid: Dictionary = data.get("district_grid", {})
	if not grid.is_empty():
		district_res = int(grid.get("res", 25))
		district_n = int(grid.size[0])
		_district_grid = _unpack(str(grid.get("data", "")), district_n * int(grid.size[1]))
	palette = [
		[m.plaster_cream, 3.0], [m.plaster_rose, 2.0], [m.plaster_white, 2.5],
		[m.brick, 2.0], [m.plaster_blue, 1.0], [m.concrete, 1.2], [m.wood_old, 0.5],
	]
	_prepare_roads()
	_prepare_bridges()
	_prepare_buildings()
	_prepare_areas()
	# Ham JSON dizileri hazirliktan sonra kullanilmaz; Variant sozluk/dizi
	# olarak koridor haritasinda yuzlerce MB tutuyordu. Kucuk bilgi alanlari
	# (merkez, olcek, dogus, noktalar, harita goruntusu) kalir.
	for key: String in ["buildings", "roads", "areas", "land_rle", "inside_rle", "terrain_grid",
			"land", "terrain_half_m", "bridges"]:
		data.erase(key)


static func _decode_rle(raw: Array, rows: Array) -> PackedByteArray:
	## [ilk deger, run1, run2, ...] satirlarini ikili aramaya uygun kumulatif
	## sonlara cevirir. Bellek: satir basina yalnizca gecis sayisi kadar int.
	var firsts := PackedByteArray()
	firsts.resize(raw.size())
	rows.resize(raw.size())
	for i in raw.size():
		var row: Array = raw[i]
		firsts[i] = int(row[0])
		var ends := PackedInt32Array()
		ends.resize(row.size() - 1)
		var total := 0
		for k in range(1, row.size()):
			total += int(row[k])
			ends[k - 1] = total
		rows[i] = ends
	return firsts


static func _rle_get(rows: Array, firsts: PackedByteArray, row: int, col: int) -> int:
	if row < 0 or row >= rows.size() or col < 0:
		return 0
	var ends: PackedInt32Array = rows[row]
	# Ilk "son > col" olan run; cift numarali run ilk degeri tasir.
	var run := ends.bsearch(col, false)
	return firsts[row] ^ (run & 1)


static func _unpack(text: String, size: int) -> PackedByteArray:
	if text == "":
		var empty := PackedByteArray()
		empty.resize(size)
		return empty
	var compressed := Marshalls.base64_to_raw(text)
	var bytes := compressed.decompress_dynamic(size + 16, FileAccess.COMPRESSION_DEFLATE)
	if bytes.size() != size:
		push_error("Harita dizisi beklenen boyutta degil (%d != %d)" % [bytes.size(), size])
		bytes.resize(size)
	return bytes


func configure(world: VoxelWorld) -> void:
	## Dikey sinir SABIT DEGIL: en yuksek bina/kule + pay. Eski 96 m tavani
	## yuksek binalari sessizce kesiyordu. Sutun basina ust sinir
	## (max_chunk_y) bos gokyuzu chunk'larinin uretilmesini onler.
	world.min_cell = Vector3i(0, SEA_FLOOR - 2, 0)
	world.max_cell = Vector3i(width, maxi(96, max_top + 24), height)
	world.column_top = max_chunk_y
	if format >= 2 and not _inside_rows.is_empty():
		world.set_limit(inside_mask(), int(round(log(inside_res) / log(2.0))), width / inside_res + 1)


func max_chunk_y(cx: int, cz: int) -> int:
	## Bu chunk sutununda (16 x 16) uretilmesi gereken en yuksek chunk
	## katmani. Ustu KESIN bostur (hava): uretilmez, sorgulara hava doner.
	## Komsu sutunlarin binalari da hesaba katilir (catidan komsu catiya
	## gecis, yan yuzlerin meshlenmesi). Is parcacigi guvenli (salt okuma).
	var top := SKY_BASE
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for index: int in _building_tiles.get(Vector2i(cx + dx, cz + dz), []):
				top = maxi(top, int(buildings[index].top_y) + 8)
	if not bridges.is_empty():
		var p := Vector2(cx * TILE + 8, cz * TILE + 8)
		for b: Dictionary in bridges:
			if p.x >= b.lo.x - 24 and p.y >= b.lo.y - 24 and p.x <= b.hi.x + 24 and p.y <= b.hi.y + 24:
				top = maxi(top, TOWER_TOP + 4)
	return top >> 4


func inside_mask() -> PackedByteArray:
	## Koridor maskesini VoxelWorld icin duz bayt dizisine acar (inside_res
	## metre/hucre). Run'lar dilim olarak eklenir; hucre hucre dongu yok.
	var cols := width / inside_res + 1
	var ones := PackedByteArray()
	ones.resize(cols)
	ones.fill(1)
	var zeros := PackedByteArray()
	zeros.resize(cols)
	var mask := PackedByteArray()
	for row in _inside_rows.size():
		var ends: PackedInt32Array = _inside_rows[row]
		var value := int(_inside_first[row])
		var start := 0
		for end in ends:
			var n := mini(end, cols) - start
			if n > 0:
				mask.append_array((ones if value == 1 else zeros).slice(0, n))
				start += n
			value ^= 1
		if start < cols:
			mask.append_array(zeros.slice(0, cols - start))
	return mask


func is_inside(x: int, z: int) -> bool:
	## Oynanabilir koridorda mi? (v1 haritalarin tamami oynanabilir)
	if x < 0 or z < 0 or x >= width or z >= height:
		return false
	if format < 2 or _inside_rows.is_empty():
		return true
	return _rle_get(_inside_rows, _inside_first, z / inside_res, x / inside_res) != 0


func district_index(x: float, z: float) -> int:
	## Sabit haritada noktanin semti (-1: su ya da semt verisi yok).
	if _district_grid.is_empty():
		return -1
	var ix := int(x) / district_res
	var iz := int(z) / district_res
	if ix < 0 or iz < 0 or ix >= district_n or iz >= district_n:
		return -1
	return int(_district_grid[iz * district_n + ix]) - 1


func district_at(x: float, z: float) -> Dictionary:
	var i := district_index(x, z)
	return districts[i] if i >= 0 and i < districts.size() else {}


func border_distance(x: float, z: float) -> float:
	## Girilebilir alanin kenarina uzaklik (m). Eski haritalarda INF.
	if border <= 0:
		return INF
	return minf(minf(x - border, z - border), minf(width - border - x, height - border - z))


func spawn_point() -> Vector3:
	var s: Array = data.get("spawn", [width * 0.5, height * 0.5])
	var x := int(s[0])
	var z := int(s[1])
	# En yakin acik kaldirim/yol hucresini ara.
	for r in range(0, 40):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var info := column_info(x + dx, z + dz)
				if info.kind in ["road", "sidewalk", "plaza"] and info.building < 0 \
						and _clear_around(x + dx, z + dz, 2):
					return Vector3(x + dx + 0.5, info.surface_half * 0.5 + (0.5 if info.kind == "sidewalk" else 0.0) + 0.1, z + dz + 0.5)
	return Vector3(x + 0.5, 10.0, z + 0.5)


func _clear_around(x: int, z: int, r: int) -> bool:
	## Cevrede bina/deniz yok mu? (dogus noktasi cepheye yapismasin)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var kind: String = column_info(x + dx, z + dz).kind
			if kind in ["building", "sea", "void"] or column_info(x + dx, z + dz).tree:
				return false
	return true


func ground_height(x: int, z: int) -> int:
	## Yol bulma icin: ayakta durulan ilk hucrenin y'si. Kopru tabliyesinde
	## tabliye (alttaki zemin degil): zombiler koprude yurur.
	var info := column_info(x, z)
	if info.has("deck_half"):
		return int(info.deck_half) / 2
	var half: int = info.surface_half + (1 if info.kind == "sidewalk" else 0)
	return half / 2


func surface_y(x: int, z: int) -> float:
	## Ayakta durulan yuzeyin KESIN yuksekligi (m). ground_height hucre
	## verir; yarim bloklu (egimli) zeminde gercek yuzey 0.5 m yukaridadir.
	## Arac gibi govdeler buna konmazsa yarim bloga gomulu baslar ve kilitlenir.
	var info := column_info(x, z)
	if info.has("deck_half"):
		return int(info.deck_half) * 0.5
	match info.kind:
		"sea":
			return 0.0
		"pier":
			return 1.0
	return (int(info.surface_half) + (1 if info.kind == "sidewalk" else 0)) * 0.5


# ---------------------------------------------------------------------------
# Hazirlik
# ---------------------------------------------------------------------------
func _prepare_roads() -> void:
	for road: Dictionary in data.get("roads", []):
		if format < 2 and (road.get("bridge", false) or int(road.get("layer", 0)) > 0):
			continue   # v1: ust gecitler atlanir (Kadikoy uretimi degismesin)
		# v2: kucuk kopru/ust gecitler zemin seviyesinde yol olur (ag kopmasin);
		# buyuk kopru ayri sistemdir ve bu listede yoktur.
		var pts: Array = road.pts
		var half := float(road.w) * 0.5
		var sidewalk := float(road.sw)
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			var segment := {"a": a, "b": b, "half": half, "sidewalk": sidewalk,
				"surface": road.surface, "type": road.type}
			var index := roads.size()
			roads.append(segment)
			var reach := half + sidewalk + 1.0
			_index_box(_road_tiles, Vector2(minf(a.x, b.x) - reach, minf(a.y, b.y) - reach),
				Vector2(maxf(a.x, b.x) + reach, maxf(a.y, b.y) + reach), index)


func _prepare_bridges() -> void:
	for raw: Dictionary in data.get("bridge_decks", []):
		var pts := PackedVector2Array()
		for p: Array in raw.pts:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() < 2:
			continue
		var cum := PackedFloat32Array([0.0])
		var lo := pts[0]
		var hi := pts[0]
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
			lo = lo.min(pts[i])
			hi = hi.max(pts[i])
		var half := float(raw.half)
		var reach := Vector2(half + 5.0, half + 5.0)
		var length := cum[cum.size() - 1]
		var towers: Array = raw.towers
		bridges.append({
			"name": str(raw.get("name", "")), "pts": pts, "cum": cum, "length": length, "half": half,
			"t1": float(towers[0]), "t2": float(towers[1]),
			# Rampa uclari yerel zemine oturur (yarim metre; +1 = zeminden hafif yuksek).
			"g0": _terrain_at(int(pts[0].x), int(pts[0].y)) + 1,
			"g1": _terrain_at(int(pts[pts.size() - 1].x), int(pts[pts.size() - 1].y)) + 1,
			"lo": lo - reach, "hi": hi + reach,
		})


func bridge_point(b: Dictionary, s: float) -> Vector2:
	## Orta hat uzerinde bastan `s` metre otedeki nokta.
	var pts: PackedVector2Array = b.pts
	var cum: PackedFloat32Array = b.cum
	for k in pts.size() - 1:
		if s <= cum[k + 1] or k == pts.size() - 2:
			var span := maxf(1e-6, cum[k + 1] - cum[k])
			return pts[k].lerp(pts[k + 1], clampf((s - cum[k]) / span, 0.0, 1.0))
	return pts[pts.size() - 1]


func _bridge_at(p: Vector2) -> Dictionary:
	## Kopru orta hattina gore (s: bastan uzaklik, d: yanal uzaklik).
	for i in bridges.size():
		var b: Dictionary = bridges[i]
		if p.x < b.lo.x or p.y < b.lo.y or p.x > b.hi.x or p.y > b.hi.y:
			continue
		var pts: PackedVector2Array = b.pts
		var cum: PackedFloat32Array = b.cum
		var best_d := INF
		var best_s := 0.0
		for k in pts.size() - 1:
			var a := pts[k]
			var ab := pts[k + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(1e-6, ab.length_squared()), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best_d:
				best_d = d
				best_s = cum[k] + ab.length() * t
		# Uclarin otesi kopru degildir (yuvarlak "bas" olusmasin).
		if best_d <= b.half + 4.0 and best_s > 0.5 and best_s < b.length - 0.5:
			return {"index": i, "s": best_s, "d": best_d}
	return {}


func deck_half(b: Dictionary, s: float) -> int:
	## Tabliye yuruyus yuzeyi (yarim metre). Kuleye kadar dogrusal rampa, ana
	## aciklik DUZ: kamburluk yarim bloklarla serit cizgilerini bolerdi.
	var top := float(DECK_Y * 2)
	var h: float = top
	if s < b.t1:
		h = lerpf(float(b.g0), top, s / maxf(1.0, b.t1))
	elif s > b.t2:
		h = lerpf(float(b.g1), top, (b.length - s) / maxf(1.0, b.length - b.t2))
	return roundi(h)


func cable_y(b: Dictionary, s: float) -> float:
	## Ana halat yuksekligi (dunya y): kule tepesinden sarkan parabol.
	## Voxel degil; BridgeDecor cizer.
	var hang := float(TOWER_TOP - 2)
	if s >= b.t1 and s <= b.t2:
		var span := maxf(1.0, (b.t2 - b.t1) * 0.5)
		var k: float = (s - (b.t1 + b.t2) * 0.5) / span
		var low := DECK_Y + 2.5
		return low + (hang - low) * k * k
	# Yan aciklik: ankraja (kopru ucu) dogru tabliyeye iner.
	var deck := deck_half(b, s) * 0.5 + 1.5
	var u: float = s / maxf(1.0, b.t1) if s < b.t1 else (b.length - s) / maxf(1.0, b.length - b.t2)
	return deck + (hang - deck) * u * u


func _bridge_part(b: Dictionary, s: float, d: float) -> String:
	var near_tower := minf(absf(s - b.t1), absf(s - b.t2))
	if d <= b.half:
		return "edge" if d > b.half - 1.0 else "deck"
	if near_tower <= 2.5 and d <= b.half + 3.0:
		return "tower"
	# Ana halat ve askilar voxel DEGIL (bkz. BridgeDecor): 1 m kuplerle
	# basamaklanan halat yakindan kirik bir kafes gibi gorunuyordu.
	return ""


func _prepare_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	for raw: Dictionary in data.get("buildings", []):
		var poly := PackedVector2Array()
		for p: Array in raw.poly:
			poly.append(Vector2(p[0], p[1]))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		if hi.x < 0 or hi.y < 0 or lo.x > width or lo.y > height:
			continue
		rng.seed = hash(raw.id)
		var base_half := 255
		if raw.has("base_half"):
			# v2: arac onceden hesapladi (27 bin binada acilis suresi kisa kalir).
			base_half = int(raw.base_half)
		else:
			# Taban: ayak izindeki EN DUSUK zemin. Yokus asagi tarafta bodrum
			# gorunur -- Istanbul yokuslarinin tipik gorunumu.
			var step := 2.0
			var sx := lo.x
			while sx <= hi.x:
				var sz := lo.y
				while sz <= hi.y:
					if Geometry2D.is_point_in_polygon(Vector2(sx, sz), poly):
						base_half = mini(base_half, _terrain_at(int(sx), int(sz)))
					sz += step
				sx += step
			if base_half == 255:
				base_half = _terrain_at(int((lo.x + hi.x) * 0.5), int((lo.y + hi.y) * 0.5))
		var levels := maxi(1, int(raw.levels))
		var cls := str(raw.get("class", "residential"))
		var facade := _pick_facade(rng, cls, raw)
		var base_y := int(ceil(base_half * 0.5))
		var holes: Array = []
		for ring: Array in raw.get("holes", []):
			var hole := PackedVector2Array()
			for p: Array in ring:
				hole.append(Vector2(p[0], p[1]))
			if hole.size() >= 3:
				holes.append(hole)
		var area := _poly_area(poly)
		for hole: PackedVector2Array in holes:
			area -= _poly_area(hole)
		# Ic mekan: yerlesimi olan, tarihi olmayan ve 14 m2'den buyuk bina.
		# BUTUN katlar ayni 4 m ritimdedir; hangi katlara merdivenle
		# ulasildigi plandan gelir (plan.accessible). Cati yuksekligi plandan
		# bagimsiz, chunk'tan chunk'a tutarli.
		var layout_id := str(Content.interiors.get("class_layout", {}).get(cls, ""))
		# "solid": sur, kule, kompleks duvari -- tasarim geregi dolu hacim.
		var interior := layout_id != "" and not bool(raw.get("historic", false)) and not bool(raw.get("solid", false)) \
			and area >= 14.0
		var top_y := base_y - 1 + levels * FLOOR_HEIGHT
		max_top = maxi(max_top, top_y + 2)
		var entry := {
			"id": str(raw.id), "class": cls, "levels": levels, "estimated": bool(raw.get("est", true)),
			"height_source": str(raw.get("height_source", "osm_levels" if not bool(raw.get("est", true)) else "class_estimate")),
			"poly": poly, "holes": holes, "lo": lo, "hi": hi, "base_y": base_y, "interior": interior,
			"accessible": levels if interior else 0,
			"top_y": top_y, "facade": facade, "area": area,
			"shop": cls in ["market", "pharmacy", "electronics", "workshop", "garage", "police", "clinic", "checkpoint"],
			"pitched": levels <= 3 and (bool(raw.get("historic", false)) or rng.randf() < 0.25),
			"name": str(raw.get("name", "")), "religious": cls == "religious",
			"ground_uses": raw.get("ground_uses", []),
			"centroid": (lo + hi) * 0.5,
		}
		var index := buildings.size()
		buildings.append(entry)
		_index_box(_building_tiles, lo, hi, index)


static func _poly_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5


# ---------------------------------------------------------------------------
# Ic mekan planlari
# ---------------------------------------------------------------------------
func interior_plan(index: int) -> Dictionary:
	## Binanin ic plani (deterministik, onbellekli). Is parcacigi guvenli:
	## iki isci ayni binayi ayni anda planlarsa ikisi de ayni sonucu uretir.
	if index < 0 or index >= buildings.size() or not bool(buildings[index].get("interior", false)):
		return {"ok": false}
	_plan_mutex.lock()
	var cached: Variant = _plans.get(index)
	if cached == null:
		cached = _plans_old.get(index)
		if cached != null:
			_plans[index] = cached
	_plan_mutex.unlock()
	if cached != null:
		return cached
	var plan := InteriorPlanner.build(self, index)
	_plan_mutex.lock()
	_plans[index] = plan
	if _plans.size() > PLAN_CACHE:
		_plans_old = _plans
		_plans = {}
	_plan_mutex.unlock()
	return plan


var _plan_tasks: Dictionary = {}      # bina indeksi -> is kimligi (yalnizca ana is parcacigi)


func plan_cached(index: int) -> bool:
	_plan_mutex.lock()
	var ok := _plans.has(index) or _plans_old.has(index)
	_plan_mutex.unlock()
	return ok


func request_plan(index: int) -> void:
	## Plani arka planda hesaplat (gorsel yukleyici ana is parcacigini beklemesin).
	if plan_cached(index) or _plan_tasks.has(index):
		return
	_plan_tasks[index] = WorkerThreadPool.add_task(interior_plan.bind(index), false, "ic-plan")


func poll_plans() -> void:
	for index: int in _plan_tasks.keys():
		if WorkerThreadPool.is_task_completed(_plan_tasks[index]):
			WorkerThreadPool.wait_for_task_completion(_plan_tasks[index])
			_plan_tasks.erase(index)


func furniture_at(cell: Vector3i) -> Dictionary:
	## Bu voxel hucresini dolduran mobilya: {plan, f, index} ya da bos.
	var index := building_at(cell.x, cell.z)
	if index < 0:
		return {}
	var plan := interior_plan(index)
	if not plan.get("ok", false):
		return {}
	var o: Vector2i = plan.origin
	var s: Vector2i = plan.size
	var lx := cell.x - o.x
	var lz := cell.z - o.y
	if lx < 0 or lz < 0 or lx >= s.x or lz >= s.y:
		return {}
	var rel := cell.y - int(plan.floors[0].y)
	var k := floori(float(rel) / InteriorPlanner.FLOOR_HEIGHT)
	var row := rel - k * InteriorPlanner.FLOOR_HEIGHT       # 0..2 oda satiri
	if k < 0 or k >= plan.floors.size() or row > 2:
		return {}
	var fl: Dictionary = plan.floors[k]
	if bool(fl.get("solid", false)):
		return {}
	var li := lz * s.x + lx
	for key: String in ["fidx_up", "fidx"]:
		var fi: int = fl[key][li]
		if fi < 0:
			continue
		var gi: int = int(fl.fbase) + fi
		var f: Dictionary = plan.furniture[gi]
		var rows: Array = f.rows
		if row >= int(rows[0]) and row <= int(rows[1]):
			return {"plan": plan, "f": f, "index": gi}
	return {}


func door_at(cell: Vector2i) -> Dictionary:
	## Bu sutundaki giris kapisi: {plan, door} ya da bos.
	var index := building_at(cell.x, cell.y)
	if index < 0:
		return {}
	var plan := interior_plan(index)
	if not plan.get("ok", false):
		return {}
	for door: Dictionary in plan.doors:
		if door.cell == cell:
			return {"plan": plan, "door": door}
	return {}


func buildings_near(position: Vector3, radius: float) -> Array:
	## Konuma yakin binalar (ayak izi kutusuna gore).
	var result: Array = []
	var p := Vector2(position.x, position.z)
	var r := ceili(radius / TILE)
	var t := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	var seen := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for index: int in _building_tiles.get(t + Vector2i(dx, dz), []):
				if seen.has(index):
					continue
				seen[index] = true
				var b: Dictionary = buildings[index]
				var closest := p.clamp(b.lo, b.hi)
				if closest.distance_to(p) <= radius:
					result.append(index)
	return result


func _plan_column(index: int, x: int, z: int) -> Dictionary:
	## Bir sutunun kat kat plan kodlari (chunk uretimi icin).
	var plan := interior_plan(index)
	if not plan.get("ok", false):
		return {}
	var o: Vector2i = plan.origin
	var s: Vector2i = plan.size
	var lx := x - o.x
	var lz := z - o.y
	if lx < 0 or lz < 0 or lx >= s.x or lz >= s.y:
		return {}
	var li := lz * s.x + lx
	var col := {"floors": plan.floors.size(), "accessible": int(plan.accessible), "codes": [], "mask": [],
		"mat": [], "floor_mat": [], "wall_mat": [], "solid": []}
	for fl: Dictionary in plan.floors:
		var solid := bool(fl.get("solid", false))
		col.solid.append(solid)
		col.floor_mat.append(int(m.get(str(fl.get("floor_mat", plan.floor_material)), m.concrete)))
		col.wall_mat.append(int(m.get(str(fl.get("wall_mat", plan.wall_material)), m.interior_plaster)))
		if solid:
			col.codes.append(InteriorPlanner.FILL)
			col.mask.append(0)
			col.mat.append(0)
			continue
		col.codes.append(int(fl.codes[li]))
		col.mask.append(int(fl.rows[li]))
		var fi: int = fl.fidx[li]
		if fi < 0:
			fi = fl.fidx_up[li]
		col.mat.append(int(m.get(plan.furniture[int(fl.fbase) + fi].material, m.furniture_wood)) if fi >= 0 else 0)
	for door: Dictionary in plan.doors:
		if door.cell == Vector2i(x, z):
			col["door_mat"] = 0 if door.open else int(m.get(door.material, m.door_wood))
			col["door_rows"] = int(door.get("rows", 2))
	# Merdiven cekirdegi: basamak hucresi, orta kolon ya da cati korkulugu.
	var stairs: Dictionary = plan.get("stairs", {})
	if not stairs.is_empty():
		var here := Vector2i(x, z)
		col["flights"] = int(stairs.flights)
		col["roof_open"] = bool(stairs.roof)
		if (stairs.get("shaft", []) as Array).has(here):
			col["ladder"] = true
		elif stairs.tops.has(here):
			col["core_t"] = float(stairs.tops[here])
		elif stairs.pillar.has(here):
			col["pillar"] = true
		elif bool(stairs.roof) and here != stairs.entry and here != stairs.exit:
			# Cati boslugunun cevresi korkuluk; ama cikis/giris hucresinin
			# yanlari ACIK kalir (spiralde kose cikisi iki yandan kapanirdi).
			var beside_exit := false
			for d: Vector2i in InteriorPlanner.DIRS:
				if here + d == stairs.exit or here + d == stairs.entry:
					beside_exit = true
			if not beside_exit:
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if stairs.tops.has(here + Vector2i(dx, dz)):
							col["roof_rail"] = true
	return col


func _pick_facade(rng: RandomNumberGenerator, cls: String, raw: Dictionary) -> int:
	# Sabit tasarim haritasi cepheyi acikca verebilir (tarihi han, kiyi konagi...).
	var forced := str(raw.get("facade", ""))
	if forced != "" and m.has(forced):
		return m[forced]
	if cls == "religious" or bool(raw.get("historic", false)) or cls == "fortification":
		return m.limestone
	if cls in ["industrial", "garage"]:
		return m.concrete if rng.randf() < 0.6 else m.metal_sheet
	if cls in ["prison", "checkpoint"]:
		return m.concrete
	if cls == "school":
		return m.brick if rng.randf() < 0.5 else m.plaster_cream
	if cls in ["hospital", "civic", "police", "military", "clinic"]:
		return m.plaster_white if rng.randf() < 0.5 else m.concrete
	var total := 0.0
	for entry: Array in palette:
		total += entry[1]
	var roll := rng.randf() * total
	for entry: Array in palette:
		roll -= entry[1]
		if roll <= 0.0:
			return entry[0]
	return m.plaster_cream


func _prepare_areas() -> void:
	for raw: Dictionary in data.get("areas", []):
		var poly := PackedVector2Array()
		for p: Array in raw.poly:
			poly.append(Vector2(p[0], p[1]))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		var index := areas.size()
		areas.append({"kind": raw.kind, "poly": poly, "lo": lo, "hi": hi})
		_index_box(_area_tiles, lo, hi, index)


func _index_box(target: Dictionary, lo: Vector2, hi: Vector2, index: int) -> void:
	var t0 := Vector2i(floori(maxf(0.0, lo.x) / TILE), floori(maxf(0.0, lo.y) / TILE))
	var t1 := Vector2i(floori(minf(width - 1, hi.x) / TILE), floori(minf(height - 1, hi.y) / TILE))
	for tz in range(t0.y, t1.y + 1):
		for tx in range(t0.x, t1.x + 1):
			var key := Vector2i(tx, tz)
			if not target.has(key):
				target[key] = []
			target[key].append(index)


func _terrain_at(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= width or z >= height:
		return 2
	if format < 2:
		return terrain[z * width + x]
	# v2: 4 m izgara CIFT DOGRUSAL okunur; en yakin hucre alinsaydi arazi
	# 4 m'lik teraslar halinde basamaklanirdi.
	var fx := (x + 0.5) / terrain_res - 0.5
	var fz := (z + 0.5) / terrain_res - 0.5
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var top := lerpf(_grid(ix, iz), _grid(ix + 1, iz), tx)
	var bottom := lerpf(_grid(ix, iz + 1), _grid(ix + 1, iz + 1), tx)
	# Kara en az 1 m (yarim metre x 2): kiyida deniz hucresine karisip su
	# seviyesine inmesin.
	return maxi(2, roundi(lerpf(top, bottom, tz)))


func _grid(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, terrain_w - 1)
	iz = clampi(iz, 0, terrain_h - 1)
	return terrain[iz * terrain_w + ix]


func is_land(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= width or z >= height:
		return false
	if format >= 2:
		return _rle_get(_land_rows, _land_first, z / land_res, x / land_res) != 0
	return land[z * width + x] != 0


# ---------------------------------------------------------------------------
# Sutun bilgisi
# ---------------------------------------------------------------------------
func column_info(x: int, z: int) -> Dictionary:
	## Onbellek IKI NESILLIDIR: genc nesil dolunca eskisi atilir, genc eski
	## olur. Oyuncunun yakinindaki sutunlar surekli genc nesle tasinir;
	## 10 km'lik haritayi gezen oyuncuda bellek sinirsiz buyumez (v1'in tek
	## sozlugu kucuk haritada sorun degildi).
	var key := Vector2i(x, z)
	_mutex.lock()
	var cached: Variant = _columns.get(key)
	if cached == null:
		cached = _columns_old.get(key)
		if cached != null:
			_columns[key] = cached
	_mutex.unlock()
	if cached != null:
		return cached
	var info := _compute_column(x, z)
	_mutex.lock()
	_columns[key] = info
	if _columns.size() > COLUMN_CACHE:
		_columns_old = _columns
		_columns = {}
	_mutex.unlock()
	return info


func cached_columns() -> int:
	return _columns.size() + _columns_old.size()


func building_at(x: int, z: int) -> int:
	## Bu sutundaki binanin indeksi ya da -1 (yol kesmesi DIKKATE ALINMAZ:
	## bina kimligi ayak izine aittir).
	var tile := Vector2i(floori(x / float(TILE)), floori(z / float(TILE)))
	var p := Vector2(x + 0.5, z + 0.5)
	for index: int in _building_tiles.get(tile, []):
		var b: Dictionary = buildings[index]
		if p.x < b.lo.x or p.y < b.lo.y or p.x > b.hi.x or p.y > b.hi.y:
			continue
		if Geometry2D.is_point_in_polygon(p, b.poly):
			# Ic avlu (OSM inner ring) binaya ait degildir: acik zemin.
			var in_hole := false
			for hole: PackedVector2Array in b.holes:
				if Geometry2D.is_point_in_polygon(p, hole):
					in_hole = true
					break
			if not in_hole:
				return index
	return -1


func _compute_column(x: int, z: int) -> Dictionary:
	var info := _compute_base(x, z)
	if bridges.is_empty() or info.kind == "void":
		return info
	var hit := _bridge_at(Vector2(x + 0.5, z + 0.5))
	if hit.is_empty():
		return info
	var b: Dictionary = bridges[hit.index]
	# Kopru izinin altinda bina ve agac yok: tabliyeyi delerlerdi.
	if info.kind == "building":
		info.kind = "ground"
		info.building = -1
		info.surface = m.cobblestone
		info.erase("edge")
	info.tree = false
	var part := _bridge_part(b, hit.s, hit.d)
	if part == "":
		return info
	info["bridge"] = part
	info["bridge_index"] = hit.index
	info["bridge_s"] = hit.s
	info["bridge_d"] = hit.d
	if part == "deck" or part == "edge":
		info["deck_half"] = deck_half(b, hit.s)
	return info


func _compute_base(x: int, z: int) -> Dictionary:
	var info := {"kind": "ground", "surface_half": _terrain_at(x, z), "surface": m.cobblestone,
		"building": -1, "tree": false, "water": false}
	if x < 0 or z < 0 or x >= width or z >= height:
		info.kind = "void"
		return info
	var tile := Vector2i(floori(x / float(TILE)), floori(z / float(TILE)))
	var p := Vector2(x + 0.5, z + 0.5)
	var h := _hash(x, z)
	# Alanlar (park, iskele, meydan) -- once belirlenir, yollar ustune yazar.
	var area_kind := ""
	for index: int in _area_tiles.get(tile, []):
		var area: Dictionary = areas[index]
		if p.x < area.lo.x or p.y < area.lo.y or p.x > area.hi.x or p.y > area.hi.y:
			continue
		if Geometry2D.is_point_in_polygon(p, area.poly):
			area_kind = area.kind
			if area_kind != "parking":
				break
	if not is_land(x, z):
		if area_kind == "pier":
			info.kind = "pier"
			info.surface_half = 2
			return info
		info.kind = "sea"
		info.water = true
		info.surface_half = 0
		return info
	# GERCEK OLCEK (bicim 3): bina ayak izi OSM'deki yerindedir; sabit tablo
	# genisligiyle cizilen yol binanin ICINE GIRMEZ (yol o noktada daralir).
	# Sikistirilmis eski haritalarda yol oncelikliydi (sokak acik kalsin).
	if real_scale:
		var owner := building_at(x, z)
		if owner >= 0:
			return _building_info(info, x, z, owner)
	# Yollar: en genis kapsayan yol kazanir.
	var best_width := -1.0
	for index: int in _road_tiles.get(tile, []):
		var road: Dictionary = roads[index]
		var d := _segment_distance(p, road.a, road.b)
		var half: float = road.half
		var sidewalk: float = road.sidewalk
		if d <= half and half * 2.0 > best_width:
			best_width = half * 2.0
			info.kind = "road"
			info.surface = m.asphalt if road.surface == "asphalt" else m.cobblestone
		elif d <= half + sidewalk and info.kind != "road" and best_width < 0.0:
			info.kind = "sidewalk"
			info.surface = m.sidewalk
	if info.kind == "road":
		return info
	var building := building_at(x, z) if not real_scale else -1
	if building >= 0 and info.kind != "sidewalk":
		return _building_info(info, x, z, building)
	if info.kind == "sidewalk":
		# Kaldirim agaclari: seyrek ve yola degil kaldirimin dis kenarina.
		info.tree = h % 29 == 0
		return info
	match area_kind:
		"park", "grass", "pitch":
			info.kind = "park"
			info.surface = m.grass
			info.tree = area_kind == "park" and h % 17 == 0
		"forest":
			info.kind = "park"
			info.surface = m.grass
			info.tree = h % 7 == 0
		"cemetery":
			info.kind = "cemetery"
			info.surface = m.grass
			info.tree = h % 31 == 0
		"plaza", "parking":
			info.kind = "plaza"
			info.surface = m.cobblestone if area_kind == "plaza" else m.asphalt
		"construction":
			info.kind = "ground"
			info.surface = m.dirt
		_:
			if format >= 2 and not is_inside(x, z):
				# Koridor disi (girilemez): verisi olmayan ic bolgeler parke
				# ovasi degil, agacli yesil alan olarak ufka karisir.
				info.surface = m.grass
				info.tree = h % 23 == 0
			else:
				# Binalar arasi bosluk: avlu/aralik. Cogunlukla parke, bazen toprak/cimen.
				info.surface = m.cobblestone if h % 5 != 0 else (m.grass if h % 2 == 0 else m.dirt)
	return info


func _building_info(info: Dictionary, x: int, z: int, building: int) -> Dictionary:
	info.kind = "building"
	info.building = building
	# Cephe mi? Sutun basina BIR KEZ hesaplanir (her y icin degil).
	info["edge"] = false
	for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _occupies(x + o.x, z + o.y, building):
			info.edge = true
			break
	return info


func _occupies(x: int, z: int, building: int) -> bool:
	## Bu hucre GERCEKTEN bu binaya mi ait? (deniz degil, yol/kaldirim kesmemis)
	if not is_land(x, z) or building_at(x, z) != building:
		return false
	if real_scale:
		return true          # gercek olcek: yol binayi kesmez
	var tile := Vector2i(floori(x / float(TILE)), floori(z / float(TILE)))
	var p := Vector2(x + 0.5, z + 0.5)
	for index: int in _road_tiles.get(tile, []):
		var road: Dictionary = roads[index]
		if _segment_distance(p, road.a, road.b) <= road.half + road.sidewalk:
			return false
	return true


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _hash(x: int, z: int) -> int:
	var h := (x * 73856093) ^ (z * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16)) % 1000003


# ---------------------------------------------------------------------------
# Chunk doldurma
# ---------------------------------------------------------------------------
func generate_chunk(chunk: VoxelChunk) -> void:
	var origin := chunk.origin()
	if chunk.coord.y > max_chunk_y(chunk.coord.x, chunk.coord.z):
		return                 # kesin bos gokyuzu
	for lz in 16:
		for lx in 16:
			var x := origin.x + lx
			var z := origin.z + lz
			var info := column_info(x, z)
			if info.kind == "void":
				continue
			# Ic mekanli binada sutunun kat kat plan kodlari BIR KEZ okunur.
			var col := {}
			if info.kind == "building":
				var b: Dictionary = buildings[info.building]
				if bool(b.interior) and origin.y <= int(b.top_y) + 1 and origin.y + 16 >= int(b.base_y) - 1:
					col = _plan_column(info.building, x, z)
				elif origin.y > int(b.top_y) + 1 and not info.tree:
					continue       # sutun bu chunk'ta bos
			for ly in 16:
				var y := origin.y + ly
				var value := _block_at(x, y, z, info, col)
				if value != 0:
					chunk.blocks[VoxelChunk.index(lx, ly, lz)] = value
	# Agac yapraklari komsu sutunlardan tasar: cevredeki capalar BIR KEZ
	# toplanir, yapraklar dogrudan basilir.
	if origin.y > 40 or origin.y + 16 < -2:
		return
	for z in range(origin.z - 2, origin.z + 18):
		for x in range(origin.x - 2, origin.x + 18):
			var anchor := column_info(x, z)
			if anchor.tree:
				_stamp_leaves(chunk, origin, x, z, anchor)


func _stamp_leaves(chunk: VoxelChunk, origin: Vector3i, ax: int, az: int, anchor: Dictionary) -> void:
	var half: int = anchor.surface_half + (1 if anchor.kind == "sidewalk" else 0)
	var surface_y := half / 2 + (1 if half % 2 == 1 else 0)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var lx := ax + dx - origin.x
			var lz := az + dz - origin.z
			if lx < 0 or lz < 0 or lx >= 16 or lz >= 16:
				continue
			for y in range(surface_y + 3, surface_y + 6):
				var ly := y - origin.y
				if ly < 0 or ly >= 16:
					continue
				var r := absi(dx) + absi(dz) + (1 if y == surface_y + 5 else 0)
				if r > 3 or (dx == 0 and dz == 0 and y < surface_y + 4):
					continue
				var i := VoxelChunk.index(lx, ly, lz)
				# Bina ici artik bos: yaprak odalarin icine basilmasin.
				if chunk.blocks[i] == 0 and column_info(ax + dx, az + dz).kind != "building":
					chunk.blocks[i] = m.leaves


func _block_at(x: int, y: int, z: int, info: Dictionary, col: Dictionary = {}) -> int:
	if info.has("bridge"):
		var value := _bridge_block(y, info)
		if value >= 0:
			return value
	var kind: String = info.kind
	if kind == "sea":
		if y <= SEA_FLOOR:
			return m.stone
		if y <= SEA_FLOOR + 1:
			return m.sand
		return m.water if y <= WATER_TOP else 0
	if kind == "pier":
		if y == 0:
			return m.pier_deck
		if y < 0 and y > SEA_FLOOR and (x % 4 == 0 and z % 4 == 0):
			return m.log          # iskele ayaklari
		if y <= SEA_FLOOR:
			return m.stone
		if y <= SEA_FLOOR + 1:
			return m.sand
		return m.water if y <= WATER_TOP else 0
	if kind == "building":
		return _building_block(x, y, z, info, col)

	var half: int = info.surface_half
	if kind == "sidewalk":
		half += 1
	var top_full := half / 2 - 1          # son tam blok
	var slab_y := half / 2 if half % 2 == 1 else -1000
	if y == slab_y:
		return _half_of(info.surface, kind)
	if y <= top_full:
		if y == top_full and slab_y == -1000:
			return _full_of(info.surface, kind)
		if y >= top_full - 2:
			return m.dirt
		return m.stone
	# Yuzeyin ustu: agac, mezar tasi.
	var surface_y := half / 2 + (1 if half % 2 == 1 else 0)
	if info.tree and y >= surface_y and y < surface_y + 4:
		return m.log
	if kind == "cemetery" and y == surface_y and _hash(x, z) % 5 == 0:
		return m.gravestone
	return 0


func _bridge_block(y: int, info: Dictionary) -> int:
	## Kopru hucresi; -1: kopru bu hucreye karismaz (taban sutun kurali).
	var b: Dictionary = bridges[info.bridge_index]
	var s: float = info.bridge_s
	var part: String = info.bridge
	if part == "tower":
		# Celik kule bacagi: deniz tabanindan tepeye.
		return m.bridge_steel if y <= TOWER_TOP and y > SEA_FLOOR - 1 else -1
	# Tabliye / kenar
	var h: int = info.deck_half
	var top_full := h / 2 - 1
	var girder := top_full - 1
	var d: float = info.bridge_d
	if y == top_full + 1 or y == top_full + 2:
		if part == "edge":
			return m.railing       # 2 m korkuluk: koprude yanlislikla dusulmez
		if y == top_full + 1 and d < 0.5:
			# Orta refuj: alcak bordur (yarim blok). Capraz izgarada tam blok
			# iki hucre genisliginde kaba bir zikzak oluyordu.
			return m.sidewalk
		if y == top_full + 1 and h % 2 == 1:
			return m.asphalt_half
	if y == top_full:
		if part != "deck":
			return m.bridge_steel
		# Kesik serit cizgileri (3 serit / yon).
		if (absf(d - 3.6) < 0.3 or absf(d - 7.1) < 0.3) and fposmod(s, 9.0) < 4.0:
			return m.asphalt_line
		return m.asphalt
	if y == girder:
		return m.bridge_steel
	var near_tower := minf(absf(s - b.t1), absf(s - b.t2))
	if near_tower <= 1.5:
		# Kuleler arasi yatay kirisler: tepe, orta ve tabliye alti.
		var mid_beam := (DECK_Y + TOWER_TOP) / 2 + 6
		if (y >= TOWER_TOP - 3 and y <= TOWER_TOP) or (y >= mid_beam and y <= mid_beam + 1) \
				or (y >= girder - 3 and y <= girder - 2):
			return m.bridge_steel
	if y > top_full:
		return -1
	# Tabliyenin alti: zemine kadar bosluk; karada alcak rampa DOLGU, yuksekte AYAK.
	var ground := _base_top(info)
	if y <= ground:
		return -1
	if info.kind != "sea" and info.kind != "pier":
		if girder - ground <= 4:
			return m.concrete
		if fposmod(s, PIER_EVERY) < 2.0 and d >= b.half - 5.0 and d <= b.half - 3.0:
			return m.concrete
	return 0


func _base_top(info: Dictionary) -> int:
	## Taban sutunun en ust dolu (ya da yarim) hucresi.
	match info.kind:
		"sea":
			return WATER_TOP
		"pier":
			return 0
	var half: int = info.surface_half + (1 if info.kind == "sidewalk" else 0)
	return half / 2 if half % 2 == 1 else half / 2 - 1


func _full_of(surface: int, kind: String) -> int:
	if kind == "sidewalk":
		return m.curb_block
	return surface


func _half_of(surface: int, kind: String) -> int:
	if kind == "sidewalk":
		return m.sidewalk
	if surface == m.asphalt:
		return m.asphalt_half
	if surface == m.grass:
		return m.grass_half
	return m.cobble_half


func _building_block(x: int, y: int, z: int, info: Dictionary, col: Dictionary = {}) -> int:
	## Bicim 3: butun katlar 4 m (satir 0 doseme, 1..3 oda). Ic mekanli
	## binada (col dolu) kat kat plan; merdiven cekirdegi hucreleri kat
	## sinirindan bagimsiz InteriorPlanner.core_block ile cizilir (doseme
	## yok, ince basamak tablalari). Plani olmayan bina dolu hacimdir.
	var b: Dictionary = buildings[info.building]
	var base_y: int = b.base_y
	var top_y: int = b.top_y
	if y < SEA_FLOOR + 3:
		return m.stone
	if y > top_y + 1:
		return 0
	var edge: bool = info.edge
	var rel := y - base_y
	var core := col.has("core_t")
	if y == top_y + 1:
		# Cati: kenarda korkuluk duvari (parapet), eski/kucuk binada kiremit;
		# merdiven cati cikisinin cevresi korkuluk.
		if b.pitched:
			return m.roof_tile
		if edge:
			return b.facade
		if bool(col.get("roof_rail", false)):
			return m.railing
		return 0
	if y == top_y:
		if col.has("ladder") and bool(col.get("roof_open", false)):
			return m.ladder
		if core and bool(col.get("roof_open", false)):
			return _core_value(col, rel)
		return (m.roof_tile if b.pitched else m.roof_flat) if not edge else b.facade
	if y < base_y - 1:
		return m.concrete if edge else m.interior
	var k := (rel + 1) / FLOOR_HEIGHT
	var row := (rel + 1) % FLOOR_HEIGHT     # 0 doseme, 1..3 oda
	if not col.is_empty():
		if edge:
			return _facade_accessible(x, z, b, k, row, col)
		if k < int(col.floors) and bool(col.solid[k]):
			return m.concrete if row == 0 else m.interior
		if col.has("ladder"):
			# Tirmanma safti: zemin kat dosemesi, ustunde kat katlarindan gecen merdiven.
			if rel == -1:
				return int(col.floor_mat[0])
			return m.ladder if rel <= FLOOR_HEIGHT * int(col.flights) - 1 else 0
		if core:
			var value := _core_value(col, rel)
			if value == 0 and rel == -1:
				return int(col.floor_mat[0])      # zemin kat dosemesi (toprak ustu)
			return value
		if col.has("pillar"):
			return int(col.wall_mat[mini(k, int(col.floors) - 1)])
		return _interior_block(k, row, col)
	if not edge:
		# DOLU HACIM: kat dosemesi her 4 blokta, arasi "bina ici yapi".
		return m.concrete if row == 0 else m.interior
	if rel < 0:
		return m.concrete   # bodrum/temel (yokus asagi tarafta gorunur)
	var along := x + z
	if k == 0 and b.shop:
		# Zemin kat dukkan: vitrin cami + kepenk.
		if row == 1:
			return m.metal_sheet if along % 4 == 0 else m.glass
		if row == 2:
			return m.glass if along % 4 != 0 else m.metal_sheet
		return m.concrete
	if row == 0:
		return b.facade
	if b.religious:
		return b.facade if along % 5 != 2 else m.glass
	if row >= 2 and along % 3 == 1:
		return m.glass
	if along % 3 == 2 and row == 3 and _hash(x, z) % 7 == 0:
		return m.window_frame
	return b.facade


func _core_value(col: Dictionary, rel: int) -> int:
	match InteriorPlanner.core_block(float(col.core_t), rel, int(col.flights)):
		1:
			return m.stair_step
		2:
			return m.stair_step_half
	return 0


func _facade_accessible(x: int, z: int, b: Dictionary, k: int, row: int, col: Dictionary) -> int:
	## Ic mekanli binanin cephesi: kapi, pencere (1-3 m), dukkan vitrini.
	if row == 0:
		return m.concrete if k == 0 else b.facade
	if k == 0 and col.has("door_mat"):
		return int(col.door_mat) if row <= int(col.door_rows) else b.facade
	var along := x + z
	if k == 0 and b.shop:
		if row <= 2:
			return m.metal_sheet if along % 4 == 0 else m.glass
		return b.facade
	if row >= 2 and along % 3 == 1:
		return m.glass
	return b.facade


func _interior_block(k: int, row: int, col: Dictionary) -> int:
	## Ic mekanli katin ici: plan kodundan duvar/doseme/mobilya.
	if k >= int(col.floors):
		return m.concrete if row == 0 else m.interior
	var code: int = col.codes[k]
	var floor_mat: int = col.floor_mat[k]
	var wall_mat: int = col.wall_mat[k]
	match code:
		InteriorPlanner.FREE:
			return floor_mat if row == 0 else 0
		InteriorPlanner.DOORWAY:
			return floor_mat if row == 0 else (wall_mat if row == 3 else 0)
		InteriorPlanner.WALL:
			return floor_mat if row == 0 else wall_mat
		InteriorPlanner.FURNITURE:
			if row == 0:
				return floor_mat
			return col.mat[k] if (int(col.mask[k]) >> (row - 1)) & 1 == 1 else 0
		InteriorPlanner.STAIR:
			return wall_mat          # cekirdek bilgisi olmayan STAIR (olmamali): kati
		InteriorPlanner.OUT:
			return 0
	return m.concrete if row == 0 else m.interior

# ---------------------------------------------------------------------------
# Bilgi
# ---------------------------------------------------------------------------
func building_count() -> int:
	return buildings.size()


func pois() -> Array:
	return data.get("pois", [])
