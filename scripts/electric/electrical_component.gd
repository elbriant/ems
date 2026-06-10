extends Node2D
class_name ElectricalComponent

# Variables eléctricas base
var voltage_in: float = 0.0
var current_draw: float = 0.0
var equivalent_resistance: float = INF

# --- UI DEBUG PANEL ---
static var _panel_z_counter: int = 100
var ui_container: PanelContainer
var v_box: VBoxContainer
var header_label: Label
var details_label: Label
var separator: HSeparator
var is_expanded: bool = false
var is_ui_visible: bool = false

# --- Customización desde el Editor (Inspector) ---
@export_group("Debug Panel Style")
@export var panel_bg_color: Color = Color(0.08, 0.08, 0.12, 0.88):
	set(value):
		panel_bg_color = value
		_apply_panel_style()

@export var panel_border_color: Color = Color(0.35, 0.55, 0.9, 0.6):
	set(value):
		panel_border_color = value
		_apply_panel_style()

@export_range(0, 10, 1) var panel_border_width: int = 1:
	set(value):
		panel_border_width = value
		_apply_panel_style()

@export_range(0, 16, 1) var panel_corner_radius: int = 6:
	set(value):
		panel_corner_radius = value
		_apply_panel_style()

@export_range(8, 24, 1) var panel_font_size: int = 13:
	set(value):
		panel_font_size = value
		_apply_font_style()

@export var panel_header_color: Color = Color(0.15, 0.18, 0.28, 0.9):
	set(value):
		panel_header_color = value
		_apply_panel_style()

@export var panel_font_color: Color = Color(0.85, 0.88, 0.95, 1.0):
	set(value):
		panel_font_color = value
		_apply_font_style()

func _ready() -> void:
	add_to_group("electrical_components")
	_setup_ui()

func _setup_ui() -> void:
	# 1. Contenedor principal
	ui_container = PanelContainer.new()
	add_child(ui_container)
	ui_container.visible = false
	ui_container.z_index = 100
	
	_apply_panel_style()
	
	# 2. VBox interno con padding
	v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 2)
	ui_container.add_child(v_box)
	
	# 3. Header clickeable
	header_label = Label.new()
	header_label.text = "[ %s ]" % name
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_label.mouse_filter = Control.MOUSE_FILTER_STOP
	header_label.gui_input.connect(_on_header_input)
	v_box.add_child(header_label)
	
	# 4. Separador visual
	separator = HSeparator.new()
	separator.visible = false
	v_box.add_child(separator)
	
	# 5. Detalles expandibles
	details_label = Label.new()
	details_label.visible = is_expanded
	details_label.mouse_filter = Control.MOUSE_FILTER_STOP
	details_label.gui_input.connect(_on_panel_input)
	v_box.add_child(details_label)
	
	_apply_font_style()
	
	# Posición inicial relativa al componente
	ui_container.position = Vector2(20, -20)

func _apply_panel_style() -> void:
	if not ui_container:
		return
	var style = StyleBoxFlat.new()
	style.bg_color = panel_bg_color
	style.set_border_width_all(panel_border_width)
	style.border_color = panel_border_color
	style.set_corner_radius_all(panel_corner_radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	ui_container.add_theme_stylebox_override("panel", style)
	
	# Header: fondo ligeramente más claro
	if header_label:
		var header_style = StyleBoxFlat.new()
		header_style.bg_color = panel_header_color
		header_style.set_corner_radius_all(panel_corner_radius)
		header_style.content_margin_left = 4
		header_style.content_margin_right = 4
		header_style.content_margin_top = 2
		header_style.content_margin_bottom = 2
		header_label.add_theme_stylebox_override("normal", header_style)
		
		# Hover sutil en header
		var header_hover = header_style.duplicate()
		header_hover.bg_color = panel_header_color.lightened(0.15)
		header_label.add_theme_stylebox_override("hover", header_hover)

func _apply_font_style() -> void:
	if header_label:
		header_label.add_theme_font_size_override("font_size", panel_font_size + 1)
		header_label.add_theme_color_override("font_color", panel_font_color)
	if details_label:
		details_label.add_theme_font_size_override("font_size", panel_font_size)
		details_label.add_theme_color_override("font_color", panel_font_color.lightened(0.1))

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		bring_to_front()
		toggle_expansion()

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		bring_to_front()

func bring_to_front() -> void:
	_panel_z_counter += 1
	ui_container.z_index = _panel_z_counter

func toggle_expansion() -> void:
	is_expanded = !is_expanded
	_update_expansion_visual()

func _update_expansion_visual() -> void:
	if details_label:
		details_label.visible = is_expanded
	if separator:
		separator.visible = is_expanded

func _process(_delta: float) -> void:
	if is_ui_visible:
		update_ui_content()

func update_ui_content() -> void:
	header_label.text = "[ %s ] %.1fV" % [name, voltage_in]
	details_label.text = get_debug_text()

func get_debug_text() -> String:
	return "I: %.2f A\nR: %.1f Ω" % [current_draw, equivalent_resistance]

func set_details_visible(visible: bool) -> void:
	is_ui_visible = visible
	ui_container.visible = visible

# --- Expand / Collapse All (llamado por main_engine) ---
func expand_all_details() -> void:
	is_expanded = true
	_update_expansion_visual()

func collapse_all_details() -> void:
	is_expanded = false
	_update_expansion_visual()
