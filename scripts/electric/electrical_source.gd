extends ElectricalComponent
class_name ElectricalSource

@export_category("Configuración de Fuente")
@export var supply_voltage: float = 220.0 # Voltaje base de la red
## Impedancia Thévenin equivalente de la red pública de baja tensión (Ω).
## 0.5 Ω es un valor típico: con 220V da corriente de cortocircuito ~440A,
## dentro del rango real de 200-1000A para instalaciones residenciales.
## Modela la caída V_drop = I_total · Z_source, físicamente más correcto
## que un factor ad-hoc multiplicado por la corriente.
@export var source_impedance: float = 0.5

@export_category("Conexiones de Red")
# Ahora sí podrás arrastrar los ElectricalWire principales a esta lista en el inspector
@export var connected_components: Array[ElectricalComponent] = []

func _ready() -> void:
	# ¡CRÍTICO! Ejecuta la función _ready de ElectricalComponent para crear la UI colapsable
	super._ready() 
	
	Globals.global_voltage_changed.connect(change_supply_voltage)
	add_to_group("power_sources")
	# Iniciar la red con el voltaje por defecto al arrancar la simulación
	call_deferred("update_network")

# Esta función se llamará cuando muevas el slider en la UI
func change_supply_voltage(new_voltage: float) -> void:
	supply_voltage = new_voltage
	update_network()

# Inicia la reacción en cadena por todo el grafo eléctrico
func update_network() -> void:
	# Pass 1: Calcular corriente aproximada con voltaje nominal
	var total_system_current: float = 0.0
	for child in connected_components:
		if child != null:
			child.update_electrical_state(supply_voltage)
			total_system_current += child.current_draw

	# Caída de tensión en la impedancia de la fuente (Ley de Ohm: V = I · Z)
	# Solo se modela la impedancia agregada de la acometida pública;
	# los cables aguas abajo ya aplican su propia caída en ElectricalWire.
	voltage_in = clamp(supply_voltage - total_system_current * source_impedance, 0.0, supply_voltage)

	# Pass 2: Propagar el voltaje corregido por la red.
	# ElectricalWire.update_electrical_state() ya hace la doble pasada local
	# (cables en cascada recalculan voltage_drop en cada nivel).
	total_system_current = 0.0
	for child in connected_components:
		if child != null:
			child.update_electrical_state(voltage_in)
			total_system_current += child.current_draw

	current_draw = total_system_current

# --- NUEVO: Panel de Depuración de la Fuente ---
# Al hacer clic en el nombre de la fuente en el juego, se expandirá esto:
func get_debug_text() -> String:
	var total_power = voltage_in * current_draw
	var lineas_activas = connected_components.size()
	
	return "⚡ DIAGNÓSTICO GLOBAL ⚡\nVoltaje Real: %.1f V\nCorriente Total: %.2f A\nPotencia Total: %.1f W\nLíneas Conectadas: %d" % [
		voltage_in, current_draw, total_power, lineas_activas
	]
