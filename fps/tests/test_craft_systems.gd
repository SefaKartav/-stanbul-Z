extends Node
## Yeni uretim dongusu (29 Eylul 2026): ~760 tarif, islev sinifi, elektrik,
## tarim, kaynak toplama, yerlestirilebilir yapi kati hucreleri.

const FAMILY_TARGETS := {"build": 180, "process": 100, "tools": 60, "weapons": 80, "defense": 60, "power": 55,
	"food": 85, "health": 50, "storage": 40, "vehicle": 50}


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


func test_recipe_count_and_families(t) -> void:
	t.ok(Content.recipes.size() >= 760, "en az 760 tarif (%d)" % Content.recipes.size())
	var counts := {}
	for recipe: RecipeDef in Content.recipes.values():
		counts[recipe.family] = int(counts.get(recipe.family, 0)) + 1
	for family: String in FAMILY_TARGETS:
		t.ok(int(counts.get(family, 0)) >= int(FAMILY_TARGETS[family]),
			"%s ailesi hedefe ulasmali (%d / %d)" % [family, int(counts.get(family, 0)), FAMILY_TARGETS[family]])
	var stations := {}
	for recipe: RecipeDef in Content.recipes.values():
		stations[recipe.station] = true
	for station: String in RecipeDef.STATIONS:
		t.ok(stations.has(station), "istasyon '%s' en az bir tarifte kullanilir" % station)


func test_every_output_has_a_working_handler(t) -> void:
	var bad := []
	var classes := {}
	for recipe: RecipeDef in Content.recipes.values():
		var output := Content.item(recipe.output_id)
		if output == null:
			bad.append(recipe.id + ": cikti yok")
			continue
		var problem := ItemUse.handler_problem(output)
		if problem != "":
			bad.append("%s -> %s" % [recipe.id, problem])
		classes[ItemUse.classify(output)] = true
	t.eq(bad, [], "her ciktinin calisan isleyicisi olmali")
	for kind: String in ["consume", "throw", "equip", "weapon", "ammo", "mod", "tool", "place", "build", "component",
			"repair", "vehicle"]:
		t.ok(classes.has(kind), "islev sinifi '%s' tariflerde temsil ediliyor" % kind)


static func _stock_for(recipe: RecipeDef, batches: int) -> Inventory:
	## Hata ayiklama envanteri: tarifin girdilerini (etiket icin karsilayan ilk
	## esya) istenen kalitede koyar.
	var inv := Inventory.new(100000.0, 2000)
	for ingredient: Dictionary in recipe.inputs:
		var def: ItemDef = null
		if ingredient.item != "":
			def = Content.item(ingredient.item)
		else:
			var options: Array = Content.graph.items_with_tag(ingredient.tag)
			options.sort()
			for id: String in options:
				if id != recipe.output_id:
					def = Content.item(id)
					break
		if def == null:
			continue
		var count: int = ingredient.count * (batches if ingredient.consumed else 1)
		inv.add(ItemStack.new(def, count, maxf(80.0, float(ingredient.get("min_quality", 0.0)))))
	return inv


func test_every_recipe_crafts_from_debug_inventory(t) -> void:
	## Belgenin kabul kosulu: her tarif gercek CraftingService yoluyla uretilir,
	## girdiler harcanir, cikti envantere girer (kilit bilinen sayilir).
	var service := CraftingService.new(Content.items, 1234)
	var failed := []
	for recipe: RecipeDef in Content.recipes.values():
		service.known_recipes[recipe.id] = true
		var tier := maxi(recipe.station_tier, 1)
		var ok := false
		var reason := ""
		for attempt in 6:          # basarisizlik olasiligi olan tarifler icin yeniden dene
			var inv := _stock_for(recipe, 1)
			var before := inv.count(recipe.output_id)
			var check := service.check(inv, recipe, recipe.station, tier, 0.0)
			if not check.ok:
				reason = str(check.reason)
				break
			var result := service.craft(inv, recipe, recipe.station, tier, 0.0)
			if result.success:
				ok = inv.count(recipe.output_id) >= before + recipe.output_count
				reason = "" if ok else "cikti envantere girmedi"
				break
			reason = str(result.reason)
			if recipe.failure_chance <= 0.0:
				break
		if not ok:
			failed.append("%s (%s)" % [recipe.id, reason])
	t.eq(failed.slice(0, 12), [], "her tarif hata ayiklama envanterinden uretilmeli (%d basarisiz)" % failed.size())


func test_locked_recipes_explain_unlock_path(t) -> void:
	var service := CraftingService.new(Content.items, 7)
	var kinds := {}
	for recipe: RecipeDef in Content.recipes.values():
		if recipe.unlocked:
			continue
		kinds[recipe.learn_kind()] = true
		var check := service.check(_stock_for(recipe, 1), recipe, recipe.station, 5, 0.0)
		t.ok(bool(check.get("locked", false)), "%s kilitli olmali" % recipe.id)
		t.ok(recipe.learn_text() != "", "%s acilma yolu yazmali" % recipe.id)
		if kinds.size() >= 4:
			break
	t.ok(kinds.has("level") or kinds.has("skill"), "seviye/beceri ile acilan tarif var")


