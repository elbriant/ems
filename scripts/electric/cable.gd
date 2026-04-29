class_name Cable
extends Line2D

@export var current_flow: float = 0.0
@export var max_current: float = 20.0  # Amperios máximos

func _process(delta):
	update_cable_appearance()

func update_cable_appearance():
	# Color basado en la carga (verde -> amarillo -> rojo)
	var load_ratio = clamp(abs(current_flow) / max_current, 0.0, 1.0)
	
	# Gradiente de color
	if load_ratio < 0.5:
		modulate = Color.GREEN.lerp(Color.YELLOW, load_ratio * 2)
	else:
		modulate = Color.YELLOW.lerp(Color.RED, (load_ratio - 0.5) * 2)
	
	# Grosor dinámico
	width = 2.0 + load_ratio * 6.0
	
	# Animación de flujo (partículas o puntos moviéndose)
	if current_flow > 0.1:
		# animate_flow(load_ratio)
		pass
