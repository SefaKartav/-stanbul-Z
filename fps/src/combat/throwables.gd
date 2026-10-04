class_name Throwables
extends Node3D
## Firlatilabilirler (eski oyunda veride vardi, hicbir sistem kullanmiyordu).
##
##   molotof      : alan yangini -> zombilere yanma durumu; blok KIRMAZ
##   boru bombasi : patlama -> aktorlere dusen hasar + yakin bloklara malzeme
##                  carpaniyla hasar (bir SILAHTIR; kazma degildir)
##   ses tuzagi   : gecikmeli buyuk gurultu -> hordeyi baska yere ceker
##   isaret fisegi: uzun sureli isik (gece gorus)
## Istatistikler esyanin `effects` alanindan (eski piksel birimleri, Units).

const GRAVITY := 18.0
const SPEED := 17.0

var game: Node
var flying: Array = []          # [{stack_def, position, velocity, time}]
var effects_live: Array = []    # [{kind, position, time, node}]
var selected := 0


func setup(p_game: Node) -> void:
	game = p_game


func available() -> Array:
	var list: Array = []
	for stack: ItemStack in game.inventory.stacks:
		if stack.definition.has_tag("throwable") and not list.has(stack.definition.id):
			list.append(stack.definition.id)
	return list


func current() -> String:
	var list := available()
	if list.is_empty():
		return ""
	selected = posmod(selected, list.size())
	return list[selected]


func cycle() -> void:
	selected += 1
	var id := current()
	if id != "":
		game.hud.message("Firlatilacak: %s" % Content.item(id).name, Hud.ACCENT)


func throw_current() -> void:
	var id := current()
	if id == "":
		game.hud.message("Firlatacak bir sey yok (molotof, boru bombasi, ses tuzagi, fisek uret)", Hud.RED)
		return
	var stack: ItemStack = game.inventory.find(id)
	var taken: ItemStack = game.inventory.take_from_stack(stack, 1)
	if taken == null:
		return
	var look: Vector3 = game.player.look_direction()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.2, 0.12)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.55, 0.3) if id == "molotov" else Color(0.35, 0.35, 0.38)
	box.material = material
	mesh.mesh = box
	add_child(mesh)
	flying.append({"def": taken.definition, "quality": taken.quality, "position": game.player.eye_position() + look * 0.5,
		"velocity": look * SPEED + Vector3(0, 3.0, 0), "time": 0.0, "node": mesh})
	game.sfx.play_at("melee_swing", game.player.eye_position(), -4.0)


func tick(delta: float) -> void:
	for item: Dictionary in flying.duplicate():
		item.time += delta
		item.velocity.y -= GRAVITY * delta
		var step: Vector3 = item.velocity * delta
		var hit := VoxelRay.cast(game.world, item.position, step.normalized(), step.length())
		if not hit.is_empty() or item.time > 6.0:
			var at: Vector3 = hit.position + hit.normal * 0.2 if not hit.is_empty() else item.position
			flying.erase(item)
			item.node.queue_free()
			_land(item.def, item.quality, at)
			continue
		item.position += step
		item.node.position = item.position
		item.node.rotation.x += delta * 8.0
	for fx: Dictionary in effects_live.duplicate():
		fx.time -= delta
		match fx.kind:
			"fire":
				if int(fx.time * 4.0) != int((fx.time + delta) * 4.0):
					for actor: Node3D in game.actors.near(fx.position, fx.radius):
						if actor.faction() == "zombie" and actor.is_alive():
							actor.receive_damage(fx.dps * 0.25, "fire", Vector3.UP, actor.global_position, game.player, "body")
					if game.player.global_position.distance_to(fx.position) < fx.radius * 0.7:
						game.vitals.statuses.apply(StatusEffects.BURN, 2.0, 4.0)
			"lure":
				if fx.get("armed", false) == false and fx.time <= fx.fire_at:
					fx.armed = true
					game.on_noise_at(fx.position, fx.radius)
					game.sfx.play_at("zombie_scream", fx.position, 4.0)
		if fx.time <= 0.0:
			if fx.node != null and is_instance_valid(fx.node):
				fx.node.queue_free()
			effects_live.erase(fx)


static func land_kind(def: ItemDef) -> String:
	## Firlatilabilirin etkisi ETIKET ve ETKIDEN turetilir (eskiden kimlige
	## gore sabitti; yeni bombalar veriyle eklenir).
	if def.has_tag("explosive"):
		return "explode"
	if def.has_tag("incendiary"):
		return "fire"
	if def.effects.has("smoke_radius"):
		return "smoke"
	if def.effects.has("shock"):
		return "shock"
	if def.effects.has("noise_radius"):
		return "lure"
	if def.effects.has("light_radius"):
		return "light"
	return "explode" if def.effects.has("damage") else ""


