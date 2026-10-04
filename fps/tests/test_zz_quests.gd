extends Node
## Gorev omurgasi gercek oyun sahnesinde: olay -> ilerleme, odul BIR KEZ,
## kaydet/yukle, gorev nesnesi, savunma, kaybolan gorev esyasi, olen kisi.

const SAVE_DIR := "user://test_saves_quest/"


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for f in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute(SAVE_DIR + f)


func _make_game(load_slot: String = "") -> Game:
	var game: Game = load("res://src/game/game.gd").new()
	game.start_site = "kadikoy"
	game.save_directory = SAVE_DIR
	game.load_slot = load_slot
	add_child(game)
	return game


func _ready_wait(game: Game, t) -> bool:
	var waited := 0.0
	while not game.ready_for_play and waited < 90.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	t.ok(game.ready_for_play, "dunya hazir")
	return game.ready_for_play


func test_quest_chain_rewards_once(t) -> void:
	_cleanup()
	var game := _make_game()
	if not await _ready_wait(game, t):
		game.free()
		return
	var q := game.quests
	t.eq(str(q.active_main().get("id", "")), "m01", "ilk ana gorev m01")
	var tabs_before := game.inventory.count("purification_tabs")
	q.notify("water_filled", {})
	t.ok(q.done.has("m01"), "olay gorevi tamamlar")
	t.eq(game.inventory.count("purification_tabs"), tabs_before + 3, "odul verildi")
	t.eq(str(q.active_main().get("id", "")), "m02", "sonraki adim acildi")
	q.notify("craft", {"recipe": "r_weapon_rifle"})
	t.ok(not q.done.has("m02"), "ilgisiz uretim sayilmaz")
	t.ok(game.save_game("gorev", false), "kaydedildi")
	game.free()
	var again := _make_game("gorev")
	if not await _ready_wait(again, t):
		again.free()
		return
	t.ok(again.quests.done.has("m01"), "tamamlanan gorev kayitta")
	t.eq(again.inventory.count("purification_tabs"), tabs_before + 3, "odul yuklemede TEKRAR verilmez")
	again.quests.notify("water_filled", {})
	t.eq(again.inventory.count("purification_tabs"), tabs_before + 3, "tamamlanmis gorev olayla yeniden odullenmez")
	again.quests.notify("craft", {"recipe": "r_purify_tablet"})
	t.ok(again.quests.done.has("m02"), "dogru tarif m02'yi bitirir")
	t.ok(again.quests.hud_line() != "", "HUD hedef satiri")
	var entries := again.quests.journal_entries()
	t.ok(entries.size() >= 3, "gunlukte gorevler")
	again.free()
	_cleanup()


func test_fetch_defend_and_lost_item(t) -> void:
	_cleanup()
	var game := _make_game()
	if not await _ready_wait(game, t):
		game.free()
		return
	var q := game.quests
	for id in ["m01", "m02", "m03", "m04", "m05", "m06", "m07"]:
		q.done[id] = true
	q.tick(1.0)
	t.eq(str(q.active_main().id), "m08", "m08 aktif")
	var prop: Dictionary = game.props.get_entry(QuestSystem.PROP_PREFIX + "m08:0")
	t.ok(not prop.is_empty(), "gorev nesnesi dunyaya kondu")
	t.ok(prop.get("pos", Vector3.INF) != Vector3.INF, "konum OSM'den cozuldu")
	# Etkilesim: esya alinir, gorev ilerler.
	var inter := q.interaction_for(prop, "E")
	t.eq(str(inter.get("kind", "")), "mission", "etkilesim sunulur")
	q._finish_interact("m08", "m08:0")
	t.eq(game.inventory.count("pump_impeller"), 1, "pervane alindi")
	q.tick(1.0)
	t.ok(q.done.has("m08"), "fetch esya cantadayken tamamlanir")
	# Esya kaybolur: m09 kilitlenmemeli, yedek belirmeli.
	game.inventory.remove("pump_impeller", 1)
	q.tick(1.0)
	var backup: Dictionary = game.props.get_entry(QuestSystem.PROP_PREFIX + "yedek:pump_impeller")
	t.ok(not backup.is_empty() and not backup.get("removed", false), "kaybolan gorev esyasinin yedegi belirir")
	q.interact(q.interaction_for(backup, "E"))
	t.eq(game.inventory.count("pump_impeller"), 1, "yedekten yeniden alinir")
	# m09: ihtiyaclari ver, etkilesim -> savunma dalgasi.
	game.inventory.add(ItemStack.new(Content.item("pvc_pipe"), 3, 50.0))
	game.inventory.add(ItemStack.new(Content.item("nail"), 10, 0.0))
	q.tick(1.0)
	q._finish_interact("m09", "m09:0")
	t.eq(game.inventory.count("pump_impeller"), 0, "ihtiyac harcandi")
	var key := "m09:0"
	t.ok(q.defend.has(key) and (q.defend[key] as Array).size() > 0, "savunma zombileri dogdu")
	# Tekrar etkilesim ihtiyaci IKINCI KEZ harcamaz (yarim kalan savunma).
	var paid_items := game.inventory.count("pvc_pipe")
	q.defend.erase(key)
	q._finish_interact("m09", key)
	t.eq(game.inventory.count("pvc_pipe"), paid_items, "yeniden baslatilan savunma bedava")
	for id: int in q.defend.get(key, []):
		var z: Object = instance_from_id(id)
		if z != null and is_instance_valid(z):
			(z as Zombie).receive_damage(99999.0, "true", Vector3.FORWARD, Vector3.ZERO, null, "body")
	q.tick(1.0)
	t.ok(q.done.has("m09"), "saldiri puskurtulunce gorev biter")
	t.ok(q.flags.has("water_line"), "dunya durumu: su hatti")
	game.free()
	_cleanup()


func test_rescue_target_death_has_alternative(t) -> void:
	_cleanup()
	var game := _make_game()
	if not await _ready_wait(game, t):
		game.free()
		return
	var q := game.quests
	for id in ["m01", "m02", "m03", "m04", "m05", "m06"]:
		q.done[id] = true
	var m07 := QuestSystem.quest("m07")
	var obj := q.objective(m07)
	t.eq(q._rescue_profile(m07, obj), "hakan", "hedef kisi")
	game.survivors.rescued["hakan"] = true        # oldu (sakin degil)
	var alt := q._rescue_profile(m07, obj)
	t.ok(alt != "hakan" and alt != "", "olen kisinin yerine baska biri (%s)" % alt)
	game.free()
	_cleanup()
