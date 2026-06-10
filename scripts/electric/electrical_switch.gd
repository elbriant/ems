extends ElectricalComponent
class_name ElectricalSwitch

# Interruptor manual genérico.
# Se coloca en serie en cualquier rama de la red eléctrica.
# Cuando está cerrado (is_closed=true), propaga voltaje a los componentes conectados.
# Cuando está abierto (is_closed=false), se comporta como circuito abierto (R=INF).

@export_category("Interruptor")
## Estado del interruptor: true = cerrado (ON), false = abierto (OFF)
@export var is_closed: bool = true

@export_category("Conexiones")
## Componentes eléctricos aguas abajo (cualquier ElectricalComponent)
@export var connected_components: Array[ElectricalComponent] = []

var total_downstream_current: float = 0.0
var button: Button

func _ready() -> void:
	super._ready()
	_create_button()

func _create_button() -> void:
	button = Button.new()
	button.text = "ON" if is_closed else "OFF"
	button.position = Vector2(-30, 20)
	button.z_index = 5
	button.custom_minimum_size = Vector2(60, 30)
	_update_button_style()
	button.pressed.connect(_on_button_pressed)
	add_child(button)

func _on_button_pressed() -> void:
	is_closed = not is_closed
	button.text = "ON" if is_closed else "OFF"
	_update_button_style()
	get_tree().call_group("power_sources", "update_network")

func _update_button_style() -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	if is_closed:
		style.bg_color = Color(0.15, 0.65, 0.15, 0.9)
		style.border_color = Color(0.2, 0.8, 0.2, 1.0)
	else:
		style.bg_color = Color(0.65, 0.15, 0.15, 0.9)
		style.border_color = Color(0.8, 0.2, 0.2, 1.0)
	style.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = hover_style.bg_color.lightened(0.15)
	button.add_theme_stylebox_override("hover", hover_style)

	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color.WHITE)

func update_electrical_state(received_voltage: float) -> void:
	voltage_in = received_voltage

	if not is_closed:
		equivalent_resistance = INF
		current_draw = 0.0
		total_downstream_current = 0.0
		for child in connected_components:
			if child != null:
				child.update_electrical_state(0.0)
		return

	equivalent_resistance = 0.0
	total_downstream_current = 0.0
	for child in connected_components:
		if child != null:
			child.update_electrical_state(voltage_in)
			total_downstream_current += child.current_draw
	current_draw = total_downstream_current

func get_debug_text() -> String:
	var base_text = super.get_debug_text()
	var estado: String = "CERRADO (ON)" if is_closed else "ABIERTO (OFF)"
	var potencia: float = voltage_in * current_draw
	return "%s\nEstado: %s\nI downstream: %.2f A\nP: %.1f W" % [
		base_text, estado, total_downstream_current, potencia
	]
