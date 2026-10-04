class_name Effects
extends Node3D
## Anlik gorsel efektler: vurus kivilcimi/tozu, blok enkaz kupleri, namlu
## alevi, mermi izi, kan. Hepsi havuzlanir; yogun catismada her mermide
## yeni dugum yaratmak kare suresini bozardi.
##
## Belgenin kurali: kirilan blok HEMEN kaybolur; buradaki kupler yalnizca
## kisa omurlu gorsel parcaciktir, fizik enkazi ya da yikim klibi degildir.

const PARTICLE_POOL := 24
const TRACER_POOL := 16

var _particles: Array = []
var _particle_index := 0
var _tracers: Array = []
var _tracer_index := 0
var _flash_light: OmniLight3D
var _flash_time := 0.0
var _cube_mesh: BoxMesh
var _tracer_material: StandardMaterial3D


func _ready() -> void:
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3(0.09, 0.09, 0.09)
	var cube_material := StandardMaterial3D.new()
	cube_material.vertex_color_use_as_albedo = true
	cube_material.roughness = 0.95
	_cube_mesh.material = cube_material
	for i in PARTICLE_POOL:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.95
		p.lifetime = 0.9
		p.mesh = _cube_mesh
		p.direction = Vector3.UP
		p.spread = 55.0
		p.gravity = Vector3(0, -14, 0)
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 4.0
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.3
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.local_coords = false
		add_child(p)
		_particles.append(p)
	_tracer_material = StandardMaterial3D.new()
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.albedo_color = Color(1.0, 0.9, 0.6, 0.8)
	_tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_material.emission_enabled = true
	_tracer_material.emission = Color(1.0, 0.85, 0.5)
	for i in TRACER_POOL:
		var tracer := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.018, 0.018, 1.0)
		box.material = _tracer_material
		tracer.mesh = box
		tracer.visible = false
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tracer.set_meta("life", 0.0)
		add_child(tracer)
		_tracers.append(tracer)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.78, 0.45)
	_flash_light.omni_range = 7.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)


func _next_particles() -> CPUParticles3D:
	var p: CPUParticles3D = _particles[_particle_index]
	_particle_index = (_particle_index + 1) % PARTICLE_POOL
	p.restart()
	return p


func impact(position: Vector3, normal: Vector3, color: Color, destroyed: bool) -> void:
	var p := _next_particles()
	p.global_position = position + normal * 0.03
	p.direction = normal if normal != Vector3.ZERO else Vector3.UP
	p.amount = 18 if destroyed else 6
	p.spread = 70.0 if destroyed else 40.0
	p.initial_velocity_min = 1.0 if destroyed else 1.8
	p.initial_velocity_max = 4.5 if destroyed else 3.2
	p.lifetime = 1.1 if destroyed else 0.45
	p.scale_amount_min = 0.8 if destroyed else 0.35
	p.scale_amount_max = 2.2 if destroyed else 0.8
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, color.lightened(0.1))
	ramp.set_color(1, color.darkened(0.3))
	p.color_ramp = ramp
	p.emitting = true


func blood(position: Vector3, direction: Vector3) -> void:
	var p := _next_particles()
	p.global_position = position
	p.direction = direction
	p.amount = 10
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.lifetime = 0.5
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	p.color = Color(0.42, 0.06, 0.05)
	p.color_ramp = null
	p.emitting = true


func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 1.5:
		return
	var node: MeshInstance3D = _tracers[_tracer_index]
	_tracer_index = (_tracer_index + 1) % TRACER_POOL
	var mid := from.lerp(to, 0.5)
	node.visible = true
	node.global_position = mid
	node.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	node.scale = Vector3(1, 1, length)
	node.set_meta("life", 0.05)


func muzzle_flash(position: Vector3, strength: float) -> void:
	_flash_light.global_position = position
	_flash_light.light_energy = 2.5 * strength
	_flash_time = 0.05


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_flash_light.light_energy = 0.0
	for node: MeshInstance3D in _tracers:
		if not node.visible:
			continue
		var life: float = node.get_meta("life") - delta
		node.set_meta("life", life)
		if life <= 0.0:
			node.visible = false
