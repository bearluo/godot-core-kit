# 游戏时钟设计(GameClock / CoreKit.clock)

> 模拟经营农场三件套之一(1/3)。给用 core-kit 的游戏一台**世界时钟/日历**:年/季/日/时/分,混合推进(实时自动走时 + 显式跳时/睡觉),跨级级联时发原生 signal 并向 `CoreKit.bus` 广播 `clock:*` 事件。作为**第一个真正 publish 的 kit 子系统**,顺带确立全 kit 的 bus 事件命名约定 `namespace:event`。

**版本:** v0.15.0(承 layer-manager v0.14.0)

## 目标

新增第 14 个门面子系统 **`CoreKit.clock`**(`systems/game_clock.gd`,`extends Node`,无 class_name):

- **日历模型**:`year`(1 起)/`season_index`(0 起)/`day`(1 起)/`hour`(0 起)/`minute`(0 起);可配置 `days_per_season`(默认 28)、`seasons`(默认 4:spring/summer/fall/winter)、`hours_per_day`(默认 24)、`minutes_per_hour`(默认 60)、`wake_hour`(默认 6)。不 `configure` 亦开箱可用。
- **混合推进**:`_process(delta)` 按 `time_scale`(游戏分钟/真实秒,**默认 0 = 起始暂停**)累加自动走时;同时 `advance_minutes/advance_hours/advance_day/sleep_to_next_day` 显式推进。二者共用同一条级联(分→时→日→季→年)。
- **双通道广播**:每跨一级发对应**原生 signal**(直连),并(经 `bind_bus` 注入 EventBus 后)向 `CoreKit.bus` `publish` 对应 `clock:*` 事件(payload = 快照 Dictionary)。未注入 bus 时只发原生 signal(降级,不崩)。
- **持久化**:`to_dict()/from_dict()`,游戏自行接入 `CoreKit.saves`(from_dict 用 `int()` 包 JSON 回来的 float)。
- **确立 bus 事件命名约定**:`namespace:event`(冒号),写进 `docs/core/event-bus.md`,附「已保留命名空间登记表」。

## 非目标(YAGNI v1)

- **天气/季节内容**:时钟只报"现在几点几季",下不下雨、季节产什么作物是游戏的事。
- **昼夜相位(dawn/day/dusk/night)**:游戏可从 `hour()` 自行判定,不内建相位枚举与阈值。
- **多时钟/时区**:世界只有一台时钟(单例,故上门面);要局部计时器用 `Timer`/`FrameScheduler`。
- **调度/闹钟(在 X 时间触发回调)**:游戏订阅 `clock:*` 自行判断,时钟不接管定时任务。
- **EventBus 强制校验命名**:约定是文档纪律 + `EV_*` 常量,**不**在 EventBus 里加运行时校验(避免噪音、不破坏现有 `demo_event`/`evt`)。
- **自动存档接线**:时钟不 `preload` SaveManager,只给 `to_dict/from_dict`,由游戏粘合。

## 架构 / 定位

**上门面**,第 14 个子系统 `CoreKit.clock`,`systems/` 下无 `class_name` 的预加载脚本。**为何上门面**:世界时钟天然全局单例,且要 `CoreKit.bus` 广播——必须挂 autoload 子树才能跨场景常驻并复用总线。与 off-facade 的背包/数据表(游戏多实例/游戏持有)刻意不同。

**打破"13 子系统"不变量 → 14**:`core_kit.gd` 新增 preload/属性/构造/`_ready` 里 `bind_bus` + `_services` 注册/`RESERVED_KEYS` 一项;`test_core_kit.gd` 属性表(13→14)、节点序数组(加 `GameClock`)、保留键表、版本、`bind_bus` 断言、provide 守卫同步。

**依赖纪律**:仅依赖 EventBus,经 `bind_bus(bus)` 注入(唯一合法跨系统通道,只在 `core_kit.gd:_ready()` 调),引用存无类型 `_bus = null` 并守卫未绑定路径。构造序把 `GameClock` append 在末位(第 14,`LayerManager` 之后)。

## 组件

### a. `GameClock`(`systems/game_clock.gd`,`extends Node`)

