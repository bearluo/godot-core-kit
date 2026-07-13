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
	if cfg.has("seasons") and not (cfg["seasons"] as Array).is_empty(): _seasons = (cfg["seasons"] as Array).duplicate()
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
