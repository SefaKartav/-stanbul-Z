class_name WorkOrders
extends RefCounted
## Is emri: oyuncunun zanaatkara biraktigi SIRALI uretim kuyrugu
## (Python: game/base/workorder.py).
##
## EMIR VERI, IS SIMULASYON: emir yalnizca "ne, kac tane, kim icin" tutar.
## Malzeme REZERVE EDILMEZ; her gun yeniden bakilir, yoksa emir beklemede
## kalir ve sebebi yazilir. Sira onemlidir: "once bandaj, sonra fisek".

const MAX_QUANTITY := 50
const MAX_ORDERS := 8

var orders: Array = []      # [{recipe_id, quantity, done, settlement_id, blocked}]


func add(recipe_id: String, quantity: int, settlement_id: String) -> String:
	if orders.size() >= MAX_ORDERS:
		return "workorder.queue_full"
	quantity = clampi(quantity, 1, MAX_QUANTITY)
	for order: Dictionary in orders:
		if order.recipe_id == recipe_id and order.settlement_id == settlement_id:
			order.quantity = mini(MAX_QUANTITY, order.quantity + quantity)
			return "workorder.increased"
	orders.append({"recipe_id": recipe_id, "quantity": quantity, "done": 0,
		"settlement_id": settlement_id, "blocked": ""})
	return "workorder.added"


func cancel(index: int) -> bool:
	if index < 0 or index >= orders.size():
		return false
	orders.remove_at(index)
	return true


func next_for(settlement_id: String) -> Dictionary:
	for order: Dictionary in orders:
		if order.settlement_id == settlement_id and order.done < order.quantity:
			return order
	return {}


func prune() -> Array:
	var finished := orders.filter(func(o: Dictionary) -> bool: return o.done >= o.quantity)
	orders = orders.filter(func(o: Dictionary) -> bool: return o.done < o.quantity)
	return finished


func to_dict() -> Dictionary:
	var list: Array = []
	for order: Dictionary in orders:
		list.append({"recipe_id": order.recipe_id, "quantity": order.quantity,
			"done": order.done, "settlement_id": order.settlement_id})
	return {"orders": list}


func load_dict(data: Dictionary, bases: Array, recipes: Dictionary) -> void:
	## BILINMEYEN tarif ya da us sessizce atilir: kaldirilmis bir tarifin
	## emri yuzunden kayit acilmaz hale gelmemeli.
	orders.clear()
	for raw: Variant in data.get("orders", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var recipe_id := str(raw.get("recipe_id", ""))
		var settlement_id := str(raw.get("settlement_id", ""))
		if not recipes.has(recipe_id) or not settlement_id in bases:
			continue
		orders.append({"recipe_id": recipe_id, "quantity": int(raw.get("quantity", 1)),
			"done": int(raw.get("done", 0)), "settlement_id": settlement_id, "blocked": ""})
