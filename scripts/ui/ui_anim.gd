class_name UiAnim
extends RefCounted
## Tiny shared tween helpers for HUD juice (hover pops, pressed dips).


static func hover_pop(control: Control, amount: float = 1.06) -> void:
	## Scale the control up slightly on hover, back on exit.
	control.mouse_entered.connect(func() -> void: _scale_to(control, amount))
	control.mouse_exited.connect(func() -> void: _scale_to(control, 1.0))


static func _scale_to(control: Control, target: float) -> void:
	if not is_instance_valid(control):
		return
	control.pivot_offset = control.size * 0.5
	var tween: Tween = control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * target, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
