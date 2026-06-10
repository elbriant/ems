extends Node

signal sun_info_changed(hour: float, rotation_deg: float)

@export var cycle_duration: float = 120.0
@export var day_portion: float = 0.85

@export_group("CanvasModulate")
@export var day_tint: Color = Color(0.78, 0.78, 0.82, 1.0)
@export var night_tint: Color = Color(0.12, 0.12, 0.25, 1.0)

@export_group("DirectionalLight2D")
@export var day_energy: float = 0.8
@export var night_energy: float = 0.02
@export var day_light_color: Color = Color(1.0, 0.95, 0.85, 1.0)
@export var night_light_color: Color = Color(0.3, 0.3, 0.6, 1.0)

@export_group("Sky")
@export var day_sky_modulate: Color = Color(0.75, 0.82, 1.0, 1.0)
@export var night_sky_modulate: Color = Color(0.04, 0.04, 0.15, 1.0)

var elapsed_seconds: float = 0.0
var is_manual_mode: bool = false
var manual_hour: float = 12.0
var time_scale: float = 1.0

@onready var canvas_modulate: CanvasModulate = $"../decorations/CanvasModulate"
@onready var directional_light: DirectionalLight2D = $"../decorations/DirectionalLight2D"
@onready var sky_sprite: Sprite2D = $"../BG/Sprite2D"


func _ready() -> void:
	_update_cycle()


func _process(delta: float) -> void:
	if not is_manual_mode:
		elapsed_seconds = fmod(elapsed_seconds + delta * time_scale, cycle_duration)
	_update_cycle()


func set_manual_mode(enabled: bool) -> void:
	is_manual_mode = enabled


func set_manual_hour(hour: float) -> void:
	manual_hour = hour
	_update_cycle()


func set_time_scale(scale: float) -> void:
	time_scale = maxf(scale, 1.0)


func get_time_scale() -> float:
	return time_scale


func _update_cycle() -> void:
	var hour_24: float = _get_hour()
	var day_factor: float = _calculate_day_factor(hour_24)
	var rot_deg: float = _calculate_rotation_deg(hour_24)

	Globals.current_day_factor = day_factor

	if canvas_modulate:
		canvas_modulate.color = night_tint.lerp(day_tint, day_factor)

	if directional_light:
		directional_light.energy = lerpf(night_energy, day_energy, day_factor)
		directional_light.rotation = deg_to_rad(rot_deg)
		directional_light.color = night_light_color.lerp(day_light_color, day_factor)

	if sky_sprite:
		sky_sprite.modulate = night_sky_modulate.lerp(day_sky_modulate, day_factor)

	sun_info_changed.emit(hour_24, rot_deg)


func _get_hour() -> float:
	if is_manual_mode:
		return manual_hour
	var raw_t: float = fmod(elapsed_seconds, cycle_duration) / cycle_duration
	var day_t: float
	if raw_t < day_portion:
		day_t = raw_t / day_portion
	else:
		day_t = 1.0 + (raw_t - day_portion) / (1.0 - day_portion)
	return fmod(6.0 + day_t * 12.0, 24.0)


func _calculate_day_factor(hour: float) -> float:
	var t: float = hour / 24.0
	return 0.5 + 0.5 * cos((t - 0.5) * TAU)


func _calculate_rotation_deg(hour: float) -> float:
	# hour 0=midnight(270°), 6=dawn(0°), 12=noon(90°), 18=dusk(180°)
	var deg: float = (hour - 12.0) * 15.0
	return fposmod(deg, 360.0)
