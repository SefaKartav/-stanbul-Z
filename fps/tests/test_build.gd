extends RefCounted
## Insa kurallari: destek, suya platform siniri, kopru onarimi, atomik odeme.


func _m(id: String) -> int:
	return Content.blocks.index_of(id)


func _world() -> VoxelWorld:
	var world := VoxelWorld.new(Content.blocks)
	world.generator = FlatGenerator.new(Content.blocks)
	world.min_cell = Vector3i(-64, -16, -64)
	world.max_cell = Vector3i(64, 48, 64)
	for cy in range(-1, 2):
		for cz in range(-2, 2):
			for cx in range(-2, 2):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	return world


func _sea(world: VoxelWorld) -> void:
	## x >= 10 deniz: zemin kazilir, su konur (harita blogu olarak).
	for x in range(10, 30):
		for z in range(-3, 4):
			for y in range(-4, 0):
				world.set_block(Vector3i(x, y, z), _m("water"), VoxelWorld.ORIGIN_WORLD)
	world.placed.clear()


func test_block_on_ground_is_valid(t) -> void:
	var rules := BuildRules.new(_world())
	t.eq(rules.errors.size(), 0, "katalog hatasiz olmali: %s" % [rules.errors])
	t.ok(rules.validate([Vector3i(0, 0, 0)], []).ok)


func test_floating_block_is_rejected(t) -> void:
	var rules := BuildRules.new(_world())
	var result := rules.validate([Vector3i(0, 5, 0)], [])
	t.ok(not result.ok, "havada blok olmamali")


func test_cannot_build_long_platform_over_water(t) -> void:
	var world := _world()
	_sea(world)
	var rules := BuildRules.new(world)
	var placed := 0
	# Kiyidan (x=9 kara) denize dogru su yuzeyi seviyesinde blok koymayi dene.
	for x in range(10, 20):
		var cell := Vector3i(x, -1, 0)
		if rules.validate([cell], []).ok:
			world.set_block(cell, _m("wood"))
			placed += 1
		else:
			break
	t.ok(placed <= BuildRules.CANTILEVER, "kiyidan en fazla %d blok uzanilabilmeli (%d)" % [BuildRules.CANTILEVER, placed])


func test_real_bridge_gap_can_be_repaired(t) -> void:
	var world := _world()
	_sea(world)
	# Haritanin kendi koprusu: x 10..29 boyunca y=0 tabliye, ortasi yikilmis.
	for x in range(10, 30):
		world.set_block(Vector3i(x, 0, 0), _m("concrete"), VoxelWorld.ORIGIN_WORLD)
	world.placed.clear()
	for x in range(18, 21):
		world.set_block(Vector3i(x, 0, 0), 0, VoxelWorld.ORIGIN_WORLD)
	var rules := BuildRules.new(world)
	var ok := true
	for x: int in [18, 20, 19]:
		var result := rules.validate([Vector3i(x, 0, 0)], [])
		ok = ok and result.ok
		world.set_block(Vector3i(x, 0, 0), _m("concrete_block"))
	t.ok(ok, "gercek kopru bosluklari onarilabilmeli")


func test_payment_is_atomic(t) -> void:
	var bag := Inventory.new()
	bag.add(ItemStack.new(Content.item("wood_plank"), 2))
	var cost := [{"item": "wood_plank", "count": 2}, {"tag": "fastener", "count": 2}]
	t.ok(not BuildRules.can_pay(cost, [bag]).ok, "civi yokken odenememeli")
	t.ok(not BuildRules.pay(cost, [bag]), "odeme reddedilmeli")
	t.eq(bag.count("wood_plank"), 2, "reddedilen odeme tahtayi harcamamali")
	bag.add(ItemStack.new(Content.item("nail"), 5))
	t.ok(BuildRules.pay(cost, [bag]), "tam malzemeyle odenmeli")
	t.eq(bag.count("wood_plank"), 0)
	t.eq(bag.count("nail"), 3)


func test_payment_uses_bag_then_stockpile(t) -> void:
	var bag := Inventory.new()
	var stock := Inventory.new(500.0, 200)
	bag.add(ItemStack.new(Content.item("sand"), 1))
	stock.add(ItemStack.new(Content.item("sand"), 5))
	t.ok(BuildRules.pay([{"item": "sand", "count": 3}], [bag, stock]))
	t.eq(bag.count("sand"), 0, "once canta")
	t.eq(stock.count("sand"), 3, "kalani depodan")


func test_placed_block_is_marked_player_origin(t) -> void:
	var world := _world()
	world.set_block(Vector3i(3, 0, 3), _m("wood"))
	var result := world.apply_damage(Vector3i(3, 0, 3), 999.0)
	t.ok(result.destroyed)
	t.eq(result.origin, VoxelWorld.ORIGIN_PLACED, "kirilan oyuncu blogu kurtarma dususu vermemeli")


func test_repair_cost_is_proportional(t) -> void:
	var world := _world()
	world.set_block(Vector3i(0, 0, 0), _m("wood"))
	world.apply_damage(Vector3i(0, 0, 0), 30.0)    # 60 hp'nin yarisi
	var rules := BuildRules.new(world)
	var repair := rules.repair_cost(Vector3i(0, 0, 0))
	t.ok(not repair.is_empty(), "hasarli ahsap onarilabilmeli")
	t.near(repair.amount, 30.0, 0.01)
	t.eq(int(repair.cost[0].count), 1, "yari hasar icin en az 1 tahta")
