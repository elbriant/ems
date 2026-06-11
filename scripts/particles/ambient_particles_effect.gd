extends Node2D
class_name AmbientParticlesEffect

## Partículas ambientales que siempre están en la cámara.
## Efecto de parallax sutil: se mueven ligeramente en sentido opuesto
## al movimiento de la cámara, creando sensación de profundidad.

@export_category("Apariencia")
@export var particle_texture: Texture2D
@export var color_tint: Color = Color(1.0, 0.95, 0.85, 0.6)
@export var base_scale: float = 1.5
@export_range(0, 1) var scale_variation: float = 0.4

@export_category("Emisión")
## Tamaño del área de emisión (centrada en la cámara)
@export var emission_area: Vector2 = Vector2(800, 500)
## Cantidad de partículas
@export_range(5, 100) var particle_amount: int = 25
## Velocidad de deriva de las partículas (px/s)
@export var drift_speed: float = 10.0
## Vida de cada partícula
@export var particle_lifetime: float = 5.0
## Ángulo de dispersión (grados, 180 = omnidireccional)
@export_range(0, 180) var spread: float = 180.0
## Gravedad que afecta las partículas
@export var gravity: Vector3 = Vector3.ZERO

@export_category("Rotación y Color")
## Velocidad angular mínima (grados/s)
@export var angular_velocity_min: float = -10.0
## Velocidad angular máxima (grados/s)
@export var angular_velocity_max: float = 10.0
## Variación de tono (matiz) mínima (-1 a 1)
@export_range(-1, 1) var hue_variation_min: float = 0.0
## Variación de tono (matiz) máxima (-1 a 1)
@export_range(-1, 1) var hue_variation_max: float = 0.0

@export_category("Parallax")
## Fuerza del efecto parallax (0 = sin parallax, 1 = mucho)
@export_range(0, 1) var parallax_strength: float = 0.3

@export_category("Material (Advanced)")
## Si asignas un material, se duplica y se le aplican los parámetros de arriba encima.
## Los parámetros no cubiertos por exports (como color_ramp) quedan del material.
@export var custom_material: ParticleProcessMaterial

var _gpu_particles: GPUParticles2D
var _camera: Camera2D
var _last_camera_pos: Vector2
var _camera_velocity: Vector2

func _ready() -> void:
	_setup()

func _setup() -> void:
	_gpu_particles = GPUParticles2D.new()
	_gpu_particles.name = "AmbientDust"
	_gpu_particles.z_index = 100
	add_child(_gpu_particles)

	var mat: ParticleProcessMaterial
	if custom_material:
		mat = custom_material.duplicate()
		_apply_exports_to_material(mat)
	else:
		mat = _create_default_material()

	_gpu_particles.process_material = mat
	_gpu_particles.texture = particle_texture if particle_texture else _make_default_texture()
	_gpu_particles.amount = particle_amount
	_gpu_particles.lifetime = particle_lifetime
	_gpu_particles.emitting = true
	_gpu_particles.one_shot = false
	_gpu_particles.explosiveness = 0.0
	_gpu_particles.randomness = 0.8

func _create_default_material() -> ParticleProcessMaterial:
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()

	# Dirección base (hacia arriba sutil)
	mat.direction = Vector3(0, -0.5, 0)
	_apply_exports_to_material(mat)

	# Fade in/out (solo en material por defecto, no se toca con custom)
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	grad.colors = PackedColorArray([
		Color(color_tint.r, color_tint.g, color_tint.b, 0.0),
		Color(color_tint.r, color_tint.g, color_tint.b, color_tint.a),
		Color(color_tint.r, color_tint.g, color_tint.b, color_tint.a),
		Color(color_tint.r, color_tint.g, color_tint.b, 0.0)
	])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	mat.color_ramp = tex

	return mat

func _apply_exports_to_material(mat: ParticleProcessMaterial) -> void:
	# Emisión
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.set("emission_box_extents", Vector3(
		emission_area.x * 0.5, emission_area.y * 0.5, 0
	))
	mat.spread = spread
	mat.initial_velocity_min = drift_speed * 0.5
	mat.initial_velocity_max = drift_speed * 1.5
	mat.gravity = gravity

	# Escala
	mat.scale_min = base_scale * (1.0 - scale_variation)
	mat.scale_max = base_scale * (1.0 + scale_variation)

	# Color
	mat.color = color_tint

	# Rotación
	mat.angular_velocity_min = angular_velocity_min
	mat.angular_velocity_max = angular_velocity_max

	# Variación de tono
	mat.hue_variation_min = hue_variation_min
	mat.hue_variation_max = hue_variation_max

func _make_default_texture() -> ImageTexture:
	var img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var c: Vector2 = Vector2(3.5, 3.5)
	for x in range(8):
		for y in range(8):
			var d: float = Vector2(x, y).distance_to(c) / 3.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d * d, 0.0, 1.0)) if d <= 1.0 else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_2d()
		if _camera:
			_last_camera_pos = _camera.global_position
		return

	# Calcular velocidad de la cámara para parallax
	_camera_velocity = (_camera.global_position - _last_camera_pos) / maxf(delta, 0.001)
	_last_camera_pos = _camera.global_position

	# Seguir a la cámara con offset de parallax
	# Las partículas se mueven en sentido opuesto a la cámara
	var parallax_offset: Vector2 = -_camera_velocity * parallax_strength * delta
	global_position = _camera.global_position + parallax_offset

func set_enabled(enabled: bool) -> void:
	if _gpu_particles:
		_gpu_particles.emitting = enabled
