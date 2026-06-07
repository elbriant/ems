extends CanvasLayer
class_name PedagogicalOverlay

# Overlay pedagógico que muestra al usuario las hipótesis del modelo simplificado.
# Diseñado para que el simulador sea "pedagógicamente honesto" — un alumno
# avanzado sabe qué simplificaciones asume el modelo y cuándo deja de ser válido.
# Tecla: H para mostrar/ocultar.

const TOGGLE_KEY: Key = KEY_H
const TITLE: String = "⚠ MODELO SIMPLIFICADO — USO EDUCATIVO"
const DISCLAIMER_LINES: PackedStringArray = [
	"• Red modelada en DC, sin reactancias (X_L, X_C)",
	"• Cargas resistivas por defecto (asignar power_factor <1.0 para motores)",
	"• Breaker (ElectricalBreaker/BranchCircuit) protege contra CORRIENTE,",
	"  NO contra sobrevoltaje. Para sobrevoltaje usa VoltageRegulator.",
	"• Jerarquía real: Fuente → Regulador → Breaker principal → Breakers ramales",
	"• Modelo térmico del cable: ratio I/I_max instantáneo (no integra τ_térmica)",
	"• Impedancia de fuente: 0.5 Ω típica (Z_Thévenin de la red pública)",
	"• Sistema monofásico + bifásico derivado (NO trifásico)",
	"• Split-phase: 220V centro-tap → 2×110V, con corriente de neutro calculada",
	"• Para análisis real: usar SPICE, ETAP, OpenDSS",
	"",
	"Atajos: H = mostrar/ocultar este panel",
]

var panel: PanelContainer
var title_label: Label
var body_label: Label
var is_visible_panel: bool = false

func _ready() -> void:
	# Encima de cualquier otra UI
	layer = 100
	_build_panel()
	panel.visible = false

func _build_panel() -> void:
	panel = PanelContainer.new()
	add_child(panel)
	# Esquina superior derecha
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -340
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = 360
	# Mouse filter: IGNORE para no bloquear CheckButton del mundo 2D (regla AGENTS.md)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.85, 0.2, 0.9)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	vbox.add_theme_constant_override("separation", 4)

	title_label = Label.new()
	title_label.text = TITLE
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	body_label = Label.new()
	body_label.text = "\n".join(DISCLAIMER_LINES)
	body_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	body_label.add_theme_font_size_override("font_size", 11)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEY:
			is_visible_panel = not is_visible_panel
			panel.visible = is_visible_panel

# Método estático: crea el overlay y lo añade al árbol de la escena actual.
# Llamar desde main_engine._ready() o desde cualquier nodo al iniciar.
static func create_and_attach(parent: Node) -> PedagogicalOverlay:
	var overlay := PedagogicalOverlay.new()
	overlay.name = "PedagogicalOverlay"
	parent.add_child(overlay)
	return overlay
