# farm-sim P2 · 内容与深度 实现计划

> **执行方式:** 本计划由主会话 inline 执行(executing-plans),每个 Task 独立可测、结尾一次 headless 断言 + 一个编辑器 F5 检查点。Task 之间做完一批停下让需求方 F5。步骤用 `- [ ]` 追踪。

**Goal:** 把已成型的 vertical slice(P0+P1)扩成有季节轮替、天气、工具升级、任务/成就 UI、多语言、音效的"有内容"农场游戏。

**Architecture:** 继续走 `world.gd`(真实游戏根)+ 逻辑/表现分离。P2 复用三个已写好但只接在旧 dogfood `game.gd` 的组件(`weather_system.gd` / `quest_log.gd` / `achievement_tracker.gd`),把它们接进 `world.gd`;新增视觉/UI 层与程序化音频。数据缺口(作物季节、季节作物、季节作物 item、音频)全部就地补齐,音频用代码生成 `AudioStreamWAV`,零二进制资产。

**Tech Stack:** Godot 4.7 GDScript;core-kit 门面(`CoreKit.clock/bus/i18n/audio/layers/settings/saves`)+ off-facade 类库(`KitDataRegistry` / `KitInventory` / `KitUiStack` / `KitRebindList`)。

## Global Constraints(每个 Task 隐含遵守)

