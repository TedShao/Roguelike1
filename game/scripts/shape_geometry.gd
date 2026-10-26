class_name ShapeGeometry
extends RefCounted

## Read the actual authored shape and its full transform, never a second hitbox.
static func contains(shape_node: CollisionShape2D, world_point: Vector2) -> bool:
	if shape_node.disabled or shape_node.shape == null:
		return false
	var local_point: Vector2 = shape_node.global_transform.affine_inverse() * world_point
	if shape_node.shape is RectangleShape2D:
		var rectangle: RectangleShape2D = shape_node.shape
		return Rect2(-rectangle.size / 2.0, rectangle.size).has_point(local_point)
	if shape_node.shape is CircleShape2D:
		var circle: CircleShape2D = shape_node.shape
		return local_point.length_squared() <= circle.radius * circle.radius
	return false

