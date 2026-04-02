extends Node3D

@export_dir var models_dir: String = "res://models"
@export_file("*.yaml") var model_overrides_file: String = "res://models/models.yaml"
@export var columns: int = 4
@export var spacing_x: float = 2.0
@export var spacing_z: float = 2.0
@export var gltf_model_scale: float = 1.0
@export var fbx_model_scale: float = 1.0
@export var use_unshaded_debug_material: bool = false
@export var gallery_origin: Vector3 = Vector3(0.0, 0.0, -1.0)
@export var pedestal_height: float = 0.1
@export var default_target_model_height: float = 1.5
@export var cookie_min_radius: float = 0.18
@export var cookie_margin: float = 0.05
@export_range(0.5, 2.0, 0.05) var xr_render_target_size_multiplier: float = 1.3
@export var start_in_ar: bool = true
@export var xr_move_speed: float = 1.5
@export var xr_turn_speed_degrees: float = 90.0
@export var xr_stick_deadzone: float = 0.15
@export var desktop_preview_enabled: bool = true
@export var desktop_forward_move_speed: float = 3.5
@export var desktop_strafe_move_speed: float = 1.5
@export var desktop_vertical_move_speed: float = 1.0
@export var desktop_look_sensitivity: float = 0.1
@export var desktop_stick_simulation_enabled: bool = true

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var floor_mesh: MeshInstance3D = $Floor
@onready var gallery_root: Node3D = $GalleryRoot
@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var left_hand_mesh: MeshInstance3D = $XROrigin3D/LeftHand/LeftHandMesh
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var right_hand_mesh: MeshInstance3D = $XROrigin3D/RightHand/RightHandMesh
@onready var desktop_preview: Node3D = $DesktopPreview
@onready var desktop_camera: Camera3D = $DesktopPreview/DesktopCamera3D
@onready var desktop_left_marker: MeshInstance3D = $DesktopPreview/DesktopLeftMarker
@onready var desktop_right_marker: MeshInstance3D = $DesktopPreview/DesktopRightMarker

var _model_overrides: Dictionary = {}
var _xr_active: bool = false
var _desktop_pitch_degrees: float = 0.0
var _active_model_controls: Array[Dictionary] = []
var _control_button_previous: Dictionary = {}
var _button_press_events: Dictionary = {}
var _left_hand_idle_material: StandardMaterial3D
var _right_hand_idle_material: StandardMaterial3D
var _hand_active_material: StandardMaterial3D
var _debug_red_material: StandardMaterial3D
var _debug_brown_material: StandardMaterial3D
var _debug_black_material: StandardMaterial3D
var _right_debug_material: StandardMaterial3D = null
var _enable_control_debug_visuals: bool = false
var _is_ar_mode: bool = false
var _toggle_ar_button_previous: bool = false

func _ready() -> void:
	_xr_active = _enable_xr_if_available()
	call_deferred("_late_xr_setup")
	_connect_controller_signals()
	_setup_hand_feedback_materials()
	_model_overrides = _load_model_overrides(model_overrides_file)
	_configure_preview_mode()
	_spawn_gallery()


func _enable_xr_if_available() -> bool:
	var interface: OpenXRInterface = XRServer.find_interface("OpenXR")
	if interface == null:
		return false

	interface.render_target_size_multiplier = xr_render_target_size_multiplier

	if not interface.is_initialized():
		if not interface.initialize():
			return false

	# En Pico, el estado puede no estar listo al primer _ready().
	# Marcamos el viewport para XR para evitar el bucle "No viewport was marked with use_xr".
	get_viewport().use_xr = true
	return true


func _late_xr_setup() -> void:
	if _xr_active:
		_apply_initial_xr_mode()
		return
	_xr_active = _enable_xr_if_available()
	_configure_preview_mode()
	_apply_initial_xr_mode()


func _configure_preview_mode() -> void:
	var use_desktop_preview: bool = desktop_preview_enabled and not _xr_active
	desktop_preview.visible = use_desktop_preview
	desktop_camera.current = use_desktop_preview
	xr_origin.visible = _xr_active

	if use_desktop_preview:
		desktop_preview.rotation_degrees.x = 0.0
		_desktop_pitch_degrees = 0.0
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _connect_controller_signals() -> void:
	if not left_hand.button_pressed.is_connected(_on_left_controller_button_pressed):
		left_hand.button_pressed.connect(_on_left_controller_button_pressed)
	if not right_hand.button_pressed.is_connected(_on_right_controller_button_pressed):
		right_hand.button_pressed.connect(_on_right_controller_button_pressed)


