class_name Abilities
extends RefCounted
## Ozel yetenekler (Python: powers/*). Veri data/powers/powers.json'dan.
##
## FPS uyarlamasi: eski "yuvarlanma" imlec yonunde donerek atiliyordu.
## Birinci sahiste ekrani ZORLA dondurmek mide bulandirir; ayni islevi
## (kusatmadan kacis) goren kisa bir KACINMA atilmasi kullanilir: kamera
## sabit, govde hareket yonune (yoksa bakis yonune) firlar, duvardan gecmez.
## Itekleme yalnizca DUSMANLARI iter; cevre blogunu asla kirmaz.
##
## Rutbe olcekleri eski oyunla ayni: hasar +%28, yaricap +%14, bekleme -%9.

const ACTIONS := {
	"ability_dodge": "combat_roll", "ability_shove": "shove", "ability_first_aid": "first_aid",
	"ability_adrenaline": "adrenaline", "ability_distraction": "distraction",
}

var game: Node
var cooldowns: Dictionary = {}
var casting: Dictionary = {}      # suren ilk yardim: {power, left}


func _init(p_game: Node) -> void:
	game = p_game


func rank(power_id: String) -> int:
	return game.progression.rank_of(power_id)


func cooldown_of(power: Dictionary) -> float:
	return float(power.cooldown) * (1.0 - 0.09 * (rank(power.id) - 1))


func tick(delta: float) -> void:
	for key: String in cooldowns.keys():
		cooldowns[key] = maxf(0.0, cooldowns[key] - delta)
	if not casting.is_empty():
		casting.left -= delta
		if casting.left <= 0.0:
			_finish_heal(casting.power)
			casting = {}


func interrupt() -> void:
	if not casting.is_empty():
		casting = {}
		game.hud.message("Ilk yardim yarida kesildi", Hud.RED)


func handle_input() -> void:
	for action: String in ACTIONS:
		if Input.is_action_just_pressed(action):
			use(ACTIONS[action])


func use(power_id: String) -> void:
	var power: Dictionary = Content.powers.get(power_id, {})
	if power.is_empty():
		return
	if float(cooldowns.get(power_id, 0.0)) > 0.0:
		game.hud.message("%s hazir degil (%.0f sn)" % [power.name, cooldowns[power_id]], Hud.MUTED_COLOR)
		return
	if not game.vitals.spend_energy(float(power.cost)):
		game.hud.message("%s icin enerji yetmiyor" % power.name, Hud.RED)
		return
	cooldowns[power_id] = cooldown_of(power)
	var r := rank(power_id)
	match str(power.strategy):
		"dash":
			var distance := Units.move_m(float(power.range)) * (1.0 + 0.1 * (r - 1))
			var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			var direction := Basis(Vector3.UP, game.player.yaw) * Vector3(input.x, 0, input.y)
			game.player.dodge(direction, distance / 0.25, 0.25)
			_noise(power)
		"shockwave":
			var radius := Units.move_m(float(power.radius)) * (1.0 + 0.14 * (r - 1)) + 0.6
			var damage := float(power.damage) * (1.0 + 0.28 * (r - 1))
			var origin: Vector3 = game.player.global_position
			for actor: Node3D in game.actors.near(origin, radius):
				if actor.faction() != "zombie" or not actor.is_alive():
					continue
				var push := actor.global_position - origin
				push.y = 0.0
				push = push.normalized() if push.length() > 0.01 else Vector3.FORWARD
				actor.receive_damage(damage, "physical", push, actor.global_position, game.player, "body")
				if actor is Zombie:
					var z := actor as Zombie
					z.velocity += push * Units.move_m(float(power.knockback)) * (1.0 - z.def.knockback_resist) * 0.5
					z.stagger_timer = maxf(z.stagger_timer, 0.6)
					z.state = Zombie.State.STAGGER
			game.player.add_trauma(float(power.shake))
			game.sfx.play_at("melee_hit", origin, 0.0)
			_noise(power)
		"heal":
			casting = {"power": power, "left": float(power.cast_time)}
			game.hud.message("Yarani sariyorsun... (hasar alirsan kesilir)", Hud.ACCENT)
		"self_buff":
			for status: Dictionary in power.self_status:
				game.vitals.statuses.apply(str(status.kind), float(status.duration) * (1.0 + 0.15 * (r - 1)),
					float(status.magnitude))
			game.hud.message(power.name + "!", Hud.GREEN)
		"lure":
			var eye: Vector3 = game.player.eye_position()
			var look: Vector3 = game.player.look_direction()
			var reach := Units.move_m(float(power.range)) * (1.0 + 0.12 * (r - 1)) * 2.0
			var hit := VoxelRay.cast(game.world, eye, look, reach)
			var point: Vector3 = hit.position if not hit.is_empty() else eye + look * reach
			var radius := Units.perception_m(float(power.noise_radius)) * (1.0 + 0.18 * (r - 1))
			game.on_noise_at(point, radius)
			game.sfx.play_at("impact_metal", point, 2.0)
			game.hud.message("Ses %d m oteye firlatildi" % int(eye.distance_to(point)), Hud.ACCENT)


func _finish_heal(power: Dictionary) -> void:
	var r := rank(power.id)
	var amount: float = float(power.damage) * (1.0 + 0.28 * (r - 1)) * game.skills.multiplier("healing")
	game.vitals.heal(amount, [StatusEffects.BLEED, StatusEffects.INFECTION])
	game.progression.count("healed")
	game.hud.message("Ilk yardim: +%d can, kanama ve enfeksiyon kesildi" % int(amount), Hud.GREEN)


func _noise(power: Dictionary) -> void:
	if float(power.noise_radius) > 0.0:
		game.on_noise_at(game.player.global_position, Units.perception_m(float(power.noise_radius)))


func status_text() -> String:
	var parts := PackedStringArray()
	for action: String in ACTIONS:
		var id: String = ACTIONS[action]
		var left := float(cooldowns.get(id, 0.0))
		parts.append("%s %s" % [Settings.binding_label(action), "hazir" if left <= 0.0 else "%.0f" % left])
	return "  ".join(parts)


func to_dict() -> Dictionary:
	return {"cooldowns": cooldowns.duplicate()}


func load_dict(data: Dictionary) -> void:
	cooldowns = data.get("cooldowns", {}).duplicate()