func _land(def: ItemDef, quality: float, at: Vector3) -> void:
	var scale := 0.7 + 0.6 * quality / 100.0
	var e := def.effects
	match land_kind(def):
		"explode":
			explode(at, float(e.get("damage", 120.0)) * scale, Units.move_m(float(e.get("radius", 130.0))))
		"smoke":
			# Duman: menzildeki zombiler seni goremez (yalnizca ses); gorus
			# kaybi zombi baglamindaki `smoke` alanlariyla uygulanir.
			var r := Units.move_m(float(e.get("smoke_radius", 140.0)))
			var cloud := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = r
			sphere.height = r * 1.2
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.78, 0.78, 0.8, 0.55)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sphere.material = mat
			cloud.mesh = sphere
			cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.position = at + Vector3(0, r * 0.3, 0)
			add_child(cloud)
			effects_live.append({"kind": "smoke", "position": at, "radius": r, "time": float(e.get("duration", 14.0)), "node": cloud})
			game.effects.impact(at, Vector3.UP, Color(0.7, 0.7, 0.72), true)
			game.hud.message("Duman perdesi: %d sn boyunca içinde görünmezsin" % int(e.get("duration", 14.0)), Hud.ACCENT)
		"shock":
			var r := Units.move_m(float(e.get("radius", 100.0)))
			for actor: Node3D in game.actors.near(at, r):
				if actor.faction() == "zombie" and actor.is_alive():
					actor.receive_damage(float(e.get("damage", 20.0)) * scale, "shock", Vector3.UP, actor.global_position, game.player, "body")
					if actor.has_method("apply_status"):
						actor.apply_status("slow", float(e.get("shock", 4.0)), 0.7)
			game.effects.muzzle_flash(at, 2.0)
			game.sfx.play_at("impact_metal", at, 2.0)
			game.on_noise_at(at, Units.perception_m(260.0))
		"fire":
			var radius := Units.move_m(float(e.get("radius", 90.0)))
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.55, 0.2)
			light.light_energy = 2.5
			light.omni_range = radius * 2.5
			light.position = at
			add_child(light)
			effects_live.append({"kind": "fire", "position": at, "radius": radius,
				"dps": float(e.get("damage", 30.0)) * scale / 2.0, "time": float(e.get("burn_duration", 6.0)), "node": light})
			for actor: Node3D in game.actors.near(at, radius):
				if actor.faction() == "zombie" and actor.is_alive():
					actor.receive_damage(float(e.get("damage", 30.0)) * scale, "fire", Vector3.UP, actor.global_position, game.player, "body")
			game.effects.impact(at, Vector3.UP, Color(1.0, 0.5, 0.15), true)
			game.sfx.play_at("break_glass", at, 0.0)
			game.on_noise_at(at, Units.perception_m(200.0))
		"lure":
			var delay := float(e.get("delay", 3.0))
			effects_live.append({"kind": "lure", "position": at, "radius": Units.perception_m(float(e.get("noise_radius", 620.0))),
				"time": delay + 0.5, "fire_at": 0.5, "node": null})
			game.hud.message("Ses tuzagi %d sn sonra otecek" % int(delay), Hud.ACCENT)
		"light":
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.25, 0.2)
			light.light_energy = 3.0
			light.omni_range = Units.move_m(float(e.get("light_radius", 180.0))) * 1.5
			light.position = at + Vector3(0, 0.3, 0)
			add_child(light)
			effects_live.append({"kind": "light", "position": at, "time": float(e.get("duration", 25.0)), "node": light})
			game.on_noise_at(at, Units.perception_m(120.0))


func in_smoke(position: Vector3) -> bool:
	for fx: Dictionary in effects_live:
		if fx.kind == "smoke" and fx.position.distance_to(position) < float(fx.radius):
			return true
	return false


func explode(at: Vector3, damage: float, radius: float) -> void:
	## Patlama: aktorlere dusen hasar; yakin bloklara malzeme carpaniyla hasar.
	for actor: Node3D in game.actors.near(at, radius):
		if not actor.is_alive():
			continue
		var d := actor.global_position.distance_to(at)
		var falloff := clampf(1.0 - d / radius, 0.15, 1.0)
		if VoxelRay.line_clear(game.world, at, actor.global_position + Vector3(0, 1.0, 0)):
			actor.receive_damage(damage * falloff, "explosive", (actor.global_position - at).normalized(),
				actor.global_position, game.player, "body")
	var pd: float = game.player.global_position.distance_to(at)
	if pd < radius:
		game.vitals.take_hit(damage * clampf(1.0 - pd / radius, 0.1, 1.0) * 0.6, "explosive", (game.player.global_position - at).normalized())
	var block_radius := 2
	var center := VoxelWorld.cell_of(at)
	for dy in range(-block_radius, block_radius + 1):
		for dz in range(-block_radius, block_radius + 1):
			for dx in range(-block_radius, block_radius + 1):
				var cell := center + Vector3i(dx, dy, dz)
				var dist := Vector3(dx, dy, dz).length()
				if dist > block_radius + 0.5:
					continue
				var value: int = game.world.get_cell(cell)
				if value == 0 or value == VoxelWorld.BOUNDARY or game.world.materials.solid[value] == 0:
					continue
				var amount: float = damage * 2.0 * game.world.materials.damage_mult[value] * (1.0 - dist / (block_radius + 1.0))
				var result: Dictionary = game.world.apply_damage(cell, amount)
				if result.destroyed:
					game.combat.block_destroyed.emit(cell, value, result.origin)
	game.effects.impact(at, Vector3.UP, Color(0.35, 0.33, 0.3), true)
	game.effects.muzzle_flash(at, 4.0)
	game.player.add_trauma(clampf(1.2 - pd / (radius * 2.0), 0.0, 0.8))
	game.sfx.play_at("shot_shotgun", at, 8.0)
	game.on_noise_at(at, Units.perception_m(900.0))
