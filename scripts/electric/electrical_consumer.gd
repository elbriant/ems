extends ElectricalComponent
class_name ElectricalConsumer

@export_category("Especificaciones de Fábrica")
@export var nominal_voltage: float = 110.0
@export var nominal_power: float = 1000.0
## Factor de potencia (cos φ). 1.0 = resistivo puro, ~0.65 = motor de inducción típico
@export var power_factor: float = 1.0
## Rendimiento η. 1.0 = sin pérdidas, ~0.75 = motor típico
@export var efficiency: float = 1.0

@export_group("Clasificación del Dispositivo")
## Define el comportamiento físico por defecto (cutoff, inrush, fp).
## Si dejas los overrides numéricos en -1, se usan los valores por clase.
enum DeviceClass { INCANDESCENT, MOTOR, COMPRESSOR, SMPS, MIXED }
@export var device_class: DeviceClass = DeviceClass.MIXED

## Cutoff de bajo voltaje por defecto según clase de dispositivo (fracción de V_nom).
## INCANDESCENT aguanta hasta 60% (filamento se enfría y R baja, peligroso si V sube).
## MOTOR/COMPRESSOR cortan a 85% (protección del bobinado).
## SMPS aguanta hasta 80% (UVLO del capacitor bulk).
const CLASS_CUTOFF: Dictionary = {
	DeviceClass.INCANDESCENT: 0.60,
	DeviceClass.MOTOR: 0.85,
	DeviceClass.COMPRESSOR: 0.85,
	DeviceClass.SMPS: 0.80,
	DeviceClass.MIXED: 0.80,
}

@export_group("Umbrales de Tolerancia")
## -1 = usar CLASS_CUTOFF[device_class]; cualquier otro valor = override manual
@export var min_power_on_percent: float = -1.0
@export var min_safe_percent: float = 0.90
## IEC 60038: el rango normal es ±10% (extremo 1.10 es el límite, no "sobrevoltaje")
@export var max_safe_percent: float = 1.05
@export var burnout_percent: float = 1.25

@export_group("Dinámica de Arranque (Inrush)")
## -1 = usar INRUSH_PROFILES[device_class]
@export var inrush_multiplier: float = -1.0
@export var inrush_duration: float = -1.0

## Perfiles reales de corriente de arranque:
##   Bombilla incandescente fría: R_fría/R_caliente ≈ 1/12 → pico ~12× por 150 ms
##   Motor inducción: 4-8× durante 1-3 s
##   Compresor: 5-7× durante 200-500 ms (con PTC de arranque)
##   SMPS: 1.5-2.5× durante 50-150 ms (carga de C_bulk)
const INRUSH_PROFILES: Dictionary = {
	DeviceClass.INCANDESCENT: [12.0, 0.15],
	DeviceClass.MOTOR: [6.0, 2.0],
	DeviceClass.COMPRESSOR: [6.0, 0.5],
	DeviceClass.SMPS: [2.0, 0.1],
	DeviceClass.MIXED: [2.5, 0.5],
}

@export_category("Control Manual")
@export var has_switch: bool = false
@export var is_switched_on: bool = true
## Marcar como lavadora (usado por la demo de carga residencial para encender
## todas simultáneamente). Al activarse, el nodo se añade al grupo "washers".
@export var is_washer: bool = false

@export_category("Visualización")
@export var visual_sprite: Sprite2D 
@export var visual_light: PointLight2D
@export var flicker_intensity: float = 0.2

enum DeviceState { OFF, UNDERVOLTAGE, NORMAL, OVERVOLTAGE, BROKEN }
var current_state: DeviceState = DeviceState.OFF
var internal_resistance: float = 0.0
var original_sprite_position: Vector2
var original_light_position: Vector2
var original_light_color: Color
var original_light_energy: float
var original_light_scale: float
var toggle_button: CheckButton 

# Variables internas para el pico de corriente
var is_inrush_active: bool = false
var simulation_started: bool = false

