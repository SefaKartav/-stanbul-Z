class_name WeaponView
extends Node3D
## Birinci sahis silah ve kol gorunumu.
##
## KATMAN AYRIMI: silah ve kollar 2. render katmanindadir ve ayri bir
## ust kamera (ViewModelLayer) tarafindan cizilir. Duvara yaslaninca silahin
## duvara gomulmesi boylece gorsel olarak olmaz -- ama silah DUNYADA gercek
## konumunda durur ve namlu ucu Hitscan'in namlu kontrolune gercek dunya
## konumuyla girer (bkz. Hitscan). Gorsel hile mekanik hile degildir.
##
## Paketteki silahlarin ates/doldurma animasyonu yoktur (README); hareketler
## burada prosedurel uretilir: tepme yayi, doldurma egilmesi, sarjor/pompa
## parcasinin kaymasi, kusanma, sallanti, nisan alma.

const VIEW_LAYER := 2
const HIP := Vector3(0.17, -0.19, -0.46)
const HIP_YAW := 0.1                 # namlu nisangaha hafifce donuk
const EQUIP_TIME := 0.32

var model: Node3D
var arms: Node3D
var model_id := ""
var weapon: WeaponDef
var aim_blend := 0.0
var muzzle_local := Vector3(0, 0.05, -0.25)
var sight_height := 0.08

var _kick := 0.0
var _kick_velocity := 0.0
var _equip_time := 0.0
var _reload_progress := -1.0
var _swing := -1.0
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _bob_phase := 0.0
var _magazine: Node3D
var _magazine_rest := Vector3.ZERO
var _pump: Node3D
var _pump_rest := Vector3.ZERO
var _pump_kick := 0.0


func _ready() -> void:
	arms = AssetLibrary.instantiate("fps_arms")
	_set_layer(arms)
	add_child(arms)


func show_weapon(p_weapon: WeaponDef) -> void:
	weapon = p_weapon
	if model != null:
		model.queue_free()
		model = null
	_magazine = null
	_pump = null
	if weapon == null:
		visible = false
		return
	visible = true
	model_id = AssetLibrary.weapon_model_id(weapon)
	if model_id != "":
		model = AssetLibrary.instantiate(model_id)
		var box := AssetLibrary.bounds(model_id)
		muzzle_local = Vector3(0, box.position.y + box.size.y * 0.72, box.position.z)
		sight_height = box.position.y + box.size.y
		_magazine = _find_part(model, "magazine")
		_pump = _find_part(model, "pump")
	else:
		model = _melee_model(weapon.id)
		muzzle_local = Vector3(0, 0.0, -0.6)
		sight_height = 0.1
	if _magazine != null:
		_magazine_rest = _magazine.position
	if _pump != null:
		_pump_rest = _pump.position
	_set_layer(model)
	add_child(model)
	# Kol modelinde eller -Z ucundadir (manifest: z -0.175); elleri kabzaya
	# getirmek icin kollar o kadar geri kaydirilir, omuzlar kameranin arkasinda kalir.
	arms.position = Vector3(0, 0.0, 0.175) if model_id != "" else Vector3(0.05, 0.08, 0.2)
	_equip_time = EQUIP_TIME
	_reload_progress = -1.0


func _find_part(root: Node, part: String) -> Node3D:
	for child in root.get_children():
		if child is Node3D and String(child.name).to_lower().contains(part):
			return child
		var found := _find_part(child, part)
		if found != null:
			return found
	return null


