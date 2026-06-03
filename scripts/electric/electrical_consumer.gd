extends ElectricalComponent
class_name ElectricalConsumer

@export_category("Especificaciones de Fábrica")
@export var nominal_voltage: float = 110.0
@export var nominal_power: float = 1000.0

@export_group("Umbrales de Tolerancia")
@export var min_power_on_percent: float = 0.70  
@export var min_safe_percent: float = 0.90      
@export var max_safe_percent: float = 1.10      
@export var burnout_percent: float = 1.25       

@export_group("Dinámica de Arranque (Inrush)")
@export var inrush_multiplier: float = 2.5 # Consume 2.5 veces más al arrancar
@export var inrush_duration: float = 0.5   # El pico dura medio segundo

@export_category("Control Manual")
@export var has_switch: bool = false      
@export var is_switched_on: bool = true   

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
		internal_resistance = pow(nominal_voltage, 2) / nominal_power
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

	var v_burnout = nominal_voltage * burnout_percent
	var v_over = nominal_voltage * max_safe_percent
	var v_under = nominal_voltage * min_safe_percent
	var v_cutoff = nominal_voltage * min_power_on_percent

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
			
	# Multiplicamos la corriente si el pico está activo
	if is_inrush_active:
		current_draw *= inrush_multiplier

# Esta función espera X segundos y luego relaja el circuito
func _handle_inrush_timer() -> void:
	await get_tree().create_timer(inrush_duration).timeout
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
	var power_consumed = voltage_in * current_draw
	
	# Añadimos un pequeño aviso visual al texto si el Inrush está activo
	var extra_info = " (¡PICO!)" if is_inrush_active else ""
	
	return "%s\nPotencia: %.1f W\nEstado: %s%s" % [base_text, power_consumed, current_state_text, extra_info]

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
