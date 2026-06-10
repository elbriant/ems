extends ElectricalComponent
class_name UninterruptiblePowerSupply

# UPS (Uninterruptible Power Supply / Sistemas de Alimentación Ininterrumpida)
# Proporciona respaldo energético mediante batería durante apagones.
# Modelo básico: transferencia automática, nivel de batería, tiempo de respaldo.
#
# COLOCACIÓN CORRECTA EN LA RED:
#   ElectricalSource → VoltageRegulator → UPS → ElectricalDistributionPanel → cargas
#
# FLUJO DE POTENCIA:
#   - MODO NORMAL: Red → UPS (pasa voltaje) → Cargas. Batería se carga si < 100%.
#   - MODO BATERÍA: Red cae → UPS activa batería → inversor → Cargas.
#   - MODO LOW_BATTERY: Batería baja → aviso → posible apagón.
#   - MODO OVERLOAD: Carga excede capacidad → UPS se apaga para protegerse.

@export_category("Configuración del UPS")
## Voltaje nominal de operación (V). Debe coincidir con la red.
@export var nominal_voltage: float = 220.0
## Capacidad de batería en Watt-horas (Wh). Ejemplos típicos:
##   600VA/360W → ~300Wh (oficina, PC)
##   1500VA/900W → ~700Wh (residencial pequeño)
##   3000VA/2700W → ~1500Wh (residencial completo)
@export var battery_capacity_wh: float = 1500.0
## Potencia máxima de salida en VA (define el tamaño del UPS).
@export var max_output_power: float = 1500.0

@export_category("Transferencia y Protección")
## Tiempo de transferencia a batería (ms). Online: 0ms, Line-interactive: 2-10ms, Standby: 5-15ms
@export var transfer_time_ms: float = 10.0
## Umbral de subtensión para activar batería (fracción de V_nom). 
## 0.85 = 187V para 220V nominal (IEC 60038 rango extremo inferior)
@export_range(0.5, 0.95) var blackout_threshold: float = 0.85
## Voltaje mínimo para reconectar a red (V). Debe ser mayor que blackout_threshold.
@export var reconnect_voltage: float = 190.0
## Tiempo de confirmación antes de reconectar a red (segundos). Evita ciclado por fluctuaciones.
@export var reconnect_delay: float = 1.0

@export_category("Batería")
## Nivel de batería inicial (%). 100 = completamente cargada.
@export_range(0.0, 100.0) var battery_charge_percent: float = 100.0
## Umbral de batería baja (%). Debajo de esto, el UPS apaga las cargas para preservar batería.
@export_range(5.0, 50.0) var low_battery_threshold: float = 20.0
## Velocidad de carga de batería (% por segundo). Típico: 0.5-2% por segundo.
@export var charge_rate: float = 1.0

@export_category("Conexiones")
## Cargas aguas abajo del UPS (típicamente: el panel de distribución)
@export var connected_components: Array[ElectricalComponent] = []

@export_category("Simulación")
## Multiplicador de tiempo para acelerar la simulación de carga/descarga.
## 1.0 = tiempo real, 10.0 = 10x más rápido, 60.0 = 1 minuto = 1 segundo
@export_range(1.0, 3600.0) var time_scale: float = 1.0

# --- ESTADO INTERNO ---
var mode: String = "NORMAL"  # NORMAL | BATTERY | LOW_BATTERY | OVERLOAD | CHARGING | OFF
var is_on_battery: bool = false
var is_charging: bool = false
var current_load_power: float = 0.0
var battery_runtime_remaining: float = 0.0  # segundos
var time_on_battery: float = 0.0  # tiempo acumulado en modo batería
var reconnect_timer: float = 0.0  # tiempo desde que la red volvió a ser estable
var last_output_voltage: float = 0.0
var transfer_in_progress: bool = false
var transfer_timer: float = 0.0

func _ready() -> void:
	super._ready()
	_calculate_runtime()

func _process(delta: float) -> void:
	super._process(delta)
	
	# Aplicar escala de tiempo para acelerar simulación
	var scaled_delta: float = delta * time_scale
	
	# Actualizar timer de reconexión
	if mode == "NORMAL" and reconnect_timer > 0.0:
		reconnect_timer += scaled_delta
		if reconnect_timer >= reconnect_delay:
			reconnect_timer = 0.0
	
	# Actualizar tiempo en batería
	if is_on_battery:
		time_on_battery += scaled_delta
	
	# Actualizar estado de carga de batería
	_update_battery_charge(scaled_delta)
	
	# Actualizar runtime restante si estamos en batería
	if is_on_battery and current_load_power > 0.0:
		_calculate_runtime()

