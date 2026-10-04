extends RefCounted
## Voxel cekirdegi: isin, hasar, kalici farklar, chunk siniri, carpisma.


func _world() -> VoxelWorld:
	var world := VoxelWorld.new(Content.blocks)
	world.generator = FlatGenerator.new(Content.blocks)
	world.min_cell = Vector3i(-64, -16, -64)
	world.max_cell = Vector3i(64, 48, 64)
	for cy in range(-1, 3):
		for cz in range(-2, 2):
			for cx in range(-2, 2):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	return world


func _m(id: String) -> int:
	return Content.blocks.index_of(id)


func test_ray_hits_ground_at_expected_distance(t) -> void:
	var world := _world()
	var hit := VoxelRay.cast(world, Vector3(0.5, 5.0, 0.5), Vector3.DOWN, 20.0)
	t.ok(not hit.is_empty(), "zemine carpmali")
	t.near(hit.distance, 5.0, 0.001, "zemin y=0'da")
	t.eq(hit.cell, Vector3i(0, -1, 0))
	t.eq(hit.normal, Vector3.UP)


func test_ray_passes_over_slab_but_hits_its_top(t) -> void:
	var world := _world()
	world.set_block(Vector3i(3, 0, 0), _m("sidewalk"))
	# Kaldirimin (0.5 m) ustunden yatay gecen isin ona carpmaz...
	var over := VoxelRay.cast(world, Vector3(0.5, 0.75, 0.5), Vector3.RIGHT, 6.0)
	t.ok(over.is_empty(), "0.75 m yukseklikte kaldirimin ustunden gecmeli")
	# ...ama yukaridan inen isin ust yuzeyine 0.5 m'de carpar.
	var down := VoxelRay.cast(world, Vector3(3.5, 3.0, 0.5), Vector3.DOWN, 5.0)
	t.near(down.distance, 2.5, 0.001, "yarim blok ustu")


func test_unloaded_region_blocks_rays(t) -> void:
	var world := _world()
	var hit := VoxelRay.cast(world, Vector3(0.5, 5.0, 0.5), Vector3.RIGHT, 500.0)
	t.ok(not hit.is_empty() and hit.boundary, "yuklenmemis bolge hava sayilmamali")


func test_material_hit_counts_differ(t) -> void:
	# Ayni sabit test silahi (26 hasar) ile ahsap < tugla < beton < celik.
	var world := _world()
	var counts := {}
	var x := 0
	for id: String in ["wood", "brick", "concrete", "steel"]:
		var cell := Vector3i(x, 0, 5)
		world.set_block(cell, _m(id))
		var shots := 0
		while world.get_cell(cell) != 0 and shots < 500:
			var mult: float = Content.blocks.damage_mult[_m(id)]
			world.apply_damage(cell, 26.0 * mult)
			shots += 1
		counts[id] = shots
		x += 2
	t.eq(counts.wood, 3, "ahsap")
	t.ok(counts.brick > counts.wood and counts.concrete > counts.brick and counts.steel > counts.concrete,
		"dayaniklilik sirasi: %s" % [counts])


func test_destroyed_block_becomes_air_immediately(t) -> void:
	var world := _world()
	var cell := Vector3i(1, 0, 1)
	world.set_block(cell, _m("glass"))
	var result := world.apply_damage(cell, 100.0)
	t.ok(result.destroyed)
	t.eq(world.get_cell(cell), 0)
	t.ok(VoxelRay.cast(world, Vector3(1.5, 0.5, -3.0), Vector3.BACK, 6.0).is_empty(),
		"kirilan hucreden isin gecmeli")


func test_modifications_survive_chunk_reload(t) -> void:
	var world := _world()
	var cell := Vector3i(2, -1, 2)
	world.set_block(cell, 0)
	world.set_block(Vector3i(4, 0, 4), _m("brick"))
	world.apply_damage(Vector3i(4, 0, 4), 40.0)
	var coord := VoxelWorld.chunk_of(cell)
	world.unload_chunk(coord)
	t.eq(world.get_cell(cell), VoxelWorld.BOUNDARY, "bosaltilan chunk bilinmeyen olmali")
	world.ensure_chunk(coord)
	t.eq(world.get_cell(cell), 0, "kirilan zemin geri gelmemeli")
	t.eq(world.get_cell(Vector3i(4, 0, 4)), _m("brick"), "konan blok kalmali")
	t.near(world.hp_of(Vector3i(4, 0, 4)), 110.0, 0.01, "kismi HP korunmali")


