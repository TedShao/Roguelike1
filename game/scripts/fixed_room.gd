@tool
class_name FixedRoom
extends Node2D

@export var room_id: String = "A"
@export var display_name: String = "墙边展示房"
@export_multiline var encounter_note: String = ""
## Distance between cell centers. Snap authored objects to this grid; no auto-layout.
@export_range(16, 128, 1) var cell_size: float = 68.0
@export var rules: BattleRules
@export var show_grid: bool = true
@export var grid_color: Color = Color(0.45, 0.53, 0.55, 0.12)

var danger_cells: Array = []
var target_cells: Array = []
var candidate_cells: Array = []
var movement_path: Array = []
var pushed_path: Array = []
var hover_cell: Vector2i = Vector2i(-999, -999)
# Derived query results only, never authored geometry or a second level layout.
var _blocked_cache: Dictionary = {}

func invalidate_navigation_cache() -> void:
	_blocked_cache.clear()

func _process(_delta: float) -> void:
	# Editor preview redraw only; never changes a scene or resource property.
	if Engine.is_editor_hint():
		queue_redraw()

func cell_to_local(cell: Vector2i) -> Vector2:
	return $GridOrigin.position + Vector2(cell) * cell_size

func local_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(((point - $GridOrigin.position) / cell_size).round())

func world_to_cell(point: Vector2) -> Vector2i:
	return local_to_cell(to_local(point))

func player_cell() -> Vector2i:
	return world_to_cell($PlayerSpawn.global_position)

func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var collision: CollisionShape2D = $MapBounds/CollisionShape2D
	if not collision.shape is RectangleShape2D:
		return result
	var rect: RectangleShape2D = collision.shape
	var half: Vector2 = rect.size / 2.0
	var a: Vector2i = world_to_cell(collision.to_global(-half))
	var b: Vector2i = world_to_cell(collision.to_global(half))
	if absi(b.x - a.x) > 64 or absi(b.y - a.y) > 64:
		return result
	for y in range(mini(a.y, b.y) - 1, maxi(a.y, b.y) + 2):
		for x in range(mini(a.x, b.x) - 1, maxi(a.x, b.x) + 2):
			var c := Vector2i(x, y)
			if inside_bounds(c):
				result.append(c)
	return result

func inside_bounds(cell: Vector2i) -> bool:
	var center: Vector2 = cell_to_local(cell)
	# Entire tile must fit in the authored boundary; tiny epsilon permits touching edges.
	var half: float = cell_size * 0.5 - 0.01
	for corner in [Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half)]:
		if not ShapeGeometry.contains($MapBounds/CollisionShape2D, to_global(center + corner)):
			return false
	return true

func blocked(cell: Vector2i) -> bool:
	if Engine.is_editor_hint():
		return _blocked_from_scene(cell)
	if not _blocked_cache.has(cell):
		_blocked_cache[cell] = _blocked_from_scene(cell)
	return _blocked_cache[cell]

func _blocked_from_scene(cell: Vector2i) -> bool:
	if not inside_bounds(cell):
		return true
	var point: Vector2 = to_global(cell_to_local(cell))
	for wall in $Walls.get_children():
		var shape: CollisionShape2D = wall.get_node_or_null("CollisionShape2D")
		if shape != null and ShapeGeometry.contains(shape, point):
			return true
	return false

func enemy_actors() -> Array[BattleActor]:
	var result: Array[BattleActor] = []
	for actor in $Enemies.get_children():
		if actor is BattleActor:
			result.append(actor)
	result.sort_custom(func(a: BattleActor, b: BattleActor) -> bool:
		var ac: Vector2i = world_to_cell(a.global_position)
		var bc: Vector2i = world_to_cell(b.global_position)
		return ac.y < bc.y or (ac.y == bc.y and ac.x < bc.x))
	return result

