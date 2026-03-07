extends Node3D

@export_dir var models_dir: String = "res://models"
@export var columns: int = 4
@export var spacing_x: float = 2.0
@export var spacing_z: float = 2.0
@export var model_scale: float = 1.0
@export var gallery_origin: Vector3 = Vector3(0.0, 0.0, -1.0)
@export var pedestal_height: float = 0.1
@export var target_model_height: float = 1.5
@export var cookie_min_radius: float = 0.18
@export var cookie_margin: float = 0.05

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
	model_paths = _unique_paths(model_paths)

	if model_paths.is_empty():
		push_warning("No se encontraron modelos en %s" % models_dir)
		var debug_slot := Node3D.new()
		debug_slot.name = "Slot_DEBUG_EMPTY"
		debug_slot.position = gallery_origin
		gallery_root.add_child(debug_slot)
		debug_slot.add_child(_make_pedestal())
		debug_slot.add_child(_make_shadow_cookie(null))
		return

	for i in model_paths.size():
		var model_path := model_paths[i]
		var instance := _instantiate_model(model_path)

		var slot := Node3D.new()
		slot.name = "Slot_%02d" % i
		slot.position = _grid_position(i, model_paths.size())
		gallery_root.add_child(slot)

		var pedestal := _make_pedestal()
		slot.add_child(pedestal)

		if instance == null:
			push_warning("No se pudo instanciar: %s" % model_path)
			slot.add_child(_make_shadow_cookie(null))
			continue

		instance.scale = Vector3.ONE * model_scale
		instance.position = Vector3.ZERO
		slot.add_child(instance)
		_fit_model_height(instance, target_model_height)
		_place_model_on_pedestal(instance, pedestal_height)
		slot.add_child(_make_shadow_cookie(instance))


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
			elif ext == "import":
				var source_name: String = name.trim_suffix(".import")
				var source_ext: String = source_name.get_extension().to_lower()
				if source_ext == "glb" or source_ext == "gltf":
					out_paths.append("%s/%s" % [base_dir, source_name])
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


func _make_shadow_cookie(model_root: Node3D) -> MeshInstance3D:
	var radius: float = cookie_min_radius
	if model_root != null:
		var bounds: AABB = _compute_model_local_aabb(model_root)
		if bounds.size != Vector3.ZERO:
			var half_x: float = bounds.size.x * 0.5
			var half_z: float = bounds.size.z * 0.5
			radius = maxf(cookie_min_radius, maxf(half_x, half_z) + cookie_margin)

	var cookie := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.004
	mesh.radial_segments = 32
	cookie.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.15, 1.0)
	mat.roughness = 0.95
	cookie.material_override = mat
	cookie.position = Vector3(0.0, pedestal_height + 0.003, 0.0)
	return cookie


func _grid_position(index: int, total_items: int) -> Vector3:
	var safe_columns: int = maxi(mini(columns, maxi(total_items, 1)), 1)
	var col: int = index % safe_columns
	var row: int = index / safe_columns
	var centered_x: float = (float(col) - (float(safe_columns - 1) * 0.5)) * spacing_x
	return gallery_origin + Vector3(centered_x, 0.0, float(row) * spacing_z)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _unique_paths(paths: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for p in paths:
		if seen.has(p):
			continue
		seen[p] = true
		out.append(p)
	return out


func _fit_model_height(model_root: Node3D, desired_height: float) -> void:
	var bounds: AABB = _compute_model_local_aabb(model_root)
	if bounds.size.y <= 0.0001:
		return

	var scale_factor: float = desired_height / bounds.size.y
	model_root.scale *= Vector3.ONE * scale_factor


func _place_model_on_pedestal(model_root: Node3D, y_base: float) -> void:
	var bounds: AABB = _compute_model_local_aabb(model_root)
	if bounds.size == Vector3.ZERO:
		return

	var center_x: float = bounds.position.x + (bounds.size.x * 0.5)
	var center_z: float = bounds.position.z + (bounds.size.z * 0.5)
	var bottom_y: float = bounds.position.y
	model_root.position += Vector3(-center_x, y_base - bottom_y, -center_z)


func _compute_model_local_aabb(model_root: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model_root, meshes)

	var has_bounds: bool = false
	var combined: AABB = AABB(Vector3.ZERO, Vector3.ZERO)
	var root_inv: Transform3D = model_root.global_transform.affine_inverse()

	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue

		var mesh_aabb: AABB = mesh_instance.get_aabb()
		var to_model_space: Transform3D = root_inv * mesh_instance.global_transform
		var transformed: AABB = _transform_aabb(mesh_aabb, to_model_space)
		if not has_bounds:
			combined = transformed
			has_bounds = true
		else:
			combined = combined.merge(transformed)

	if not has_bounds:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return combined


func _collect_mesh_instances(node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out_meshes.append(node as MeshInstance3D)

	for child in node.get_children():
		_collect_mesh_instances(child, out_meshes)


func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var first: Vector3 = xform * aabb.get_endpoint(0)
	var result: AABB = AABB(first, Vector3.ZERO)

	for i in range(1, 8):
		var p: Vector3 = xform * aabb.get_endpoint(i)
		result = result.expand(p)
	return result
