class_name BridgeDecor
extends Node3D
## 15 Temmuz Sehitler Koprusu'nun voxel OLMAYAN parcasi: ana halatlar,
## dikey askilar ve gorus yaricapinin otesindeki sade siluet.
##
## NEDEN VOXEL DEGIL?
##   Yarim metrelik halat 1 m'lik kuplerle cizilince merdiven gibi
##   basamaklanir ve yakindan kirik bir kafes gibi gorunur (ilk surumde
##   denendi). Halatlar tabliyenin DISINDA, korkulugun otesindedir: uzerinde
##   yurunmez, arkasina saklanilmaz; vurus ve yikim kuralini etkilemez.
##   Kule ve tabliye voxel'dir (vurulur, delinir, onarilir).
##
## UZAK GORUNUS (LOD)
##   Voxel dunya yalnizca gorus yaricapi kadar uretilir ve kenari sisle
##   gizlenir. Kopru sehrin simgesidir: Kadikoy'den, Uskudar'dan ufukta
##   gorunmeli. Bu yuzden yaricapin OTESINDE sisten etkilenmeyen, rengi sis
##   rengine yakin (hava perspektifi) sade bir siluet cizilir. Kopru 30 m'lik
##   parcalara bolunur; her parcanin yakin (halat, aski) ve uzak (siluet)
##   hali kendi gorunurluk araligiyla birbirine devredilir.

const PIECE := 30.0
const CABLE_WIDTH := 0.55
const HANGER_WIDTH := 0.14
const FAR_WIDTH := 1.4                 # uzakta piksel altina dusmesin

var city: CityGenerator
var near_material: StandardMaterial3D
var far_material: StandardMaterial3D
var _near: Array[GeometryInstance3D] = []
var _far: Array[GeometryInstance3D] = []
var _box := BoxMesh.new()


func setup(p_city: CityGenerator, reach: float) -> void:
	city = p_city
	_box.size = Vector3.ONE
	near_material = StandardMaterial3D.new()
	near_material.albedo_color = Color(0.34, 0.36, 0.39)
	near_material.metallic = 0.5
	near_material.roughness = 0.5
	far_material = StandardMaterial3D.new()
	far_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	far_material.disable_fog = true
	far_material.albedo_color = Color(0.58, 0.6, 0.64)
	for b: Dictionary in city.bridges:
		_build(b)
	set_reach(reach)


func set_reach(reach: float) -> void:
	## Gorus yaricapi (m) degisince devir mesafeleri de degisir.
	for node in _near:
		node.visibility_range_end = reach * 1.05
	for node in _far:
		node.visibility_range_begin = reach * 0.8


func set_sky(fog_color: Color) -> void:
	## Uzak siluetin rengi sis rengine yakin: gece koyu, gunduz soluk mavi-gri.
	far_material.albedo_color = fog_color.lerp(Color(0.2, 0.22, 0.26), 0.3)


func piece_count() -> int:
	return _near.size()


func _build(b: Dictionary) -> void:
	var pieces := ceili(b.length / PIECE)
	for k in pieces:
		var s0 := k * PIECE
		var s1: float = minf(b.length, s0 + PIECE)
		var middle := city.bridge_point(b, (s0 + s1) * 0.5)
		var origin := Vector3(middle.x, city.deck_half(b, (s0 + s1) * 0.5) * 0.5, middle.y)
		var near: Array[Transform3D] = []
		var far: Array[Transform3D] = []
		# Ana halatlar: 5 m'lik dogru parcalarla parabol.
		var s := s0
		while s < s1 - 0.01:
			var e: float = minf(s1, s + 5.0)
			for side: float in [-1.0, 1.0]:
				var a := _cable_point(b, s, side)
				var c := _cable_point(b, e, side)
				near.append(_beam(a, c, CABLE_WIDTH, origin))
				far.append(_beam(a, c, FAR_WIDTH, origin))
			s = e
		# Dikey askilar: halattan tabliye kenarina.
		var h := ceilf(s0 / CityGenerator.HANGER_EVERY) * CityGenerator.HANGER_EVERY
		while h < s1:
			for side: float in [-1.0, 1.0]:
				var top := _cable_point(b, h, side)
				var bottom := Vector3(top.x, city.deck_half(b, h) * 0.5 + 0.2, top.z)
				if top.y - bottom.y > 1.0:
					near.append(_beam(bottom, top, HANGER_WIDTH, origin))
			h += CityGenerator.HANGER_EVERY
		# Uzak siluet: tabliye kutusu ve kuleler.
		var deck_a := _deck_point(b, s0)
		var deck_b := _deck_point(b, s1)
		far.append(_slab(deck_a, deck_b, b.half * 2.0, 2.5, origin))
		for t: float in [b.t1, b.t2]:
			if t >= s0 and t < s1:
				_far_tower(b, t, origin, far)
		_near.append(_instance(near, near_material, origin, true))
		_far.append(_instance(far, far_material, origin, false))


