extends RefCounted
## Mobilya basina loot: tek seferlik zar, kismi alma, tahrip, yenilenme,
## bina butcesi, tematik dagilim ve hedefleme kurallari.

const MAP := "res://data/map/kadikoy.json"

static var _city: CityGenerator


static func _get_city() -> CityGenerator:
	if _city == null:
		_city = CityGenerator.new(Content.blocks, MAP)
	return _city


static func _plan_with(city: CityGenerator, layout_id: String, skip: int = 0) -> Dictionary:
	for i in city.buildings.size():
		var plan := city.interior_plan(i)
		if plan.get("ok", false) and plan.layout == layout_id:
			if skip == 0:
				return plan
			skip -= 1
	return {}


static func _first_container(plan: Dictionary, type_id: String = "") -> Dictionary:
	for f: Dictionary in plan.furniture:
		if f.container != "" and (type_id == "" or f.container == type_id):
			return f
	return {}


static func _total(stacks: Array) -> int:
	var n := 0
	for s: ItemStack in stacks:
		n += s.quantity
	return n


func test_roll_happens_once(t) -> void:
	var city := _get_city()
	var reg := ContainerRegistry.new(city)
	var plan := _plan_with(city, "apartment")
	var f := _first_container(plan, "kitchen_cabinet")
	t.ok(not f.is_empty(), "mutfak dolabi olmali")
	reg.roll(plan, f, 1)
	var first := _describe(reg.items(f.id))
	reg.roll(plan, f, 1)
	reg.roll(plan, f, 5)
	t.eq(_describe(reg.items(f.id)), first, "ikinci zar icerigi degistirmemeli")
	t.ok(not reg.items(f.id).is_empty(), "'basic' mutfak dolabi bos baslamaz")
	# Kayit dongusu: ayni icerik geri gelir, yeniden zar atilmaz.
	var again := ContainerRegistry.new(city)
	again.load_dict(JSON.parse_string(JSON.stringify(reg.to_dict())))
	t.eq(_describe(again.items(f.id)), first, "kayit/yukle icerigi korur")
	again.roll(plan, f, 9)
	t.eq(_describe(again.items(f.id)), first, "yuklemeden sonra da zar atilmaz")
	# Ayni kimlik, sifir durum: ayni tohum -> ayni sonuc (kayit yukleyip tekrar denemek fayda vermez).
	var fresh := ContainerRegistry.new(city)
	fresh.roll(plan, f, 1)
	t.eq(_describe(fresh.items(f.id)), first, "zar kimlikten turer (tekrar denemek ayni sonucu verir)")


func test_partial_take_respects_capacity(t) -> void:
	var city := _get_city()
	var reg := ContainerRegistry.new(city)
	var plan := _plan_with(city, "market")
	var f := _first_container(plan, "market_shelf")
	reg.roll(plan, f, 1)
	var before := _total(reg.items(f.id))
	t.ok(before > 0, "market rafi dolu baslar")
	var tiny := Inventory.new(0.2, 2)       # neredeyse dolu canta
	var result := reg.take_all(f.id, tiny)
	var after := _total(reg.items(f.id))
	t.eq(after + _total(tiny.stacks), before, "hic esya kaybolmamali ya da cogalmamali")
	var big := Inventory.new(999.0, 99)
	reg.take(f.id, 0, 1, big)
	t.eq(_total(reg.items(f.id)) + _total(tiny.stacks) + _total(big.stacks), before, "tek adet alma da korunumlu")
	t.eq(reg.status(f), "items" if _total(reg.items(f.id)) > 0 else "empty", "durum icerikle tutarli")


func test_destroy_drops_once(t) -> void:
	var city := _get_city()
	var reg := ContainerRegistry.new(city)
	var plan := _plan_with(city, "apartment")
	var f := _first_container(plan, "wardrobe")
	if f.is_empty():
		f = _first_container(plan)
	reg.roll(plan, f, 1)
	var bag := Inventory.new(999.0, 99)
	if not reg.items(f.id).is_empty():
		reg.take(f.id, 0, 0, bag)
	var remaining := _total(reg.items(f.id))
	var debris := reg.destroy(plan, f, 1)
	t.eq(_total(debris), remaining, "enkaz kalan esyayi tasir; alinan geri gelmez")
	t.eq(reg.destroy(plan, f, 2).size(), 0, "ikinci tahrip bir sey dusurmez")
	t.eq(reg.status(f), "destroyed", "durum kirik")


