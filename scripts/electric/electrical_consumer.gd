extends ElectricalComponent
class_name ElectricalConsumer

@export_category("Especificaciones de Fábrica")
@export var nominal_voltage: float = 110.0
@export var nominal_power: float = 1000.0

@export_group("Umbrales de Tolerancia")
# Por debajo del 70% (ej. < 77V), no tiene energía suficiente para arrancar
@export var min_power_on_percent: float = 0.70  
# Por debajo del 90%, arranca pero funciona mal (Bajo Voltaje)
@export var min_safe_percent: float = 0.90      
# Por encima del 110%, sufre estrés térmico (Sobrevoltaje)
@export var max_safe_percent: float = 1.10      
# Por encima del 125% (ej. > 137V), se quema irreversiblemente
@export var burnout_percent: float = 1.25       

@export_category("Control Manual")
@export var has_switch: bool = false      
@export var is_switched_on: bool = true   

@export_category("Visualización")
@export var visual_sprite: Sprite2D 

enum DeviceState { OFF, UNDERVOLTAGE, NORMAL, OVERVOLTAGE, BROKEN }
var current_state: DeviceState = DeviceState.OFF
var internal_resistance: float = 0.0
var original_sprite_position: Vector2
var toggle_button: CheckButton 

func _ready() -> void:
	super._ready() 
	
	if nominal_power > 0:
		internal_resistance = pow(nominal_voltage, 2) / nominal_power
		equivalent_resistance = internal_resistance
	else:
		internal_resistance = 0.0
		
	if visual_sprite:
		original_sprite_position = visual_sprite.position

	if has_switch:
		add_to_group("switchable_devices") 
		toggle_button = CheckButton.new()
		add_child(toggle_button)
		toggle_button.button_pressed = is_switched_on
		toggle_button.position = Vector2(-20, 20) 
		toggle_button.z_index = 5
		toggle_button.toggled.connect(_on_switch_toggled)

func _on_switch_toggled(toggled_on: bool) -> void:
	is_switched_on = toggled_on
	get_tree().call_group("power_sources", "update_network")

func update_electrical_state(received_voltage: float) -> void:
	voltage_in = received_voltage
	
	# 1. Chequeos de ruptura o apagado manual
	if current_state == DeviceState.BROKEN:
		equivalent_resistance = INF
		current_draw = 0.0
		return

	if has_switch and not is_switched_on:
		current_state = DeviceState.OFF
		equivalent_resistance = INF
		current_draw = 0.0
		return

	# Restauramos la resistencia base
	equivalent_resistance = internal_resistance

	# 2. Evaluación de los umbrales de tensión
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
		# El voltaje es menor al v_cutoff (ej. 60V). El dispositivo se apaga.
		current_state = DeviceState.OFF
		equivalent_resistance = INF # No consume porque el circuito interno no cierra
		current_draw = 0.0

# --- LÓGICA VISUAL EN TIEMPO REAL ---
func _process(delta: float) -> void:
	super._process(delta) 
	
	if visual_sprite:
		match current_state:
			DeviceState.OFF:
				# Totalmente inactivo y sin consumo
				visual_sprite.modulate = Color(0.3, 0.3, 0.3)
				visual_sprite.position = original_sprite_position
				
			DeviceState.UNDERVOLTAGE:
				# Oscurecido y amarillento (El bombillo apenas brilla, la nevera suena feo)
				visual_sprite.modulate = Color(0.6, 0.6, 0.4)
				visual_sprite.position = original_sprite_position
				
			DeviceState.NORMAL:
				# Funcionamiento óptimo
				visual_sprite.modulate = Color.WHITE
				visual_sprite.position = original_sprite_position
				
			DeviceState.OVERVOLTAGE:
				# Peligro inminente: Tinte naranja intenso y vibración ligera
				visual_sprite.modulate = Color(1.0, 0.6, 0.2)
				visual_sprite.position = original_sprite_position + Vector2(
					randf_range(-1.0, 1.0),
					randf_range(-1.0, 1.0)
				)
				
			DeviceState.BROKEN:
				# Destruido: Tinte rojo sangre y vibración violenta
				visual_sprite.modulate = Color.RED
				visual_sprite.position = original_sprite_position + Vector2(
					randf_range(-4.0, 4.0),
					randf_range(-4.0, 4.0)
				)

# --- TEXTO DE DEPURACIÓN ACTUALIZADO ---
func get_debug_text() -> String:
	var base_text = super.get_debug_text()
	
	# Aseguramos que el array coincida con el enum DeviceState
	var state_strings = ["APAGADO", "BAJO VOLTAJE", "NORMAL", "SOBREVOLTAJE", "QUEMADO"]
	var current_state_text = state_strings[current_state]
	var power_consumed = voltage_in * current_draw
	
	return "%s\nPotencia: %.1f W\nEstado: %s" % [base_text, power_consumed, current_state_text]

func set_switch_state_externally(turn_on: bool) -> void:
	if not has_switch or current_state == DeviceState.BROKEN:
		return
		
	is_switched_on = turn_on
	if toggle_button:
		toggle_button.set_pressed_no_signal(turn_on)
