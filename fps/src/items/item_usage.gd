class_name ItemUsage
extends RefCounted
## Esyayi KULLANMA: `effects` sozlugunu oynanisa baglar (Python:
## game/items/usage.py). ETKI SOZLUGU SOZLESMEDIR: yeni tuketilebilir
## eklemek veri isidir. Bilinmeyen anahtar sessizce yutulmaz, raporlanir.
## KURAL: hicbir etkisi ise yaramayacaksa esya HARCANMAZ ve nedeni soylenir.

const CURES := {"cure_bleed": "bleed", "cure_infection": "infection", "cure_burn": "burn", "cure_sick": "sick",
	"cure_fracture": "fracture"}
const CURE_LABELS := {"bleed": "kanamayi durdurur", "infection": "enfeksiyonu temizler", "sick": "mide bulantisini gecirir",
	"burn": "yanigi sondurur", "fracture": "kirigi sarar"}
const NON_CONSUMABLE := ["damage", "radius", "burn_duration", "noise_radius", "delay",
	"light_radius", "armor", "toxin_resist", "capacity", "health", "path_cost", "uses",
	"fire_rate", "range", "station_tier", "supply", "smoke_radius", "shock", "stamina_bonus", "noise_bonus",
	"stamina_cost", "harvest_wood", "harvest_stone", "harvest_metal", "harvest_soil", "harvest_glass",
	"harvest_vehicle", "harvest_yield", "repair_weapon", "repair_armor", "repair_vehicle", "repair_tool",
	"repair_block", "light_range", "radio_range", "zoom", "map_reveal", "compass", "pierce", "spread",
	"noise", "incendiary", "vehicle_speed", "vehicle_tank", "vehicle_capacity", "vehicle_armor", "vehicle_noise",
	"vehicle_ram", "vehicle_light", "fishing"]


static func describe(stack: ItemStack) -> String:
	var effects := stack.definition.effects
	var parts := PackedStringArray()
	var food := Content.nutrition_of(stack.definition.id)
	if bool(food.get("raw", false)):
		parts.append("cig yenmez: ocakta pisir (C)")
	if float(food.get("food", 0.0)) != 0.0:
		parts.append("%+d tokluk" % int(food.food))
	if float(food.get("water", 0.0)) != 0.0:
		parts.append("%+d su" % int(food.water))
	if food.has("returns"):
		parts.append("kabi geri kalir")
	if float(food.get("illness", 0.0)) > 0.0:
		parts.append("%%%d mide bulantisi riski" % int(float(food.illness) * 100))
	if food.has("shelf_life_h"):
		parts.append("%d oyun saatinde bozulur" % int(food.shelf_life_h))
	if effects.has("heal"):
		parts.append("+%d can" % int(effects.heal))
	if effects.has("stamina"):
		parts.append("+%d enerji" % int(effects.stamina))
	if effects.has("speed_boost"):
		parts.append("%%%d hız (%d sn)" % [int(effects.speed_boost * 100), int(effects.get("duration", 0))])
	if effects.has("regen"):
		parts.append("saniyede %.1f can, %d sn" % [effects.regen, int(effects.get("duration", 30))])
	if effects.has("fortify"):
		parts.append("%%%d hasar direnci, %d sn" % [int(effects.fortify * 100), int(effects.get("duration", 60))])
	if effects.has("focus"):
		parts.append("%%%d az dağılma, %d sn" % [int(effects.focus * 100), int(effects.get("duration", 60))])
	if effects.has("toxin_resist"):
		parts.append("%%%d asit/zehir direnci (kuşanılır)" % int(effects.toxin_resist * 100))
	if effects.has("light_range"):
		parts.append("%d m ışık (kuşanılır)" % int(effects.light_range))
	for key: String in ItemUse.REPAIR_KEYS:
		if effects.has(key):
			parts.append("%d dayanıklılık onarır (%s)" % [int(effects[key]), {"repair_weapon": "silah",
				"repair_armor": "zırh", "repair_vehicle": "araç", "repair_tool": "alet", "repair_block": "blok"}[key]])
	for key: String in ["harvest_wood", "harvest_stone", "harvest_metal", "harvest_soil", "harvest_glass", "harvest_vehicle"]:
		if effects.has(key):
			parts.append("%s ×%.1f" % [{"harvest_wood": "ahşap", "harvest_stone": "taş", "harvest_metal": "metal",
				"harvest_soil": "toprak", "harvest_glass": "cam", "harvest_vehicle": "araç sökümü"}[key], effects[key]])
	if stack.definition.category == "vehicle_part":
		parts.append("araç parçası: %s" % stack.definition.slot)
	for key: String in CURES:
		if effects.has(key):
			parts.append(CURE_LABELS[CURES[key]])
	if effects.has("armor"):
		parts.append("%d zirh (kusanilir)" % int(effects.armor))
	if effects.has("capacity"):
		parts.append("+%d kg tasima (kusanilir)" % int(effects.capacity))
	if effects.has("damage") and stack.definition.category == "consumable":
		parts.append("%d hasar (firlatilir)" % int(effects.damage))
	if effects.has("station_tier"):
		parts.append("T%d tezgah (yerlestirilir)" % int(effects.station_tier))
	if stack.definition.id == "barricade_kit":
		parts.append("barikat (insa kipinde yerlestirilir)")
	if stack.definition.category == "weapon":
		var weapon: WeaponDef = Content.weapons.get(stack.definition.weapon_id)
		if weapon != null:
			parts.append("%d hasar, %d'lik sarjor" % [int(weapon.damage), weapon.magazine] if not weapon.is_melee()
				else "%d hasar, yakin dovus" % int(weapon.damage))
	return " · ".join(parts)


