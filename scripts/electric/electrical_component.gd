extends Node2D
class_name ElectricalComponent

# Variables eléctricas base
var voltage_in: float = 0.0
var current_draw: float = 0.0
var equivalent_resistance: float = INF

# --- NUEVA UI AVANZADA ---
var ui_container: PanelContainer
var v_box: VBoxContainer
var header_label: Label
var details_label: Label
var is_expanded: bool = false
var is_ui_visible: bool = false

func _ready() -> void:
	add_to_group("electrical_components")
	_setup_ui()

func _setup_ui() -> void:
	# 1. Contenedor principal con fondo
	ui_container = PanelContainer.new()
	add_child(ui_container)
	ui_container.visible = false
	
	# Estilo del panel (Fondo oscuro semitransparente)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7) # Negro con 70% opacidad
	style.set_border_width_all(1)
	style.border_color = Color(0.5, 0.5, 0.5, 0.5)
	style.set_corner_radius_all(4)
	ui_container.add_theme_stylebox_override("panel", style)
	
	# 2. Organización vertical
	v_box = VBoxContainer.new()
	ui_container.add_child(v_box)
	
	# 3. Encabezado (Nombre + Botón de expansión)
	header_label = Label.new()
	header_label.text = "[ %s ]" % name
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_label.mouse_filter = Control.MOUSE_FILTER_STOP # Permite clics
	header_label.gui_input.connect(_on_header_input) # Detectar clic
	v_box.add_child(header_label)
	
	# 4. Detalles (Lo que se contrae/expande)
	details_label = Label.new()
	details_label.visible = is_expanded
	details_label.add_theme_font_size_override("font_size", 12)
	v_box.add_child(details_label)
	
	# Posición inicial
	ui_container.position = Vector2(20, -20)

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		toggle_expansion()

func toggle_expansion() -> void:
	is_expanded = !is_expanded
	if details_label:
		details_label.visible = is_expanded

func _process(_delta: float) -> void:
	if is_ui_visible:
		update_ui_content()

func update_ui_content() -> void:
	# El encabezado ahora puede mostrar un resumen rápido (Voltaje)
	header_label.text = "[ %s ] %.1fV" % [name, voltage_in]
	# Los detalles muestran todo lo demás
	details_label.text = get_debug_text()

func get_debug_text() -> String:
	return "I: %.2f A\nR: %.1f Ω" % [current_draw, equivalent_resistance]

func set_details_visible(visible: bool) -> void:
	is_ui_visible = visible
	ui_container.visible = visible
