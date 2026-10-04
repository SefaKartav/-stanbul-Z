class_name InteriorPlanner
extends RefCounted
## Girilebilir bina ici PLANI: ayak izinden deterministik oda, gecit,
## merdiven cekirdegi ve mobilya yerlesimi (veri: data/world/interiors.json).
##
## Plan SAF bir hesaptir: dunyaya yazmaz, dugum olusturmaz. Ayni bina icin
## her zaman ayni plani uretir (tohum = bina kimligi). Bu sayede
##   * chunk uretimi (is parcaciginda) duvar/doseme/mobilya hacmini plandan
##     okur; chunk bosaltilip geri gelse ayni ic mekan olusur,
##   * container kimlikleri (bina + kat + kat icindeki sira) kararlidir.
##
## KAT DUZENI (uretici surumu 3): BUTUN katlar 1 doseme + 3 bos hucre = 4 m,
## net tavan 3 m. Cephe ile ic kat ayni ritmi izler (eskiden girilebilir
## katlar 4 m, ust katlar 3 m idi).
##
## MERDIVEN CEKIRDEGI (butun katlara erisim)
##   Once giris -> merdiven cekirdegi -> sahanlik baglantisi cozulur, sonra
##   odalar ve mobilya. Sablonlar: U (donuslu, 2x5), spiral (3x3, orta
##   kolon), L ve duz. Basamak yuksekligi 0.5 m (voxel yarim blok) ve basis
##   1 m; kat basi 8 basamak. U ve spiral kat kat UST USTE yigilir: her
##   basamak hucresinin kat icinde tek bir yuksekligi vardir, basamak 1-1.5 m
##   kalinliginda "ince" bir tabladir; boylece bir ust katin ayni hucredeki
##   basamagi ile arasinda en az 2.5 m bas boslugu kalir (hedef >= 2.05 m).
##   Cekirdek hucrelerinde kat dosemesi yoktur (merdiven boslugu). Duz cati
##   varsa son kol catiya cikar; cati cikisi korkulukla cevrilir.
##   L ve duz sablon yigilmaz: yalnizca tek kol (zemin -> 1. kat).
##
## KARMA KULLANIM: yerlesimin "upper" alani varsa (market, eczane...) ust
## katlar o yerlesimle (konut) planlanir; zemin kat dukkan kalir.
##
## UST KAT VARYANTLARI: kat 0 kendine ozgudur; ust katlar en fazla 3 plan
## varyantini sirayla kullanir (1,4,7.. ayni; komsu katlar farkli). Gercek
## apartmanlarda daireler ust uste benzer; plan maliyeti bina basina sinirli.
## Mobilya kimlikleri ve loot her kat icin ayridir.
##
## GUVENCELER (testlerle dogrulanir, bkz. tests/test_interiors.gd)
##   * Giris sokaktan erisilebilir: dis zemin ile ic doseme arasi <= 0.55 m.
##   * Her oda katin girisine (zeminde kapi, ustte merdiven varisi) baglidir;
##     baglanamayan cep DOLU yapilir (loot yok).
##   * Merdiven girisi zemin katta kapidan ulasilabilir olmali; degilse baska
##     yerlesim denenir. Hicbiri olmazsa ust katlar DOLU kalir ve plan
##     "reason_upper" ile nedenini tasir (rapor/test gorur).
##   * Mobilya gecitleri, girisi ve merdiveni kapatmaz; her container'in
##     onunde girisle bagli bos bir erisim hucresi vardir.

const OUT := 0
const FACADE := 1
const FREE := 2
const WALL := 3
const DOOR := 4          # giris kapisi (cephe hucresi)
const DOORWAY := 5       # ic gecit (kanatsiz, 1 x 2 m)
const FURNITURE := 6
const STAIR := 7         # merdiven cekirdegi (basamak ya da orta kolon)
const FILL := 8          # ulasilamayan cep: dolu hacim
const SHAFT := 9         # (eski) merdiven boslugu -- surum 3'te STAIR kullanilir

const FLOOR_HEIGHT := 4
const STEP := 0.5
const ROOM_ROWS := 3
const MAX_STEP := 0.55    # oyuncu basamagi (VoxelBody)
const MAX_VARIANTS := 3
const CORRIDOR_MIN_CELLS := 170     # bu alanin ustundeki katta ortak koridor
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var city: CityGenerator
var index := -1
var building: Dictionary
var base_layout: Dictionary = {}
var layout: Dictionary = {}          # uzerinde calisilan katin yerlesimi
var layout_id := ""
var rng := RandomNumberGenerator.new()
var ox := 0
var oz := 0
var w := 0
var h := 0
var occ := PackedByteArray()
var edge := PackedByteArray()
var inner := PackedByteArray()
var floor_y := 0
# Uzerinde calisilan katin dizileri. UYE degiskendir: Packed diziler deger
# tipidir; fonksiyona arguman olarak gecilseydi degisiklik kopyada kalirdi.
var codes := PackedByteArray()
var steps := PackedByteArray()
var fidx := PackedInt32Array()      # hucrenin tabanindaki mobilya (kat ici indeks, -1 yok)
var fidx_up := PackedInt32Array()   # duvar montajli ust mobilya (kat ici indeks, -1 yok)
var rowmask := PackedByteArray()    # katı mobilya satirlari (bit 0..2)
var furniture: Array = []           # UZERINDE CALISILAN KATIN mobilyalari
var slot := 0                       # kat ici container sira numarasi (kimlik)
var core: Dictionary = {}           # yerel cekirdek: {steps{Vector2i:t}, pillar[], entry, exit, name, stack}


static func build(p_city: CityGenerator, p_index: int) -> Dictionary:
	var planner := InteriorPlanner.new()
	planner.city = p_city
	planner.index = p_index
	return planner._run()