func _on_left_controller_button_pressed(name: String) -> void:
	_button_press_events[name] = true


func _on_right_controller_button_pressed(name: String) -> void:
	_button_press_events[name] = true


func _setup_hand_feedback_materials() -> void:
	_left_hand_idle_material = StandardMaterial3D.new()
	_left_hand_idle_material.albedo_color = Color(0.2, 0.9, 0.35, 1.0)
	_right_hand_idle_material = StandardMaterial3D.new()
	_right_hand_idle_material.albedo_color = Color(0.2, 0.8, 0.95, 1.0)
	_hand_active_material = StandardMaterial3D.new()
	_hand_active_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_debug_red_material = StandardMaterial3D.new()
	_debug_red_material.albedo_color = Color(1.0, 0.0, 0.0, 1.0)
	_debug_brown_material = StandardMaterial3D.new()
	_debug_brown_material.albedo_color = Color(0.45, 0.26, 0.08, 1.0)
	_debug_black_material = StandardMaterial3D.new()
	_debug_black_material.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	left_hand_mesh.material_override = _left_hand_idle_material
	right_hand_mesh.material_override = _right_hand_idle_material
	desktop_left_marker.material_override = _left_hand_idle_material
	desktop_right_marker.material_override = _right_hand_idle_material


func _update_hand_button_feedback() -> void:
	var left_active: bool = _control_button_pressed("left_trigger_click")
	var right_active: bool = _control_button_pressed("right_trigger_click")
	left_hand_mesh.material_override = _hand_active_material if left_active else _left_hand_idle_material
	right_hand_mesh.material_override = _right_debug_material if _right_debug_material != null else (_hand_active_material if right_active else _right_hand_idle_material)
	desktop_left_marker.material_override = _hand_active_material if left_active else _left_hand_idle_material
	desktop_right_marker.material_override = _right_debug_material if _right_debug_material != null else (_hand_active_material if right_active else _right_hand_idle_material)


func _unhandled_input(event: InputEvent) -> void:
	if not desktop_preview_enabled or _xr_active:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		desktop_preview.rotate_y(deg_to_rad(-motion.relative.x * desktop_look_sensitivity))
		_desktop_pitch_degrees = clampf(_desktop_pitch_degrees - motion.relative.y * desktop_look_sensitivity, -85.0, 85.0)
		desktop_camera.rotation_degrees.x = _desktop_pitch_degrees


func _process(delta: float) -> void:
	if _xr_active or desktop_stick_simulation_enabled:
		if _xr_active:
			_process_ar_vr_toggle()
			_process_xr_locomotion(delta)
		_process_model_controls(delta)
		_update_hand_button_feedback()
	if _xr_active:
		return
	if not desktop_preview_enabled:
		return

	var move_input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move_input.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move_input.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move_input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move_input.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		move_input.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		move_input.y += 1.0
	if Input.is_key_pressed(KEY_F):
		move_input.y -= 1.0
	if Input.is_key_pressed(KEY_R):
		move_input.y += 1.0
	if Input.is_key_pressed(KEY_PAGEDOWN):
		move_input.y -= 1.0
	if Input.is_key_pressed(KEY_PAGEUP):
		move_input.y += 1.0

	if move_input == Vector3.ZERO:
		return

	move_input = move_input.normalized()
	var basis: Basis = desktop_preview.global_transform.basis
	var strafe_movement: Vector3 = basis.x * move_input.x
	var forward_movement: Vector3 = basis.z * move_input.z
	var vertical_movement: Vector3 = Vector3.UP * move_input.y
	desktop_preview.global_position += (strafe_movement * desktop_strafe_move_speed * delta) + (forward_movement * desktop_forward_move_speed * delta) + (vertical_movement * desktop_vertical_move_speed * delta)


func _process_xr_locomotion(delta: float) -> void:
	var stick: Vector2 = left_hand.get_vector2("primary")
	if stick.length() < xr_stick_deadzone:
		return

	var camera_basis: Basis = xr_camera.global_transform.basis
	var forward: Vector3 = -camera_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()

	var right: Vector3 = camera_basis.x
	right.y = 0.0
	if right.length_squared() > 0.0001:
		right = right.normalized()

	var grip_pressed: bool = left_hand.is_button_pressed("grip_click")
	if absf(stick.x) >= xr_stick_deadzone:
		if grip_pressed:
			xr_origin.global_position += right * (stick.x * xr_move_speed * delta)
		else:
			_rotate_xr_origin_around_camera(-stick.x * deg_to_rad(xr_turn_speed_degrees) * delta)

	if absf(stick.y) >= xr_stick_deadzone:
		if forward.length_squared() > 0.0001:
			xr_origin.global_position += forward * (stick.y * xr_move_speed * delta)


