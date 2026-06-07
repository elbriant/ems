extends ElectricalComponent
class_name ElectricalSplitPhasePanel

@export_category("Conexiones Fase 1 (110V)")
@export var phase_1_components: Array[ElectricalComponent] = []

@export_category("Conexiones Fase 2 (110V)")
@export var phase_2_components: Array[ElectricalComponent] = []

@export_category("Conexiones Bifásicas (220V)")
@export var biphasic_components: Array[ElectricalComponent] = []

# Variables para monitorear el balance
var phase_1_current: float = 0.0
var phase_2_current: float = 0.0
var neutral_current: float = 0.0
var biphasic_current: float = 0.0

func update_electrical_state(received_voltage: float) -> void:
	# Asumimos que received_voltage es el total que viene de la calle (ej. 220V)
	voltage_in = received_voltage
	
	# Dividimos matemáticamente el voltaje
	var single_phase_voltage = voltage_in / 2.0 
	
	phase_1_current = 0.0
	phase_2_current = 0.0
	biphasic_current = 0.0

	# 1. Alimentar Fase 1
	for child in phase_1_components:
		if child != null:
			child.update_electrical_state(single_phase_voltage)
			phase_1_current += child.current_draw

	# 2. Alimentar Fase 2
	for child in phase_2_components:
		if child != null:
			child.update_electrical_state(single_phase_voltage)
			phase_2_current += child.current_draw

	# 3. Alimentar equipos de 220V (Aires acondicionados, cocinas)
	for child in biphasic_components:
		if child != null:
			child.update_electrical_state(voltage_in) # Reciben los 220V completos
			biphasic_current += child.current_draw

	# La corriente del neutro en un sistema split-phase es la diferencia
	# vectorial de las corrientes de fase. Como asumimos misma fase, es |L1 - L2|.
	# Físicamente: si L1 y L2 están desbalanceadas, el neutro lleva la diferencia
	# de vuelta al transformador. Un neutro subdimensionado se calienta
	# aunque las fases estén dentro de su ampacidad.
	neutral_current = abs(phase_1_current - phase_2_current)

	# La corriente total que este tablero le pide al cable de la calle:
	# Los equipos de 220V jalan de ambas fases.
	# Si las fases 110V están desbalanceadas, la carga total de la casa se calcula así:
	var max_phase_current = max(phase_1_current, phase_2_current)
	current_draw = max_phase_current + biphasic_current


func get_debug_text() -> String:
	var base_text = super.get_debug_text()
	return "%s\nL1: %.2f A\nL2: %.2f A\nNeutro: %.2f A\nBifásica 220V: %.2f A" % [
		base_text, phase_1_current, phase_2_current, neutral_current, biphasic_current
	]
