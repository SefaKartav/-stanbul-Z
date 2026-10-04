extends Node
## Zombi yol bulma ve duyu: kirilan gecit, barikat maliyeti, sigmayan delik.


func _m(id: String) -> int:
	return Content.blocks.index_of(id)


func _world() -> VoxelWorld:
	var world := VoxelWorld.new(Content.blocks)
	world.generator = FlatGenerator.new(Content.blocks)
	world.min_cell = Vector3i(-64, -16, -64)
	world.max_cell = Vector3i(64, 48, 64)
	for cy in range(-1, 2):
		for cz in range(-4, 4):
			for cx in range(-4, 4):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	return world


func _nav(world: VoxelWorld, target: Vector2i) -> NavGrid:
	var nav := NavGrid.new(world, func(_x: int, _z: int) -> int: return 0)
	nav.begin(target)
	while not nav.step(100000):
		pass
	return nav


func _wall(world: VoxelWorld, x: int, from_z: int, to_z: int, material: String, height: int = 3,
		placed: bool = false) -> void:
	for z in range(from_z, to_z + 1):
		for y in height:
			world.set_block(Vector3i(x, y, z), _m(material),
				VoxelWorld.ORIGIN_PLACED if placed else VoxelWorld.ORIGIN_WORLD)


func test_path_goes_around_wall_through_gap(t) -> void:
	var world := _world()
	_wall(world, 5, -20, -1, "concrete")
	_wall(world, 5, 3, 20, "concrete")          # gecit: z = 0..2
	var nav := _nav(world, Vector2i(10, 10))
	var d := nav.distance_at(0, 10)
	t.ok(d > 0, "duvarin arkasi ulasilabilir olmali")
	t.ok(d > 10 * 10 + 20, "yol duvarin etrafindan dolasmali (%d)" % d)


func test_broken_wall_opens_new_route(t) -> void:
	var world := _world()
	_wall(world, 5, -64, 63, "brick")
	var nav := _nav(world, Vector2i(10, 0))
	var before := nav.distance_at(0, 0)
	# Oyuncu duvarda 1x2 delik acar (ayni sutunda iki blok).
	world.set_block(Vector3i(5, 0, 0), 0, VoxelWorld.ORIGIN_WORLD)
	world.set_block(Vector3i(5, 1, 0), 0, VoxelWorld.ORIGIN_WORLD)
	nav = _nav(world, Vector2i(10, 0))
	var after := nav.distance_at(0, 0)
	t.ok(after > 0 and (before < 0 or after < before), "kirilan gecit rotaya girmeli (%d -> %d)" % [before, after])


func test_ai_does_not_fit_through_one_block_hole(t) -> void:
	var world := _world()
	_wall(world, 5, -64, 63, "brick")
	world.set_block(Vector3i(5, 0, 0), 0, VoxelWorld.ORIGIN_WORLD)   # yalnizca 1 m yukseklik
	var nav := _nav(world, Vector2i(10, 0))
	var d := nav.distance_at(0, 0)
	t.ok(d < 0 or d > 10 * 60, "1 m'lik delikten gecmemeli (%d)" % d)


func test_barricade_raises_cost_but_stays_passable(t) -> void:
	var world := _world()
	_wall(world, 5, -64, -1, "concrete")
	_wall(world, 5, 1, 63, "concrete")
	# Tek gecit z=0: barikatla kapatildi.
	_wall(world, 5, 0, 0, "wood", 2, true)
	var nav := _nav(world, Vector2i(10, 0))
	var d := nav.distance_at(0, 0)
	t.ok(d > 0, "tek yol barikatsa zombi oraya yonelmeli (saldirmak icin)")
	t.ok(d >= NavGrid.BARRICADE_COST, "barikat maliyeti eklenmeli (%d)" % d)
	var step := nav.next_step(4, 0)
	t.ok(not step.is_empty() and step.barricade, "sonraki adim barikat hucresi olmali")
	t.eq(nav.barricade_cell(5, 0).y, 0, "saldirilacak hucre bulunmali")


func test_world_wall_is_never_a_barricade(t) -> void:
	var world := _world()
	_wall(world, 5, -64, 63, "wood", 2, false)  # haritanin kendi tahta duvari
	var nav := _nav(world, Vector2i(10, 0))
	t.eq(nav.column(5, 0)[1], false, "harita blogu barikat sayilmamali")
	t.ok(nav.distance_at(0, 0) < 0, "haritanin duvari kazilarak gecilmez")


func test_noise_within_hearing_triggers_investigate(t) -> void:
	var world := _world()
	var manager := ZombieManager.new()
	add_child(manager)
	var actors := ActorRegistry.new()
	manager.setup(world, _nav(world, Vector2i(0, 0)), actors, null, null, func(_x: int, _z: int) -> int: return 0)
	var walker: ZombieDef = Content.zombies["walker"]
	var near := manager.spawn(walker, Vector3(5.5, 0, 0.5))
	var far := manager.spawn(walker, Vector3(5.5, 0, 0.5) + Vector3(walker.hearing_m() + 20.0, 0, 0))
	actors.rebuild()
	manager.emit_noise(Vector3(0.5, 0, 0.5), 30.0)
	manager._dispatch_noise()
	t.eq(near.state, Zombie.State.INVESTIGATE, "yakin zombi sesi duymali")
	t.ok(far.state != Zombie.State.INVESTIGATE, "uzaktaki duymamali")
	manager.free()
