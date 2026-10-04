class_name JournalScreen
extends Screen
## Gorev gunlugu (J): amac, gerekce, hedefler (tamam/aktif/kilitli, eksik
## malzeme), konum, uzaklik ve odul. "Hedef yap" haritada ve HUD'da yon
## gosterir. Dunyayi DURDURMAZ (okurken tehlike surer).

var list: ItemList
var detail: VBoxContainer
var _entries: Array = []
var _selected := ""


func _init() -> void:
	super._init()
	title = "Görev Günlüğü"
	toggle_action = "journal"


func _build_content() -> void:
	list = ItemList.new()
	list.custom_minimum_size = Vector2(520, 0)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(i: int) -> void:
		_selected = str(list.get_item_metadata(i))
		_show())
	body.add_child(list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	detail = Screen.column(700)
	scroll.add_child(detail)
	footer.text = "Ana hedef: mahalleleri temiz su, enerji, haberlesme ve guvenli ikmal hatlariyla birbirine baglayan kalici bir hayatta kalan agi."


func refresh() -> void:
	var quests: QuestSystem = game.quests
	_entries = quests.journal_entries()
	list.clear()
	var first := ""
	for group: Array in [[true, false], [false, false], [true, true], [false, true]]:
		for e: Dictionary in _entries:
			if bool(e.main) != group[0] or bool(e.done) != group[1]:
				continue
			var label := "%s%s  %s" % ["" if e.main else "[yan] ", e.stage, e.title]
			if e.done:
				label = "✓ " + label
			var i := list.add_item(label)
			list.set_item_metadata(i, e.id)
			list.set_item_custom_fg_color(i, UiTheme.MUTED if e.done else (UiTheme.ACCENT if e.main else UiTheme.TEXT))
			if first == "":
				first = e.id
			if e.id == _selected:
				list.select(i)
	if _selected == "":
		_selected = first
		for i in list.item_count:
			if str(list.get_item_metadata(i)) == _selected:
				list.select(i)
	_show()


func _show() -> void:
	for child in detail.get_children():
		child.queue_free()
	var entry := {}
	for e: Dictionary in _entries:
		if e.id == _selected:
			entry = e
	if entry.is_empty():
		detail.add_child(UiTheme.label("Gorev yok.", 20))
		return
	detail.add_child(UiTheme.label(entry.title, 28, UiTheme.ACCENT))
	detail.add_child(UiTheme.label("%s%s" % ["Ana gorev -- " if entry.main else "Yan gorev -- ", entry.stage], 18, UiTheme.MUTED))
	detail.add_child(UiTheme.label(str(entry.text), 20))
	detail.add_child(UiTheme.label("Hedefler", 22, UiTheme.ACCENT))
	for o: Dictionary in entry.objectives:
		var mark: String = {"done": "✓", "active": "▶", "locked": "·"}.get(o.state, "·")
		var color := UiTheme.GOOD if o.state == "done" else (UiTheme.TEXT if o.state == "active" else UiTheme.MUTED)
		detail.add_child(UiTheme.label("%s %s" % [mark, o.label], 19, color))
	var p: Vector3 = entry.get("position", Vector3.INF)
	if p != Vector3.INF:
		var me: Vector3 = game.player.global_position
		var d := Vector2(p.x, p.z).distance_to(Vector2(me.x, me.z))
		var dist := ("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % int(d))
		var walk := int(d / Player.RUN_SPEED / 60.0)
		detail.add_child(UiTheme.label("Konum: %s uzakta (kosarak ~%d dk, %s)" % [dist, walk, game._bearing(p)], 19))
		detail.add_child(UiTheme.button("Hedef yap (haritada ve ekranda goster)", func() -> void:
			game.waypoint = p
			game.hud.message("Hedef isaretlendi: %s" % entry.title, Hud.ACCENT)))
	var rewards: Dictionary = entry.rewards
	var parts := PackedStringArray()
	if rewards.has("xp"):
		parts.append("%d deneyim" % int(rewards.xp))
	for it: Array in rewards.get("items", []):
		var def: ItemDef = Content.item(str(it[0]))
		if def != null:
			parts.append("%s x%d" % [def.name, int(it[1])])
	for r: Variant in rewards.get("unlock", []):
		var recipe: RecipeDef = Content.recipes.get(str(r))
		parts.append("sema: " + (recipe.name if recipe != null else str(r)))
	if rewards.has("points"):
		parts.append("+%d beceri puani" % int(rewards.points))
	if rewards.has("flag"):
		parts.append({"water_line": "su hatti (uslere gunluk su)", "network": "telsiz agi", "bridge": "kopru gecisi",
			"campaign_done": "ANA HEDEF", "intel_1": "bina istihbarati", "grid": "sebeke tasarrufu",
			"beacon": "isaret menzili", "radio_found": "role semasi", "donation": "yeni gelen biri"}.get(str(rewards.flag), str(rewards.flag)))
	detail.add_child(UiTheme.label("Odul: " + (", ".join(parts) if not parts.is_empty() else "-"), 19, UiTheme.GOOD))
	if entry.done:
		detail.add_child(UiTheme.label("Tamamlandi.", 19, UiTheme.MUTED))
