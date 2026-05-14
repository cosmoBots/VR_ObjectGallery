extends Node3D

const MqttClientScript = preload("res://mqtt_client.gd")
const MQTT_STATUS_CONNECTING := 0
const MQTT_NORMALIZED_DISPLAY_DECIMALS := 4

@export_dir var models_dir: String = "res://models"
@export_file("*.yaml") var model_overrides_file: String = "res://models/models.yaml"
@export_file("*.yaml") var mqtt_config_file: String = "res://models/mqtt.yaml"
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
var _active_filtered_views: Array[Dictionary] = []
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
var _mqtt_config: Dictionary = {}
var _mqtt_client = null
var _mqtt_topic_handlers: Dictionary = {}
var _mqtt_reconnect_timer: float = 0.0


func _default_model_override() -> Dictionary:
	return {
		"fit_height": true,
		"fit_width": true,
		"fit_depth": true,
		"place_on_pedestal": true,
		"show_pedestal": true,
		"show_cookie": false,
		"target_height": 1.5,
		"target_width": 1.5,
		"target_depth": 1.5,
		"rotation_degrees": [0.0, 0.0, 0.0],
		"translation": [0.0, 0.0, 0.0],
		"double_sided": false,
	}


func _ready() -> void:
	_xr_active = _enable_xr_if_available()
	call_deferred("_late_xr_setup")
	_connect_controller_signals()
	_setup_hand_feedback_materials()
	_model_overrides = _load_model_overrides(model_overrides_file)
	_validate_model_overrides(_model_overrides)
	_mqtt_config = _load_mqtt_config(mqtt_config_file)
	_configure_preview_mode()
	_spawn_gallery()
	_setup_mqtt()


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
	_process_mqtt(delta)
	if _xr_active or desktop_stick_simulation_enabled:
		if _xr_active:
			_process_ar_vr_toggle()
			_process_xr_locomotion(delta)
		_process_filtered_views()
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
	environment.ambient_light_color = Color(0.78, 0.8, 0.84, 1.0)
	environment.ambient_light_energy = 1.0
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
	_active_filtered_views.clear()
	_mqtt_topic_handlers.clear()
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
		if _double_sided_for_override(override):
			_apply_double_sided_materials(instance)
		slot.add_child(instance)
		_fit_model_size(
			instance,
			bool(override.get("fit_height", false)),
			float(override.get("target_height", default_target_model_height)),
			bool(override.get("fit_width", false)),
			float(override.get("target_width", default_target_model_height)),
			bool(override.get("fit_depth", false)),
			float(override.get("target_depth", default_target_model_height))
		)
		if _place_on_pedestal_for_override(override):
			_place_model_on_pedestal(instance, pedestal_height)
		_register_filtered_views(instance, override)
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
	if ext == "tscn":
		var source_ext: String = _source_extension_for_resolved_path(path)
		if source_ext == "fbx":
			return fbx_model_scale
		return gltf_model_scale
	if ext == "fbx":
		return fbx_model_scale
	return gltf_model_scale


func _instantiate_model(path: String) -> Node3D:
	var resolved_path: String = _resolve_scene_override_path(path)
	var res := ResourceLoader.load(resolved_path)
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


func _resolve_scene_override_path(path: String) -> String:
	var ext: String = path.get_extension().to_lower()
	if ext == "tscn":
		return path
	if not _is_supported_model_extension(ext):
		return path

	var scene_override_path: String = "%s.tscn" % path.get_basename()
	if ResourceLoader.exists(scene_override_path):
		return scene_override_path
	return path


func _source_extension_for_resolved_path(path: String) -> String:
	var basename: String = path.get_basename()
	var candidates := ["glb", "gltf", "fbx"]
	for candidate in candidates:
		var candidate_path := "%s.%s" % [basename, candidate]
		if FileAccess.file_exists(candidate_path):
			return candidate
	return ""


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


