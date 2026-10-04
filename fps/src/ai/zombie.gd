class_name Zombie
extends Node3D
## Zombi: durum makinesi + duyu + voxel govdesi (Python: game/ai/brain.py,
## game/systems/ai.py).
##
## FSM (davranis agaci degil): bosta / dolasma / arastirma / kovalama /
## saldiri / sersemleme / olu. Zombi karar agaci sig; FSM okunakli ve ucuz.
##
## DUYULAR
##   * Gorus: yari aci `sight_angle`, gece daralir, fener acikken genisler.
##     ARKASI KORDUR -- sessizce arkadan gecmek mumkun olmali.
##   * Ses: silah, arama, bagiran zombi ayni `noise` yolundan gelir;
##     duyma = min(ses yaricapi, zombinin kulagi).
##   * Gorus hatti her ~5 adimda bir taranir (80 ms gec tepki bir ozellik).
##
## CEVREYE SALDIRI SINIRI
##   Zombi yalnizca OYUNCUNUN KOYDUGU kirilabilir bloklara (barikat) saldirir.
##   Haritanin kendi duvarlarini, zeminini kazmaz; yolu yoksa dolasir.

enum State { IDLE, WANDER, INVESTIGATE, CHASE, ATTACK, BREACH, STAGGER, DEAD }

## Oyuncunun kafa isabeti carpani (beceri agaci 'Zayif nokta': 2.0 x (1 + bonus)).
static var player_head_mult := 2.0

const HALF_WIDTH := 0.3
const HEIGHT := 1.85
const HEAD := 0.32
const STEP_HEIGHT := 0.55
const GRAVITY := 22.0
const JUMP_VELOCITY := 7.2
const SIGHT_CHECK_INTERVAL := 5
const CORPSE_TIME := 90.0

var def: ZombieDef
var manager: Node                 # ZombieManager
var health := 60.0
var state := State.IDLE
var state_time := 0.0
var velocity := Vector3.ZERO
var on_floor := false
var facing := Vector3.FORWARD
var last_known := Vector3.ZERO
var investigate_timer := 0.0
var attack_timer := 0.0
var windup_timer := -1.0
var stagger_timer := 0.0
var scream_timer := 0.0
var wander_dir := Vector3.ZERO
var wander_timer := 0.0
var target: Object = null          # oyuncu ya da NPC
var breach_cell := Vector3i.ZERO
var awake := true
var tick_offset := 0
var corpse_timer := 0.0
var looted := false
var model_scale := 1.0
var slow_timer := 0.0              # dikenli tel / yapiskan tuzak: hiz carpani sure
var slow_amount := 0.0

var _model: Node3D
var _anim: AnimationPlayer
var _current_anim := ""
var _hurt_flash := 0.0
var _stuck_time := 0.0
var _last_position := Vector3.ZERO


func setup(p_def: ZombieDef, p_manager: Node, seed_value: int) -> void:
	def = p_def
	manager = p_manager
	health = def.health
	tick_offset = seed_value % SIGHT_CHECK_INTERVAL
	scream_timer = def.scream_interval
	model_scale = 1.0
	match def.id:
		"brute": model_scale = 1.22
		"bloated": model_scale = 1.12
		"hound": model_scale = 0.72
		"crawler": model_scale = 0.9
		"runner", "stalker": model_scale = 0.96


func _ready() -> void:
	var model := def.model_id(tick_offset * 7919 + int(get_instance_id() % 97))
	_model = AssetLibrary.instantiate(model)
	_model.scale = Vector3.ONE * model_scale
	if def.id == "crawler" and not model.begins_with("iz2_"):
		_model.scale.y *= 0.55      # sürünen: yere yakin
	add_child(_model)
	_anim = _find_player(_model)
	if _anim != null:
		for loop_name: String in ["idle", "walk"]:
			if _anim.has_animation(loop_name):
				_anim.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
		_play("idle")


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