func _set_layer(node: Node) -> void:
	if node is VisualInstance3D:
		var visual := node as VisualInstance3D
		visual.layers = 1 << (VIEW_LAYER - 1)
		if visual is GeometryInstance3D:
			(visual as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_set_layer(child)


func _melee_model(weapon_id: String) -> Node3D:
	## Pakette yakin dovus modeli yok; kutulardan sade bir model.
	var root := Node3D.new()
	var parts: Array = []
	match weapon_id:
		"melee_knife":
			parts = [[Vector3(0.03, 0.035, 0.12), Vector3(0, 0, 0), Color(0.15, 0.12, 0.1)],
				[Vector3(0.012, 0.03, 0.2), Vector3(0, 0.005, -0.16), Color(0.75, 0.76, 0.78)]]
		"melee_axe":
			parts = [[Vector3(0.04, 0.04, 0.62), Vector3(0, 0, -0.18), Color(0.45, 0.3, 0.18)],
				[Vector3(0.03, 0.2, 0.14), Vector3(0, 0.08, -0.46), Color(0.7, 0.12, 0.1)]]
		"melee_sledge":
			parts = [[Vector3(0.045, 0.045, 0.7), Vector3(0, 0, -0.2), Color(0.45, 0.3, 0.18)],
				[Vector3(0.12, 0.12, 0.2), Vector3(0, 0, -0.56), Color(0.3, 0.3, 0.32)]]
		_:
			# Uretilen alet ve silahlar: kimlikteki anahtar kelimeye gore sap + bas.
			var handle := Color(0.45, 0.3, 0.18)
			var steel := Color(0.62, 0.63, 0.66)
			var stone := Color(0.5, 0.48, 0.44)
			var head_color := stone if weapon_id.contains("stone") else steel
			if weapon_id.contains("pick"):
				parts = [[Vector3(0.04, 0.04, 0.62), Vector3(0, 0, -0.2), handle],
					[Vector3(0.03, 0.34, 0.05), Vector3(0, 0.02, -0.48), head_color]]
			elif weapon_id.contains("axe") or weapon_id.contains("hatchet"):
				parts = [[Vector3(0.04, 0.04, 0.6), Vector3(0, 0, -0.18), handle],
					[Vector3(0.03, 0.18, 0.12), Vector3(0, 0.07, -0.44), head_color]]
			elif weapon_id.contains("shovel"):
				parts = [[Vector3(0.035, 0.035, 0.7), Vector3(0, 0, -0.22), handle],
					[Vector3(0.18, 0.02, 0.22), Vector3(0, 0, -0.62), head_color]]
			elif weapon_id.contains("spear"):
				parts = [[Vector3(0.03, 0.03, 1.1), Vector3(0, 0, -0.35), handle],
					[Vector3(0.02, 0.05, 0.18), Vector3(0, 0, -0.98), steel]]
			elif weapon_id.contains("machete") or weapon_id.contains("blade") or weapon_id.contains("yatagan") \
					or weapon_id.contains("cleaver") or weapon_id.contains("sickle"):
				parts = [[Vector3(0.035, 0.04, 0.14), Vector3(0, 0, 0), Color(0.15, 0.12, 0.1)],
					[Vector3(0.012, 0.06, 0.46), Vector3(0, 0.01, -0.3), steel]]
			elif weapon_id.contains("bat") or weapon_id.contains("club"):
				parts = [[Vector3(0.05, 0.05, 0.72), Vector3(0, 0, -0.22), Color(0.55, 0.4, 0.24)]]
				if weapon_id.contains("nail") or weapon_id.contains("spiked"):
					parts.append([Vector3(0.1, 0.1, 0.16), Vector3(0, 0, -0.5), Color(0.5, 0.5, 0.52)])
			elif weapon_id.contains("hammer") or weapon_id.contains("mace") or weapon_id.contains("wrench"):
				parts = [[Vector3(0.04, 0.04, 0.5), Vector3(0, 0, -0.15), handle],
					[Vector3(0.1, 0.1, 0.14), Vector3(0, 0, -0.42), steel]]
			else:
				parts = [[Vector3(0.045, 0.045, 0.7), Vector3(0, 0, -0.2), Color(0.42, 0.42, 0.44)]]
	for part: Array in parts:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		var material := StandardMaterial3D.new()
		material.albedo_color = part[2]
		material.roughness = 0.8
		box.material = material
		mesh.mesh = box
		mesh.position = part[1]
		root.add_child(mesh)
	root.rotation_degrees = Vector3(18, -8, 0)
	return root


# --- olaylar ---
func fire_kick(strength: float) -> void:
	_kick_velocity += 6.0 + strength * 5.0
	_pump_kick = 1.0 if _pump != null else 0.0


func begin_reload() -> void:
	_reload_progress = 0.0


func set_reload_progress(progress: float) -> void:
	_reload_progress = progress


func end_reload() -> void:
	_reload_progress = -1.0


func swing() -> void:
	_swing = 0.0


func add_sway(mouse_delta: Vector2) -> void:
	_sway_target += mouse_delta * 0.0006


func muzzle_global() -> Vector3:
	if model == null:
		return global_position
	return model.global_transform * muzzle_local


# --- kare guncellemesi ---
func update_view(delta: float, aiming: bool, move_speed: float, on_floor: bool) -> void:
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta * 7.0)
	# Tepme: kritik sonumlu yay.
	_kick_velocity += (-_kick * 180.0 - _kick_velocity * 22.0) * delta
	_kick += _kick_velocity * delta
	_equip_time = maxf(0.0, _equip_time - delta)
	_sway_target = _sway_target.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	_sway = _sway.lerp(_sway_target, clampf(delta * 10.0, 0.0, 1.0))
	if on_floor and move_speed > 0.5:
		_bob_phase += delta * move_speed * 1.7
	var bob := Vector3(cos(_bob_phase) * 0.012, absf(sin(_bob_phase)) * 0.014, 0) \
		* clampf(move_speed / 4.0, 0.0, 1.5) * (1.0 - aim_blend * 0.8) * Settings.head_bob

	var aim_position := Vector3(0.0, -sight_height - 0.012, -0.3)
	var target := HIP.lerp(aim_position, aim_blend) + bob
	var rotation_target := Vector3(0, HIP_YAW * (1.0 - aim_blend), 0)
	target.z += _kick * 0.05
	rotation_target.x += _kick * 0.12
	# Kusanma: asagidan yukari kalkis.
	var equip := _equip_time / EQUIP_TIME
	target.y -= equip * equip * 0.35
	rotation_target.x -= equip * 0.6
	# Doldurma: asagi in, yana yatir, sarjoru cikar-tak.
	if _reload_progress >= 0.0:
		var dip := sin(clampf(_reload_progress, 0.0, 1.0) * PI)
		target.y -= dip * 0.1
		rotation_target.z += dip * 0.5
		rotation_target.x += dip * 0.25
		if _magazine != null:
			var out := sin(clampf(_reload_progress * 1.25, 0.0, 1.0) * PI)
			_magazine.position = _magazine_rest + Vector3(0, -0.22 * out, 0.04 * out)
	elif _magazine != null:
		_magazine.position = _magazine_rest
	if _pump != null:
		_pump_kick = move_toward(_pump_kick, 0.0, delta * 3.0)
		_pump.position = _pump_rest + Vector3(0, 0, 0.09 * sin(_pump_kick * PI))
	# Yakin dovus savurusu.
	if _swing >= 0.0:
		_swing += delta * 3.2
		var s := sin(clampf(_swing, 0.0, 1.0) * PI)
		rotation_target += Vector3(-0.9 * s, 0.6 * s, -0.4 * s)
		target += Vector3(-0.12 * s, 0.05 * s, -0.12 * s)
		if _swing >= 1.0:
			_swing = -1.0
	rotation_target.y += -_sway.x
	rotation_target.x += -_sway.y
	position = position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	rotation = rotation.lerp(rotation_target, clampf(delta * 14.0, 0.0, 1.0))