func _run() -> Dictionary:
	building = city.buildings[index]
	var result := {"ok": false, "index": index, "id": building.id, "class": building.class, "floors": [],
		"doors": [], "furniture": [], "stairs": {}, "accessible": 0, "levels": int(building.levels)}
	if not bool(building.get("interior", false)):
		result["reason"] = "sinif/boyut: ic mekan yok"
		return result
	layout_id = str(Content.interiors.get("class_layout", {}).get(building.class, ""))
	base_layout = Content.interiors.get("layouts", {}).get(layout_id, {})
	layout = base_layout
	if base_layout.is_empty():
		result["reason"] = "yerlesim tipi yok"
		return result
	rng.seed = hash(str(building.id) + ":ic")
	floor_y = building.base_y
	_footprint()
	var count := 0
	for v in inner:
		count += v
	if count < 6:
		result["reason"] = "ayak izi cok kucuk"
		return result
	var entrance := _find_entrance()
	if entrance.is_empty():
		result["reason"] = "sokaktan erisilebilir giris yok"
		return result
	result["layout"] = layout_id
	result["origin"] = Vector2i(ox, oz)
	result["size"] = Vector2i(w, h)
	result["floor_material"] = str(base_layout.get("floor", "parquet"))
	result["wall_material"] = str(base_layout.get("wall", "interior_plaster"))
	var door_asset := str(base_layout.get("door", "door_entrance_metal"))
	var door_id := "%s:kapi0" % building.id
	result.doors.append({"id": door_id, "cell": entrance.door, "floor": 0,
		"outward": entrance.outward, "asset": door_asset, "material": _door_material(door_asset),
		"open": _hash01(door_id) < 0.3, "rows": 3 if entrance.tall else 2})

	var levels := maxi(1, int(building.levels))
	var roof := not bool(building.get("pitched", false))
	# Merdiven cekirdegi: once zemin kat baglantisi, sonra odalar.
	var floor0 := {}
	if levels >= 2:
		for candidate: Dictionary in _core_candidates(entrance, levels):
			core = candidate
			floor0 = _plan_floor(0, entrance)
			if codes[_i(core.entry)] == FREE and _reachable(entrance.inner, core.entry):
				break
			core = {}
			floor0 = {}
		if core.is_empty():
			result["reason_upper"] = "merdiven cekirdegi sigmadi ya da girisle baglanamadi"
	if floor0.is_empty():
		floor0 = _plan_floor(0, entrance)
	var flights := 0
	if not core.is_empty():
		flights = (levels - 1 + (1 if roof else 0)) if bool(core.stack) else 1
		flights = mini(flights, levels - 1 + (1 if roof else 0))
	var reachable_floors := mini(levels, flights + 1)
	var all_furniture: Array = []
	var floors: Array = []
	floor0["fbase"] = 0
	all_furniture.append_array(floor0.furniture)
	floors.append(floor0)
	var variants: Dictionary = {}
	for k in range(1, levels):
		var fl: Dictionary
		if k >= reachable_floors:
			fl = _solid_floor(k)
		else:
			var v := (k - 1) % MAX_VARIANTS
			if not variants.has(v):
				variants[v] = _plan_floor(k, entrance)
			fl = _copy_floor(variants[v], k)
		fl["fbase"] = all_furniture.size()
		all_furniture.append_array(fl.furniture)
		floors.append(fl)
	result.floors = floors
	result.furniture = all_furniture
	if not core.is_empty():
		var cells: Array = []
		var tops := {}
		for c: Vector2i in core.steps:
			cells.append(_abs(c))
			tops[_abs(c)] = float(core.steps[c])
		var pillar: Array = []
		for c: Vector2i in core.pillar:
			pillar.append(_abs(c))
		var shaft: Array = []
		for c: Vector2i in core.get("shaft", []):
			shaft.append(_abs(c))
		result.stairs = {"template": core.name, "cells": cells, "tops": tops, "pillar": pillar, "shaft": shaft,
			"entry": _abs(core.entry), "exit": _abs(core.exit), "flights": flights, "roof": roof and flights >= levels,
			"stack": core.stack}
	result.accessible = reachable_floors
	result.ok = true
	return result


# ---------------------------------------------------------------------------
# Ayak izi
# ---------------------------------------------------------------------------
func _footprint() -> void:
	var lo: Vector2 = building.lo
	var hi: Vector2 = building.hi
	ox = floori(lo.x) - 1
	oz = floori(lo.y) - 1
	w = ceili(hi.x) - ox + 2
	h = ceili(hi.y) - oz + 2
	occ.resize(w * h)
	edge.resize(w * h)
	inner.resize(w * h)
	for lz in h:
		for lx in w:
			occ[lz * w + lx] = 1 if city._occupies(ox + lx, oz + lz, index) else 0
	for lz in h:
		for lx in w:
			var i := lz * w + lx
			if occ[i] == 0:
				continue
			for d in DIRS:
				if not _occ(Vector2i(lx, lz) + d):
					edge[i] = 1
					break
	# En buyuk ic bilesen: kopuk cepler dolu kalir.
	var best: Array = []
	var seen := PackedByteArray()
	seen.resize(w * h)
	for lz in h:
		for lx in w:
			var i := lz * w + lx
			if occ[i] == 0 or edge[i] == 1 or seen[i] == 1:
				continue
			var comp: Array = []
			var stack: Array = [Vector2i(lx, lz)]
			seen[i] = 1
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				comp.append(c)
				for d in DIRS:
					var n := c + d
					if _in(n) and occ[_i(n)] == 1 and edge[_i(n)] == 0 and seen[_i(n)] == 0:
						seen[_i(n)] = 1
						stack.append(n)
			if comp.size() > best.size():
				best = comp
	for c: Vector2i in best:
		inner[_i(c)] = 1


func _find_entrance() -> Dictionary:
	## Cephe hucresi: bir yani ic mekan, KARSI yani sokak. Dis zemin ile ic
	## doseme arasi en fazla bir basamak (0.55 m) olmali.
	var best := {}
	var best_score := INF
	var walkable := ["road", "sidewalk", "plaza", "ground", "park", "cemetery"]
	for lz in h:
		for lx in w:
			var c := Vector2i(lx, lz)
			if edge[_i(c)] == 0:
				continue
			for d in DIRS:
				var inside := c - d
				var outside := c + d
				if not _in(inside) or inner[_i(inside)] == 0 or _occ(outside):
					continue
				var o := _abs(outside)
				var info := city.column_info(o.x, o.y)
				if not info.kind in walkable or int(info.building) >= 0 or info.has("bridge") or bool(info.tree):
					continue
				var outside_y := city.surface_y(o.x, o.y)
				var diff := absf(outside_y - float(floor_y))
				if diff > MAX_STEP:
					continue
				var tall := outside_y > float(floor_y) + 0.05
				var score := diff * 4.0 + rng.randf() * 0.5 + (1.5 if tall else 0.0)
				if info.kind in ["road", "sidewalk"]:
					score -= 1.0
				if not _is_inner(inside - d) or not _is_inner(inside - d * 2):
					score += 1.5
				var side := Vector2i(d.y, d.x)
				if not (_in(c + side) and edge[_i(c + side)] == 1 and _in(c - side) and edge[_i(c - side)] == 1):
					score += 3.0
				if score < best_score:
					best_score = score
					best = {"door": _abs(c), "door_local": c, "inner": inside, "outward": d, "tall": tall}
	return best


