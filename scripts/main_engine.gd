extends Node
@onready var voltage_label: Label = $CanvasLayer/UI/Panel/Label
@onready var v_slider: VSlider = $CanvasLayer/UI/Panel/VSlider

func _ready() -> void:
	update_ui_label(v_slider.value)

func update_ui_label(voltage: float) -> void:
	voltage_label.text = "Voltaje actual: %.1f" % voltage

func _on_v_slider_value_changed(value: float) -> void:
	update_ui_label(value)
	Globals.global_voltage_changed.emit(value)


func _on_reset_button_down() -> void:
	# get_tree() accede al árbol principal del juego
	# reload_current_scene() destruye la escena activa y la vuelve a cargar desde cero
	get_tree().reload_current_scene()


func _on_details_toggled(toggled_on: bool) -> void:
	# Llamamos a la función "set_details_visible" en todos los nodos del grupo "electrical_components",
	# pasándole como argumento el nuevo estado (detalles_activados)
	get_tree().call_group("electrical_components", "set_details_visible", toggled_on) # Replace with function body.


func _on_toggle_all_devices_toggled(toggled_on: bool) -> void:
	# 1. Cambiamos el estado de todos los switches físicamente
	get_tree().call_group("switchable_devices", "set_switch_state_externally", toggled_on)
	
	# 2. Forzamos un recálculo general de la red para que los cables se enteren del cambio
	get_tree().call_group("power_sources", "update_network") # Replace with function body.