func _play(name: String, speed: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(name):
		return
	if _current_anim != name:
		_current_anim = name
		_anim.play(name, 0.15)
	_anim.speed_scale = speed


# --- aktor arayuzu ---
func faction() -> String:
	return "zombie"


func is_alive() -> bool:
	return state != State.DEAD


func body_height() -> float:
	return HEIGHT * model_scale * (0.55 if def.id == "crawler" else 1.0)


func hit_test(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var p := global_position
	var w := HALF_WIDTH * model_scale
	var h := body_height()
	var head_min := Vector3(p.x - 0.2 * model_scale, p.y + h - HEAD * model_scale, p.z - 0.2 * model_scale)
	var head_max := Vector3(p.x + 0.2 * model_scale, p.y + h, p.z + 0.2 * model_scale)
	var head := ActorRegistry.ray_box(origin, direction, head_min, head_max, max_distance)
	var body := ActorRegistry.ray_box(origin, direction, Vector3(p.x - w, p.y, p.z - w),
		Vector3(p.x + w, p.y + h - HEAD * model_scale, p.z + w), max_distance)
	if head >= 0.0 and (body < 0.0 or head <= body):
		return {"distance": head, "zone": "head"}
	if body >= 0.0:
		return {"distance": body, "zone": "body"}
	return {}


func receive_damage(amount: float, damage_type: String, direction: Vector3, _point: Vector3,
		source: Object, zone: String) -> Dictionary:
	if state == State.DEAD:
		return {"dealt": 0.0, "killed": false}
	var head_mult := player_head_mult if source is Player else 2.0
	var raw := amount * (head_mult if zone == "head" else 1.0)
	var dealt := def.mitigate(raw, damage_type)
	health -= dealt
	_hurt_flash = 1.0
	# Geri itme ve sersemleme: vurulan zombi bir an duraklamali.
	var push := Units.move_m(90.0) * (1.0 - def.knockback_resist)
	velocity += Vector3(direction.x, 0, direction.z).normalized() * push * 0.6
	if health <= 0.0:
		_die()
		return {"dealt": dealt, "killed": true}
	if dealt >= def.health * 0.12 and def.stagger_time > 0.0:
		stagger_timer = def.stagger_time
		_enter(State.STAGGER)
	# Vurulan zombi atesin geldigi yonu bilir.
	if source != null and source is Node3D:
		last_known = (source as Node3D).global_position
		investigate_timer = def.investigate_time
		if state in [State.IDLE, State.WANDER, State.INVESTIGATE]:
			_enter(State.INVESTIGATE)
	return {"dealt": dealt, "killed": false}


func apply_status(kind: String, duration: float, magnitude: float) -> void:
	## Tuzak etkileri. Yalnizca yavaslatma zombi hareketini degistirir;
	## yanma/elektrik hasari tuzak tarafindan dogrudan verilir.
	if kind == "slow":
		slow_timer = maxf(slow_timer, duration)
		slow_amount = clampf(maxf(slow_amount, magnitude), 0.0, 0.85)


func _die() -> void:
	_enter(State.DEAD)
	health = 0.0
	corpse_timer = CORPSE_TIME
	if _anim != null:
		_anim.stop()
	if manager != null:
		manager.on_zombie_died(self)


func _enter(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_time = 0.0


# --- ses ---
func hear(position: Vector3, radius: float) -> void:
	if state in [State.DEAD, State.CHASE, State.ATTACK, State.BREACH]:
		return
	var hearing := minf(radius, def.hearing_m())
	if global_position.distance_to(position) <= hearing:
		last_known = position
		investigate_timer = def.investigate_time
		_enter(State.INVESTIGATE)


# --- dusunme + hareket (ZombieManager cagirir) ---
func think(delta: float, ctx: Dictionary) -> void:
	state_time += delta
	if attack_timer > 0.0:
		attack_timer -= delta
	var chosen: Object = ctx.player if ctx.player_alive else null
	var chosen_pos: Vector3 = ctx.player_position
	var distance: float = global_position.distance_to(chosen_pos) if chosen != null else INF
	var checking: bool = (ctx.tick + tick_offset) % SIGHT_CHECK_INTERVAL == 0
	# Yakindaki NPC'ler de hedeftir (koloni kusatmasi).
	for npc: Node3D in ctx.colonists:
		var d := global_position.distance_to(npc.global_position)
		if d < distance and d <= def.sight_m() and (not checking or _line_of_sight(npc.global_position)):
			chosen = npc
			chosen_pos = npc.global_position
			distance = d
	target = chosen

	if state == State.STAGGER:
		stagger_timer -= delta
		_move(delta, Vector3.ZERO, 0.0, ctx)
		if stagger_timer <= 0.0:
			_enter(State.CHASE if chosen != null else State.WANDER)
		return

	var senses := chosen != null and _can_sense(chosen_pos, distance, ctx, checking)
	if senses:
		last_known = chosen_pos
		investigate_timer = def.investigate_time
	var speed_mult: float = ctx.speed_multiplier
	match state:
		State.IDLE:
			if senses:
				_alert()
			elif state_time > 1.2:
				_enter(State.WANDER)
			_move(delta, Vector3.ZERO, 0.0, ctx)
		State.WANDER:
			if senses:
				_alert()
				return
			wander_timer -= delta
			if wander_timer <= 0.0:
				wander_timer = randf_range(1.4, 3.6)
				if randf() < 0.35:
					wander_dir = Vector3.ZERO
				else:
					var angle := randf() * TAU
					wander_dir = Vector3(cos(angle), 0, sin(angle))
			_move(delta, wander_dir, def.speed_m() * 0.55, ctx)
		State.INVESTIGATE:
			if senses:
				_alert()
				return
			investigate_timer -= delta
			if investigate_timer <= 0.0:
				_enter(State.WANDER)
				return
			var to := last_known - global_position
			to.y = 0.0
			if to.length() < 1.5:
				investigate_timer = minf(investigate_timer, 1.0)
				_move(delta, Vector3.ZERO, 0.0, ctx)
			else:
				_move(delta, _path_direction(last_known, ctx), def.speed_m() * speed_mult, ctx)
		State.CHASE:
			if distance <= def.attack_range_m():
				_enter(State.ATTACK)
				windup_timer = def.attack_windup
				return
			if not senses and investigate_timer <= 0.0:
				_enter(State.INVESTIGATE)
				investigate_timer = def.investigate_time
				return
			investigate_timer -= delta
			_scream(delta)
			var direction := _path_direction(chosen_pos, ctx)
			if state == State.BREACH:
				return
			_move(delta, direction, def.sprint_speed_m() * speed_mult, ctx)
		State.ATTACK:
			_attack(delta, chosen, chosen_pos, distance, ctx)
		State.BREACH:
			_breach(delta, ctx)


func _alert() -> void:
	_enter(State.CHASE)
	if manager != null:
		manager.play_sound("zombie_alert", global_position, -4.0)


func _can_sense(target_pos: Vector3, distance: float, ctx: Dictionary, checking: bool) -> bool:
	var sight: float = def.sight_m() * ctx.sight_multiplier * ctx.light_bonus * ctx.stealth
	if distance > sight:
		return false
	if not checking:
		return state in [State.CHASE, State.ATTACK, State.BREACH]
	var to := target_pos - global_position
	to.y = 0.0
	if to.length_squared() > 0.01 and facing.length_squared() > 0.0:
		if rad_to_deg(facing.angle_to(to)) > def.sight_angle:
			return false
	return _line_of_sight(target_pos)


func _line_of_sight(target_pos: Vector3) -> bool:
	var eye := global_position + Vector3(0, body_height() * 0.9, 0)
	return VoxelRay.line_clear(manager.world, eye, target_pos + Vector3(0, 1.5, 0))


func _scream(delta: float) -> void:
	if def.scream_radius <= 0.0:
		return
	scream_timer -= delta
	if scream_timer > 0.0:
		return
	scream_timer = def.scream_interval
	manager.emit_noise(global_position, def.scream_m())
	manager.play_sound("zombie_scream", global_position, 0.0)


func _path_direction(goal: Vector3, ctx: Dictionary) -> Vector3:
	## Akis alani yon verirse onu, vermezse dogrudan hedefe. Siradaki hucre
	## oyuncu barikatiysa BREACH durumuna gecilir.
	var nav: NavGrid = ctx.nav
	var cell := Vector2i(floori(global_position.x), floori(global_position.z))
	var goal_cell := Vector2i(floori(goal.x), floori(goal.z))
	if nav != null and nav.ready_target.distance_to(goal_cell) < 3.0 and nav.reachable(cell.x, cell.y):
		var step := nav.next_step(cell.x, cell.y)
		if not step.is_empty():
			if step.barricade:
				var barricade := nav.barricade_cell(step.cell.x, step.cell.y)
				if barricade.y != NavGrid.NONE:
					var center := Vector3(barricade) + Vector3(0.5, 0, 0.5)
					var flat := center - global_position
					flat.y = 0.0
					if flat.length() < 1.3:
						breach_cell = barricade
						_enter(State.BREACH)
						return Vector3.ZERO
			var next := Vector3(step.cell.x + 0.5, 0, step.cell.y + 0.5) - Vector3(global_position.x, 0, global_position.z)
			if next.length_squared() > 0.0001:
				return next.normalized()
	var direct := goal - global_position
	direct.y = 0.0
	return direct.normalized() if direct.length_squared() > 0.01 else Vector3.ZERO


func _attack(delta: float, chosen: Object, chosen_pos: Vector3, distance: float, ctx: Dictionary) -> void:
	_move(delta, Vector3.ZERO, 0.0, ctx)
	var to := chosen_pos - global_position
	to.y = 0.0
	if to.length_squared() > 0.0:
		facing = to.normalized()
	# Menzilden cikarsa hazirlik iptal: oyuncu geri cekilerek KACABILMELI.
	if chosen == null or distance > def.attack_range_m() * 1.35:
		windup_timer = -1.0
		_enter(State.CHASE)
		return
	if windup_timer >= 0.0:
		windup_timer -= delta
		if windup_timer <= 0.0:
			windup_timer = -1.0
			if distance <= def.attack_range_m() * 1.15:
				manager.zombie_strikes(self, chosen, to.normalized())
			attack_timer = def.attack_cooldown
		return
	if attack_timer <= 0.0:
		windup_timer = def.attack_windup
		_play("attack", 1.2)


func _breach(delta: float, ctx: Dictionary) -> void:
	## Barikat kirma: yalnizca oyuncunun koydugu kirilabilir blok.
	var world: VoxelWorld = manager.world
	var value := world.get_cell(breach_cell)
	if value == 0 or value == VoxelWorld.BOUNDARY or not world.placed.has(breach_cell) \
			or world.materials.zombie_breakable[value] == 0:
		_enter(State.CHASE)
		return
	var to := Vector3(breach_cell) + Vector3(0.5, 0, 0.5) - global_position
	to.y = 0.0
	if to.length() > 1.8:
		_enter(State.CHASE)
		return
	facing = to.normalized()
	_move(delta, to.normalized() * 0.2, 0.3, ctx)
	if attack_timer <= 0.0:
		attack_timer = def.attack_cooldown
		_play("attack", 1.0)
		manager.zombie_hits_block(self, breach_cell, def.damage * 1.5)


func _move(delta: float, direction: Vector3, speed: float, ctx: Dictionary) -> void:
	if slow_timer > 0.0:
		slow_timer -= delta
		speed *= 1.0 - slow_amount
		if slow_timer <= 0.0:
			slow_amount = 0.0
	var desired := direction * speed
	# Kalabalikta ayrisma: ust uste binmesinler.
	desired += manager.separation(self) * 1.2
	var accel := def.acceleration_m() * 1.5
	var horizontal := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3(desired.x, 0, desired.z), accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = maxf(-40.0, velocity.y - GRAVITY * delta)
	var result := VoxelBody.move(manager.world, global_position, velocity, delta,
		HALF_WIDTH * minf(model_scale, 1.0), body_height(), STEP_HEIGHT if on_floor else 0.0, on_floor)
	var before := global_position
	global_position = result.position
	on_floor = result.on_floor
	velocity.y = result.velocity.y
	# Tam bloga takildiysa zipla (zombiler 1 m'lik basamagi asar).
	if result.hit_wall and on_floor and speed > 0.1:
		velocity.y = JUMP_VELOCITY
	var moved := (global_position - before)
	moved.y = 0.0
	if speed > 0.1 and moved.length() < speed * delta * 0.1:
		_stuck_time += delta
		if _stuck_time > 1.5:
			# Sikisma: rastgele yana kay. Akis alani bir sonraki taramada duzelir.
			var angle := randf() * TAU
			velocity += Vector3(cos(angle), 0, sin(angle)) * 2.0
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0
	if direction.length_squared() > 0.01:
		facing = facing.lerp(direction.normalized(), clampf(delta * 8.0, 0.0, 1.0)).normalized()


func animate(delta: float) -> void:
	if state == State.DEAD:
		_model.rotation.x = lerpf(_model.rotation.x, -PI * 0.5, clampf(delta * 6.0, 0.0, 1.0))
		_model.position.y = lerpf(_model.position.y, 0.12, clampf(delta * 6.0, 0.0, 1.0))
		return
	var flat := Vector2(velocity.x, velocity.z).length()
	if state in [State.ATTACK, State.BREACH] and windup_timer >= 0.0 or (state == State.BREACH):
		pass
	elif flat > 0.3:
		_play("walk", clampf(flat / 1.6, 0.6, 2.4))
	else:
		_play("idle", 1.0)
	if facing.length_squared() > 0.001:
		# Paket modellerinin on yonu -Z (manifest): donus = atan2(-x, -z).
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-facing.x, -facing.z), clampf(delta * 10.0, 0.0, 1.0))
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 4.0)


func to_dict() -> Dictionary:
	return {"id": def.id, "p": [global_position.x, global_position.y, global_position.z],
		"hp": health, "state": state if state != State.DEAD else State.DEAD}