static func can_use(stack: ItemStack, vitals: PlayerVitals) -> Array:
	## [kullanilabilir_mi, neden]
	var effects := stack.definition.effects
	var food := Content.nutrition_of(stack.definition.id)
	if bool(food.get("raw", false)):
		return [false, "Cig yenmez: ocakta suyla pisir (Roket Ocagi)"]
	var gives_food := float(food.get("food", 0.0)) > 0.0
	var gives_water := float(food.get("water", 0.0)) > 0.0
	if gives_food or gives_water:
		if (gives_food and vitals.satiety < 97.0) or (gives_water and vitals.hydration < 97.0):
			return [true, ""]
		if effects.is_empty():
			return [false, "Tok ve susuz degilsin"]
	if effects.is_empty():
		return [false, "Bu esya kullanilmaz"]
	var usable := false
	for key: String in effects:
		if not key in NON_CONSUMABLE and key != "duration":
			usable = true
	if not usable:
		return [false, "Bu esya kullanilmaz; yerlestirilir ya da kusanilir"]
	if float(effects.get("heal", 0.0)) > 0.0 and vitals.health < PlayerVitals.MAX_HEALTH:
		return [true, ""]
	if float(effects.get("stamina", 0.0)) > 0.0 and vitals.energy < vitals.energy_max:
		return [true, ""]
	if float(effects.get("speed_boost", 0.0)) > 0.0:
		return [true, ""]
	for key: String in ["regen", "fortify", "focus", "xp"]:
		if float(effects.get(key, 0.0)) > 0.0:
			return [true, ""]
	for key: String in CURES:
		if effects.has(key) and vitals.statuses.has(CURES[key]):
			return [true, ""]
	if float(effects.get("heal", 0.0)) > 0.0:
		for key: String in CURES:
			if effects.has(key):
				return [false, "Canin dolu ve iyilestirecek bir durum yok"]
		return [false, "Canin zaten dolu"]
	for key: String in CURES:
		if effects.has(key):
			return [false, "Iyilestirecek bir durum yok"]
	return [false, "Su an bir ise yaramaz"]


