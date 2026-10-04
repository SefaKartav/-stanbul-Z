extends Node
## Gercek oyun sahnesinde uretim kuyrugu: adet bitiminde harcama, eksik
## malzemede DURAKLAMA (esya yakmaz), kuyruktan cikarma (iade/cogaltma yok),
## kaydet/yukle.

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


func test_queue_pause_cancel_save(t) -> void:
	var game := _make_game()
	if not await _wait_ready(game, t):
		game.free()
		return
	game.zombies.clear()
	var recipe: RecipeDef = Content.recipes["rx_rope_rags"]      # 4 bez -> 1 halat, el ile
	game.inventory.clear()
	game.inventory.add(ItemStack.new(Content.item("cloth_rag"), 8, 50.0))
	t.ok(game.start_craft(recipe, 3, game.inventory, "hands", 1), "is baslar")
	for i in 12:
		game._update_craft_job(recipe.time + 0.05)
	t.eq(game.inventory.count("rope"), 2, "malzeme yettigi kadar (2) uretildi")
	t.eq(game.inventory.count("cloth_rag"), 0, "harcanan bez tam 8")
	t.eq(game.craft_queue.size(), 1, "ucuncu adet bekliyor (is dusmedi)")
	t.ok(str(game.craft_job.get("paused", "")) != "", "eksik malzemede is DURAKLAR")
	# Ikinci is kuyruga; cikarinca hicbir sey degismez.
	var other: RecipeDef = Content.recipes["rx_whetstone_brick"]
	game.inventory.add(ItemStack.new(Content.item("loose_brick"), 2, 50.0))
	game.inventory.add(ItemStack.new(Content.item("sand"), 1, 50.0))
	t.ok(game.start_craft(other, 1, game.inventory, "hands", 1), "ikinci is kuyruga")
	t.eq(game.craft_queue.size(), 2, "kuyrukta iki is")
	game.dequeue_craft(1)
	t.eq(game.craft_queue.size(), 1, "cikarilan is gitti")
	t.eq(game.inventory.count("loose_brick"), 2, "cikarilan is malzeme yakmaz")
	# Kaydet / yukle: kalan adet korunur, malzeme gelince devam eder.
	t.ok(game.save_game("kuyruk", false), "kayit yazilir")
	game.free()
	var again := _make_game("kuyruk")
	if not await _wait_ready(again, t):
		again.free()
		return
	again.zombies.clear()
	t.eq(again.craft_queue.size(), 1, "kuyruk kayittan geri gelir")
	t.eq(int(again.craft_queue[0].remaining), 1, "kalan adet korunur")
	t.eq(again.inventory.count("rope"), 2, "uretilen halat korunur (cogalma yok)")
	again.inventory.add(ItemStack.new(Content.item("cloth_rag"), 4, 50.0))
	for i in 4:
		again._update_craft_job(recipe.time + 0.05)
	t.eq(again.inventory.count("rope"), 3, "malzeme gelince is kendiliginden tamamlanir")
	t.eq(again.craft_queue.size(), 0, "biten is kuyruktan duser")
	again.free()