实现以**绝对分钟**为中枢:任意推进都换算成"自 (year1,season0,day1,00:00) 起的绝对分钟",加减后再分解回各字段,天然正确处理跨多级的大跳。

```gdscript
extends Node
## CoreKit.clock —— 游戏时钟/日历(第 14 子系统)。维护 年/季/日/时/分 日历,混合推进:
## _process 按 time_scale(游戏分钟/真实秒,默认 0=暂停)自动走时,同时提供 advance_minutes/
## advance_day/sleep_to_next_day 显式推进。级联(分→时→日→季→年)以绝对分钟为中枢实现;
## 每跨一级发对应原生 signal,并(若 bind_bus 注入)向 CoreKit.bus 广播 "clock:xxx"。
##
## 依赖:仅 EventBus,经 bind_bus 注入;未注入则只发原生 signal(bus 静默跳过)。
## 持久化:to_dict/from_dict,游戏自行接入 CoreKit.saves。
##
## 事件命名约定(全 kit,见 docs/core/event-bus.md):"namespace:event"。本子系统 namespace
## = "clock",事件名以 EV_* 常量导出,游戏订阅引用常量:
##   CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_new_day)

## --- 事件名常量(payload 均为 snapshot() 快照 Dictionary)---
const EV_TIME_CHANGED := "clock:time_changed"      ## 每分钟推进
const EV_HOUR_CHANGED := "clock:hour_changed"      ## 跨小时
const EV_DAY_CHANGED := "clock:day_changed"        ## 跨天(作物生长主钩子)
const EV_SEASON_CHANGED := "clock:season_changed"  ## 跨季
const EV_YEAR_CHANGED := "clock:year_changed"      ## 跨年

## --- 原生 signal(直连;与 bus 广播同时发)---
signal time_changed(hour: int, minute: int)
signal hour_changed(hour: int)
signal day_changed(day: int, season_index: int, year: int)
signal season_changed(season_index: int)
signal year_changed(year: int)

## --- 日历配置(configure 覆盖;默认星露谷式)---
var _minutes_per_hour := 60
var _hours_per_day := 24
var _days_per_season := 28
var _seasons: Array = ["spring", "summer", "fall", "winter"]
var _wake_hour := 6

## --- 日历状态(1 起:year/day;0 起:season_index/hour/minute)---
var _year := 1
var _season_index := 0
var _day := 1
var _hour := 6
var _minute := 0

## 游戏分钟/真实秒;<=0 或 paused 时 _process 不推进。默认 0(起始暂停)。
var time_scale := 0.0
var paused := false
var _accum := 0.0   ## 实时累加的游戏分钟小数余量

## bind_bus 注入;untyped:未注入(脱离门面单测)为 null。
var _bus = null


func bind_bus(bus) -> void:
	_bus = bus


## 覆盖日历配置(任一键可缺省;应在推进前调用)。键:minutes_per_hour/hours_per_day/
## days_per_season/seasons(Array)/wake_hour。其它键忽略(故 from_dict 可整包传入)。
func configure(cfg: Dictionary) -> void:
	if cfg.has("minutes_per_hour"): _minutes_per_hour = maxi(1, int(cfg["minutes_per_hour"]))
	if cfg.has("hours_per_day"): _hours_per_day = maxi(1, int(cfg["hours_per_day"]))
	if cfg.has("days_per_season"): _days_per_season = maxi(1, int(cfg["days_per_season"]))
	if cfg.has("seasons"): _seasons = (cfg["seasons"] as Array).duplicate()
	if cfg.has("wake_hour"): _wake_hour = clampi(int(cfg["wake_hour"]), 0, _hours_per_day - 1)


func _process(delta: float) -> void:
	if paused or time_scale <= 0.0:
		return
	_accum += delta * time_scale
	if _accum < 1.0:
		return
	var whole := int(_accum)
	_accum -= float(whole)
	advance_minutes(whole)


func pause() -> void:
	paused = true


func resume() -> void:
	paused = false


func set_time_scale(scale: float) -> void:
	time_scale = maxf(0.0, scale)


## 推进 n 游戏分钟(n<=0 no-op)。以绝对分钟加法级联,按跨级发信号/广播。
func advance_minutes(n: int) -> void:
	if n <= 0:
		return
	var b_year := _year
	var b_season := _season_index
	var b_absday := _abs_day()
	var b_hour := _hour
	_set_from_abs(_abs_minutes() + n)
	_fire(b_year, b_season, b_absday, b_hour)


func advance_hours(n: int) -> void:
	advance_minutes(n * _minutes_per_hour)


## 前进一整天(保持当前时:分)。
func advance_day() -> void:
	advance_minutes(_minutes_per_day())


## 睡觉:跳到次日 wake_hour:00。
func sleep_to_next_day() -> void:
	var b_year := _year
	var b_season := _season_index
	var b_absday := _abs_day()
	var b_hour := _hour
	var next_day_start := (b_absday + 1) * _minutes_per_day()
	_set_from_abs(next_day_start + _wake_hour * _minutes_per_hour)
	_fire(b_year, b_season, b_absday, b_hour)


## 直接置位(不发级联信号;用于 from_dict/调试)。各字段夹取到合法范围。
func set_datetime(year: int, season_index: int, day: int, hour: int, minute: int) -> void:
	_year = maxi(1, year)
	_season_index = clampi(season_index, 0, _seasons.size() - 1)
	_day = clampi(day, 1, _days_per_season)
	_hour = clampi(hour, 0, _hours_per_day - 1)
	_minute = clampi(minute, 0, _minutes_per_hour - 1)
	_accum = 0.0


## --- 只读 getter ---
func year() -> int: return _year
func season_index() -> int: return _season_index
func season_name() -> String:
	return String(_seasons[_season_index]) if _season_index < _seasons.size() else ""
func day() -> int: return _day
func hour() -> int: return _hour
func minute() -> int: return _minute
func seasons() -> Array: return _seasons.duplicate()
func days_per_season() -> int: return _days_per_season


## 当前日历快照(bus payload / UI 一次性读取)。
func snapshot() -> Dictionary:
	return {
		"year": _year, "season_index": _season_index, "season_name": season_name(),
		"day": _day, "hour": _hour, "minute": _minute,
	}


## --- 持久化 ---
func to_dict() -> Dictionary:
	var d := snapshot()
	d.erase("season_name")   # 派生字段不存
	d["time_scale"] = time_scale
	d["paused"] = paused
	d["minutes_per_hour"] = _minutes_per_hour
	d["hours_per_day"] = _hours_per_day
	d["days_per_season"] = _days_per_season
	d["seasons"] = _seasons.duplicate()
	d["wake_hour"] = _wake_hour
	return d


func from_dict(d: Dictionary) -> void:
	configure(d)   # 先恢复配置(configure 只挑自己的键,int() 包)
	set_datetime(int(d.get("year", 1)), int(d.get("season_index", 0)),
		int(d.get("day", 1)), int(d.get("hour", _wake_hour)), int(d.get("minute", 0)))
	time_scale = float(d.get("time_scale", 0.0))
	paused = bool(d.get("paused", false))


## --- 内部:绝对分钟中枢 ---
func _minutes_per_day() -> int: return _hours_per_day * _minutes_per_hour
func _minutes_per_season() -> int: return _days_per_season * _minutes_per_day()
func _minutes_per_year() -> int: return _seasons.size() * _minutes_per_season()

func _abs_minutes() -> int:
	return ((_year - 1) * _seasons.size() + _season_index) * _minutes_per_season() \
		+ (_day - 1) * _minutes_per_day() + _hour * _minutes_per_hour + _minute

func _abs_day() -> int:
	return _abs_minutes() / _minutes_per_day()

func _set_from_abs(m: int) -> void:
	if m < 0: m = 0
	var mps := _minutes_per_season()
	var mpd := _minutes_per_day()
	var seasons_n := _seasons.size()
	_year = m / _minutes_per_year() + 1
	m = m % _minutes_per_year()
	_season_index = m / mps
	m = m % mps
	_day = m / mpd + 1
	m = m % mpd
	_hour = m / _minutes_per_hour
	_minute = m % _minutes_per_hour

## 从粗到细比较并发信号 + bus 广播。
func _fire(b_year: int, b_season: int, b_absday: int, b_hour: int) -> void:
	if _year != b_year:
		year_changed.emit(_year); _publish(EV_YEAR_CHANGED)
	if _season_index != b_season:
		season_changed.emit(_season_index); _publish(EV_SEASON_CHANGED)
	if _abs_day() != b_absday:
		day_changed.emit(_day, _season_index, _year); _publish(EV_DAY_CHANGED)
	if _hour != b_hour:
		hour_changed.emit(_hour); _publish(EV_HOUR_CHANGED)
	time_changed.emit(_hour, _minute); _publish(EV_TIME_CHANGED)

func _publish(ev: String) -> void:
	if _bus != null:
		_bus.publish(ev, snapshot())
```

