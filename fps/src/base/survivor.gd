class_name Survivor
extends Node3D
## Hayatta kalan NPC: sehirde kurtarilmayi bekleyen ya da usteki sakin.
##
## GORUNEN BEDEN, KALICI KAYIT DEGILDIR: sakinin cani, morali ve isi
## Colony kaydinda (residents) tutulur; bu dugum onun dunyadaki yansimasidir.
## Bu ayrim uzak ussun soyut uretimiyle yakindaki NPC'nin isinin CIFT
## uretim yapmasini engeller: iki taraf da ayni kaydi okur/yazar.
##
## Nobetci (guard) zombilere ates eder ve her atista ussun deposundan
## GERCEK bir fisek harcar; fisek bitince susar.

enum Mode { WAITING, FOLLOW, RESIDENT, DEAD }

const HALF_WIDTH := 0.3
const HEIGHT := 1.85

var profile_id := ""
var mode := Mode.WAITING
var manager: Node
var velocity := Vector3.ZERO
var on_floor := false
var facing := Vector3.FORWARD
var health := 100.0
var target_point := Vector3.ZERO
var wander_timer := 0.0
var guard_cooldown := 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _current := ""
var _label: Label3D


func setup(p_profile: String, p_manager: Node, p_mode: int) -> void:
	profile_id = p_profile
	manager = p_manager
	mode = p_mode


func _ready() -> void:
	var models := ["survivor_scout", "survivor_medic", "survivor_engineer", "survivor_guard", "survivor_civilian"]
	var model_id: String = models[absi(hash(profile_id)) % models.size()]
	match profile_id:
		"ayse": model_id = "survivor_medic"
		"cem": model_id = "survivor_guard"
		"murat": model_id = "survivor_engineer"
		"deniz": model_id = "survivor_scout"
	# 600 paket: meslege ozel karakter modeli (su teknisyeni, elektrikci...).
	var profile: Dictionary = Content.colony.get("profiles", {}).get(profile_id, {})
	if AssetLibrary.has(str(profile.get("model", ""))):
		model_id = str(profile.model)
	_model = AssetLibrary.instantiate(model_id)
	add_child(_model)
	_anim = _find_anim(_model)
	if _anim != null:
		for loop_name: String in ["idle", "walk"]:
			if _anim.has_animation(loop_name):
				_anim.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.2, 0)
	_label.font_size = 40
	_label.outline_size = 10
	_label.modulate = Color(0.95, 0.9, 0.7)
	_label.no_depth_test = false
	add_child(_label)
	_refresh_label()


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


func _refresh_label() -> void:
	var profile: Dictionary = Content.colony.profiles.get(profile_id, {})
	var name: String = profile.get("name", profile_id)
	match mode:
		Mode.WAITING: _label.text = "%s (yardim bekliyor)" % name
		Mode.FOLLOW: _label.text = "%s (seni izliyor)" % name
		Mode.RESIDENT:
			var r: Dictionary = manager.colony().residents.get(profile_id, {})
			var role: String = Content.colony.roles.get(r.get("role", "idle"), {}).get("label", "")
			_label.text = "%s -- %s" % [name, role]
		_: _label.text = ""


func set_mode(p_mode: int) -> void:
	mode = p_mode
	_refresh_label()


# --- aktor arayuzu (zombiler NPC'leri hedefler, oyuncu mermisi gecer) ---
func faction() -> String:
	return "survivor"


func is_alive() -> bool:
	return mode != Mode.DEAD


