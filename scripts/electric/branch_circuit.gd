extends Node
class_name BranchCircuit

# Modela un circuito ramal dentro de un panel de distribución.
# Contiene su propio breaker termomagnético (IEC 60898) y la lista
# de cargas que protege. En la realidad, esto es un "slot" del panel con
# un breaker físico (15A, 20A, 30A) y los cables/consumidores conectados
# aguas abajo de ese breaker.
#
# NOTA: Hereda de Node (no Resource) porque @export con tipos derivados
# de Node (ElectricalComponent) solo es válido en clases Node-derived.
# Cada BranchCircuit se añade como hijo del ElectricalDistributionPanel.

@export var circuit_name: String = "Circuito"
## Corriente nominal del breaker (A). Típicos: 15A iluminación, 20A tomacorrientes, 30A cocina/A/C
@export var rated_current: float = 20.0
## Curva de disparo magnético IEC 60898: B=3-5·In, C=5-10·In, D=10-20·In
@export_enum("Curva B (3-5·In)", "Curva C (5-10·In)", "Curva D (10-20·In)") var magnetic_curve: int = 1
## Cargas (consumidores, cables o sub-paneles) protegidos por este circuito
@export var connected_components: Array[ElectricalComponent] = []

# --- ESTADO DEL BREAKER (interno, no se exporta) ---
var is_tripped: bool = false
var trip_reason: String = ""
var overload_integral: float = 0.0  # Integral I²t simplificada
var current_load: float = 0.0       # Última corriente que circuló (A)

# Umbrales curva IEC 60898 (constantes privadas)
const THERMAL_THRESHOLD_1: float = 1.13
const THERMAL_THRESHOLD_2: float = 1.30
const THERMAL_THRESHOLD_3: float = 1.45
const MAGNETIC_MULTIPLIERS := {0: 4.0, 1: 7.5, 2: 15.0}

# Propaga el voltaje a las cargas si el breaker está cerrado.
# Devuelve la corriente total consumida (0 si el breaker disparó).
# delta: tiempo transcurrido para actualizar la integral térmica.
func propagate(voltage: float, delta: float) -> float:
	if is_tripped:
		current_load = 0.0
		return 0.0

	var total: float = 0.0
	for child in connected_components:
		if child != null:
			child.update_electrical_state(voltage)
			total += child.current_draw

	current_load = total
	_check_trip(delta)
	return current_load

# Verifica si la corriente excede la curva del breaker (lógica IEC 60898
# idéntica a la de ElectricalBreaker, duplicada intencionalmente para
# mantener el BranchCircuit autosuficiente como nodo independiente).
func _check_trip(delta: float) -> void:
	if rated_current <= 0.0:
		return

	var ratio: float = current_load / rated_current

	# 1) Disparo magnético: instantáneo ante cortocircuito
	var magnetic_threshold: float = MAGNETIC_MULTIPLIERS[magnetic_curve]
	if ratio >= magnetic_threshold:
		_trip("CORTOCIRCUITO (%.1f·In)" % ratio)
		return

	# 2) Disparo térmico: integral I²t simplificada
	if ratio > THERMAL_THRESHOLD_1:
		overload_integral += delta
		var trigger_time: float
		if ratio >= THERMAL_THRESHOLD_3:
			trigger_time = 600.0  # 10 min a 1.45·In
		elif ratio >= THERMAL_THRESHOLD_2:
			trigger_time = 3600.0  # 1 h a 1.30·In
		else:
			trigger_time = 3600.0 * 4.0  # 4 h entre 1.13 y 1.30·In
		if overload_integral >= trigger_time:
			_trip("SOBRECARGA TÉRMICA (%.2f·In durante %.0fs)" % [ratio, overload_integral])
			return
	else:
		# Enfriamiento: la integral decae cuando vuelve a rango normal
		overload_integral = max(0.0, overload_integral - delta * 0.5)

func _trip(reason: String) -> void:
	is_tripped = true
	trip_reason = reason
	print("[BranchCircuit '%s'] DISPARADO: %s" % [circuit_name, reason])

# Método público para rearmar el breaker manualmente
func reset() -> void:
	is_tripped = false
	trip_reason = ""
	overload_integral = 0.0
	current_load = 0.0
	print("[BranchCircuit '%s'] REARMADO" % circuit_name)

# Texto de depuración para mostrar en el panel padre
func get_circuit_debug_text() -> String:
	var status: String
	if is_tripped:
		status = "🔴 DISPARADO (%s)" % trip_reason
	else:
		var load_pct: float = (current_load / rated_current) * 100.0 if rated_current > 0.0 else 0.0
		status = "🟢 CERRADO (%.0f%%)" % load_pct
	return "[%s | %.0fA | Curva %s] %s" % [
		circuit_name, rated_current, "BCD"[magnetic_curve], status
	]