# ---------------------------------------------------------------------------
# Elektrik
# ---------------------------------------------------------------------------
class FakeTime extends RefCounted:
	var dark := 1.0
	func hours_per_second() -> float:
		return 1.0 / 40.0
	func darkness() -> float:
		return dark
	func total_hours() -> float:
		return 10.0


class FakeBases extends RefCounted:
	func settlement_at(_p: Vector3) -> Settlement:
		return null


class FakeActors extends RefCounted:
	func near(_p: Vector3, _r: float) -> Array:
		return []


class FakeGame extends Node:
	var time := FakeTime.new()
	var bases := FakeBases.new()
	var actors := FakeActors.new()
	var player := Node3D.new()
	var noises := 0
	func on_noise_at(_p: Vector3, _r: float) -> void:
		noises += 1


func _place(placeables: Placeables, item_id: String, cell: Vector3i, quality: float = 50.0) -> Dictionary:
	return placeables.place(ItemStack.new(Content.item(item_id), 1, quality), cell, 0)


func test_power_grid_generator_battery_and_reach(t) -> void:
	var placeables := Placeables.new()
	placeables.catalog = Content.placeables
	add_child(placeables)
	var grid := PowerGrid.new(placeables)
	var game := FakeGame.new()
	add_child(game)
	var gen := _place(placeables, "generator_small", Vector3i(0, 1, 0))
	gen.fuel = 4.0
	var near_lamp := _place(placeables, "lamp_led", Vector3i(3, 1, 0))
	var far_lamp := _place(placeables, "lamp_led", Vector3i(40, 1, 0))
	var battery := _place(placeables, "battery_bank_small", Vector3i(0, 1, 3))
	grid.tick(0.6, game)
	t.ok(bool(near_lamp.powered), "jeneratore 3 m'deki lamba yanar")
	t.ok(not bool(far_lamp.powered), "40 m'deki bagsiz lamba yanmaz")
	t.ok(float(gen.fuel) < 4.0, "jenerator yakit yakar")
	t.ok(float(battery.charge) > 0.0, "fazla uretim akuye gider")
	t.ok(game.noises > 0, "calisan jenerator gurultu yapar")
	# Kablo diregi uzaktaki lambayi aga baglar.
	_place(placeables, "power_pole_wood", Vector3i(14, 1, 0))
	_place(placeables, "power_pole_wood", Vector3i(28, 1, 0))
	grid.tick(0.6, game)
	t.ok(bool(far_lamp.powered), "direklerle baglanan uzak lamba yanar")
	# Jenerator kapaninca aku besler; aku bitince karanlik.
	gen.on = false
	grid.tick(0.6, game)
	t.ok(bool(near_lamp.powered), "jenerator kapaliyken aku besler")
	battery.charge = 0.0
	grid.tick(0.6, game)
	t.ok(not bool(near_lamp.powered), "aku ve jenerator yoksa lamba sonuk")
	placeables.free()
	game.free()


func test_power_switch_splits_network(t) -> void:
	var placeables := Placeables.new()
	placeables.catalog = Content.placeables
	add_child(placeables)
	var grid := PowerGrid.new(placeables)
	var game := FakeGame.new()
	add_child(game)
	var gen := _place(placeables, "generator_small", Vector3i(0, 1, 0))
	gen.fuel = 4.0
	var sw := _place(placeables, "power_switch", Vector3i(5, 1, 0))
	var lamp := _place(placeables, "lamp_led", Vector3i(10, 1, 0))
	grid.tick(0.6, game)
	t.ok(bool(lamp.powered), "acik salter uzerinden lamba yanar")
	sw.on = false
	grid.mark_dirty()
	grid.tick(0.6, game)
	t.ok(not bool(lamp.powered), "kapali salter agi boler")
	placeables.free()
	game.free()