- **分支纪律**:全部改动留在 `example/farm-sim` 分支,**不升版本号、不 ff-merge 到 main**(这是示例/游戏代码,非 kit 改动)。
- **不碰 kit 内部**:只 `CoreKit.*` 与 class_name 类库消费门面;不改 `addons/godot-core-kit/**`(P2 若发现 kit 缺口,记进"反哺候选",不在本计划里改 kit)。
- **不动旧 dogfood**:`game.gd`/`game.tscn` 及其组件保持可跑(kit 回归);P2 只**新增接线**到 `world.gd`,复用组件时不改其对外行为(必要时只加可选参数、保持默认等价)。
- **GDScript 坑**:RHS 来自无类型注入对象(`_bag`/`_shop`/`_grid`/`def`/`payload` 等)时用 `var x =`,**不要 `:=`**(否则 "Cannot infer type" parse error)。
- **缩进用 Tab**。
- **验收门**:每个 Task 结尾 `powershell -File test\run_all.ps1` 必须仍 `=== SUMMARY FAILS=0 ===`;farm-sim 端到端 `FARM_SMOKE=1` 跑通打印 `[World][SMOKE] PASS`。
- **git 提交**:每个 Task 一个 commit,message 结尾 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`;用 Bash `git commit -F - <<'EOF' … EOF` heredoc。

## 文件结构(P2 新增/修改)

| 文件 | 责任 | Task |
|---|---|---|
| `examples/farm-sim/crop_def.gd` | +`seasons: Array` 字段(空=全季) | 1 |
| `examples/farm-sim/data/crops/pumpkin.tres` | 秋季限定作物(南瓜) | 1 |
| `examples/farm-sim/data/items/pumpkin_seed.tres` / `pumpkin.tres` | 南瓜种子/产物 | 1 |
| `examples/farm-sim/farm_grid.gd` | `plant` 加季节门;`advance_day` 加生长加成参数 | 1,2 |
| `examples/farm-sim/weather_view.gd` | 雨天视觉覆盖层(占位) | 2 |
| `examples/farm-sim/log_panel.gd` | 任务/成就日志面板 | 4 |
| `examples/farm-sim/settings_panel.gd` | 音量滑条 + 语言切换 + 键位重绑定 | 5,6 |
| `examples/farm-sim/i18n_strings.gd` | 内存 zh/en 翻译表 + key 化 helper | 5 |
| `examples/farm-sim/audio_bank.gd` | 程序化 `AudioStreamWAV` 音效/BGM | 6 |
| `examples/farm-sim/world.gd` | 接线全部 P2 系统 + 输入派发 | 1-6 |
| `examples/farm-sim/hud.gd` | 季节/天气/语言 key 化显示 | 1,2,5 |
| `examples/farm-sim/pause_menu.gd` | +"设置"入口 | 5 |
| `examples/farm-sim/shop_panel.gd` | +工具升级购买行 | 3 |
| `project.godot` | +`toggle_log` 输入动作(L) | 4 |
| `test/test_farm_season.gd` | 季节门 + 天气加成 headless 测 | 1,2 |

---

### Task 1: 季节系统 + 季节限定作物

**Files:**
- Modify: `examples/farm-sim/crop_def.gd`(+`seasons` 字段)
- Modify: `examples/farm-sim/farm_grid.gd`(`plant` 加季节门)
- Create: `examples/farm-sim/data/crops/pumpkin.tres`、`data/items/pumpkin_seed.tres`、`data/items/pumpkin.tres`
- Modify: `examples/farm-sim/world.gd`(configure 时钟 7 天/季;plant 传当前季;起始给南瓜种子;out-of-season 播种提示)
- Modify: `examples/farm-sim/hud.gd`(选中种子行标注季节不符)
- Create: `test/test_farm_season.gd`

**Interfaces:**
- Produces:
  - `CropDef.seasons: Array`(元素 StringName;空数组 = 全季可种)
  - `FarmGrid.plant(cell: Vector2i, crop_id_arg, season := &"") -> bool`(season 非空且作物 seasons 非空且不含 season → 返回 false 不消耗种子;season 为 `&""` 时跳过季节校验,保持旧行为)
  - `FarmGrid.crop_plantable(crop_id, season) -> bool`(纯查询,供 HUD/plant 复用)

- [ ] **Step 1:** `crop_def.gd` 末尾加字段:
```gdscript
@export var seasons: Array = []   ## 可种植季节(StringName,如 [&"fall"]);空 = 全季可种
```

- [ ] **Step 2:** 建三个 .tres(照 `turnip.tres` 格式,`load_steps=2`,ext_resource 指向 crop_def.gd/item_def.gd):
  - `data/crops/pumpkin.tres`:`id=&"pumpkin"`,`display_name="南瓜"`,`grow_days=5`,`seed_item=&"pumpkin_seed"`,`harvest_item=&"pumpkin"`,`harvest_amount=1`,`seasons=[&"fall"]`
  - `data/items/pumpkin_seed.tres`(照 `potato_seed.tres`):`id=&"pumpkin_seed"`,`display_name="南瓜种子"`,`category=&"seed"`,`buy_price=30`,`sell_price=0`,`max_stack=99`
  - `data/items/pumpkin.tres`(照 `potato.tres`):`id=&"pumpkin"`,`display_name="南瓜"`,`category=&"produce"`,`buy_price=0`,`sell_price=120`,`max_stack=99`

- [ ] **Step 3:** `farm_grid.gd`:加 `crop_plantable` + `plant` 季节门。`plant` 现有签名是 `plant(cell, crop_id_arg)`,改为带默认参数保持向后兼容:
```gdscript
## 该作物在给定季节能否种(seasons 空=全季;season 为 &"" 视为不校验)。
func crop_plantable(crop_id_arg, season: StringName) -> bool:
	if season == &"":
		return true
	var def = _registry.get_def_or(&"crop", crop_id_arg, null)
	if def == null:
		return false
	var ss: Array = def.seasons
	return ss.is_empty() or ss.has(season)
```
在 `plant` 的既有校验(TILLED/WATERED + 无作物 + 背包有种子)之前插入:
```gdscript
	if not crop_plantable(crop_id_arg, season):
		return false
```
`plant` 签名改为 `func plant(cell: Vector2i, crop_id_arg, season: StringName = &"") -> bool:`。

- [ ] **Step 4:** `world.gd::_ready`:
  - 载作物目录后即 `CoreKit.clock.configure({"days_per_season": 7})`(四季一年内可达;放在订阅前)。
  - 起始背包加 `_bag.add(&"pumpkin_seed", 5, {}, 99)`。
  - `_use_tool` 里 `plant` 调用改为 `_grid.plant(c, _selected_crop, CoreKit.clock.season_name())`;plant 失败且原因是季节不符时打印提示:
```gdscript
	else:
		var season := StringName(CoreKit.clock.season_name())
		did = _grid.plant(c, _selected_crop, season)
		if did:
			CoreKit.log.info("[World] 播种 %s @ %s" % [_selected_crop, c])
		elif not _grid.crop_plantable(_selected_crop, season):
			CoreKit.log.info("[World] %s 不在当季(%s)可种" % [selected_crop_name(), CoreKit.clock.season_name()])
		else:
			did = _grid.water(c)
			if did: CoreKit.log.info("[World] 浇水 @ %s" % c)