func hit_test(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var p := global_position
	var d := ActorRegistry.ray_box(origin, direction, Vector3(p.x - HALF_WIDTH, p.y, p.z - HALF_WIDTH),
		Vector3(p.x + HALF_WIDTH, p.y + HEIGHT, p.z + HALF_WIDTH), max_distance)
	return {"distance": d, "zone": "body"} if d >= 0.0 else {}


func receive_damage(amount: float, _type: String, _direction: Vector3, _point: Vector3,
		_source: Object, _zone: String) -> Dictionary:
	if mode == Mode.DEAD:
		return {"dealt": 0.0, "killed": false}
	var r: Dictionary = manager.colony().residents.get(profile_id, {})
	if not r.is_empty():
		r.health = maxf(0.0, float(r.health) - amount)
		health = r.health
	else:
		health = maxf(0.0, health - amount)
	if health <= 0.0:
		set_mode(Mode.DEAD)
		manager.on_survivor_died(self)
		return {"dealt": amount, "killed": true}
	return {"dealt": amount, "killed": false}


# --- davranis ---
func think(delta: float, ctx: Dictionary) -> void:
	if mode == Mode.DEAD:
		return
	var goal := global_position
	var speed := 0.0
	match mode:
		Mode.WAITING:
			speed = 0.0
		Mode.FOLLOW:
			var player_pos: Vector3 = ctx.player_position
			if global_position.distance_to(player_pos) > 3.0:
				goal = player_pos
				speed = 4.6
		Mode.RESIDENT:
			var r: Dictionary = manager.colony().residents.get(profile_id, {})
			if r.get("role", "") == "guard" and r.get("health", 0) > 0:
				_guard(delta, ctx)
			wander_timer -= delta
			if wander_timer <= 0.0 or global_position.distance_to(target_point) < 1.0:
				wander_timer = randf_range(4.0, 9.0)
				target_point = manager.random_point_in_base(profile_id, global_position)
			goal = target_point
			speed = 1.6
	var to := goal - global_position
	to.y = 0.0
	var direction := to.normalized() if to.length() > 0.8 else Vector3.ZERO
	var desired := direction * speed
	velocity.x = move_toward(velocity.x, desired.x, 12.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 12.0 * delta)
	velocity.y = maxf(-40.0, velocity.y - 22.0 * delta)
	var result := VoxelBody.move(manager.world, global_position, velocity, delta, HALF_WIDTH, HEIGHT,
		0.55 if on_floor else 0.0, on_floor)
	global_position = result.position
	velocity.y = result.velocity.y
	on_floor = result.on_floor
	if result.hit_wall and on_floor and speed > 0.1:
		velocity.y = 7.2
	if direction.length_squared() > 0.0:
		facing = direction


func _guard(delta: float, ctx: Dictionary) -> void:
	## Nobetci: menzildeki en yakin zombiye ates eder, GERCEK fisek harcar.
	guard_cooldown -= delta
	if guard_cooldown > 0.0:
		return
	var cfg: Dictionary = Content.colony.settings
	var reach := Units.weapon_range_m(float(cfg.guard_range))
	var eye := global_position + Vector3(0, 1.6, 0)
	var best: Node3D = null
	var best_d := reach
	for actor: Node3D in manager.actors.near(global_position, reach):
		if actor.faction() != "zombie" or not actor.is_alive():
			continue
		var d := actor.global_position.distance_to(global_position)
		if d < best_d and VoxelRay.line_clear(manager.world, eye, actor.global_position + Vector3(0, 1.2, 0)):
			best = actor
			best_d = d
	if best == null:
		return
	guard_cooldown = float(cfg.guard_interval)
	var base: Settlement = manager.base_of(profile_id)
	if base == null or base.stockpile.count(cfg.guard_ammo) <= 0:
		manager.guard_out_of_ammo(profile_id)
		return
	base.stockpile.remove(cfg.guard_ammo, 1)
	var skill := float(manager.colony().residents[profile_id].skills.get("shooting", 0))
	var dir := (best.global_position + Vector3(0, 1.2, 0) - eye).normalized()
	var spread := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * maxf(0.5, 4.0 - skill * 0.35)
	dir = Hitscan.direction_with_spread(dir, spread)
	manager.guard_fire(self, eye, dir, float(cfg.guard_damage) * manager.colony().colony_skills.multiplier("guard_damage"),
		Units.perception_m(float(cfg.guard_noise)))
	facing = Vector3(dir.x, 0, dir.z).normalized()


func animate(delta: float) -> void:
	if mode == Mode.DEAD:
		_model.rotation.x = lerpf(_model.rotation.x, -PI * 0.5, clampf(delta * 6.0, 0.0, 1.0))
		return
	var flat := Vector2(velocity.x, velocity.z).length()
	if _anim != null:
		var name := "walk" if flat > 0.3 else "idle"
		if _current != name and _anim.has_animation(name):
			_current = name
			_anim.play(name, 0.2)
		_anim.speed_scale = clampf(flat / 1.5, 0.6, 2.0) if flat > 0.3 else 1.0
	if facing.length_squared() > 0.001:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-facing.x, -facing.z), clampf(delta * 8.0, 0.0, 1.0))
	if mode == Mode.RESIDENT and Engine.get_process_frames() % 60 == 0:
		_refresh_label()
