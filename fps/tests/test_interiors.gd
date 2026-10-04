extends RefCounted
## Girilebilir bina icleri: plan kapsami ve GERCEK oyuncu govdesiyle
## (VoxelBody, 0.6 x 1.8 m) yurunebilirlik.

const MAP := "res://data/map/kadikoy.json"

static var _city: CityGenerator


static func _get_city() -> CityGenerator:
	if _city == null:
		_city = CityGenerator.new(Content.blocks, MAP)
	return _city


func test_plans_cover_supported_classes(t) -> void:
	var city := _get_city()
	var candidates := 0
	var ok := 0
	var reasons := {}
	var layouts := {}
	var containers := 0
	for i in city.buildings.size():
		if not bool(city.buildings[i].interior):
			continue
		candidates += 1
		var plan := city.interior_plan(i)
		if plan.ok:
			ok += 1
			for fl: Dictionary in plan.floors:
				for arr: String in ["fidx", "fidx_up"]:
					for v: int in fl[arr]:
						if v >= 0 and int(fl.fbase) + v >= plan.furniture.size():
							t.ok(false, "bina %d kat %d %s=%d >= mobilya %d" % [i, fl.k, arr, v, plan.furniture.size()])
							return
			layouts[plan.layout] = int(layouts.get(plan.layout, 0)) + 1
			for f: Dictionary in plan.furniture:
				if f.container != "":
					containers += 1
		else:
			reasons[plan.get("reason", "?")] = int(reasons.get(plan.get("reason", "?"), 0)) + 1
	print("  ic mekan: %d/%d bina, yerlesim %s, %d container, basarisiz %s" % [ok, candidates, layouts, containers, reasons])
	t.ok(candidates > 100, "aday bina olmali")
	t.ok(ok >= candidates * 0.6, "adaylarin cogu girilebilir olmali (%d/%d)" % [ok, candidates])
	for layout_id: String in ["apartment", "market", "pharmacy"]:
		t.ok(layouts.has(layout_id), "'%s' yerlesimi uretilmeli" % layout_id)


func test_plan_is_deterministic(t) -> void:
	var city := _get_city()
	var index := _first_ok(city, "apartment")
	var a := InteriorPlanner.build(city, index)
	var b := InteriorPlanner.build(city, index)
	t.eq(a.furniture.size(), b.furniture.size(), "ayni bina ayni mobilya sayisi")
	for i in a.furniture.size():
		t.eq(a.furniture[i].id, b.furniture[i].id, "kimlikler ayni (%d)" % i)
		t.eq(a.furniture[i].cells, b.furniture[i].cells, "hucreler ayni (%d)" % i)


func test_every_container_reachable_from_street(t) -> void:
	## Kapidan girip her container'in onune GERCEK govdeyle yurunebilmeli.
	var city := _get_city()
	var checked := 0
	var unreachable := 0
	for layout_id: String in ["apartment", "market", "pharmacy", "workshop", "security"]:
		var found := 0
		for i in city.buildings.size():
			if found >= 8:
				break
			var plan := city.interior_plan(i)
			if not plan.get("ok", false) or plan.layout != layout_id:
				continue
			found += 1
			var world := _world_around(city, plan)
			var door: Dictionary = plan.doors[0]
			_open_door(world, plan)
			var outside: Vector2i = door.cell + door.outward
			var reach := _walk(world, outside, city.surface_y(outside.x, outside.y), plan)
			for f: Dictionary in plan.furniture:
				if f.container == "" or int(f.floor) >= int(plan.accessible):
					continue
				checked += 1
				var any := false
				for a: Vector2i in f.get("access", []):
					if TestWalker.reached(reach, a, float(plan.floors[int(f.floor)].y)):
						any = true
				if not any:
					unreachable += 1
					print("  ulasilamayan: %s %s" % [f.id, f.asset])
	print("  %d container denetlendi, %d ulasilamaz" % [checked, unreachable])
	t.ok(checked > 10, "denetlenecek container olmali")
	t.eq(unreachable, 0, "her container kapidan yurunerek ulasilabilir olmali")


func test_stairs_reach_upper_floor(t) -> void:
	var city := _get_city()
	var index := -1
	for i in city.buildings.size():
		var plan := city.interior_plan(i)
		if plan.get("ok", false) and plan.accessible >= 2 and not plan.stairs.is_empty():
			index = i
			break
	if index < 0:
		t.ok(false, "merdivenli bina bulunamadi")
		return
	var plan := city.interior_plan(index)
	var world := _world_around(city, plan)
	var door: Dictionary = plan.doors[0]
	_open_door(world, plan)
	var outside: Vector2i = door.cell + door.outward
	var reach := _walk(world, outside, city.surface_y(outside.x, outside.y), plan)
	var exit: Vector2i = plan.stairs.exit
	t.ok(TestWalker.reached(reach, exit, float(plan.floors[1].y)),
		"merdivenden ust kata cikilmali (%s sablonu, varis y=%d)" % [plan.stairs.template, plan.floors[1].y])
	for k in plan.accessible:
		t.ok(TestWalker.floor_reached(reach, plan, k), "kat %d/%d yurunerek ulasilmali" % [k, plan.accessible])
	var head: Array = TestWalker.headroom_ok(world, reach, plan.stairs.tops, float(plan.floors[0].y))
	t.eq(int(head[0]), 0, "basamaklarda bas boslugu >= 2.05 m (en kotu %.2f m, %d nokta)" % [head[1], head[2]])