func test_restock_rules(t) -> void:
	var city := _get_city()
	var reg := ContainerRegistry.new(city)
	var plan := _plan_with(city, "apartment")
	var f := _first_container(plan, "kitchen_cabinet")
	reg.roll(plan, f, 1)
	reg.take_all(f.id, Inventory.new(999.0, 99))
	t.eq(reg.status(f), "empty", "bosaldi")
	t.ok(not reg.can_restock(plan, f, 3), "6 gun dolmadan yenilenmez")
	t.ok(reg.can_restock(plan, f, 7), "6 gun sonra bir jeton")
	t.ok(reg.restock(plan, f, 7), "jetonla yeni arama doldurur")
	t.ok(not reg.items(f.id).is_empty(), "yenilenen dolap dolu")
	t.ok(not reg.can_restock(plan, f, 7), "jeton harcandi (container sayisiyla katlanmaz)")
	var other := {}
	for g: Dictionary in plan.furniture:
		if g.container != "" and g.id != f.id:
			other = g
			break
	if not other.is_empty():
		reg.roll(plan, other, 7)
		reg.take_all(other.id, Inventory.new(999.0, 99))
		t.ok(not reg.can_restock(plan, other, 8), "ayni binanin baska dolabi ayni jetonu tekrar kullanamaz")
	# Tavan: 100 gun bekleyince en fazla restock_max_tokens.
	t.eq(reg.restock_tokens(plan.id, 100), int(Content.containers.restock_max_tokens), "jeton birikimi tavanli")


func test_budget_is_per_building(t) -> void:
	## Bina toplam cekilis butcesi container sayisindan bagimsiz ~ sinif butcesi.
	var city := _get_city()
	var reg := ContainerRegistry.new(city)
	var checked := 0
	for layout_id: String in ["apartment", "market", "pharmacy"]:
		for skip in 4:
			var plan := _plan_with(city, layout_id, skip)
			if plan.is_empty():
				continue
			var alloc := reg.allocation(plan)
			var total := 0
			for v: int in alloc.values():
				total += v
			var budget: float = reg.building_budget(plan)
			checked += 1
			t.ok(total <= ceili(budget) + alloc.size() / 3 + 2, "%s butcesi asilmamali (%d / %.0f, %d container)" % [plan.id, total, budget, alloc.size()])
	t.ok(checked >= 6, "yeterli bina denetlendi")


func test_thematic_distribution(t) -> void:
	## Sabit tohumlarla cok sayida cekilis: eczanede ilac, gardiropta kumas,
	## mutfakta yiyecek baskin; silah evlerde nadir ama imkansiz degil.
	var rng := RandomNumberGenerator.new()
	var samples := {"pharmacy_shelf": ["medical"], "wardrobe": ["fabric"], "kitchen_cabinet": ["food", "water"],
		"market_shelf": ["food", "water"], "tool_cabinet": ["fastener", "tool", "metal"]}
	for type_id: String in samples:
		var def := ContainerRegistry.type_def(type_id)
		var hits := 0
		var total := 0
		var weapons := 0
		for seed_value in 400:
			rng.seed = seed_value * 7919 + 13
			var pool := ContainerRegistry._pick_pool(def.pools, rng, false)
			var stack := ContainerRegistry.pick_entry(Content.loot_tables[pool], rng)
			if stack == null:
				continue
			total += 1
			if stack.definition.category == "weapon":
				weapons += 1
			for tag: String in samples[type_id]:
				if stack.definition.has_tag(tag):
					hits += 1
					break
		var ratio := float(hits) / maxf(1.0, total)
		print("  %s: %%%d tematik, %d silah / %d" % [type_id, int(ratio * 100), weapons, total])
		t.ok(ratio >= 0.55, "%s tematik esya baskin olmali (%%%d)" % [type_id, int(ratio * 100)])
		t.ok(ratio < 1.0 or type_id == "pharmacy_shelf", "%s yalnizca tek tur vermemeli" % type_id)
		t.ok(float(weapons) / maxf(1.0, total) < 0.08, "%s silah nadir olmali" % type_id)
	# Her havuz gecerli esyalara bakar.
	for type_id: String in Content.containers.types:
		for pool: Array in Content.containers.types[type_id].pools:
			t.ok(Content.loot_tables.has(pool[0]), "%s havuzu var: %s" % [type_id, pool[0]])


func test_basic_supplies_not_pure_luck(t) -> void:
	## Ilk girilen dairede yiyecek/su bulunabilmeli: mutfak dolabinin ilk
	## cekilisi ana havuzdan, hic bos baslamaz.
	var city := _get_city()
	var found := 0
	var tried := 0
	for skip in 12:
		var plan := _plan_with(city, "apartment", skip)
		if plan.is_empty():
			continue
		var reg := ContainerRegistry.new(city)
		var any := false
		for f: Dictionary in plan.furniture:
			if f.container != "kitchen_cabinet":
				continue
			reg.roll(plan, f, 1)
			for s: ItemStack in reg.items(f.id):
				if s.definition.has_tag("food") or s.definition.has_tag("water"):
					any = true
		tried += 1
		if any:
			found += 1
	t.ok(tried >= 6, "yeterli daire")
	t.ok(found >= tried * 0.8, "dairelerin cogunda mutfakta yiyecek/su olmali (%d/%d)" % [found, tried])


