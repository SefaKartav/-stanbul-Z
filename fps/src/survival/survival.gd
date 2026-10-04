class_name Survival
extends RefCounted
## Kisisel hayatta kalma servisi: aclik/susuzluk tiki, bozulma, soguk oda,
## yagmur varili, hizli ye/ic ve su kaynagindan doldurma.
##
## ZAMAN: tek ortak kaynak TimeOfDay'dir. Gecen oyun saati her fizik adiminda
## `delta * time.hours_per_second()` olarak hesaplanir; duraklatan menude
## fizik adimi calismaz, uyku/olum/yukleme atlamalari `skip_hours` ile TEK
## SEFER islenir (ayni saat iki kez sayilmaz).
##
## BOZULMA: pisirilmis yemek gibi raf omru olan esya yiginin `expires`
## alanina dunya saati olarak damgalanir; sure dolunca yigin ayni adetle
## bozuk esyaya donusur. Kaydet/yukle saati SIFIRLAMAZ. Ussun soguk odasi
## (yakitla) o ussun deposunda bozulmayi 4 kat yavaslatir.

const SPOIL_CHECK_HOURS := 0.25
const FILL_SECONDS := 2.2

var game: Node
var rng := RandomNumberGenerator.new()
var _spoil_timer := 0.0
var _last_drink_warning := -100.0


func _init(p_game: Node) -> void:
	game = p_game
	rng.randomize()


func activity() -> String:
	var player: Player = game.player
	if player.sprinting:
		return "sprint"
	var flat := Vector2(player.velocity.x, player.velocity.z).length()
	var base := "idle"
	if flat > Player.WALK_SPEED + 0.4:
		base = "run"
	elif flat > 0.3:
		base = "walk"
	if game.inventory.overloaded():
		return "overloaded" if base != "run" else "run"
	return base


func tick(delta: float) -> void:
	var hours: float = delta * game.time.hours_per_second()
	var vitals: PlayerVitals = game.vitals
	vitals.tick_needs(hours, activity(), game.skills)
	game.player.stamina_cap = vitals.stamina_cap() + game.skills.bonus("stamina_max") + game.equipment_bonus("stamina_bonus")
	game.player.regen_factor = vitals.regen_factor()
	_spoil_timer += hours
	if _spoil_timer >= SPOIL_CHECK_HOURS:
		_spoil_timer = 0.0
		update_spoilage()


# ---------------------------------------------------------------------------
# Bozulma
# ---------------------------------------------------------------------------
func now() -> float:
	return game.time.total_hours()


static func stamp(inventory: Inventory, now_hours: float) -> void:
	## Raf omru olan ama henuz damgalanmamis yiginlara son kullanma yaz.
	for stack: ItemStack in inventory.stacks:
		if stack.expires >= 0.0:
			continue
		var life := float(Content.nutrition_of(stack.definition.id).get("shelf_life_h", 0.0))
		if life > 0.0:
			stack.expires = now_hours + life


static func spoil(inventory: Inventory, now_hours: float) -> int:
	## Suresi dolan yiginlari bozuk esyaya cevirir; donusen adet.
	var changed := 0
	var fresh: Array = []
	for stack: ItemStack in inventory.stacks:
		if stack.expires >= 0.0 and stack.expires <= now_hours:
			var into := str(Content.nutrition_of(stack.definition.id).get("spoils_to", ""))
			var def: ItemDef = Content.item(into)
			if def != null:
				fresh.append(ItemStack.new(def, stack.quantity, 0.0))
				changed += stack.quantity
				stack.quantity = 0
	if changed > 0:
		inventory.compact()
		for stack: ItemStack in fresh:
			if inventory.add(stack) > 0:
				pass   # bozuk yemek sigmazsa yok olur (zaten degersiz); adet raporlanir
	return changed


func update_spoilage() -> void:
	var t := now()
	stamp(game.inventory, t)
	var lost := spoil(game.inventory, t)
	if lost > 0:
		game.hud.message("%d porsiyon yemek bozuldu (cantada)" % lost, Hud.RED)
	for base: Settlement in game.bases.settlements:
		stamp(base.stockpile, t)
		if cold_room_active(base):
			# Soguk oda: gecen her saatin 3/4'u kadar son kullanma ileri kayar.
			for stack: ItemStack in base.stockpile.stacks:
				if stack.expires >= 0.0:
					stack.expires += SPOIL_CHECK_HOURS * 0.75
		spoil(base.stockpile, t)


func cold_room_active(base: Settlement) -> bool:
	## Yakitli soguk oda (ussun deposundan gunluk yakit) YA DA elektrikli
	## buzdolabi (catalog power > 0: aginda guc varsa).
	for entry: Dictionary in game.placeables.entries:
		if entry.kind != "cold_room" or not base.contains_position(Vector3(entry.cell)):
			continue
		if PowerGrid.draw_of(game.placeables.info_of(entry)) > 0.0:
			if bool(entry.powered):
				return true
		elif bool(base.get_meta("cold_fuelled", false)):
			return true
	return false


