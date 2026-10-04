class_name Screen
extends Control
## Tam ekran menu tabani.
##
## DURAKLATMA POLITIKASI (belgenin 5. bolumu -- acikca belirlendi):
##   * `pauses_world = true`  -> harita (M) ve Esc menusu. Dunya DURUR.
##   * `pauses_world = false` -> envanter, uretim, koloni, beceri. Dunya
##     AKAR: hayatta kalma baskisi surer, uretim sureleri gercek zamanda
##     isler, zombi yaklasirken cantayi karistirmak bir risktir.
##   Iki durumda da fare serbest kalir ve TIKLAMA ATES DEGILDIR: oyuncu
##   girdisi kapatilir, menu kapaninca tetik bir kez birakilmadan
##   ates edilmez (bkz. PlayerCombat).

signal closed

var game: Node
var pauses_world := false
var title := ""
var toggle_action := ""          # ayni tus ekrani kapatir (I, C, M...)
var subtitle := ""               # basligin yanindaki kisa aciklama
var toggle_key := ""             # baslikta gosterilen kapatma tusu ("C", "I")
var root: VBoxContainer
var header_extra: HBoxContainer  # alt siniflar baslik satirina rozet ekleyebilir
var body: HBoxContainer
var footer: Label


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()


func build() -> void:
	## Alt siniflar `_build_content()` ile govdeyi doldurur.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.02, 0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64 if side in ["left", "right"] else 44)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	# Baslik: vurgu cizgisi + buyuk harfli baslik + alt baslik ... tus ipuclari
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)
	var bar := ColorRect.new()
	bar.color = UiTheme.ACCENT
	bar.custom_minimum_size = Vector2(4, 34)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(bar)
	var title_label := UiTheme.heading(title, 36, UiTheme.TEXT)
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title_label)
	if subtitle != "":
		var sub := UiTheme.label(subtitle, 18, UiTheme.MUTED)
		sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sub.autowrap_mode = TextServer.AUTOWRAP_OFF
		header.add_child(sub)
	header_extra = HBoxContainer.new()
	header_extra.add_theme_constant_override("separation", 8)
	header_extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_extra.alignment = BoxContainer.ALIGNMENT_END
	header.add_child(header_extra)
	if toggle_key == "" and toggle_action != "" and toggle_action != "interact":
		toggle_key = Settings.binding_label(toggle_action)
	if toggle_key != "":
		header.add_child(UiTheme.key_hint(toggle_key, "ya da"))
	header.add_child(UiTheme.key_hint("Esc", "Kapat"))
	var close_button := UiTheme.button("✕", close)
	close_button.custom_minimum_size = Vector2(44, 40)
	close_button.tooltip_text = "Kapat"
	header.add_child(close_button)
	root.add_child(HSeparator.new())

	body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	var foot := PanelContainer.new()
	foot.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.INSET, 5, UiTheme.LINE_SOFT, 1, 14, 8))
	root.add_child(foot)
	footer = UiTheme.label("", 16, UiTheme.MUTED)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(footer)
	_build_content()
	refresh()


func _build_content() -> void:
	pass


func refresh() -> void:
	pass


func close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or (toggle_action != "" and event.is_action_pressed(toggle_action)):
		get_viewport().set_input_as_handled()
		close()


static func column(min_width: float = 0.0, expand: bool = true) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	if expand:
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x = min_width
	return box
