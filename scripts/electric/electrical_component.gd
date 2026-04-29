class_name ElectricalComponent
extends Node2D

# Propiedades eléctricas fundamentales
var voltage: float = 0.0
var current: float = 0.0
var resistance: float = 10.0  # Ohms
var power_rating: float = 100.0  # Watts máximos
var is_functional: bool = true

# Estados del dispositivo
enum DeviceState {NORMAL, UNDERVOLTAGE, OVERLOAD, EXPLODED, NO_FUNCTIONAL}
var current_state: DeviceState = DeviceState.NORMAL

func calculate_current(voltage_input: float) -> float: 
	if not is_functional:
		return 0.0
	current = voltage_input / resistance
	
	# Determinar estado
	if voltage_input < 50:  # Umbral de bajo voltaje
		current_state = DeviceState.UNDERVOLTAGE
	elif voltage_input > 240:  # Sobrecarga
		current_state = DeviceState.OVERLOAD
		if voltage_input > 300:
			current_state = DeviceState.EXPLODED
			is_functional = false
	else:
		current_state = DeviceState.NORMAL
	
	return current