func update_electrical_state(received_voltage: float) -> void:
	voltage_in = received_voltage
	equivalent_resistance = 0.0  # UPS ideal cerrado tiene R ≈ 0
	
	# Evaluar si el voltaje de red es aceptable
	var v_min_acceptable: float = nominal_voltage * blackout_threshold
	
	if received_voltage >= v_min_acceptable:
		# --- RED ESTABLE ---
		if is_on_battery:
			# Si la batería se agotó (modo OFF), reconectar inmediato
			if mode == "OFF":
				_exit_battery_mode()
				_propagate_to_loads(received_voltage)
				return
			
			# Transición de batería → red (con delay)
			if received_voltage >= reconnect_voltage:
				reconnect_timer += get_process_delta_time() if is_inside_tree() else 0.016
				if reconnect_timer >= reconnect_delay:
					_exit_battery_mode()
		else:
			# Red estable, modo normal
			mode = "NORMAL"
			last_output_voltage = received_voltage
			
			# Cargar batería si no está al 100%
			if battery_charge_percent < 100.0:
				is_charging = true
				mode = "CHARGING"
			else:
				is_charging = false
			
			# Propagar voltaje a las cargas
			_propagate_to_loads(received_voltage)
	
	elif received_voltage > 0.0 and received_voltage < v_min_acceptable:
		# --- RED INESTABLE / SUBTENSIÓN ---
		if not is_on_battery:
			# Activar modo batería
			_enter_battery_mode()
		
		# Verificar si la batería se agotó
		if battery_charge_percent <= 0.0:
			mode = "OFF"
			_propagate_to_loads(0.0)
			return
		
		# Verificar si la batería está baja
		if battery_charge_percent <= low_battery_threshold:
			mode = "LOW_BATTERY"
		
		# Propagar voltaje de batería (inversor genera V_nominal)
		_propagate_to_loads(nominal_voltage)
	
	else:
		# --- APAGÓN TOTAL (V = 0) ---
		if not is_on_battery:
			_enter_battery_mode()
		
		# Verificar si la batería se agotó
		if battery_charge_percent <= 0.0:
			mode = "OFF"
			_propagate_to_loads(0.0)
			return
		
		# Verificar si la batería está baja
		if battery_charge_percent <= low_battery_threshold:
			mode = "LOW_BATTERY"
			_propagate_to_loads(0.0)
		else:
			_propagate_to_loads(nominal_voltage)

func _enter_battery_mode() -> void:
	is_on_battery = true
	is_charging = false
	reconnect_timer = 0.0
	time_on_battery = 0.0
	mode = "BATTERY"
	print("[UPS] Modo BATERÍA activado (V_in = %.1f V)" % voltage_in)

func _exit_battery_mode() -> void:
	is_on_battery = false
	is_charging = true
	mode = "NORMAL"
	print("[UPS] Red restaurada, modo NORMAL (V_in = %.1f V)" % voltage_in)

func _propagate_to_loads(voltage: float) -> void:
	var total_current: float = 0.0
	var total_power: float = 0.0
	
	for child in connected_components:
		if child != null:
			child.update_electrical_state(voltage)
			total_current += child.current_draw
			total_power += voltage * child.current_draw
	
	current_draw = total_current
	current_load_power = total_power
	
	# Verificar sobrecarga
	if current_load_power > max_output_power:
		mode = "OVERLOAD"
		print("[UPS] ⚠️ SOBRECARGA: %.1f W > %.1f W" % [current_load_power, max_output_power])

func _update_battery_charge(delta: float) -> void:
	if is_charging and not is_on_battery:
		# Cargar batería desde red
		var charge_amount: float = charge_rate * delta
		battery_charge_percent = minf(battery_charge_percent + charge_amount, 100.0)
	elif is_on_battery and current_load_power > 0.0:
		# Descargar batería
		var previous_percent: float = battery_charge_percent
		# Horas restantes = Capacidad(Wh) * Carga(%) / Potencia(W)
		# Descarga por segundo = 100% / (Horas * 3600)
		var hours_remaining: float = (battery_capacity_wh * battery_charge_percent / 100.0) / current_load_power
		var discharge_per_second: float = 100.0 / (hours_remaining * 3600.0)
		battery_charge_percent = maxf(battery_charge_percent - discharge_per_second * delta, 0.0)
		
		# Si la batería se agotó, propagar 0V a las cargas inmediatamente
		if previous_percent > 0.0 and battery_charge_percent <= 0.0:
			mode = "OFF"
			_propagate_to_loads(0.0)
			print("[UPS] 🔋 Batería AGOTADA - Cortando energía a cargas")

