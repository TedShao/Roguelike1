@tool
extends Button

@export var skill: SkillSpec
var hover_tween: Tween
var pulse_tween: Tween

func _ready() -> void:
	if skill != null:
		$Icon.texture = skill.icon
		$Title.text = skill.display_name
		$Description.text = skill.description.replace("冷却 %d。" % skill.cooldown, "").replace("点击即执行。", "")
		$Cooldown.text = "冷却 %d" % skill.cooldown
		tooltip_text = skill.description
	update_selection()
	if Engine.is_editor_hint():
		return
	mouse_entered.connect(hover.bind(true))
	mouse_exited.connect(hover.bind(false))
	focus_entered.connect(hover.bind(true))
	focus_exited.connect(hover.bind(false))
	toggled.connect(on_toggled)

func hover(entered: bool) -> void:
	if hover_tween: hover_tween.kill()
	if pulse_tween: pulse_tween.kill()
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.tween_property($Icon, "scale", Vector2.ONE * (1.12 if entered else 1.0), 0.12).set_trans(Tween.TRANS_QUAD)
	hover_tween.tween_property($Highlight, "modulate:a", 0.28 if entered else 0.0, 0.12)

func on_toggled(_pressed: bool) -> void:
	update_selection()
	if pulse_tween: pulse_tween.kill()
	if hover_tween: hover_tween.kill()
	$Icon.scale = Vector2.ONE * 0.88
	pulse_tween = create_tween()
	pulse_tween.tween_property($Icon, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	$ClickParticles.restart()
	$ClickParticles.emitting = true

func update_selection() -> void:
	$Selected.visible = button_pressed
	$SelectedIcon.visible = button_pressed
	$Title.add_theme_color_override("font_color", Color("fff1ce") if button_pressed else Color("4e3424"))
	$Description.add_theme_color_override("font_color", Color("ffedcb") if button_pressed else Color("71543b"))
	$Cooldown.add_theme_color_override("font_color", Color("fff1ce") if button_pressed else Color("8e6338"))
