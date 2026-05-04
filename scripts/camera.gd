extends Camera2D

@export var world_limits: ReferenceRect
@export var base_speed: float = 400.0
@export var mouse_pan_speed: float = 1.5
@export var pan_smoothing: float = 0.2  # Suavizado del pan (0 = instantáneo, 1 = muy lento)

@export_group("Zoom")
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0

var is_panning: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO  # Posición objetivo para suavizado

func _ready():
	target_position = position

func _process(delta: float) -> void:
	var viewport_halfsize = get_viewport_rect().size / zoom / 2
	var limit_min: Vector2 = Vector2(world_limits.position.x + viewport_halfsize.x, world_limits.position.y + viewport_halfsize.y)
	var limit_max: Vector2 = Vector2(world_limits.position.x + world_limits.size.x - viewport_halfsize.x, world_limits.position.y + world_limits.size.y - viewport_halfsize.y)
	
	# Movimiento por teclado
	var direction = Vector2.ZERO
	if not is_panning:
		if Input.is_physical_key_pressed(KEY_W): direction.y -= 1
		if Input.is_physical_key_pressed(KEY_S): direction.y += 1
		if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
		if Input.is_physical_key_pressed(KEY_D): direction.x += 1
		
		if direction != Vector2.ZERO:
			direction = direction.normalized()
			target_position += (base_speed / zoom.x) * direction * delta
	
	# Aplicar movimiento suave
	position = position.lerp(target_position, pan_smoothing)
	
	# Aplicar límites a la posición objetivo (para evitar overshoot)
	target_position.x = clamp(target_position.x, limit_min.x, limit_max.x)
	target_position.y = clamp(target_position.y, limit_min.y, limit_max.y)
	
	# Forzar posición actual a límites
	position.x = clamp(position.x, limit_min.x, limit_max.x)
	position.y = clamp(position.y, limit_min.y, limit_max.y)

func _input(event: InputEvent) -> void:
	# Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom += Vector2(zoom_speed, zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom -= Vector2(zoom_speed, zoom_speed)
		
		zoom = zoom.clamp(Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))
		
		# Pan con botón medio
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_panning = true
				last_mouse_position = event.global_position
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			else:
				is_panning = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	
	# Movimiento del mouse
	elif event is InputEventMouseMotion and is_panning:
		var mouse_delta = event.global_position - last_mouse_position
		var pan_vector = -mouse_delta * mouse_pan_speed / zoom.x
		target_position += pan_vector
		last_mouse_position = event.global_position
