extends SceneTree
## Gelistirme araci: bir FPS kaydinin ozetini yazdirir.
##   godot --headless --path fps --script res://tools/dump_save.gd -- <dosya>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for path in args:
		var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if file == null:
			print("acilamadi: ", path)
			continue
		var data: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(data) != TYPE_DICTIONARY:
			print("cozulemedi: ", path)
			continue
		print("== ", path)
		print("  surum ", data.get("version"), " dunya ", data.get("world", {}).get("site"), " / ",
			data.get("world", {}).get("map_id"), " uretici ", data.get("world", {}).get("generator_version"))
		print("  zaman ", data.get("time"))
		print("  oyuncu ", data.get("player", {}).get("position"))
		print("  binalar ", data.get("buildings"))
		print("  degisen hucre ", data.get("world", {}).get("voxels", {}).get("modified", []).size(),
			" hasarli ", data.get("world", {}).get("voxels", {}).get("damage", []).size())
		print("  araclar ", data.get("vehicles", {}).get("entries", []).size(), " usler ", data.get("bases", {}).get("bases", []).size())
		print("  anahtarlar ", data.keys())
	quit()
