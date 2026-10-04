class_name Crosshair
extends Control
## Dinamik nisangah: dagilma buyudukce acilir. Silahin gercek dagilma
## acisini ekrana cevirir; "nisangah dar ama mermi saciliyor" yalani olmaz.

var spread_degrees := 1.5
var hit_marker := 0.0
var kill_marker := 0.0
var visible_cross := true
var color := Color(1, 1, 1, 0.9)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	hit_marker = maxf(0.0, hit_marker - delta * 4.0)
	kill_marker = maxf(0.0, kill_marker - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	if not visible_cross:
		return
	var center := size * 0.5
	var camera := get_viewport().get_camera_3d()
	var fov := camera.fov if camera != null else 80.0
	# Dagilma acisini piksele cevir: tan(aci) / tan(fov/2) * yarim yukseklik.
	var gap := tan(deg_to_rad(spread_degrees)) / tan(deg_to_rad(fov * 0.5)) * size.y * 0.5
	gap = clampf(gap, 4.0, 120.0)
	var length := 9.0
	var width := 2.0
	var shadow := Color(0, 0, 0, 0.6)
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var a := center + dir * gap
		var b := center + dir * (gap + length)
		draw_line(a + Vector2(1, 1), b + Vector2(1, 1), shadow, width + 1)
		draw_line(a, b, color, width)
	draw_circle(center, 1.5, color)
	if hit_marker > 0.0:
		var c := Color(1, 1, 1, hit_marker) if kill_marker <= 0.0 else Color(1, 0.3, 0.25, kill_marker)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + d * 6.0, center + d * 13.0, c, 2.5)
