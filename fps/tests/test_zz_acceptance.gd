extends Node
## Belgenin kabul maddesi 5 (gercek oyun sahnesi): jeneratoru besle ve kapat,
## lamba sonsun; tareti besle; suyu aritmak icin uret; yemegi tuket; araca
## parca tak; kaydet/yukle -> somut etkiler korunur. (Kapi ac/kir, duvar yik
## ve merdiven: test_interiors / test_build.)

const SAVE_DIR := "user://test_saves_accept/"


func _make_game(load_slot: String = "") -> Game:
	var game: Game = load("res://src/game/game.gd").new()
	game.start_site = "kadikoy"
	game.save_directory = SAVE_DIR
	game.load_slot = load_slot
	add_child(game)
	return game


func _wait(game: Game, t) -> bool:
	var waited := 0.0
	while not game.ready_for_play and waited < 90.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	t.ok(game.ready_for_play, "dunya hazir")
	return game.ready_for_play


func test_concrete_effects_survive_save(t) -> void:
	var game := _make_game()
	if not await _wait(game, t):
		game.free()
		return
	game.zombies.clear()
	var base := Vector3i(floori(game.player.global_position.x) + 3, floori(game.player.global_position.y),
		floori(game.player.global_position.z) + 3)
	# 1) Jenerator + lamba: yakit koy, calisir; kapat, lamba soner.
	var gen := game.placeables.place(ItemStack.new(Content.item("generator_small"), 1, 50.0), base, 0)
	var lamp := game.placeables.place(ItemStack.new(Content.item("lamp_led"), 1, 50.0), base + Vector3i(3, 0, 0), 0)
	game.inventory.add(ItemStack.new(Content.item("gasoline"), 2, 50.0))
	game._use_placeable(gen)
	t.ok(float(gen.fuel) > 0.0 and bool(gen.on), "jenerator yakitla calisir")
	game.power.mark_dirty()
	game.power.tick(0.6, game)
	t.ok(bool(lamp.powered), "lamba yanar")
	game._use_placeable(gen)          # yakit yok -> ac/kapa
	t.ok(not bool(gen.on), "jenerator kapatildi")
	game.power.tick(0.6, game)
	t.ok(not bool(lamp.powered), "jenerator kapaninca lamba soner (aku yok)")
	# 2) Tareti besle.
	var turret := game.placeables.place(ItemStack.new(Content.item("turret_dart"), 1, 50.0), base + Vector3i(0, 0, 4), 0)
	game.inventory.add(ItemStack.new(Content.item("bolt"), 10, 50.0))
	game._use_placeable(turret)
	t.eq(int(turret.ammo), 10, "taret 10 ok ile beslendi")
	# 3) Suyu arit (gercek tarif yolu).
	var recipe: RecipeDef = Content.recipes["r_water_ceramic"]
	game.inventory.add(ItemStack.new(Content.item("water_dirty"), 4, 50.0))
	game.inventory.add(ItemStack.new(Content.item("ceramic_filter"), 1, 60.0))
	game.crafting.known_recipes[recipe.id] = true
	var clean_before := game.inventory.count("water_bottle")
	var result := game.crafting.craft(game.inventory, recipe, recipe.station, 5, 0.0)
	t.ok(result.success, "aritma tarifi uretir: %s" % result.get("reason", ""))
	t.eq(game.inventory.count("water_bottle"), clean_before + recipe.output_count, "temiz su arttı")
	# 4) Yemek tuket.
	game.vitals.satiety = 30.0
	game.inventory.add(ItemStack.new(Content.item("lentil_soup"), 1, 60.0))
	var soup := game.inventory.find("lentil_soup")
	var used := ItemUsage.use(soup, game.vitals, game.inventory, game.skills, RandomNumberGenerator.new())
	t.ok(used.ok and game.vitals.satiety > 45.0, "corba tokluk verdi (%.0f)" % game.vitals.satiety)
	# 5) Araca parca tak.
	t.ok(not game.vehicles.entries.is_empty(), "park etmis arac var")
	var car: Dictionary = game.vehicles.entries[0]
	var cap_before: float = (car.trunk as Inventory).capacity_kg
	game.inventory.add(ItemStack.new(Content.item("roof_rack"), 1, 60.0))
	var msg := game.vehicles.install_part(car, game.inventory.find("roof_rack"), game.inventory)
	t.ok((car.trunk as Inventory).capacity_kg > cap_before, "tavan bagaji kapasite ekledi: %s" % msg)
	var car_pos: Vector3 = car.position
	t.ok(game.save_game("kabul", false), "kaydedildi")
	game.free()
	# --- yeniden ac ---
	var again := _make_game("kabul")
	if not await _wait(again, t):
		again.free()
		return
	var g2 := {}
	var t2 := {}
	for e: Dictionary in again.placeables.entries:
		if e.item_id == "generator_small":
			g2 = e
		elif e.item_id == "turret_dart":
			t2 = e
	t.ok(not g2.is_empty() and float(g2.fuel) > 0.0 and not bool(g2.on), "jenerator yakiti ve kapali hali korunur")
	t.eq(int(t2.get("ammo", -1)), 10, "taret mermisi korunur")
	var car2: Dictionary = {}
	for e: Dictionary in again.vehicles.entries:
		if (e.position as Vector3).distance_to(car_pos) < 1.0:
			car2 = e
	t.ok(not car2.is_empty() and (car2.get("parts", {}) as Dictionary).has("rack"), "arac parcasi kayitta")
	t.ok(again.inventory.count("water_bottle") >= clean_before + recipe.output_count, "uretilen su kayitta")
	again.free()
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for f in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute(SAVE_DIR + f)
