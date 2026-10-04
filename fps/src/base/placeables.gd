class_name Placeables
extends Node3D
## Dunyaya konan uretilmis yapilar (Python: game/base/placeable.py).
##
## TURLER (build_catalog.json "placeables" -> "kind"). Her turun calisma
## zamani isleyicisi bu dosyada ya da adi gecen sistemdedir:
##   station        uretim istasyonu (tier; tarif `power` isterse ELEKTRIK)
##   turret         taret: once kendi sarjoru, sonra ussun deposu; `power` varsa elektrik
##   trap           tuzak: ezilme/kesme/yanma/elektrik/patlama/yavaslatma; kullanim hakki
##   light          lamba: guc varsa yanar (sensor/gece sensoru ile kosullu)
##   generator      jenerator: yakit (chemical_fuel) yakar, guc uretir, GURULTU yapar
##   battery        aku: fazla gucu depolar, eksikte verir (Wh)
##   solar          gunes paneli: gunduz uretir
##   relay          direk/role: kablo menzilini uzatir
##   switch         anahtar: kapaliyken agi boler (E)
##   sensor         hareket/gece sensoru: agdaki lamba ve tuzaklari kosullu calistirir
##   alarm          alarm: menzilde zombi -> uyari (+ istege bagli siren gurultusu)
##   decoy          yem: aralikli gurultuyle zombileri ceker (guc ya da yakit)
##   storage        sandik/dolap: kendi envanteri (kapasite kg/yuva), E ile acilir
##   bed            yatak: E ile uyu (zaman atlar, iyilestirir); ussun yatakhane kapasitesi
##   colony         koloni is yeri: ussun rol kapasitesini artirir (revir, mutfak, atolye)
##   planter        saksi/tarla: tohum ek, sula, hasat (Farming)
##   rain_collector yagmur varili: her gun ussun deposuna kirli su
##   cold_room      soguk oda: ussun deposunda bozulmayi yavaslatir (yakitla)
##   purifier       elektrikli arıtıcı: her gun ussun kirli suyunu temizler
##
## CARPISMA: katı turler GORUNMEZ katı voxel hucresi birakir (placed_light /
## placed_heavy). Oyuncu, zombi, mermi ve yol bulma o hucreyi gorur; zombi
## yolunu kapatan yapiya saldirir. Hucre kirilinca yapi YOK OLUR (esya geri
## gelmez; enkazdan bir parca malzeme dusebilir).
##
## Istatistikler esyanin `effects` alanindan KALITEYLE olceklenir
## (0.7x .. 1.3x). Geri toplama (sokup alma) esyayi AYNI kalitede verir:
## koy-topla dongusuyle hicbir sey cogalmaz.

signal changed
signal destroyed(entry: Dictionary)

const STATION_RANGE := 4.0
const KINDS := ["station", "turret", "trap", "light", "generator", "battery", "solar", "turbine", "relay", "switch",
	"sensor", "alarm", "decoy", "storage", "bed", "colony", "planter", "rain_collector", "cold_room", "purifier"]
const SOLID_KINDS := ["station", "turret", "generator", "battery", "relay", "storage", "bed", "colony",
	"cold_room", "purifier", "rain_collector", "alarm", "decoy", "solar", "turbine"]
const POWER_KINDS := ["generator", "battery", "solar", "turbine", "relay", "switch", "sensor"]
const KIND_NAMES := {"station": "İstasyon", "turret": "Taret", "trap": "Tuzak", "light": "Lamba",
	"generator": "Jeneratör", "battery": "Akü", "solar": "Güneş paneli", "turbine": "Rüzgâr türbini", "relay": "Kablo direği",
	"switch": "Anahtar", "sensor": "Sensör", "alarm": "Alarm", "decoy": "Yem", "storage": "Depo",
	"bed": "Yatak", "colony": "Koloni iş yeri", "planter": "Ekim alanı", "rain_collector": "Yağmur toplayıcı",
	"cold_room": "Soğuk oda", "purifier": "Arıtıcı"}

