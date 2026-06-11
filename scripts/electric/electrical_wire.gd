extends ElectricalComponent
class_name ElectricalWire

# --- CONFIGURACIÓN EN EL EDITOR ---
@export_group("Especificaciones Físicas")
## esto es el calibre del cable
@export_enum("14 AWG (15A - Iluminación)", "12 AWG (20A - Tomacorrientes)", "10 AWG (30A - Cargas pesadas)") var wire_gauge: int = 1
@export var length_meters: float = 5.0 # Longitud del cable en metros

@export_group("Longitud Dinámica")
## Si está activo, la longitud se calcula automáticamente desde los puntos del Line2D
@export var calculate_length_from_line2d: bool = false
## Multiplicador de calibración: ajusta las unidades del Line2D a metros reales.
## Por ejemplo, si un segmento de 4 unidades equivale a 1 metro, usar 0.25.
@export var length_multiplier: float = 0.025
## Referencia al Line2D visual (Cable_comun). Si se deja vacío, se busca automáticamente
## entre los hijos del nodo.
@export var cable_line: Line2D

@export_group("Conexiones de Red")
## Aquí arrastras los nodos (consumidores u otros cables) en el inspector de Godot
@export var connected_components: Array[ElectricalComponent] = []

# --- VARIABLES INTERNAS ---
var wire_resistance: float = 0.0
var max_current: float = 0.0
var voltage_drop: float = 0.0
var thermal_stress: float = 0.0 # Porcentaje de 0.0 a 1.0+ para gráficos
var _warning_cooldown: float = 0.0
const WARNING_COOLDOWN: float = 3.0

@export_group("Advertencias")
@export var warning_config: WarningParticleConfig

# Tabla de especificaciones reales para cobre a 25°C
const AWG_SPECS = {
	0: {"ohms_per_meter": 0.00828, "max_amps": 15.0}, # 14 AWG
	1: {"ohms_per_meter": 0.00521, "max_amps": 20.0}, # 12 AWG
	2: {"ohms_per_meter": 0.00327, "max_amps": 30.0}  # 10 AWG
}

func _ready() -> void:
	super._ready()
	
	# Si la longitud dinámica está activada, calcular desde el Line2D
	if calculate_length_from_line2d:
		_resolve_cable_line()
		if cable_line != null:
			length_meters = _calculate_line2d_length() * length_multiplier
	
	# 1. Calcular la resistencia estática del cable
	var specs = AWG_SPECS[wire_gauge]
	max_current = specs["max_amps"]
	wire_resistance = specs["ohms_per_meter"] * length_meters

func _process(delta: float) -> void:
	super._process(delta)
	# Update warning cooldown
	if _warning_cooldown > 0.0:
		_warning_cooldown -= delta * Globals.time_scale

# --- MOTOR LÓGICO ---
func update_electrical_state(received_voltage: float) -> void:
	voltage_in = received_voltage
	var total_current_demanded = 0.0
	
	# IMPORTANTE: En una red en árbol, el cable primero debe pasar el voltaje 
	# a sus hijos para ver cuánta corriente "piden". 
	# (Usamos una aproximación rápida asumiendo que el V_out inicial es casi V_in)
	
	for child in connected_components:
		if child != null:
			# Enviamos el voltaje actual a los dispositivos
			child.update_electrical_state(voltage_in)
			# Sumamos la corriente que nos piden de regreso
			total_current_demanded += child.current_draw
			
	# 2. Registramos la corriente total que atraviesa este cable
	current_draw = total_current_demanded
	
	# 3. Calculamos la Caída de Tensión (Ley de Ohm: V = I * R)
	voltage_drop = current_draw * wire_resistance
	
	# 4. Calculamos el voltaje real que llega al final del cable
	var voltage_out = voltage_in - voltage_drop
	
	# (Opcional para mayor precisión) Repasar a los hijos con el voltaje_out corregido
	if voltage_drop > 0.1: # Solo si la caída es significativa
		for child in connected_components:
			if child != null:
				child.update_electrical_state(voltage_out)
		# Recalcular corriente real tras el segundo paso (hijos ahora reportan
		# su corriente al voltaje corregido, no al voltaje original)
		current_draw = 0.0
		for child in connected_components:
			if child != null:
				current_draw += child.current_draw
		# Recalcular caída de tensión con la corriente corregida
		voltage_drop = current_draw * wire_resistance
		 
	# 5. Calcular el estrés térmico (Para la mecánica visual estilo Poly Bridge)
	thermal_stress = current_draw / max_current
	
	verificar_integridad()
	
	# Spawn warning particle if overheating and warnings are enabled
	if thermal_stress > 1.0 and Globals.show_overheating_warnings and _warning_cooldown <= 0.0:
		_spawn_overheating_warning()
		_warning_cooldown = WARNING_COOLDOWN

func _spawn_overheating_warning() -> void:
	var stress_percent = int(thermal_stress * 100)
	WarningParticle.create_warning(
		get_tree().current_scene.get_node("world"),
		global_position + Vector2(0, -40),
		"⚠ SOBRECARGA: %s al %d%%" % [name, stress_percent],
		Color(1.0, 0.4, 0.1),
		warning_config
	)

func verificar_integridad() -> void:
	if thermal_stress > 1.2:
		# Sobrecarga severa: El cable se funde
		print(name + " se ha FUNDIDO por sobrecarga térmica.")
		# Aquí puedes cortar la conexión: connected_components.clear()
	elif thermal_stress > 1.0:
		# Calentamiento peligroso
		print(name + " está sobrecargado. Riesgo de incendio.")

# Sobrescribimos la función de la clase padre
func get_debug_text() -> String:
	var porcentaje_estres = thermal_stress * 100.0
	
	# Reemplazamos la palabra genérica "Cable" por el nombre real del nodo
	return "[ %s ]\nFlujo: %.2f A / %.1f A\nEstrés: %d%%\nCaída: %.2f V\nLongitud: %.1f m" % [
		name, current_draw, max_current, int(porcentaje_estres), voltage_drop, length_meters
	]

# --- LONGITUD DINÁMICA ---

## Busca el Line2D (Cable_comun) entre los hijos si no fue asignado manualmente.
func _resolve_cable_line() -> void:
	if cable_line != null:
		return
	# Buscar entre los hijos directos un Line2D
	for child in get_children():
		if child is Line2D:
			cable_line = child as Line2D
			return
	push_warning("ElectricalWire '%s': no se encontró un Line2D hijo para calcular longitud dinámica." % name)

## Calcula la longitud total del Line2D sumando las distancias entre segmentos consecutivos.
func _calculate_line2d_length() -> float:
	if cable_line == null or cable_line.points.size() < 2:
		return 0.0
	var total_length: float = 0.0
	var points: PackedVector2Array = cable_line.points
	for i in range(points.size() - 1):
		total_length += points[i].distance_to(points[i + 1])
	return total_length
