extends Node
## Oyuncu ayarlari ve DEGISTIRILEBILIR tus atamalari.
##
## Tus haritasi project.godot'ta degil burada kurulur: atamalar
## user://settings.cfg'den okunur ve oyun icinden degistirilebilir. Tek
## kaynak burasi oldugu icin "ayar menusu baska, oyun baska tus bekliyor"
## turu tutarsizlik olusamaz.
##
## Eski yetenek tuslari (Q/F/Space) yeni FPS kontrolleriyle cakisiyordu:
## Space artik ZIPLAMA, F fener. Yetenekler bu yuzden Q/V/G/X/Z'ye tasindi.

signal changed

const PATH := "user://settings.cfg"

# eylem -> [etiket, varsayilan atama]. Atama: "key:<fiziksel kod>" ya da "mouse:<dugme>".
const ACTIONS := {
	"move_forward": ["İleri", "key:W"],
	"move_back": ["Geri", "key:S"],
	"move_left": ["Sol", "key:A"],
	"move_right": ["Sağ", "key:D"],
	"jump": ["Zıpla", "key:Space"],
	"sprint": ["Depar", "key:Shift"],
	"walk_toggle": ["Yürü / koş geçişi", "key:CapsLock"],
	"crouch": ["Çömel", "key:Ctrl"],
	"fire": ["Ateş", "mouse:1"],
	"aim": ["Nişan", "mouse:2"],
	"reload": ["Doldur", "key:R"],
	"interact": ["Etkileşim / ara", "key:E"],
	"build": ["İnşa kipi", "key:B"],
	"inventory": ["Envanter", "key:I"],
	"inventory_alt": ["Envanter (2)", "key:Tab"],
	"craft": ["Üretim", "key:C"],
	"map": ["Harita", "key:M"],
	"colony": ["Koloni", "key:L"],
	"skills": ["Beceriler", "key:K"],
	"journal": ["Görev günlüğü", "key:J"],
	"quick_eat": ["Hızlı ye (en iyi yiyecek)", "key:N"],
	"quick_drink": ["Hızlı iç (en temiz su)", "key:U"],
	"flashlight": ["Fener", "key:F"],
	"look_center": ["Araçta bakışı ortala", "key:H"],
	"throw": ["Fırlat (molotof, bomba, ses tuzağı, fişek)", "key:T"],
	"throw_cycle": ["Fırlatılacak eşyayı değiştir", "key:Y"],
	"weapon_1": ["Silah 1", "key:1"],
	"weapon_2": ["Silah 2", "key:2"],
	"weapon_3": ["Silah 3", "key:3"],
	"weapon_4": ["Silah 4", "key:4"],
	"weapon_next": ["Sonraki silah", "mouse:5"],
	"weapon_prev": ["Önceki silah", "mouse:4"],
	"ability_shove": ["İtekleme", "key:Q"],
	"ability_dodge": ["Kaçınma", "key:V"],
	"ability_first_aid": ["İlk yardım", "key:G"],
	"ability_adrenaline": ["Adrenalin", "key:X"],
	"ability_distraction": ["Dikkat dağıtma", "key:Z"],
	"binoculars": ["Dürbün (basılı tut)", "key:O"],
	"quick_save": ["Hızlı kaydet", "key:F5"],
	"quick_load": ["Hızlı yükle", "key:F9"],
	"pause": ["Duraklat", "key:Escape"],
	"debug_overlay": ["Teşhis", "key:F3"],
}

var sensitivity_x := 0.12
var sensitivity_y := 0.12
var invert_y := false
var fov := 80.0
var head_bob := 1.0            # 0 = kapali
var screen_shake := 1.0        # 0 = kapali
var view_distance := 7         # chunk (16 m)
var shadow_quality := 2        # 0 kapali, 1 dusuk, 2 orta, 3 yuksek
var graphics_preset := 1       # 0 dusuk, 1 orta, 2 yuksek, 3 ozel (elle ayar)
var aa_mode := 1               # 0 kapali, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x
var soft_look := true          # mat palet + uzakta yumusak doku
var legacy_look := false       # yalniz olcum (--legacy-look): eski isik/golge/AA parametreleri; kaydedilmez
var master_volume := 0.8
var fullscreen := true
var always_run := true         # varsayilan kademe kosu (3.6 m/sn); Caps Lock yuruyuse gecer
var difficulty := "normal"     # kolay / normal / zor: aclik-susuzluk hizi ve hasari
var favorites: Array = []      # favori tarif kimlikleri (uretim ekrani)
var bindings: Dictionary = {}  # eylem -> atama metni


