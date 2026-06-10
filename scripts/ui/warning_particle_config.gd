extends Resource
class_name WarningParticleConfig

@export_group("Comportamiento")
@export var lifetime: float = 2.0
@export var float_speed: float = 30.0
@export var random_offset_range: float = 20.0
@export var scale_curve: float = 0.3

@export_group("Panel de fondo")
@export var bg_color: Color = Color(0.0, 0.0, 0.0, 0.7)
@export var corner_radius: int = 6
@export var border_width: int = 0
@export var border_color: Color = Color(0.4, 0.4, 0.4, 1.0)
@export var padding: Vector2 = Vector2(10, 5)
@export var shadow_enabled: bool = false
@export var shadow_color: Color = Color(0, 0, 0, 0.4)
@export var shadow_offset: Vector2 = Vector2(2, 2)

@export_group("Texto")
@export var font_size: int = 14
@export var font_color: Color = Color(1.0, 0.3, 0.2)
@export var font_shadow_enabled: bool = false
@export var font_shadow_color: Color = Color(0, 0, 0, 0.6)
@export var font_shadow_offset: Vector2 = Vector2(1, 1)

@export_group("Icono")
@export var show_icon: bool = true
@export var icon_text: String = "⚠"
@export var icon_font_size: int = 18
@export var icon_color: Color = Color(1.0, 0.8, 0.0)
@export var icon_margin_right: float = 6.0

@export_group("Animación de entrada")
@export var entrance_animation: bool = true
@export var entrance_scale_from: float = 0.5
@export var entrance_duration: float = 0.2
