extends RefCounted
## Sabit kurgusal harita (yeni_istanbul): sinirlar, kararlilik, kurumlar,
## ulasilabilirlik (GERCEK oyuncu govdesi), baglamsal loot, dogus guvenligi.

const MAP := "res://data/map/yeni_istanbul.json"
const KINDS := {"military": 3, "checkpoint": 8, "hospital": 4, "clinic": 8, "pharmacy": 24, "school": 12, "prison": 2,
	"historic": 8}
## Kurum -> planinda bulunmasi gereken container turlerinden en az biri (tema).
const THEME := {"school": ["school_locker", "school_shelf", "lab_cabinet"], "prison": ["prison_locker"],
	"military": ["military_crate"], "hospital": ["hospital_cabinet", "pharmacy_shelf"],
	"pharmacy": ["pharmacy_shelf", "pharmacy_counter", "medicine_cabinet"], "clinic": ["medical_chest", "medicine_cabinet", "pharmacy_shelf"]}

static var _city: CityGenerator
static var _index: Dictionary = {}


static func _get_city() -> CityGenerator:
	if _city == null:
		var t0 := Time.get_ticks_msec()
		_city = CityGenerator.new(Content.blocks, MAP)
		print("  yeni_istanbul yukleme: %d ms, %d bina, %d yol segmenti" % [Time.get_ticks_msec() - t0,
			_city.buildings.size(), _city.roads.size()])
		for i in _city.buildings.size():
			_index[str(_city.buildings[i].id)] = i
	return _city


static func _hash(city: CityGenerator) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for b: Dictionary in city.buildings:
		ctx.update(("%s|%s|%d|%d|%.1f,%.1f;" % [b.id, b["class"], b.levels, b.base_y, b.lo.x, b.lo.y]).to_utf8_buffer())
	for r: Dictionary in city.roads:
		ctx.update(("%.1f,%.1f,%.1f,%.1f;" % [r.a.x, r.a.y, r.b.x, r.b.y]).to_utf8_buffer())
	for p: Dictionary in city.pois():
		ctx.update(("%s|%s;" % [p.kind, str(p.p)]).to_utf8_buffer())
	return ctx.finish().hex_encode()


func test_bounds_and_fixed_identity(t) -> void:
	var city := _get_city()
	t.eq(city.map_id, "yeni_istanbul", "harita kimligi")
	t.eq(Vector2i(city.width, city.height), Vector2i(10000, 10000), "10 x 10 km (1 birim = 1 m)")
	t.eq(int(city.data.get("world_version", 0)), 1, "surumlu dunya verisi")
	t.ok(bool(city.data.get("fictional", false)), "kurgusal (OSM/gercek koordinat yok)")
	t.ok(not city.data.has("transform"), "cografi donusum tasimaz")
	t.ok(str(city.data.get("content_hash", "")).length() == 64, "icerik hash'i kayitli")
	t.ok(city.border > 0, "sinir bandi tanimli")
	t.eq(city.border_distance(5000, 5000), 5000.0 - city.border, "sinira uzaklik")
	t.ok(not city.is_inside(10, 5000) and city.is_inside(200, 5000), "kenar bandi girilemez, ici acik")
	var stats: Dictionary = city.data.get("stats", {})
	t.near(float(stats.get("water_km2", 0)), 20.0, 0.5, "su ~20 km2")
	var zones: Dictionary = stats.get("zone_km2", {})
	for z: String in {"historic": 12.0, "residential": 22.0, "commercial": 10.0, "industrial": 10.0, "green": 12.0,
			"institutional": 14.0}:
		t.near(float(zones.get(z, 0)), {"historic": 12.0, "residential": 22.0, "commercial": 10.0, "industrial": 10.0,
			"green": 12.0, "institutional": 14.0}[z], 0.6, "%s alani hedefte" % z)
	var cov: Dictionary = stats.get("coverage_pct", {})
	var bands := {"historic": [45, 60], "residential": [30, 45], "commercial": [35, 50], "industrial": [20, 35],
		"institutional": [15, 30], "green": [0, 5]}
	for z: String in bands:
		t.ok(float(cov.get(z, -1)) >= bands[z][0] and float(cov.get(z, -1)) <= bands[z][1],
			"%s kaplama %%%s bandinda %s" % [z, cov.get(z), bands[z]])


func test_same_version_same_world(t) -> void:
	## Ayni surum: yeni oyunlar ayni yol/bina/POI hash'ini verir.
	var a := _hash(_get_city())
	var other := CityGenerator.new(Content.blocks, MAP)
	t.eq(_hash(other), a, "ikinci yukleme ayni dunya")


func test_every_institution_exists(t) -> void:
	var city := _get_city()
	var counts := {}
	var families := {}
	for p: Dictionary in city.pois():
		counts[p.kind] = int(counts.get(p.kind, 0)) + 1
		if p.kind == "historic":
			families[str(p.get("family", ""))] = true
		for id: Variant in p.get("buildings", []):
			t.ok(_index.has(str(id)), "POI binasi haritada: %s" % id)
	for kind: String in KINDS:
		t.eq(int(counts.get(kind, 0)), int(KINDS[kind]), "%s sayisi" % kind)
	for fam: String in ["tower", "dome", "palace", "cistern", "wall", "han", "waterfront_mansion", "square"]:
		t.ok(families.has(fam), "tarihi odak ailesi: %s" % fam)


