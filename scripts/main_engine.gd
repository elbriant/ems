extends Node
@onready var voltage_label: Label = $CanvasLayer/UI/Panel/Label
@onready var current_label: Label = $CanvasLayer/UI/Panel/CurrentLabel
@onready var v_slider: VSlider = $CanvasLayer/UI/Panel/VSlider
@onready var sun_slider: HSlider = $CanvasLayer/UI/Panel/MarginContainer/HBoxContainer/VBoxContainer2/sun_hour_box/sun_slider
@onready var sun_angle_label: Label = $CanvasLayer/UI/Panel/MarginContainer/HBoxContainer/VBoxContainer2/sun_angle_label
@onready var manual_sun_toggle: CheckButton = $CanvasLayer/UI/Panel/MarginContainer/HBoxContainer/VBoxContainer2/manual_sun_toggle
@onready var day_night_cycle: Node = $world/DayNightCycle
@onready var chart: Control = $CanvasLayer/UI/Panel/Chart
@onready var time_scale_slider: HSlider = $CanvasLayer/UI/Panel/MarginContainer/HBoxContainer/VBoxContainer2/time_scale_box/time_scale_slider
@onready var time_scale_value_label: Label = $CanvasLayer/UI/Panel/MarginContainer/HBoxContainer/VBoxContainer2/time_scale_box/time_scale_value
@onready var warning_toggle: CheckButton = $CanvasLayer/UI/Panel/MarginContainer/HBoxContainer/VBoxContainer3/warning_toggle

const HISTORY_SIZE := 80
const SAMPLE_INTERVAL := 0.15

var voltage_history: PackedFloat32Array
var sample_timer: float = 0.0

# UPS Demo
var ups_node: UninterruptiblePowerSupply = null
var power_failure_timer: float = 0.0
var is_power_failure_active: bool = false
var saved_voltage: float = 220.0


func _ready() -> void:
	update_ui_label(v_slider.value)
	voltage_history.append(v_slider.value)
	if day_night_cycle:
		day_night_cycle.sun_info_changed.connect(_on_sun_info_changed)
	# Overlay pedagógico (tecla H): muestra al usuario las hipótesis del modelo
	PedagogicalOverlay.create_and_attach(self)
	
	# Buscar nodo UPS en Casa 1 para la demo de apagón
	ups_node = $world/Electrics/casa1_cableado/UPS


func update_ui_label(voltage: float) -> void:
	voltage_label.text = "Voltaje actual: %.1f" % voltage


func _process(delta: float) -> void:
	sample_timer += delta
	if sample_timer >= SAMPLE_INTERVAL:
		sample_timer = 0.0
		record_sample(v_slider.value)
		update_current_label()
	
	# Manejar timer de simulación de apagón
	if is_power_failure_active:
		power_failure_timer -= delta
		if power_failure_timer <= 0.0:
			_end_power_failure_simulation()

func update_current_label() -> void:
	# Suma la corriente de todas las power_sources (típicamente una sola).
	# Usamos la variable current_draw que ElectricalSource actualiza en cada update_network().
	var sources := get_tree().get_nodes_in_group("power_sources")
	var total: float = 0.0
	for s in sources:
		if s != null and "current_draw" in s:
			total += s.current_draw
	if current_label:
		current_label.text = "Corriente total: %.2f A" % total


func record_sample(value: float) -> void:
	voltage_history.append(value)
	if voltage_history.size() > HISTORY_SIZE:
		voltage_history.remove_at(0)
	chart.queue_redraw()


func _on_v_slider_value_changed(value: float) -> void:
	update_ui_label(value)
	Globals.global_voltage_changed.emit(value)


func _on_reset_button_down() -> void:
	get_tree().reload_current_scene()


func _on_details_toggled(toggled_on: bool) -> void:
	get_tree().call_group("electrical_components", "set_details_visible", toggled_on)


func _on_expand_all_details_toggled(toggled_on: bool) -> void:
	if toggled_on:
		get_tree().call_group("electrical_components", "expand_all_details")
	else:
		get_tree().call_group("electrical_components", "collapse_all_details")


func _on_toggle_all_devices_toggled(toggled_on: bool) -> void:
	get_tree().call_group("switchable_devices", "set_switch_state_externally", toggled_on)
	get_tree().call_group("power_sources", "update_network")

# Demo de carga residencial: enciende simultáneamente todas las lavadoras
# marcadas con is_washer=true, generando un pico de inrush compuesto.
# Útil para visualizar la caída de tensión en la acometida cuando muchos
# motores arrancan a la vez (escenario típico de hora punta).
func _on_washer_demo_button_down() -> void:
	get_tree().call_group("washers", "set_switch_state_externally", true)
	# Forzamos recálculo inmediato para que el pico de inrush se dispare ya.
	get_tree().call_group("power_sources", "update_network")


func _on_sun_slider_value_changed(value: float) -> void:
	if day_night_cycle and manual_sun_toggle.button_pressed:
		day_night_cycle.set_manual_hour(value)