func test_targeting_needs_line_of_sight_and_inside(t) -> void:
	## Cepheden/duvar arkasindan/kapali kapidan dolap hedeflenemez; iceride
	## bakilan dolap hedeflenir.
	var city := _get_city()
	var plan := _plan_with(city, "market")
	var world := VoxelWorld.new(Content.blocks)
	city.configure(world)
	world.generator = city
	var o: Vector2i = plan.origin
	var s: Vector2i = plan.size
	var y0: int = plan.floors[0].y
	for cz in range(VoxelWorld.chunk_of(Vector3i(0, 0, o.y - 4)).z, VoxelWorld.chunk_of(Vector3i(0, 0, o.y + s.y + 4)).z + 1):
		for cx in range(VoxelWorld.chunk_of(Vector3i(o.x - 4, 0, 0)).x, VoxelWorld.chunk_of(Vector3i(o.x + s.x + 4, 0, 0)).x + 1):
			for cy in range(VoxelWorld.chunk_of(Vector3i(0, y0 - 2, 0)).y, VoxelWorld.chunk_of(Vector3i(0, y0 + 6, 0)).y + 1):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	var view := InteriorView.new()
	view.setup(city, world, ContainerRegistry.new(city), func() -> int: return 1)
	# Iceriden: container'in erisim hucresinde durup ona bak.
	var f := {}
	for g: Dictionary in plan.furniture:
		if g.container != "" and int(g.floor) == 0 and not g.get("access", []).is_empty():
			f = g
			break
	var access: Vector2i = f.access[0]
	var feet := Vector3(access.x + 0.5, y0, access.y + 0.5)
	var eye := feet + Vector3(0, 1.62, 0)
	var cell: Vector2i = f.cells[0]
	var aim := (Vector3(cell.x + 0.5, y0 + 0.5, cell.y + 0.5) - eye).normalized()
	var target := view.find_target(eye, aim, feet)
	t.eq(target.get("kind", ""), "container", "iceriden bakilan dolap hedeflenir")
	# Kapi kapaliyken disaridan kapiya bakmak: kapi hedeflenir, dolap degil.
	var door: Dictionary = plan.doors[0]
	if view.door_state(plan, door) == "open":
		view.toggle_door(plan, door, Callable())
	var out: Vector2i = door.cell + door.outward
	var feet_out := Vector3(out.x + 0.5, city.surface_y(out.x, out.y), out.y + 0.5)
	var eye_out := feet_out + Vector3(0, 1.62, 0)
	var aim_in := Vector3(-door.outward.x, -0.25, -door.outward.y).normalized()
	var at_door := view.find_target(eye_out, aim_in, feet_out)
	t.eq(at_door.get("kind", ""), "door", "kapali kapi arkasindaki dolap degil kapi hedeflenir")
	# Disaridan, dolabin arkasindaki cepheye bakmak: hedef yok ya da "iceri gir".
	var hits := 0
	for g: Dictionary in plan.furniture:
		if g.container == "":
			continue
		var c: Vector2i = g.cells[0]
		for d: Vector2i in InteriorPlanner.DIRS:
			var outside := c + d * 2
			if city.building_at(outside.x, outside.y) >= 0:
				continue
			var fo := Vector3(outside.x + 0.5, y0, outside.y + 0.5)
			var eo := fo + Vector3(0, 1.62, 0)
			var tg := view.find_target(eo, (Vector3(c.x + 0.5, y0 + 0.5, c.y + 0.5) - eo).normalized(), fo)
			if tg.get("kind", "") == "container":
				hits += 1
	t.eq(hits, 0, "binanin disindan hicbir dolap aranamaz")
	view.free()


static func _describe(stacks: Array) -> String:
	var parts := PackedStringArray()
	for s: ItemStack in stacks:
		parts.append("%s:%d" % [s.definition.id, s.quantity])
	return ",".join(parts)


func test_search_interruption_policy(t) -> void:
	## Kesilen arama esya VERMEZ ama ilerlemeyi saklar; geri donunce kaldigi
	## yerden surer. Tamamlaninca bir kez `completed` gelir ve ilerleme sifirlanir.
	var city := _get_city()
	var reg := ContainerRegistry.new(city)
	var plan := _plan_with(city, "apartment")
	var f := _first_container(plan)
	var search := SearchSystem.new(reg)
	var done: Array = []
	search.completed.connect(func(_p: Dictionary, _f: Dictionary, _r: bool) -> void: done.append(1))
	var feet := Vector3(1, 0, 1)
	search.begin(plan, f, feet)
	var duration: float = search.session.duration
	search.update(duration * 0.5, feet)
	search.update(0.01, feet + Vector3(2.0, 0, 0))          # yerinden oynadi
	t.ok(not search.active(), "hareket aramayi keser")
	t.eq(done.size(), 0, "kesilen arama odul vermez")
	t.ok(absf(reg.progress(f.id) - 0.5) < 0.05, "ilerleme container'da saklanir (%.2f)" % reg.progress(f.id))
	search.begin(plan, f, feet)
	t.ok(search.progress() >= 0.45, "geri gelince kaldigi yerden surer")
	search.on_player_damaged()
	t.ok(not search.active(), "hasar aramayi keser")
	search.begin(plan, f, feet)
	search.update(duration, feet)
	t.eq(done.size(), 1, "tamamlaninca bir kez biter")
	t.eq(reg.progress(f.id), 0.0, "bitince ilerleme sifirlanir")
