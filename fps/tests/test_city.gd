extends RefCounted
## Kadikoy haritasi: yuklenir, dogus noktasi yurunebilir, uretim suresi olculur.

const MAP := "res://data/map/kadikoy.json"


func test_city_loads_and_spawn_is_open(t) -> void:
	var city := CityGenerator.new(Content.blocks, MAP)
	t.ok(city.width > 100 and city.height > 100, "harita boyutu")
	t.ok(city.buildings.size() > 100, "binalar yuklenmeli (%d)" % city.buildings.size())
	var spawn := city.spawn_point()
	var info := city.column_info(floori(spawn.x), floori(spawn.z))
	t.ok(info.kind in ["road", "sidewalk", "plaza"], "dogus acik bir yerde olmali (%s)" % info.kind)


func test_generation_speed(t) -> void:
	var city := CityGenerator.new(Content.blocks, MAP)
	var spawn := city.spawn_point()
	var base := Vector3i(floori(spawn.x) >> 4, 0, floori(spawn.z) >> 4)
	var t0 := Time.get_ticks_usec()
	var columns := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for lz in 16:
				for lx in 16:
					city.column_info((base.x + dx) * 16 + lx, (base.z + dz) * 16 + lz)
					columns += 1
	var column_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	var chunks := 0
	for cy in range(-1, 3):
		var chunk := VoxelChunk.new(Vector3i(base.x, cy, base.z))
		city.generate_chunk(chunk)
		chunks += 1
	var chunk_ms := (Time.get_ticks_usec() - t1) / 1000.0 / chunks
	print("  sutun: %d adet %.1f ms (%.3f ms/sutun) | chunk: %.1f ms/chunk (sutunlar onbellekte)" % [
		columns, column_ms, column_ms / columns, chunk_ms])
	t.ok(column_ms / columns < 0.5, "sutun hesabi 0.5 ms'nin altinda olmali")
	t.ok(chunk_ms < 40.0, "chunk uretimi 40 ms'nin altinda olmali (%.1f)" % chunk_ms)


func test_buildings_have_facade_and_interior(t) -> void:
	var city := CityGenerator.new(Content.blocks, MAP)
	var found_edge := false
	var found_inner := false
	for x in range(0, city.width, 3):
		for z in range(0, city.height, 3):
			var info := city.column_info(x, z)
			if info.kind == "building":
				if info.edge:
					found_edge = true
				else:
					found_inner = true
		if found_edge and found_inner:
			break
	t.ok(found_edge and found_inner, "binalarin hem cephesi hem dolu ici olmali")
