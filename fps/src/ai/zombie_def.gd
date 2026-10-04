class_name ZombieDef
extends RefCounted
## Zombi tanimi (veri). Birimler eski dunya pikseli; bkz. Units.
## (Python: game/ai/brain.py ZombieDef)

const FIELDS := [
	"id", "name", "health", "armor", "speed", "sprint_speed", "acceleration",
	"damage", "attack_range", "attack_windup", "attack_cooldown",
	"sight_radius", "sight_angle", "hearing_radius", "investigate_time",
	"knockback_resist", "sprite", "weight", "stagger_time", "resistances",
	"bite_status", "bite_duration", "bite_magnitude",
	"scream_radius", "scream_interval",
]

# Eski sprite kimligi -> asset paketindeki model. Birden fazla tip ayni
# modeli paylasir; olcek ve renk farki `ZombieVisual` icinde verilir.
const MODEL_BY_SPRITE := {
	"actors/zombie": "zombie_walker",
	"actors/zombie_runner": "zombie_runner",
	"actors/zombie_brute": "zombie_brute",
	"actors/zombie_spitter": "zombie_worker",
}
# Tip bazli ozel model esleme (sprite'tan once bakilir).
## 600 paket (25 Eylul 2026): tipe ozgu yeni govdeler; siluet tipi soyler.
const MODEL_BY_ID := {
	"worker": "zombie_worker",
	"armored": "iz2_zombie_riot_guard",
	"spitter": "iz2_zombie_spitter",
	"crawler": "iz2_zombie_crawler",
	"screamer": "iz2_zombie_screecher",
	"stalker": "iz2_zombie_climber",
	"infected": "iz2_zombie_hazmat",
	"ripper": "iz2_zombie_firefighter",
	"bloated": "iz2_zombie_cook",
}
# Siradan yuruyenlerde cesitlilik (kimlik tohumuyla kararli).
const WALKER_VARIANTS := ["zombie_walker", "zombie_walker", "iz2_zombie_courier", "iz2_zombie_luggage", "zombie_police"]

var id: String
var name: String
var health: float
var armor: float
var speed: float
var sprint_speed: float
var acceleration: float
var damage: float
var attack_range: float
var attack_windup: float
var attack_cooldown: float
var sight_radius: float
var sight_angle: float
var hearing_radius: float
var investigate_time: float
var knockback_resist: float
var stagger_time: float
var sprite: String
var weight: float
var resistances: Dictionary = {}
var bite_status: String = ""
var bite_duration: float = 0.0
var bite_magnitude: float = 0.0
var scream_radius: float = 0.0
var scream_interval: float = 4.0


func model_id(variant: int = 0) -> String:
	if MODEL_BY_ID.has(id) and AssetLibrary.has(str(MODEL_BY_ID[id])):
		return MODEL_BY_ID[id]
	if id == "walker":
		var pick: String = WALKER_VARIANTS[absi(variant) % WALKER_VARIANTS.size()]
		if AssetLibrary.has(pick):
			return pick
	return MODEL_BY_SPRITE.get(sprite, "zombie_walker")


# --- metre cinsinden turetilmis degerler ---
func speed_m() -> float:
	return Units.zombie_move_m(speed)


func sprint_speed_m() -> float:
	return Units.zombie_move_m(maxf(sprint_speed, speed))


func acceleration_m() -> float:
	return Units.zombie_move_m(acceleration)


func attack_range_m() -> float:
	# Eski menzil karakter MERKEZLERI arasindaydi; FPS'te kapsul yuzeyleri
	# arasi olcuyoruz, bu yuzden govde yaricaplari kadar pay eklenir.
	return Units.move_m(attack_range) + 0.6


func sight_m() -> float:
	return Units.perception_m(sight_radius)


func hearing_m() -> float:
	return Units.perception_m(hearing_radius)


func scream_m() -> float:
	return Units.perception_m(scream_radius)


static func from_dict(source: String, zombie_id: String, data: Dictionary, errors: Array) -> ZombieDef:
	var v := ContentValidator.new(source, zombie_id, data, errors)
	v.reject_unknown(FIELDS)
	var z := ZombieDef.new()
	z.id = zombie_id
	z.name = v.text("name")
	z.health = v.num("health", null, 1.0)
	z.armor = v.num("armor", 0.0, 0.0)
	z.speed = v.num("speed", null, 1.0)
	z.sprint_speed = v.num("sprint_speed", 0.0, 0.0)
	z.acceleration = v.num("acceleration", 420.0, 1.0)
	z.damage = v.num("damage", null, 0.0)
	z.attack_range = v.num("attack_range", 24.0, 1.0)
	z.attack_windup = v.num("attack_windup", 0.25, 0.0)
	z.attack_cooldown = v.num("attack_cooldown", 1.1, 0.05)
	z.sight_radius = v.num("sight_radius", 240.0, 0.0)
	z.sight_angle = v.num("sight_angle", 75.0, 1.0, 180.0)
	z.hearing_radius = v.num("hearing_radius", 380.0, 0.0)
	z.investigate_time = v.num("investigate_time", 6.0, 0.0)
	z.knockback_resist = v.num("knockback_resist", 0.0, 0.0, 1.0)
	z.stagger_time = v.num("stagger_time", 0.18, 0.0)
	z.sprite = v.text("sprite", "actors/zombie")
	z.weight = v.num("weight", 1.0, 0.0)
	z.resistances = v.number_dict("resistances")
	z.bite_status = v.text("bite_status", "")
	z.bite_duration = v.num("bite_duration", 0.0, 0.0)
	z.bite_magnitude = v.num("bite_magnitude", 0.0, 0.0)
	z.scream_radius = v.num("scream_radius", 0.0, 0.0)
	z.scream_interval = v.num("scream_interval", 4.0, 0.5)
	return z


func mitigate(amount: float, damage_type: String) -> float:
	## Eski Health.mitigate: once direnc orani, sonra duz zirh; zirh hasari
	## hicbir zaman %10'un altina indiremez.
	if damage_type == "true":
		return amount
	var resisted := amount * (1.0 - float(resistances.get(damage_type, 0.0)))
	return maxf(resisted * 0.10, resisted - armor)