func test_institutions_enterable_with_themed_loot(t) -> void:
	## Her kurum turunden bir bina: kapidan GERCEK govdeyle girilir, tema
	## container'larinin onune ve kullanilan ust katlara yurunur.
	var city := _get_city()
	for kind: String in THEME:
		var done := false
		for p: Dictionary in city.pois():
			if done:
				break
			if p.kind != kind:
				continue
			for id: Variant in p.get("buildings", []):
				var plan := city.interior_plan(int(_index[str(id)]))
				if not plan.get("ok", false):
					continue
				var world := TestWalker.world_around(city, plan, int(city.buildings[plan.index].top_y) + 2)
				var door: Dictionary = plan.doors[0]
				for c in int(door.get("rows", 2)):
					world.set_block(Vector3i(door.cell.x, plan.floors[0].y + c, door.cell.y), 0, VoxelWorld.ORIGIN_WORLD)
				var outside: Vector2i = door.cell + door.outward
				var o: Vector2i = plan.origin
				var s: Vector2i = plan.size
				var top := float(CityGenerator.FLOOR_HEIGHT * plan.floors.size() + int(plan.floors[0].y) + 2)
				var reach := TestWalker.walk(world, outside, city.surface_y(outside.x, outside.y), o - Vector2i(2, 2),
					o + s + Vector2i(2, 2), float(plan.floors[0].y) - 3.0, top)
				var themed := 0
				var unreachable := 0
				for f: Dictionary in plan.furniture:
					if f.container == "" or int(f.floor) >= int(plan.accessible):
						continue
					var any := false
					for a: Vector2i in f.get("access", []):
						if TestWalker.reached(reach, a, float(plan.floors[int(f.floor)].y)):
							any = true
					if not any:
						unreachable += 1
					elif str(f.container) in THEME[kind]:
						themed += 1
				for k in plan.accessible:
					t.ok(TestWalker.floor_reached(reach, plan, k), "%s kat %d/%d yurunerek" % [kind, k, plan.accessible])
				t.eq(unreachable, 0, "%s: her container ulasilir" % kind)
				t.ok(themed > 0, "%s: baglamsal loot container'i var (%s)" % [kind, THEME[kind]])
				print("  %s %s: %d kat, %d tema container" % [kind, id, plan.accessible, themed])
				done = true
				break
		t.ok(done, "%s: girilebilir bina bulundu" % kind)


func test_themed_loot_differs(t) -> void:
	## Kurum turu loot'u: okul kitap/alet/gida, hapishane metal/guvenlik,
	## askeri muhimmat, hastane tibbi. Havuz tablolari gercek veriden.
	var rng := RandomNumberGenerator.new()
	var tags := {"school_locker": ["paper", "food", "tool", "electronic", "chemical"], "prison_locker": ["metal", "lock", "fabric", "fastener", "food"],
		"military_crate": ["ammo", "explosive_filler", "armor_raw", "weapon", "military", "food"], "hospital_cabinet": ["medical", "syringe", "chemical"]}
	for type_id: String in tags:
		var def := ContainerRegistry.type_def(type_id)
		var hits := 0
		var total := 0
		for seed_value in 200:
			rng.seed = seed_value * 31 + 7
			var pool := ContainerRegistry._pick_pool(def.pools, rng, false)
			var stack := ContainerRegistry.pick_entry(Content.loot_tables[pool], rng)
			if stack == null:
				continue
			total += 1
			for tag: String in tags[type_id]:
				if stack.definition.has_tag(tag) or stack.definition.category == tag:
					hits += 1
					break
		t.ok(total > 0 and float(hits) / total >= 0.45, "%s tematik (%d/%d)" % [type_id, hits, total])


func test_spawn_safety_and_crossings(t) -> void:
	var city := _get_city()
	var sp := city.spawn_point()
	var water := INF
	for w: Dictionary in city.data.get("water_points", []):
		water = minf(water, Vector2(float(w.p[0]), float(w.p[1])).distance_to(Vector2(sp.x, sp.z)))
	var pharmacy := INF
	for p: Dictionary in city.pois():
		if p.kind == "pharmacy":
			pharmacy = minf(pharmacy, Vector2(float(p.p[0]), float(p.p[1])).distance_to(Vector2(sp.x, sp.z)))
	t.ok(water < 120.0, "dogusta su noktasi yakin (%.0f m)" % water)
	t.ok(pharmacy > 150.0 and pharmacy < 450.0, "ilk ihtiyac noktasi 2-4 dk yurume (%.0f m)" % pharmacy)
	t.eq(city.district_at(sp.x, sp.z).get("id", ""), "rihtim", "dogus Rihtim semtinde")
	t.ok(city.bridges.size() >= 1, "asma kopru")
	var crossings := 0
	for p: Dictionary in city.pois():
		if p.kind == "bridge":
			crossings += 1
	t.ok(crossings >= 4, "bogaz/halic icin birden cok gecit (%d): tek dar bogaz yok" % crossings)
	for id: String in ["rihtim_iskele", "feneralti_burnu", "liman_gari", "carsibasi_meydan", "saraykapi_iskele",
			"bademlik_sahil", "kalebend_sahil", "martikoy_sahil"]:
		t.ok(city.data.places.has(id), "gorev yeri tanimli: %s" % id)


func test_quest_anchors_resolve_on_new_and_old_maps(t) -> void:
	## Gorev capalari yeni POI kimlikleridir; eski harita kimlik -> eski ad tablosuyla cozer.
	var ids := {}
	for q: Dictionary in Content.quests_source.get("main", []) + Content.quests_source.get("side", []):
		for o: Dictionary in q.get("objectives", []):
			for part: String in str(o.get("anchor", "")).split(":"):
				if part.contains("_") and not part.contains("|"):
					ids[part] = true
	var city := _get_city()
	var legacy: Dictionary = Content.place_roles.get("maltepe_besiktas", {}).get("places", {})
	for id: String in ids:
		t.ok(city.data.places.has(id), "yeni haritada yer: %s" % id)
		t.ok(legacy.has(id), "eski harita karsiligi: %s" % id)