static func use(stack: ItemStack, vitals: PlayerVitals, inventory: Inventory, skills: SkillProfile,
		rng: RandomNumberGenerator = null) -> Dictionary:
	## {ok, message, unknown}. Tuketim yalnizca etki UYGULANDIYSA yapilir.
	var check := can_use(stack, vitals)
	if not check[0]:
		return {"ok": false, "message": check[1], "unknown": []}
	var effects := stack.definition.effects
	var applied := PackedStringArray()
	var unknown: Array = []
	var food := Content.nutrition_of(stack.definition.id)
	var returns := str(food.get("returns", ""))
	if returns != "":
		# ATOMIK: once kopyada "1 tuket + kabi ekle" dene; kap sigmiyorsa
		# hicbir sey tuketilmez (kap sessizce kaybolmaz).
		var trial := inventory.clone()
		var index := inventory.stacks.find(stack)
		var twin: ItemStack = trial.stacks[index] if index >= 0 else null
		if twin == null or trial.take_from_stack(twin, 1) == null \
				or trial.add(ItemStack.new(Content.item(returns), 1, 0.0)) > 0:
			return {"ok": false, "message": "Bos kap icin yer yok -- once yer ac", "unknown": []}
	if float(food.get("food", 0.0)) != 0.0 or float(food.get("water", 0.0)) != 0.0:
		var f := float(food.get("food", 0.0)) * skills.multiplier("food_value")
		var w := float(food.get("water", 0.0))
		vitals.feed(f, w)
		if f != 0.0:
			applied.append("%+d tokluk" % int(f))
		if w != 0.0:
			applied.append("%+d su" % int(w))
		var risk := float(food.get("illness", 0.0)) * skills.multiplier("illness_risk")
		var roll := rng.randf() if rng != null else randf()
		if risk > 0.0 and roll < risk:
			vitals.statuses.apply(StatusEffects.SICK, float(Content.nutrition.get("effects", {}).get("sick_seconds", 150.0)), 1.0)
			applied.append("MIDEN BULANDI")
	for key: String in effects:
		if key in NON_CONSUMABLE or key == "duration":
			continue
		var value := float(effects[key])
		match key:
			"heal":
				# Tip becerisi iyilestirmeyi buyutur.
				var amount := value * skills.multiplier("healing")
				vitals.heal(amount)
				applied.append("+%d can" % int(amount))
			"stamina":
				vitals.energy = minf(vitals.energy_max, vitals.energy + value)
				applied.append("+%d enerji" % int(value))
			"speed_boost":
				vitals.statuses.apply(StatusEffects.ADRENALINE, float(effects.get("duration", 10.0)), value)
				applied.append("hız artışı")
			"regen":
				vitals.statuses.apply(StatusEffects.REGEN, float(effects.get("duration", 30.0)), value)
				applied.append("%d sn iyileşme" % int(effects.get("duration", 30.0)))
			"fortify":
				vitals.statuses.apply(StatusEffects.FORTIFIED, float(effects.get("duration", 60.0)), value)
				applied.append("%%%d hasar direnci" % int(value * 100))
			"xp":
				applied.append("+%d deneyim" % int(value))
			"focus":
				vitals.statuses.apply(StatusEffects.FOCUS, float(effects.get("duration", 60.0)), value)
				applied.append("odak (%%%d az dağılma)" % int(value * 100))
			_:
				if CURES.has(key):
					if vitals.statuses.has(CURES[key]):
						vitals.statuses.remove(CURES[key])
						applied.append(CURE_LABELS[CURES[key]])
				else:
					unknown.append(key)
	if applied.is_empty():
		return {"ok": false, "message": "Etkisi olmadi", "unknown": unknown}
	inventory.take_from_stack(stack, 1)
	if returns != "":
		inventory.add(ItemStack.new(Content.item(returns), 1, 0.0))
	return {"ok": true, "message": "%s: %s" % [stack.definition.name, ", ".join(applied)], "unknown": unknown,
		"xp": float(effects.get("xp", 0.0))}
