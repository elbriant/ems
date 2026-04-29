extends Camera2D

@export_group("Movimiento")
@export var base_speed: float = 400.0

@export_group("Zoom")
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0

func _process(delta: float) -> void:
	var limit_min: Vector2 = Vector2(self.limit_right, self.limit_top)
	var limit_max: Vector2 = Vector2(self.limit_left, self.limit_bottom)
	var direction = Vector2.ZERO

	if Input.is_physical_key_pressed(KEY_W): direction.y -= 1
	if Input.is_physical_key_pressed(KEY_S): direction.y += 1
	if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
	if Input.is_physical_key_pressed(KEY_D): direction.x += 1

	if direction != Vector2.ZERO:
		direction = direction.normalized()
		
		# CÁLCULO DE VELOCIDAD DINÁMICA:
		# Dividimos la velocidad base por el zoom actual.
		# Si zoom es 0.5 (lejos), la velocidad será base_speed / 0.5 = base_speed * 2.
		var velocity = (base_speed / zoom.x) * direction
		position += velocity * delta

	# RESTRICCIÓN DE LÍMITES (CLAMP):
	# Esto evita que la posición del nodo siga aumentando fuera de los bordes.
	position.x = clamp(position.x, limit_min.x, limit_max.x)
	position.y = clamp(position.y, limit_min.y, limit_max.y)
	print(position)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom += Vector2(zoom_speed, zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom -= Vector2(zoom_speed, zoom_speed)
		
		# Limitar el zoom para no perder la escala
		zoom = zoom.clamp(Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))
