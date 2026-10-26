class_name EnemySpec
extends Resource

@export_enum("chaser", "heavy", "speaker") var kind: String = "chaser"
@export var display_name: String = "跟风者"
@export var max_health: int = 10
@export var damage: int = 3
@export var reach: int = 1
@export var pressure: int = 0
@export_multiline var description: String = "相邻攻击 3，否则靠近一格。移动与攻击不在同一响应发生。"