```

- [ ] **Step 5:** `hud.gd`:选中种子行加当季标注(需 world 暴露 `selected_crop_plantable() -> bool`)。`world.gd` 加:
```gdscript
func selected_crop_plantable() -> bool:
	return _grid.crop_plantable(_selected_crop, StringName(CoreKit.clock.season_name()))
```
`hud.gd::_process` 的 `_seed_label` 改:
```gdscript
		var ok_season: bool = _world.selected_crop_plantable()
		_seed_label.text = "选中: %s%s (Q 切换)" % [
			_world.selected_crop_name(), "" if ok_season else " [非当季]"]
```

- [ ] **Step 6:** 写 `test/test_farm_season.gd`(`extends SceneTree`,运行时 `load()` 不顶层 preload,不依赖 CoreKit;直接 new FarmGrid/KitInventory/KitDataRegistry)。断言:
  - 载 crop/item 目录后 `registry.get_def(&"crop",&"pumpkin").seasons == [&"fall"]`
  - `grid.plant(cell, &"pumpkin", &"spring")` == false 且 `bag.count(&"pumpkin_seed")` 不变(未消耗)
  - `grid.till(cell)` 后 `grid.plant(cell, &"pumpkin", &"fall")` == true 且种子 -1
  - `grid.crop_plantable(&"turnip", &"winter")` == true(turnip seasons 空=全季)
  结尾 `print("test_farm_season: ALL PASS"); quit(0)` 或失败计数 quit(1)。
  > 注:KitDataRegistry/KitInventory 是 class_name,首次需 `godot --headless --path . --import` 生成缓存(run_all 已含 import 步)。

- [ ] **Step 7:** 跑 `test/test_farm_season.gd` 单测(见验收命令),确认 ALL PASS。

- [ ] **Step 8:** 把 `'test_farm_season'` 加进 `test/run_all.ps1` 的 `$tests` 数组(farm 相关测一组,置于 `'test_core_kit'` 之前)。跑 `powershell -File test\run_all.ps1` → `FAILS=0`。

- [ ] **Step 9:** 更新 `world.gd::_run_smoke`:选种循环断言里作物数从 3→4(现有 `_crop_ids.size() >= 3` 改 `>= 4`);smoke 用 `turnip`(全季)不受季节门影响,无需改播种断言。跑 `FARM_SMOKE=1` 确认 `[World][SMOKE] PASS`。

- [ ] **Step 10:** commit `feat(farm-sim P2): 季节系统 + 秋季限定作物南瓜（clock 7天/季 + plant 季节门）`。

---

### Task 2: 天气可见 + 雨天生长加成

**Files:**
- Modify: `examples/farm-sim/farm_grid.gd`(`advance_day` 加生长加成参数)
- Create: `examples/farm-sim/weather_view.gd`(雨天视觉覆盖)
- Modify: `examples/farm-sim/world.gd`(接 `weather_system.gd`;生长改由 `weather:changed` 驱动;挂 weather_view)
- Modify: `examples/farm-sim/hud.gd`(显示当前天气)
- Modify: `test/test_farm_season.gd`(加天气加成断言)

**Interfaces:**
- Consumes: `weather_system.gd`(已存在)`EV_CHANGED = "weather:changed"`,payload `{day, kind, growth_bonus}`;`WeatherSystem.current_kind() -> StringName`;`name_of(kind)`。
- Produces:
  - `FarmGrid.advance_day(bonus: int = 0) -> void`(每株非成熟作物长 `1 + max(0,bonus)` 格)
  - `WeatherView.bind(weather_system)` + 订阅 `weather:changed` 显隐雨幕

- [ ] **Step 1:** `farm_grid.gd::advance_day` 加参数(默认 0 → 旧行为不变):
```gdscript
## 逐日生长:每株未成熟作物 +（1+bonus）格。bonus 由天气注入(雨天 +1)。
func advance_day(bonus: int = 0) -> void:
	var step := 1 + maxi(0, bonus)
	for cell in _crops.keys():
		var c = _crops[cell]
		if int(c["stage"]) < int(c["grow_days"]):
			c["stage"] = mini(int(c["grow_days"]), int(c["stage"]) + step)
