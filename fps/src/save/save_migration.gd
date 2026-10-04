class_name SaveMigration
extends RefCounted
## OLCEK GOCU: sikistirilmis (0.65) haritanin kaydini 1:1 haritaya tasir.
##
## Kural (Claude Code gelistirme promptu, bolum 10):
##   * Konum rastgele 1/0.65 ile carpilmaz: eski kayit konumu ESKI donusumle
##     cografi koordinata (enlem/boylam), oradan YENI haritanin donusumuyle
##     oyun konumuna cevrilir (data/map/legacy_transforms.json).
##   * Kararli kimlikler korunur: bina kimligi (OSM "w123") ayni; kapi
##     kimlikleri ayni. Oyuncu, arac, yerdeki esya, us merkezi, yerlestirilen
##     istasyon ve hedef isareti cografi olarak tasinir.
##   * Topolojik olarak tasinamayan veri GIZLENMEZ: blok farklari (kirilan/
##     konan hucreler) yeni izgarada ayni binaya denk gelmez; sayilari
##     raporlanir, kaynak kayit yedek dosyada korunur. Zombiler yeniden
##     dogar. Eski dolap icerikleri yerine "aranmis bina" orani aktarilir:
##     aranmis binanin ayni orandaki dolaplari bos gelir (ikinci kez odul yok).
##   * Kaynak kayit dosyasi Game tarafinda "<yuva>_olcek065_yedek" olarak
##     kopyalanir; goc kopyada yapilir, ilk kayitta yeni bicim yazilir.

const LEGACY := "res://data/map/legacy_transforms.json"


static func legacy_entry(map_id: String) -> Dictionary:
	var errors: Array = []
	var data: Variant = ContentValidator.load_json(LEGACY, errors)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data.get(map_id, {})


static func applies(data: Dictionary, map_id: String, generator_version: int) -> bool:
	var world: Dictionary = data.get("world", {})
	if str(world.get("map_id", "")) != map_id or generator_version < 3:
		return false
	var saved := int(world.get("generator_version", -1))
	var entry := legacy_entry(map_id)
	if entry.is_empty():
		return false
	for v: Variant in entry.get("generator_versions", []):
		if int(v) == saved:      # JSON sayilari float; tam sayi olarak karsilastir
			return true
	return false


