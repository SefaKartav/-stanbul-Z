class_name Hitscan
extends RefCounted
## Anlik isabet (hitscan) cozucusu.
##
## TEK SIRALI VURUS LISTESI
##   Voxel hucreleri ve aktorler (zombi, NPC) ayni isin boyunca MESAFEYE
##   gore birlestirilir; ilk gecerli engel ilk islenir. "Duvarin arkasindaki
##   zombiyi vurdum" hatasi bu yuzden olusamaz.
##
## KAMERA ISINI + NAMLU ISINI
##   Nisan kameradan alinir (oyuncu ne goruyorsa oraya). Ama mermi NAMLUDAN
##   cikar: namlu ile hedef noktasi arasinda blok varsa mermi o bloga
##   carpar. Namlu duvarin icindeyse (duvara yaslanmis) mermi o duvara
##   gider. Boylece kose arkasindan kamerayla gorup namluyla vurmak olmaz.
##
## DELME
##   Delmesiz (pierce = 0) mermi ilk katı blokta durur; duvarin arkasina
##   HICBIR hasar gecmez. Delen silahta guc = pierce x 0.5; her blok
##   malzemesinin direnci kadar gucu ve orantili hasari eritir. Kirilgan
##   malzeme (cam, yaprak) kirilirsa artan hasarla mermi yoluna devam eder.
##   Aktor delme sayisi eski oyundaki `pierce` ile aynidir.

const MUZZLE_TOLERANCE := 0.08
const BLOCK_PENETRATION_PER_PIERCE := 0.5
const ACTOR_PIERCE_FALLOFF := 0.75

var world: VoxelWorld
var actors: ActorRegistry


func _init(p_world: VoxelWorld, p_actors: ActorRegistry) -> void:
	world = p_world
	actors = p_actors


func fire(eye: Vector3, direction: Vector3, muzzle: Vector3, max_range: float, damage: float,
		damage_type: String, pierce: int, faction: String, source: Object,
		damages_blocks: bool = true) -> Dictionary:
	## Tek mermi/sacma. Sonuc:
	## {impacts: [{kind, position, normal, value, destroyed, actor, killed, dealt, zone}], end: Vector3}
	direction = direction.normalized()
	var impacts: Array = []

	# 1) Namlu duvarin icinde mi? Gozden namluya dogru bir engel varsa mermi ona gider.
	var to_muzzle := muzzle - eye
	if to_muzzle.length() > 0.01:
		var blocked := VoxelRay.cast(world, eye, to_muzzle.normalized(), to_muzzle.length())
		if not blocked.is_empty():
			if damages_blocks:
				impacts.append(_hit_block(blocked, damage, damage_type, source))
			else:
				impacts.append(_impact_only(blocked))
			return {"impacts": impacts, "end": blocked.position}

	# 2) Kamera isininin gordugu ilk engeli bul (yalnizca hedef noktasi icin).
	var aim_hit := VoxelRay.cast(world, eye, direction, max_range)
	var aim_actor := actors.raycast(eye, direction, max_range, faction, source)
	var aim_distance := max_range
	if not aim_hit.is_empty():
		aim_distance = aim_hit.distance
	if not aim_actor.is_empty() and aim_actor[0].distance < aim_distance:
		aim_distance = aim_actor[0].distance
	var target := eye + direction * aim_distance

	# 3) Mermi NAMLUDAN hedef noktasina gider.
	var shot_dir := (target - muzzle)
	var shot_len := shot_dir.length()
	if shot_len < 0.05:
		shot_dir = direction
	else:
		shot_dir /= shot_len
	# Hedef noktasindan sonra da ayni dogrultuda menzil sonuna kadar devam.
	var travel := max_range

	var ray := VoxelRay.new(world, muzzle, shot_dir, travel)
	var actor_hits := actors.raycast(muzzle, shot_dir, travel, faction, source)
	var actor_index := 0
	var pierce_left := pierce
	var power := pierce * BLOCK_PENETRATION_PER_PIERCE
	var current_damage := damage
	var next_block := ray.next_hit()
	var end := muzzle + shot_dir * travel

	while current_damage > 0.5:
		var next_actor: Dictionary = actor_hits[actor_index] if actor_index < actor_hits.size() else {}
		var block_first: bool = not next_block.is_empty() and (next_actor.is_empty() or next_block.distance <= next_actor.distance)
		if block_first:
			if next_block.boundary:
				impacts.append(_impact_only(next_block))
				end = next_block.position
				break
			var impact: Dictionary
			if damages_blocks:
				impact = _hit_block(next_block, current_damage, damage_type, source)
			else:
				impact = _impact_only(next_block)
			impacts.append(impact)
			var value: int = next_block.value
			var mult: float = world.materials.damage_mult[value]
			if impact.destroyed and world.materials.fragile[value] == 1 and mult > 0.0:
				# Cam kirildi: kalan enerjiyle devam.
				current_damage = maxf(0.0, (current_damage * mult - impact.dealt) / mult)
				next_block = ray.next_hit()
				continue
			var resistance: float = world.materials.penetration[value]
			if power > resistance:
				power -= resistance
				current_damage *= clampf(1.0 - resistance * 0.6, 0.1, 1.0)
				next_block = ray.next_hit()
				continue
			end = next_block.position
			break
		elif not next_actor.is_empty():
			var actor: Node3D = next_actor.actor
			actor_index += 1
			if not is_instance_valid(actor) or not actor.is_alive():
				continue
			var point: Vector3 = muzzle + shot_dir * float(next_actor.distance)
			var result: Dictionary = actor.receive_damage(current_damage, damage_type, shot_dir, point,
				source, next_actor.get("zone", "body"))
			impacts.append({"kind": "actor", "position": point, "normal": -shot_dir, "actor": actor,
				"killed": result.get("killed", false), "dealt": result.get("dealt", 0.0),
				"zone": next_actor.get("zone", "body"), "destroyed": false, "value": 0})
			if pierce_left <= 0:
				end = point
				break
			pierce_left -= 1
			current_damage *= ACTOR_PIERCE_FALLOFF
		else:
			break
	return {"impacts": impacts, "end": end}


func _hit_block(hit: Dictionary, damage: float, _damage_type: String, _source: Object) -> Dictionary:
	var value: int = hit.value
	var mult: float = world.materials.damage_mult[value]
	var result := world.apply_damage(hit.cell, damage * mult)
	return {"kind": "block", "position": hit.position, "normal": hit.normal, "value": value,
		"cell": hit.cell, "destroyed": result.destroyed, "dealt": result.dealt,
		"origin": result.origin, "actor": null, "killed": false}


func _impact_only(hit: Dictionary) -> Dictionary:
	return {"kind": "block", "position": hit.position, "normal": hit.normal,
		"value": hit.value, "cell": hit.cell, "destroyed": false, "dealt": 0.0,
		"origin": VoxelWorld.ORIGIN_WORLD, "actor": null, "killed": false}


static func direction_with_spread(forward: Vector3, offset_degrees: Vector2) -> Vector3:
	## Ileri vektoru yatay/dikey derece kaydirmasiyla doner.
	var right := forward.cross(Vector3.UP)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(forward).normalized()
	var result := forward.rotated(up, deg_to_rad(offset_degrees.x))
	return result.rotated(right, deg_to_rad(offset_degrees.y)).normalized()