```
（按 `farm_grid.gd` 现有 `_crops` 内部结构调整字段名;保持"成熟即封顶"语义。）

- [ ] **Step 2:** 写 `weather_view.gd`（`extends CanvasItem`/`Node2D`,占位视觉）:`bind(weather)` 存引用并订阅 `WeatherSystem.EV_CHANGED`;`_on_weather(payload)` 存 `_rainy = payload.kind == &"rainy"` 并 `queue_redraw()`;`_draw()` 雨天铺一层半透明冷色矩形(覆盖视口)+ 几条斜向雨线(占位,`draw_line`)。挂在 world 下、玩家之上、HUD 之下(HUD 在 CoreKit.layers"hud",天然更高)。
```gdscript
extends Node2D
## 天气视觉(P2 占位):雨天铺半透明冷色 + 斜雨线。真素材/粒子留 P5。
var _rainy := false
func bind(weather) -> void:
	CoreKit.bus.subscribe(weather.EV_CHANGED, _on_weather)
func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)
func _on_weather(payload: Dictionary) -> void:
	_rainy = payload.get("kind", &"") == &"rainy"
	queue_redraw()
func _draw() -> void:
	if not _rainy: return
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.3, 0.4, 0.6, 0.18))
	for i in range(24):
		var x := float((i * 53) % int(vp.x))
		draw_line(Vector2(x, 0), Vector2(x - 12, vp.y), Color(0.7, 0.8, 1.0, 0.25), 1.0)
```
> 注:覆盖层用视口坐标要跟随相机。占位阶段直接用 `CanvasLayer` 更稳:把 weather_view 挂到 `CoreKit.layers` 的一个层(如新层名 `"weather"`,z 在 hud 之下)或 world 下的独立 `CanvasLayer`。实现时选 CanvasLayer 承载,`_draw` 用 `get_viewport_rect()`。

- [ ] **Step 3:** `world.gd::_ready`:
  - 在订阅时钟之前 `add_child` 一个 `WeatherSystem`(`preload weather_system.gd` → new → name="Weather" → add_child)。它 `_ready` 订阅 `clock:day_changed`,须早于任何 advance。
  - 挂 weather_view(CanvasLayer 承载),`bind(weather)`。
  - **改生长驱动**:删掉 `CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_day)`,改订阅 `weather.EV_CHANGED` → `_on_weather`。原因:weather 在 `clock:day_changed` 处理里 **嵌套** publish `weather:changed`,由 world 在此长作物,保证"先定天气再生长"的事件链顺序(与 dogfood crop.gd 同构)。
```gdscript
func _on_weather(payload: Dictionary) -> void:
	var bonus := int(payload.get("growth_bonus", 0))
	_grid.advance_day(bonus)
	_view.queue_redraw()
	if bonus > 0:
		CoreKit.log.info("[World] 雨天,作物加速生长 +%d" % bonus)
```
  - 删除旧 `_on_day`(或留空引用)。

- [ ] **Step 4:** `hud.gd`:加天气显示(world 暴露 `weather_name() -> String`)。`world.gd`:
```gdscript
func weather_name() -> String:
	return _weather.name_of(_weather.current_kind()) if _weather != null else ""
```
HUD `_date_label` 追加天气,或加一行 `_weather_label`:`"天气: %s" % _world.weather_name()`。

- [ ] **Step 5:** 更新 `world.gd::_run_smoke`:现在生长经 `weather:changed`。smoke 里 `CoreKit.clock.advance_day()` 会触发 weather→world 生长链(weather 已入树)。断言"advance grow_days 天后成熟"仍成立(雨只会加速,成熟是 stage>=grow_days 封顶);把逐日循环后的 `crop_mature` 断言保留。若 smoke 依赖精确 stage,改为 `>=` 判定。

- [ ] **Step 6:** `test_farm_season.gd` 加断言:`grid` 种一株后 `grid.advance_day(0)` 长 1;再 `advance_day(1)` 多长 2(共 3);验证 bonus 生效。

- [ ] **Step 7:** 跑 `run_all.ps1`(FAILS=0)+ `FARM_SMOKE=1`(PASS)。

- [ ] **Step 8:** commit `feat(farm-sim P2): 接入天气系统 + 雨天视觉覆盖 + 生长加成（事件链 clock→weather→grid）`。

---

### Task 3: 工具升级(3×3 浇水)

**Files:**
- Modify: `examples/farm-sim/world.gd`(`_water_radius` + 区域浇水 + 购买升级 + 存档)
- Modify: `examples/farm-sim/shop_panel.gd`(+升级购买行)

**Interfaces:**
- Produces:
  - `World.water_radius() -> int`、`World.buy_water_upgrade() -> bool`(费用固定,如 200;成功 `_water_radius=1` 并扣金币,幂等:已升级返回 false)
  - 存档新增键 `"water_radius"`

- [ ] **Step 1:** `world.gd`:加 `var _water_radius := 0` 与 `const WATER_UPGRADE_COST := 200`。
```gdscript
func water_radius() -> int: return _water_radius
func water_upgraded() -> bool: return _water_radius > 0
func buy_water_upgrade() -> bool:
	if _water_radius > 0 or _shop.gold < WATER_UPGRADE_COST:
		return false
	_shop.gold -= WATER_UPGRADE_COST
	_water_radius = 1
	CoreKit.log.info("[World] 水壶升级:浇水范围 3×3")
	return true
