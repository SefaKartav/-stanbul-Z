extends Node
## Kalici bolgesel zombi nufusu (sabit harita): yogunluk bantlari, dogus
## nefes alani, kurum nufusu (cift sayim yok), kalici temizlik, yavas dolma.

static var _city: CityGenerator


func _pop() -> Population:
	if _city == null:
		_city = CityGenerator.new(Content.blocks, "res://data/map/yeni_istanbul.json")
	var manager := ZombieManager.new()
	add_child(manager)
	var pop := Population.new()
	add_child(pop)
	pop.setup(_city, manager, _city.spawn_point())
	return pop


func test_zone_density_bands(t) -> void:
	var pop := _pop()
	var per_zone := {}
	for i in pop.budget.size():
		var c := Vector2((i % pop.n + 0.5) * Population.CELL, (i / pop.n + 0.5) * Population.CELL)
		var d := _city.district_at(c.x, c.y)
		if d.is_empty() or pop.budget[i] <= 0.0:
			continue
		# Tam kara hucresi ve kurum disi (kurum kendi tablosunu kullanir).
		var full := true
		for s: Vector2 in [Vector2(-40, -40), Vector2(40, -40), Vector2(-40, 40), Vector2(40, 40)]:
			if _city.district_at(c.x + s.x, c.y + s.y).is_empty():
				full = false
		if not full or c.distance_to(Vector2(_city.spawn_point().x, _city.spawn_point().z)) < 300.0:
			continue
		var list: Array = per_zone.get(d.zone, [])
		list.append(pop.budget[i] / (Population.CELL * Population.CELL / 1e6))
		per_zone[d.zone] = list
	for zone: String in per_zone:
		var list: Array = per_zone[zone]
		list.sort()
		var med: float = list[list.size() / 2]
		var band: Array = Content.zones[zone].density_km2
		print("  %s: medyan %.0f / km2 (%s)" % [zone, med, band])
		t.ok(med >= float(band[0]) * 0.95 and med <= float(band[1]) * 1.6, "%s yogunlugu bantta (%.0f)" % [zone, med])
	print("  toplam kalici nufus: %.0f" % pop.total_budget)
	t.ok(pop.total_budget > 8000.0, "sehir kalabalik (toplam %.0f)" % pop.total_budget)
	pop.manager.free()
	pop.free()


func test_spawn_breathing_room(t) -> void:
	var pop := _pop()
	var sp := _city.spawn_point()
	t.near(pop.alive(pop.cell_of(sp)), 0.0, 0.01, "dogus hucresi bos (100 m nefes alani)")
	t.ok(pop.density_at(sp) < 40.0, "dogus cevresi seyrek (%.0f/km2)" % pop.density_at(sp))
	var far := 0.0
	for p: Dictionary in _city.pois():
		if p.kind == "hospital":
			far = maxf(far, pop.density_at(Vector3(float(p.p[0]), 0, float(p.p[1]))))
	t.ok(far > 300.0, "kurum cevresi yogun (%.0f/km2)" % far)
	pop.manager.free()
	pop.free()


func test_institution_population_not_double_counted(t) -> void:
	var pop := _pop()
	var inst: Dictionary = Content.zones.institutions
	for p: Dictionary in _city.pois():
		if p.kind != "military":
			continue
		var c := pop.cell_of(Vector3(float(p.p[0]), 0, float(p.p[1])))
		var total := 0.0
		for i in pop.budget.size():
			if pop.table_of[i] == pop.table_of[c]:
				total += pop.budget[i]
		t.ok(total >= float(inst.military.count[0]) - 0.5 and total <= float(inst.military.count[1]) + 0.5,
			"askeri alan nufusu 70-120 araliginda (%.1f): semt butcesine eklenmez" % total)
		break
	pop.manager.free()
	pop.free()


func test_kills_persist_and_regrow_slowly(t) -> void:
	var pop := _pop()
	var i := 0
	for k in pop.budget.size():
		if pop.budget[k] > 10.0:
			i = k
			break
	var before := pop.alive(i)
	for _j in 5:
		var z := Zombie.new()
		z.set_meta("pop_cell", i)
		pop._on_killed(z)
		z.free()
	t.near(pop.alive(i), before - 5.0, 0.01, "olen zombi hucreden duser")
	var saved := pop.to_dict()
	var other := _pop()
	other.load_dict(saved)
	t.near(other.alive(i), before - 5.0, 0.01, "temizlik kayitta korunur")
	other.on_new_day()
	t.ok(other.alive(i) > before - 5.0 and other.alive(i) < before, "gunde yavas geri dolar (sinirsiz yeniden dogma yok)")
	t.ok(pop.wave_scale(Vector3.INF) == 1.0 and pop.wave_scale(_city.spawn_point()) >= 0.6, "dalga olcegi sinirli")
	for p: Population in [pop, other]:
		p.manager.free()
		p.free()