func _rotate_xr_origin_around_camera(angle_radians: float) -> void:
	var pivot: Vector3 = xr_camera.global_position
	var origin_position: Vector3 = xr_origin.global_position
	var relative: Vector3 = origin_position - pivot
	relative = relative.rotated(Vector3.UP, angle_radians)
	xr_origin.global_position = pivot + relative
	xr_origin.rotate_y(angle_radians)


func _apply_initial_xr_mode() -> void:
	if not _xr_active:
		return
	if start_in_ar:
		_switch_to_ar()
	else:
		_switch_to_vr()


func _process_ar_vr_toggle() -> void:
	var toggle_pressed: bool = _control_button_pressed("left_by_button")
	if toggle_pressed and not _toggle_ar_button_previous:
		if _is_ar_mode:
			_switch_to_vr()
		else:
			_switch_to_ar()
	_toggle_ar_button_previous = toggle_pressed


func _switch_to_ar() -> bool:
	var xr_interface: XRInterface = XRServer.primary_interface
	if xr_interface == null:
		return false

	if xr_interface.is_passthrough_supported():
		if not xr_interface.start_passthrough():
			return false
	else:
		var modes: PackedInt32Array = xr_interface.get_supported_environment_blend_modes()
		if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		elif XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
		else:
			return false

	get_viewport().transparent_bg = true
	var environment: Environment = world_environment.environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.84, 0.88, 1.0)
	environment.ambient_light_energy = 1.15
	floor_mesh.visible = false
	_is_ar_mode = true
	return true


func _switch_to_vr() -> bool:
	var xr_interface: XRInterface = XRServer.primary_interface
	if xr_interface == null:
		return false

	if xr_interface.is_passthrough_supported():
		xr_interface.stop_passthrough()

	var modes: PackedInt32Array = xr_interface.get_supported_environment_blend_modes()
	if XRInterface.XR_ENV_BLEND_MODE_OPAQUE in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE

	get_viewport().transparent_bg = false
	var environment: Environment = world_environment.environment
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	environment.ambient_light_energy = 1.0
	floor_mesh.visible = true
	_is_ar_mode = false
	return true


func _spawn_gallery() -> void:
	_clear_children(gallery_root)
	_active_model_controls.clear()
	_enable_control_debug_visuals = false
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
		var model_name := model_path.get_file()
		var override: Dictionary = _override_for_model(model_name)
		if bool(override.get("debug_control_visuals", false)):
			_enable_control_debug_visuals = true

		var slot := Node3D.new()
		slot.name = "Slot_%02d" % i
		slot.position = _grid_position(i, model_paths.size())
		gallery_root.add_child(slot)

		var pedestal := _make_pedestal()
		if _show_pedestal_for_override(override):
			slot.add_child(pedestal)

		if instance == null:
			push_warning("No se pudo instanciar: %s" % model_path)
			if _show_cookie_for_override(override):
				slot.add_child(_make_shadow_cookie(null))
			continue

		instance.scale = Vector3.ONE * _model_scale_for_path(model_path, override)
		instance.position = _vector3_from_override(override, "translation", Vector3.ZERO)
		instance.rotation_degrees = _vector3_from_override(override, "rotation_degrees", Vector3.ZERO)
		_apply_material_mode(instance, override)
		if use_unshaded_debug_material:
			_apply_debug_material(instance)
		slot.add_child(instance)
		if override.get("fit_height", false):
			_fit_model_height(instance, float(override.get("target_height", default_target_model_height)))
		if _place_on_pedestal_for_override(override):
			_place_model_on_pedestal(instance, pedestal_height)
		_register_model_controls(instance, override)
		if _show_cookie_for_override(override):
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
			if _is_supported_model_extension(ext):
				out_paths.append(full_path)
			elif ext == "import":
				var source_name: String = name.trim_suffix(".import")
				var source_ext: String = source_name.get_extension().to_lower()
				if _is_supported_model_extension(source_ext):
					out_paths.append("%s/%s" % [base_dir, source_name])
	dir.list_dir_end()


