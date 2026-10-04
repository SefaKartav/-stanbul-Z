class_name SkillsScreen
extends Screen
## Beceri agaci (K): seviye, deneyim kaynaklari, alti dal x 8 dugum.
## Her dugum icin maliyet, onkosul, seviye ve ustalik durumu ACIKCA yazilir;
## aciklama veriden gelir (UI'da gorunup calismayan dugum yok: icerik
## dogrulamasi davranis kimliklerini kodla eslestirir).

var columns: HBoxContainer
var header: Label


func _init() -> void:
	super._init()
	title = "Beceri Ağacı"
	toggle_action = "skills"


func _build_content() -> void:
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(outer)
	header = UiTheme.label("", 22, UiTheme.ACCENT)
	outer.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	scroll.add_child(columns)
	var buttons := HBoxContainer.new()
	outer.add_child(buttons)
	buttons.add_child(UiTheme.button("Puanlari iade et (usste, 3 gunde bir, seviye deneyiminin yarisi)", _respec))
	footer.text = "Dugum acmak: puan + onkosul + seviye + ustalik. Yetenek tuslari: Q itekleme, V kacinma, G ilk yardim, X adrenalin, Z dikkat dagitma."


func refresh() -> void:
	for child in columns.get_children():
		child.queue_free()
	var p: Progression = game.progression
	var need := p.xp_needed() if p.level < Progression.max_level() else 0.0
	var src := PackedStringArray()
	for key: String in p.sources:
		src.append("%s %d" % [{"kill": "oldurme", "search": "arama", "quest": "gorev", "discovery": "kesif",
			"craft": "uretim", "other": "diger"}.get(key, key), int(p.sources[key])])
	header.text = "Seviye %d/%d   Deneyim %d/%d   Puan: %d   (harcanan %d / agacin toplami %d)   Kaynaklar: %s" % [
		p.level, Progression.max_level(), int(p.xp), int(need), p.points, p.spent_points(), SkillTree.total_cost(), ", ".join(src)]
	for branch: Dictionary in Content.skill_tree.get("branches", []):
		var col := Screen.column(300, false)
		col.custom_minimum_size.x = 300
		columns.add_child(col)
		var c: Array = branch.get("color", [200, 200, 200])
		col.add_child(UiTheme.label(str(branch.name), 22, Color8(int(c[0]), int(c[1]), int(c[2]))))
		for n: Dictionary in SkillTree.branch_nodes(str(branch.id)):
			_node(col, n, p)


func _node(col: VBoxContainer, n: Dictionary, p: Progression) -> void:
	var owned := p.nodes.has(n.id)
	var check: Array = SkillTree.check(str(n.id), p)
	var panel := PanelContainer.new()
	col.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var kind := ""
	if n.has("behavior") or n.has("unlock"):
		kind = " [yeni eylem]"
	elif n.has("power"):
		kind = " [yetenek]"
	box.add_child(UiTheme.label("%s%s  (%d puan)" % [n.name, kind, int(n.cost)], 18,
		UiTheme.GOOD if owned else (UiTheme.ACCENT if check[0] else UiTheme.TEXT)))
	var desc := UiTheme.label(str(n.desc), 15, UiTheme.MUTED if not owned else UiTheme.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 280
	box.add_child(desc)
	if owned:
		box.add_child(UiTheme.label("ACIK", 15, UiTheme.GOOD))
		return
	var button := UiTheme.button("Ac" if check[0] else str(check[1]), func() -> void:
		if p.upgrade(str(n.id)):
			for recipe_id: Variant in n.get("unlock", []):
				game.crafting.known_recipes[str(recipe_id)] = true
			game.refresh_skill_effects()
			game.hud.message("Beceri acildi: %s" % n.name, Hud.GREEN)
		refresh())
	button.disabled = not check[0]
	box.add_child(button)


func _respec() -> void:
	if game.bases.inside == null:
		game.hud.message("Puan iadesi yalnizca bir ussun icindeyken yapilabilir", Hud.RED)
		return
	var problem: String = game.progression.respec(game.time.day)
	if problem != "":
		game.hud.message(problem, Hud.RED)
	else:
		game.refresh_skill_effects()
		game.hud.message("Beceri puanlari iade edildi", Hud.ACCENT)
	refresh()