```

- [ ] **Step 2:** `world.gd::_use_tool` 浇水分支改为区域浇水:凡"浇水"动作(种下后再按、或对已耕地按),浇 facing cell + 半径内所有可浇格。抽 helper:
```gdscript
func _water_area(center: Vector2i) -> bool:
	var any := false
	for dy in range(-_water_radius, _water_radius + 1):
		for dx in range(-_water_radius, _water_radius + 1):
			var cc := center + Vector2i(dx, dy)
			if _grid.cell_valid(cc) and _grid.water(cc):
				any = true
	return any
```
把 `_use_tool` 里两处 `_grid.water(c)` 换成 `_water_area(c)`。（`FarmGrid.water` 已是"仅 TILLED→WATERED 生效、否则 false",区域浇水天然只作用合法格。）

- [ ] **Step 3:** `save_game`/`load_game` 加 `"water_radius"`:save 写 `_water_radius`;load 读 `_water_radius = int(d.get("water_radius", 0))`。

- [ ] **Step 4:** `shop_panel.gd`:`_build_rows` 末尾追加一条 upgrade 行(仅当未升级)。`_rows` 元素加 `kind:"upgrade"`;`_refresh` 渲染 `"[升级] 水壶 3×3  价%d" % WATER_UPGRADE_COST`;`_do` 里 `kind=="upgrade"` → `_world.buy_water_upgrade()`。shop_panel 需 `bind` 时多接 world 引用(`bind(shop, reg, bag, world)`;`world.gd::_open_ui` 的 "shop" 分支相应多传 self)。升级成功后重建行(移除该行)。

- [ ] **Step 5:** 更新 `_run_smoke`:金币足够时 `buy_water_upgrade()` == true 且 `_water_radius==1`;耕出 3×3 一片后对中心 `_water_area` 使 9 格变 WATERED;存读档往返带上 water_radius(改一处后 load 复原为升级前值)。

- [ ] **Step 6:** 跑 `run_all.ps1`(FAILS=0)+ `FARM_SMOKE=1`(PASS)。

- [ ] **Step 7:** commit `feat(farm-sim P2): 水壶升级 3×3 区域浇水（商店购买 + 随存档持久化）`。

---

### Task 4: 任务/成就面板

**Files:**
- Modify: `project.godot`(+`toggle_log` 输入动作)
- Create: `examples/farm-sim/log_panel.gd`
- Modify: `examples/farm-sim/world.gd`(接 quest_log + achievement_tracker;载 quest/achievement 数据;存档带任务进度;开关日志面板)

**Interfaces:**
- Consumes: `quest_log.gd`(`bind(registry)`,`summary_lines()`,`to_dict/from_dict`,`done_count/quest_count`);`achievement_tracker.gd`(`bind(registry)`,`summary_lines()`,`unlocked_count/total`)。二者 `_ready` 各自订阅事件,须在任何 shop/clock/weather 事件前入树。
- Produces: `LogPanel.bind(quest_log, tracker)`;`World` 存档新增 `"quests"` 键。

- [ ] **Step 1:** `project.godot` `[input]` 段仿 `toggle_inventory` 加 `toggle_log`(物理键 L = physical_keycode 76):
```
toggle_log={
"deadzone": 0.2,
"events": [Object(InputEventKey,…,"physical_keycode":76,…)]
}
```
（照现有 `toggle_inventory` 块整体复制改 physical_keycode 与动作名。)

- [ ] **Step 2:** `world.gd::_ready`:
  - `_registry.load_dir(&"quest", "res://examples/farm-sim/data/quests")` 与 `load_dir(&"achievement", …/data/achievements)`。
  - 在 shop/weather 入树**之前**建 `_quest_log`(QuestLog,bind registry,add_child)与 `_tracker`(Achievements,bind registry,add_child)。顺序:quest_log/tracker → shop → weather(tracker 订阅 shop:bought/quest:completed/weather:changed;quest_log 订阅 clock:day_changed/shop:sold)。
  - 存 `var _quest_log`、`var _tracker` 字段。

- [ ] **Step 3:** 写 `log_panel.gd`(`extends Control`,照 `inventory_panel.gd` 结构):`bind(quest_log, tracker)`;`_ready` 建标题"任务 / 成就 (L 关闭)" + 两个 VBox 分别填 `quest_log.summary_lines()` 与 `tracker.summary_lines()`;`handle_action(_a)` 空转(只读)。

- [ ] **Step 4:** `world.gd`:`_open_ui` 加 `"log"` 分支(new LogPanel,bind `_quest_log`,`_tracker`);`_unhandled_input` 加 `if event.is_action_pressed("toggle_log"): _toggle_ui("log"); return`;活动面板路由已通用(handle_action 空转即可)。

- [ ] **Step 5:** `save_game` 加 `"quests": _quest_log.to_dict()`;`load_game` 加 `_quest_log.from_dict(d["quests"])`(注意旧存档无此键 → `d.get("quests", {})`)。成就是账号级(settings),不进存档,无需动。

- [ ] **Step 6:** 更新 `_run_smoke`:卖出产物后 `_quest_log.done_count()` 或某 quest 进度 > 0;买种子后 `_tracker.unlocked_count() >= 1`(first_purchase);开关 "log" 面板 build/push/pop 无错。收尾 `_tracker.reset_all()`(清 settings 成就分区,保证可重复跑)。

- [ ] **Step 7:** 跑 `run_all.ps1`(FAILS=0)+ `FARM_SMOKE=1`(PASS)。

- [ ] **Step 8:** commit `feat(farm-sim P2): 任务/成就接入 world + 日志面板（L 键）+ 任务进度随存档`。

---

### Task 5: i18n 语言切换

**Files:**
- Create: `examples/farm-sim/i18n_strings.gd`(内存 zh/en 翻译 + key helper)
- Modify: `examples/farm-sim/world.gd`(载翻译、默认 zh、locale_changed 重建活动面板、语言切换 API)
- Modify: `examples/farm-sim/hud.gd`、`pause_menu.gd`、`inventory_panel.gd`、`shop_panel.gd`、`log_panel.gd`(文案 key 化)
- Create: `examples/farm-sim/settings_panel.gd`(本 Task 先只放语言切换;音量/重绑定在 Task 6 补)

**Interfaces:**
- Produces:
  - `I18nStrings.install()`(static;建 zh/en `Translation` 并 `CoreKit.i18n.add_translation`)
  - `I18nStrings.crop_name(reg, crop_id) -> String`(优先 `t("CROP_"+id)`,回退 def.display_name)
  - `World.cycle_locale()`(zh↔en 切换,经 `CoreKit.i18n.set_locale`)

- [ ] **Step 1:** 写 `i18n_strings.gd`:静态建两份 `Translation`(locale "zh"/"en"),覆盖 UI key(HUD_GOLD/HUD_ENERGY/HUD_SEED/HUD_WEATHER/HUD_SEASON_*、MENU_SAVE/LOAD/CONTINUE/SETTINGS、SHOP_TITLE/BUY/SELL、INV_TITLE、LOG_TITLE、SET_LANG/SET_VOLUME/SET_REBIND、WEATHER_SUNNY/RAINY、SEASON_spring/summer/fall/winter)与作物 key(CROP_turnip/parsnip/potato/pumpkin)。`crop_name` helper 见上。
```gdscript
static func _tr(locale: String, msgs: Dictionary) -> void:
	var t := Translation.new()
	t.locale = locale
	for k in msgs: t.add_message(k, msgs[k])
	CoreKit.i18n.add_translation(t)
