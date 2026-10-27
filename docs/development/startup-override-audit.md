# 启动覆盖审计

2026-10-27 更新：D1 Kenney 重绘和大地图。原 D1 的实际编辑证据保留在后文。检查 `.gd` 赋值、场景动画轨道、原生保存重载测试和实际编辑器操作。开始前仓库只有研究／设计文档，没有旧 Godot 工程、原始游戏素材或用户存档。

## 结论与依据

固定布局只存于 `.tscn`，技能／敌人数值存于 `.tres`。主控制器没有生成格子、铺墙、重排房间或重新指定固定贴图的代码；FixedRoom 的 `@tool` 只绘制网格预览；SkillCard 的 `@tool` 根据绑定的技能资源显示图标和说明。所有程序代码均在仓库中，不依赖仓库外的布局生成程序。

|检查项|启动／刷新是否覆盖|证据|
|---|---|---|
|Ground、墙体、出口的 Position／Scale／Texture|否|[main.gd](../../game/scripts/main.gd) `_ready`、`bind_room` 只取现有 RoomHost 子场景；`replace_room` 重建保存的 PackedScene，不给固定节点赋变换或贴图|
|地图边界、墙体碰撞形状／尺寸|否|[fixed_room.gd](../../game/scripts/fixed_room.gd) `cells`、`inside_bounds`、`blocked` 读取节点；[shape_geometry.gd](../../game/scripts/shape_geometry.gd) `contains` 使用实际 shape 和完整逆变换|
|出生点|否|[battle_model.gd](../../game/scripts/battle_model.gd) `_init` 从 `room.player_cell()` 和 `enemy_actors()` 读取；初始 Player 是 Marker 子节点，没有启动坐标纠正|
|出口交互范围与提示偏移／文字|否|[fixed_interactable.gd](../../game/scripts/fixed_interactable.gd) `contains_world_point` 读取子形状，`set_hovered` **只写 Prompt.visible**；图像、范围与提示都是 ExitGate 子节点|
|角色 Sprite 的 Texture／Scale／Position|否|角色[场景](../../game/scenes/actors/player.tscn)持有属性；动画目标是专用 `Feedback` 节点，不写 Sprite2D 的长期美术配置|
|角色根节点运行位置|**是，正常战斗移动**|`main.gd` `submit`：Tween `actor.global_position`，无动画时直接赋值；目标从已验证行动的格坐标换算，包含玩家、追击和击退。重启从保存场景恢复出生点|
|Feedback 位移与颜色|**是，正常动画**|各角色 AnimationPlayer 的 `idle`／`attack` 写 `Feedback:position`；`hit` 写 `Feedback:modulate`；`battle_actor.gd` 触发并恢复 idle|
|粒子状态|**是，正常受击效果**|`battle_actor.gd` `play_hit` 调用 `HitParticles.restart()`、设置 emitting；Texture、数量、寿命与尺寸由场景定义，不在脚本重设|
|角色血量 Label 和敌人显隐|**是，动态状态**|`battle_actor.gd` `set_vitals` 写 Vitals.text；`main.gd` `refresh` 在事件播放后按 hp 改 visible。HP 由规则资源初始化，不读取 Label 占位文字|
|HUD 标题、提示、数值、按钮文本／可用状态|**是，动态信息**|`main.gd` `bind_room`、`refresh`、`choose`、`update_hover`、`show_loadout` 等；房间名取根节点属性，技能名称／说明取 SkillSpec。状态文字不能作为静态设置入口|
|HUD 固定位置／尺寸|无脚本重写|`main.tscn` 保存 Control、Panel、VBox/HBox 的约束；Godot 容器会自动排子项，属于场景内布局规则。没有每帧写按钮坐标的代码|
|网格、危险预告、目标／鼠标提示|**动态绘制**|`fixed_room.gd` `_draw`；用现有 GridOrigin、Cell Size、边界生成临时画线，不生成或修改固定节点|
|房间刷新／重新开始|重新实例化保存场景|`advance_room` 保留 HP、压力、透支持续／冷却；`restart_run` 从 Encounter Scenes[0] 重新开始。不会把保存场景替换成写死坐标|
|技能、敌人、规则资源|只读，不写回|BattleModel 内独立保存当前 HP、冷却、状态和占格；不修改规格资源或保存 `.tres`|
|用户存档|无读写|D1 没有正式保存功能，没有读取／写入 `user://` 游戏存档。测试只写被忽略的 `artifacts/`。Godot 自身仍可生成正常缓存和日志|

