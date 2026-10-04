class_name WeaponDef
extends RefCounted
## Silah tanimi (veri). data/weapons/*.json dosyalarindan gelir; kodda hicbir
## silah sabiti yoktur. (Python: game/combat/weapons.py)
##
## BIRIMLER: JSON degerleri eski 2D oyunun DUNYA PIKSELI cinsindendir
## (16 px = 1 m). Veri dosyalari degistirilmeden korunur; metreye cevrim
## tek yerde, `Units` sinifinda yapilir (bkz. src/core/units.gd).

const FIELDS := [
	"id", "name", "category", "damage", "damage_type", "fire_rate", "pellets",
	"spread", "projectile_speed", "range", "magazine", "reload_time",
	"ammo_type", "noise_radius", "recoil", "shake", "automatic", "knockback",
	"pierce", "muzzle_offset",
]
const CATEGORIES := ["pistol", "shotgun", "smg", "rifle", "melee"]
const DAMAGE_TYPES := ["physical", "fire", "shock", "acid", "explosive", "true"]

var id: String
var name: String
var category: String
var damage: float
var damage_type: String = "physical"
var fire_rate: float
var pellets: int = 1
var spread: float = 0.0          # derece, yari aci
var projectile_speed: float
var range_px: float
var magazine: int
var reload_time: float
var ammo_type: String
var noise_radius_px: float
var recoil: float                # atistan sonra eklenen dagilma (derece)
var shake: float
var automatic: bool
var knockback: float
var pierce: int
var muzzle_offset: float


func shot_interval() -> float:
	return 1.0 / fire_rate if fire_rate > 0.0 else 0.0


func is_melee() -> bool:
	return category == "melee"


func range_m() -> float:
	return Units.weapon_range_m(range_px)


func noise_radius_m() -> float:
	return Units.perception_m(noise_radius_px)


static func from_dict(source: String, weapon_id: String, data: Dictionary, errors: Array) -> WeaponDef:
	var v := ContentValidator.new(source, weapon_id, data, errors)
	v.reject_unknown(FIELDS)
	var w := WeaponDef.new()
	w.id = weapon_id
	w.name = v.text("name")
	w.category = v.choice("category", CATEGORIES)
	w.damage = v.num("damage", null, 0.0)
	w.damage_type = v.choice("damage_type", DAMAGE_TYPES, "physical")
	w.fire_rate = v.num("fire_rate", null, 0.01, 60.0)
	w.pellets = v.integer("pellets", 1, 1)
	w.spread = v.num("spread", 0.0, 0.0, 90.0)
	w.projectile_speed = v.num("projectile_speed", 900.0, 0.0)
	w.range_px = v.num("range", 420.0, 8.0)
	w.magazine = v.integer("magazine", null, 1)
	w.reload_time = v.num("reload_time", null, 0.0)
	w.ammo_type = v.text("ammo_type")
	w.noise_radius_px = v.num("noise_radius", 300.0, 0.0)
	w.recoil = v.num("recoil", 0.0, 0.0)
	w.shake = v.num("shake", 0.15, 0.0, 1.0)
	w.automatic = v.flag("automatic", false)
	w.knockback = v.num("knockback", 0.0, 0.0)
	w.pierce = v.integer("pierce", 0, 0)
	w.muzzle_offset = v.num("muzzle_offset", 12.0, 0.0)
	return w