# ---------------------------------------------------------------------------
# Merdiven cekirdegi
# ---------------------------------------------------------------------------
static func templates() -> Array:
	## Yerel sablonlar (d = +x ileri, yan = +y). t: basamak ustunun kat
	## dosemesine gore yuksekligi (m). entry: kat seviyesinde kalkis hucresi,
	## exit: bir ust kat seviyesinde varis hucresi.
	var u := {"name": "U", "stack": true, "pillar": [], "entry": Vector2i(0, 0), "exit": Vector2i(0, 1),
		"steps": {Vector2i(1, 0): 0.5, Vector2i(2, 0): 1.0, Vector2i(3, 0): 1.5, Vector2i(4, 0): 2.0,
			Vector2i(4, 1): 2.0, Vector2i(3, 1): 2.5, Vector2i(2, 1): 3.0, Vector2i(1, 1): 3.5}}
	var spiral := {"name": "spiral", "stack": true, "pillar": [Vector2i(1, 1)], "entry": Vector2i(0, 0),
		"exit": Vector2i(0, 0),
		"steps": {Vector2i(1, 0): 0.5, Vector2i(2, 0): 1.0, Vector2i(2, 1): 1.5, Vector2i(2, 2): 2.0,
			Vector2i(1, 2): 2.5, Vector2i(0, 2): 3.0, Vector2i(0, 1): 3.5}}
	var l_shape := {"name": "L", "stack": false, "pillar": [], "entry": Vector2i(0, 0), "exit": Vector2i(4, 4),
		"steps": {Vector2i(1, 0): 0.5, Vector2i(2, 0): 1.0, Vector2i(3, 0): 1.5, Vector2i(4, 0): 2.0,
			Vector2i(4, 1): 2.5, Vector2i(4, 2): 3.0, Vector2i(4, 3): 3.5}}
	var straight := {"name": "duz", "stack": false, "pillar": [], "entry": Vector2i(0, 0), "exit": Vector2i(8, 0),
		"steps": {Vector2i(1, 0): 0.5, Vector2i(2, 0): 1.0, Vector2i(3, 0): 1.5, Vector2i(4, 0): 2.0,
			Vector2i(5, 0): 2.5, Vector2i(6, 0): 3.0, Vector2i(7, 0): 3.5}}
	# Tirmanma merdiveni: dar/capraz ayak izinde 0.5 m basamak sigmiyorsa son
	# care. Tek hucrelik saft butun katlardan gecer; yaninda kat girisi.
	var ladder := {"name": "tirmanma", "stack": true, "ladder": true, "pillar": [], "steps": {},
		"shaft": [Vector2i(0, 0)], "entry": Vector2i(1, 0), "exit": Vector2i(1, 0)}
	return [u, spiral, l_shape, straight, ladder]


static func _orient(c: Vector2i, rot: int, mirror: bool) -> Vector2i:
	var p := Vector2i(c.x, -c.y) if mirror else c
	for _r in rot:
		p = Vector2i(-p.y, p.x)
	return p


func _core_candidates(entrance: Dictionary, levels: int) -> Array:
	## Uygun cekirdek yerlesimleri, iyiden kotuye (en fazla 6). Yigilabilir
	## sablonlar (U, spiral) once; L/duz yalnizca tek kol icin.
	var found: Array = []
	var cells: Array = []
	for lz in h:
		for lx in w:
			if inner[lz * w + lx] == 1:
				cells.append(Vector2i(lx, lz))
	# Deterministik karistir: buyuk binada ilk uygun yerlesimler yeterli.
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	var door_in: Vector2i = entrance.inner
	_free_total = cells.size()
	for template: Dictionary in templates():
		# Tek kol (L, duz) yalnizca yigilabilir sablon hic sigmadiysa denenir.
		if not bool(template.stack) and _has_stack(found):
			continue
		var per_template := 0
		_bfs_budget = 40
		for anchor: Vector2i in cells:
			if per_template >= 3 or _bfs_budget <= 0:
				break
			var placed := {}
			for variant in 8:
				placed = _place_template(template, anchor, variant / 2, variant % 2 == 1, door_in, entrance.outward)
				if not placed.is_empty() or _bfs_budget <= 0:
					break
			if not placed.is_empty():
				found.append(placed)
				per_template += 1
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	return found.slice(0, 6)


var _free_total := 0
var _bfs_budget := 0


static func _has_stack(found: Array) -> bool:
	for f: Dictionary in found:
		if bool(f.stack):
			return true
	return false


func _place_template(template: Dictionary, anchor: Vector2i, rot: int, mirror: bool, door_in: Vector2i,
		outward: Vector2i) -> Dictionary:
	var step_cells := {}
	var blocked := {}
	var against := 0
	for c: Vector2i in template.steps:
		var p := anchor + _orient(c, rot, mirror)
		if not _is_inner(p) or p == door_in or p == door_in - outward:
			return {}
		step_cells[p] = template.steps[c]
		blocked[p] = true
	var shaft: Array = []
	for c: Vector2i in template.get("shaft", []):
		var p := anchor + _orient(c, rot, mirror)
		if not _is_inner(p) or p == door_in or p == door_in - outward:
			return {}
		shaft.append(p)
		blocked[p] = true
	var pillar: Array = []
	for c: Vector2i in template.pillar:
		var p := anchor + _orient(c, rot, mirror)
		if not _is_inner(p) or p == door_in:
			return {}
		pillar.append(p)
		blocked[p] = true
	var entry := anchor + _orient(template.entry, rot, mirror)
	var exit := anchor + _orient(template.exit, rot, mirror)
	if not _is_inner(entry) or not _is_inner(exit) or blocked.has(entry) or blocked.has(exit):
		return {}
	for p: Vector2i in blocked:
		for d in DIRS:
			if _in(p + d) and edge[_i(p + d)] == 1:
				against += 1
	# Giristen kalkisa ve varistan katin geri kalanina baglanti (odalar yok iken).
	_bfs_budget -= 1
	if not _connected(door_in, entry, blocked):
		return {}
	# Varistan katin buyuk kismina ulasilmali (dar binada cekirdek bir ucta).
	if _count_reachable(exit, blocked) < maxi(4, int((_free_total - blocked.size()) * 0.45)):
		return {}
	var score := against * 1.0 + rng.randf() * 2.0 + (6.0 if bool(template.stack) else 0.0) - (12.0 if template.get("ladder", false) else 0.0)
	# Cok uzak cekirdek (kapidan > 25 m) koridoru uzatir; hafif ceza.
	score -= maxf(0.0, Vector2(entry - door_in).length() - 25.0) * 0.2
	return {"name": template.name, "stack": template.stack, "steps": step_cells, "pillar": pillar, "shaft": shaft,
		"entry": entry, "exit": exit, "score": score, "anchor": anchor}