func _is_supported_model_extension(ext: String) -> bool:
	return ext == "glb" or ext == "gltf" or ext == "fbx"


func _model_scale_for_path(path: String, override: Dictionary = {}) -> float:
	if override.has("scale"):
		return float(override["scale"])

	var ext: String = path.get_extension().to_lower()
	if ext == "fbx":
		return fbx_model_scale
	return gltf_model_scale


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


func _override_for_model(model_name: String) -> Dictionary:
	if _model_overrides.has(model_name):
		return _model_overrides[model_name]
	return {}


func _place_on_pedestal_for_override(override: Dictionary) -> bool:
	if override.has("place_on_pedestal"):
		return bool(override["place_on_pedestal"])
	return true


func _show_pedestal_for_override(override: Dictionary) -> bool:
	if override.has("show_pedestal"):
		return bool(override["show_pedestal"])
	return true


func _show_cookie_for_override(override: Dictionary) -> bool:
	if override.has("show_cookie"):
		return bool(override["show_cookie"])
	return true


func _vector3_from_override(data: Dictionary, key: String, default_value: Vector3) -> Vector3:
	if not data.has(key):
		return default_value

	var value = data[key]
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return default_value


func _load_model_overrides(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("No se pudo abrir YAML de modelos: %s" % path)
		return {}

	var overrides: Dictionary = {}
	var in_models_section: bool = false
	var current_model: String = ""
	var in_controls_section: bool = false
	var current_control: String = ""

	while not file.eof_reached():
		var raw_line: String = file.get_line()
		var line: String = raw_line.split("#", true, 1)[0].rstrip("\r\n\t ")
		if line.is_empty():
			continue

		if line == "models:":
			in_models_section = true
			continue

		if not in_models_section:
			continue

		if line.begins_with("  ") and not line.begins_with("    "):
			var model_key: String = line.strip_edges().trim_suffix(":")
			model_key = model_key.trim_prefix("\"").trim_suffix("\"")
			model_key = model_key.trim_prefix("'").trim_suffix("'")
			current_model = model_key
			overrides[current_model] = {}
			in_controls_section = false
			current_control = ""
			continue

		if current_model.is_empty():
			continue

		if line.begins_with("    "):
			var entry: String = line.strip_edges()
			if entry == "controls:":
				overrides[current_model]["controls"] = {}
				in_controls_section = true
				current_control = ""
				continue

			if in_controls_section and line.begins_with("      ") and not line.begins_with("        "):
				current_control = entry.trim_suffix(":")
				overrides[current_model]["controls"][current_control] = {}
				continue

			if in_controls_section and current_control != "" and line.begins_with("        "):
				var control_entry: String = line.strip_edges()
				var control_sep: int = control_entry.find(":")
				if control_sep == -1:
					continue

				var control_key: String = control_entry.substr(0, control_sep).strip_edges()
				var control_value_text: String = control_entry.substr(control_sep + 1).strip_edges()
				overrides[current_model]["controls"][current_control][control_key] = _parse_yaml_scalar(control_value_text)
				continue

			var sep: int = entry.find(":")
			if sep == -1:
				continue

			var key: String = entry.substr(0, sep).strip_edges()
			var value_text: String = entry.substr(sep + 1).strip_edges()
			overrides[current_model][key] = _parse_yaml_scalar(value_text)
			in_controls_section = false
			current_control = ""

	return overrides


func _parse_yaml_scalar(value_text: String):
	if value_text.is_empty():
		return ""

	if value_text == "true":
		return true
	if value_text == "false":
		return false

	if value_text.begins_with("[") and value_text.ends_with("]"):
		var inside: String = value_text.substr(1, value_text.length() - 2).strip_edges()
		if inside.is_empty():
			return []

		var parts: PackedStringArray = inside.split(",", false)
		var out: Array = []
		for part in parts:
			out.append(_parse_yaml_scalar(part.strip_edges()))
		return out

	if (value_text.begins_with("\"") and value_text.ends_with("\"")) or (value_text.begins_with("'") and value_text.ends_with("'")):
		return value_text.substr(1, value_text.length() - 2)

	if value_text.is_valid_float():
		return value_text.to_float()
	if value_text.is_valid_int():
		return value_text.to_int()

	return value_text


func _apply_debug_material(model_root: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model_root, meshes)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.74, 0.68, 1.0)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for mesh_instance in meshes:
		mesh_instance.material_override = mat
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _apply_material_mode(model_root: Node3D, override: Dictionary) -> void:
	var material_mode: String = str(override.get("material_mode", "original")).to_lower()
	if material_mode == "original":
		return

	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model_root, meshes)

	for mesh_instance in meshes:
		if material_mode == "unshaded":
			var unshaded := StandardMaterial3D.new()
			unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			unshaded.albedo_color = Color(0.82, 0.82, 0.78, 1.0)
			mesh_instance.material_override = unshaded
			continue

		if material_mode != "matte":
			continue

		if mesh_instance.mesh == null:
			continue

		var surface_count: int = mesh_instance.mesh.get_surface_count()
		for surface_index in range(surface_count):
			var source_material: Material = mesh_instance.mesh.surface_get_material(surface_index)
			var matte_material := StandardMaterial3D.new()
			matte_material.roughness = 1.0
			matte_material.metallic = 0.0
			matte_material.specular = 0.0
			matte_material.emission_enabled = false
			matte_material.rim_enabled = false
			matte_material.clearcoat_enabled = false
			matte_material.anisotropy_enabled = false

			if source_material is BaseMaterial3D:
				var base := source_material as BaseMaterial3D
				matte_material.albedo_color = base.albedo_color
				matte_material.albedo_texture = base.albedo_texture
				matte_material.transparency = base.transparency
				matte_material.cull_mode = base.cull_mode
			else:
				matte_material.albedo_color = Color(0.82, 0.82, 0.78, 1.0)

			mesh_instance.set_surface_override_material(surface_index, matte_material)


