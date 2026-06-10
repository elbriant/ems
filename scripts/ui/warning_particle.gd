extends Node2D
class_name WarningParticle

@export var config: WarningParticleConfig

var panel: PanelContainer
var hbox: HBoxContainer
var label: Label
var icon_label: Label
var elapsed: float = 0.0
var start_position: Vector2
var entrance_elapsed: float = 0.0
var _initialized: bool = false

func _init() -> void:
	panel = PanelContainer.new()
	panel.name = "WarningPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	
	hbox = HBoxContainer.new()
	hbox.name = "WarningHBox"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)
	
	icon_label = Label.new()
	icon_label.name = "IconLabel"
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon_label)
	
	label = Label.new()
	label.name = "WarningLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(label)

func _ready() -> void:
	if not _initialized:
		_apply_config()
		_initialized = true
	start_position = global_position

func _apply_config() -> void:
	if not config:
		config = Globals.default_warning_config
	if not config:
		config = WarningParticleConfig.new()
	
	# Icono
	if config.show_icon:
		icon_label.visible = true
		icon_label.text = config.icon_text
		icon_label.add_theme_font_size_override("font_size", config.icon_font_size)
		icon_label.add_theme_color_override("font_color", config.icon_color)
		label.add_theme_constant_override("margin_left", int(config.icon_margin_right))
	else:
		icon_label.visible = false
	
	# Panel
	var style = StyleBoxFlat.new()
	style.bg_color = config.bg_color
	style.set_corner_radius_all(config.corner_radius)
	style.content_margin_left = config.padding.x
	style.content_margin_right = config.padding.x
	style.content_margin_top = config.padding.y
	style.content_margin_bottom = config.padding.y
	
	if config.border_width > 0:
		style.set_border_width_all(config.border_width)
		style.border_color = config.border_color
	
	if config.shadow_enabled:
		style.shadow_color = config.shadow_color
		style.shadow_offset = config.shadow_offset
	
	panel.add_theme_stylebox_override("panel", style)
	
	# Texto
	label.add_theme_font_size_override("font_size", config.font_size)
	label.add_theme_color_override("font_color", config.font_color)
	
	if config.font_shadow_enabled:
		label.add_theme_color_override("font_shadow_color", config.font_shadow_color)
		label.add_theme_constant_override("shadow_offset_x", int(config.font_shadow_offset.x))
		label.add_theme_constant_override("shadow_offset_y", int(config.font_shadow_offset.y))

func setup(message: String, color: Color = Color(0,0,0,0)) -> void:
	if not _initialized:
		_apply_config()
		_initialized = true
	
	label.text = message
	if color != Color(0,0,0,0):
		label.add_theme_color_override("font_color", color)
	
	if config.entrance_animation:
		entrance_elapsed = 0.0
		scale = Vector2(config.entrance_scale_from, config.entrance_scale_from)

func _process(delta: float) -> void:
	elapsed += delta
	var progress = elapsed / config.lifetime
	if progress >= 1.0:
		queue_free()
		return
	
	global_position = start_position + Vector2(0, -config.float_speed * elapsed)
	
	var alpha = 1.0 - progress
	var c = label.get_theme_color("font_color")
	label.add_theme_color_override("font_color", Color(c.r, c.g, c.b, alpha))
	
	var target_scale = 1.0 + progress * config.scale_curve
	
	if config.entrance_animation and entrance_elapsed < config.entrance_duration:
		entrance_elapsed += delta
		var t = clampf(entrance_elapsed / config.entrance_duration, 0.0, 1.0)
		target_scale = lerpf(config.entrance_scale_from, 1.0, t)
	
	scale = Vector2(target_scale, target_scale)

static func create_warning(parent: Node, world_position: Vector2, message: String, color: Color = Color(0,0,0,0), cfg: WarningParticleConfig = null) -> WarningParticle:
	var warning = WarningParticle.new()
	if cfg:
		warning.config = cfg
	warning.setup(message, color)
	
	parent.add_child(warning)
	warning.global_position = world_position
	
	# Aplicar offset random después de estar en el árbol
	if warning.config:
		var offset = Vector2(randf_range(-warning.config.random_offset_range, warning.config.random_offset_range), randf_range(-warning.config.random_offset_range, warning.config.random_offset_range))
		warning.global_position += offset
	
	warning.start_position = warning.global_position
	return warning
