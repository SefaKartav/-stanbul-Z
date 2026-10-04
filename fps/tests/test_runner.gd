extends Node
## Basit test kosucusu.
##
## GUT gibi bir eklenti yerine 60 satirlik kendi kosucumuz: dis bagimlilik
## yok, export'a girmez ve basliksiz (headless) calisir:
##     godot --headless --path fps res://tests/test_runner.tscn
## tests/ altindaki her test_*.gd dosyasinin test_ ile baslayan her
## fonksiyonu cagrilir. Test, verilen `t` nesnesine iddia yazar.
## Cikis kodu basarisiz test sayisidir; CI ve derleme betigi buna bakar.

class Asserter:
	var failures: Array = []
	var current := ""
	var checks := 0

	func ok(condition: bool, message: String = "") -> void:
		checks += 1
		if not condition:
			failures.append("%s: %s" % [current, message if message != "" else "kosul saglanmadi"])

	func eq(actual: Variant, expected: Variant, message: String = "") -> void:
		checks += 1
		if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
			failures.append("%s: %s beklenen %s (%s), gelen %s (%s)" % [current, message, expected,
				type_string(typeof(expected)), actual, type_string(typeof(actual))])
		elif actual != expected:
			failures.append("%s: %s beklenen %s, gelen %s" % [current, message, expected, actual])

	func near(actual: float, expected: float, tolerance: float = 0.001, message: String = "") -> void:
		checks += 1
		if absf(actual - expected) > tolerance:
			failures.append("%s: %s beklenen ~%s, gelen %s" % [current, message, expected, actual])

	static func _is_num(value: Variant) -> bool:
		return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _ready() -> void:
	var filter := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var started := Time.get_ticks_msec()
	var asserter := Asserter.new()
	var total := 0
	var files := Array(DirAccess.get_files_at("res://tests"))
	files.sort()
	if not Content.ok():
		print("ICERIK HATALI -- testlerden once duzeltilmeli:")
		for error: String in Content.errors:
			print("  - ", error)
		get_tree().quit(100)
		return
	for file_name: String in files:
		if not file_name.begins_with("test_") or not file_name.ends_with(".gd") or file_name == "test_runner.gd":
			continue
		var script: GDScript = load("res://tests/" + file_name)
		if script == null or not script.can_instantiate():
			asserter.failures.append("%s: betik derlenemedi" % file_name)
			print("FAIL %s (derleme hatasi)" % file_name)
			continue
		var suite: Object = script.new()
		if suite is Node:
			add_child(suite)
		for method: Dictionary in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (file_name + ":" + name).contains(filter):
				continue
			asserter.current = "%s:%s" % [file_name.get_basename(), name]
			var before := asserter.failures.size()
			var checks_before := asserter.checks
			# `await` eszamanli bir cagrida degeri hemen dondurur; kare
			# bekleyen (coroutine) testler ise gercekten beklenir.
			await suite.call(name, asserter)
			# GDScript calisma hatasi fonksiyonu SESSIZCE keser. Hic iddia
			# calistirmayan test gecmis sayilamaz.
			if asserter.checks == checks_before:
				asserter.failures.append("%s: hic iddia calismadi (betik hatasi?)" % asserter.current)
			total += 1
			var status := "ok  " if asserter.failures.size() == before else "FAIL"
			print("%s %s" % [status, asserter.current])
		if suite is Node:
			suite.queue_free()
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	print("")
	for failure: String in asserter.failures:
		print("  x ", failure)
	print("%d test, %d basarisiz, %.2f sn" % [total, asserter.failures.size(), elapsed])
	get_tree().quit(asserter.failures.size())
