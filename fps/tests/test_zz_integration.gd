extends Node
## UCTAN UCA: gercek oyun sahnesi + gercek Kadikoy haritasi.
##
## Belgenin elle dogrulanacak akisinin otomatiklestirilebilen parcasi:
## blok kir/hasarla/koy, binayi disaridan ara, kaydet, oyunu KAPAT, yeniden
## ac -> hasarli bloklar, yikilan yer, konan blok, envanter, bina arama
## hakki, depo ve zaman korunmus olmali. Ayrica uyumsuz kayit ACILMAMALI
## ve dosyasi korunmali.

const SAVE_DIR := "user://test_saves/"


func _make_game(load_slot: String = "") -> Game:
	var game: Game = load("res://src/game/game.gd").new()
	game.start_site = "kadikoy"
	game.save_directory = SAVE_DIR
	game.load_slot = load_slot
	add_child(game)
	return game


func _wait_ready(game: Game, t) -> bool:
	var waited := 0.0
	while not game.ready_for_play and waited < 90.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	t.ok(game.ready_for_play, "dunya 90 sn icinde hazir olmali")
	return game.ready_for_play


func _cleanup_saves() -> void:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for file_name in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute(SAVE_DIR + file_name)


func test_save_close_reopen_keeps_world(t) -> void:
	_cleanup_saves()
	var game := _make_game()
	if not await _wait_ready(game, t):
		game.free()
		return
	game.zombies.clear()
	var p := game.player.global_position
	var world := game.world
	# 1) Oyuncunun yanina bir tahta duvar koy, bir tanesini hasarla.
	var base_cell := Vector3i(floori(p.x) + 2, floori(p.y), floori(p.z))
	var wood := Content.blocks.index_of("wood")
	world.set_block(base_cell, wood, VoxelWorld.ORIGIN_PLACED)
	world.set_block(base_cell + Vector3i.UP, wood, VoxelWorld.ORIGIN_PLACED)
	world.apply_damage(base_cell + Vector3i.UP, 25.0)
	# 2) Zemini kir (haritanin kendi blogu).
	var ground := Vector3i(floori(p.x) - 2, floori(p.y) - 1, floori(p.z))
	var ground_before := world.get_cell(ground)
	world.set_block(ground, 0, VoxelWorld.ORIGIN_WORLD)
	# 3) Yakindaki bir binada bir dolabi ara (sureyi atla), bir esya al, kalanini birak.
	var target := _nearby_container(game)
	t.ok(not target.is_empty(), "dogus cevresinde aranabilir dolap olmali")
	var container_id := ""
	var left_count := -1
	if not target.is_empty():
		container_id = target.f.id
		game.search.begin(target.plan, target.f, p)
		game.search.update(999.0, p)
		t.ok(game.containers.state(container_id).r, "arama bitince zar atilmis olmali")
		if game.current_screen != null:
			game.close_screen()
		var items: Array = game.containers.items(container_id)
		if not items.is_empty():
			game.containers.take(container_id, 0, 1, game.inventory)
		left_count = _count(game.containers.items(container_id))
	# 4) Envanter ve zaman
	game.inventory.add(ItemStack.new(Content.item("sand"), 7))
	var sand := game.inventory.count("sand")
	game.time.normalized = 0.61
	t.ok(game.save_game("entegrasyon", false), "kayit yazilmali: %s" % game.saves.last_error)
	game.free()

	# --- yeniden ac ---
	var again := _make_game("entegrasyon")
	if not await _wait_ready(again, t):
		again.free()
		return
	var w2 := again.world
	t.eq(w2.get_cell(base_cell), wood, "konan blok kalmali")
	t.near(w2.hp_of(base_cell + Vector3i.UP), 35.0, 0.01, "kismi HP korunmali")
	t.ok(w2.placed.has(base_cell), "oyuncu kokeni korunmali (kirilinca dusus yok)")
	t.eq(w2.get_cell(ground), 0, "kirilan zemin geri gelmemeli (onceden %d idi)" % ground_before)
	t.eq(again.inventory.count("sand"), sand, "envanter korunmali")
	t.near(again.time.normalized, 0.61, 0.01, "zaman korunmali")
	if container_id != "":
		t.ok(again.containers.state(container_id).r, "aranmis dolap kayitta aranmis kalmali (yeniden zar yok)")
		t.eq(_count(again.containers.items(container_id)), left_count, "dolapta kalan esya aynen korunmali")
	again.free()


static func _count(stacks: Array) -> int:
	var n := 0
	for s: ItemStack in stacks:
		n += s.quantity
	return n