### b. `core_kit.gd` 门面接线(第 14 子系统)

- 头注释(第 3-4 行)子系统属性列表末加 ` / .clock`。
- `const GameClockScript := preload("res://addons/godot-core-kit/systems/game_clock.gd")`(preload 段末,`LayerManagerScript` 后)。
- `var clock: GameClockScript`(属性段末,`var layers` 后)。
- `_init` 末尾(`add_child(layers)` 后):
  ```gdscript
  clock = GameClockScript.new()
  clock.name = "GameClock"
  add_child(clock)
  ```
- `_ready` 里:接线段加 `clock.bind_bus(bus)`(在 `i18n.bind_settings(settings)` 后、`log.info` 横幅前);注册段加 `_services["clock"] = clock`(在 `_services["layers"] = layers` 后)。
- `RESERVED_KEYS` 注释 `13 个内置` → `14 个内置`;数组末 `"layers"]` → `"layers", "clock"]`。
- `VERSION` → `"0.15.0"`。

### c. `docs/core/event-bus.md` 事件命名约定(kit 级)

新增一节「事件命名约定」:
- 格式 `namespace:event`(冒号);namespace = 子系统门面短名,event = 过去时 snake_case;payload = 单 `Dictionary`/null。
- 每个发事件的子系统导出 `EV_*` 常量,订阅引用常量。
- 一张「已保留命名空间登记表」:`clock`(GameClock,本次首登)。游戏用自己的命名空间(如 `farm:*`),不得借 kit 命名空间。

