extends ElectricalComponent
class_name VoltageRegulator

# Regulador automático de voltaje (AVR / stabilizer).
# Protege las cargas contra sobrevoltaje y subtensión CLIPEANDO el voltaje
# de salida a una banda segura alrededor del voltaje nominal.
#
# COLOCACIÓN CORRECTA EN LA RED:
#   ElectricalSource → VoltageRegulator → ElectricalBreaker → cargas
#
# IMPORTANTE: Un breaker termomagnético protege contra CORRIENTE excesiva
# (sobrecarga, cortocircuito). NO protege contra VOLTAJE excesivo.
# La protección contra sobrevoltaje la realiza un regulador/estabilizador
# o un SPD (Surge Protective Device / varistor). Esto es jerarquía real
# de protecciones en una instalación eléctrica.

@export_category("Configuración del Regulador")
## Voltaje nominal de salida (V). Típicos: 110V, 120V, 220V, 230V, 240V
@export var nominal_voltage: float = 220.0
## Banda de regulación (±% del nominal). Estándar: 0.10 (±10% según IEC 60038)
@export_range(0.01, 0.25) var regulation_band: float = 0.10
## Si V_in cae por debajo de este umbral (fracción de V_nom), el regulador SE APAGA
## totalmente (protección contra subtensión severa, evita daño por bajo voltaje extremo).
## 0 = desactivar esta protección.
@export_range(0.0, 0.9) var blackout_threshold: float = 0.5

@export_category("Conexiones")
## Cargas aguas abajo del regulador (típicamente: el breaker principal del panel)
@export var connected_components: Array[ElectricalComponent] = []

# Estado interno
var is_active: bool = true
var regulation_mode: String = "NORMAL"  # NORMAL | CLIPPING_HIGH | CLIPPING_LOW | BLACKOUT
var last_output_voltage: float = 0.0

func _ready() -> void:
	super._ready()

# Limita el voltaje de salida a la banda [V_min, V_max] y propaga a los hijos.
func update_electrical_state(received_voltage: float) -> void:
	voltage_in = received_voltage
	equivalent_resistance = 0.0  # Regulador ideal cerrado tiene R ≈ 0

	var v_min: float = nominal_voltage * (1.0 - regulation_band)
	var v_max: float = nominal_voltage * (1.0 + regulation_band)
	var blackout_v: float = nominal_voltage * blackout_threshold if blackout_threshold > 0.0 else 0.0

	var voltage_out: float = received_voltage

	if blackout_threshold > 0.0 and received_voltage < blackout_v:
		# Subtensión severa: apagado total (protección de equipos)
		is_active = false
		regulation_mode = "BLACKOUT"
		voltage_out = 0.0
	elif received_voltage > v_max:
		# Sobretensión: clipeo al máximo permitido
		is_active = true
		regulation_mode = "CLIPPING_HIGH"
		voltage_out = v_max
	elif received_voltage < v_min:
		# Subtensión: clipeo al mínimo permitido
		is_active = true
		regulation_mode = "CLIPPING_LOW"
		voltage_out = v_min
	else:
		# Dentro de banda: pasa tal cual
		is_active = true
		regulation_mode = "NORMAL"
		voltage_out = received_voltage

	last_output_voltage = voltage_out

	# Propagar voltaje regulado a las cargas
	if is_active:
		var total_current: float = 0.0
		for child in connected_components:
			if child != null:
				child.update_electrical_state(voltage_out)
				total_current += child.current_draw
		current_draw = total_current
	else:
		# Apagado total: nada consume corriente
		for child in connected_components:
			if child != null:
				# Propagamos 0V para que los hijos registren el blackout
				child.update_electrical_state(0.0)
		current_draw = 0.0

# Modo de operación del regulador para debug
func get_regulation_status() -> String:
	match regulation_mode:
		"NORMAL":
			return "🟢 NORMAL (V_in = %.1f V, pasa tal cual)" % voltage_in
		"CLIPPING_HIGH":
			return "🟡 CLIPEANDO ALTO (V_in = %.1f V → V_out = %.1f V)" % [voltage_in, last_output_voltage]
		"CLIPPING_LOW":
			return "🟡 CLIPEANDO BAJO (V_in = %.1f V → V_out = %.1f V)" % [voltage_in, last_output_voltage]
		"BLACKOUT":
			return "🔴 APAGADO (V_in = %.1f V < umbral %.1f V)" % [voltage_in, nominal_voltage * blackout_threshold]
		_:
			return "DESCONOCIDO"

func get_debug_text() -> String:
	var base_text: String = super.get_debug_text()
	var v_min: float = nominal_voltage * (1.0 - regulation_band)
	var v_max: float = nominal_voltage * (1.0 + regulation_band)
	return "%s\nV_in: %.1f V | V_out: %.1f V\nBanda: %.1f - %.1f V (±%.0f%%)\nEstado: %s" % [
		base_text, voltage_in, last_output_voltage, v_min, v_max, regulation_band * 100.0, get_regulation_status()
	]