func test_door_state_is_consistent(t) -> void:
	## Kapi ac/kapa: carpisma, mermi/gorus ve zombi yol bulmasi AYNI veriden
	## okur; kapinin onunde govde varken kapanmaz; kirilan kapi bir daha kapanmaz.
	var city := _get_city()
	var plan := {}
	for i in city.buildings.size():
		var candidate := city.interior_plan(i)
		# Kapilarin %30'u acik baslar (terk edilmis sehir); kapali olani sec.
		if candidate.get("ok", false) and candidate.layout == "apartment" and not candidate.doors[0].open:
			plan = candidate
			break
	t.ok(not plan.is_empty(), "kapisi kapali baslayan apartman olmali")
	var world := _world_around(city, plan)
	var view := InteriorView.new()
	view.setup(city, world, ContainerRegistry.new(city), func() -> int: return 1)
	var nav := NavGrid.new(world, city.ground_height)
	var door: Dictionary = plan.doors[0]
	var y0 := float(plan.floors[0].y)
	var at := Vector3(door.cell.x + 0.5, y0 + 0.02, door.cell.y + 0.5)
	var outside := Vector3(door.cell.x + door.outward.x * 2 + 0.5, y0 + 1.2, door.cell.y + door.outward.y * 2 + 0.5)
	var inside := Vector3(door.cell.x - door.outward.x * 2 + 0.5, y0 + 1.2, door.cell.y - door.outward.y * 2 + 0.5)
	t.eq(view.door_state(plan, door), "closed", "kapi kapali baslar")
	t.ok(VoxelBody.is_blocked(world, at, 0.3, 1.8), "kapali kapidan govde gecmez")
	t.ok(not VoxelRay.line_clear(world, outside, inside), "kapali kapi mermi/gorusu keser")
	t.ok(int(nav.column(door.cell.x, door.cell.y)[0]) != int(y0), "kapali kapi zombi rotasinda yurunebilir degil")
	t.eq(view.toggle_door(plan, door, Callable()), "Kapi acildi", "acilir")
	t.ok(not VoxelBody.is_blocked(world, at, 0.3, 1.8), "acik kapidan govde gecer")
	t.ok(VoxelRay.line_clear(world, outside, inside), "acik kapidan mermi/gorus gecer")
	t.eq(int(nav.column(door.cell.x, door.cell.y)[0]), int(y0), "acik kapi zombi rotasina girer (takip eder)")
	var blocked := func(_lo: Vector3, _hi: Vector3) -> bool: return true
	t.eq(view.toggle_door(plan, door, blocked), "Kapinin onu dolu", "icinde govde varken kapanmaz")
	t.eq(view.door_state(plan, door), "open", "kapanamayan kapi acik kalir")
	t.eq(view.toggle_door(plan, door, Callable()), "Kapi kapandi", "kapanir")
	t.ok(VoxelBody.is_blocked(world, at, 0.3, 1.8), "yeniden kapanan kapi carpisir")
	# Silahla kirilma (herhangi bir kapi hucresi havaya doner): hepsi gider.
	world.set_block(Vector3i(door.cell.x, int(y0), door.cell.y), 0, VoxelWorld.ORIGIN_WORLD)
	t.eq(view.door_state(plan, door), "broken", "kirik kapi")
	t.ok(not VoxelBody.is_blocked(world, at, 0.3, 1.8), "kirik kapidan gecilir")
	t.eq(view.toggle_door(plan, door, Callable()), "Kapi kirik", "kirik kapi kapanmaz")
	view.free()


# --- yardimcilar ---
static func _open_door(world: VoxelWorld, plan: Dictionary) -> void:
	var door: Dictionary = plan.doors[0]
	for c in int(door.get("rows", 2)):
		world.set_block(Vector3i(door.cell.x, plan.floors[0].y + c, door.cell.y), 0, VoxelWorld.ORIGIN_WORLD)

static func _first_ok(city: CityGenerator, layout_id: String) -> int:
	for i in city.buildings.size():
		var plan := city.interior_plan(i)
		if plan.get("ok", false) and plan.layout == layout_id:
			return i
	return -1


static func _world_around(city: CityGenerator, plan: Dictionary) -> VoxelWorld:
	return TestWalker.world_around(city, plan, int(city.buildings[plan.index].top_y) + 2)


static func _walk(world: VoxelWorld, start: Vector2i, start_y: float, plan: Dictionary) -> Dictionary:
	## 3B govde yurumesi (bkz. TestWalker): ust uste merdiven kollari dogru izlenir.
	var o: Vector2i = plan.origin
	var s: Vector2i = plan.size
	var top := float(CityGenerator.FLOOR_HEIGHT * plan.floors.size() + int(plan.floors[0].y) + 2)
	return TestWalker.walk(world, start, start_y, o - Vector2i(2, 2), o + s + Vector2i(2, 2),
		float(plan.floors[0].y) - 3.0, top)