class ViewModelLayer:
	extends CanvasLayer
	## Silahi dunyanin USTUNE cizen ikinci kamera, KENDI kucuk dunyasinda.
	##
	## Ayri dunya bilincli: paylasilan dunyada gunes golgesi bu kamera icin
	## bir kez daha hesaplanir ve golge maliyeti ikiye katlanirdi. Bu kamera
	## her kare ana kameranin DUNYA donusumunu kopyalar; bu yuzden silahin bu
	## dunyadaki global konumu, ana dunyadaki konumuyla ayni sayilardir ve
	## namlu ucu Hitscan'e dogrudan verilebilir.
	var viewport: SubViewport
	var camera: Camera3D
	var follow: Camera3D
	var light: DirectionalLight3D

	func setup(main_camera: Camera3D) -> void:
		layer = -1
		follow = main_camera
		var container := SubViewportContainer.new()
		container.stretch = true
		container.set_anchors_preset(Control.PRESET_FULL_RECT)
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(container)
		viewport = SubViewport.new()
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.positional_shadow_atlas_size = 0
		container.add_child(viewport)
		camera = Camera3D.new()
		camera.near = 0.01
		camera.far = 5.0
		camera.fov = 62.0
		light = DirectionalLight3D.new()
		light.shadow_enabled = false
		light.light_energy = 1.0
		light.rotation_degrees = Vector3(-50, -30, 0)
		viewport.add_child(light)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.background_color = Color(0, 0, 0, 0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.64, 0.68)
		env.ambient_light_energy = 0.8
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		camera.environment = env
		viewport.add_child(camera)
		camera.current = true

	func attach(view: Node3D) -> void:
		camera.add_child(view)

	func sync_lighting(sun: DirectionalLight3D, ambient: float) -> void:
		## Silah gunes yonu ve gece karanligiyla uyumlu aydinlansin.
		light.global_basis = sun.global_basis
		light.light_energy = sun.light_energy * 0.9 if sun.visible else 0.0
		light.light_color = sun.light_color
		camera.environment.ambient_light_energy = clampf(ambient, 0.15, 0.9)

	func _process(_delta: float) -> void:
		if follow != null and is_instance_valid(follow):
			camera.global_transform = follow.global_transform
			camera.fov = 62.0