func _connected(a: Vector2i, b: Vector2i, blocked: Dictionary) -> bool:
	var seen := {a: true}
	var stack: Array = [a]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if c == b:
			return true
		for d in DIRS:
			var n := c + d
			if _is_inner(n) and not blocked.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return false


func _count_reachable(a: Vector2i, blocked: Dictionary) -> int:
	var seen := {a: true}
	var stack: Array = [a]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS:
			var n := c + d
			if _is_inner(n) and not blocked.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen.size()


func _reachable(a: Vector2i, b: Vector2i) -> bool:
	## Planlanmis katta (kodlarla) a -> b yurunebilir mi?
	var seen := {a: true}
	var stack: Array = [a]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if c == b:
			return true
		for d in DIRS:
			var n := c + d
			if _in(n) and not seen.has(n) and codes[_i(n)] in [FREE, DOORWAY]:
				seen[n] = true
				stack.append(n)
	return false


static func core_block(t: float, u: int, flights: int) -> int:
	## Cekirdek basamak hucresinin (basamak yuksekligi t) mutlak satirdaki
	## icerigi: 0 bos, 1 tam basamak blogu, 2 yarim basamak. u: zemin kat
	## dosemesinin ustunden hucre satiri (0 = zemin katin ilk bos satiri).
	## Basamak ince tabladir: ust yuzeyi T = 4k + t; T tam ise tek hucre
	## (T-1), yarim ise alti tam (floor(T)-1) + ustu yarim (floor(T)).
	var k0 := floori((float(u) - t + 1.5) / FLOOR_HEIGHT)
	for k in [k0 - 1, k0, k0 + 1]:
		if k < 0 or k >= flights:
			continue
		var top: float = k * FLOOR_HEIGHT + t
		var whole := floori(top)
		if absf(top - whole) < 0.01:
			if u == whole - 1:
				return 1
		else:
			if u == whole - 1:
				return 1
			if u == whole:
				return 2
	return 0


# ---------------------------------------------------------------------------
# Kat plani
# ---------------------------------------------------------------------------
func _layout_for(k: int) -> Dictionary:
	if k > 0 and base_layout.has("upper"):
		var upper: Dictionary = Content.interiors.get("layouts", {}).get(str(base_layout.upper), {})
		if not upper.is_empty():
			return upper
	return base_layout


func _plan_floor(k: int, entrance: Dictionary) -> Dictionary:
	layout = _layout_for(k)
	rng.seed = hash("%s:ic:%d" % [building.id, k])
	furniture = []
	slot = 0
	codes = PackedByteArray()
	codes.resize(w * h)
	steps = PackedByteArray()
	steps.resize(w * h)
	fidx = PackedInt32Array()
	fidx.resize(w * h)
	fidx.fill(-1)
	fidx_up = PackedInt32Array()
	fidx_up.resize(w * h)
	fidx_up.fill(-1)
	rowmask = PackedByteArray()
	rowmask.resize(w * h)
	for i in w * h:
		if occ[i] == 0:
			codes[i] = OUT
		elif edge[i] == 1:
			codes[i] = FACADE
		elif inner[i] == 1:
			codes[i] = FREE
		else:
			codes[i] = FILL
	var entry: Vector2i = entrance.inner
	if k == 0:
		codes[_i(entrance.door_local)] = DOOR
	if not core.is_empty():
		for c: Vector2i in core.steps:
			codes[_i(c)] = STAIR
			steps[_i(c)] = int(round(float(core.steps[c]) / STEP))
		for c: Vector2i in core.pillar:
			codes[_i(c)] = STAIR
		for c: Vector2i in core.get("shaft", []):
			codes[_i(c)] = STAIR
		if k > 0:
			entry = core.exit
	# Ortak koridor: buyuk katta girisle (ya da merdiven varisiyla) ayni
	# hizada, uzun eksen boyunca 2 m'lik koridor ve iki yaninda duvar.
	var corridor: Dictionary = {}
	var region: Array = []
	for lz in h:
		for lx in w:
			if codes[lz * w + lx] == FREE:
				region.append(Vector2i(lx, lz))
	if region.size() >= CORRIDOR_MIN_CELLS and bool(layout.get("corridor", false)):
		corridor = _carve_corridor(region, entry)
		if not corridor.is_empty():
			region = region.filter(func(c: Vector2i) -> bool: return codes[_i(c)] == FREE and not corridor.has(c))
	var area_limits: Array = layout.get("room_area", [6, 22])
	_split(region, int(area_limits[0]), int(area_limits[1]), 0)
	# Oda bolme cizgisi girisi, cekirdek giris/cikisini ve onlerini kesmesin.
	var protect: Array = [entry]
	if k == 0:
		protect.append(entrance.inner - entrance.outward)
	if not core.is_empty():
		for c: Vector2i in [core.entry, core.exit]:
			protect.append(c)
			for d in DIRS:
				if _in(c + d) and codes[_i(c + d)] == WALL:
					protect.append(c + d)
	for c: Vector2i in protect:
		if _in(c) and codes[_i(c)] == WALL and not corridor.has(c):
			codes[_i(c)] = FREE
	var room_list := _connect_rooms(entry, corridor)
	var entry_room := -1
	for r in room_list.size():
		if room_list[r].has(entry):
			entry_room = r
	if entry_room < 0:
		room_list.append([entry])
		entry_room = room_list.size() - 1
	var types := {}
	var entry_type := str(layout.get("entry", "living"))
	var rest: Array = []
	for r in room_list.size():
		if r == entry_room:
			continue
		if not corridor.is_empty() and room_list[r].has(corridor.keys()[0]):
			types[r] = "corridor"
			continue
		rest.append(r)
	types[entry_room] = entry_type if corridor.is_empty() or not room_list[entry_room].has(corridor.keys()[0]) else "corridor"
	if room_list.size() == 1 and layout.has("single"):
		types[entry_room] = str(layout.single)
	rest.sort_custom(func(a: int, b: int) -> bool: return room_list[a].size() > room_list[b].size())
	if types[entry_room] == "corridor" and not rest.is_empty():
		types[rest[0]] = entry_type
		rest.remove_at(0)
	for spec: Array in layout.get("rooms", []):
		if rest.is_empty():
			break
		var pick: int = rest[0] if spec[1] != "small" else rest[rest.size() - 1]
		types[pick] = str(spec[0])
		rest.erase(pick)
	# Kalan odalar: yerlesimin tekrar listesi (buyuk katta ikinci daire).
	var cycle: Array = layout.get("repeat", [])
	var n := 0
	for r: int in rest:
		types[r] = str(cycle[n % cycle.size()]) if not cycle.is_empty() else entry_type
		n += 1
	var reserved := {entry: true}
	if k == 0:
		reserved[entrance.inner] = true
	if not core.is_empty():
		for c: Vector2i in [core.entry, core.exit]:
			reserved[c] = true
			for d in DIRS:
				if _in(c + d) and codes[_i(c + d)] == FREE:
					reserved[c + d] = true
	for c: Vector2i in corridor:
		reserved[c] = true
	for lz in h:
		for lx in w:
			var c := Vector2i(lx, lz)
			if codes[_i(c)] == DOORWAY:
				for d in DIRS:
					reserved[c + d] = true
	var required: Array = []
	for key: Vector2i in reserved:
		if _in(key) and codes[_i(key)] == FREE:
			required.append(key)
	var placer := _Placer.new(self, reserved, required, entry, k)
	var rooms_out: Array = []
	for r in room_list.size():
		var type_id: String = types.get(r, "storage")
		var abs_cells: Array = []
		for c: Vector2i in room_list[r]:
			abs_cells.append(_abs(c))
		rooms_out.append({"type": type_id, "cells": abs_cells, "area": room_list[r].size()})
		if type_id != "corridor":
			placer.furnish(room_list[r], type_id)
	return {"k": k, "codes": codes, "steps": steps, "fidx": fidx, "fidx_up": fidx_up, "rows": rowmask,
		"rooms": rooms_out, "entry": _abs(entry), "y": floor_y + k * FLOOR_HEIGHT, "furniture": furniture,
		"layout": str(layout.get("label", "")), "floor_mat": str(layout.get("floor", "parquet")),
		"wall_mat": str(layout.get("wall", "interior_plaster")), "solid": false, "variant": k,
		"use": str(building.class) if layout == base_layout else str(layout.get("use", "residential"))}