func _calculate_runtime() -> void:
	if current_load_power > 0.0:
		# Horas restantes = Capacidad(Wh) * Carga(%) / Potencia(W)
		var hours: float = (battery_capacity_wh * battery_charge_percent / 100.0) / current_load_power
		battery_runtime_remaining = hours * 3600.0  # Convertir a segundos
	else:
		battery_runtime_remaining = INF  # Sin carga = duración indefinida

# --- FUNCIONES PÚBLICAS ---

## Devuelve información del estado de la batería para debug/UI.
func get_battery_status() -> String:
	var runtime_min: float = battery_runtime_remaining / 60.0
	if battery_runtime_remaining == INF:
		return "🔋 %.0f%% | ⏱️ ∞ (sin carga)" % battery_charge_percent
	elif battery_runtime_remaining > 3600.0:
		var hours: float = battery_runtime_remaining / 3600.0
		return "🔋 %.0f%% | ⏱️ %.1fh" % [battery_charge_percent, hours]
	else:
		return "🔋 %.0f%% | ⏱️ %.0f min" % [battery_charge_percent, runtime_min]

## Estima el tiempo restante de batería en formato legible.
func get_runtime_string() -> String:
	if battery_runtime_remaining == INF:
		return "Indefinido"
	elif battery_runtime_remaining > 3600.0:
		var hours: int = floori(battery_runtime_remaining / 3600.0)
		var mins: int = floori(fmod(battery_runtime_remaining, 3600.0) / 60.0)
		return "%dh %02dmin" % [hours, mins]
	else:
		var mins: int = floori(battery_runtime_remaining / 60.0)
		var secs: int = floori(fmod(battery_runtime_remaining, 60.0))
		return "%dmin %02ds" % [mins, secs]

## Simula una falla de red para pruebas (forzar modo batería).
func simulate_power_failure() -> void:
	if not is_on_battery:
		_enter_battery_mode()
		_propagate_to_loads(nominal_voltage)
		print("[UPS] Simulación de falla de red activada")

## Cancela la simulación de falla (restaura modo normal).
func cancel_power_failure_simulation() -> void:
	if is_on_battery:
		_exit_battery_mode()
		_propagate_to_loads(voltage_in if voltage_in > 0.0 else nominal_voltage)
		print("[UPS] Simulación de falla cancelada")

## Devuelve el porcentaje de carga de la batería.
func get_charge_percent() -> float:
	return battery_charge_percent

## Indica si el UPS está operando en modo batería.
func is_battery_active() -> bool:
	return is_on_battery

## Establece el multiplicador de tiempo para la simulación.
func set_time_scale(scale: float) -> void:
	time_scale = maxf(scale, 1.0)
	print("[UPS] Escala de tiempo: %.1fx" % time_scale)

## Devuelve el multiplicador de tiempo actual.
func get_time_scale() -> float:
	return time_scale

# --- DEBUG ---
func get_debug_text() -> String:
	var base_text: String = super.get_debug_text()
	var mode_text: String = _get_mode_text()
	var battery_text: String = get_battery_status()
	var runtime_text: String = "⏱️ Restante: %s" % get_runtime_string()
	var load_text: String = "⚡ Carga: %.1f W / %.1f W" % [current_load_power, max_output_power]
	var time_scale_text: String = "⏩ Velocidad: %.1fx" % time_scale
	
	return "%s\n%s\n%s\n%s\n%s\n%s\nV_in: %.1f V | V_out: %.1f V" % [
		base_text, mode_text, battery_text, runtime_text, load_text, time_scale_text,
		voltage_in, last_output_voltage
	]

func _get_mode_text() -> String:
	match mode:
		"NORMAL":
			return "🟢 NORMAL (red estable)"
		"CHARGING":
			return "🟡 CARGANDO (%.0f%%)" % battery_charge_percent
		"BATTERY":
			return "🔴 BATERÍA (red caída)"
		"LOW_BATTERY":
			return "🟠 BATERÍA BAJA (%.0f%%)" % battery_charge_percent
		"OVERLOAD":
			return "⚫ SOBRECARGA"
		"OFF":
			return "⚫ APAGADO (sin batería)"
		_:
			return "❓ DESCONOCIDO"