func _fit_model_size(
	model_root: Node3D,
	fit_height: bool,
	desired_height: float,
	fit_width: bool,
	desired_width: float,
	fit_depth: bool,
	desired_depth: float
) -> void:
	var bounds: AABB = _compute_model_local_aabb(model_root)
	if bounds.size == Vector3.ZERO:
		return

	var scale_factor: float = 1.0
	var has_scale_target: bool = false
	if fit_height and bounds.size.y > 0.0001:
		scale_factor = desired_height / bounds.size.y
		has_scale_target = true
	if fit_width:
		if bounds.size.x > 0.0001:
			var width_scale_factor: float = desired_width / bounds.size.x
			if not has_scale_target:
				scale_factor = width_scale_factor
				has_scale_target = true
			elif width_scale_factor < scale_factor:
				scale_factor = width_scale_factor
	if fit_depth and bounds.size.z > 0.0001:
		var depth_scale_factor: float = desired_depth / bounds.size.z
		if not has_scale_target:
			scale_factor = depth_scale_factor
			has_scale_target = true
		elif depth_scale_factor < scale_factor:
			scale_factor = depth_scale_factor
	if not has_scale_target or is_equal_approx(scale_factor, 1.0):
		return

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
	var resolved := _default_model_override()
	if _model_overrides.has(model_name):
		var model_override: Dictionary = _model_overrides[model_name]
		for key in model_override.keys():
			resolved[key] = model_override[key]
	return resolved


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
	return false


func _double_sided_for_override(override: Dictionary) -> bool:
	if override.has("double_sided"):
		return bool(override["double_sided"])
	if override.has("double_side"):
		return bool(override["double_side"])
	return false


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
	var in_filtered_views_section: bool = false
	var current_filtered_view: String = ""

	while not file.eof_reached():
		var raw_line: String = _normalize_yaml_line(file.get_line())
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
			in_filtered_views_section = false
			current_filtered_view = ""
			continue

		if current_model.is_empty():
			continue

		if line.begins_with("    "):
			var entry: String = line.strip_edges()
			if entry == "controls:":
				overrides[current_model]["controls"] = {}
				in_controls_section = true
				current_control = ""
				in_filtered_views_section = false
				current_filtered_view = ""
				continue

			if entry == "filtered_views:":
				overrides[current_model]["filtered_views"] = {}
				in_filtered_views_section = true
				current_filtered_view = ""
				in_controls_section = false
				current_control = ""
				continue

			if in_controls_section and line.begins_with("      ") and not line.begins_with("        "):
				current_control = entry.trim_suffix(":")
				overrides[current_model]["controls"][current_control] = {}
				continue

			if in_filtered_views_section and line.begins_with("      ") and not line.begins_with("        "):
				current_filtered_view = entry.trim_suffix(":")
				overrides[current_model]["filtered_views"][current_filtered_view] = {}
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

			if in_filtered_views_section and current_filtered_view != "" and line.begins_with("        "):
				var filtered_entry: String = line.strip_edges()
				var filtered_sep: int = filtered_entry.find(":")
				if filtered_sep == -1:
					continue

				var filtered_key: String = filtered_entry.substr(0, filtered_sep).strip_edges()
				var filtered_value_text: String = filtered_entry.substr(filtered_sep + 1).strip_edges()
				overrides[current_model]["filtered_views"][current_filtered_view][filtered_key] = _parse_yaml_scalar(filtered_value_text)
				continue

			var sep: int = entry.find(":")
			if sep == -1:
				continue

			var key: String = entry.substr(0, sep).strip_edges()
			var value_text: String = entry.substr(sep + 1).strip_edges()
			overrides[current_model][key] = _parse_yaml_scalar(value_text)
			in_controls_section = false
			current_control = ""
			in_filtered_views_section = false
			current_filtered_view = ""

	return overrides