func _copy_floor(source: Dictionary, k: int) -> Dictionary:
	## Varyant katini baska bir kata tasir: plan dizileri paylasilir, mobilya
	## kayitlari (kimlik, kat, yukseklik) bu kata yeniden yazilir.
	if int(source.k) == k:
		return source
	var dy := (k - int(source.k)) * FLOOR_HEIGHT
	var items: Array = []
	for f: Dictionary in source.furniture:
		var copy := f.duplicate()
		copy.floor = k
		copy.id = str(f.id).replace(":f%d:" % int(source.k), ":f%d:" % k)
		var o: Vector3 = f.origin
		copy.origin = Vector3(o.x, o.y + dy, o.z)
		copy.erase("above_used")
		items.append(copy)
	var fl := source.duplicate()
	fl.k = k
	fl.y = floor_y + k * FLOOR_HEIGHT
	fl.furniture = items
	fl.variant = int(source.k)
	return fl


func _solid_floor(k: int) -> Dictionary:
	## Ulasilamayan kat: dolu hacim (loot yok), yine de cephesi pencereli.
	return {"k": k, "solid": true, "y": floor_y + k * FLOOR_HEIGHT, "furniture": [], "rooms": [],
		"codes": PackedByteArray(), "steps": PackedByteArray(), "fidx": PackedInt32Array(),
		"fidx_up": PackedInt32Array(), "rows": PackedByteArray(), "entry": Vector2i.ZERO,
		"floor_mat": "concrete", "wall_mat": "interior_plaster", "layout": "", "variant": k}


func _carve_corridor(region: Array, entry: Vector2i) -> Dictionary:
	## Giris hucresinden uzun eksen boyunca 2 hucre genis koridor; iki yani
	## duvar. Koridor hucreleri FREE kalir, kendi bileseni olur.
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	var set := {}
	for c: Vector2i in region:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		set[c] = true
	var along_x := (hi.x - lo.x) >= (hi.y - lo.y)
	var centre := (lo + hi) / 2
	var line := entry.y if along_x else entry.x
	var mid := centre.y if along_x else centre.x
	var second := line + (1 if mid >= line else -1)
	var cells := {}
	var a0 := lo.x if along_x else lo.y
	var a1 := hi.x if along_x else hi.y
	for a in range(a0, a1 + 1):
		for l: int in [line, second]:
			var c := Vector2i(a, l) if along_x else Vector2i(l, a)
			if set.has(c) and codes[_i(c)] == FREE:
				cells[c] = true
	if cells.size() < 8:
		return {}
	# Koridorun yaninda duvar (kapi Kruskal ile acilir).
	for c: Vector2i in cells:
		for d in DIRS:
			var n: Vector2i = c + d
			if set.has(n) and not cells.has(n) and codes[_i(n)] == FREE:
				codes[_i(n)] = WALL
	# Girisle koridor arasinda duvar kalmasin.
	for d in DIRS:
		var n: Vector2i = entry + d
		if _in(n) and codes[_i(n)] == WALL and (cells.has(n + d) or cells.has(entry)):
			codes[_i(n)] = FREE
			cells[n] = true
	if not cells.has(entry):
		var reach := false
		for d in DIRS:
			if cells.has(entry + d):
				reach = true
		if not reach:
			# Giris koridora bitisik degil: koridordan girise duz bir kol ac.
			var p := entry
			for _s in 40:
				var step := Vector2i(0, signi(line - p.y)) if along_x else Vector2i(signi(line - p.x), 0)
				if step == Vector2i.ZERO:
					break
				p += step
				if cells.has(p):
					break
				if _in(p) and codes[_i(p)] in [FREE, WALL]:
					codes[_i(p)] = FREE
					cells[p] = true
	return cells


func _split(cells: Array, min_area: int, max_area: int, depth: int) -> void:
	## BSP: alan sinirin ustundeyse uzun eksene dik bir duvar cizgisiyle bol.
	if cells.size() <= max_area or depth > 8:
		return
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c: Vector2i in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var span := hi - lo
	var axes: Array = [0, 1] if span.x >= span.y else [1, 0]
	for axis: int in axes:
		var a0 := lo.x if axis == 0 else lo.y
		var a1 := hi.x if axis == 0 else hi.y
		if a1 - a0 < 5:
			continue
		var middle := (a0 + a1) / 2
		var offsets: Array = [0, 1, -1, 2, -2] if rng.randf() < 0.5 else [0, -1, 1, -2, 2]
		for off: int in offsets:
			var p: int = middle + off
			# Oda en dar yerinde 2.5 m'den az olmasin (voxel: 3 hucre).
			if p - a0 < 3 or a1 - p < 3:
				continue
			var left: Array = []
			var right: Array = []
			var line: Array = []
			for c: Vector2i in cells:
				var v := c.x if axis == 0 else c.y
				if v < p:
					left.append(c)
				elif v > p:
					right.append(c)
				else:
					line.append(c)
			if left.size() < min_area or right.size() < min_area:
				continue
			for c: Vector2i in line:
				if codes[_i(c)] == FREE:
					codes[_i(c)] = WALL
			_split(left, min_area, max_area, depth + 1)
			_split(right, min_area, max_area, depth + 1)
			return