var entries: Array = []      # [{id, item_id, quality, kind, info, cell, rot, stats, node, ...}]
var _next_id := 1
var catalog: Dictionary = {}
var world: VoxelWorld
var _by_cell: Dictionary = {}   # Vector3i -> entry (katı hucreler)
var _placing := false
var _light_nodes: Dictionary = {}   # entry id -> OmniLight3D


func _ready() -> void:
	catalog = Content.placeables


func setup(p_world: VoxelWorld) -> void:
	world = p_world
	world.block_changed.connect(_on_block_changed)


static func stats_from_item(item: ItemDef, quality: float) -> Dictionary:
	var scale := 0.7 + 0.6 * (quality / 100.0)
	var result := {}
	for key: String in item.effects:
		result[key] = float(item.effects[key]) * scale
	return result


func is_placeable(item_id: String) -> bool:
	return catalog.has(item_id)


func info_of(entry: Dictionary) -> Dictionary:
	return catalog.get(entry.item_id, {})


func label_of(entry: Dictionary) -> String:
	var def := Content.item(entry.item_id)
	return def.name if def != null else str(entry.item_id)


func footprint(item_id: String, origin: Vector3i, rotation_steps: int) -> Array:
	var info: Dictionary = catalog.get(item_id, {})
	var size: Array = info.get("size", [1, 1, 1])
	var cells: Array = []
	for y in int(size[1]):
		for i in int(size[0]):
			for k in int(size[2]):
				var offset := Vector3i(i, y, k)
				if rotation_steps % 2 == 1:
					offset = Vector3i(k, y, i)
				cells.append(origin + offset)
	return cells


func occupied(cell: Vector3i) -> bool:
	if _by_cell.has(cell):
		return true
	for entry: Dictionary in entries:
		if entry.cell == cell:
			return true
	return false


func is_solid_kind(kind: String, info: Dictionary) -> bool:
	return bool(info.get("solid", kind in SOLID_KINDS))


func place(stack: ItemStack, cell: Vector3i, rotation_steps: int) -> Dictionary:
	var info: Dictionary = catalog.get(stack.definition.id, {})
	var stats := stats_from_item(stack.definition, stack.quality)
	var kind := str(info.get("kind", "station"))
	var entry := {
		"id": _next_id, "item_id": stack.definition.id, "quality": stack.quality,
		"kind": kind, "station": info.get("station", ""),
		"tier": maxi(1, int(round(stats.get("station_tier", float(info.get("tier", 1)))))), "cell": cell,
		"rot": rotation_steps, "stats": stats, "node": null,
		"health": stats.get("health", float(info.get("health", 180.0))), "cooldown": 0.0,
		"uses": int(stats.get("uses", float(info.get("uses", 0)))),
		"on": true, "fuel": 0.0, "charge": 0.0, "powered": false, "active": false, "ammo": 0,
		"cells": [], "state": {},
	}
	if kind == "storage":
		entry["inv"] = Inventory.new(float(info.get("capacity_kg", 60.0)), int(info.get("slots", 24)))
	if kind == "planter":
		entry.state = {"seed": "", "growth": 0.0, "water": 0.0, "fertilized": false, "quality": 50.0}
	_next_id += 1
	entries.append(entry)
	if is_solid_kind(kind, info):
		_claim_cells(entry, footprint(stack.definition.id, cell, rotation_steps), str(info.get("material", "placed_light")))
	_build_node(entry)
	changed.emit()
	return entry