func _load_mqtt_config(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("No se pudo abrir YAML de MQTT: %s" % path)
		return {}

	var config: Dictionary = {}
	var in_mqtt_section: bool = false
	while not file.eof_reached():
		var raw_line: String = _normalize_yaml_line(file.get_line())
		var line: String = raw_line.split("#", true, 1)[0].rstrip("\r\n\t ")
		if line.is_empty():
			continue
		if line == "mqtt:":
			in_mqtt_section = true
			continue
		if not in_mqtt_section:
			continue
		if not line.begins_with("  ") or line.begins_with("    "):
			continue
		var entry: String = line.strip_edges()
		var sep: int = entry.find(":")
		if sep == -1:
			continue
		var key: String = entry.substr(0, sep).strip_edges()
		var value_text: String = entry.substr(sep + 1).strip_edges()
		config[key] = _parse_yaml_scalar(value_text)
	return config


func _validate_model_overrides(overrides: Dictionary) -> void:
	var used_local_ctrls: Dictionary = {}
	for model_name in overrides.keys():
		var override = overrides[model_name]
		if not (override is Dictionary):
			continue
		var controls = override.get("controls", {})
		if not (controls is Dictionary):
			continue
		for action_name in controls.keys():
			var control_config = controls[action_name]
			if not (control_config is Dictionary):
				continue
			var round_decimals: int = maxi(0, int(control_config.get("round_decimals", 4)))
			if control_config.has("step"):
				var step: float = float(control_config.get("step", 0.0))
				if step <= 0.0:
					push_warning("step no positivo en %s/%s" % [str(model_name), str(action_name)])
				elif not _value_matches_rounding(step, round_decimals):
					push_warning(
						"step %s no es representable exactamente con round_decimals=%d en %s/%s" % [
							str(step),
							round_decimals,
							str(model_name),
							str(action_name),
						]
					)
			var local_ctrl: String = str(control_config.get("local_ctrl", "")).strip_edges()
			if local_ctrl.is_empty():
				continue
			if used_local_ctrls.has(local_ctrl):
				push_warning(
					"local_ctrl repetido '%s' en %s/%s; ya usado en %s" % [
						local_ctrl,
						str(model_name),
						str(action_name),
						str(used_local_ctrls[local_ctrl]),
					]
				)
				continue
			used_local_ctrls[local_ctrl] = "%s/%s" % [str(model_name), str(action_name)]


func _normalize_yaml_line(raw_line: String) -> String:
	# Godot puede guardar ficheros de texto con tabs segun la configuracion
	# del editor. Nuestro YAML usa indentacion por espacios, asi que lo
	# normalizamos antes de parsearlo.
	return raw_line.replace("\t", "    ")


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


func _apply_double_sided_materials(model_root: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model_root, meshes)

	for mesh_instance in meshes:
		if mesh_instance.material_override != null:
			mesh_instance.material_override = _material_with_cull_disabled(mesh_instance.material_override)

		if mesh_instance.mesh == null:
			continue

		var surface_count: int = mesh_instance.mesh.get_surface_count()
		for surface_index in range(surface_count):
			var source_material: Material = mesh_instance.get_surface_override_material(surface_index)
			if source_material == null:
				source_material = mesh_instance.mesh.surface_get_material(surface_index)
			mesh_instance.set_surface_override_material(surface_index, _material_with_cull_disabled(source_material))


func _material_with_cull_disabled(source_material: Material) -> Material:
	if source_material is BaseMaterial3D:
		var material := (source_material as BaseMaterial3D).duplicate(true) as BaseMaterial3D
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		return material

	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.82, 0.82, 0.78, 1.0)
	fallback.roughness = 1.0
	fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
	return fallback


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


func _setup_mqtt() -> void:
	if not bool(_mqtt_config.get("enabled", false)):
		return
	if _mqtt_topic_handlers.is_empty():
		return

	_mqtt_client = MqttClientScript.new()
	_mqtt_client.configure(_mqtt_config)
	_mqtt_client.message.connect(_on_mqtt_message)
	_mqtt_client.connected.connect(_on_mqtt_connected)
	_mqtt_client.disconnected.connect(_on_mqtt_disconnected)
	for topic in _mqtt_topic_handlers.keys():
		_mqtt_client.subscribe(str(topic))
	_mqtt_client.connect_to_broker()


func _process_mqtt(delta: float) -> void:
	if _mqtt_client == null:
		return
	_mqtt_client.poll()
	if _mqtt_client.is_broker_connected():
		_mqtt_reconnect_timer = 0.0
		return
	if _mqtt_client.get_connection_status() == MQTT_STATUS_CONNECTING:
		return
	_mqtt_reconnect_timer -= delta
	if _mqtt_reconnect_timer <= 0.0:
		_mqtt_reconnect_timer = 5.0
		_mqtt_client.connect_to_broker()


func _on_mqtt_connected() -> void:
	print("MQTT conectado a %s:%d" % [str(_mqtt_config.get("host", "")), int(_mqtt_config.get("port", 1883))])


func _on_mqtt_disconnected() -> void:
	push_warning("MQTT desconectado")


