class_name TimeOfDay
extends RefCounted
## Gunun dongusu ve GECE BASKISI (Python: world/daynight.py).
##
## Gece bir gorsel filtre degil bir OYUN MEKANIGIDIR: gorus azalir, fener
## seni ele verir, horde artar, zombiler hizlanir. Dordunun toplami oyuncuyu
## "gun batmadan usse don" davranisina iter.

const DAY_LENGTH := 960.0          # gercek saniye (16 dk)
const NIGHT_START := 0.80
const NIGHT_END := 0.24
const PHASES := [
	[0.00, Color8(52, 60, 96), "Gece"],
	[0.22, Color8(128, 116, 132), "Safak"],
	[0.30, Color8(232, 214, 190), "Sabah"],
	[0.46, Color8(255, 252, 244), "Ogle"],
	[0.62, Color8(244, 224, 190), "Ikindi"],
	[0.74, Color8(186, 138, 118), "Gun Batimi"],
	[0.82, Color8(92, 88, 122), "Aksam"],
	[0.90, Color8(52, 60, 96), "Gece"],
]

var normalized := 0.375            # 09:00'da baslar
var day := 1
var speed := 1.0 / DAY_LENGTH
var paused := false


func update(delta: float) -> int:
	## Ilerletir; kac gun donumu gectigini dondurur.
	if paused:
		return 0
	normalized += speed * delta
	var turned := 0
	while normalized >= 1.0:
		normalized -= 1.0
		day += 1
		turned += 1
	return turned


func advance_hours(hours: float) -> int:
	var turned := 0
	normalized += hours / 24.0
	while normalized >= 1.0:
		normalized -= 1.0
		day += 1
		turned += 1
	return turned


func hour() -> float:
	return normalized * 24.0


func total_hours() -> float:
	## Oyun basindan beri gecen dunya saati (bozulma, gorev sureleri, uzmanlik).
	return float(day - 1) * 24.0 + normalized * 24.0


func hours_per_second() -> float:
	## Bir gercek saniyede gecen oyun saati (1 oyun saati = 40 sn).
	return 0.0 if paused else speed * 24.0


func clock() -> String:
	var minutes := int(normalized * 24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func phase_name() -> String:
	var name: String = PHASES[0][2]
	for phase: Array in PHASES:
		if normalized >= phase[0]:
			name = phase[2]
	return name


func is_night() -> bool:
	return normalized >= NIGHT_START or normalized < NIGHT_END


func ambient() -> Color:
	var count := PHASES.size()
	for i in count:
		var start: float = PHASES[i][0]
		var color: Color = PHASES[i][1]
		var next_start: float = PHASES[(i + 1) % count][0]
		var next_color: Color = PHASES[(i + 1) % count][1]
		var span_end := next_start if next_start > start else next_start + 1.0
		var position := normalized
		if position < start:
			position += 1.0
		if position >= start and position < span_end:
			return color.lerp(next_color, (position - start) / maxf(1e-6, span_end - start))
	return PHASES[0][1]


func darkness() -> float:
	## 0 = tam gunduz, 1 = en koyu gece.
	var c := ambient()
	return 1.0 - (c.r + c.g + c.b) / 3.0


func sight_multiplier() -> float:
	return 1.0 - 0.45 * darkness()


func horde_multiplier() -> float:
	return 1.0 + darkness()


func zombie_speed_multiplier() -> float:
	return 1.0 + 0.18 * darkness()


func to_dict() -> Dictionary:
	return {"normalized": normalized, "day": day}


func load_dict(data: Dictionary) -> void:
	normalized = clampf(float(data.get("normalized", 0.375)), 0.0, 0.9999)
	day = maxi(1, int(data.get("day", 1)))