```

- [ ] **Step 2:** `world.gd::_ready` 开头调 `I18nStrings.install()`,并 `CoreKit.i18n.set_locale("zh")`(默认中文;i18n 经 Settings 持久化,下次启动自动恢复)。加:
```gdscript
func cycle_locale() -> void:
	CoreKit.i18n.set_locale("en" if CoreKit.i18n.get_locale() == "zh" else "zh")
```
订阅 `CoreKit.i18n.locale_changed` → 若有活动面板则重建(`_close_ui` 后 `_open_ui` 同名),保证切语言即时刷新;HUD 每帧读 `t()` 天然实时。

- [ ] **Step 3:** 各 UI 文案 key 化:HUD/面板里硬编码中文替换成 `CoreKit.i18n.t("KEY")`;作物名用 `I18nStrings.crop_name(_registry, id)`;季节/天气名用 `t("SEASON_"+season_name)` / `t("WEATHER_"+kind)`。保持 fallback(缺键 t() 原样返回 key,不崩)。

- [ ] **Step 4:** `pause_menu.gd`:菜单项 key 化,并加一项"设置"(打开 settings 面板)与"语言: 中/EN"(调 `world.cycle_locale()`)。或把语言切换放进新建的 `settings_panel.gd`(本 Task 建其骨架,只含语言切换按钮,Task 6 补音量/重绑定);pause_menu "设置" → world `_open_ui("settings")`。选后者(更符合"设置面板"归拢)。

- [ ] **Step 5:** `world.gd`:`_open_ui` 加 `"settings"` 分支(new SettingsPanel,bind world);pause_menu "设置" 项 `_activate` 调 `_world.open_settings()`(world 关菜单再开 settings,避免栈叠)。settings 面板 `handle_action` 处理 ↑↓ 选项 + farm_use 切换语言。

- [ ] **Step 6:** 更新 `_run_smoke`:`CoreKit.i18n.get_locale()` 默认 "zh";`cycle_locale()` 后为 "en" 且 `t("MENU_SAVE")` 中英不同;切回 zh;收尾 `CoreKit.settings.erase_section("locale")`(复位持久化)。开关 "settings" 面板 build/push/pop 无错。

- [ ] **Step 7:** 跑 `run_all.ps1`(FAILS=0)+ `FARM_SMOKE=1`(PASS)。

- [ ] **Step 8:** commit `feat(farm-sim P2): i18n 中/英切换（内存翻译 + UI/作物文案 key 化 + 设置面板语言项）`。

---

### Task 6: 音效 + BGM(程序化)+ 音量/键位重绑定设置

**Files:**
- Create: `examples/farm-sim/audio_bank.gd`(程序化 `AudioStreamWAV`)
- Modify: `examples/farm-sim/world.gd`(动作点播 SFX;ready 播 BGM)
- Modify: `examples/farm-sim/settings_panel.gd`(+音量滑条 + `KitRebindList`)

**Interfaces:**
- Produces:
  - `AudioBank.sfx(name: StringName) -> AudioStreamWAV`(till/plant/water/harvest/buy/sell/day/rain;缓存)
  - `AudioBank.bgm() -> AudioStreamWAV`(循环 loop_mode=LOOP_FORWARD)
- Consumes: `CoreKit.audio.play_sfx/play_music/set_volume/get_volume`;`KitRebindList`(class_name,`setup(rows)`);`World.cycle_locale`。

- [ ] **Step 1:** 写 `audio_bank.gd`:静态 `_tone(freq, ms, vol, decay) -> AudioStreamWAV`,以 16-bit PCM 正弦(带指数衰减包络)填 `PackedByteArray`,`format = AudioStreamWAV.FORMAT_16_BITS`,`mix_rate = 22050`,`stereo = false`。每个 SFX 用不同基频/时长(耕=低钝、种=中、浇=水滴双音、收=上行、买/卖=叮、day=柔和、rain=白噪短促)。`bgm()` 拼几个音阶音循环、`loop_mode = AudioStreamWAV.LOOP_FORWARD` + `loop_begin=0`/`loop_end=样本数`。结果按 name 缓存进 static Dictionary。
  > headless 用 dummy 音频驱动,生成/播放不崩;无需真实资产。

- [ ] **Step 2:** `world.gd`:各动作点播 SFX——`_use_tool` 成功分支按 did 类型播 till/plant/water/harvest;shop buy/sell 经订阅 `shop:bought`/`shop:sold` 播 buy/sell(或在 shop_panel 触发);`_on_weather` 雨天播 rain;`_sleep` 播 day。`_ready` 末尾 `CoreKit.audio.play_music(AudioBank.bgm(), 1.0)`。
```gdscript
func _sfx(name: StringName) -> void:
	CoreKit.audio.play_sfx(AudioBank.sfx(name))
