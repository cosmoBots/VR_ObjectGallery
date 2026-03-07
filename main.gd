extends Node3D

@export_dir var models_dir: String = "res://models"
@export var columns: int = 4
@export var spacing_x: float = 2.0
@export var spacing_z: float = 2.0
@export var model_scale: float = 1.0
@export var gallery_origin: Vector3 = Vector3(-3.0, 0.0, -3.0)
@export var pedestal_height: float = 0.1

@onready var gallery_root: Node3D = $GalleryRoot

func _ready() -> void:
	_enable_xr_if_available()
	call_deferred("_enable_xr_if_available")
	_spawn_gallery()


func _enable_xr_if_available() -> void:
	var interface: OpenXRInterface = XRServer.find_interface("OpenXR")
	if interface == null:
		return

	if not interface.is_initialized():
		interface.initialize()

	# En Pico, el estado puede no estar listo al primer _ready().
	# Marcamos el viewport para XR para evitar el bucle "No viewport was marked with use_xr".
	get_viewport().use_xr = true


func _spawn_gallery() -> void:
	_clear_children(gallery_root)
	var model_paths: Array[String] = []
	_collect_model_paths(models_dir, model_paths)
	model_paths.sort()

	if model_paths.is_empty():
		push_warning("No se encontraron modelos en %s" % models_dir)
		return

	for i in model_paths.size():
		var model_path := model_paths[i]
		var instance := _instantiate_model(model_path)
		if instance == null:
			push_warning("No se pudo instanciar: %s" % model_path)
			continue

		var slot := Node3D.new()
		slot.name = "Slot_%02d" % i
		slot.position = _grid_position(i)
		gallery_root.add_child(slot)

		var pedestal := _make_pedestal()
		slot.add_child(pedestal)

		instance.scale = Vector3.ONE * model_scale
		instance.position = Vector3(0.0, pedestal_height, 0.0)
		slot.add_child(instance)


func _collect_model_paths(base_dir: String, out_paths: Array[String]) -> void:
	var dir := DirAccess.open(base_dir)
	if dir == null:
		push_warning("No se puede abrir directorio: %s" % base_dir)
		return

	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue

		var full_path := "%s/%s" % [base_dir, name]
		if dir.current_is_dir():
			_collect_model_paths(full_path, out_paths)
		else:
			var ext := name.get_extension().to_lower()
			if ext == "glb" or ext == "gltf":
				out_paths.append(full_path)
	dir.list_dir_end()


func _instantiate_model(path: String) -> Node3D:
	var res := ResourceLoader.load(path)
	if res == null:
		return null

	if res is PackedScene:
		var node := (res as PackedScene).instantiate()
		if node is Node3D:
			return node
		var wrapper := Node3D.new()
		wrapper.add_child(node)
		return wrapper

	if res is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = res as Mesh
		var wrapper_mesh := Node3D.new()
		wrapper_mesh.add_child(mesh_instance)
		return wrapper_mesh

	return null


func _make_pedestal() -> MeshInstance3D:
	var pedestal := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, pedestal_height, 0.8)
	pedestal.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.15, 1.0)
	mat.roughness = 0.9
	pedestal.material_override = mat

	pedestal.position = Vector3(0.0, pedestal_height * 0.5, 0.0)
	return pedestal


func _grid_position(index: int) -> Vector3:
	var col := index % max(columns, 1)
	var row := index / max(columns, 1)
	return gallery_origin + Vector3(float(col) * spacing_x, 0.0, float(row) * spacing_z)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
