class_name WeaponState
extends RefCounted
## Kusanilmis silahin CALISMA ZAMANI durumu (Python: WeaponSlot).
##
## Eski oyundan iki bilincli fark (tasima tablosunda "yalnizca hedef"
## olarak isaretli davranislarin tamamlanmasi):
##   * Silah GERCEK bir envanter esyasidir; sarjor esyanin icinde (`loaded`)
##     durur. Yedek cephane cantadaki mermi esyalaridir; doldurma onlari
##     GERCEKTEN harcar. Eski oyun 1-4 tuslariyla bedava silah ve sarjorun
##     6 kati bedava mermi veriyordu.
##   * Takili modlar istatistiklere CARPAN olarak uygulanir (ItemStack.
##     stat_multiplier) ve dayaniklilik her atista azalir.

var stack: ItemStack               # silah esyasi (kalite, dayaniklilik, modlar, sarjor)
var weapon: WeaponDef
var inventory: Inventory           # yedek cephanenin geldigi canta
var cooldown := 0.0
var reload_timer := 0.0
var reload_total := 0.0
var spread_bloom := 0.0
var trigger_held := false
var _durability_carry := 0.0


func _init(p_stack: ItemStack, p_weapon: WeaponDef, p_inventory: Inventory) -> void:
	stack = p_stack
	weapon = p_weapon
	inventory = p_inventory


# --- mod ve kalite etkili istatistikler ---
func quality_factor() -> float:
	## Kalite silahin hasarini ve isabetini hafifce etkiler (0.9x .. 1.1x).
	return 0.9 + 0.2 * clampf(stack.quality / 100.0, 0.0, 1.0)


func ammo_def() -> ItemDef:
	## Sarjordeki (ya da tercih edilen) mermi cesidi.
	if weapon.ammo_type == "":
		return null
	if stack.ammo_id != "":
		var chosen := Content.item(stack.ammo_id)
		if chosen != null and chosen.ammo_type == weapon.ammo_type:
			return chosen
	return Content.ammo_item_for(weapon.ammo_type)


func ammo_stat(key: String, default: float = 1.0) -> float:
	var def := ammo_def()
	return float(def.effects.get(key, default)) if def != null else default


func damage(skills: SkillProfile) -> float:
	return weapon.damage * stack.stat_multiplier("damage") * quality_factor() * skills.multiplier("weapon_damage") \
		* ammo_stat("damage")


func pierce() -> int:
	return weapon.pierce + int(stack.stat_multiplier("pierce_add") - 1.0 + 0.001) + int(ammo_stat("pierce", 0.0))


func damage_type() -> String:
	if ammo_stat("incendiary", 0.0) > 0.0:
		return "fire"
	if ammo_stat("shock", 0.0) > 0.0 or stack.stat_multiplier("shock") > 1.0:
		return "shock"
	return weapon.damage_type


func magazine_size() -> int:
	if weapon.is_melee():
		return 1
	return maxi(1, int(round(weapon.magazine * stack.stat_multiplier("magazine"))))


func reload_time(skills: SkillProfile) -> float:
	return weapon.reload_time * stack.stat_multiplier("reload_time") * skills.multiplier("weapon_reload")


func base_spread(skills: SkillProfile) -> float:
	return weapon.spread * stack.stat_multiplier("spread") * skills.multiplier("weapon_spread") \
		* (2.0 - quality_factor()) * ammo_stat("spread")


func total_spread(skills: SkillProfile, aiming: bool, moving: float, crouching: bool) -> float:
	## Derece cinsinden yari aci. Nisan almak, comelmek ve durmak toplar;
	## kosmak dagitir. Ard arda atis `spread_bloom` ile acilir.
	var spread := base_spread(skills) + spread_bloom
	if aiming:
		spread *= 0.45
	if crouching:
		spread *= 0.8
	spread += moving * (1.2 if not aiming else 0.5)
	return spread


func recoil() -> float:
	return weapon.recoil * stack.stat_multiplier("recoil")


func range_m() -> float:
	return weapon.range_m() * stack.stat_multiplier("range")


func noise_m(skills: SkillProfile) -> float:
	return weapon.noise_radius_m() * stack.stat_multiplier("noise_radius") * skills.multiplier("noise_radius") \
		* ammo_stat("noise")


# --- durum ---
func loaded() -> int:
	return stack.loaded