func test_save_roundtrip_keeps_damage_and_origin(t) -> void:
	var world := _world()
	world.set_block(Vector3i(0, 0, 0), _m("wood"))
	world.apply_damage(Vector3i(0, 0, 0), 20.0)
	world.set_block(Vector3i(1, -1, 0), 0, VoxelWorld.ORIGIN_WORLD)
	var data := world.to_dict()
	var json := JSON.stringify(data)
	var restored := _world()
	restored.load_dict(JSON.parse_string(json))
	t.eq(restored.get_cell(Vector3i(0, 0, 0)), _m("wood"))
	t.near(restored.hp_of(Vector3i(0, 0, 0)), 40.0, 0.01)
	t.ok(restored.placed.has(Vector3i(0, 0, 0)), "oyuncu kokeni korunmali")
	t.eq(restored.get_cell(Vector3i(1, -1, 0)), 0)


func test_mesher_culls_shared_faces(t) -> void:
	var world := VoxelWorld.new(Content.blocks)
	world.min_cell = Vector3i(-64, -16, -64)
	world.max_cell = Vector3i(64, 48, 64)
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			for cy in range(-1, 2):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	world.set_block(Vector3i(5, 5, 5), _m("brick"))
	var terrain := VoxelTerrain.new()
	terrain.setup(world, null)
	var one := ChunkMesher.build(terrain._snapshot(Vector3i.ZERO), {}, Vector3i.ZERO, Content.blocks)
	t.eq(one.opaque[Mesh.ARRAY_VERTEX].size(), 24, "tek blok 6 yuz")
	world.set_block(Vector3i(6, 5, 5), _m("brick"))
	var two := ChunkMesher.build(terrain._snapshot(Vector3i.ZERO), {}, Vector3i.ZERO, Content.blocks)
	t.eq(two.opaque[Mesh.ARRAY_VERTEX].size(), 40, "iki bitisik blok 10 yuz")
	terrain.free()


func test_mesher_culls_across_chunk_border(t) -> void:
	var world := VoxelWorld.new(Content.blocks)
	world.min_cell = Vector3i(-64, -16, -64)
	world.max_cell = Vector3i(64, 48, 64)
	for cz in range(-1, 2):
		for cx in range(-1, 3):
			for cy in range(-1, 2):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	world.set_block(Vector3i(15, 5, 5), _m("brick"))
	world.set_block(Vector3i(16, 5, 5), _m("brick"))
	var terrain := VoxelTerrain.new()
	terrain.setup(world, null)
	var left := ChunkMesher.build(terrain._snapshot(Vector3i.ZERO), {}, Vector3i.ZERO, Content.blocks)
	t.eq(left.opaque[Mesh.ARRAY_VERTEX].size(), 20, "komsu chunk'taki blokla ortak yuz cizilmemeli")
	terrain.free()


func test_body_lands_on_ground(t) -> void:
	var world := _world()
	var position := Vector3(0.5, 3.0, 0.5)
	var velocity := Vector3.ZERO
	var on_floor := false
	for _i in 120:
		velocity.y -= 20.0 / 60.0
		var r := VoxelBody.move(world, position, velocity, 1.0 / 60.0, 0.3, 1.8, 0.55, on_floor)
		position = r.position
		velocity = r.velocity
		on_floor = r.on_floor
	t.near(position.y, 0.0, 0.01, "zemine inmeli")
	t.ok(on_floor)


func test_body_blocked_by_wall_but_steps_onto_curb(t) -> void:
	var world := _world()
	for z in range(-2, 3):
		world.set_block(Vector3i(3, 0, z), _m("sidewalk"))
		world.set_block(Vector3i(6, 0, z), _m("brick"))
		world.set_block(Vector3i(6, 1, z), _m("brick"))
	var position := Vector3(0.5, 0.0, 0.5)
	var on_floor := true
	for _i in 180:
		var r := VoxelBody.move(world, position, Vector3(3.0, -1.0, 0.0), 1.0 / 60.0, 0.3, 1.8, 0.55, on_floor)
		position = r.position
		on_floor = r.on_floor
	t.ok(position.x > 4.0, "kaldirima basamakla cikmali (x=%.2f)" % position.x)
	t.ok(position.x <= 5.7 + 0.01, "duvarin icine girmemeli (x=%.2f)" % position.x)
