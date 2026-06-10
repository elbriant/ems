extends Node2D
class_name DeviceOverloadEffect

## Efecto de partículas que se activa cuando un dispositivo entra en
## sobrecarga (OVERVOLTAGE) o se quema (BROKEN). Usa GPUParticles2D
## nativo con ParticleProcessMaterial que el usuario puede editar.

@export_category("Referencias")
## El ElectricalConsumer padre (si está vacío, busca en el padre automáticamente)
@export var target_device: ElectricalConsumer

@export_category("Apariencia")
## Textura de cada partícula
@export var particle_texture: Texture2D
## Color de partículas en sobrecarga
@export var overload_color: Color = Color(1.0, 0.5, 0.1, 0.9)
## Color de partículas cuando se quema
@export var broken_color: Color = Color(1.0, 0.15, 0.05, 1.0)
## Escala de partículas en sobrecarga
@export var overload_scale: float = 1.0
## Escala de partículas cuando se quema
@export var broken_scale: float = 1.5

@export_category("Comportamiento")
## Cantidad de partículas en sobrecarga
@export_range(5, 80) var overload_amount: int = 15
## Cantidad de partículas al quemarse (ráfaga)
@export_range(10, 120) var broken_amount: int = 40
## Vida de cada partícula
@export var particle_lifetime: float = 0.8
## Velocidad inicial de emisión
@export var emission_velocity: float = 60.0
## Gravedad que afecta las partículas (hacia arriba = negativo)
@export var particle_gravity: float = -30.0
## Dispersión angular de la emisión (0 = unidireccional, 180 = omnidireccional)
@export_range(0, 180) var spread_angle: float = 45.0
## Posición offset de la emisión relativa al padre
@export var emission_offset: Vector2 = Vector2(0, -20)

@export_category("Material (Advanced)")
## Si quieres usar tu propio ParticleProcessMaterial, arrástralo aquí.
@export var custom_material: ParticleProcessMaterial

# Nodos internos
var _gpu_particles: GPUParticles2D
var _process_material: ParticleProcessMaterial

# Estado
var _previous_state: int = -1  # ElectricalConsumer.DeviceState
var _is_initialized: bool = false

func _ready() -> void:
	await get_tree().process_frame
	
	# Auto-detectar el ElectricalConsumer padre
	if not target_device:
		target_device = get_parent() as ElectricalConsumer
	
	if not target_device:
		push_warning("DeviceOverloadEffect '%s': No se encontró ElectricalConsumer." % name)
		return
	
	_setup()
	_is_initialized = true

func _setup() -> void:
	# Crear GPUParticles2D
	_gpu_particles = GPUParticles2D.new()
	_gpu_particles.name = "OverloadParticles"
	_gpu_particles.position = emission_offset
	_gpu_particles.z_index = 15
	add_child(_gpu_particles)
	
	# Configurar material
	if custom_material:
		_process_material = custom_material
	else:
		_create_default_material()
	
	_gpu_particles.process_material = _process_material
	# Si no hay textura, crear una por defecto (chispa)
	if particle_texture:
		_gpu_particles.texture = particle_texture
	else:
		_gpu_particles.texture = _generate_default_texture()
	_gpu_particles.amount = overload_amount
	_gpu_particles.lifetime = particle_lifetime
	_gpu_particles.emitting = false
	_gpu_particles.one_shot = false
	_gpu_particles.explosiveness = 0.1
	_gpu_particles.randomness = 0.5
	
	# Zona de emisión: semi-círculo superior
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_process_material.emission_ring_axis = Vector3(0, -1, 0)
	_process_material.emission_ring_height = 0.0
	_process_material.emission_ring_inner_radius = 5.0
	_process_material.emission_ring_radius = 15.0

func _create_default_material() -> void:
	_process_material = ParticleProcessMaterial.new()
	_process_material.direction = Vector3(0, -1, 0)
	_process_material.spread = spread_angle
	_process_material.initial_velocity_min = emission_velocity * 0.5
	_process_material.initial_velocity_max = emission_velocity
	_process_material.gravity = Vector3(0, particle_gravity, 0)
	_process_material.scale_min = overload_scale * 0.5
	_process_material.scale_max = overload_scale * 1.2
	_process_material.color = overload_color
	
	# Drag para que se desaceleren
	_process_material.damping_min = 20.0
	_process_material.damping_max = 40.0
	
	# Fase angular para movimiento circular sutil
	_process_material.angular_velocity_min = -30.0
	_process_material.angular_velocity_max = 30.0

func _process(_delta: float) -> void:
	if not _is_initialized or not target_device:
		return
	
	var current_state: int = target_device.current_state
	
	# Solo actuar si el estado cambió
	if current_state == _previous_state:
		return
	
	_previous_state = current_state
	_update_particle_state(current_state)

func _update_particle_state(state: int) -> void:
	match state:
		0:  # OFF
			_deactivate()
		1:  # UNDERVOLTAGE
			_deactivate()
		2:  # NORMAL
			_deactivate()
		3:  # OVERVOLTAGE
			_activate_overload()
		4:  # BROKEN
			_activate_broken()

func _activate_overload() -> void:
	if not _gpu_particles:
		return
	
	# Configurar para sobrecarga
	_gpu_particles.amount = overload_amount
	_process_material.color = overload_color
	_process_material.scale_min = overload_scale * 0.5
	_process_material.scale_max = overload_scale * 1.2
	_process_material.initial_velocity_min = emission_velocity * 0.5
	_process_material.initial_velocity_max = emission_velocity
	_gpu_particles.emitting = true
	_gpu_particles.one_shot = false

func _activate_broken() -> void:
	if not _gpu_particles:
		return
	
	# Ráfaga de partículas al quemarse
	_gpu_particles.amount = broken_amount
	_process_material.color = broken_color
	_process_material.scale_min = broken_scale * 0.8
	_process_material.scale_max = broken_scale * 1.5
	_process_material.initial_velocity_min = emission_velocity * 1.5
	_process_material.initial_velocity_max = emission_velocity * 2.5
	_gpu_particles.one_shot = true
	_gpu_particles.emitting = true

func _deactivate() -> void:
	if _gpu_particles:
		_gpu_particles.emitting = false

func _generate_default_texture() -> ImageTexture:
	# Chispa pequeña de 8x8
	var img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(3.5, 3.5)
	for x in range(8):
		for y in range(8):
			var dist: float = Vector2(x, y).distance_to(center) / 3.5
			if dist <= 1.0:
				var alpha: float = clampf(1.0 - dist, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 0.8, 0.3, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
