extends SceneTree
## Gelistirme araci: GLB sahnelerinin dugum agacini, materyallerini ve
## animasyonlarini yazdirir.
##   godot --headless --path fps --script res://tools/dump_scene.gd -- <res yolu>...


func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var packed: PackedScene = load(path)
		if packed == null:
			print("yuklenemedi: ", path)
			continue
		var root := packed.instantiate()
		print("== ", path)
		_dump(root, 1)
		root.free()
	quit()


func _dump(node: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + "%s <%s>" % [node.name, node.get_class()]
	if node is Node3D:
		var n := node as Node3D
		line += " pos=%s rot=%s" % [n.position, n.rotation_degrees]
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m is BaseMaterial3D:
					var bm := m as BaseMaterial3D
					line += " [mat '%s' transp=%d alpha=%.2f vcol=%s]" % [bm.resource_name, bm.transparency, bm.albedo_color.a, bm.vertex_color_use_as_albedo]
				else:
					line += " [mat %s]" % m
	if node is AnimationPlayer:
		line += " anims=%s" % [(node as AnimationPlayer).get_animation_list()]
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)