func on_new_day(day: int) -> Array:
	## Gunluk: yagmur varilleri depoya kirli su koyar, soguk odalar yakit yer.
	## Donus: [[mesaj, renk]]
	var messages: Array = []
	for base: Settlement in game.bases.settlements:
		var barrels := 0
		var rooms := 0
		var rain_amount := 0
		var r := RandomNumberGenerator.new()
		r.seed = hash("%s:%d" % [base.id, day])
		for entry: Dictionary in game.placeables.entries:
			if not base.contains_position(Vector3(entry.cell)):
				continue
			if entry.kind == "rain_collector":
				barrels += 1
				# Toplayicinin gunluk araligi katalogdan (varil 1-4, sarnic 3-7).
				var daily: Array = game.placeables.info_of(entry).get("daily", [1, 4])
				rain_amount += r.randi_range(int(daily[0]), int(daily[1])) + (2 if game.skills.has_behavior("rain_bonus") else 0)
			elif entry.kind == "cold_room" and PowerGrid.draw_of(game.placeables.info_of(entry)) <= 0.0:
				rooms += 1
		if barrels > 0:
			# Istanbul yagisi: sabit tohum (gun + us), toplayici basina aralik.
			var amount := rain_amount
			var left := base.stockpile.add(ItemStack.new(Content.item("water_dirty"), amount, 0.0))
			messages.append(["%s: yagmur varillerine %d sise kirli su toplandi%s" % [base.name, amount - left,
				"" if left == 0 else " (depo dolu, %d tasti)" % left], Hud.BLUE])
		if rooms > 0:
			var fuel := base.stockpile.matching_tag("chemical_fuel")
			if not fuel.is_empty():
				base.stockpile.take_from_stack(fuel[0], rooms)
				base.set_meta("cold_fuelled", true)
			else:
				base.set_meta("cold_fuelled", false)
				messages.append(["%s: soguk oda yakitsiz kaldi -- yemekler normal hizda bozulacak" % base.name, Hud.RED])
	return messages


# ---------------------------------------------------------------------------
# Hizli ye / ic
# ---------------------------------------------------------------------------
func best(kind: String) -> ItemStack:
	## "food": en cok doyuran ve EN ERKEN bozulacak once; "water": temiz su
	## once, kirli su yalnizca baska su yoksa.
	var best_stack: ItemStack = null
	var best_score := -INF
	for stack: ItemStack in game.inventory.stacks:
		var info := Content.nutrition_of(stack.definition.id)
		if info.is_empty() or bool(info.get("raw", false)):
			continue
		var value := float(info.get(kind, 0.0))
		if value <= 0.0:
			continue
		var score := value - float(info.get("illness", 0.0)) * 200.0
		if stack.expires >= 0.0:
			score += 30.0 - clampf(stack.expires - now(), 0.0, 30.0)   # yakinda bozulacak once
		if score > best_score:
			best_score = score
			best_stack = stack
	return best_stack


func quick(kind: String) -> void:
	var stack := best(kind)
	if stack == null:
		game.hud.message("Cantanda %s yok" % ("yenecek bir sey" if kind == "food" else "icilecek su"), Hud.RED)
		return
	var info := Content.nutrition_of(stack.definition.id)
	if float(info.get("illness", 0.0)) > 0.0:
		# Riskli tuketim ikinci basista onaylanir (3 sn icinde).
		var t := Time.get_ticks_msec() / 1000.0
		if t - _last_drink_warning > 3.0:
			_last_drink_warning = t
			game.hud.message("Elindeki tek secenek %s (%%%d mide bulantisi riski). Yine de tuketmek icin tekrar bas." % [
				stack.definition.name, int(float(info.illness) * 100)], Hud.ACCENT)
			return
	var result := ItemUsage.use(stack, game.vitals, game.inventory, game.skills, rng)
	game.hud.message(result.message, Hud.GREEN if result.ok else Hud.RED)
	if result.ok:
		game.sfx.play_ui("pickup")


# ---------------------------------------------------------------------------
# Su kaynagindan doldurma
# ---------------------------------------------------------------------------
func fill_from_source(source_label: String) -> String:
	## Bos siseleri (en fazla 6) kirli suyla doldurur. Atomik: sigmazsa
	## hicbiri dolmaz.
	var empties: int = game.inventory.count("bottle_empty")
	if empties <= 0:
		return "Doldurmak icin bos sise yok (bos siseler dolaplarda ve icilen sulardan cikar)"
	var n := mini(empties, 6)
	var trial: Inventory = game.inventory.clone()
	trial.remove("bottle_empty", n)
	if trial.add(ItemStack.new(Content.item("water_dirty"), n, 0.0)) > 0:
		return "Cantada yer yok"
	game.inventory.replace_with(trial)
	return "%s: %d sise KIRLI su dolduruldu -- kaynat, tabletle ya da filtrele" % [source_label, n]