func validation_errors() -> PackedStringArray:
	var issues := PackedStringArray()
	if rules == null:
		issues.append("Room.rules 未指定资源。")
	var bounds: CollisionShape2D = $MapBounds/CollisionShape2D
	if not bounds.shape is RectangleShape2D:
		issues.append("MapBounds 必须使用 RectangleShape2D。")
		return issues
	var relative_bounds: Transform2D = global_transform.affine_inverse() * bounds.global_transform
	if not is_zero_approx(relative_bounds.get_rotation()):
		issues.append("MapBounds 不支持旋转；请移动／缩放整个房间。")
	var dimensions: Vector2 = (bounds.shape.size * relative_bounds.get_scale()).abs()
	if dimensions.x / cell_size > 64 or dimensions.y / cell_size > 64:
		issues.append("本轮固定房间边界限 64×64 格以内。")
		return issues
	if not $PlayerSpawn/Player.position.is_zero_approx():
		issues.append("请移动 PlayerSpawn；Player 子节点局部 Position 应为 (0,0)。")
	var occupied: Array[Vector2i] = []
	var markers: Array[Node2D] = [$PlayerSpawn]
	for actor in enemy_actors():
		markers.append(actor)
		if actor.enemy_spec == null:
			issues.append("%s 未指定 Enemy Spec。" % actor.name)
	for marker in markers:
		var cell: Vector2i = world_to_cell(marker.global_position)
		if to_local(marker.global_position).distance_to(cell_to_local(cell)) > 0.1:
			issues.append("%s 不在格心；请在编辑器对齐，不会运行时偷偷吸附。" % marker.name)
		if blocked(cell) or cell in occupied:
			issues.append("%s 出生格在墙外／墙内／与其他单位重叠。" % marker.name)
		occupied.append(cell)
	for wall in $Walls.get_children():
		if wall.get_node_or_null("CollisionShape2D") == null:
			issues.append("%s 缺少逻辑碰撞来源 CollisionShape2D。" % wall.name)
	return issues

func refresh_overlays(danger: Array, targets: Array = [], candidates: Array = [], path: Array = [], push_path: Array = []) -> void:
	danger_cells = danger
	target_cells = targets
	candidate_cells = candidates
	movement_path = path
	pushed_path = push_path
	queue_redraw()

func _draw() -> void:
	if not is_node_ready() or get_node_or_null("MapBounds/CollisionShape2D") == null:
		return
	if show_grid:
		for cell in cells():
			var rect := Rect2(cell_to_local(cell) - Vector2.ONE * cell_size / 2, Vector2.ONE * cell_size)
			draw_rect(rect, grid_color, false, 1.0)
	if Engine.is_editor_hint():
		return
	for cell in candidate_cells:
		draw_circle(cell_to_local(cell), cell_size * 0.14, Color(0.65, 0.88, 1.0, 0.9), false, 2.0)
	for cell in danger_cells:
		var rect := Rect2(cell_to_local(cell) - Vector2.ONE * (cell_size / 2 - 4), Vector2.ONE * (cell_size - 8))
		draw_rect(rect, Color(0.93, 0.31, 0.24, 0.22))
		draw_rect(rect, Color(1.0, 0.46, 0.32, 0.9), false, 2.0)
		draw_line(rect.position + Vector2(8, 8), rect.end - Vector2(8, 8), Color(1, 0.55, 0.3), 2.0)
		draw_line(Vector2(rect.end.x - 8, rect.position.y + 8), Vector2(rect.position.x + 8, rect.end.y - 8), Color(1, 0.55, 0.3), 2.0)
	for cell in target_cells:
		var rect := Rect2(cell_to_local(cell) - Vector2.ONE * (cell_size / 2 - 7), Vector2.ONE * (cell_size - 14))
		draw_rect(rect, Color(0.5, 0.88, 0.8, 0.8), false, 2.0)
	for i in range(1, movement_path.size()):
		var a: Vector2 = cell_to_local(movement_path[i - 1])
		var b: Vector2 = cell_to_local(movement_path[i])
		var direction: Vector2 = (b - a).normalized()
		var side := Vector2(-direction.y, direction.x)
		draw_line(a, b, Color(0.55, 0.9, 1.0, 0.9), 2.0)
		draw_line(b, b - direction * 9 + side * 5, Color(0.55, 0.9, 1.0), 2.0)
		draw_line(b, b - direction * 9 - side * 5, Color(0.55, 0.9, 1.0), 2.0)
	for cell in pushed_path:
		var center: Vector2 = cell_to_local(cell)
		draw_arc(center, cell_size * 0.25, 0.0, PI, 12, Color(1.0, 0.8, 0.35), 2.0)
	if not blocked(hover_cell):
		var side: float = cell_size - 6.0
		draw_rect(Rect2(cell_to_local(hover_cell) - Vector2.ONE * side / 2.0, Vector2.ONE * side), Color(0.92, 0.81, 0.59, 0.65), false, 1.0)