func _ammo_candidates() -> Array:
	## Doldurmada kullanilacak yiginlar: tercih edilen cesit; sarjor bossa
	## ve tercih tukendiyse ayni capin baska cesidi (cesit karismaz).
	var all := inventory.stacks.filter(func(s: ItemStack) -> bool:
		return s.definition.category == "ammo" and s.definition.ammo_type == weapon.ammo_type)
	if stack.ammo_id == "":
		return all
	var chosen := all.filter(func(s: ItemStack) -> bool: return s.definition.id == stack.ammo_id)
	if chosen.is_empty() and stack.loaded == 0:
		return all
	return chosen


func reserve() -> int:
	if weapon.ammo_type == "":
		return 0
	var total := 0
	for s: ItemStack in _ammo_candidates():
		total += s.quantity
	return total


func reloading() -> bool:
	return reload_timer > 0.0


func broken() -> bool:
	return stack.broken()


func can_fire() -> bool:
	if broken() or reloading() or cooldown > 0.0:
		return false
	return weapon.is_melee() or stack.loaded > 0


func begin_reload(skills: SkillProfile) -> bool:
	if weapon.is_melee() or reloading() or stack.loaded >= magazine_size() or reserve() <= 0:
		return false
	reload_total = reload_time(skills)
	reload_timer = reload_total
	return true


func cancel_reload() -> void:
	reload_timer = 0.0


func finish_reload() -> int:
	## Cantadan GERCEK mermi alir. Doldurulan adedi dondurur.
	var needed := magazine_size() - stack.loaded
	var taken := 0
	if needed > 0:
		var candidates := _ammo_candidates()
		if not candidates.is_empty() and (stack.ammo_id == "" or stack.loaded == 0):
			stack.ammo_id = (candidates[0] as ItemStack).definition.id
			candidates = candidates.filter(func(s: ItemStack) -> bool: return s.definition.id == stack.ammo_id)
		for s: ItemStack in candidates:
			var take := mini(needed - taken, s.quantity)
			s.quantity -= take
			taken += take
			if taken >= needed:
				break
		inventory.compact()
	stack.loaded += taken
	reload_timer = 0.0
	return taken


func unload_to_inventory() -> int:
	## Sarjordeki mermiyi cantaya geri koyar (silah degistirirken DEGIL;
	## yalnizca oyuncu silahi sokerken/birakirken istenirse).
	if stack.loaded <= 0 or weapon.ammo_type == "":
		return 0
	var loaded_def := ammo_def()
	if loaded_def == null:
		return 0
	var amount := stack.loaded
	var left := inventory.add(ItemStack.new(loaded_def, amount))
	stack.loaded = left
	return amount - left


func consume_round(skills: SkillProfile) -> void:
	cooldown = weapon.shot_interval()
	if weapon.is_melee():
		_wear(skills)
		return
	stack.loaded = maxi(0, stack.loaded - 1)
	spread_bloom = minf(spread_bloom + recoil(), recoil() * 5.0)
	_wear(skills)


func _wear(skills: SkillProfile) -> void:
	if stack.definition.durability <= 0:
		return
	# Tamir becerisi asinmayi yavaslatir; kesirli kayip biriktirilir ki
	# carpan 0.9 da olsa gercekten etkili olsun.
	_durability_carry += skills.multiplier("durability_loss")
	var whole := int(_durability_carry)
	if whole > 0:
		_durability_carry -= whole
		stack.durability = maxi(0, stack.durability - whole)


func tick(delta: float) -> bool:
	## Zamanlayicilari ilerletir. Doldurma bittiyse true.
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)
	spread_bloom = maxf(0.0, spread_bloom - recoil() * 3.0 * delta)
	if reloading():
		reload_timer -= delta
		if reload_timer <= 0.0:
			finish_reload()
			return true
	return false


static func spread_offsets(count: int, spread: float, rng: RandomNumberGenerator) -> Array:
	## Sacma/dagilma acilari: [yatay, dikey] derece ciftleri. Tek mermide
	## daire icinde rastgele; coklu mermide esit dagitilmis halka + sapma
	## (eski 2D yelpazenin 3D karsiligi -- "delik delik" his olmaz).
	var result: Array = []
	if count <= 1:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * spread
		result.append(Vector2(cos(angle), sin(angle)) * radius)
		return result
	for i in count:
		var ring := 0.35 if i == 0 else 1.0
		var angle := TAU * float(i) / count + rng.randf_range(-0.3, 0.3)
		var radius := spread * ring * rng.randf_range(0.55, 1.0)
		result.append(Vector2(cos(angle), sin(angle)) * radius)
	return result
