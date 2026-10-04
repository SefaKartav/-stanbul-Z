class_name Gathering
extends RefCounted
## Kaynak toplama: balta, kazma, anahtar, kurek, testere...
##
## KURAL DEGISIKLIGI (29 Eylul 2026, yeni uretim dongusu): eskiden yakin
## dovus hicbir blogu kirmazdi ("kazma yok"). Artik YALNIZCA `harvest_*`
## etkisi olan aletler, yalnizca o SINIFTAKI malzemeyi kazar:
##   harvest_wood  -> kutuk, tahta, eski ahsap, mobilya, yaprak
##   harvest_stone -> tas, beton, tugla, siva, kaldirim, kiremit
##   harvest_metal -> sac, celik, korkuluk, metal mobilya (anahtar/levye)
##   harvest_soil  -> toprak, cim, kum
##   harvest_glass -> cam (dikkatli sok: kirik yerine butun parca)
## Silahlar (bicak, boru, balyoz) blok KIRMAZ; bu kural aynen korunur.
##
## BEDEL: her vurus nefes harcar (yetmezse vurulmaz), aletin dayanikliligi
## asinir (WeaponState._wear) ve GURULTU cikar (zombiler duyar).
## SOMURU YOK: yalnizca haritanin KENDI blogu (ORIGIN_WORLD) urun verir ve
## kirilan hucre dunya farki olarak kaydedilir -- yeniden yuklemede geri
## dogmaz. Oyuncunun koydugu blok kazilirsa urun vermez (B kipinde "Sok"
## sinirli geri kazanim verir).

const STAMINA_PER_SWING := 7.0

var world: VoxelWorld
var rng := RandomNumberGenerator.new()


func _init(p_world: VoxelWorld) -> void:
	world = p_world
	rng.randomize()


static func material_class(material_id: String) -> String:
	return str(Content.harvest.get("materials", {}).get(material_id, {}).get("class", ""))


static func tool_power(stack: ItemStack, cls: String) -> float:
	if stack == null or cls == "":
		return 0.0
	return float(stack.definition.effects.get("harvest_" + cls, 0.0))


func swing(stack: ItemStack, eye: Vector3, forward: Vector3, reach: float, damage: float) -> Dictionary:
	## Aletle blok vurusu. {hit, cell, value, destroyed, drops: [ItemStack], reason}
	var result := {"hit": false, "destroyed": false, "drops": [], "reason": ""}
	var hit := VoxelRay.cast(world, eye, forward, reach)
	if hit.is_empty() or hit.boundary:
		return result
	var value: int = hit.value
	var material_id := world.materials.ids[value]
	var cls := material_class(material_id)
	var power := tool_power(stack, cls)
	result.cell = hit.cell
	result.value = value
	result.position = hit.position
	result.normal = hit.normal
	if power <= 0.0:
		result.reason = "Bu aletle %s sökülmez" % str(Content.blocks.get_def(value).get("name", material_id)).to_lower() \
			if cls != "" else ""
		return result
	result.hit = true
	var applied := world.apply_damage(hit.cell, damage * power)
	result.destroyed = applied.destroyed
	if applied.destroyed and applied.origin == VoxelWorld.ORIGIN_WORLD:
		result.drops = drops_for(material_id, float(stack.definition.effects.get("harvest_yield", 1.0)), stack.quality)
	return result


func drops_for(material_id: String, yield_mult: float, quality: float) -> Array:
	var table: Dictionary = Content.harvest.get("materials", {}).get(material_id, {})
	var drops: Array = []
	for drop: Variant in table.get("drops", []):
		if typeof(drop) != TYPE_DICTIONARY:
			continue
		if rng.randf() > float(drop.get("chance", 1.0)):
			continue
		var count: Array = drop.get("count", [1, 1])
		var n := int(round(rng.randi_range(int(count[0]), int(count[1])) * yield_mult))
		var def := Content.item(str(drop.item))
		if n > 0 and def != null:
			drops.append(ItemStack.new(def, n, clampf(quality - 10.0, 10.0, 80.0)))
	return drops


func salvage_vehicle(entry: Dictionary, stack: ItemStack) -> Array:
	## Park etmis araci anahtarla sokme (bir kez). Arac hurdaya doner.
	var power := tool_power(stack, "vehicle")
	if power <= 0.0 or bool(entry.get("salvaged", false)):
		return []
	entry["salvaged"] = true
	var drops: Array = []
	for drop: Variant in Content.harvest.get("vehicle_salvage", []):
		if typeof(drop) != TYPE_DICTIONARY or rng.randf() > float(drop.get("chance", 1.0)) * minf(1.3, power):
			continue
		var count: Array = drop.get("count", [1, 1])
		var def := Content.item(str(drop.item))
		if def != null:
			drops.append(ItemStack.new(def, rng.randi_range(int(count[0]), int(count[1])), 35.0))
	return drops
