class_name VoxelRay
extends RefCounted
## Voxel isin yuruteci (Amanatides-Woo DDA).
##
## Isin hucreden hucreye ilerler ve ugradigi KATI hucreleri sirayla verir.
## Tek bir `next_hit()` cagrisi en yakin engeli bulur; delme mekanigi ise
## ayni yurutecle bir sonrakini ister -- boylece "ilk engel sirasi" ve
## "kalinlik" (kac hucre gecildi) dogal olarak elde edilir.
##
## Yarim bloklar (kaldirim) icin hucre icinde ayrica kutu testi yapilir:
## kaldirimin ustunden gecen mermi ona carpmis sayilmaz.
## Harita siniri ve yuklenmemis chunk (BOUNDARY) her zaman engeldir.

var world: VoxelWorld
var origin: Vector3
var direction: Vector3
var max_distance: float

var _cell: Vector3i
var _step: Vector3i
var _t_max: Vector3
var _t_delta: Vector3
var _t_enter := 0.0
var _enter_normal := Vector3.ZERO
var _done := false


func _init(p_world: VoxelWorld, p_origin: Vector3, p_direction: Vector3, p_max_distance: float) -> void:
	world = p_world
	origin = p_origin
	direction = p_direction.normalized()
	max_distance = p_max_distance
	_cell = VoxelWorld.cell_of(origin)
	_step = Vector3i(signi(int(signf(direction.x))), signi(int(signf(direction.y))), signi(int(signf(direction.z))))
	_t_delta = Vector3(
		INF if direction.x == 0.0 else absf(1.0 / direction.x),
		INF if direction.y == 0.0 else absf(1.0 / direction.y),
		INF if direction.z == 0.0 else absf(1.0 / direction.z))
	_t_max = Vector3(
		_first_boundary(origin.x, direction.x, _cell.x),
		_first_boundary(origin.y, direction.y, _cell.y),
		_first_boundary(origin.z, direction.z, _cell.z))


static func _first_boundary(position: float, dir: float, cell: int) -> float:
	if dir > 0.0:
		return (cell + 1.0 - position) / dir
	if dir < 0.0:
		return (position - cell) / -dir
	return INF


func next_hit() -> Dictionary:
	## Bir sonraki katı hucreyi dondurur; yoksa bos sozluk.
	## {cell, value, distance, position, normal, boundary}
	while not _done:
		if _t_enter > max_distance:
			_done = true
			return {}
		var cell := _cell
		var t_enter := _t_enter
		var normal := _enter_normal
		# Bir sonraki hucreye gec (sonucu donmeden once, yuruteç ilerlesin).
		var t_exit: float
		if _t_max.x < _t_max.y and _t_max.x < _t_max.z:
			t_exit = _t_max.x
			_cell.x += _step.x
			_t_max.x += _t_delta.x
			_enter_normal = Vector3(-_step.x, 0, 0)
		elif _t_max.y < _t_max.z:
			t_exit = _t_max.y
			_cell.y += _step.y
			_t_max.y += _t_delta.y
			_enter_normal = Vector3(0, -_step.y, 0)
		else:
			t_exit = _t_max.z
			_cell.z += _step.z
			_t_max.z += _t_delta.z
			_enter_normal = Vector3(0, 0, -_step.z)
		_t_enter = t_exit

		var value := world.get_block(cell.x, cell.y, cell.z)
		if value == 0:
			continue
		if value == VoxelWorld.BOUNDARY:
			_done = true
			return _hit(cell, value, t_enter, normal, true)
		if world.materials.solid[value] == 0:
			continue
		if world.materials.shape[value] == BlockMaterials.SHAPE_SLAB:
			var slab := _slab_entry(cell, t_enter, t_exit, normal)
			if slab.is_empty():
				continue
			return _hit(cell, value, slab.t, slab.normal, false)
		return _hit(cell, value, t_enter, normal, false)
	return {}


func _slab_entry(cell: Vector3i, t_enter: float, t_exit: float, normal: Vector3) -> Dictionary:
	## Isin hucrenin ALT YARISINA giriyor mu? Kaldirim 0.5 m yuksekliginde.
	var top := cell.y + 0.5
	if origin.y + direction.y * t_enter <= top:
		return {"t": t_enter, "normal": normal}
	# Ustten giriyorsa, hucreden cikmadan ust yuzeye iniyor mu?
	if direction.y >= 0.0:
		return {}
	var t_top := (top - origin.y) / direction.y
	if t_top <= t_exit:
		return {"t": t_top, "normal": Vector3.UP}
	return {}


func _hit(cell: Vector3i, value: int, distance: float, normal: Vector3, boundary: bool) -> Dictionary:
	if distance > max_distance:
		_done = true
		return {}
	return {
		"cell": cell, "value": value, "distance": distance,
		"position": origin + direction * distance,
		"normal": normal, "boundary": boundary,
	}


static func cast(p_world: VoxelWorld, p_origin: Vector3, p_direction: Vector3, p_max_distance: float) -> Dictionary:
	## Tek atimlik kullanim: en yakin katı hucre ya da bos sozluk.
	return VoxelRay.new(p_world, p_origin, p_direction, p_max_distance).next_hit()


static func line_clear(p_world: VoxelWorld, from: Vector3, to: Vector3) -> bool:
	## Iki nokta arasinda katı engel yok mu? (gorus, namlu kontrolu)
	var offset := to - from
	var length := offset.length()
	if length < 0.0001:
		return true
	return cast(p_world, from, offset / length, length).is_empty()
