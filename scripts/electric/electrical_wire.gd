extends ElectricalComponent
class_name ElectricalWire

# --- CONFIGURACIÓN EN EL EDITOR ---
@export_group("Especificaciones Físicas")
## esto es el calibre del cable
@export_enum("14 AWG (15A - Iluminación)", "12 AWG (20A - Tomacorrientes)", "10 AWG (30A - Cargas pesadas)") var wire_gauge: int = 1
@export var length_meters: float = 5.0 # Longitud del cable en metros

@export_group("Conexiones de Red")
## Aquí arrastras los nodos (consumidores u otros cables) en el inspector de Godot
@export var connected_components: Array[ElectricalComponent] = []

# --- VARIABLES INTERNAS ---
var wire_resistance: float = 0.0
var max_current: float = 0.0
var voltage_drop: float = 0.0
var thermal_stress: float = 0.0 # Porcentaje de 0.0 a 1.0+ para gráficos

# Tabla de especificaciones reales para cobre a 25°C
const AWG_SPECS = {
	0: {"ohms_per_meter": 0.00828, "max_amps": 15.0}, # 14 AWG
	1: {"ohms_per_meter": 0.00521, "max_amps": 20.0}, # 12 AWG
	2: {"ohms_per_meter": 0.00327, "max_amps": 30.0}  # 10 AWG
}

func _ready() -> void:
	super._ready()
	# 1. Calcular la resistencia estática del cable
	var specs = AWG_SPECS[wire_gauge]
	max_current = specs["max_amps"]
	wire_resistance = specs["ohms_per_meter"] * length_meters

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
				 
	# 5. Calcular el estrés térmico (Para la mecánica visual estilo Poly Bridge)
	thermal_stress = current_draw / max_current
	
	verificar_integridad()

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
	return "[ %s ]\nFlujo: %.2f A / %.1f A\nEstrés: %d%%\nCaída: %.2f V" % [
		name, current_draw, max_current, int(porcentaje_estres), voltage_drop
	]