func _register_model_controls(model_root: Node3D, override: Dictionary) -> void:
	if not override.has("controls"):
		return

	var controls = override["controls"]
	if not (controls is Dictionary):
		return

	for control_name in controls.keys():
		var control_config = controls[control_name]
		if not (control_config is Dictionary):
			continue

		var target_name: String = str(control_config.get("target_node", ""))
		if target_name.is_empty():
			continue

		var target_node: Node = model_root.find_child(target_name, true, false)
		if target_node == null:
			push_warning("No se encontro nodo de control: %s" % target_name)
			continue
		if not target_node is Node3D:
			push_warning("Nodo de control no es Node3D: %s" % target_name)
			continue

		var axis_name: String = str(control_config.get("axis", "x")).to_lower()
		var axis_index: int = _axis_index_from_name(axis_name)
		if axis_index == -1:
			push_warning("Eje no soportado en control %s: %s" % [control_name, axis_name])
			continue

		var target_3d := target_node as Node3D
		_active_model_controls.append({
			"binding": String(control_name),
			"reset_binding": String(control_config.get("reset_binding", "")),
			"node": target_3d,
			"axis_index": axis_index,
			"axis_name": axis_name,
			"min": float(control_config.get("min", -1.0)),
			"max": float(control_config.get("max", 1.0)),
			"speed": float(control_config.get("speed", 0.1)),
			"base_position": target_3d.position,
			"offset": 0.0,
		})


func _process_model_controls(delta: float) -> void:
	_right_debug_material = null
	var reset_states: Dictionary = {}
	for control in _active_model_controls:
		var reset_binding: String = str(control.get("reset_binding", ""))
		if reset_binding.is_empty() or reset_states.has(reset_binding):
			continue
		reset_states[reset_binding] = _control_button_pressed(reset_binding)

	if _enable_control_debug_visuals and bool(reset_states.get("right_ax_button", false)):
		_right_debug_material = _debug_red_material

	for i in _active_model_controls.size():
		var control: Dictionary = _active_model_controls[i]
		var reset_binding: String = str(control.get("reset_binding", ""))
		if not reset_binding.is_empty():
			var reset_now: bool = bool(reset_states.get(reset_binding, false)) or bool(_button_press_events.get(reset_binding, false))
			if _enable_control_debug_visuals and reset_binding == "right_ax_button":
				_right_debug_material = _debug_brown_material
			if reset_now:
				control["offset"] = 0.0
				var reset_node := control["node"] as Node3D
				reset_node.position = control["base_position"]
				if _enable_control_debug_visuals and reset_binding == "right_ax_button":
					_right_debug_material = _debug_black_material
				_active_model_controls[i] = control
				continue

		var input_value: float = _control_input_value(str(control["binding"]))
		if absf(input_value) < 0.15:
			continue

		var new_offset: float = clampf(float(control["offset"]) + (input_value * float(control["speed"]) * delta), float(control["min"]), float(control["max"]))
		control["offset"] = new_offset

		var target_node := control["node"] as Node3D
		var base_position: Vector3 = control["base_position"]
		var axis_index: int = int(control["axis_index"])
		var new_position: Vector3 = base_position
		new_position[axis_index] = base_position[axis_index] + new_offset
		target_node.position = new_position

		_active_model_controls[i] = control

	for reset_binding in reset_states.keys():
		_control_button_previous[reset_binding] = reset_states[reset_binding]
	_button_press_events.clear()


