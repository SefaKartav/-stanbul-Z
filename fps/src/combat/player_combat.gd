class_name PlayerCombat
extends Node
## Oyuncunun silah kullanimi: kusanma, ates, doldurma, yakin dovus.
##
## KURALLAR
##   * Cevre bloklarina YALNIZCA ATESLI SILAH hasar verir. Yakin dovus
##     silahi (boru, balta) yalnizca aktorlere vurur; blok kirmaz, kazmaz.
##   * Menu/harita acikken tiklama ateslemez: `input_enabled` kapalidir ve
##     menu kapandiktan sonra tetik bir kez BIRAKILMADAN ates edilmez.
##   * Her atis gurultu uretir (`noise` sinyali); zombiler onu duyar.

signal noise(position: Vector3, radius: float)
signal fired(weapon: WeaponDef)
signal block_destroyed(cell: Vector3i, value: int, origin: int)
signal actor_hit(actor: Object, killed: bool, zone: String)
signal message(text: String)
signal loadout_changed
signal harvested(drops: Array, at: Vector3)

const SLOT_COUNT := 4

var player: Player
var view: WeaponView
var inventory: Inventory
var hitscan: Hitscan
var actors: ActorRegistry
var effects: Effects
var sfx: Sfx
var crosshair: Crosshair
var skills := SkillProfile.new()
var input_enabled := true
var gathering: Gathering          # alet (harvest_*) vuruslari icin; yoksa toplama yok
var focus := 1.0                  # "Odakli" durum etkisi: dagilma carpani (Game her kare yazar)

var slots: Array = [null, null, null, null]   # ItemStack referanslari (envanterdeki)
var active_slot := -1
var state: WeaponState
var _rng := RandomNumberGenerator.new()
var _trigger_released := true
var _was_reloading := false


func _ready() -> void:
	_rng.randomize()


func setup(p_player: Player, p_view: WeaponView, p_inventory: Inventory, p_hitscan: Hitscan,
		p_actors: ActorRegistry, p_effects: Effects, p_sfx: Sfx, p_crosshair: Crosshair) -> void:
	player = p_player
	view = p_view
	inventory = p_inventory
	hitscan = p_hitscan
	actors = p_actors
	effects = p_effects
	sfx = p_sfx
	crosshair = p_crosshair
	inventory.changed.connect(_on_inventory_changed)


# --- tasima ---
func _on_inventory_changed() -> void:
	## Envanterden cikan silah yuvadan da duser; yeni silah bos yuvaya girer.
	for i in SLOT_COUNT:
		if slots[i] != null and not inventory.stacks.has(slots[i]):
			slots[i] = null
			if i == active_slot:
				_unequip()
	for stack: ItemStack in inventory.stacks:
		# Silah ve TOPLAMA ALETI (weapon_id tasiyan her esya) yuvaya girer.
		if stack.definition.weapon_id == "" or slots.has(stack):
			continue
		var free := slots.find(null)
		if free < 0:
			break
		slots[free] = stack
		if active_slot < 0:
			equip(free)
	loadout_changed.emit()


func assign_slot(index: int, stack: ItemStack) -> void:
	if index < 0 or index >= SLOT_COUNT or stack == null or stack.definition.weapon_id == "":
		return
	var previous := slots.find(stack)
	if previous >= 0:
		slots[previous] = slots[index]
	slots[index] = stack
	if active_slot == index or active_slot == previous:
		equip(index)
	loadout_changed.emit()