鼠标输入使用事件自己的 viewport 坐标，经 canvas 逆变换得到世界坐标，再查询场景真实形状；不依赖轮询操作系统指针的另一个位置。相机／房间整体平移不会引入另一套点击区域。

## 实际验证

- 在 Godot Inspector 内将 A 房 `Props/ExitGate` Position `(536,370)` 改为 `(548,352)`，保存到原房间场景；随后真实运行 A 房清场并点击新位置，成功进入 B 房。这个编辑结果保留在提交中。
- 原生测试另存 `artifacts/edited-room-verification.tscn`，修改出口贴图、父缩放、Sprite缩放、Shape尺寸、Prompt文字、出生点和一段墙的位置；通过生产控制器加载、刷新、重启，断言配置保留。
- 测试平移出口父节点 `(20,10)`，分别核对图像、Shape 和 Prompt 的全局位移均一致。
- 实际渲染检查确认战后按钮不出窗口、预告覆盖三格、编辑后的出口重启后仍在新位置。

源码路径是可搜索的审计依据；行号会随修订变化，优先按上述函数定位。运行规则验证不代表已验证游戏乐趣或完整一章。

参考 Godot 官方：[导出属性](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_exports.html)、[场景组织](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)。

## Kenney 重绘增量审计

- `maze_a/b/c.tscn` 是新增19×13关卡的唯一布局源。`Ground` 下地砖、`Walls` 下墙及光源、出生点、出口全部已序列化；工程不需要任何外部生成程序才能运行。
- `FixedRoom._blocked_cache` 只缓存 `_blocked_from_scene` 对真实形状的查询结果；`main.bind_room` 清空缓存。无持久化坐标表，也不把缓存反写场景。运行时改墙需显式失效缓存，编辑器不使用缓存。
- `skill_card.gd._ready` 读取其 Skill 资源，写 Icon.texture、Title／Description／Cooldown 文本。这些是内容绑定，长期改图标应改 SkillSpec.icon。节点的 Offsets／贴图原件不被启动脚本重写。
- `hover`／`on_toggled` 临时写 Icon.scale、Highlight 透明度和 ClickParticles 状态；`update_selection` 更新选中标记和文字颜色。这是用户要求的交互反馈，动画不移动卡片根节点。
- HUD 的技能栏读取 SkillSpec.icon，技能名、可用／冷却文字会刷新；控件位置与尺寸仍在 main.tscn。纸面、按钮和条形图纹理保存在 game/ui/*.tres。
- 48像素格子的悬停框从 Cell Size 派生，修复旧60像素固定框。动画、SVG粒子、生命／压力规则未更改。
- 新地图保存重载测试把出口改到(792,120)、交互Shape改为38×40，经生产控制器读取后仍保持且可命中。测试文件只写 artifacts，不触及用户存档。


## 2026-10-27 智能交互与自动边框

`main.gd` 写技能按钮的动态选中态、冷却文字、tooltip和自动启用态；不写按钮位置／尺寸／图像源布局。`auto_skill_button.gd` 根据按钮当前size绘制环绕边框，仅启用时刷新phase；颜色与周期在主场景属性配置。`fixed_room.gd` 新增候选点、位移线和推移弧线均为动态覆盖绘制；固定地板、墙体、地图边界、出生点仍只由保存场景读取。`autocast_planner.gd` 不修改规则或场景，候选最终交由原preview校验和execute提交。当前用户的project.godot既有修改保持原样。
