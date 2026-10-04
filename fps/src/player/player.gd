class_name Player
extends Node3D
## Birinci sahis karakter denetleyicisi.
##
## Konum = AYAK merkezi. Govde 0.6 m genis, ayakta 1.8 m, comelince 1.3 m.
## Hareket VoxelBody ile dogrudan voxel verisine karsi cozulur (bkz. oradaki
## gerekce). Kamera ve silah bu dugumun cocuklaridir.
##
## Ayarlar (bkz. Settings): dikey/yatay hassasiyet, ters Y, FOV, bas
## sallanmasi ve ekran sarsintisi siddeti. Hepsi 0'a indirilebilir.

signal landed(fall_speed: float)
signal footstep

const HALF_WIDTH := 0.3
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.3
const STAND_EYE := 1.62
const CROUCH_EYE := 1.12
## GERCEK OLCEK HAREKETI (25 Eylul 2026): 1 birim = 1 m. Eski 4.3 / 6.8 m/sn
## sikistirilmis haritada bile hizliydi. Kademeler:
##   yuru 1.7 m/sn (Caps Lock ile gecis), kos 3.6 m/sn (varsayilan, nefes
##   harcamaz), depar 5.6 m/sn (Shift, nefes harcar). "Her zaman kos"
##   ayari kapatilirsa varsayilan yuruyus olur, Caps Lock kosuya gecer.
const WALK_SPEED := 1.7
const RUN_SPEED := 3.6
const SPRINT_SPEED := 5.6
const CROUCH_SPEED := 1.2
const AIM_SPEED_FACTOR := 0.6
const GROUND_ACCEL := 14.0
const AIR_ACCEL := 3.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 7.6        # ~1.3 m: tam bloga zıplanir
const STEP_HEIGHT := 0.55         # kaldirim/yarim blok otomatik
const MAX_FALL := 40.0
const STAMINA_MAX := 100.0
const SPRINT_DRAIN := 14.0        # /sn (depar)
const STAMINA_REGEN := 12.0       # yururken/dururken
const RUN_REGEN := 3.0            # kosarken yavas dolar
const JUMP_COST := 8.0

var world: VoxelWorld
var extra_boxes_provider: Callable   # () -> Array (arac, sandik gibi katı dekor)
var velocity := Vector3.ZERO
var on_floor := false
var crouching := false
var sprinting := false
var walk_mode := false            # Caps Lock: yuru <-> kos gecisi
var climbing := false             # tirmanma merdiveninde
const CLIMB_SPEED := 2.0
var stamina_cap := STAMINA_MAX    # aclik/susuzluk nefes tavanini dusurur
var regen_factor := 1.0           # aclik/susuzluk nefes yenilenmesini yavaslatir
var aiming := false
var stamina := STAMINA_MAX
var speed_factor := 1.0           # agirlik yuku ve durum etkileri
var input_enabled := true
var driving := false              # aracta: govde hareketi aracin, bakis serbest
var fov_override := 0.0           # >0: dikey gorus acisi zorla (arac kabini)
var yaw := 0.0
var pitch := 0.0
var height := STAND_HEIGHT
var eye_height := STAND_EYE
var in_water := false

var camera: Camera3D
var head: Node3D                  # yaw/pitch koku; silah buna baglidir
var _bob_time := 0.0
var _bob_offset := Vector3.ZERO
var _trauma := 0.0
var _land_dip := 0.0
var _step_distance := 0.0
var _dodge_time := 0.0
var _dodge_velocity := Vector3.ZERO
var _noise := FastNoiseLite.new()


func _ready() -> void:
	head = Node3D.new()
	head.name = "Head"
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.05
	camera.far = 900.0
	camera.current = true
	head.add_child(camera)
	head.position.y = eye_height
	_noise.seed = 7
	_noise.frequency = 2.0
	camera.fov = Settings.fov
	Settings.changed.connect(func() -> void: camera.fov = Settings.fov)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var aim_factor := 0.65 if aiming else 1.0
		yaw -= deg_to_rad(motion.relative.x * Settings.sensitivity_x * aim_factor)
		var dy := motion.relative.y * Settings.sensitivity_y * aim_factor
		if Settings.invert_y:
			dy = -dy
		pitch = clampf(pitch - deg_to_rad(dy), deg_to_rad(-89.0), deg_to_rad(89.0))


var alive := true


func faction() -> String:
	return "player"


func is_alive() -> bool:
	return alive


func look_direction() -> Vector3:
	return -camera.global_transform.basis.z