func _side(b: Dictionary, s: float) -> Vector2:
	var ahead: Vector2 = city.bridge_point(b, minf(b.length, s + 1.0)) - city.bridge_point(b, maxf(0.0, s - 1.0))
	return ahead.normalized().orthogonal()


func _cable_point(b: Dictionary, s: float, side: float) -> Vector3:
	var p: Vector2 = city.bridge_point(b, s) + _side(b, s) * side * (b.half + 0.6)
	return Vector3(p.x, city.cable_y(b, s) + 0.5, p.y)


func _deck_point(b: Dictionary, s: float) -> Vector3:
	var p := city.bridge_point(b, s)
	# Ust yuzu asfaltin 0.25 m altinda: devir bandinda voxel tabliyeyle cakismasin.
	return Vector3(p.x, city.deck_half(b, s) * 0.5 - 1.5, p.y)


func _far_tower(b: Dictionary, t: float, origin: Vector3, out: Array[Transform3D]) -> void:
	var base := city.bridge_point(b, t)
	var side := _side(b, t)
	var ahead := side.orthogonal()
	var top := float(CityGenerator.TOWER_TOP) + 1.0
	var bottom := float(CityGenerator.SEA_FLOOR)
	for sign: float in [-1.0, 1.0]:
		var leg: Vector2 = base + side * sign * (b.half + 1.5)
		out.append(_oriented_box(Vector3(leg.x, (top + bottom) * 0.5, leg.y), side, ahead,
			Vector3(3.0, top - bottom, 5.0), origin))
	out.append(_oriented_box(Vector3(base.x, top - 2.0, base.y), side, ahead,
		Vector3(b.half * 2.0 + 6.0, 4.0, 3.0), origin))


func _beam(a: Vector3, c: Vector3, width: float, origin: Vector3) -> Transform3D:
	## a'dan c'ye uzanan ince kutu (birim kupun olceklenmis hali).
	var direction := c - a
	var length := direction.length()
	var forward := direction / maxf(1e-4, length)
	var up := Vector3.UP if absf(forward.y) < 0.98 else Vector3.RIGHT
	var basis := Basis.looking_at(forward, up)
	basis.x *= width
	basis.y *= width
	basis.z *= length
	return Transform3D(basis, (a + c) * 0.5 - origin)


func _slab(a: Vector3, c: Vector3, width: float, thickness: float, origin: Vector3) -> Transform3D:
	var direction := c - a
	var length := direction.length()
	var basis := Basis.looking_at(direction / maxf(1e-4, length), Vector3.UP)
	basis.x *= width
	basis.y *= thickness
	basis.z *= length
	return Transform3D(basis, (a + c) * 0.5 - origin)


func _oriented_box(center: Vector3, side: Vector2, ahead: Vector2, size: Vector3, origin: Vector3) -> Transform3D:
	var basis := Basis(Vector3(side.x, 0, side.y) * size.x, Vector3.UP * size.y, Vector3(ahead.x, 0, ahead.y) * size.z)
	return Transform3D(basis, center - origin)


func _instance(transforms: Array[Transform3D], material: Material, origin: Vector3,
		shadows: bool) -> GeometryInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _box
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = origin
	add_child(node)
	return node