func _ready() -> void:
	super._ready() 
	
	if nominal_power > 0:
		# R = V² · cos(φ) · η / P  (modela carga mixta resistiva-inductiva)
		internal_resistance = pow(nominal_voltage, 2) * power_factor * efficiency / nominal_power
		equivalent_resistance = internal_resistance
	else:
		internal_resistance = 0.0
		
	if visual_sprite:
		original_sprite_position = visual_sprite.position

	if visual_light:
		original_light_position = visual_light.position
		original_light_color = visual_light.color
		original_light_energy = visual_light.energy
		original_light_scale = visual_light.texture_scale

	if has_switch:
		add_to_group("switchable_devices")
		toggle_button = CheckButton.new()
		add_child(toggle_button)
		toggle_button.button_pressed = is_switched_on
		toggle_button.position = Vector2(-20, 20)
		toggle_button.z_index = 5
		toggle_button.toggled.connect(_on_switch_toggled)

	if is_washer:
		add_to_group("washers")

	# Evita el pico al iniciar la escena dando un "periodo de gracia" de 0.2 segundos
	get_tree().create_timer(0.2).timeout.connect(func(): simulation_started = true)

func _on_switch_toggled(toggled_on: bool) -> void:
	is_switched_on = toggled_on
	get_tree().call_group("power_sources", "update_network")

func update_electrical_state(received_voltage: float) -> void:
	voltage_in = received_voltage
	
	# Guardamos el estado anterior para saber si nos acabamos de encender
	var previous_state = current_state
	
	if current_state == DeviceState.BROKEN:
		equivalent_resistance = INF
		current_draw = 0.0
		return

	if has_switch and not is_switched_on:
		current_state = DeviceState.OFF
		equivalent_resistance = INF
		current_draw = 0.0
		return

	equivalent_resistance = internal_resistance

	# Si el override manual es -1 (o negativo), usar el cutoff por defecto de la clase
	var effective_cutoff: float = min_power_on_percent
	if effective_cutoff < 0.0:
		effective_cutoff = CLASS_CUTOFF[device_class]

	var v_burnout = nominal_voltage * burnout_percent
	var v_over = nominal_voltage * max_safe_percent
	var v_under = nominal_voltage * min_safe_percent
	var v_cutoff = nominal_voltage * effective_cutoff

	if voltage_in > v_burnout:
		current_state = DeviceState.BROKEN
		equivalent_resistance = INF 
		current_draw = 0.0
		if toggle_button: toggle_button.disabled = true 
		
	elif voltage_in > v_over:
		current_state = DeviceState.OVERVOLTAGE
		current_draw = calculate_current()
		
	elif voltage_in >= v_under and voltage_in <= v_over:
		current_state = DeviceState.NORMAL
		current_draw = calculate_current()
		
	elif voltage_in >= v_cutoff and voltage_in < v_under:
		current_state = DeviceState.UNDERVOLTAGE
		current_draw = calculate_current()
		
	else:
		current_state = DeviceState.OFF
		equivalent_resistance = INF
		current_draw = 0.0

	# --- LÓGICA DEL PICO DE ARRANQUE (INRUSH) ---
	# Si la simulación ya arrancó, estaba apagado, y ahora se encendió (sin quemarse)
	if simulation_started and previous_state == DeviceState.OFF and current_state != DeviceState.OFF and current_state != DeviceState.BROKEN:
		if not is_inrush_active:
			is_inrush_active = true
			_handle_inrush_timer()

	# Resolver perfil de inrush: override manual o perfil por clase
	var effective_inrush_mult: float = inrush_multiplier
	var effective_inrush_dur: float = inrush_duration
	if effective_inrush_mult < 0.0 or effective_inrush_dur < 0.0:
		var profile: Array = INRUSH_PROFILES[device_class]
		if effective_inrush_mult < 0.0:
			effective_inrush_mult = profile[0]
		if effective_inrush_dur < 0.0:
			effective_inrush_dur = profile[1]

	# Multiplicamos la corriente si el pico está activo
	if is_inrush_active:
		current_draw *= effective_inrush_mult

# Esta función espera X segundos y luego relaja el circuito
func _handle_inrush_timer() -> void:
	# Usar la duración efectiva resuelta arriba
	var effective_inrush_dur: float = inrush_duration
	if effective_inrush_dur < 0.0:
		effective_inrush_dur = INRUSH_PROFILES[device_class][1]
	await get_tree().create_timer(effective_inrush_dur).timeout
	is_inrush_active = false
	# Avisamos a la red que el pico terminó para que los cables se estabilicen
	get_tree().call_group("power_sources", "update_network")

