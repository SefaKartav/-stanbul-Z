extends RefCounted
## Maltepe-Besiktas koridoru (harita bicimi v2) ve 15 Temmuz Sehitler Koprusu.
##
## Harita buyuk oldugu icin bir kez yuklenir ve testler arasinda paylasilir.

const MAP := "res://data/map/maltepe_besiktas.json"

static var _city: CityGenerator
static var _load_ms := 0.0


static func _get_city() -> CityGenerator:
	if _city == null:
		var t0 := Time.get_ticks_usec()
		_city = CityGenerator.new(Content.blocks, MAP)
		_load_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return _city


static func _project(city: CityGenerator, lat: float, lon: float) -> Vector2i:
	## Harita aracinin izdusumu (build_corridor.py `project`).
	## TEK donusum: tools/geo.py = GeoTransform (haritadaki "transform").
	var p := city.geo.forward(lon, lat)
	return Vector2i(floori(p.x), floori(p.y))


func test_corridor_loads(t) -> void:
	var city := _get_city()
	print("  koridor yukleme: %.0f ms, %d bina, %d yol segmenti" % [_load_ms, city.buildings.size(), city.roads.size()])
	t.eq(city.format, 3, "harita bicimi v3 (1:1)")
	t.near(float(city.data.scale), 1.0, 0.0001, "olcek 1.0: 1 birim = 1 m")
	t.ok(city.buildings.size() > 20000, "binalar yuklenmeli (%d)" % city.buildings.size())
	t.ok(_load_ms < 15000.0, "yukleme 15 sn'nin altinda olmali (%.0f ms)" % _load_ms)
	var spawn := city.spawn_point()
	var info := city.column_info(floori(spawn.x), floori(spawn.z))
	t.ok(info.kind in ["road", "sidewalk", "plaza"], "dogus acik bir yerde olmali (%s)" % info.kind)
	t.ok(city.is_inside(floori(spawn.x), floori(spawn.z)), "dogus oynanabilir koridorda olmali")


func test_known_land_and_sea(t) -> void:
	var city := _get_city()
	for entry: Array in [["Kadikoy carsi", 40.9895, 29.0270, true], ["Besiktas", 41.0430, 29.0070, true],
			["Bostanci", 40.9600, 29.0950, true], ["Uskudar", 41.0255, 29.0170, true],
			["Bogaz", 41.0460, 29.0340, false], ["Marmara", 40.9400, 29.0700, false]]:
		var p := _project(city, entry[1], entry[2])
		t.eq(city.is_land(p.x, p.y), entry[3], "%s %s olmali" % [entry[0], "kara" if entry[3] else "deniz"])
	var kadikoy := _project(city, 40.9895, 29.0270)
	var atasehir := _project(city, 40.9920, 29.1270)
	t.ok(city.is_inside(kadikoy.x, kadikoy.y), "Kadikoy koridorda")
	t.ok(not city.is_inside(atasehir.x, atasehir.y), "Atasehir ici koridor disinda")


func test_limit_mask_blocks_outside(t) -> void:
	var city := _get_city()
	var world := VoxelWorld.new(Content.blocks)
	city.configure(world)
	world.generator = city
	var atasehir := _project(city, 40.9920, 29.1270)
	var kadikoy := _project(city, 40.9895, 29.0270)
	world.ensure_chunk(VoxelWorld.chunk_of(Vector3i(atasehir.x, 20, atasehir.y)))
	world.ensure_chunk(VoxelWorld.chunk_of(Vector3i(kadikoy.x, 20, kadikoy.y)))
	t.eq(world.get_block(atasehir.x, 20, atasehir.y), VoxelWorld.BOUNDARY, "koridor disi gorunmez duvar")
	t.ok(world.get_visual_block(atasehir.x, 20, atasehir.y) != VoxelWorld.BOUNDARY, "ama manzara olarak uretilmis")
	t.ok(world.get_block(kadikoy.x, 20, kadikoy.y) != VoxelWorld.BOUNDARY, "koridor ici acik")
	t.ok(not world.is_open_column(atasehir.x, atasehir.y), "is_open_column disarida false")


func test_generation_speed(t) -> void:
	var city := _get_city()
	var spawn := city.spawn_point()
	var base := Vector2i(floori(spawn.x) >> 4, floori(spawn.z) >> 4)
	var t0 := Time.get_ticks_usec()
	var columns := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for lz in 16:
				for lx in 16:
					city.column_info((base.x + dx) * 16 + lx, (base.y + dz) * 16 + lz)
					columns += 1
	var column_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	for cy in range(-1, 3):
		city.generate_chunk(VoxelChunk.new(Vector3i(base.x, cy, base.y)))
	var chunk_ms := (Time.get_ticks_usec() - t1) / 1000.0 / 4.0
	print("  koridor sutun: %.3f ms/sutun | chunk: %.1f ms" % [column_ms / columns, chunk_ms])
	t.ok(column_ms / columns < 0.5, "sutun hesabi 0.5 ms'nin altinda olmali")
	t.ok(chunk_ms < 40.0, "chunk uretimi 40 ms'nin altinda olmali (%.1f)" % chunk_ms)