func eye_position() -> Vector3:
	return camera.global_position


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount * Settings.screen_shake)


func add_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	pitch = clampf(pitch + deg_to_rad(pitch_degrees), deg_to_rad(-89.0), deg_to_rad(89.0))
	yaw += deg_to_rad(yaw_degrees)


func dodge(direction: Vector3, speed: float, duration: float) -> void:
	## Kacinma hamlesi (eski "yuvarlanma"). Kamera ZORLA dondurulmez; yalnizca
	## govde kisa sure hizlanir. Duvardan gecirmez: VoxelBody engeller.
	if direction.length_squared() < 0.01:
		direction = -head.global_transform.basis.z
	direction.y = 0.0
	_dodge_velocity = direction.normalized() * speed
	_dodge_time = duration


func physics_step(delta: float) -> void:
	## Oyun sahnesi tarafindan sabit adimda cagrilir.
	if world == null or driving:
		velocity = Vector3.ZERO
		return
	var wish := Vector3.ZERO
	var wants_jump := false
	var wants_crouch := false
	var wants_sprint := false
	if input_enabled:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var basis := Basis(Vector3.UP, yaw)
		wish = basis * Vector3(input.x, 0.0, input.y)
		wants_jump = Input.is_action_just_pressed("jump")
		wants_crouch = Input.is_action_pressed("crouch")
		wants_sprint = Input.is_action_pressed("sprint") and input.y < -0.1
		aiming = Input.is_action_pressed("aim")
		if Input.is_action_just_pressed("walk_toggle"):
			walk_mode = not walk_mode
	else:
		aiming = false

	_update_crouch(wants_crouch)
	sprinting = wants_sprint and not crouching and not aiming and stamina > 1.0 and wish.length() > 0.1
	var speed := base_speed()
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if aiming:
		speed *= AIM_SPEED_FACTOR
	speed *= speed_factor
	if in_water:
		speed *= 0.55

	var target := wish * speed
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	horizontal = horizontal.move_toward(target, accel * speed * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var moving := wish.length() > 0.1
	if sprinting:
		stamina = maxf(0.0, stamina - SPRINT_DRAIN * delta)
	elif moving and base_speed() >= RUN_SPEED and not crouching:
		stamina = minf(stamina_cap, stamina + RUN_REGEN * regen_factor * delta)
	else:
		stamina = minf(stamina_cap, stamina + STAMINA_REGEN * regen_factor * delta)
	stamina = minf(stamina, stamina_cap)

	if wants_jump and on_floor and not crouching and stamina >= JUMP_COST * 0.5:
		velocity.y = JUMP_VELOCITY
		stamina = maxf(0.0, stamina - JUMP_COST)
		on_floor = false

	climbing = _touching_ladder()
	if climbing:
		# TIRMANMA MERDIVENI (dar bina cekirdegi): yercekimi yok; W/Space yukari,
		# S/Ctrl asagi, girdi yoksa tutunur. Yatayda merdivenden adim atilir.
		var up := 0.0
		if input_enabled:
			if Input.is_action_pressed("jump") or Input.is_action_pressed("move_forward"):
				up = CLIMB_SPEED
			elif Input.is_action_pressed("crouch") or Input.is_action_pressed("move_back"):
				up = -CLIMB_SPEED
		velocity.y = up
	elif in_water:
		velocity.y = move_toward(velocity.y, 1.0 if Input.is_action_pressed("jump") else -0.8, 8.0 * delta)
	else:
		velocity.y = maxf(-MAX_FALL, velocity.y - GRAVITY * delta)

	var total := velocity
	if _dodge_time > 0.0:
		_dodge_time -= delta
		total += _dodge_velocity

	var fall_speed := -velocity.y
	var boxes: Array = extra_boxes_provider.call() if extra_boxes_provider.is_valid() else []
	var result := VoxelBody.move(world, position, total, delta, HALF_WIDTH, height,
		STEP_HEIGHT if (on_floor or climbing) else 0.0, on_floor or climbing, boxes)
	var was_on_floor := on_floor
	var moved: Vector3 = result.position - position
	position = result.position
	velocity.y = result.velocity.y
	if absf(result.velocity.x) < absf(total.x) * 0.5:
		velocity.x = 0.0
		_dodge_velocity.x = 0.0
	if absf(result.velocity.z) < absf(total.z) * 0.5:
		velocity.z = 0.0
		_dodge_velocity.z = 0.0
	on_floor = result.on_floor
	if on_floor and not was_on_floor and fall_speed > 2.0:
		_land_dip = clampf(fall_speed * 0.012, 0.0, 0.18)
		landed.emit(fall_speed)

	var liquid_value := world.get_block(floori(position.x), floori(position.y + 0.9), floori(position.z))
	in_water = liquid_value > 0 and liquid_value != VoxelWorld.BOUNDARY and world.materials.liquid[liquid_value] == 1

	if on_floor:
		var flat := Vector2(moved.x, moved.z).length()
		_step_distance += flat
		var stride := 2.4 if sprinting else 1.9
		if _step_distance >= stride:
			_step_distance = 0.0
			footstep.emit()


func _touching_ladder() -> bool:
	## Govde bir tirmanma merdiveni hucresiyle cakisiyor mu?
	if world == null:
		return false
	var lo := Vector3(position.x - HALF_WIDTH, position.y, position.z - HALF_WIDTH)
	var hi := Vector3(position.x + HALF_WIDTH, position.y + height * 0.5, position.z + HALF_WIDTH)
	for y in range(floori(lo.y), floori(hi.y) + 1):
		for z in range(floori(lo.z), floori(hi.z - 0.001) + 1):
			for x in range(floori(lo.x), floori(hi.x - 0.001) + 1):
				var v := world.get_block(x, y, z)
				if v > 0 and v != VoxelWorld.BOUNDARY and world.materials.climbable[v] == 1:
					return true
	return false


func base_speed() -> float:
	## Varsayilan kademe: "her zaman kos" ayari ile Caps Lock gecisi.
	return RUN_SPEED if Settings.always_run != walk_mode else WALK_SPEED


func _update_crouch(wants: bool) -> void:
	if wants and not crouching:
		crouching = true
		height = CROUCH_HEIGHT
	elif not wants and crouching:
		# Tavan alcaksa kalkamayiz.
		if not VoxelBody.is_blocked(world, position, HALF_WIDTH - 0.01, STAND_HEIGHT):
			crouching = false
			height = STAND_HEIGHT


func _process(delta: float) -> void:
	var target_eye := CROUCH_EYE if crouching else STAND_EYE
	eye_height = move_toward(eye_height, target_eye, delta * 4.0)
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.8)

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if on_floor and flat_speed > 0.5:
		_bob_time += delta * flat_speed * 1.6
	else:
		_bob_time = lerpf(_bob_time, roundf(_bob_time / PI) * PI, delta * 6.0)
	var bob_amount := 0.045 * Settings.head_bob * clampf(flat_speed / RUN_SPEED, 0.0, 1.5)
	_bob_offset = Vector3(cos(_bob_time * 0.5) * bob_amount * 0.6, absf(sin(_bob_time)) * bob_amount, 0)

	_trauma = maxf(0.0, _trauma - delta * 1.6)
	var shake := _trauma * _trauma
	var t := Time.get_ticks_msec() / 1000.0
	var shake_pitch := _noise.get_noise_2d(t * 25.0, 0.0) * 0.05 * shake
	var shake_yaw := _noise.get_noise_2d(0.0, t * 25.0) * 0.05 * shake
	var shake_roll := _noise.get_noise_2d(t * 25.0, 50.0) * 0.08 * shake

	head.position = Vector3(0, eye_height - _land_dip, 0) + _bob_offset
	head.rotation = Vector3(0, yaw, 0)
	camera.rotation = Vector3(pitch + shake_pitch, shake_yaw, shake_roll)
	var target_fov := Settings.fov * (0.78 if aiming else 1.0) * (1.06 if sprinting else 1.0)
	if fov_override > 0.0:
		target_fov = fov_override        # arac kabini: modelin tasarlandigi gorus acisi
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 12.0, 0.0, 1.0))


func teleport(target: Vector3) -> void:
	position = VoxelBody.unstick(world, target, HALF_WIDTH, height)
	velocity = Vector3.ZERO


func to_dict() -> Dictionary:
	return {"position": [position.x, position.y, position.z], "yaw": yaw, "pitch": pitch,
		"stamina": stamina, "crouching": crouching, "walk_mode": walk_mode}


func load_dict(data: Dictionary) -> void:
	var p: Array = data.get("position", [position.x, position.y, position.z])
	position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	yaw = float(data.get("yaw", 0.0))
	pitch = float(data.get("pitch", 0.0))
	stamina = float(data.get("stamina", STAMINA_MAX))
	walk_mode = bool(data.get("walk_mode", false))