func _ready() -> void:
	for action: String in ACTIONS:
		bindings[action] = ACTIONS[action][1]
	load_settings()
	apply_bindings()
	apply_display()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	sensitivity_x = float(config.get_value("mouse", "sensitivity_x", sensitivity_x))
	sensitivity_y = float(config.get_value("mouse", "sensitivity_y", sensitivity_y))
	invert_y = bool(config.get_value("mouse", "invert_y", invert_y))
	fov = clampf(float(config.get_value("view", "fov", fov)), 60.0, 110.0)
	head_bob = clampf(float(config.get_value("view", "head_bob", head_bob)), 0.0, 1.0)
	screen_shake = clampf(float(config.get_value("view", "screen_shake", screen_shake)), 0.0, 1.0)
	view_distance = clampi(int(config.get_value("graphics", "view_distance", view_distance)), 3, 16)
	shadow_quality = clampi(int(config.get_value("graphics", "shadow_quality", shadow_quality)), 0, 3)
	graphics_preset = clampi(int(config.get_value("graphics", "preset", graphics_preset)), 0, 3)
	aa_mode = clampi(int(config.get_value("graphics", "aa_mode", aa_mode)), 0, 3)
	soft_look = bool(config.get_value("graphics", "soft_look", soft_look))
	fullscreen = bool(config.get_value("graphics", "fullscreen", fullscreen))
	master_volume = clampf(float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	always_run = bool(config.get_value("controls", "always_run", always_run))
	var saved_difficulty := str(config.get_value("gameplay", "difficulty", difficulty))
	difficulty = saved_difficulty if saved_difficulty in ["kolay", "normal", "zor"] else "normal"
	var saved_favorites: Variant = config.get_value("crafting", "favorites", [])
	favorites = Array(saved_favorites) if typeof(saved_favorites) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY] else []
	for action: String in ACTIONS:
		var value: Variant = config.get_value("bindings", action, bindings[action])
		if typeof(value) == TYPE_STRING and _parse_binding(value) != null:
			bindings[action] = value


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("mouse", "sensitivity_x", sensitivity_x)
	config.set_value("mouse", "sensitivity_y", sensitivity_y)
	config.set_value("mouse", "invert_y", invert_y)
	config.set_value("view", "fov", fov)
	config.set_value("view", "head_bob", head_bob)
	config.set_value("view", "screen_shake", screen_shake)
	config.set_value("graphics", "view_distance", view_distance)
	config.set_value("graphics", "shadow_quality", shadow_quality)
	config.set_value("graphics", "preset", graphics_preset)
	config.set_value("graphics", "aa_mode", aa_mode)
	config.set_value("graphics", "soft_look", soft_look)
	config.set_value("graphics", "fullscreen", fullscreen)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("controls", "always_run", always_run)
	config.set_value("gameplay", "difficulty", difficulty)
	config.set_value("crafting", "favorites", favorites)
	for action: String in bindings:
		config.set_value("bindings", action, bindings[action])
	config.save(PATH)
	changed.emit()


## Grafik on ayarlari: [golge, kenar yumusatma, gorus (chunk)]. "Ozel" (3)
## elle yapilan degisiklikte kendiliginden secilir.
const PRESET_NAMES := ["Düşük", "Orta", "Yüksek", "Özel"]
const PRESETS := [[1, 1, 5], [2, 1, 7], [3, 2, 9]]
const AA_NAMES := ["Kapalı", "FXAA", "MSAA 2x", "MSAA 4x"]


func apply_preset(index: int) -> void:
	graphics_preset = clampi(index, 0, 3)
	if graphics_preset < PRESETS.size():
		var p: Array = PRESETS[graphics_preset]
		shadow_quality = int(p[0])
		aa_mode = int(p[1])
		view_distance = int(p[2])
	save_settings()


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.0001, master_volume)))


func rebind(action: String, event: InputEvent) -> bool:
	## Oyun icinden yeni atama. Ayni tusu kullanan baska eylem varsa ona
	## eski tus verilir (takas): iki eylemin ayni tusu paylasmasi, "tusa
	## basinca iki sey oldu" turu gizli hatalara yol acardi.
	var text := binding_from_event(event)
	if text == "" or not bindings.has(action):
		return false
	var previous: String = bindings[action]
	for other: String in bindings:
		if other != action and bindings[other] == text:
			bindings[other] = previous
	bindings[action] = text
	apply_bindings()
	save_settings()
	return true


func reset_bindings() -> void:
	for action: String in ACTIONS:
		bindings[action] = ACTIONS[action][1]
	apply_bindings()
	save_settings()


func apply_bindings() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		var event: InputEvent = _parse_binding(bindings[action])
		if event != null:
			InputMap.action_add_event(action, event)
	changed.emit()


static func binding_from_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:" + OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""


static func _parse_binding(text: String) -> InputEvent:
	if text.begins_with("key:"):
		var code := OS.find_keycode_from_string(text.substr(4))
		if code == KEY_NONE:
			return null
		var key := InputEventKey.new()
		key.physical_keycode = code
		return key
	if text.begins_with("mouse:"):
		var mouse := InputEventMouseButton.new()
		mouse.button_index = int(text.substr(6)) as MouseButton
		return mouse
	return null


func binding_label(action: String) -> String:
	var text: String = bindings.get(action, "")
	if text.begins_with("key:"):
		return text.substr(4)
	match text:
		"mouse:1": return "Sol tik"
		"mouse:2": return "Sag tik"
		"mouse:3": return "Orta tik"
		"mouse:4": return "Tekerlek yukari"
		"mouse:5": return "Tekerlek asagi"
	return text
