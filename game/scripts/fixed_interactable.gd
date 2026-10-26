class_name FixedInteractable
extends Node2D

@export var interaction_id: String = "exit"

func contains_world_point(point: Vector2) -> bool:
	return ShapeGeometry.contains($InteractionArea/CollisionShape2D, point)

func set_hovered(value: bool) -> void:
	# Only hover visibility changes. Position, text, texture and shape remain authored.
	$Prompt.visible = value