# ---------------------------------------------------------------------------
# Tarim
# ---------------------------------------------------------------------------
func test_farming_plant_water_grow_harvest(t) -> void:
	var placeables := Placeables.new()
	placeables.catalog = Content.placeables
	add_child(placeables)
	var planter := _place(placeables, "planter_box", Vector3i(0, 1, 0))
	var inv := Inventory.new(200.0, 40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	t.ok(Farming.interact(planter, inv, rng, null).contains("tohum yok"), "tohumsuz ekim olmaz")
	inv.add(ItemStack.new(Content.item("tomato_seeds"), 2, 50.0))
	Farming.interact(planter, inv, rng, null)
	t.eq(str(planter.state.seed), "tomato_seeds", "tohum ekildi")
	var hours := float(Farming.crop("tomato_seeds").hours)
	Farming.tick(planter, hours * 0.5)
	t.near(float(planter.state.growth), 0.0, 0.001, "susuz bitki buyumez")
	inv.add(ItemStack.new(Content.item("water_dirty"), 6, 0.0))
	for i in 6:
		Farming.interact(planter, inv, rng, null)
	for step in 20:
		Farming.tick(planter, hours / 10.0)
		if float(planter.state.growth) >= 1.0:
			break
		if float(planter.state.water) < 1.0:
			Farming.interact(planter, inv, rng, null)
	t.ok(float(planter.state.growth) >= 1.0, "sulanan bitki olgunlasir (%.2f)" % float(planter.state.growth))
	var msg := Farming.interact(planter, inv, rng, null)
	t.ok(msg.begins_with("Hasat"), "olgun bitki hasat edilir: %s" % msg)
	t.ok(inv.count("tomato") > 0, "urun cantaya girer")
	t.eq(str(planter.state.seed), "", "hasattan sonra saksi bos")
	placeables.free()


# ---------------------------------------------------------------------------
# Kaynak toplama
# ---------------------------------------------------------------------------
func test_gathering_only_world_blocks_with_right_tool(t) -> void:
	var world := _world()
	var gathering := Gathering.new(world)
	gathering.rng.seed = 3
	var log_mat := Content.blocks.index_of("log")
	var cell := Vector3i(3, 1, 0)
	world.set_block(cell, log_mat, VoxelWorld.ORIGIN_WORLD)
	var axe := ItemStack.new(Content.item("stone_axe"), 1, 60.0)
	var pick := ItemStack.new(Content.item("stone_pickaxe"), 1, 60.0)
	var eye := Vector3(0.5, 1.5, 0.5)
	var fwd := (Vector3(cell) + Vector3(0.5, 0.5, 0.5) - eye).normalized()
	var miss := gathering.swing(pick, eye, fwd, 5.0, 999.0)
	t.ok(not miss.hit, "kazma kutuk kesmez")
	var got: Array = []
	for i in 30:
		var r := gathering.swing(axe, eye, fwd, 5.0, 999.0)
		if r.destroyed:
			got = r.drops
			break
	t.eq(world.get_cell(cell), 0, "balta kutugu keser")
	var names := got.map(func(s: ItemStack) -> String: return s.definition.id)
	t.ok(names.has("wood_log"), "kutuk dusurur: %s" % str(names))
	# Oyuncunun koydugu blok urun vermez (somuru yok).
	world.set_block(cell, log_mat, VoxelWorld.ORIGIN_PLACED)
	var placed_drops: Array = []
	for i in 30:
		var r := gathering.swing(axe, eye, fwd, 5.0, 999.0)
		if r.destroyed:
			placed_drops = r.drops
			break
	t.eq(placed_drops.size(), 0, "oyuncu blogu toplama urunu vermez")


# ---------------------------------------------------------------------------
# Yerlestirilebilir: kati hucre, kirilinca yok olur
# ---------------------------------------------------------------------------
func test_solid_placeable_claims_cells_and_breaks(t) -> void:
	var world := _world()
	var placeables := Placeables.new()
	placeables.catalog = Content.placeables
	add_child(placeables)
	placeables.setup(world)
	var entry := _place(placeables, "workbench_basic", Vector3i(2, 1, 2))
	t.ok(not entry.cells.is_empty(), "tezgah gorunmez kati hucre alir")
	var cell: Vector3i = entry.cells[0]
	t.ok(world.get_cell(cell) != 0, "hucre dolu (carpisma, mermi)")
	t.ok(placeables.occupied(cell), "hucre dolu sayilir")
	var gone := [false]
	placeables.destroyed.connect(func(_e: Dictionary) -> void: gone[0] = true)
	world.set_block(cell, 0, VoxelWorld.ORIGIN_WORLD)
	t.ok(gone[0], "hucre kirilinca yapi yok olur")
	t.ok(not placeables.entries.has(entry), "kayitlardan duser")
	placeables.free()


func test_storage_placeable_keeps_contents(t) -> void:
	var placeables := Placeables.new()
	placeables.catalog = Content.placeables
	add_child(placeables)
	var crate := _place(placeables, "crate_small", Vector3i(0, 1, 0))
	t.ok(crate.has("inv"), "sandik envanter tasir")
	(crate.inv as Inventory).add(ItemStack.new(Content.item("nail"), 12, 50.0))
	var saved := placeables.to_dict()
	var again := Placeables.new()
	again.catalog = Content.placeables
	add_child(again)
	again.load_dict(saved)
	var loaded: Dictionary = again.entries[0]
	t.eq((loaded.inv as Inventory).count("nail"), 12, "sandik icerigi kayitta korunur")
	var out := again.take_contents(loaded)
	t.eq(out.size(), 1, "sokulen sandigin icerigi geri verilir")
	placeables.free()
	again.free()
