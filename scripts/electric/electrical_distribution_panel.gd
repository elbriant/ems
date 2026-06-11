extends ElectricalSplitPhasePanel
class_name ElectricalDistributionPanel

# Panel de distribución eléctrica (load center) — versión realista que combina
# un split-phase panel con breakers termomagnéticos IEC 60898 en cada circuito.
# Modela el comportamiento real de un tablero residencial:
#   - L1 (110V) y L2 (110V) con varios circuitos ramales (breaker + cargas)
#   - Bifásica (220V) con sus propios circuitos (estufa, A/C, secadora)
#   - Si un breaker dispara → ese circuito queda fuera (R=INF)
#   - El resto de la casa sigue funcionando (modelo de Selectividad)

@export_category("Circuitos Fase 1 (110V)")
## Cada BranchCircuit tiene su propio breaker (rated_current + curva magnética)
## y su lista de cargas conectadas aguas abajo.
@export var phase_1_circuits: Array[BranchCircuit] = []

@export_category("Circuitos Fase 2 (110V)")
@export var phase_2_circuits: Array[BranchCircuit] = []

@export_category("Circuitos Bifásicos (220V)")
## Para equipos de alta potencia: estufa eléctrica, aire acondicionado,
## secadora, calentador de agua. Reciben los 220V completos.
@export var biphasic_circuits: Array[BranchCircuit] = []

# Estado interno
var _last_delta: float = 0.016  # Fallback ~60 FPS si nunca se ha llamado a _process

func _ready() -> void:
	super._ready()
	# Los BranchCircuit son Nodes (no Resources) y deben estar en el árbol de escena.
	# Si fueron asignados al array por código y aún no tienen parent, los adoptamos.
	_adopt_circuits(phase_1_circuits)
	_adopt_circuits(phase_2_circuits)
	_adopt_circuits(biphasic_circuits)

func _adopt_circuits(circuits: Array[BranchCircuit]) -> void:
	for c in circuits:
		if c != null and c.get_parent() == null:
			add_child(c)

# Helper para crear y registrar un BranchCircuit en una fase específica.
# Devuelve la instancia creada para que el caller pueda asignar connected_components.
func add_circuit(phase: int, p_name: String, p_rated: float, p_curve: int) -> BranchCircuit:
	var circuit := BranchCircuit.new()
	circuit.circuit_name = p_name
	circuit.rated_current = p_rated
	circuit.magnetic_curve = p_curve
	add_child(circuit)
	match phase:
		0: phase_1_circuits.append(circuit)
		1: phase_2_circuits.append(circuit)
		2: biphasic_circuits.append(circuit)
		_: push_warning("ElectricalDistributionPanel: fase inválida %d (use 0=L1, 1=L2, 2=220V)" % phase)
	return circuit

# Sobrescribe update_electrical_state del padre para usar BranchCircuit.
# La firma es la misma; los phase_X_components del padre se IGNORAN.
func update_electrical_state(received_voltage: float) -> void:
	voltage_in = received_voltage
	var single_phase_voltage: float = voltage_in / 2.0
	# Usar el delta real del frame (o el último conocido si se llama desde un timer/signal)
	var dt: float = get_process_delta_time() if is_inside_tree() else _last_delta
	if dt <= 0.0:
		dt = _last_delta

	phase_1_current = 0.0
	phase_2_current = 0.0
	biphasic_current = 0.0

	# 1) Circuitos de Fase 1
	for circuit in phase_1_circuits:
		if circuit != null:
			phase_1_current += circuit.propagate(single_phase_voltage, dt)

	# 2) Circuitos de Fase 2
	for circuit in phase_2_circuits:
		if circuit != null:
			phase_2_current += circuit.propagate(single_phase_voltage, dt)

	# 3) Circuitos bifásicos (220V completos)
	for circuit in biphasic_circuits:
		if circuit != null:
			biphasic_current += circuit.propagate(voltage_in, dt)

	# Corriente del neutro: diferencia de las corrientes de fase (modelo simplificado
	# asumiendo misma fase; en realidad es vectorial pero la magnitud es |L1 - L2|)
	neutral_current = abs(phase_1_current - phase_2_current)

	# Demanda total al cable de la calle (equivalente a 220V):
	# P_total = 110·I_L1 + 110·I_L2 + 220·I_bifasica
	# I_eq = P / 220 = (I_L1 + I_L2) / 2 + I_bifasica
	var total_single_phase_current: float = phase_1_current + phase_2_current
	current_draw = (total_single_phase_current / 2.0) + biphasic_current

# _process se llama cada frame; usamos super para mantener la UI colapsable del padre.
# Solo guardamos el último delta como fallback por si update_electrical_state
# se invoca antes del primer _process.
func _process(delta: float) -> void:
	super._process(delta)
	_last_delta = delta

# --- UTILIDADES PÚBLICAS ---

# Devuelve una lista con los breakers disparados (para que la UI los muestre)
func get_tripped_circuits() -> Array[String]:
	var tripped: Array[String] = []
	for c in phase_1_circuits:
		if c != null and c.is_tripped:
			tripped.append("L1: " + c.get_circuit_debug_text())
	for c in phase_2_circuits:
		if c != null and c.is_tripped:
			tripped.append("L2: " + c.get_circuit_debug_text())
	for c in biphasic_circuits:
		if c != null and c.is_tripped:
			tripped.append("220V: " + c.get_circuit_debug_text())
	return tripped

# Rearma TODOS los breakers disparados del panel (reset masivo)
func reset_all_breakers() -> void:
	for c in phase_1_circuits:
		if c != null and c.is_tripped:
			c.reset()
	for c in phase_2_circuits:
		if c != null and c.is_tripped:
			c.reset()
	for c in biphasic_circuits:
		if c != null and c.is_tripped:
			c.reset()
	# Tras rearmar, recalcular la red
	get_tree().call_group("power_sources", "update_network")

# Rearma un circuito específico por nombre
func reset_circuit(circuit_name: String) -> void:
	for c in phase_1_circuits:
		if c != null and c.circuit_name == circuit_name:
			c.reset()
	for c in phase_2_circuits:
		if c != null and c.circuit_name == circuit_name:
			c.reset()
	for c in biphasic_circuits:
		if c != null and c.circuit_name == circuit_name:
			c.reset()
	get_tree().call_group("power_sources", "update_network")

# --- DEBUG ---
func get_debug_text() -> String:
	var base_text: String = super.get_debug_text()
	var lines: Array[String] = [base_text]

	lines.append("--- Circuitos L1 (110V) ---")
	for c in phase_1_circuits:
		if c != null:
			lines.append(c.get_circuit_debug_text())

	lines.append("--- Circuitos L2 (110V) ---")
	for c in phase_2_circuits:
		if c != null:
			lines.append(c.get_circuit_debug_text())

	lines.append("--- Circuitos 220V ---")
	for c in biphasic_circuits:
		if c != null:
			lines.append(c.get_circuit_debug_text())

	return "\n".join(lines)
