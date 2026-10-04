extends RefCounted
## Projedeki HER GDScript dosyasi derleniyor mu? Testi olmayan bir dosyadaki
## sozdizimi hatasi ancak o kod calistiginda (belki oyunun ortasinda)
## ortaya cikardi; burada acilista yakalanir.


func test_all_scripts_compile(t) -> void:
	var files: Array = []
	_collect("res://src", files)
	t.ok(files.size() > 10, "betikler bulunmali")
	for path: String in files:
		var script: GDScript = load(path)
		t.ok(script != null and script.can_instantiate(), "derlenemedi: " + path)


func test_all_shaders_load(t) -> void:
	var files: Array = []
	_collect("res://src", files, ".gdshader")
	for path: String in files:
		var shader: Shader = load(path)
		t.ok(shader != null and shader.code.length() > 0, "shader yuklenemedi: " + path)


func _collect(dir: String, out: Array, extension: String = ".gd") -> void:
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(extension):
			out.append(dir + "/" + file_name)
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + sub, out, extension)