func _register_mqtt_filtered_view(override: Dictionary, action_name: String, view_index: int) -> void:
	var mqtt_id: String = str(override.get("mqtt_id", "")).strip_edges()
	if mqtt_id.is_empty():
		return
	var base_topic: String = _mqtt_action_topic(mqtt_id, action_name)
	_mqtt_topic_handlers[base_topic] = {
		"type": "filter",
		"index": view_index,
		"state_topic": "%s/state" % base_topic,
	}


func _register_mqtt_control(override: Dictionary, action_name: String, control_index: int) -> void:
	var mqtt_id: String = str(override.get("mqtt_id", "")).strip_edges()
	if mqtt_id.is_empty():
		return
	var base_topic: String = _mqtt_action_topic(mqtt_id, action_name)
	var norm_topic: String = "%s/norm" % base_topic
	var abs_topic: String = "%s/abs" % base_topic
	var incr_topic: String = "%s/incr" % base_topic
	var step_topic: String = "%s/stp" % base_topic
	var state_topic: String = "%s/state" % base_topic
	_mqtt_topic_handlers[norm_topic] = {
		"type": "control",
		"mode": "norm",
		"index": control_index,
		"state_topic": state_topic,
	}
	_mqtt_topic_handlers[abs_topic] = {
		"type": "control",
		"mode": "abs",
		"index": control_index,
		"state_topic": state_topic,
	}
	_mqtt_topic_handlers[incr_topic] = {
		"type": "control",
		"mode": "incr",
		"index": control_index,
		"state_topic": state_topic,
	}
	if control_index >= 0 and control_index < _active_model_controls.size():
		_mqtt_topic_handlers[step_topic] = {
			"type": "control",
			"mode": "stp",
			"index": control_index,
			"state_topic": state_topic,
		}
		_active_model_controls[control_index]["mqtt_state_topic"] = state_topic


func _on_mqtt_message(topic: String, payload: String) -> void:
	if not _mqtt_topic_handlers.has(topic):
		return
	var handler: Dictionary = _mqtt_topic_handlers[topic]
	match str(handler.get("type", "")):
		"filter":
			_apply_mqtt_filter(handler, payload)
		"control":
			_apply_mqtt_control(handler, payload)
		_:
			pass


func _apply_mqtt_filter(handler: Dictionary, payload: String) -> void:
	var value = _parse_mqtt_bool(payload)
	var state_topic: String = str(handler.get("state_topic", ""))
	if value == null:
		_publish_mqtt_state(state_topic, "outofrange")
		return
	var index: int = int(handler.get("index", -1))
	if index < 0 or index >= _active_filtered_views.size():
		_publish_mqtt_state(state_topic, "outofrange")
		return
	_publish_mqtt_state(state_topic, "ack")
	var filtered_view: Dictionary = _active_filtered_views[index]
	filtered_view["active"] = bool(value)
	_apply_filtered_view_visibility(filtered_view)
	_active_filtered_views[index] = filtered_view
	_publish_mqtt_state(state_topic, "done")


func _apply_mqtt_control(handler: Dictionary, payload: String) -> void:
	var state_topic: String = str(handler.get("state_topic", ""))
	var index: int = int(handler.get("index", -1))
	if index < 0 or index >= _active_model_controls.size():
		_publish_mqtt_state(state_topic, "outofrange")
		return

	var control: Dictionary = _active_model_controls[index]
	var mode: String = str(handler.get("mode", ""))
	if not payload.strip_edges().is_valid_float():
		_publish_mqtt_control_state(control, state_topic, "outofrange", _control_absolute_range(control))
		return
	var raw_requested_value: float = payload.strip_edges().to_float()
	var requested_value: float = _control_round_value(control, raw_requested_value)
	var target_offset: float = float(control.get("offset", 0.0))
	match mode:
		"norm":
			if raw_requested_value < -1.0 or raw_requested_value > 1.0:
				_publish_mqtt_control_state(control, state_topic, "outofrange", _control_absolute_range(control))
				return
			target_offset = _control_target_offset_from_norm(control, raw_requested_value)
		"incr":
			var absolute_value: float = _control_round_value(control, _control_current_absolute_value(control) + requested_value)
			target_offset = _control_offset_from_absolute_value(control, absolute_value)
		"abs":
			var absolute_value: float = _control_round_value(control, requested_value)
			target_offset = _control_offset_from_absolute_value(control, absolute_value)
		"stp":
			if not _is_effective_integer(raw_requested_value):
				_publish_mqtt_control_state(control, state_topic, "outofrange", _control_absolute_range(control))
				return
			var step_count: int = int(round(raw_requested_value))
			var step_size: float = float(control.get("step", 0.0))
			if step_size <= 0.0:
				_publish_mqtt_control_state(control, state_topic, "outofrange", _control_absolute_range(control))
				return
			var absolute_value: float = _control_round_value(control, _control_current_absolute_value(control) + (step_count * step_size))
			target_offset = _control_offset_from_absolute_value(control, absolute_value)
		_:
			_publish_mqtt_control_state(control, state_topic, "outofrange", _control_absolute_range(control))
			return

	if target_offset < float(control.get("min", -1.0)) or target_offset > float(control.get("max", 1.0)):
		_publish_mqtt_control_state(control, state_topic, "outofrange", _control_absolute_range(control))
		return

	_publish_mqtt_control_state(control, state_topic, "ack")
	control["mqtt_target_offset"] = target_offset
	control["mqtt_move_active"] = true
	control["mqtt_state_topic"] = state_topic
	_active_model_controls[index] = control