func _claim_cells(entry: Dictionary, cells: Array, material_id: String) -> void:
	## Gorunmez katı hucre: carpisma, mermi, gorus ve yol bulma icin.
	if world == null:
		return
	var material := world.materials.index_of(material_id)
	if material == 0:
		return
	_placing = true
	for c: Vector3i in cells:
		# Kayit yuklenirken chunk henuz yuklu olmayabilir: hucre farklarda
		# zaten bu malzemeyse yalnizca sahiplik kaydedilir.
		if int(world.modified.get(c, -1)) == material:
			entry.cells.append(c)
			_by_cell[c] = entry
		elif world.get_cell(c) == 0:
			world.set_block(c, material, VoxelWorld.ORIGIN_PLACED)
			entry.cells.append(c)
			_by_cell[c] = entry
	_placing = false


func _release_cells(entry: Dictionary) -> void:
	if world == null:
		return
	_placing = true
	for c: Vector3i in entry.get("cells", []):
		_by_cell.erase(c)
		if world.placed.has(c):
			world.set_block(c, 0, VoxelWorld.ORIGIN_WORLD)
	_placing = false
	entry.cells = []


func _on_block_changed(cell: Vector3i, _previous: int, current: int) -> void:
	## Yapinin hucresi kirildi (zombi, patlama, mermi): yapi YOK OLUR.
	if _placing or current != 0 or not _by_cell.has(cell):
		return
	var entry: Dictionary = _by_cell[cell]
	_by_cell.erase(cell)
	entry.cells.erase(cell)
	_destroy(entry)


func _destroy(entry: Dictionary) -> void:
	if not entries.has(entry):
		return
	_release_cells(entry)
	_free_node(entry)
	entries.erase(entry)
	destroyed.emit(entry)
	changed.emit()


func entry_at_cell(cell: Vector3i) -> Dictionary:
	return _by_cell.get(cell, {})


func _build_node(entry: Dictionary) -> void:
	var info: Dictionary = catalog.get(entry.item_id, {})
	var node := AssetLibrary.instantiate(info.get("model", "storage_crate"))
	node.position = Vector3(entry.cell) + Vector3(0.5, 0.0, 0.5)
	node.rotation.y = entry.rot * PI * 0.5
	add_child(node)
	entry.node = node
	if entry.kind == "light":
		var light := OmniLight3D.new()
		var l: Dictionary = info.get("light", {})
		var c: Array = l.get("color", [255, 236, 200])
		light.light_color = Color8(int(c[0]), int(c[1]), int(c[2]))
		light.light_energy = float(l.get("energy", 1.6))
		light.omni_range = float(l.get("range", 10.0)) * (0.8 + 0.4 * entry.quality / 100.0)
		light.shadow_enabled = bool(l.get("shadow", false))
		light.position = Vector3(0, float(l.get("height", 1.6)), 0)
		light.visible = false
		node.add_child(light)
		_light_nodes[entry.id] = light


func _free_node(entry: Dictionary) -> void:
	if entry.node != null and is_instance_valid(entry.node):
		entry.node.queue_free()
	entry.node = null
	_light_nodes.erase(entry.id)


func remove_entry(entry: Dictionary) -> ItemStack:
	## Soker ve esyayi AYNI kalitede geri verir. Depo icerigi, jenerator
	## yakiti ve taret sarjoru cagiran tarafindan bosaltilir (bkz. take_contents).
	var definition := Content.item(entry.item_id)
	_release_cells(entry)
	_free_node(entry)
	entries.erase(entry)
	changed.emit()
	if definition == null:
		return null
	return ItemStack.new(definition, 1, entry.quality)


func take_contents(entry: Dictionary) -> Array:
	## Sokulen yapinin icindekiler (esya kaybolmaz): depo envanteri, taret
	## sarjoru, ekili urun (olgun degilse tohum da gider -- yarim buyumus
	## bitki sokulunce kurur), jenerator yakiti birim olarak geri verilmez.
	var out: Array = []
	if entry.has("inv"):
		for stack: ItemStack in (entry.inv as Inventory).stacks:
			out.append(stack.copy())
		(entry.inv as Inventory).clear()
	if int(entry.get("ammo", 0)) > 0:
		var ammo_def := Content.item(str(info_of(entry).get("ammo", "")))
		if ammo_def != null:
			out.append(ItemStack.new(ammo_def, int(entry.ammo), 50.0))
		entry.ammo = 0
	return out


