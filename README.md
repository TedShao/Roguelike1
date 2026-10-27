# Roguelike1

单角色回合制地牢 Roguelike。**Godot D1 已升级为 Kenney 美术、三张19×13地牢、可点击技能卡、智能左键和右键自动施放**，可在编辑器打开、编辑固定场景、运行测试；不是完整第一章。

仓库：[TedShao/Roguelike1](https://github.com/TedShao/Roguelike1)。研究、设计、Godot 工程、场景、资源与测试统一纳入 Git。

## 打开本地项目

Godot 导入仓库根目录的 [project.godot](project.godot)。当前验证版本为 **Godot 4.7.2，Compatibility，macOS Apple M3**。运行项目（F5），点击卡片选择两项基础技能开始；当前地图为 `game/scenes/rooms/maze_a.tscn`、`maze_b.tscn`、`maze_c.tscn`（旧room_*是测试夹具），主场景位于 `game/scenes/main.tscn`。

默认左键点相邻敌人普攻、点相邻空格移动；1／2选技能后单击目标施放。右键技能按钮开启环绕闪烁与自动施放，再次右键关闭；每次自动施放照常耗回合。

- **已实现：**A／B／C 三张19×13固定地牢、Kenney UI面板与图标、卡片悬停／点击粒子、三类敌人、十项基础技能选二、一步一响应、关键攻击预告、透支3回合＋结束后冷却5回合并跨房保留、防护、压力、免费重配、失败重开和房间推进。
- **尚未实现：**升级精修、符文掉落、完整构筑图鉴、NPC／商店／事件、首领、正式存档、八节点章节、声音、最终美术精修与发布导出。不会把 D1 当成完整游戏。
- **编辑入口：**[固定配置编辑指南](docs/development/editor-guide.md)；[启动脚本覆盖清单](docs/development/startup-override-audit.md)。布局保存在场景，不在启动脚本另排一套。
- **验证：**[D1 验证记录](docs/development/d1-verification.md)。103项规则回归、93项地图／图标检查、44项实际渲染与界面输入检查、56项新交互检查；这不能替代用户试玩和乐趣验证。

本轮细节：[交互与自动施放精修](docs/development/interaction-refinement.md)；[Kenney 重绘验证](docs/development/kenney-redesign-verification.md)；[素材来源与哈希](game/art/kenney/manifest.json)；[十技能图标含义](game/art/skills/manifest.json)。

2026-10-27 更新：上一阶段[第一章规格 v0.4](design/first-playable/README.md)作为实现依据。用户已授权创建并开始 Godot 初版；具体未确认数值仍是测试基准，不因此冻结平衡。

## 当前产品方向

- 单角色、一步一响应，敌人采用关键预告。
- 局内自由构筑，以少数技能配合为主，允许形成核心技能；技能主要采用回合冷却。
- 白板人物通过升级、技能加点与符文塑造能力；基础技能自由学习，稀有改造与符文主要掉落。职业感和混合能力由组合形成，路径图鉴供参考。
- 短房间遭遇串联、频繁掉落、清场后统一调整构筑。
- 清场后可免费重配；透支双倍伤害／双倍承伤，持续 3 回合，效果结束后冷却 5 回合。
- 允许成型构筑碾压普通房间。
- 题材为中文社区抽象文化融合暗黑地牢；加入可控压力／癫狂，以高风险换取强收益。
- Steam／桌面优先，网页试玩可选；2D 优先；当前初版使用 Godot，固定俯视网格；本轮采用Kenney地牢与冒险UI，风格体验仍待用户试玩。

## 文档入口

|文档|内容|
|---|---|
|[全系统完整性核查](design/systems-completeness-audit.md)|各系统真实状态、敌人／NPC／商店规格示例、首版补齐工作包|
|[启动评审与技术准备](design/development-readiness-review.md)|引擎检查、具体规则风险和战斗子原型范围|
|[当前产品设计 v0.4](design/README.md)|确认项、核心体验、当前细化方案入口|
|[首版完整规格](design/first-playable/README.md)|一章八节点，系统规则与范围；与旧稿冲突时优先采用本稿|
|[白板成长与路径图鉴](design/progression-and-atlas.md)|自由学习与加点、8 类参考能力关系、混合与转型|
|[回合与压力规则](design/combat-and-pressure.md)|透支、癫狂、超载、降压、冷却及预告规则草案|
|[技能、符文与掉落](design/builds-and-loot.md)|24 基础技能、16 符文／改造候选、6 遗物及战后整理|
|[世界与美术方向](design/world-and-art.md)|抽象文化的玩法表达、2D 优先与中性角色动作规划|
|[房间与整局节奏](design/run-and-encounters.md)|敌人职责、首领、事件及候选整局流程|
|[规划与验证](design/roadmap.md)|当前任务状态、阶段入口和待验证问题|
|[设计决定记录](research/2026-10-23/direction-decisions.md)|用户逐项选择及未确认边界|
|[研究总览](research/2026-10-23/README.md)|22 款市场样本、10 款重点机制档案与跨作品比较|
|[240 条中文评价编码](research/2026-10-23/reviews-240.md)|定性评价摘要、版本语境与原帖链接|
|[证据方法](research/2026-10-23/evidence-method.md)|采样方式、来源口径与研究局限|

研究快照日期：2026-10-23。评价为目的抽样，不代表玩家总体观点比例；设计草案尚未通过实际游玩验证。