func _control_input_value(binding: String) -> float:
	if not _xr_active and desktop_stick_simulation_enabled:
		return _desktop_control_input_value(binding)

	match binding:
		"left_stick_x":
			return left_hand.get_vector2("primary").x
		"left_stick_y":
			return left_hand.get_vector2("primary").y
		"right_stick_x":
			return right_hand.get_vector2("primary").x
		"right_stick_y":
			return right_hand.get_vector2("primary").y
		"left_secondary_x":
			return left_hand.get_vector2("secondary").x
		"left_secondary_y":
			return left_hand.get_vector2("secondary").y
		"right_secondary_x":
			return right_hand.get_vector2("secondary").x
		"right_secondary_y":
			return right_hand.get_vector2("secondary").y
		_:
			return 0.0


func _control_button_pressed(binding: String) -> bool:
	if not _xr_active and desktop_stick_simulation_enabled:
		return _desktop_control_button_pressed(binding)

	match binding:
		"left_stick_click":
			return left_hand.is_button_pressed("primary_click")
		"right_stick_click":
			return right_hand.is_button_pressed("primary_click")
		"left_by_button":
			return left_hand.is_button_pressed("by_button")
		"right_by_button":
			return right_hand.is_button_pressed("by_button")
		"left_ax_button":
			return left_hand.is_button_pressed("ax_button")
		"right_ax_button":
			return right_hand.is_button_pressed("ax_button")
		"left_trigger_click":
			return left_hand.is_button_pressed("trigger_click")
		"right_trigger_click":
			return right_hand.is_button_pressed("trigger_click")
		"left_secondary_click":
			return left_hand.is_button_pressed("secondary_click")
		"right_secondary_click":
			return right_hand.is_button_pressed("secondary_click")
		_:
			return false


func _desktop_control_input_value(binding: String) -> float:
	match binding:
		"left_stick_x":
			return _desktop_axis_value(KEY_J, KEY_L)
		"left_stick_y":
			return _desktop_axis_value(KEY_K, KEY_I)
		"right_stick_x":
			return _desktop_axis_value(KEY_LEFT, KEY_RIGHT)
		"right_stick_y":
			return _desktop_axis_value(KEY_DOWN, KEY_UP)
		"left_secondary_x":
			return _desktop_axis_value(KEY_F, KEY_H)
		"left_secondary_y":
			return _desktop_axis_value(KEY_G, KEY_T)
		"right_secondary_x":
			return _desktop_axis_value(KEY_KP_4, KEY_KP_6)
		"right_secondary_y":
			return _desktop_axis_value(KEY_KP_2, KEY_KP_8)
		_:
			return 0.0


func _desktop_control_button_pressed(binding: String) -> bool:
	match binding:
		"left_stick_click":
			return Input.is_key_pressed(KEY_U)
		"right_stick_click":
			return Input.is_key_pressed(KEY_O)
		"left_by_button":
			return Input.is_key_pressed(KEY_B)
		"right_by_button":
			return Input.is_key_pressed(KEY_N)
		"left_ax_button":
			return Input.is_key_pressed(KEY_1)
		"right_ax_button":
			return Input.is_key_pressed(KEY_2)
		"left_trigger_click":
			return Input.is_key_pressed(KEY_Y)
		"right_trigger_click":
			return Input.is_key_pressed(KEY_P)
		"left_secondary_click":
			return Input.is_key_pressed(KEY_7)
		"right_secondary_click":
			return Input.is_key_pressed(KEY_0)
		_:
			return false


func _desktop_axis_value(negative_key: Key, positive_key: Key) -> float:
	var value: float = 0.0
	if Input.is_key_pressed(negative_key):
		value -= 1.0
	if Input.is_key_pressed(positive_key):
		value += 1.0
	return value


func _axis_index_from_name(axis_name: String) -> int:
	match axis_name:
		"x":
			return 0
		"y":
			return 1
		"z":
			return 2
		_:
			return -1