func equip(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT or slots[index] == null:
		return
	if state != null:
		state.cancel_reload()
	var stack: ItemStack = slots[index]
	var weapon: WeaponDef = Content.weapons.get(stack.definition.weapon_id)
	if weapon == null:
		return
	active_slot = index
	state = WeaponState.new(stack, weapon, inventory)
	state.cooldown = WeaponView.EQUIP_TIME
	view.show_weapon(weapon)
	if sfx != null:
		sfx.play_at("equip", player.eye_position(), -8.0)
	loadout_changed.emit()


func _unequip() -> void:
	active_slot = -1
	state = null
	view.show_weapon(null)
	loadout_changed.emit()


func cycle(direction: int) -> void:
	for step in range(1, SLOT_COUNT + 1):
		var index := posmod(active_slot + step * direction, SLOT_COUNT)
		if slots[index] != null:
			equip(index)
			return


# --- adim ---
func physics_step(delta: float) -> void:
	if state == null:
		return
	var finished := state.tick(delta)
	if finished:
		view.end_reload()
		if sfx != null:
			sfx.play_at("reload_in", player.eye_position(), -6.0)
		loadout_changed.emit()
	if state.reloading():
		view.set_reload_progress(1.0 - state.reload_timer / maxf(0.01, state.reload_total))

	if not input_enabled:
		_trigger_released = false
		return
	for i in SLOT_COUNT:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			equip(i)
	if Input.is_action_just_pressed("weapon_next"):
		cycle(1)
	if Input.is_action_just_pressed("weapon_prev"):
		cycle(-1)
	if Input.is_action_just_pressed("reload"):
		_try_reload()

	var held := Input.is_action_pressed("fire")
	if not held:
		_trigger_released = true
		state.trigger_held = false
		return
	if not _trigger_released:
		return
	var wants := held if state.weapon.automatic else (held and not state.trigger_held)
	state.trigger_held = true
	if not wants:
		return
	if state.broken():
		message.emit("%s bozuk -- tezgahta onar" % state.stack.definition.name)
		_trigger_released = false
		return
	if not state.can_fire():
		if not state.weapon.is_melee() and state.loaded() <= 0 and not state.reloading():
			if not _try_reload() and sfx != null:
				sfx.play_at("dry_fire", player.eye_position(), -6.0)
				_trigger_released = false
		return
	if state.weapon.is_melee():
		_swing()
	else:
		_fire()


func _try_reload() -> bool:
	if state.begin_reload(skills):
		view.begin_reload()
		if sfx != null:
			sfx.play_at("reload_out", player.eye_position(), -6.0)
		return true
	if not state.weapon.is_melee() and state.reserve() <= 0 and state.loaded() < state.magazine_size():
		var def := state.ammo_def()
		message.emit("Çantada %s yok" % (def.name if def != null else state.weapon.ammo_type))
	return false


func current_spread() -> float:
	if state == null:
		return 1.0
	var moving := clampf(Vector2(player.velocity.x, player.velocity.z).length() / Player.WALK_SPEED, 0.0, 1.6)
	if not player.on_floor:
		moving += 1.5
	return state.total_spread(skills, player.aiming, moving, player.crouching) * focus


func _fire() -> void:
	var weapon := state.weapon
	var eye := player.eye_position()
	var forward := player.look_direction()
	var muzzle := view.muzzle_global()
	var spread := current_spread()
	var damage := state.damage(skills)
	var max_range := state.range_m()
	var killed_any := false
	var hit_any := false
	for offset: Vector2 in WeaponState.spread_offsets(weapon.pellets, spread, _rng):
		var direction := Hitscan.direction_with_spread(forward, offset)
		var result := hitscan.fire(eye, direction, muzzle, max_range, damage, state.damage_type(),
			state.pierce(), "player", player)
		for impact: Dictionary in result.impacts:
			if impact.kind == "block":
				_block_feedback(impact)
			elif impact.kind == "actor":
				hit_any = true
				killed_any = killed_any or impact.killed
				actor_hit.emit(impact.actor, impact.killed, impact.zone)
				if effects != null:
					effects.blood(impact.position, direction)
				if sfx != null:
					sfx.play_at("impact_flesh", impact.position, -4.0)
		if effects != null and _rng.randf() < 0.5:
			effects.tracer(muzzle, result.end)
	state.consume_round(skills)
	var suppressed := state.stack.mod_in_slot("barrel") != null and state.stack.stat_multiplier("noise_radius") < 0.6
	if sfx != null:
		sfx.play_at("shot_suppressed" if suppressed else _shot_sound(weapon), muzzle, 0.0 if not suppressed else -6.0, 0.04)
		if weapon.category in ["pistol", "rifle", "smg"]:
			# Kovan yere duser (yakin, kisik).
			sfx.play_at("shell_eject", player.global_position + Vector3(0.3, 0.1, 0.0), -14.0, 0.1)
	if effects != null and not suppressed:
		effects.muzzle_flash(muzzle, 1.0)
	view.fire_kick(weapon.shake * 4.0)
	# Geri tepme: kamerayi yukari iter; nisan alirken ve comelirken azalir.
	var kick := state.recoil() * (0.55 if player.aiming else 1.0) * (0.8 if player.crouching else 1.0)
	player.add_recoil(kick * 0.9, _rng.randf_range(-kick, kick) * 0.35)
	player.add_trauma(weapon.shake * 0.6)
	if crosshair != null and hit_any:
		crosshair.hit_marker = 1.0
		if killed_any:
			crosshair.kill_marker = 1.0
	noise.emit(player.global_position, state.noise_m(skills))
	fired.emit(weapon)
	loadout_changed.emit()


func _block_feedback(impact: Dictionary) -> void:
	var value: int = impact.value
	if value <= 0 or value == VoxelWorld.BOUNDARY:
		return
	var def := Content.blocks.get_def(value)
	var color: Color = Content.blocks.colors[value]
	if effects != null:
		effects.impact(impact.position, impact.normal, color, impact.destroyed)
	if sfx != null:
		var sound: String = def.get("impact_sound_id", "impact_stone")
		if impact.destroyed:
			sound = "break_glass" if def.get("fragile", false) else "break_block"
		sfx.play_at(sound, impact.position, -2.0 if impact.destroyed else -5.0)
	if impact.destroyed:
		block_destroyed.emit(impact.cell, value, impact.origin)


func _shot_sound(weapon: WeaponDef) -> String:
	match weapon.category:
		"shotgun": return "shot_shotgun"
		"smg": return "shot_smg"
		"rifle": return "shot_rifle"
	return "shot_revolver" if weapon.id == "revolver_357" else "shot_pistol"


func is_harvest_tool(stack: ItemStack) -> bool:
	for key: String in stack.definition.effects:
		if key.begins_with("harvest_") and key != "harvest_yield":
			return true
	return false


func _swing() -> void:
	## Yakin dovus: onundeki koniye ANINDA vurur. Silah BLOKLARA HASAR VERMEZ;
	## yalnizca toplama aleti (harvest_*) kendi sinifindaki blogu kazar.
	var weapon := state.weapon
	var eye := player.eye_position()
	var forward := player.look_direction()
	var reach := Units.move_m(weapon.range_px) + 0.9
	var half_angle := maxf(10.0, weapon.spread)
	var hits := 0
	var damage := state.damage(skills) * skills.multiplier("melee_damage")
	var silent := false
	var tool := is_harvest_tool(state.stack)
	if tool:
		var cost := float(state.stack.definition.effects.get("stamina_cost", Gathering.STAMINA_PER_SWING))
		if player.stamina < cost:
			message.emit("Nefesin yetmiyor -- biraz dinlen")
			state.cooldown = 0.6
			return
		player.stamina -= cost
	view.swing()
	for actor: Node3D in actors.near(eye, reach + 1.0):
		if actor.faction() == "player" or not actor.is_alive():
			continue
		var target: Vector3 = actor.global_position + Vector3(0, 1.1, 0)
		var offset := target - eye
		if offset.length() > reach:
			continue
		if rad_to_deg(forward.angle_to(offset)) > half_angle:
			continue
		# Duvarin arkasindakine vurulmaz.
		if not VoxelRay.line_clear(hitscan.world, eye, target):
			continue
		# Sessiz infaz: seni fark etmemis zombiye iki kat, gurultusuz.
		var dealt_damage := damage
		if skills.has_behavior("silent_melee") and actor is Zombie \
				and (actor as Zombie).state in [Zombie.State.IDLE, Zombie.State.WANDER]:
			dealt_damage *= 2.0
			silent = true
		var result: Dictionary = actor.receive_damage(dealt_damage, state.damage_type(), offset.normalized(),
			target, player, "body")
		actor_hit.emit(actor, result.get("killed", false), "body")
		if effects != null:
			effects.blood(target, offset.normalized())
		hits += 1
		if hits >= maxi(1, weapon.pierce + 1):
			break
	if tool and hits == 0 and gathering != null:
		var r := gathering.swing(state.stack, eye, forward, reach, damage)
		if r.hit:
			var value: int = r.value
			var color: Color = Content.blocks.colors[value]
			if effects != null:
				effects.impact(r.position, r.normal, color, r.destroyed)
			if sfx != null:
				var def := Content.blocks.get_def(value)
				sfx.play_at("break_block" if r.destroyed else str(def.get("impact_sound_id", "impact_stone")), r.position, -3.0)
			noise.emit(r.position, Units.perception_m(140.0) * skills.multiplier("noise_radius"))
			if r.destroyed:
				block_destroyed.emit(r.cell, value, VoxelWorld.ORIGIN_PLACED)   # enkaz dususu yerine toplama urunu
				if not r.drops.is_empty():
					harvested.emit(r.drops, r.position)
		elif str(r.reason) != "":
			message.emit(str(r.reason))
	state.consume_round(skills)
	if sfx != null:
		sfx.play_at("melee_hit" if hits > 0 else "melee_swing", eye, -3.0)
	if crosshair != null and hits > 0:
		crosshair.hit_marker = 1.0
	player.add_trauma(weapon.shake * 0.5)
	if not silent:
		noise.emit(player.global_position, state.noise_m(skills))
	loadout_changed.emit()


func to_dict() -> Dictionary:
	var slot_indices: Array = []
	for stack: Variant in slots:
		slot_indices.append(inventory.stacks.find(stack) if stack != null else -1)
	return {"slots": slot_indices, "active": active_slot}


func load_dict(data: Dictionary) -> void:
	slots = [null, null, null, null]
	var indices: Array = data.get("slots", [])
	for i in mini(indices.size(), SLOT_COUNT):
		var index := int(indices[i])
		if index >= 0 and index < inventory.stacks.size():
			var stack: ItemStack = inventory.stacks[index]
			if stack.definition.weapon_id != "":
				slots[i] = stack
	var active := int(data.get("active", -1))
	if active >= 0 and slots[active] != null:
		equip(active)
	else:
		_unequip()
		_on_inventory_changed()
