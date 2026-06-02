extends ElectricalComponent
class_name ElectricalSource

@export_category("Configuración de Fuente")
@export var supply_voltage: float = 220.0 # Voltaje base de la red
@export var voltage_drop_factor: float = 0.4 # Factor de caída de tensión por carga (reducido)

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
	# Pass 1: Calcular corriente aproximada
	var total_system_current: float = 0.0
	for child in connected_components:
		if child != null:
			child.update_electrical_state(supply_voltage)
			total_system_current += child.current_draw
	
	# Pass 2: Calcular caída de tensión y propagar el voltaje real
	var voltage_sag = total_system_current * voltage_drop_factor
	voltage_in = clamp(supply_voltage - voltage_sag, 0.0, supply_voltage)
	
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