func _control_target_offset_from_norm(control: Dictionary, normalized_value: float) -> float:
	var target_offset: float = 0.0
	var max_offset: float = float(control.get("max", 1.0))
	var min_offset: float = float(control.get("min", -1.0))
	if normalized_value > 0.0:
		target_offset = normalized_value * max_offset
	elif normalized_value < 0.0:
		target_offset = absf(normalized_value) * min_offset
	else:
		target_offset = 0.0
	target_offset = clampf(target_offset, min_offset, max_offset)
	var absolute_value: float = _control_round_value(control, _control_absolute_value_from_offset(control, target_offset))
	return clampf(_control_offset_from_absolute_value(control, absolute_value), min_offset, max_offset)


func _control_current_absolute_value(control: Dictionary) -> float:
	return _control_absolute_value_from_offset(control, float(control.get("offset", 0.0)))


func _control_current_normalized_value(control: Dictionary) -> float:
	var offset: float = float(control.get("offset", 0.0))
	var max_offset: float = float(control.get("max", 1.0))
	var min_offset: float = float(control.get("min", -1.0))
	if is_zero_approx(offset):
		return 0.0
	if offset > 0.0:
		if is_zero_approx(max_offset):
			return 0.0
		return offset / max_offset
	if offset < 0.0:
		var negative_span: float = absf(min_offset)
		if is_zero_approx(negative_span):
			return 0.0
		return offset / negative_span
	return 0.0


func _control_display_normalized_value(control: Dictionary) -> float:
	return _round_to_decimals(_control_current_normalized_value(control), MQTT_NORMALIZED_DISPLAY_DECIMALS)


func _control_absolute_value_from_offset(control: Dictionary, offset: float) -> float:
	var base_position: Vector3 = control["base_value"]
	var axis_index: int = int(control["axis_index"])
	return base_position[axis_index] + offset


func _control_offset_from_absolute_value(control: Dictionary, absolute_value: float) -> float:
	var base_position: Vector3 = control["base_value"]
	var axis_index: int = int(control["axis_index"])
	return absolute_value - base_position[axis_index]


func _control_absolute_range(control: Dictionary) -> Array:
	return [
		_control_round_value(control, _control_absolute_value_from_offset(control, float(control.get("min", -1.0)))),
		_control_round_value(control, _control_absolute_value_from_offset(control, float(control.get("max", 1.0)))),
	]


func _default_step_for_decimals(decimals: int) -> float:
	return _round_to_decimals(1.0 / pow(10.0, maxi(0, decimals)), maxi(0, decimals))


func _control_round_value(control: Dictionary, value: float) -> float:
	return _round_to_decimals(value, int(control.get("round_decimals", 4)))


func _round_to_decimals(value: float, decimals: int) -> float:
	var safe_decimals: int = maxi(0, decimals)
	var factor: float = pow(10.0, safe_decimals)
	if is_zero_approx(factor):
		return value
	return round(value * factor) / factor


func _value_matches_rounding(value: float, decimals: int) -> bool:
	return is_equal_approx(value, _round_to_decimals(value, decimals))