func test_bridge_structure(t) -> void:
	var city := _get_city()
	t.eq(city.bridges.size(), 1, "15 Temmuz koprusu yuklenmeli")
	if city.bridges.is_empty():
		return
	var b: Dictionary = city.bridges[0]
	t.ok(b.length > 800.0 and b.t2 - b.t1 > 500.0, "ana aciklik gercekci olmali (%.0f m)" % (b.t2 - b.t1))
	# Ana acikligin ortasi: altinda deniz, ustunde tabliye.
	var pts: PackedVector2Array = b.pts
	var middle := city.bridge_point(b, (b.t1 + b.t2) * 0.5)
	var x := floori(middle.x)
	var z := floori(middle.y)
	var info := city.column_info(x, z)
	t.eq(info.get("bridge", ""), "deck", "orta hat tabliye")
	t.eq(info.kind, "sea", "ana aciklik denizin ustunde")
	var stand := city.ground_height(x, z)
	t.ok(stand >= CityGenerator.DECK_Y, "tabliye yuksekte (%d)" % stand)
	var chunk_blocks := _column_blocks(city, x, z, -8, 80)
	t.ok(chunk_blocks[stand - 1 + 8] in [city.m.asphalt, city.m.asphalt_half] or chunk_blocks[stand + 8] == city.m.asphalt_half,
		"tabliye ustu asfalt")
	t.eq(chunk_blocks[stand + 2 + 8], 0, "tabliye ustu acik")
	t.eq(chunk_blocks[10 + 8], 0, "tabliye alti bos (asma kopru, ayak yok)")
	t.eq(chunk_blocks[-2 + 8], city.m.water, "altinda Bogaz")
	# Kule: kiyida, tabliyenin yaninda, tepeye kadar celik.
	var side := (pts[1] - pts[0]).normalized().orthogonal()
	var tower: Vector2 = city.bridge_point(b, b.t1) + side * (b.half + 1.5)
	var tower_blocks := _column_blocks(city, floori(tower.x), floori(tower.y), -8, 80)
	t.eq(tower_blocks[CityGenerator.TOWER_TOP - 1 + 8], city.m.bridge_steel, "kule tepesi celik")
	t.eq(tower_blocks[CityGenerator.TOWER_TOP + 2 + 8], 0, "kule tepesinin ustu bos")


func test_bridge_decor_builds_near_and_far(t) -> void:
	var city := _get_city()
	var decor := BridgeDecor.new()
	decor.setup(city, 128.0)
	var b: Dictionary = city.bridges[0]
	t.eq(decor.piece_count(), ceili(b.length / BridgeDecor.PIECE), "kopru 30 m'lik parcalara bolunmeli")
	var near_boxes := 0
	var far_boxes := 0
	for child in decor.get_children():
		var node := child as MultiMeshInstance3D
		if node.material_override == decor.near_material:
			near_boxes += node.multimesh.instance_count
			t.ok(node.visibility_range_end > 0.0, "yakin parca uzakta kaybolmali")
		else:
			far_boxes += node.multimesh.instance_count
			t.ok(node.visibility_range_begin > 0.0, "uzak siluet yakinda gizli olmali")
	t.ok(near_boxes > 300, "halat + aski parcalari (%d)" % near_boxes)
	t.ok(far_boxes > 100, "uzak siluet parcalari (%d)" % far_boxes)
	t.ok(decor.far_material.disable_fog, "uzak siluet sisten etkilenmemeli")
	decor.free()