func nearest(position: Vector3, radius: float, kind: String = "") -> Dictionary:
	var best := {}
	var best_d := radius
	for entry: Dictionary in entries:
		if kind != "" and entry.kind != kind:
			continue
		var d := (Vector3(entry.cell) + Vector3(0.5, 0.5, 0.5)).distance_to(position)
		if d < best_d:
			best = entry
			best_d = d
	return best


func best_station(position: Vector3) -> Dictionary:
	## Menzildeki EN IYI istasyon; oyuncu hangisinin onunde durdugunu
	## hesaplamak zorunda kalmasin. Yoksa "hands" (el ile).
	## available: istasyon -> kademe ; powered: istasyon -> elektrik var mi
	var best := {"station": "hands", "tier": 1}
	var stations: Dictionary = {}
	var powered: Dictionary = {}
	var nodes: Dictionary = {}
	for entry: Dictionary in entries:
		if entry.kind != "station":
			continue
		if (Vector3(entry.cell) + Vector3(0.5, 0.5, 0.5)).distance_to(position) > STATION_RANGE:
			continue
		var station := str(entry.station)
		if int(entry.tier) >= int(stations.get(station, 0)):
			stations[station] = maxi(int(stations.get(station, 0)), int(entry.tier))
			nodes[station] = entry
		powered[station] = bool(powered.get(station, false)) or bool(entry.powered)
	best["available"] = stations
	best["powered"] = powered
	best["entries"] = nodes
	return best


func station_entry(position: Vector3, station: String) -> Dictionary:
	return best_station(position).get("entries", {}).get(station, {})


# ---------------------------------------------------------------------------
# Davranis
# ---------------------------------------------------------------------------
func tick(delta: float, game: Node) -> void:
	for entry: Dictionary in entries.duplicate():
		if not entries.has(entry):
			continue
		var center := Vector3(entry.cell) + Vector3(0.5, 0.0, 0.5)
		match entry.kind:
			"turret":
				_tick_turret(entry, center, delta, game)
			"trap":
				_tick_trap(entry, center, delta, game)
			"alarm":
				_tick_alarm(entry, center, delta, game)
			"decoy":
				_tick_decoy(entry, center, delta, game)
			"light":
				var light: OmniLight3D = _light_nodes.get(entry.id)
				if light != null and is_instance_valid(light):
					var night_only := bool(info_of(entry).get("night_only", false))
					light.visible = bool(entry.powered) and bool(entry.on) and (not night_only or game.time.darkness() > 0.45)