static func migrate(data: Dictionary, city: CityGenerator) -> Dictionary:
	## `data` yerinde degistirilir. Donus: rapor.
	var map_id := str(data.get("world", {}).get("map_id", ""))
	var old := GeoTransform.from_map(legacy_entry(map_id))
	var report := {"from_generator": int(data.get("world", {}).get("generator_version", -1)),
		"transform_from": old.to_dict(), "transform_to": city.geo.to_dict(), "moved": {}, "dropped": {}}
	var conv := func(p: Vector3) -> Vector3:
		var geo := old.inverse(Vector2(p.x, p.z))
		var n := city.geo.forward(geo.x, geo.y)
		return Vector3(n.x, city.surface_y(floori(n.x), floori(n.y)) + 0.1, n.y)

	# --- oyuncu ---
	var body: Dictionary = data.get("player", {}).get("body", {})
	if body.has("position"):
		var p: Array = body.position
		var before := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var after: Vector3 = _open_spot(city, conv.call(before))
		body.position = [after.x, after.y, after.z]
		report.moved["player"] = 1
		var geo := old.inverse(Vector2(before.x, before.z))
		report["player_geo"] = [geo.y, geo.x]
		report["player_new"] = [after.x, after.z]
	# --- hedef isareti ---
	var w: Array = data.get("waypoint", [])
	if w.size() == 3:
		var q: Vector3 = conv.call(Vector3(float(w[0]), float(w[1]), float(w[2])))
		data.waypoint = [q.x, q.y, q.z]
	# --- yerdeki esya ---
	var n := 0
	for entry: Dictionary in data.get("pickups", {}).get("entries", []):
		var p: Array = entry.get("p", [0, 0, 0])
		var q: Vector3 = _open_spot(city, conv.call(Vector3(float(p[0]), float(p[1]), float(p[2]))))
		entry.p = [q.x, q.y + 0.1, q.z]
		n += 1
	report.moved["pickups"] = n
	# --- araclar: konum tasinir; bina icine dusen arac en yakin yola ---
	n = 0
	for entry: Dictionary in data.get("vehicles", {}).get("entries", []):
		var p: Array = entry.get("p", [0, 0, 0])
		var q: Vector3 = _open_spot(city, conv.call(Vector3(float(p[0]), float(p[1]), float(p[2]))), ["road"])
		entry.p = [q.x, q.y + 0.05, q.z]
		n += 1
	report.moved["vehicles"] = n
	# --- us merkezleri ve yerlestirilenler ---
	n = 0
	for base: Dictionary in data.get("bases", {}).get("bases", []):
		if base.has("seed"):
			var s: Array = base.seed
			var q: Vector3 = conv.call(Vector3(float(s[0]) + 0.5, 0.0, float(s[1]) + 0.5))
			base.seed = [floori(q.x), floori(q.z), floori(q.y)]
			# Barikatlar blok farkiydi ve tasinamadi: us ACIK baslar (oyuncu kapatir).
			base.breached = true
			n += 1
	report.moved["bases"] = n
	n = 0
	for entry: Dictionary in data.get("placeables", {}).get("entries", []):
		if entry.has("cell"):
			var c: Array = entry.cell
			var q: Vector3 = conv.call(Vector3(float(c[0]) + 0.5, float(c[1]), float(c[2]) + 0.5))
			entry.cell = [floori(q.x), floori(q.y), floori(q.z)]
			n += 1
	report.moved["placeables"] = n
	# --- blok farklari: tasinamaz (yeni izgara) -- raporlanir ---
	var voxels: Dictionary = data.get("world", {}).get("voxels", {})
	report.dropped["modified_cells"] = (voxels.get("modified", []) as Array).size()
	report.dropped["damaged_cells"] = (voxels.get("damage", []) as Array).size()
	data.world.voxels = {}
	var z: Variant = data.get("zombies", {})
	report.dropped["zombies"] = (z.get("zombies", []) as Array).size() if typeof(z) == TYPE_DICTIONARY else 0
	data.zombies = {}
	# --- dolaplar: bina bazli aranma orani ---
	var searched := {}
	var total := {}
	for id: String in data.get("containers", {}).get("states", {}):
		var bid := id.get_slice(":f", 0)
		total[bid] = int(total.get(bid, 0)) + 1
		if bool(data.containers.states[id].get("r", false)):
			searched[bid] = int(searched.get(bid, 0)) + 1
	for bid: String in data.get("buildings", {}):
		# v1: bina arama haklari
		if int(data.buildings[bid].get("searched", 0)) > 0:
			searched[bid] = int(data.buildings[bid].searched)
	report.moved["searched_buildings"] = searched.size()
	data["containers"] = {"states": {}, "clock": data.get("containers", {}).get("clock", {}), "migrated_buildings": searched}
	data.erase("buildings")
	data.world.generator_version = CityGenerator.GENERATOR_VERSION
	data["migration"] = report
	return report


static func _open_spot(city: CityGenerator, p: Vector3, kinds: Array = ["road", "sidewalk", "plaza", "ground", "park"]) -> Vector3:
	## Tasinan nokta bina/deniz icine dustuyse en yakin acik ve oynanabilir hucre.
	var cx := floori(p.x)
	var cz := floori(p.z)
	for r in range(0, 60):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var info := city.column_info(cx + dx, cz + dz)
				if info.kind in kinds and int(info.building) < 0 and not info.has("bridge") \
						and city.is_inside(cx + dx, cz + dz) and not bool(info.tree):
					return Vector3(cx + dx + 0.5, city.surface_y(cx + dx, cz + dz) + 0.1, cz + dz + 0.5)
	return p
