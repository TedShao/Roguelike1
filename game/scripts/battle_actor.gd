class_name BattleActor
extends Node2D

@export var enemy_spec: EnemySpec

func _ready() -> void:
	$AnimationPlayer.animation_finished.connect(func(_animation): $AnimationPlayer.play("idle"))

func set_vitals(health: int, status: String = "") -> void:
	$Vitals.text = "%d%s" % [health, (" · " + status) if not status.is_empty() else ""]

func contains_world_point(point: Vector2) -> bool:
	return ShapeGeometry.contains($SelectionArea/CollisionShape2D, point)

func play_hit() -> void:
	$HitParticles.restart()
	$HitParticles.emitting = true
	# Visual feedback has a dedicated child: it never animates Sprite2D's authored scale.
	$AnimationPlayer.play("hit")

func play_attack() -> void:
	$AnimationPlayer.play("attack")