func _tick_turret(entry: Dictionary, center: Vector3, delta: float, game: Node) -> void:
	## Taret GERCEK fisek harcar: once kendi sarjorundan (E ile doldurulur),
	## sonra bulundugu ussun deposundan. Elektrikli taret gucsuzken SUSAR.
	entry.cooldown = maxf(0.0, float(entry.cooldown) - delta)
	if entry.cooldown > 0.0:
		return
	var info := info_of(entry)
	if float(info.get("power", 0.0)) > 0.0 and not bool(entry.powered):
		return
	var boost: bool = game.skills.has_behavior("turret_boost")
	var reach := Units.weapon_range_m(float(entry.stats.get("range", 300.0))) * (1.2 if boost else 1.0)
	var eye := center + Vector3(0, 1.2, 0)
	var target: Node3D = null
	var best := reach
	for actor: Node3D in game.actors.near(center, reach):
		if actor.faction() != "zombie" or not actor.is_alive():
			continue
		var d := actor.global_position.distance_to(center)
		if d < best and VoxelRay.line_clear(game.world, eye, actor.global_position + Vector3(0, 1.2, 0)):
			target = actor
			best = d
	if target == null:
		return
	entry.cooldown = 1.0 / maxf(0.4, float(entry.stats.get("fire_rate", 3.0))) * (0.7 if boost else 1.0)
	var ammo_id := str(info.get("ammo", Content.colony.settings.guard_ammo))
	var energy := ammo_id == "energy"
	if not energy:
		if int(entry.ammo) > 0:
			entry.ammo = int(entry.ammo) - 1
		else:
			var base: Settlement = game.bases.settlement_at(center)
			if base == null or base.stockpile.count(ammo_id) <= 0:
				if not entry.get("warned", false):
					entry["warned"] = true
					game.hud.message("%s susuyor: şarjörü boş (E ile %s doldur)" % [label_of(entry),
						Content.item(ammo_id).name if Content.item(ammo_id) != null else ammo_id], Hud.RED)
				return
			base.stockpile.remove(ammo_id, 1)
	entry["warned"] = false
	var dir := (target.global_position + Vector3(0, 1.2, 0) - eye).normalized()
	var damage_type := str(info.get("damage_type", "physical"))
	var result: Dictionary = game.hitscan.fire(eye, dir, eye + dir * 0.6, reach,
		float(entry.stats.get("damage", 15.0)), damage_type, int(info.get("pierce", 0)), "survivor", null, false)
	game.effects.tracer(eye + dir * 0.6, result.end)
	game.effects.muzzle_flash(eye + dir * 0.6, 0.7)
	game.sfx.play_at(str(info.get("sound", "shot_smg")), eye, -2.0)
	game.on_noise_at(eye, Units.perception_m(float(info.get("noise", 300.0))))
	if entry.node != null and is_instance_valid(entry.node):
		entry.node.rotation.y = atan2(-dir.x, -dir.z)


func _tick_trap(entry: Dictionary, center: Vector3, delta: float, game: Node) -> void:
	## Tuzak etkisi (catalog "effect"): damage (ezilme/kesme), burn (yanma,
	## yakit hakki), shock (elektrik, GUC ister), slow (dikenli tel),
	## explode (tek kullanimlik mayin). Sensorlu agda yalnizca tetiklenince.
	var info := info_of(entry)
	entry.cooldown = maxf(0.0, float(entry.cooldown) - delta)
	if entry.cooldown > 0.0:
		return
	if float(info.get("power", 0.0)) > 0.0 and not bool(entry.powered):
		return
	var radius := float(info.get("radius", 0.9))
	var effect := str(info.get("effect", "damage"))
	var hit := false
	for actor: Node3D in game.actors.near(center + Vector3(0, 0.5, 0), radius):
		if actor.faction() != "zombie" or not actor.is_alive():
			continue
		hit = true
		var damage := float(entry.stats.get("damage", 20.0))
		match effect:
			"burn":
				actor.receive_damage(damage, "fire", Vector3.UP, actor.global_position, null, "body")
			"shock":
				actor.receive_damage(damage, "shock", Vector3.UP, actor.global_position, null, "body")
			"slow":
				actor.receive_damage(damage, "physical", Vector3.UP, actor.global_position, null, "body")
				if actor.has_method("apply_status"):
					actor.apply_status("slow", 3.0, float(info.get("slow", 0.5)))
			"explode":
				game.throwables.explode(center + Vector3(0, 0.3, 0), damage, float(info.get("blast", 3.5)))
				entry.uses = 0
				break
			_:
				actor.receive_damage(damage, "physical", Vector3.UP, actor.global_position, null, "body")
		if effect != "explode":
			game.sfx.play_at(str(info.get("sound", "impact_flesh")), center, -2.0)
	if hit:
		entry.cooldown = float(info.get("cooldown", 0.8))
		if int(info.get("uses", -1)) != 0 or entry.stats.has("uses"):
			entry.uses = int(entry.uses) - 1
			if int(entry.uses) <= 0:
				# Tuzak tukendi: esya geri verilmez (harcandi).
				_release_cells(entry)
				_free_node(entry)
				entries.erase(entry)
				changed.emit()
				game.hud.message("%s tükendi" % label_of(entry), Hud.ACCENT)