func _connect_rooms(entry: Vector2i, corridor: Dictionary = {}) -> Array:
	## Duvarlarla ayrilan bilesenleri en az gecitle girise bagla; baglanamayan
	## cep DOLU olur (orada loot uretilmez). Koridor varsa once odalar
	## koridora baglanir (daire kapisi). Donus: oda hucre listeleri.
	var comp := {}
	var comps: Array = []
	for lz in h:
		for lx in w:
			var start := Vector2i(lx, lz)
			if codes[_i(start)] != FREE or comp.has(start):
				continue
			var id := comps.size()
			var cells: Array = []
			var stack: Array = [start]
			comp[start] = id
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				cells.append(c)
				for d in DIRS:
					var n := c + d
					if _in(n) and codes[_i(n)] == FREE and not comp.has(n):
						comp[n] = id
						stack.append(n)
			comps.append(cells)
	var parent: Array = range(comps.size())
	var candidates: Array = []
	var corridor_comp := -1
	if not corridor.is_empty() and comp.has(corridor.keys()[0]):
		corridor_comp = comp[corridor.keys()[0]]
	for lz in h:
		for lx in w:
			var c := Vector2i(lx, lz)
			if codes[_i(c)] != WALL:
				continue
			for pair: Array in [[Vector2i(1, 0), Vector2i(-1, 0)], [Vector2i(0, 1), Vector2i(0, -1)]]:
				var a: Vector2i = c + pair[0]
				var b: Vector2i = c + pair[1]
				if comp.has(a) and comp.has(b) and comp[a] != comp[b]:
					candidates.append([c, comp[a], comp[b]])
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	if corridor_comp >= 0:
		# Koridora acilan gecitler once (kararli siralama korunur).
		var first: Array = []
		var later: Array = []
		for cand: Array in candidates:
			(first if cand[1] == corridor_comp or cand[2] == corridor_comp else later).append(cand)
		candidates = first + later
	for cand: Array in candidates:
		var ra := _root(parent, cand[1])
		var rb := _root(parent, cand[2])
		if ra == rb:
			continue
		var crowded := false
		for d in DIRS:
			var n: Vector2i = cand[0] + d
			if _in(n) and codes[_i(n)] == DOORWAY:
				crowded = true
		if crowded:
			continue
		codes[_i(cand[0])] = DOORWAY
		parent[ra] = rb
	var entry_root := _root(parent, comp[entry]) if comp.has(entry) else -1
	var rooms: Array = []
	for id in comps.size():
		if entry_root < 0 or _root(parent, id) != entry_root:
			for c: Vector2i in comps[id]:
				codes[_i(c)] = FILL
			continue
		rooms.append(comps[id])
	for lz in h:
		for lx in w:
			var c := Vector2i(lx, lz)
			if codes[_i(c)] == DOORWAY:
				var open := 0
				for d in DIRS:
					if _in(c + d) and codes[_i(c + d)] == FREE:
						open += 1
				if open < 2:
					codes[_i(c)] = WALL
	return rooms


static func _root(parent: Array, x: int) -> int:
	while parent[x] != x:
		x = parent[x]
	return x


# ---------------------------------------------------------------------------
# Yardimcilar
# ---------------------------------------------------------------------------
func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func _i(c: Vector2i) -> int:
	return c.y * w + c.x


func _occ(c: Vector2i) -> bool:
	return _in(c) and occ[_i(c)] == 1


func _is_inner(c: Vector2i) -> bool:
	return _in(c) and inner[_i(c)] == 1


func _abs(c: Vector2i) -> Vector2i:
	return Vector2i(ox + c.x, oz + c.y)


static func _hash01(key: String) -> float:
	return float(absi(hash(key)) % 10000) / 10000.0


static func _door_material(asset: String) -> String:
	if asset.contains("glass"):
		return "door_glass"
	if asset.contains("metal"):
		return "door_metal"
	return "door_wood"


static func cells_for(size_m: float) -> int:
	## Asset olcusu voxel olcusu DEGILDIR: 1.2 m'lik raf 1 hucreye (0.1 m
	## tasma), 1.4 m'lik gardirop 2 hucreye yerlesir.
	return maxi(1, ceili(size_m - 0.25))


