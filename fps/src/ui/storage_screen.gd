class_name StorageScreen
extends Screen
## Yerlestirilmis depo (sandik, dolap, raf): canta <-> depo aktarimi.
## Aktarim atomiktir: sigmayan kisim KAYNAKTA kalir (esya silinmez).

var entry: Dictionary = {}
var bag_list: ItemList
var box_list: ItemList
var box_title: Label
var _bag: Array = []
var _box: Array = []


func _init() -> void:
	super._init()
	title = "Depo"
	subtitle = "Çanta ↔ sandık"
	toggle_action = "interact"


func _storage() -> Inventory:
	return entry.get("inv") as Inventory


func _build_content() -> void:
	title = game.placeables.label_of(entry) if not entry.is_empty() else "Depo"
	var left := Screen.column(560)
	body.add_child(left)
	left.add_child(UiTheme.section("Çanta"))
	bag_list = ItemList.new()
	bag_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_list.fixed_icon_size = Vector2i(34, 34)
	bag_list.item_activated.connect(func(i: int) -> void: _move(_bag[i], true))
	left.add_child(bag_list)
	var put_all := UiTheme.button("Tümünü koy ›", func() -> void:
		for stack: ItemStack in game.inventory.stacks.duplicate():
			if stack.definition.category != "weapon":
				_move(stack, true, false)
		refresh())
	left.add_child(put_all)

	var right := Screen.column(560)
	body.add_child(right)
	box_title = UiTheme.label("", 18, UiTheme.TEXT)
	right.add_child(UiTheme.section("Depo"))
	right.add_child(box_title)
	box_list = ItemList.new()
	box_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box_list.fixed_icon_size = Vector2i(34, 34)
	box_list.item_activated.connect(func(i: int) -> void: _move(_box[i], false))
	right.add_child(box_list)
	var take_all := UiTheme.button("‹ Tümünü al", func() -> void:
		for stack: ItemStack in _storage().stacks.duplicate():
			_move(stack, false, false)
		refresh())
	right.add_child(take_all)
	footer.text = "Çift tıkla: eşyayı karşı tarafa taşı. Sığmayan kısım yerinde kalır. Depo sökülürse içindekiler çantana/yere döner."


func refresh() -> void:
	if entry.is_empty() or _storage() == null:
		return
	var inv := _storage()
	box_title.text = "%.1f / %.0f kg · %d/%d yuva" % [inv.weight(), inv.capacity_kg, inv.slots_used(), inv.max_slots]
	_bag = InventoryScreen._sorted(game.inventory.stacks)
	_box = InventoryScreen._sorted(inv.stacks)
	_fill(bag_list, _bag)
	_fill(box_list, _box)


static func _fill(list: ItemList, stacks: Array) -> void:
	list.clear()
	for stack: ItemStack in stacks:
		var index := list.add_item("%s   ×%d   ·   %.1f kg" % [stack.display_name(), stack.quantity, stack.total_weight()],
			AssetLibrary.icon(AssetLibrary.item_model_id(stack.definition)))
		list.set_item_custom_fg_color(index, stack.color())


func _move(stack: ItemStack, to_box: bool, redraw: bool = true) -> void:
	var source: Inventory = game.inventory if to_box else _storage()
	var target: Inventory = _storage() if to_box else game.inventory
	if not source.stacks.has(stack):
		return
	var moving := source.take_from_stack(stack, stack.quantity)
	if moving == null:
		return
	var left := target.add(moving)
	if left > 0:
		source.add(ItemStack.new(moving.definition, left, moving.quality, moving.durability))
		game.hud.message("%d adet sığmadı" % left, Hud.RED)
	if redraw:
		refresh()


func _process(_delta: float) -> void:
	# Depodan uzaklasinca kapanir.
	if not entry.is_empty() and game.player.global_position.distance_to(Vector3(entry.cell) + Vector3(0.5, 0, 0.5)) > 4.0:
		close()