func _tick_alarm(entry: Dictionary, center: Vector3, delta: float, game: Node) -> void:
	var info := info_of(entry)
	entry.cooldown = maxf(0.0, float(entry.cooldown) - delta)
	if entry.cooldown > 0.0:
		return
	if float(info.get("power", 0.0)) > 0.0 and not bool(entry.powered):
		return
	var radius := float(info.get("radius", 12.0))
	for actor: Node3D in game.actors.near(center, radius):
		if actor.faction() == "zombie" and actor.is_alive():
			entry.cooldown = float(info.get("cooldown", 20.0))
			game.hud.message("ALARM: %s · %s, %d m" % [label_of(entry), game._bearing(actor.global_position),
				int(game.player.global_position.distance_to(actor.global_position))], Hud.RED)
			game.sfx.play_at(str(info.get("sound", "zombie_scream")), center, 2.0)
			var noise := float(info.get("noise", 0.0))
			if noise > 0.0:
				game.on_noise_at(center, Units.perception_m(noise))
			return


func _tick_decoy(entry: Dictionary, center: Vector3, delta: float, game: Node) -> void:
	var info := info_of(entry)
	entry.cooldown = maxf(0.0, float(entry.cooldown) - delta)
	if entry.cooldown > 0.0 or not bool(entry.on):
		return
	if float(info.get("power", 0.0)) > 0.0 and not bool(entry.powered):
		return
	entry.cooldown = float(info.get("interval", 12.0))
	game.on_noise_at(center, Units.perception_m(float(info.get("noise", 500.0))))
	game.sfx.play_at("zombie_scream", center, -4.0)


# ---------------------------------------------------------------------------
# Kalicilik
# ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	var list: Array = []
	for entry: Dictionary in entries:
		var data := {"item": entry.item_id, "q": entry.quality, "cell": [entry.cell.x, entry.cell.y, entry.cell.z],
			"rot": entry.rot, "health": entry.health, "uses": entry.uses, "on": entry.on,
			"fuel": snappedf(float(entry.fuel), 0.01), "charge": snappedf(float(entry.charge), 0.1),
			"ammo": int(entry.ammo), "state": entry.state.duplicate(true)}
		if entry.has("inv"):
			data["inv"] = (entry.inv as Inventory).to_dict()
		list.append(data)
	return {"entries": list}


func load_dict(data: Dictionary) -> void:
	for entry: Dictionary in entries:
		_free_node(entry)
		for c: Vector3i in entry.get("cells", []):
			_by_cell.erase(c)
	entries.clear()
	_by_cell.clear()
	for raw: Variant in data.get("entries", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var definition := Content.item(raw.get("item", ""))
		if definition == null or not catalog.has(definition.id):
			continue
		var c: Array = raw.get("cell", [0, 0, 0])
		var entry := place(ItemStack.new(definition, 1, float(raw.get("q", 50.0))),
			Vector3i(int(c[0]), int(c[1]), int(c[2])), int(raw.get("rot", 0)))
		entry.health = float(raw.get("health", entry.health))
		entry.uses = int(raw.get("uses", entry.uses))
		entry.on = bool(raw.get("on", true))
		entry.fuel = float(raw.get("fuel", 0.0))
		entry.charge = float(raw.get("charge", 0.0))
		entry.ammo = int(raw.get("ammo", 0))
		var state: Variant = raw.get("state", {})
		if typeof(state) == TYPE_DICTIONARY and not state.is_empty():
			entry.state = state
		if entry.has("inv") and typeof(raw.get("inv")) == TYPE_DICTIONARY:
			(entry.inv as Inventory).load_dict(raw.inv, Content.items)
