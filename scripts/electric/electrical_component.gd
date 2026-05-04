extends Node2D
class_name ElectricalComponent

# Variables eléctricas fundamentales
var voltage_in: float = 0.0      # Voltios (V) que recibe el nodo
var current_draw: float = 0.0    # Amperios (A) que consume o transmite este nodo
var equivalent_resistance: float = 0.0 # Ohmios (Ω) de este nodo y todo lo conectado a él

# Referencias a otros nodos (para armar la red)
var parent_node: ElectricalComponent = null
var connected_children: Array[ElectricalComponent] = []

# Variables visuales
var debug_label: Label
var is_showing_details: bool = false

func _ready() -> void:
	# 1. Añadimos el componente a un grupo global
	add_to_group("electrical_components")
	
	# 2. Creamos la etiqueta de texto dinámicamente
	debug_label = Label.new()
	add_child(debug_label)
	debug_label.visible = false
	
	# 3. Le damos un estilo básico para que sea legible
	debug_label.set("theme_override_font_sizes/font_size", 12)
	debug_label.set("theme_override_colors/font_outline_color", Color(0, 0, 0, 1))
	debug_label.set("theme_override_constants/outline_size", 4)
	debug_label.position = Vector2(-30, -30) # Lo desfasamos un poco para no tapar el sprite
	debug_label.z_index = 10 # Asegura que se dibuje por encima de los cables

func _process(_delta: float) -> void:
	# Solo consumimos recursos actualizando el texto si está visible
	if is_showing_details and debug_label:
		debug_label.text = get_debug_text()

# Esta función devuelve el texto. Las clases hijas pueden "sobrescribirla" (override)
func get_debug_text() -> String:
	# Añadimos '%s' al principio para inyectar la variable 'name'
	return "[ %s ]\nV: %.1f V\nI: %.2f A" % [name, voltage_in, current_draw]

# Función que será llamada por el botón de la UI
func set_details_visible(visible: bool) -> void:
	is_showing_details = visible
	if debug_label:
		debug_label.visible = visible

# Función abstracta que cada hijo deberá sobrescribir
func update_electrical_state(received_voltage: float) -> void:
	push_warning("update_electrical_state() debe ser sobrescrita por las clases hijas.")

# Función para calcular cuánta corriente "pide" este nodo hacia arriba
func calculate_current() -> float:
	if equivalent_resistance <= 0.0:
		return 0.0
	return voltage_in / equivalent_resistance
