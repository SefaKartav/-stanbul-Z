class_name TargetDummy
extends Node3D
## Atis poligonu hedefi: gercek bir aktor (ActorRegistry arayuzu). Hasar
## alir, gosterir, olurse yeniden kalkar. Testlerde "duvarin arkasindaki
## hedef" olarak da kullanilir.

signal damaged(amount: float, zone: String)

const HALF_WIDTH := 0.3
const HEIGHT := 1.8
const HEAD_HEIGHT := 0.3

var max_health := 100.0
var health := 100.0
var armor := 0.0
var total_damage := 0.0
var hits := 0
var respawn_time := 3.0
var _dead_timer := 0.0
var _flash := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	var model := BoxMesh.new()
	model.size = Vector3(HALF_WIDTH * 2.0, HEIGHT, HALF_WIDTH * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.62, 0.42)
	model.material = material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = model
	_mesh.position.y = HEIGHT * 0.5
	add_child(_mesh)


func faction() -> String:
	return "zombie"


func is_alive() -> bool:
	return health > 0.0


func hit_test(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var p := global_position
	var head_min := Vector3(p.x - 0.22, p.y + HEIGHT - HEAD_HEIGHT, p.z - 0.22)
	var head_max := Vector3(p.x + 0.22, p.y + HEIGHT, p.z + 0.22)
	var head := ActorRegistry.ray_box(origin, direction, head_min, head_max, max_distance)
	var body := ActorRegistry.ray_box(origin, direction,
		Vector3(p.x - HALF_WIDTH, p.y, p.z - HALF_WIDTH),
		Vector3(p.x + HALF_WIDTH, p.y + HEIGHT - HEAD_HEIGHT, p.z + HALF_WIDTH), max_distance)
	if head >= 0.0 and (body < 0.0 or head <= body):
		return {"distance": head, "zone": "head"}
	if body >= 0.0:
		return {"distance": body, "zone": "body"}
	return {}


func receive_damage(amount: float, _damage_type: String, _direction: Vector3, _point: Vector3,
		_source: Object, zone: String) -> Dictionary:
	if health <= 0.0:
		return {"dealt": 0.0, "killed": false}
	var dealt := amount * (2.0 if zone == "head" else 1.0)
	health -= dealt
	total_damage += dealt
	hits += 1
	_flash = 1.0
	damaged.emit(dealt, zone)
	var killed := health <= 0.0
	if killed:
		_dead_timer = respawn_time
	return {"dealt": dealt, "killed": killed}


func _process(delta: float) -> void:
	if _dead_timer > 0.0:
		_dead_timer -= delta
		_mesh.rotation.x = lerpf(_mesh.rotation.x, -PI * 0.5, delta * 8.0)
		if _dead_timer <= 0.0:
			health = max_health
			_mesh.rotation.x = 0.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		var material: StandardMaterial3D = (_mesh.mesh as BoxMesh).material
		material.albedo_color = Color(0.72, 0.62, 0.42).lerp(Color(1, 0.3, 0.2), _flash)
