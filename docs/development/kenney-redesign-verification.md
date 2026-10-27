# Kenney 重绘与大地图验证

日期：2026-10-27。基线：999adcd；本轮只改画面、布局、固定关卡内容、技能卡交互和寻路查询缓存。`battle_model.gd`、敌人规格、技能数值、规则资源未改变。状态统一见 [roadmap](../../design/roadmap.md)。

## 玩家可见变化

- Tiny Dungeon 原始16×16 atlas负责角色、石墙、地面、门和火焰摆件，场景采用48像素格、Nearest过滤；三关分别是众说回廊、抬杠石庭、回声档案室。
- 每关19×13格，总面积247格；可走162／157／160格。旧7×7关卡保留为规则测试夹具。新布局有绕行通道、分隔墙、石柱和视线遮挡，敌人数3／3／4。
- UI采用 Kenney UI Pack Adventure 的纸面、金属角、红色横幅、按钮、进度条；Game Icons用于选中与状态图形。1440×900参考画布，地图为主体，右侧三段信息区，底部操作栏。
- 技能选择采用可点击卡片：点击选中，再次点击取消；悬停高亮、图标放大12%，点击缩放回弹和SVG粒子。没有设置页式的开关；需要恰好两项能力才能出发。
- 十技能图标各自独立、按机制表达。6个以Kenney 1-Bit武器／盾符号加效果标记，4个为补足语义的项目原创SVG；不是把原创图标冒充Kenney原件。完整对应见 [图标来源表](../../game/art/skills/manifest.json)。

## 技术验证

环境：Godot4.7.2官方版，Compatibility，macOS Apple M3。测试通过CLI调用同一个实际工程；图形检查使用OpenGL渲染窗口，没有浏览器替身。未制作发行导出，以下毫秒数不等同于发行版本帧率。

|检查|结果|证据|
|---|---|---|
|既有规则与场景编辑回归|103项通过|`tests/test_runner.gd`；透支3＋5、跨房、冷却、防护、技能、伤亡优先级及形状保存重载|
|新地图与图标|93项通过|`tests/maze_suite.gd`；全地板可达、出生／出口合法、每关正常规则清场、独立图标图像哈希、编辑保存重载|
|实际渲染与界面输入|44项通过|`tests/render_smoke.gd`；实际GUI悬停／点击／取消／粒子、键盘一步移动、三关连续推进、跨房状态、重开和字体|
|连续通关|A15／B17／C22行动，最终30生命、20压力|测试驱动以正式 `main.submit` 执行动作；不加血、不改伤害、不改敌人状态、不重置跨房冷却|
|单关独立通关|A15／B16／C22行动|每关从规则初始状态开始，因此B与连续通关差1行动|
|分辨率|1440×900、1280×800、1920×1080通过|实际窗口截图；保持宽高比，非同宽高比会留边|
|固定配置修改|通过|另存新A场景，把出口由(840,72)改(792,120)、Shape改38×40；生产控制器加载后位置／形状／点击命中保持|
|寻路耗时|每次响应平均由A72.94/B86.60/C113.78ms降至3.76/3.96/4.49ms|同机器，同三张图前5次wait；含首次缓存查询。缓存只从现有碰撞节点推导，bind_room清空，编辑器不缓存|
|原始素材与存档|保留|旧prototype/*.svg未改；Kenney原PNG与许可证按原字节复制；D1无正式存档写入|

本地截图和JSON在被Git忽略的 `artifacts/kenney-*`；可复现入口如下（把Godot命令替换为本机可执行文件）：

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/test_runner.gd
godot --headless --path . --script tests/maze_suite.gd
godot --path . --script tests/render_smoke.gd
```

## 证据边界与下一轮

通关由测试用一步前瞻策略驱动，不是真人盲玩，也不证明“上瘾”或平衡良好。地图变大且有环路，不等于探索奖励已经实现：当前敌人仍按原规则全房响应；升级、掉落、符文、NPC、商店、首领、声音、正式存档仍在D2/D3待办。当前弹窗是基础技能选择，不是已实现完整职业路径图鉴。

需要用户试玩判断：地图是否仍空、敌人聚集节奏是否合理、图标能否不看说明就分辨、卡片点击是否明确、悬停和粒子是否过量。低端机器、Windows、手柄完整导航、屏幕阅读器、动态改墙和正式发布导出未测。

## 资产出处

[Kenney Tiny Dungeon](https://kenney.nl/assets/tiny-dungeon)、[UI Pack Adventure](https://kenney.nl/assets/ui-pack-adventure)、[UI Pack Pixel Adventure](https://kenney.nl/assets/ui-pack-pixel-adventure)、[Game Icons](https://kenney.nl/assets/game-icons)、[1-Bit Pack](https://kenney.nl/assets/1-bit-pack)。均保留包内CC0许可证；下载ZIP和入库原件SHA-256见 [素材清单](../../game/art/kenney/manifest.json)。UI Pixel Adventure官网版本和包内许可证版本不同，清单明确标记。