func _on_manual_sun_toggled(toggled_on: bool) -> void:
	if day_night_cycle:
		day_night_cycle.set_manual_mode(toggled_on)
	sun_slider.editable = toggled_on
	if toggled_on:
		day_night_cycle.set_manual_hour(sun_slider.value)


func _on_sun_info_changed(hour: float, rot_deg: float) -> void:
	var h: int = floori(hour)
	var m: int = int(fmod(hour, 1.0) * 60)
	sun_angle_label.text = "%02d:%02d | Rot: %.1f°" % [h, m, rot_deg]


func _on_chart_draw() -> void:
	if voltage_history.size() < 2:
		return

	var w: float = chart.size.x
	var h: float = chart.size.y
	if w <= 0 or h <= 0:
		return

	var min_v: float = 110.0
	var max_v: float = 280.0
	var range_v: float = max_v - min_v

	chart.draw_rect(Rect2(Vector2.ZERO, chart.size), Color(0, 0, 0, 0.35))

	var safe_top: float = (1.0 - (250.0 - min_v) / range_v) * h
	var safe_bot: float = (1.0 - (190.0 - min_v) / range_v) * h
	var safe_h: float = safe_bot - safe_top
	if safe_h > 0:
		chart.draw_rect(Rect2(Vector2(0, safe_top), Vector2(w, safe_h)), Color(0, 1, 0, 0.07))
		chart.draw_rect(Rect2(Vector2(0, safe_top), Vector2(w, safe_h)), Color(0, 1, 0, 0.12), false, 1.0)

	chart.draw_rect(Rect2(Vector2(0, 0), Vector2(w, safe_top)), Color(1, 0, 0, 0.05))
	chart.draw_rect(Rect2(Vector2(0, safe_bot), Vector2(w, h - safe_bot)), Color(1, 0, 0, 0.05))

	for v in range(120, 280, 20):
		var y: float = (1.0 - (v - min_v) / range_v) * h
		var alpha: float = 0.08 if v % 40 != 0 else 0.18
		chart.draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, alpha))

	var ref_y: float = (1.0 - (220.0 - min_v) / range_v) * h
	chart.draw_line(Vector2(0, ref_y), Vector2(w, ref_y), Color(1, 1, 0, 0.2), 1.0)

	if voltage_history.size() >= 2:
		var points := PackedVector2Array()
		var step_x: float = w / float(HISTORY_SIZE - 1)
		for i in range(voltage_history.size()):
			var x: float = float(i) * step_x
			var y: float = (1.0 - (voltage_history[i] - min_v) / range_v) * h
			points.append(Vector2(x, y))

		chart.draw_polyline(points, Color(0.3, 0.7, 1.0, 0.85), 2.0)

		var last_y: float = (1.0 - (voltage_history[-1] - min_v) / range_v) * h
		chart.draw_circle(Vector2(w, last_y), 3.5, Color(1, 1, 1, 0.9))


# --- UPS POWER FAILURE DEMO ---

## Simula un apagón de 5 segundos para demostrar la protección del UPS.
## La red eléctrica cae a 0V, pero el UPS mantiene las cargas de Casa 1.
func _on_power_failure_demo_button_down() -> void:
	if is_power_failure_active:
		return
	
	is_power_failure_active = true
	power_failure_timer = 5.0  # 5 segundos de apagón simulado
	
	# Guardar voltaje actual para restaurar después
	saved_voltage = v_slider.value
	
	# Forzar voltaje a 0 (simular apagón total)
	v_slider.value = 0.0
	update_ui_label(0.0)
	Globals.global_voltage_changed.emit(0.0)
	
	print("[DEMO] ⚡ APAGÓN SIMULADO INICIADO (5 segundos)")

## Finaliza la simulación de apagón y restaura el voltaje anterior.
func _end_power_failure_simulation() -> void:
	is_power_failure_active = false
	
	# Restaurar voltaje anterior
	v_slider.value = saved_voltage
	update_ui_label(saved_voltage)
	Globals.global_voltage_changed.emit(saved_voltage)
	
	print("[DEMO] ⚡ APAGÓN SIMULADO TERMINADO (voltaje restaurado a %.1f V)" % saved_voltage)


# --- TIME SCALE CONTROL ---

## Maneja el cambio del slider de escala de tiempo.
func _on_time_scale_slider_value_changed(value: float) -> void:
	var scale: float = value
	if time_scale_value_label:
		time_scale_value_label.text = "%.0fx" % scale
	
	# Aplicar escala global
	Globals.time_scale = scale
	
	# Aplicar escala al UPS si está disponible
	if ups_node:
		ups_node.set_time_scale(scale)
	
	# Aplicar escala al ciclo día/noche
	if day_night_cycle and day_night_cycle.has_method("set_time_scale"):
		day_night_cycle.set_time_scale(scale)


func _on_warning_toggle_toggled(toggled_on: bool) -> void:
	Globals.show_overheating_warnings = toggled_on
	Globals.warning_visibility_changed.emit(toggled_on)
