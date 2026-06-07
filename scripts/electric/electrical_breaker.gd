extends ElectricalComponent
class_name ElectricalBreaker

# Modela un interruptor termomagnético según IEC 60898.
# - Protección térmica: dispara con sobrecargas sostenidas (curva inversa I²t)
# - Protección magnética: disparo instantáneo ante cortocircuito
# El breaker se coloca en serie entre la fuente y un grupo de cargas.

@export_category("Configuración del Breaker")
## Corriente nominal In (A). Valores típicos residenciales: 10, 16, 20, 25, 32, 40
@export var rated_current: float = 20.0
## Curva de disparo magnético IEC 60898:
##   B = 3-5·In  (cargas resistivas, cables largos)
##   C = 5-10·In (uso general, motores pequeños) ← DEFAULT
##   D = 10-20·In (motores grandes, transformadores)
@export_enum("Curva B (3-5·In)", "Curva C (5-10·In)", "Curva D (10-20·In)") var magnetic_curve: int = 1

@export_category("Conexiones")
## Cargas (consumidores, cables o paneles) protegidos por este breaker
@export var connected_components: Array[ElectricalComponent] = []

# --- ESTADO INTERNO ---
var is_tripped: bool = false
var trip_reason: String = ""
var overload_integral: float = 0.0  # Integral de (I/In - 1)²·dt para curva térmica

# Umbrales de la curva IEC 60898 (constantes, no export para no llenar el inspector)
const THERMAL_THRESHOLD_1: float = 1.13  # No dispara en <1h
const THERMAL_THRESHOLD_2: float = 1.30  # Dispara en <1h
const THERMAL_THRESHOLD_3: float = 1.45  # Dispara en <1h más rápido
const MAGNETIC_MULTIPLIERS := {0: 4.0, 1: 7.5, 2: 15.0}  # Promedio del rango por curva

func _ready() -> void:
	super._ready()
	add_to_group("breakers")

func _process(delta: float) -> void:
	super._process(delta)
	if not is_tripped:
		_check_trip(delta)

# Llamado por update_electrical_state() del padre para propagar a los hijos.
# Si está disparado, se comporta como circuito abierto (R=INF).
func update_electrical_state(received_voltage: float) -> void:
	voltage_in = received_voltage

	if is_tripped:
		equivalent_resistance = INF
		current_draw = 0.0
		return

	equivalent_resistance = 0.0  # El breaker ideal en estado cerrado tiene R ≈ 0
	var total_current: float = 0.0
	for child in connected_components:
		if child != null:
			child.update_electrical_state(voltage_in)
			total_current += child.current_draw
	current_draw = total_current

# Verifica si la corriente excede la curva del breaker (térmica + magnética).
# Modelo simplificado de la curva inversa IEC 60898.
func _check_trip(delta: float) -> void:
	if rated_current <= 0.0:
		return

	var ratio: float = current_draw / rated_current

	# 1) DISPARO MAGNÉTICO: instantáneo si supera el umbral de cortocircuito
	var magnetic_threshold: float = MAGNETIC_MULTIPLIERS[magnetic_curve]
	if ratio >= magnetic_threshold:
		_trip("CORTOCIRCUITO (%.1f·In)" % ratio)
		return

	# 2) DISPARO TÉRMICO: integral I²t de la sobrecarga
	# Modelo simplificado: tiempo de disparo t = K / (ratio - 1)²
	# K calibrado para que a 1.30·In dispare en ~1h, a 1.45·In en ~10 min
	if ratio > THERMAL_THRESHOLD_1:
		overload_integral += delta
		# Constante de tiempo según umbral (aproximación de curva IEC)
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
		# Enfriamiento: la integral decae cuando la corriente vuelve a rango normal
		overload_integral = max(0.0, overload_integral - delta * 0.5)

func _trip(reason: String) -> void:
	is_tripped = true
	trip_reason = reason
	equivalent_resistance = INF
	current_draw = 0.0
	print("[Breaker %s] DISPARADO: %s" % [name, reason])

# Método público para rearmar manualmente (un botón en UI, o tras corregir el cortocircuito)
func reset() -> void:
	is_tripped = false
	trip_reason = ""
	overload_integral = 0.0
	equivalent_resistance = 0.0
	print("[Breaker %s] REARMADO" % name)

func get_debug_text() -> String:
	var base_text = super.get_debug_text()
	var status: String
	if is_tripped:
		status = "DISPARADO (%s)" % trip_reason
	else:
		status = "CERRADO"
	var load_pct: float = (current_draw / rated_current) * 100.0 if rated_current > 0.0 else 0.0
	return "%s\nEstado: %s\nCarga: %.1f%% (%.2f A / %.1f A)\nIntegral térm.: %.1f s" % [
		base_text, status, load_pct, current_draw, rated_current, overload_integral
	]