static func _nearby_container(game: Game) -> Dictionary:
	var city: CityGenerator = game.generator
	for index: int in city.buildings_near(game.player.global_position, 80.0):
		var plan := city.interior_plan(index)
		if not plan.get("ok", false):
			continue
		for f: Dictionary in plan.furniture:
			if f.container != "" and int(f.floor) == 0:
				return {"plan": plan, "f": f}
	return {}


func test_real_v1_save_migrates(t) -> void:
	## Kullanicinin GERCEK v1 kaydi (bina arama haklari, eski uretici): acilir,
	## aranmis binalar ikinci kez tam odul vermez, oyuncu duvara gomulmez.
	_cleanup_saves()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	# Gercek kayda oyuncunun yaninda kirilmis bir zemin hucresi ve konmus bir
	# kum torbasi eklenir (v1 bicimi korunur): goc sonrasi ikisi de yerinde olmali.
	var source := FileAccess.open_compressed("res://tests/fixtures/eski_v1_autosave.izfps", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var raw: Dictionary = JSON.parse_string(source.get_as_text())
	source.close()
	var hole := Vector3i(1636, 13, 5148)
	var sandbag := Vector3i(1628, 14, 5150)
	raw.world.voxels.modified = [[hole.x, hole.y, hole.z, 0, 0],
		[sandbag.x, sandbag.y, sandbag.z, Content.blocks.index_of("sandbag"), 1]]
	var target := FileAccess.open_compressed(SAVE_DIR + "eski.izfps", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	target.store_string(JSON.stringify(raw))
	target.close()
	var game: Game = load("res://src/game/game.gd").new()
	game.save_directory = SAVE_DIR
	game.load_slot = "eski"
	add_child(game)
	if not await _wait_ready(game, t):
		game.free()
		return
	## OLCEK GOCU (0.65 -> 1:1): konum cografi olarak korunur, blok farklari
	## tasinamaz ama RAPORLANIR, kaynak dosya yedeklenir, aranmis binalar
	## ikinci kez odul vermez.
	t.ok(not game.load_failed, "v1 kayit acilmali (olcek gocu tanimli)")
	t.eq(game.map_id, "maltepe_besiktas", "kaydin haritasi")
	var report: Dictionary = game._migration_report
	t.ok(not report.is_empty(), "goc raporu uretilmeli")
	var city: CityGenerator = game.generator
	# Cografi denklik: eski konum (eski donusum) ile yeni konum (yeni donusum)
	# ayni yere isaret etmeli (acik hucre aramasi payi 60 m).
	var legacy := GeoTransform.from_map(SaveMigration.legacy_entry("maltepe_besiktas"))
	var old_p: Array = raw.player.body.position
	var old_geo := legacy.inverse(Vector2(float(old_p[0]), float(old_p[2])))
	var new_geo := city.geo.inverse(Vector2(game.player.global_position.x, game.player.global_position.z))
	var error_m := GeoTransform.haversine(old_geo, new_geo)
	print("  goc: oyuncu %.1f m sapma; rapor %s" % [error_m, JSON.stringify(report.get("dropped", {}))])
	t.ok(error_m < 60.0, "oyuncu cografi olarak ayni yerde kalmali (%.1f m)" % error_m)
	t.eq(int(report.dropped.modified_cells), 2, "tasinamayan blok farki sayilmali (sessiz kayip yok)")
	t.eq(game.world.modified.size(), 0, "eski izgaranin farklari yeni dunyaya yanlis yere yazilmamali")
	t.ok(FileAccess.file_exists(SAVE_DIR + "eski_olcek065_yedek.izfps"), "kaynak kayit yedeklenmeli")
	var emptied := 0
	for bid: String in ["w179197238", "w179197266"]:     # eski kayitta 3 kez aranmis
		for i in city.buildings.size():
			if city.buildings[i].id != bid:
				continue
			var plan := city.interior_plan(i)
			if not plan.get("ok", false):
				continue
			for f: Dictionary in plan.furniture:
				if f.container != "" and int(f.floor) == 0 and game.containers.status(f) == "empty":
					emptied += 1
	t.ok(emptied > 0 or not game.containers.migrated.has("w179197238"), "aranmis binanin dolaplari bos gelmeli (%d)" % emptied)
	t.ok(not VoxelBody.is_blocked(game.world, game.player.global_position, Player.HALF_WIDTH, Player.STAND_HEIGHT),
		"oyuncu duvar/mobilya icinde dogmamali")
	# Tekrar kaydet: artik v3 olarak yazilir ve yeniden gocmez.
	t.ok(game.save_game("eski", false), "v3 olarak kaydedilmeli")
	game.free()
	var saves := SaveSystem.new()
	saves.directory = SAVE_DIR
	var again := saves.read("eski")
	t.eq(int(again.get("version", 0)), SaveSystem.VERSION, "yeni kayit v3")
	t.eq(int(again.get("world", {}).get("generator_version", 0)), CityGenerator.GENERATOR_VERSION, "yeni uretici surumu")
	t.ok(not SaveMigration.applies(again, "maltepe_besiktas", CityGenerator.GENERATOR_VERSION), "ikinci kez gocmez")
	_cleanup_saves()


func test_user_v2_save_migrates(t) -> void:
	## Kullanicinin 25 Eylul'deki GERCEK v2 otomatik kaydi (0.65 harita, 2. gun,
	## 52 arac): 1:1 haritada acilir, envanter/zaman/ilerleme korunur.
	_cleanup_saves()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var source := FileAccess.open_compressed("res://tests/fixtures/kullanici_v2_autosave.izfps", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var raw: Dictionary = JSON.parse_string(source.get_as_text())
	source.close()
	var target := FileAccess.open_compressed(SAVE_DIR + "kullanici.izfps", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	target.store_string(JSON.stringify(raw))
	target.close()
	var game: Game = load("res://src/game/game.gd").new()
	game.save_directory = SAVE_DIR
	game.load_slot = "kullanici"
	add_child(game)
	if not await _wait_ready(game, t):
		game.free()
		return
	t.ok(not game.load_failed, "kullanicinin v2 kaydi acilmali")
	t.eq(game.time.day, int(raw.time.day), "gun korunmali")
	var old_count := 0
	for s: Dictionary in raw.player.inventory.stacks:
		old_count += int(s.get("n", 1))
	var new_count := 0
	for s: ItemStack in game.inventory.stacks:
		new_count += s.quantity
	t.eq(new_count, old_count, "envanter adedi korunmali")
	t.eq(game.vehicles.entries.size(), (raw.vehicles.entries as Array).size(), "araclar tasinmali")
	t.ok(game.vitals.satiety >= 79.0 and game.vitals.hydration >= 79.0, "eski kayitta ihtiyac yok: guvenli varsayilan")
	t.ok(not VoxelBody.is_blocked(game.world, game.player.global_position, Player.HALF_WIDTH, Player.STAND_HEIGHT),
		"oyuncu acik bir yerde")
	game.free()
	_cleanup_saves()


func test_gear_throwables_and_schematics(t) -> void:
	## Faz D sistemleri gercek oyun sahnesinde: kusanma, sema kilidi,
	## firlatilabilirlerin blok kurali (boru bombasi silahtir, molotof kirmaz).
	_cleanup_saves()
	var game := _make_game()
	if not await _wait_ready(game, t):
		game.free()
		return
	game.zombies.clear()
	# --- kusanma: canta kapasite, zirh hasar azaltir ---
	var capacity := game.inventory.capacity_kg
	game.inventory.add(ItemStack.new(Content.item("backpack_large"), 1))
	game.inventory.add(ItemStack.new(Content.item("scrap_armor"), 1, 100.0))
	t.ok(game.equip_item(game.inventory.find("backpack_large")).begins_with("Kusanildi"), "canta kusanilmali")
	t.ok(game.inventory.capacity_kg >= capacity + 20.0, "canta kapasiteyi artirmali (%.0f -> %.0f)" % [capacity, game.inventory.capacity_kg])
	t.ok(game.equip_item(game.inventory.find("scrap_armor")).begins_with("Kusanildi"), "zirh kusanilmali")
	var dealt := game.vitals.take_hit(20.0, "physical", Vector3.FORWARD)
	t.near(dealt, 20.0 - 4.0 * 1.3, 0.01, "zirh (kalite 100) hasari azaltmali")
	# --- sema: kilitli tarif, bulununca oyuncu ve koloni icin acilir ---
	var rifle: RecipeDef = Content.recipes["r_weapon_rifle"]
	var before: Dictionary = game.crafting.check(game.inventory, rifle, rifle.station, 3)
	t.ok(bool(before.get("locked", false)) and rifle.learn_kind() == "schematic",
		"kilitli tarif sema istemeli (%s)" % before.reason)
	t.ok(str(before.reason).contains("ema"), "kilidin acilma yolu yazilmali (%s)" % before.reason)
	game.crafting.known_recipes[rifle.id] = true
	var after: Dictionary = game.crafting.check(game.inventory, rifle, rifle.station, 3)
	t.ok(not bool(after.get("locked", false)), "sema bulununca kilit kalkmali")
	t.ok(game.bases.colony.crafting.known_recipes.has(rifle.id), "sema koloni zanaatkariyla paylasilmali")
	# --- firlatilabilirler ---
	var p := game.player.global_position
	var wood := Content.blocks.index_of("wood")
	var wall := Vector3i(floori(p.x) + 6, floori(p.y) + 1, floori(p.z))
	for dz in range(-1, 2):
		game.world.set_block(wall + Vector3i(0, 0, dz), wood, VoxelWorld.ORIGIN_PLACED)
	var fire_cell := wall + Vector3i(0, 0, -1)
	game.throwables._land(Content.item("molotov"), 100.0, Vector3(wall) + Vector3(-0.3, 0.5, -0.5))
	t.near(game.world.hp_of(fire_cell), Content.blocks.max_hp[wood], 0.01, "molotof blok kirmamali")
	# Zombi patlamanin OYUNCU tarafinda (acik alan; 1:1 haritada duvarin
	# arkasi bir bina cephesine denk gelebiliyordu).
	var zombie := game.zombies.spawn(Content.zombies["walker"], Vector3(wall) + Vector3(-1.4, -1.0, 0.5))
	# Patlama ile zombi arasi acik olsun (1:1 haritada sokak dekoru degisken).
	for x in range(wall.x - 3, wall.x):
		for z in range(wall.z - 1, wall.z + 2):
			for y in range(wall.y, wall.y + 2):
				game.world.set_block(Vector3i(x, y, z), 0, VoxelWorld.ORIGIN_WORLD)
	game.actors.rebuild()
	var zombie_health := zombie.health
	game.vitals.health = 1000.0
	game.throwables._land(Content.item("pipe_bomb"), 100.0, Vector3(wall) + Vector3(-0.3, 0.5, 0.5))
	var broken := 0
	for dz in range(-1, 2):
		var cell := wall + Vector3i(0, 0, dz)
		if game.world.get_cell(cell) == 0 or game.world.hp_of(cell) < Content.blocks.max_hp[wood]:
			broken += 1
	t.ok(broken >= 2, "boru bombasi yakin bloklari hasarlamali (%d)" % broken)
	t.ok(not is_instance_valid(zombie) or zombie.health < zombie_health, "boru bombasi zombiyi yaralamali")
	# --- sema ve kusanma kayitta korunur ---
	t.ok(game.save_game("donanim", false), "kayit yazilmali")
	game.free()
	var again := _make_game("donanim")
	if not await _wait_ready(again, t):
		again.free()
		return
	t.ok(again.crafting.known_recipes.has(rifle.id), "sema kayitta korunmali")
	t.ok(again.equipment.armor != null and again.equipment.backpack != null, "kusanilanlar kayitta korunmali")
	t.ok(again.vitals.armor > 0.0, "yuklenen zirh etkin olmali")
	again.free()
	_cleanup_saves()


func test_incompatible_save_is_refused_and_kept(t) -> void:
	_cleanup_saves()
	var saves := SaveSystem.new()
	saves.directory = SAVE_DIR
	t.ok(saves.write("baska_harita", {"world": {"site": "kadikoy", "map_id": "istanbul_tamami",
		"generator_version": 1, "voxels": {}}, "time": {"day": 3}}))
	var game := _make_game("baska_harita")
	for _i in 5:
		await get_tree().process_frame
	t.ok(game.load_failed, "uyumsuz kayit acilmamali")
	t.ok(FileAccess.file_exists(SAVE_DIR + "baska_harita.izfps"), "uyumsuz kayit dosyasi korunmali")
	if is_instance_valid(game):
		game.free()


func test_corrupt_save_falls_back_to_backup(t) -> void:
	_cleanup_saves()
	var saves := SaveSystem.new()
	saves.directory = SAVE_DIR
	t.ok(saves.write("bozuk", {"world": {"map_id": "kadikoy"}, "time": {"day": 1}}))
	t.ok(saves.write("bozuk", {"world": {"map_id": "kadikoy"}, "time": {"day": 2}}))
	# Ana dosyayi boz: yedek (gun 1) yuklenmeli, ana dosya SILINMEMELI.
	var file := FileAccess.open(SAVE_DIR + "bozuk.izfps", FileAccess.WRITE)
	file.store_string("bu bir kayit degil")
	file.close()
	var data := saves.read("bozuk")
	t.eq(int(data.get("time", {}).get("day", -1)), 1, "yedek yuklenmeli")
	t.ok(saves.last_error.contains("yedek"), "oyuncuya yedekten yuklendigi soylenmeli")
	t.ok(FileAccess.file_exists(SAVE_DIR + "bozuk.izfps"), "bozuk dosya silinmemeli")
	_cleanup_saves()