func test_parked_cars_can_drive(t) -> void:
	## Park etmis araclarin cogu gercekten surulebilmeli: egimli zeminde
	## gomulu ya da burnu duvara dayali dogan arac oyuncu icin olu esyadir.
	var city := _get_city()
	var world := VoxelWorld.new(Content.blocks)
	city.configure(world)
	world.generator = city
	var vehicles := Vehicles.new()
	vehicles.setup(world, ActorRegistry.new())
	vehicles.spawn_parked(city)
	var spawn := city.spawn_point()
	var cars: Array = vehicles.entries.duplicate()
	cars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.position.distance_to(spawn) < b.position.distance_to(spawn))
	var tested := 0
	var moving := 0
	var noise := func(_p: Vector3, _r: float) -> void: pass
	for car: Dictionary in cars.slice(0, 10):
		var here := VoxelWorld.chunk_of(Vector3i(floori(car.position.x), floori(car.position.y), floori(car.position.z)))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				for dy in range(-1, 2):
					world.ensure_chunk(here + Vector3i(dx, dy, dz))
		var start: Vector3 = car.position
		car.fuel = Vehicles.TANK
		car.durability = 100.0
		if vehicles.enter(car) != "":
			continue
		tested += 1
		for _i in 150:
			vehicles.drive(1.0 / 60.0, 1.0, 0.0, false, noise)
		var travelled := Vector2(car.position.x, car.position.z).distance_to(Vector2(start.x, start.z))
		if travelled > 6.0:
			moving += 1
		else:
			var yaw: float = car.yaw
			var ahead := Vector3(-sin(yaw), 0, -cos(yaw))
			var probe: Vector3 = start + ahead * 2.6
			print("  takilan arac %s -> %s yaw %.2f gomulu:%s: onunde y0=%d y1=%d (%s)" % [start, car.position, yaw,
				VoxelBody.is_blocked(world, start, float(car.half_w), float(car.height)),
				world.get_block(floori(probe.x), floori(start.y + 0.2), floori(probe.z)),
				world.get_block(floori(probe.x), floori(start.y + 1.2), floori(probe.z)),
				city.column_info(floori(probe.x), floori(probe.z)).kind])
			var rows := ""
			for dz in range(-3, 4):
				var line := ""
				for dx in range(-3, 4):
					var cx := floori(car.position.x) + dx
					var cz := floori(car.position.z) + dz
					var top := -99
					for y in range(floori(car.position.y) - 2, floori(car.position.y) + 4):
						var v := world.get_block(cx, y, cz)
						if v != 0 and v != VoxelWorld.BOUNDARY and world.materials.solid[v] == 1:
							top = y
					line += " %s%d" % [city.column_info(cx, cz).kind.substr(0, 2), top]
				rows += line + " |"
			print("    yuzeyler: ", rows)
		vehicles.leave()
	print("  surulebilen arac: %d / %d" % [moving, tested])
	t.ok(tested >= 8, "dogus cevresinde arac olmali (%d)" % tested)
	t.ok(moving >= tested * 0.7, "araclarin cogu surulebilmeli (%d/%d)" % [moving, tested])
	vehicles.free()


func test_bridge_ramp_is_walkable_and_repairable(t) -> void:
	var city := _get_city()
	if city.bridges.is_empty():
		t.ok(false, "kopru yok")
		return
	var b: Dictionary = city.bridges[0]
	var world := VoxelWorld.new(Content.blocks)
	city.configure(world)
	world.generator = city
	var start := city.bridge_point(b, 4.0)
	var ahead := (city.bridge_point(b, 40.0) - start).normalized()
	var position := Vector3(start.x, city.ground_height(floori(start.x), floori(start.y)) + 0.6, start.y)
	var velocity := Vector3.ZERO
	var on_floor := false
	var start_y := position.y
	# Rampadan kuleye kadar yuru (4 m/sn, 60 Hz). Chunk'lar yol boyunca uretilir.
	# 1:1 olcekte rampa ~250 m (egim ~%12); 66 sn yuruyus kuleye ulasir.
	for i in 60 * 66:
		if i % 30 == 0:
			var here := VoxelWorld.chunk_of(Vector3i(floori(position.x), floori(position.y), floori(position.z)))
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						world.ensure_chunk(here + Vector3i(dx, dy, dz))
		velocity.x = ahead.x * 4.0
		velocity.z = ahead.y * 4.0
		velocity.y -= 20.0 / 60.0
		var result := VoxelBody.move(world, position, velocity, 1.0 / 60.0, 0.3, 1.7, 0.55, on_floor)
		position = result.position
		velocity = result.velocity
		on_floor = result.on_floor
	var travelled := Vector2(position.x, position.z).distance_to(start)
	print("  rampa: %.0f m yuruyus, %.1f m -> %.1f m" % [travelled, start_y, position.y])
	t.ok(travelled > 140.0, "rampada takilmadan ilerlemeli (%.0f m)" % travelled)
	t.ok(position.y > start_y + 12.0, "rampa tirmanilmali (%.1f -> %.1f)" % [start_y, position.y])
	# Kopru de voxel: vurulur, onarilir.
	var deck_cell := Vector3i(floori(position.x), floori(position.y - 0.5), floori(position.z))
	if world.get_cell(deck_cell) == 0:
		deck_cell.y -= 1
	var material := world.get_cell(deck_cell)
	t.ok(material != 0 and material != VoxelWorld.BOUNDARY, "ayak altinda tabliye blogu")
	var full := world.hp_of(deck_cell)
	world.apply_damage(deck_cell, full * 0.5)
	t.ok(world.hp_of(deck_cell) < full, "tabliye hasar alir")
	world.repair(deck_cell, full)
	t.near(world.hp_of(deck_cell), full, 0.01, "tabliye onarilir")


static func _column_blocks(city: CityGenerator, x: int, z: int, y0: int, y1: int) -> PackedInt32Array:
	## Bir sutunun y0..y1 arasi bloklari (indeks = y - y0), chunk uretimiyle.
	var out := PackedInt32Array()
	out.resize(y1 - y0)
	var chunks := {}
	for y in range(y0, y1):
		var coord := VoxelWorld.chunk_of(Vector3i(x, y, z))
		if not chunks.has(coord):
			var chunk := VoxelChunk.new(coord)
			city.generate_chunk(chunk)
			chunks[coord] = chunk
		var c: VoxelChunk = chunks[coord]
		out[y - y0] = c.blocks[VoxelChunk.index(x & 15, y & 15, z & 15)]
	return out