func _process(delta: float) -> void:
	super._process(delta) 
	
	if visual_sprite:
		match current_state:
			DeviceState.OFF:
				visual_sprite.modulate = Color(0.3, 0.3, 0.3)
				visual_sprite.position = original_sprite_position
			DeviceState.UNDERVOLTAGE:
				visual_sprite.modulate = Color(0.6, 0.6, 0.4)
				visual_sprite.position = original_sprite_position
			DeviceState.NORMAL:
				visual_sprite.modulate = Color.WHITE
				visual_sprite.position = original_sprite_position
			DeviceState.OVERVOLTAGE:
				visual_sprite.modulate = Color(1.0, 0.6, 0.2)
				visual_sprite.position = original_sprite_position + Vector2(
					randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
				)
			DeviceState.BROKEN:
				visual_sprite.modulate = Color.RED
				visual_sprite.position = original_sprite_position + Vector2(
					randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)
				)

	if visual_light:
		var voltage_ratio: float = 1.0
		if nominal_voltage > 0.0:
			voltage_ratio = voltage_in / nominal_voltage

		var night_boost: float = lerpf(1.3, 1.0, Globals.current_day_factor)
		var flicker_mult: float = 1.0
		var scale_mult: float = 1.0
			
		match current_state:
			DeviceState.OFF:
				visual_light.enabled = false
				visual_light.position = original_light_position
			DeviceState.UNDERVOLTAGE:
				visual_light.enabled = true
				visual_light.color = original_light_color * Color(0.6, 0.6, 0.4)
				scale_mult = 0.5
				flicker_mult = randf_range(1.0 - flicker_intensity, 1.0)
				visual_light.position = original_light_position
			DeviceState.NORMAL:
				visual_light.enabled = true
				visual_light.color = original_light_color
				flicker_mult = 1.0
				visual_light.position = original_light_position
			DeviceState.OVERVOLTAGE:
				visual_light.enabled = true
				visual_light.color = original_light_color * Color(1.0, 0.6, 0.2)
				flicker_mult = randf_range(1.0, 1.0 + flicker_intensity)
				visual_light.position = original_light_position + Vector2(
					randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
				)
			DeviceState.BROKEN:
				visual_light.enabled = false
				visual_light.position = original_light_position + Vector2(
					randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)
				)
		
		# Sobrescribimos flicker si estamos en Inrush
		if is_inrush_active:
			flicker_mult = randf_range(0.8, 1.4)
			
		visual_light.texture_scale = original_light_scale * scale_mult
		visual_light.energy = (original_light_energy * voltage_ratio) * flicker_mult * night_boost

func get_debug_text() -> String:
	var base_text = super.get_debug_text()
	var state_strings = ["APAGADO", "BAJO VOLTAJE", "NORMAL", "SOBREVOLTAJE", "QUEMADO"]
	var current_state_text = state_strings[current_state]
	var apparent_power = voltage_in * current_draw
	# La potencia real consumida de la red es la aparente multiplicada por fp
	# (es la energía que realmente se convierte en trabajo/calor en el dispositivo)
	var real_power = apparent_power * power_factor

	# Añadimos un pequeño aviso visual al texto si el Inrush está activo
	var extra_info = " (¡PICO!)" if is_inrush_active else ""

	return "%s\nP apar.: %.1f VA\nP real: %.1f W (fp=%.2f)\nEstado: %s%s" % [
		base_text, apparent_power, real_power, power_factor, current_state_text, extra_info
	]

func set_switch_state_externally(turn_on: bool) -> void:
	if not has_switch or current_state == DeviceState.BROKEN:
		return
		
	is_switched_on = turn_on
	if toggle_button:
		toggle_button.set_pressed_no_signal(turn_on)


# Calcula la corriente consumida usando la Ley de Ohm (I = V / R)
func calculate_current() -> float:
	# Evitamos dividir por cero o por infinito
	if equivalent_resistance > 0.0 and equivalent_resistance != INF:
		return voltage_in / equivalent_resistance
	
	return 0.0
