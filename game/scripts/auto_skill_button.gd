@tool
extends Button

## Visual only; all automatic action decisions remain in the battle controller.
@export var auto_border_color: Color = Color(1.0, 0.80, 0.34, 1.0)
@export_range(0.5, 4.0, 0.1) var auto_border_period: float = 1.4
var auto_enabled: bool = false
var phase: float = 0.0

func _ready() -> void:
	set_process(false)

func set_autocast(enabled: bool) -> void:
	if auto_enabled == enabled: return
	auto_enabled = enabled
	phase = 0.0
	set_process(enabled and not Engine.is_editor_hint())
	queue_redraw()

func _process(delta: float) -> void:
	phase = fmod(phase + delta / auto_border_period, 1.0)
	queue_redraw()

func _draw() -> void:
	if not auto_enabled: return
	var inset: float = 3.0
	var extent: Vector2 = size - Vector2.ONE * inset * 2
	var perimeter: float = 2.0 * (extent.x + extent.y)
	var color: Color = auto_border_color
	color.a *= 0.55 + 0.45 * (sin(phase * TAU * 2) + 1.0) / 2.0
	draw_rect(Rect2(Vector2.ONE * inset, extent), Color(color, color.a * 0.35), false, 1.0)
	for band in 2:
		for step in 28:
			var start: float = fmod(phase + band * 0.5 + step * 0.006, 1.0) * perimeter
			var end: float = fmod(phase + band * 0.5 + (step + 1) * 0.006, 1.0) * perimeter
			# Skip the wrap segment so the border never draws a diagonal across the icon.
			if end >= start:
				draw_line(border_point(start, extent) + Vector2.ONE * inset, border_point(end, extent) + Vector2.ONE * inset, Color(color, color.a * float(step + 1) / 28.0), 3.0, true)

func border_point(distance: float, extent: Vector2) -> Vector2:
	if distance < extent.x: return Vector2(distance, 0)
	distance -= extent.x
	if distance < extent.y: return Vector2(extent.x, distance)
	distance -= extent.y
	if distance < extent.x: return Vector2(extent.x - distance, extent.y)
	return Vector2(0, extent.y - (distance - extent.x))
