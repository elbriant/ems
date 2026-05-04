extends Line2D
class_name Cable

# Forzamos el tipado estricto para que solo acepte nodos de tipo ElectricalWire
@export var electrical_wire: ElectricalWire 

@export_category("Diseño Visual")
# Gradiente: Verde (0.0) -> Amarillo (0.5) -> Naranja (0.8) -> Rojo (1.0)
@export var stress_gradient: Gradient 

# Guardamos la posición original para efectos de temblor por sobrecarga
var original_position: Vector2

func _ready() -> void:
	original_position = position
	
	# Verificación de seguridad para evitar crasheos si olvidamos conectar el nodo en el editor
	if not electrical_wire:
		push_warning("El componente visual '%s' no tiene un ElectricalWire enlazado." % name)

func _process(_delta: float) -> void:
	# Si no hay lógica enlazada o no configuraste un gradiente, no hacemos nada
	if not electrical_wire or not stress_gradient:
		return
	
	# Extraemos el valor matemático del nodo lógico
	var stress: float = electrical_wire.thermal_stress
	
	# 1. El toque Poly Bridge (Color Dinámico)
	# clamp asegura que el valor se mantenga entre 0.0 y 1.0 para el sample del gradiente
	default_color = stress_gradient.sample(clamp(stress, 0.0, 1.0))
	
	# 2. Efecto visual de Sobrecarga (Retroalimentación adicional)
	if stress > 1.0:
		# Hacemos que el cable "vibre" o tiemble si se está calentando demasiado
		var shake_intensity = (stress - 1.0) * 2.0 
		position = original_position + Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
	else:
		# Vuelve a su posición normal si la carga se estabiliza
		position = original_position