func _is_effective_integer(value: float) -> bool:
	return is_equal_approx(value, round(value))


func _publish_mqtt_control_state(control: Dictionary, topic: String, result: String, valid_range: Array = []) -> void:
	var payload := {
		"r": result,
		"p": _control_round_value(control, _control_current_absolute_value(control)),
		"n": _control_display_normalized_value(control),
	}
	if not valid_range.is_empty():
		payload["v"] = valid_range
	_publish_mqtt_state(topic, JSON.stringify(payload))


func _publish_mqtt_state(topic: String, state: String) -> void:
	if _mqtt_client == null or topic.is_empty():
		return
	_mqtt_client.publish(topic, state)


func _parse_mqtt_bool(payload: String):
	var value: String = payload.strip_edges().to_lower()
	if value == "true" or value == "1" or value == "yes" or value == "on":
		return true
	if value == "false" or value == "0" or value == "no" or value == "off":
		return false
	return null


func _mqtt_action_topic(mqtt_id: String, action_name: String) -> String:
	var parts := PackedStringArray()
	var prefix: String = _clean_topic_part(str(_mqtt_config.get("topic_prefix", "")))
	if not prefix.is_empty():
		parts.append(prefix)
	parts.append(_clean_topic_part(mqtt_id))
	parts.append(_clean_topic_part(action_name))
	return "/".join(parts)


func _clean_topic_part(value: String) -> String:
	return value.strip_edges().trim_prefix("/").trim_suffix("/")


func _register_filtered_views(model_root: Node3D, override: Dictionary) -> void:
	if not override.has("filtered_views"):
		return

	var filtered_views = override["filtered_views"]
	if not (filtered_views is Dictionary):
		return

	for view_name in filtered_views.keys():
		var view_config = filtered_views[view_name]
		if not (view_config is Dictionary):
			continue

		var group_name: String = str(view_config.get("group", "")).strip_edges()
		if group_name.is_empty():
			continue

		var visuals: Array[VisualInstance3D] = []
		var initial_visibility: Dictionary = {}
		for node in model_root.find_children("*", "VisualInstance3D", true, false):
			var visual := node as VisualInstance3D
			if visual == null:
				continue
			visuals.append(visual)
			initial_visibility[visual] = visual.visible

		var filtered_view := {
			"name": String(view_name),
			"button": str(view_config.get("button", "left_ax_button")),
			"group": group_name,
			"visuals": visuals,
			"initial_visibility": initial_visibility,
			"active": bool(view_config.get("start_active", false)),
			"was_pressed": false,
		}
		_apply_filtered_view_visibility(filtered_view)
		_active_filtered_views.append(filtered_view)
		if bool(view_config.get("mqtt", false)):
			_register_mqtt_filtered_view(override, String(view_name), _active_filtered_views.size() - 1)


func _process_filtered_views() -> void:
	for i in _active_filtered_views.size():
		var filtered_view: Dictionary = _active_filtered_views[i]
		var button_name: String = str(filtered_view["button"])
		var pressed: bool = _control_button_pressed(button_name)
		var was_pressed: bool = bool(filtered_view.get("was_pressed", false))
		if pressed and not was_pressed:
			filtered_view["active"] = not bool(filtered_view.get("active", false))
			_apply_filtered_view_visibility(filtered_view)
		filtered_view["was_pressed"] = pressed
		_active_filtered_views[i] = filtered_view


