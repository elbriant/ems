extends Node2D
class_name CableFlowEffect

## Crea un emisor de partículas por cada segmento del Line2D.
## La cantidad de partículas se normaliza según la longitud del segmento.
## Los cambios de corriente (inrush) se suavizan para evitar saltos bruscos.

@export_category("Referencias")
@export var cable_line: Line2D
@export var electrical_wire: ElectricalWire

@export_category("Apariencia")
@export var particle_texture: Texture2D
@export var color_tint: Color = Color(0.7, 0.85, 1.0, 0.8)
@export var particle_scale: float = 0.3

@export_category("Comportamiento")
## Partículas por 100px de cable (se escalan según longitud real del segmento)
@export var particles_per_100px: float = 4.0
@export var base_speed: float = 80.0
@export var speed_scale_by_current: float = 2.0
@export var particle_lifetime: float = 1.5
@export var amount_boost_on_stress: float = 1.5
## Ángulo de dispersión (grados)
@export_range(0, 90) var spread_degrees: float = 8.0
## Frenado de partículas
@export var damping_force: float = 40.0
## Suavidad de cambios de velocidad (0 = instantáneo, 1 = muy suave)
@export_range(0, 1) var velocity_smoothing: float = 0.15
## Suavidad de cambios de corriente (mayor = más lento responde a inrush)
@export_range(1, 20) var current_smoothing: float = 8.0

@export_category("Material (Advanced)")
@export var custom_material: ParticleProcessMaterial

var _emitters: Array[Dictionary] = []
var _is_initialized: bool = false
var _smoothed_ratio: float = 0.0  # Corriente normalizada suavizada

func _ready() -> void:
	await get_tree().process_frame
	_setup()
	_is_initialized = true

func _setup() -> void:
	if not cable_line:
		push_warning("CableFlowEffect '%s': cable_line no asignado." % name)
		return
	_build_emitters()

func _build_emitters() -> void:
	for e in _emitters:
		if is_instance_valid(e["node"]):
			e["node"].queue_free()
	_emitters.clear()

	var points: PackedVector2Array = cable_line.points
	if points.size() < 2:
		return

	var tex: Texture2D = particle_texture if particle_texture else _make_default_texture()

	# Calcular longitud total del cable para referencia
	var total_length: float = 0.0
	for i in range(points.size() - 1):
		total_length += points[i].distance_to(points[i + 1])

	for i in range(points.size() - 1):
		var p_a: Vector2 = points[i]
		var p_b: Vector2 = points[i + 1]
		var seg_vec: Vector2 = p_b - p_a
		var seg_len: float = seg_vec.length()
		if seg_len < 0.5:
			continue

		var seg_angle: float = seg_vec.angle()
		var seg_mid: Vector2 = (p_a + p_b) * 0.5

		# Cantidad normalizada: más partículas en segmentos largos
		var seg_amount: int = maxi(2, int(particles_per_100px * seg_len / 100.0))

		# Crear emisor
		var em: GPUParticles2D = GPUParticles2D.new()
		em.name = "Seg%d" % i
		em.position = seg_mid
		em.rotation = seg_angle
		em.z_index = 10

		# Material
		var mat: ParticleProcessMaterial
		if custom_material:
			mat = custom_material.duplicate()
		else:
			mat = ParticleProcessMaterial.new()

		# Emisión: caja del tamaño del segmento
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.set("emission_box_extents", Vector3(seg_len * 0.5, 2.0, 0))

		# Dirección: eje local +X
		mat.direction = Vector3(1, 0, 0)
		mat.spread = spread_degrees
		# Velocidad limitada por longitud del segmento
		var max_safe_speed: float = seg_len / maxf(particle_lifetime, 0.1)
		var clamped_speed: float = minf(base_speed, max_safe_speed * 0.8)
		mat.initial_velocity_min = clamped_speed * 0.7
		mat.initial_velocity_max = clamped_speed * 1.3
		mat.gravity = Vector3(0, 0, 0)
		mat.damping_min = damping_force
		mat.damping_max = damping_force * 1.5
		mat.scale_min = particle_scale * 0.7
		mat.scale_max = particle_scale * 1.3
		mat.color = color_tint

		em.process_material = mat
		em.texture = tex
		em.amount = seg_amount
		em.lifetime = particle_lifetime
		em.emitting = false
		em.one_shot = false
		em.explosiveness = 0.05
		em.randomness = 0.4

		add_child(em)

		_emitters.append({
			"node": em,
			"segment_length": seg_len,
			"base_amount": seg_amount,
			"current_velocity": clamped_speed
		})

func _make_default_texture() -> ImageTexture:
	var img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var c: Vector2 = Vector2(3.5, 3.5)
	for x in range(8):
		for y in range(8):
			var d: float = Vector2(x, y).distance_to(c) / 3.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d * d, 0.0, 1.0)) if d <= 1.0 else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	if not _is_initialized or not electrical_wire:
		return
	_update(delta)

func _update(delta: float) -> void:
	var current: float = electrical_wire.current_draw
	var stress: float = electrical_wire.thermal_stress
	var max_cur: float = electrical_wire.max_current

	# Ratio de corriente crudo
	var raw_ratio: float = current / max_cur if max_cur > 0.0 else 0.0

	# Suavizar para evitar saltos bruscos por inrush
	# Usamos decaimiento exponencial: responde rápido a subidas, lento a bajadas
	var smooth_factor: float = 1.0 - exp(-delta * current_smoothing)
	_smoothed_ratio = lerpf(_smoothed_ratio, raw_ratio, smooth_factor)

	var should_emit: bool = current > 0.01
	var target_speed: float = base_speed * (1.0 + _smoothed_ratio * speed_scale_by_current)

	# Cantidad con boost por estrés (también suavizado)
	var stress_boost: float = 1.0
	if stress > 0.5:
		stress_boost = 1.0 + (stress - 0.5) * amount_boost_on_stress * 2.0

	var alpha: float = lerpf(0.3, 1.0, clampf(_smoothed_ratio, 0.0, 1.0))
	var col: Color = Color(color_tint.r, color_tint.g, color_tint.b, alpha)
	var sc: float = lerpf(particle_scale, particle_scale * 1.8, clampf(stress, 0.0, 1.5))

	for e in _emitters:
		if not is_instance_valid(e["node"]):
			continue

		var mat: ParticleProcessMaterial = e["node"].process_material as ParticleProcessMaterial
		if not mat:
			continue

		# Interpolar velocidad suavemente
		var max_safe: float = e["segment_length"] / maxf(particle_lifetime, 0.1)
		var clamped_target: float = minf(target_speed, max_safe * 0.8)
		e["current_velocity"] = lerpf(e["current_velocity"], clamped_target, velocity_smoothing)

		mat.initial_velocity_min = e["current_velocity"] * 0.7
		mat.initial_velocity_max = e["current_velocity"] * 1.3
		mat.scale_min = sc * 0.7
		mat.scale_max = sc * 1.3
		mat.color = col

		# Cantidad normalizada con boost de estrés suavizado
		var target_amt: int = maxi(2, int(e["base_amount"] * stress_boost))
		target_amt = clampi(target_amt, 2, 40)
		if e["node"].amount != target_amt:
			e["node"].amount = target_amt

		if should_emit:
			e["node"].emitting = true
		else:
			e["node"].emitting = false

func refresh_path() -> void:
	if _is_initialized:
		_build_emitters()