```

- [ ] **Step 3:** `settings_panel.gd` 扩展:在语言项下加三条音量行(master/music/sfx),用 `HSlider`(0~1,`value_changed` → `CoreKit.audio.set_volume(bus, v)`,初值 `get_volume`);再加一个 `KitRebindList`,`setup` farm 动作清单:
```gdscript
list.setup([
	{"action": "move_up", "label": t("上")}, {"action": "move_down", "label": t("下")},
	{"action": "move_left", "label": t("左")}, {"action": "move_right", "label": t("右")},
	{"action": "farm_use", "label": t("用工具")}, {"action": "farm_next_day", "label": t("睡觉")},
	{"action": "cycle_seed", "label": t("切种子")},
])
```
面板打开时玩家 `input_locked`,重绑定捕获不误触农场(world 已在开面板时锁 player)。注意:settings 面板既要响应 world 路由的 `handle_action`(↑↓ 选项/切语言),又含 Godot Control(HSlider/RebindButton 自己吃 GUI 输入);二者不冲突(world 只路由 move_up/down/farm_use 到 handle_action,滑条/重绑定走 GUI focus)。

- [ ] **Step 4:** 更新 `_run_smoke`:`AudioBank.sfx(&"till")` 返回非 null `AudioStreamWAV`;`CoreKit.audio.set_volume("music", 0.5)` 后 `get_volume("music")` ≈ 0.5;settings 面板(含 KitRebindList)build/push/pop 无错;收尾 `CoreKit.settings.erase_section("input")`、`erase_section("audio")`(复位重绑定/音量持久化,保证可重复跑)。

- [ ] **Step 5:** 跑 `run_all.ps1`(FAILS=0)+ `FARM_SMOKE=1`(PASS)。

- [ ] **Step 6:** commit `feat(farm-sim P2): 程序化音效/BGM + 设置面板音量滑条 + KitRebindList 键位重绑定`。

---

### 收尾(全部 Task 后)

- [ ] `world.gd` 顶部 docstring 更新操作说明(加 L 日志、天气/季节、设置面板)。
- [ ] spec `2026-07-14-farm-sim-game-design.md` 的 P2 checklist 逐项勾 `[x]`,标题加 ✅。
- [ ] 更新 memory `farm-sim-trio-plan.md` / `roadmap-post-di-ecosystem.md`:记 P2 完成。
- [ ] 编辑器 F5 总验收:四季轮替(睡 7 天跨季)、南瓜只能秋种、雨天视觉+加速、水壶升级 3×3、L 看任务成就、设置里切中英/调音量/改键、音效响。
- [ ] 提示需求方在 `example/farm-sim` 分支自行 push(按 workflow:留 push 给用户)。

## Self-Review 记录

- **Spec 覆盖**:P2 六项 checklist ↔ Task 1(季节)/2(天气)/3(工具升级)/4(任务成就 UI)/5(i18n)/6(音效+BGM+重绑定 UI)一一对应,无遗漏。
- **类型一致**:`plant(cell, crop_id, season)`、`advance_day(bonus)`、`crop_plantable(id, season)`、`buy_water_upgrade()`、`cycle_locale()`、`AudioBank.sfx(name)`/`bgm()`、`I18nStrings.install()`/`crop_name()` 在各 Task 引用一致。
- **无占位**:机制代码(季节门/生长加成/区域浇水/程序化音频/i18n 安装)与测试断言均给出实体;纯 UI 标签的逐行文案在执行时照既有面板风格补(结构已定)。
- **注意**:`farm_grid.gd` 内部 `_crops` 字段名以实际实现为准(Task 2 Step 1 的示例按现有结构对齐);shop_panel `bind` 增参数需同步 world `_open_ui` 调用点。