func _apply_filtered_view_visibility(filtered_view: Dictionary) -> void:
	var visuals: Array[VisualInstance3D] = filtered_view["visuals"]
	var initial_visibility: Dictionary = filtered_view["initial_visibility"]
	var only_group: bool = bool(filtered_view.get("active", false))
	var group_name: String = str(filtered_view["group"])

	for visual in visuals:
		if only_group:
			visual.visible = visual.is_in_group(group_name)
		else:
			visual.visible = bool(initial_visibility.get(visual, true))


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

		var local_ctrl: String = str(control_config.get("local_ctrl", "")).strip_edges()
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
		var transform_type: String = str(control_config.get("transform", "position")).to_lower()
		if transform_type != "position" and transform_type != "rotation":
			push_warning("Transform no soportado en control %s: %s" % [control_name, transform_type])
			continue
		var transform_space: String = str(control_config.get("space", "local")).to_lower()
		if transform_space != "local" and transform_space != "global":
			push_warning("Espacio no soportado en control %s: %s" % [control_name, transform_space])
			continue
		var base_value: Vector3 = _control_current_vector(target_3d, transform_type, transform_space)
		var round_decimals: int = maxi(0, int(control_config.get("round_decimals", 4)))
		var step_value: float = _default_step_for_decimals(round_decimals)
		if control_config.has("step"):
			step_value = float(control_config.get("step", step_value))
			if step_value <= 0.0:
				step_value = _default_step_for_decimals(round_decimals)
		_active_model_controls.append({
			"action_name": String(control_name),
			"local_ctrl": local_ctrl,
			"reset_binding": String(control_config.get("reset_binding", "")),
			"node": target_3d,
			"transform": transform_type,
			"space": transform_space,
			"axis_index": axis_index,
			"axis_name": axis_name,
			"min": float(control_config.get("min", -1.0)),
			"max": float(control_config.get("max", 1.0)),
			"speed": float(control_config.get("speed", 0.1)),
			"round_decimals": round_decimals,
			"step": step_value,
			"base_value": base_value,
			"offset": 0.0,
			"mqtt_move_active": false,
			"mqtt_target_offset": 0.0,
			"mqtt_state_topic": "",
		})
		if bool(control_config.get("mqtt", false)):
			_register_mqtt_control(override, String(control_name), _active_model_controls.size() - 1)


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
				control["mqtt_move_active"] = false
				_apply_control_offset(control)
				if _enable_control_debug_visuals and reset_binding == "right_ax_button":
					_right_debug_material = _debug_black_material
				_active_model_controls[i] = control
				continue

		if bool(control.get("mqtt_move_active", false)):
			var mqtt_target: float = float(control.get("mqtt_target_offset", 0.0))
			var mqtt_speed: float = maxf(absf(float(control.get("speed", 0.1))), 0.0001)
			var mqtt_offset: float = move_toward(float(control["offset"]), mqtt_target, mqtt_speed * delta)
			control["offset"] = mqtt_offset
			_apply_control_offset(control)
			if is_equal_approx(mqtt_offset, mqtt_target):
				control["mqtt_move_active"] = false
				_publish_mqtt_control_state(control, str(control.get("mqtt_state_topic", "")), "done")
			_active_model_controls[i] = control
			continue

		var input_value: float = 0.0
		var local_ctrl: String = str(control.get("local_ctrl", ""))
		if not local_ctrl.is_empty():
			input_value = _control_input_value(local_ctrl)
		if absf(input_value) < 0.15:
			continue

		var new_offset: float = clampf(float(control["offset"]) + (input_value * float(control["speed"]) * delta), float(control["min"]), float(control["max"]))
		control["offset"] = new_offset
		_apply_control_offset(control)

		_active_model_controls[i] = control

	for reset_binding in reset_states.keys():
		_control_button_previous[reset_binding] = reset_states[reset_binding]
	_button_press_events.clear()


func _apply_control_offset(control: Dictionary) -> void:
	var target_node := control["node"] as Node3D
	var base_value: Vector3 = control["base_value"]
	var axis_index: int = int(control["axis_index"])
	var new_value: Vector3 = base_value
	new_value[axis_index] = base_value[axis_index] + float(control["offset"])
	_control_set_vector(target_node, str(control.get("transform", "position")), str(control.get("space", "local")), new_value)


func _control_current_vector(target_node: Node3D, transform_type: String, transform_space: String) -> Vector3:
	if transform_type == "rotation":
		if transform_space == "global":
			return Vector3(
				rad_to_deg(target_node.global_rotation.x),
				rad_to_deg(target_node.global_rotation.y),
				rad_to_deg(target_node.global_rotation.z)
			)
		return target_node.rotation_degrees
	if transform_space == "global":
		return target_node.global_position
	return target_node.position


func _control_set_vector(target_node: Node3D, transform_type: String, transform_space: String, value: Vector3) -> void:
	if transform_type == "rotation":
		if transform_space == "global":
			target_node.global_rotation = Vector3(
				deg_to_rad(value.x),
				deg_to_rad(value.y),
				deg_to_rad(value.z)
			)
		else:
			target_node.rotation_degrees = value
		return

	if transform_space == "global":
		target_node.global_position = value
	else:
		target_node.position = value


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