## 数据流

自动:`_process(delta)` → `_accum += delta*time_scale` → 满 1 分 → `advance_minutes(whole)`。
显式:`CoreKit.clock.advance_day()` → `advance_minutes(_minutes_per_day())` → 绝对分钟 +1 天 → `_set_from_abs` 分解 → `_fire` 比较发 `day_changed`(原生)+ `CoreKit.bus.publish("clock:day_changed", snapshot)`。游戏侧 `CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_new_day)` 收到快照 → 推进作物。

## 错误处理

- `advance_minutes(n<=0)` / `advance_hours` no-op;`set_time_scale` 夹到 `>=0`。
- `configure` 缺键忽略;`seasons` 为空数组时 `season_name()` 返回 `""`(不崩)。
- 未 `bind_bus`(`_bus == null`)时 `_publish` 静默跳过,原生 signal 照发(降级路径)。
- `from_dict` 全字段 `int()/float()/bool()` 包裹,容 JSON 往返;缺键取默认。
- `set_datetime` 各字段 `clampi` 到合法范围,脏档不越界。

## 测试(headless)

### 新 `test/test_game_clock.gd`

**不入树**、`.new()` 直接实例化(手动调 `_process` 保确定性,避免真实帧干扰),末 `free`。

1. **初始状态**:`year()==1`、`season_index()==0`、`season_name()=="spring"`、`day()==1`、`hour()==6`、`minute()==0`、`paused==false`、`time_scale==0`。
2. **分→时级联**:`advance_minutes(30)`→06:30;再 `advance_minutes(40)`→07:10(`minute==10`,`hour==7`)。
3. **跨天**:置 06:00,`advance_day()`→`day==2`、`hour==6`;`advance_minutes(_minutes_per_day())` 亦可。
4. **跨季**:`configure({days_per_season=2})`,从 day1 起 `advance_day()`×2 → `season_index==1`、`day==1`。
5. **跨年**:`configure({days_per_season=1, seasons=["a","b"]})`,`advance_day()`×2 → `year==2`。
6. **sleep_to_next_day**:置 day1 14:00,`sleep_to_next_day()` → `day==2`、`hour==wake_hour(6)`、`minute==0`。
7. **原生 signal 计数**:连 `day_changed`,跨 3 天收 3 次,末次参数 `(day,season_index,year)` 正确。
8. **bus 绑定广播**:`bind_bus(EventBus.new())`,`subscribe(EV_DAY_CHANGED, cb)`,`advance_day()` → cb 收到 payload 且 `payload["day"]` 正确、`payload` 含 `season_name`。
9. **bus 未绑定降级**:默认 `_bus==null`,`advance_day()` 不崩、原生 signal 仍发。
10. **_process 走时**:`time_scale=60`,`_process(1.0)` → +60 分(07:00→08:00 类);`paused=true` 后 `_process(1.0)` 不动;`time_scale=0` 不动。
11. **to_dict/from_dict 往返**:`configure` 自定义 + 推进若干 → `to_dict()` → 新 clock `from_dict()` → `snapshot()` 与配置(`days_per_season`/`seasons`/`wake_hour`)一致、`time_scale`/`paused` 一致。
12. **set_datetime 夹取**:`set_datetime(1, 99, 999, 99, 99)` → 各字段落在合法上界内不越界。

