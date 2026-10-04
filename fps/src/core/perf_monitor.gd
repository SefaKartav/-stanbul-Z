class_name PerfMonitor
extends RefCounted
## Kare suresi olcumu: ortalama FPS tek basina yaniltir. Belgenin istedigi
## gibi p95/p99 kare suresi de tutulur -- "ortalama 60 ama her saniye bir
## takilma" durumunu ancak yuzdelikler gosterir.

const WINDOW := 600               # son ~10 sn (60 FPS'te)

var _samples := PackedFloat32Array()
var _index := 0
var _filled := 0


func _init() -> void:
	_samples.resize(WINDOW)


func push(frame_seconds: float) -> void:
	_samples[_index] = frame_seconds * 1000.0
	_index = (_index + 1) % WINDOW
	_filled = mini(_filled + 1, WINDOW)


func report() -> Dictionary:
	if _filled == 0:
		return {"avg_ms": 0.0, "p95_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0, "fps": 0.0, "samples": 0}
	var values := _samples.slice(0, _filled) if _filled < WINDOW else _samples.duplicate()
	values.sort()
	var total := 0.0
	for v in values:
		total += v
	var avg := total / values.size()
	return {
		"avg_ms": avg,
		"p95_ms": values[mini(values.size() - 1, int(values.size() * 0.95))],
		"p99_ms": values[mini(values.size() - 1, int(values.size() * 0.99))],
		"max_ms": values[values.size() - 1],
		"fps": 1000.0 / maxf(0.001, avg),
		"samples": values.size(),
	}


## Ana is parcacigi bolum sureleri (en kotu, usec): takilma kaynagini bulmak icin.
var sections: Dictionary = {}


func section(name: String, usec: int) -> void:
	sections[name] = maxi(int(sections.get(name, 0)), usec)


func worst_sections(n: int = 4) -> String:
	var keys := sections.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(sections[a]) > int(sections[b]))
	var parts := PackedStringArray()
	for k: String in keys.slice(0, n):
		parts.append("%s %.1f" % [k, int(sections[k]) / 1000.0])
	return ", ".join(parts)


func reset() -> void:
	_index = 0
	_filled = 0
	sections.clear()