# ---------------------------------------------------------------------------
# Mobilya yerlestirici
# ---------------------------------------------------------------------------
class _Placer:
	var p: InteriorPlanner
	var reserved: Dictionary
	var required: Array
	var entry: Vector2i
	var k := 0
	var room_cells: Dictionary = {}     # uzerinde calisilan oda
	var ports: Array = []               # odanin diger odalara/girise acilan hucreleri

	func _init(planner: InteriorPlanner, p_reserved: Dictionary, p_required: Array, p_entry: Vector2i,
			floor_index: int) -> void:
		p = planner
		reserved = p_reserved
		required = p_required
		entry = p_entry
		k = floor_index

	func furnish(cells: Array, type_id: String) -> void:
		var room: Dictionary = Content.interiors.get("rooms", {}).get(type_id, {})
		var density: float = float(p.layout.get("density", 1.0))
		var room_set := {}
		for c: Vector2i in cells:
			room_set[c] = true
		# BAGLANTI DENETIMI ODA ICINDE: mobilya yalnizca kendi odasini bolebilir;
		# diger odalar gecitlerle bagli ve gecit onleri ayrilmis. Butun kati her
		# mobilyada taramak buyuk binada karesel maliyetti (tek planda saniyeler).
		room_cells = room_set
		ports = []
		for c: Vector2i in cells:
			if c == entry:
				ports.append(c)
				continue
			for d in InteriorPlanner.DIRS:
				if p._in(c + d) and p.codes[p._i(c + d)] in [InteriorPlanner.DOORWAY, InteriorPlanner.DOOR]:
					ports.append(c)
					break
		for spec: Dictionary in room.get("items", []):
			var place := str(spec.get("place", "wall"))
			var chance: float = float(spec.get("chance", 1.0)) * (density if place != "ceiling" else 1.0)
			if p.rng.randf() > chance:
				continue
			var count: Array = spec.get("count", [1, 1])
			var n := p.rng.randi_range(int(count[0]), int(count[1]))
			var asset := str(spec.asset)
			if spec.has("alt") and p.rng.randf() < 0.4:
				asset = str(spec.alt)
			if place == "rows":
				_place_rows(asset, room_set, type_id, n)
				continue
			for _j in n:
				match place:
					"wall":
						_place_wall(asset, room_set, type_id, false, spec)
					"entry":
						_place_wall(asset, room_set, type_id, true, spec)
					"above":
						_place_above(asset, str(spec.get("on", "")), room_set, type_id)
					"center":
						_place_center(asset, room_set, type_id, spec)
					"ceiling":
						_place_ceiling(asset, cells, type_id)

	func _def(asset: String) -> Dictionary:
		return Content.interiors.get("furniture", {}).get(asset, {})

	func _solid(asset: String, spec: Dictionary) -> bool:
		if spec.has("solid"):
			return bool(spec.solid)
		return bool(_def(asset).get("solid", true))

	func _dims(asset: String) -> Vector3:
		var e := AssetLibrary.entry(asset)
		var d: Array = e.get("dimensions_m", [1.0, 1.0, 1.0])
		return Vector3(d[0], d[1], d[2])

	func _free(c: Vector2i, room_set: Dictionary) -> bool:
		return room_set.has(c) and p._in(c) and p.codes[p._i(c)] == InteriorPlanner.FREE and not reserved.has(c)

	func _barrier(c: Vector2i) -> bool:
		if not p._in(c):
			return true
		var code := p.codes[p._i(c)]
		return code in [InteriorPlanner.FACADE, InteriorPlanner.WALL, InteriorPlanner.FILL,
			InteriorPlanner.STAIR, InteriorPlanner.OUT, InteriorPlanner.SHAFT, InteriorPlanner.DOOR]

	func _place_wall(asset: String, room_set: Dictionary, room_type: String, near_entry: bool, spec: Dictionary) -> bool:
		var dims := _dims(asset)
		var cw := InteriorPlanner.cells_for(dims.x)
		var cd := InteriorPlanner.cells_for(dims.z)
		var options: Array = []
		for c: Vector2i in room_set:
			for d in InteriorPlanner.DIRS:
				if not _barrier(c + d) or (p._in(c + d) and p.codes[p._i(c + d)] in [InteriorPlanner.DOOR, InteriorPlanner.STAIR]):
					continue          # kapiya/merdivene sirtini veren dolap olmaz
				var facing := -d
				var along := Vector2i(facing.y, facing.x)
				options.append([c, facing, along])
				options.append([c, facing, -along])
		if near_entry:
			options.sort_custom(func(a: Array, b: Array) -> bool:
				return (a[0] - entry).length_squared() < (b[0] - entry).length_squared())
		else:
			for i in range(options.size() - 1, 0, -1):
				var j := p.rng.randi_range(0, i)
				var tmp: Variant = options[i]
				options[i] = options[j]
				options[j] = tmp
		var tries := 0
		for opt: Array in options:
			tries += 1
			if tries > 160:
				break
			var anchor: Vector2i = opt[0]
			var facing: Vector2i = opt[1]
			var along: Vector2i = opt[2]
			var rect: Array = []
			var ok := true
			for t in cw:
				for u in cd:
					var c := anchor + along * t + facing * u
					if not _free(c, room_set):
						ok = false
						break
					rect.append(c)
				if not ok:
					break
			if not ok:
				continue
			for t in cw:
				if not _barrier(anchor + along * t - facing):
					ok = false
					break
			if not ok:
				continue
			if _commit(asset, rect, facing, room_type, spec, false):
				return true
		return false

	func _place_center(asset: String, room_set: Dictionary, room_type: String, spec: Dictionary) -> bool:
		var dims := _dims(asset)
		var cw := InteriorPlanner.cells_for(dims.x)
		var cd := InteriorPlanner.cells_for(dims.z)
		var solid := _solid(asset, spec)
		var cells: Array = room_set.keys()
		var centroid := Vector2.ZERO
		for c: Vector2i in cells:
			centroid += Vector2(c)
		centroid /= maxf(1.0, cells.size())
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := Vector2(a).distance_squared_to(centroid)
			var db := Vector2(b).distance_squared_to(centroid)
			if da == db:
				return a.x < b.x or (a.x == b.x and a.y < b.y)
			return da < db)
		for anchor: Vector2i in cells:
			var rect: Array = []
			var ok := true
			for t in cw:
				for u in cd:
					var c := anchor + Vector2i(t, u)
					if (solid and not _free(c, room_set)) or not room_set.has(c):
						ok = false
					rect.append(c)
			if not ok:
				continue
			if solid:
				var touching := false
				for c: Vector2i in rect:
					for d in InteriorPlanner.DIRS:
						if _barrier(c + d) or (not rect.has(c + d) and p._in(c + d) and p.codes[p._i(c + d)] == InteriorPlanner.FURNITURE):
							touching = true
				if touching:
					continue
			if _commit(asset, rect, Vector2i(0, -1), room_type, spec, true):
				return true
		return false

	func _place_rows(asset: String, room_set: Dictionary, room_type: String, count: int) -> void:
		## Market reyonu: uzun eksene paralel raf siralari, arada 2 hucre koridor.
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		for c: Vector2i in room_set:
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		var along_x := (hi.x - lo.x) >= (hi.y - lo.y)
		var placed := 0
		var line := (lo.y if along_x else lo.x) + 2
		var line_end := (hi.y if along_x else hi.x) - 2
		while line <= line_end and placed < count:
			var a0 := (lo.x if along_x else lo.y) + 2
			var a1 := (hi.x if along_x else hi.y) - 2
			for a in range(a0, a1 + 1):
				if placed >= count:
					break
				var c := Vector2i(a, line) if along_x else Vector2i(line, a)
				if not _free(c, room_set):
					continue
				var facing := Vector2i(0, -1) if along_x else Vector2i(-1, 0)
				if _commit(asset, [c], facing, room_type, {}, true):
					placed += 1
			line += 3

	func _place_above(asset: String, on: String, room_set: Dictionary, room_type: String) -> bool:
		## Duvar montaji: alttaki esyanin hucresinin UST satirlarina.
		for f in range(p.furniture.size() - 1, -1, -1):
			var base: Dictionary = p.furniture[f]
			if base.asset != on or base.get("above_used", false):
				continue
			var cell: Vector2i = base.cells[0]
			var local := cell - Vector2i(p.ox, p.oz)
			if not room_set.has(local):
				continue
			base["above_used"] = true
			var mount: float = float(AssetLibrary.metadata(asset).get("mount_height_m", 1.4))
			var height := _dims(asset).y
			var lo_row := clampi(floori(mount), 0, InteriorPlanner.ROOM_ROWS - 1)
			var hi_row := clampi(ceili(mount + height) - 1, lo_row, InteriorPlanner.ROOM_ROWS - 1)
			_add(asset, [local], base.facing, room_type, lo_row, hi_row, mount, false, true)
			var access: Array = base.get("access", [])
			if access.is_empty():
				var front: Vector2i = local + base.facing
				if p._in(front) and p.codes[p._i(front)] == InteriorPlanner.FREE:
					access = [p._abs(front)]
					reserved[front] = true
					if not required.has(front):
						required.append(front)
			if access.is_empty() or not _still_connected([access[0] - Vector2i(p.ox, p.oz)]):
				p.furniture[p.furniture.size() - 1]["container"] = ""
			p.furniture[p.furniture.size() - 1]["access"] = access
			return true
		return false

	func _place_ceiling(asset: String, cells: Array, room_type: String) -> void:
		var centroid := Vector2.ZERO
		for c: Vector2i in cells:
			centroid += Vector2(c)
		centroid /= maxf(1.0, cells.size())
		var best: Vector2i = cells[0]
		for c: Vector2i in cells:
			if Vector2(c).distance_squared_to(centroid) < Vector2(best).distance_squared_to(centroid):
				best = c
		# Merdiven boslugunun ustune lamba asilmaz.
		if p.codes[p._i(best)] != InteriorPlanner.FREE:
			return
		var mount: float = float(AssetLibrary.metadata(asset).get("mount_height_m", 2.7))
		var top := minf(mount + _dims(asset).y, 2.98)
		p.furniture.append({"asset": asset, "cells": [p._abs(best)], "floor": k, "rows": [-1, -1],
			"material": "", "container": "", "solid": false, "facing": Vector2i(0, -1),
			"origin": Vector3(p.ox + best.x + 0.5, p.floor_y + k * InteriorPlanner.FLOOR_HEIGHT + top - _dims(asset).y, p.oz + best.y + 0.5),
			"yaw": 0.0, "room": room_type, "id": "%s:f%d:m%d" % [p.building.id, k, p.furniture.size()]})

	func _commit(asset: String, rect: Array, facing: Vector2i, room_type: String, spec: Dictionary, centered: bool) -> bool:
		var solid := _solid(asset, spec)
		var height := _dims(asset).y
		var hi_row := clampi(ceili(height - 0.1) - 1, 0, InteriorPlanner.ROOM_ROWS - 1)
		if not solid:
			_add(asset, rect, facing, room_type, -1, -1, 0.0, centered, false)
			return true
		for c: Vector2i in rect:
			p.codes[p._i(c)] = InteriorPlanner.FURNITURE
		var container := str(_def(asset).get("container", ""))
		var access: Array = []
		if container != "":
			for c: Vector2i in rect:
				for dir: Vector2i in ([facing, -facing] if centered else [facing]):
					var front: Vector2i = c + dir
					if p._in(front) and p.codes[p._i(front)] == InteriorPlanner.FREE and not rect.has(front):
						access.append(front)
		if (container != "" and access.is_empty()) or not _still_connected(access):
			for c: Vector2i in rect:
				p.codes[p._i(c)] = InteriorPlanner.FREE
			return false
		_add(asset, rect, facing, room_type, 0, hi_row, 0.0, centered, false)
		var access_abs: Array = []
		for a: Vector2i in access:
			access_abs.append(p._abs(a))
			reserved[a] = true
			if not required.has(a):
				required.append(a)
		p.furniture[p.furniture.size() - 1]["access"] = access_abs
		return true

	func _still_connected(extra: Array) -> bool:
		## Odanin portlari (gecit/giris onleri), odadaki zorunlu hucreler ve
		## extra (yeni erisim hucreleri) oda icinde birbirine bagli mi?
		if ports.is_empty():
			return extra.is_empty()
		var start: Vector2i = ports[0]
		if p.codes[p._i(start)] != InteriorPlanner.FREE:
			return false
		var seen := {start: true}
		var stack: Array = [start]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in InteriorPlanner.DIRS:
				var n := c + d
				if seen.has(n) or not room_cells.has(n) or p.codes[p._i(n)] != InteriorPlanner.FREE:
					continue
				seen[n] = true
				stack.append(n)
		for c: Vector2i in ports:
			if not seen.has(c):
				return false
		for c: Vector2i in required:
			if room_cells.has(c) and p.codes[p._i(c)] == InteriorPlanner.FREE and not seen.has(c):
				return false
		if extra.is_empty():
			return true
		for c: Vector2i in extra:
			if seen.has(c):
				return true
		return false

	func _add(asset: String, rect: Array, facing: Vector2i, room_type: String, lo_row: int, hi_row: int,
			mount: float, centered: bool, mounted: bool) -> void:
		var index := p.furniture.size()
		var def := _def(asset)
		var solid := lo_row >= 0
		var container := str(def.get("container", "")) if solid else ""
		var material := str(def.get("material", "furniture_wood")) if solid else ""
		var cells: Array = []
		var center := Vector2.ZERO
		for c: Vector2i in rect:
			cells.append(p._abs(c))
			center += Vector2(c) + Vector2(0.5, 0.5)
			if solid:
				var mask := 0
				for r in range(lo_row, hi_row + 1):
					mask |= 1 << r
				p.rowmask[p._i(c)] = p.rowmask[p._i(c)] | mask
				if mounted:
					p.fidx_up[p._i(c)] = index
				else:
					p.fidx[p._i(c)] = index
		center /= maxf(1.0, rect.size())
		var origin2 := center
		if not centered:
			var bounds := AssetLibrary.bounds(asset)
			var depth_cells := 0
			for c: Vector2i in rect:
				var rel: Vector2i = c - rect[0]
				depth_cells = maxi(depth_cells, absi(rel.x * facing.x + rel.y * facing.y) + 1)
			var back_center := center - Vector2(facing) * (depth_cells * 0.5)
			origin2 = back_center + Vector2(facing) * bounds.end.z
		var id := "%s:f%d:m%d" % [p.building.id, k, index]
		if container != "":
			id = "%s:f%d:s%d" % [p.building.id, k, p.slot]
			p.slot += 1
		p.furniture.append({"asset": asset, "cells": cells, "floor": k, "rows": [lo_row, hi_row],
			"material": material, "container": container, "solid": solid, "facing": facing,
			"origin": Vector3(p.ox + origin2.x, p.floor_y + k * InteriorPlanner.FLOOR_HEIGHT + mount, p.oz + origin2.y),
			"yaw": atan2(-float(facing.x), -float(facing.y)), "room": room_type, "id": id})