### `test/test_core_kit.gd`(改 6 处)

- 版本断言(2 行)`"0.14.0"` → `"0.15.0"`。
- test 2 `expected` 数组 layers 行后加 `["clock", "res://addons/godot-core-kit/systems/game_clock.gd"]`(13→14 项)。
- test 3 `order` 数组末 `"LayerManager"]` → `"LayerManager", "GameClock"]`,计数 13→14。
- test 6 `builtin_keys` 末 `"layers"]` → `"layers", "clock"]`;加 provide 守卫:`kit.provide("clock", 1)` 被拒、`kit.service("clock")==kit.clock`。
- 加 `bind_bus` 断言:`kit.clock` 的 `_bus == kit.bus`(门面 `_ready` 已接线)。

## 收尾件

- 新 `systems/game_clock.gd`(+`.uid`);新 `test/test_game_clock.gd`(+`.uid`)。
- `core_kit.gd`:preload+属性+构造+`bind_bus`+`_services`+`RESERVED_KEYS`+`VERSION` 0.15.0+头注释。
- `test/test_core_kit.gd`:属性表/节点序/保留键/版本/provide 守卫/`bind_bus` 断言。
- 新 `docs/systems/game-clock.md`(五段式:职责/公开 API/依赖/用法示例/注意事项),记日历模型、混合推进、bus 事件与命名约定、持久化、集成缝(作物订阅 `clock:day_changed`)。
- 改 `docs/core/event-bus.md`:加「事件命名约定 + 已保留命名空间登记表」。
- `docs/README.md`:门面子系统表加 `CoreKit.clock` 行。
- `docs/architecture.md`:子系统数 13→14(全文该处措辞)、`systems/` 布局注加 GameClock、版本 0.15.0、测试文件数(19→20)、依赖纪律注(GameClock 依赖 EventBus 经 bind_bus)。
- 根 `README.md`:门面属性表加 `CoreKit.clock` 行 + 版本 0.15.0 条目。
- `plugin.cfg`:version 0.15.0 + description 追加。
- `demo/demo.gd`:`CoreKit.clock` 冒烟——`advance_day()` 后打 marker(如 `Clock: y1 spring d2 06:00 day_evt=true`,headless 确定性);`test/run_all.ps1`:加 `test_game_clock`(19→20)+ demo marker `Clock: ` + 计数。

## 我替你拍的默认(实现时若无异议即照此)

上门面第 14 子系统 `CoreKit.clock`(`systems/game_clock.gd`,无 class_name)· 日历 年/季/日/时/分默认 4 季×28 天×24 时×60 分、wake_hour=6 · 混合推进(_process 按 time_scale 默认 0 暂停 + advance_minutes/hours/day + sleep_to_next_day)· 绝对分钟中枢级联 · 原生 signal + `CoreKit.bus` 广播 `clock:*`(bind_bus 注入,未绑定降级)· 事件命名约定 `namespace:event` 冒号,写进 event-bus.md · `EV_*` 常量导出 · to_dict/from_dict · 破 13→14 子系统 · 版本 0.15.0。
