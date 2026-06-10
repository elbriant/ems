extends Node

signal global_voltage_changed(voltage)
signal warning_visibility_changed(visible: bool)

var current_day_factor: float = 1.0
var time_scale: float = 1.0
var show_overheating_warnings: bool = true

@export_group("Advertencias")
@export var default_warning_config: WarningParticleConfig
