extends ElectricalComponent
class_name ElectricalSource

@export_category("Configuración de Fuente")
@export var supply_voltage: float = 220.0 # Voltaje base de la red

@export_category("Conexiones de Red")
# Ahora sí podrás arrastrar los ElectricalWire principales a esta lista en el inspector
@export var connected_components: Array[ElectricalComponent] = []

func _ready() -> void:
	Globals.global_voltage_changed.connect(change_supply_voltage)
	add_to_group("power_sources")
	# Opcional: Iniciar la red con el voltaje por defecto al arrancar la simulación
	call_deferred("update_network")

# Esta función se llamará cuando muevas el slider en la UI
func change_supply_voltage(new_voltage: float) -> void:
	supply_voltage = new_voltage
	update_network()

# Inicia la reacción en cadena por todo el grafo eléctrico
func update_network() -> void:
	voltage_in = supply_voltage
	var total_system_current: float = 0.0
	
	# 1. Pasada hacia abajo: Entregar voltaje a los hijos directos (los cables principales)
	for child in connected_components:
		if child != null:
			child.update_electrical_state(voltage_in)
			# 2. Pasada hacia arriba: Sumar la corriente que la red nos pide
			total_system_current += child.current_draw
		
	current_draw = total_system_current
	# print("La fuente principal está entregando: " + str(current_draw) + " Amperios")
