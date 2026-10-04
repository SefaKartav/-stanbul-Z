extends Node
## Silah - dunya - aktor etkilesimi: belgenin "ozellikle dogrulanacak
## hatalar" listesindeki atis maddeleri.

var _nodes: Array = []


func _m(id: String) -> int:
	return Content.blocks.index_of(id)


func _setup() -> Array:
	var world := VoxelWorld.new(Content.blocks)
	world.generator = FlatGenerator.new(Content.blocks)
	world.min_cell = Vector3i(-64, -16, -64)
	world.max_cell = Vector3i(64, 48, 64)
	for cy in range(-1, 3):
		for cz in range(-2, 2):
			for cx in range(-2, 2):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	var actors := ActorRegistry.new()
	return [world, actors, Hitscan.new(world, actors)]


func _dummy(actors: ActorRegistry, position: Vector3) -> TargetDummy:
	var dummy := TargetDummy.new()
	add_child(dummy)
	dummy.global_position = position
	actors.add(dummy)
	_nodes.append(dummy)
	return dummy


func _wall(world: VoxelWorld, x: int, material: String) -> void:
	for y in range(0, 3):
		for z in range(-2, 3):
			world.set_block(Vector3i(x, y, z), _m(material))


func _cleanup() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func test_non_piercing_shot_does_not_damage_behind_wall(t) -> void:
	var setup := _setup()
	var world: VoxelWorld = setup[0]
	var hitscan: Hitscan = setup[2]
	_wall(world, 5, "concrete")
	var dummy := _dummy(setup[1], Vector3(8.5, 0.0, 0.5))
	var eye := Vector3(0.5, 1.5, 0.5)
	var result := hitscan.fire(eye, Vector3.RIGHT, eye, 100.0, 26.0, "physical", 0, "player", null)
	t.eq(result.impacts.size(), 1, "tek carpisma: duvar")
	t.eq(result.impacts[0].kind, "block")
	t.eq(dummy.hits, 0, "duvar arkasindaki hedef hasar almamali")
	t.ok(world.damage.has(Vector3i(5, 1, 0)), "duvar hasar almali")
	_cleanup()


func test_muzzle_behind_cover_hits_cover_not_target(t) -> void:
	var setup := _setup()
	var world: VoxelWorld = setup[0]
	var hitscan: Hitscan = setup[2]
	# Kamera siperin USTUNDEN bakiyor, namlu ise siperin arkasinda asagida.
	for z in range(-2, 3):
		world.set_block(Vector3i(3, 0, z), _m("brick"))
	var dummy := _dummy(setup[1], Vector3(10.5, 0.0, 0.5))
	var eye := Vector3(0.5, 1.6, 0.5)
	var muzzle := Vector3(2.6, 0.7, 0.5)
	var direction := (Vector3(10.5, 1.3, 0.5) - eye).normalized()
	var result := hitscan.fire(eye, direction, muzzle, 100.0, 26.0, "physical", 0, "player", null)
	t.eq(dummy.hits, 0, "namlu siperin arkasindayken hedef vurulmamali")
	t.eq(result.impacts[0].kind, "block", "mermi siperi vurmali")
	_cleanup()


func test_muzzle_inside_wall_hits_that_wall(t) -> void:
	var setup := _setup()
	var world: VoxelWorld = setup[0]
	var hitscan: Hitscan = setup[2]
	for y in range(0, 3):
		world.set_block(Vector3i(1, y, 0), _m("wood"))
	var dummy := _dummy(setup[1], Vector3(6.5, 0.0, 0.5))
	var eye := Vector3(0.7, 1.5, 0.5)
	var muzzle := Vector3(1.3, 1.4, 0.5)          # duvarin icinde
	var result := hitscan.fire(eye, Vector3.RIGHT, muzzle, 100.0, 26.0, "physical", 0, "player", null)
	t.eq(dummy.hits, 0, "duvara yaslanmisken karsidaki hedef vurulmamali")
	t.eq(result.impacts[0].cell, Vector3i(1, 1, 0))
	_cleanup()


func test_glass_breaks_and_bullet_continues(t) -> void:
	var setup := _setup()
	var world: VoxelWorld = setup[0]
	var hitscan: Hitscan = setup[2]
	world.set_block(Vector3i(4, 1, 0), _m("glass"))
	var dummy := _dummy(setup[1], Vector3(8.5, 0.0, 0.5))
	var eye := Vector3(0.5, 1.2, 0.5)
	hitscan.fire(eye, Vector3.RIGHT, eye, 100.0, 26.0, "physical", 0, "player", null)
	t.eq(world.get_cell(Vector3i(4, 1, 0)), 0, "cam kirilmali")
	t.eq(dummy.hits, 1, "cam arkasindaki hedef kalan enerjiyle vurulmali")
	t.ok(dummy.total_damage < 26.0, "cam enerjinin bir kismini almali (%.1f)" % dummy.total_damage)
	_cleanup()


func test_piercing_rifle_goes_through_wood_not_concrete(t) -> void:
	var setup := _setup()
	var world: VoxelWorld = setup[0]
	var hitscan: Hitscan = setup[2]
	_wall(world, 4, "wood")
	var behind_wood := _dummy(setup[1], Vector3(7.5, 0.0, 0.5))
	var eye := Vector3(0.5, 1.2, 0.5)
	hitscan.fire(eye, Vector3.RIGHT, eye, 100.0, 68.0, "physical", 2, "player", null)
	t.eq(behind_wood.hits, 1, "delen tufek tahtanin arkasindakini vurmali")
	_cleanup()
	setup = _setup()
	world = setup[0]
	hitscan = setup[2]
	_wall(world, 4, "concrete")
	var behind_concrete := _dummy(setup[1], Vector3(7.5, 0.0, 0.5))
	hitscan.fire(eye, Vector3.RIGHT, eye, 100.0, 68.0, "physical", 2, "player", null)
	t.eq(behind_concrete.hits, 0, "1 m beton delinmemeli")
	_cleanup()


func test_each_pellet_damages_its_own_cell(t) -> void:
	var setup := _setup()
	var world: VoxelWorld = setup[0]
	var hitscan: Hitscan = setup[2]
	for y in range(0, 6):
		for z in range(-6, 7):
			world.set_block(Vector3i(6, y, z), _m("brick"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var eye := Vector3(0.5, 2.5, 0.5)
	var impacts := 0
	for offset: Vector2 in WeaponState.spread_offsets(8, 9.0, rng):
		var dir := Hitscan.direction_with_spread(Vector3.RIGHT, offset)
		impacts += hitscan.fire(eye, dir, eye, 100.0, 15.0, "physical", 0, "player", null).impacts.size()
	t.eq(impacts, 8, "8 sacma = 8 ayri carpisma")
	t.ok(world.damage.size() >= 4, "sacmalar birden fazla hucreye dagilmali (%d)" % world.damage.size())
	_cleanup()


func test_headshot_detected(t) -> void:
	var setup := _setup()
	var hitscan: Hitscan = setup[2]
	var dummy := _dummy(setup[1], Vector3(6.5, 0.0, 0.5))
	var eye := Vector3(0.5, 1.65, 0.5)
	var result := hitscan.fire(eye, Vector3.RIGHT, eye, 100.0, 20.0, "physical", 0, "player", null)
	t.eq(result.impacts[0].zone, "head")
	t.near(dummy.total_damage, 40.0, 0.01, "kafa vurusu iki kat")
	_cleanup()
