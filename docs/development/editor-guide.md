# Godot 编辑指南：固定场景是唯一布局来源

日期：2026-10-26。工程入口是仓库根目录 `project.godot`。当前为 D1 三房战斗切片，Godot 4.7.2 / Compatibility；不是第一章完整内容。

## 打开和运行

1. Godot 项目管理器选择“导入”，选本地仓库的 `project.godot`，打开编辑器。
2. 双击 `game/scenes/rooms/room_a.tscn`，切到顶部 **2D**。另外两房为 `room_b.tscn`、`room_c.tscn`。
3. 编辑器内修改“本地”场景并保存；运行中的“远程”节点修改不会成为长期配置。
4. 运行项目（F5 或右上角三角按钮），主场景是 `game/scenes/main.tscn`。不要用 F6 单独运行房间来测试战斗，房间自身没有主控制器／HUD。
5. 开局十项基础技能任选两项。WASD／方向键移动，1／2 选技能，鼠标第一次预览、再次点击同目标执行，右键／Esc 取消。普通攻击有独立按钮；空格等待、Q 稳神、R 为下一次有效行动开启透支。硬撑和护体结界点击即执行。

## 在哪里修改

下表中的房间路径都相对于 `RoomA`／`RoomB`／`RoomC` 根节点；同类房间结构一致。

|要调整的内容|节点／资源|Inspector 属性与关联检查|
|---|---|---|
|整间房在游戏窗口的位置|`main.tscn → Game/RoomHost`|Transform → Position，当前 (64,172)。整体移动房间、边界、角色、出口；HUD 独立|
|单个房间整体缩放／移动|房间根节点|Transform；保持房内格心关系。主场景只实例化，不重新设置位置|
|房间名称与说明|房间根节点|Display Name、Encounter Note；运行时填入 HUD|
|地面贴图／铺设尺寸|`Ground`|Texture、Region → Rect、Texture Repeat、Transform。当前 Region 476×476；**仅视觉，不决定可走范围**|
|地图边界|`MapBounds` 及其 `CollisionShape2D`|父节点 Position 当前 (238,238)，Shape → Size 当前476×476。矩形应与网格平行；不支持单独旋转边界|
|格子间距与网格原点|根节点 Cell Size；`GridOrigin`|68；Position (34,34)。格心公式＝原点＋格坐标×间距；改间距后自行对齐墙、出生点和边界，脚本不会另排一套布局|
|墙体整体位置／大小|`Walls/Wall_x_y`|Transform → Position／Scale，同时影响图像与碰撞。阻挡取实际 CollisionShape2D 覆盖的格心|
|墙体贴图或精细碰撞|墙体下 `Sprite2D`、`CollisionShape2D`|Texture／Scale；Shape → Size。只改 Sprite 的 Scale **不会**改变碰撞，请分别核对|
|玩家出生点|`PlayerSpawn`|Transform → Position；移动 Marker，不要移动其 `Player` 子节点。Player 局部位置保持(0,0)|
|敌人出生位置／类型|`Enemies/Chaser1` 等实例|Transform → Position；Enemy Spec 引用 `game/data/enemies/*.tres`。初始位置决定稳定的 y、x 响应排序|
|角色贴图与美术尺寸|角色实例下 `Feedback/Sprite2D`|Texture、Transform → Scale／Position；Feedback 自身是动态动画层，不作为长期美术偏移层|
|角色点击范围|角色实例下 `SelectionArea/CollisionShape2D`|Shape → Size、Position。角色根节点移动会带着范围和血量提示一起移动|
|角色头顶血量位置|角色实例下 `Vitals`|Layout → Transform／Offsets、字体／颜色。Text 是运行时生命与状态，不要在这里改生命值|
|出口整体位置／大小|`Props/ExitGate`|Transform → Position／Scale。A 房已实际从(536,370)改为 **(548,352)**；B、C仍为(536,370)|
|出口图像|`Props/ExitGate/Sprite2D`|Texture、Scale；与下方交互形状分别可调|
|出口交互范围|`Props/ExitGate/InteractionArea/CollisionShape2D`|Shape → Size（默认92×100）、Position。鼠标命中读取此形状，不用另一个像素距离|
|出口悬停提示与常驻文字|`Props/ExitGate/Prompt`、`ExitCaption`|Text、Offsets、字体。Prompt 只在悬停时显示；Text 和位置不被脚本重写|
|出口交互用途|`Props/ExitGate`|Interaction ID 当前 `exit`；D1 只支持此用途，不会自动生成 NPC／商店|
|技能数值与说明|`game/data/skills/*.tres`|Damage、Reach、Cooldown、Push Distance 等；Description 是人工说明，修改数值时一并核对。Skill ID 是行为标识，不随意改名|
|敌人数值与行为说明|`game/data/enemies/*.tres`|Max Health、Damage、Reach、Pressure、Description；Kind 对应 chaser／heavy／speaker|
|生命、透支和压力数值|`game/data/rules.tres`，房间根 Rules 引用|Inspector 导出字段；v0.4 测试基准，改变数值属于后续设计迭代，不是调整美术|
|HUD 布局和配色|`main.tscn → HUD/Root`；`game/ui/theme.tres`|各 Control 的 Offsets、容器间距／最小尺寸；Theme 样式、字体。容器子节点由 Godot 按约束排布，不要直接拖子按钮来对抗容器|
|房间流程顺序|`main.tscn → Game`|Encounter Scenes 数组与 RoomHost 初始实例应对应；当前 A→B→C。不是地图位置数组|
|动态动画／SVG 粒子|各角色 `AnimationPlayer`、`HitParticles`|动画轨道仅写 Feedback；粒子 Texture、Lifetime、Amount 等保存在场景，受击时 restart。不要覆盖 SVG 原稿，新增变体文件再引用|

## 实例、资源和碰撞的注意点

房间已为墙体、角色和出口打开“可编辑子节点”，可以在房间内展开修改子节点。若新加实例没有展开内容，右键实例根节点勾选该选项。修改共用原始场景会影响所有未覆盖它的实例；只改一个房间，应在该房间保存实例覆盖。

碰撞 Shape 已标记 `Local To Scene`。若要独立调整某个 Shape／Theme／规格资源，先确认它是否共用，必要时在资源下拉菜单选择“设为唯一”。Godot 保存时可能展开本地 Shape 子资源，这是正常的场景序列化，不是脚本覆盖。

这里是离散网格规则，不使用连续物理推挤：墙体实际 Shape 决定阻挡，边界要求整格都在矩形内，单位占格由战斗状态判定。更改碰撞层／掩码不会取代这套网格占用判断；不支持 PolygonShape 或任意导航网格。通用形状查询支持 RectangleShape2D 和 CircleShape2D；地图边界限矩形、64×64格以内。

出生点必须在格心且不在墙内，不得与其他单位重叠。启动校验发现不合法位置会显示错误，不会悄悄把节点吸附回默认位置。墙体轮廓和可走格由当前场景推导，没有维护第二份墙数组。

## 推荐修改检查顺序

先改出口根节点 Position 并保存、运行，确认图像和提示跟随、清场后能点击进入下一房；再改局部图像尺寸并核对交互形状。修改出生点时同时看 GridOrigin、Cell Size、MapBounds 和 Walls。修改地面范围时同时看边界，但不要把地面贴图当作碰撞。

运行后的角色位移、血量、冷却、提示显隐、选择预览、粒子和动画是正常动态行为。固定节点的贴图、位置、尺寸与形状不在启动时重设。详见[覆盖审计](startup-override-audit.md)与[验证记录](d1-verification.md)。
