class_name KitOffline
extends RefCounted
## 离线结算器 —— 放置 / 挂机类游戏「关掉进程期间应补收益」的纯函数计算。
## 给定上次在线墙钟、当前墙钟、每秒产率、封顶秒数,算离线应补收益;检测系统时间
## 回拨(now < last)按 0 结算(防玩家改系统时间刷收益)。**off-facade 静态类**:
## 游戏在读档时调 `KitOffline.settle(...)` 拿一个收益数据包,自行入账 + 弹回归窗。
##
## 恒定产率模型:离线期间进程关闭、无玩家操作,产率不变,故 `elapsed × rate` 即
## 精确解。让「在线每秒产出」与本函数同用一个产率,离线补偿即与在线连续产出一致
## (「离线 1h ≈ 在线 1h」)。多产率分段积分(在线追赶 / 产率随时间变)是未来扩展,
## 当前不做(YAGNI —— 尚无多产率消费方)。
##
## 依赖:仅 Godot 内置(`minf`),不挂门面、不 `preload` 任何子系统、不参与存档。
## 调用方自行持久化 `last_seen` 时间戳,推荐 `Time.get_unix_time_from_system()`
## (墙钟,进程退出照走;区别于 `CoreKit.clock` 那种可暂停的游戏内日历)。

const DEFAULT_CAP_SECONDS := 28800.0   # 默认封顶 8 小时


## 结算离线收益。
##   last_seen / now:Unix 秒(建议 `Time.get_unix_time_from_system()`)。
##   rate_per_sec:每秒产出;<= 0 → earned 0(未解锁自动化)。
##   cap_seconds:计入的最大秒数;<= 0 → 用 DEFAULT_CAP_SECONDS。
## 返回 { earned, elapsed, capped, rolled_back }:
##   earned      本次应补收益(elapsed × rate,rate<=0 时为 0)
##   elapsed     实际计入的秒数(min(墙钟差, cap))
##   capped      墙钟差是否超过封顶(true = 有收益被截断)
##   rolled_back 是否检测到时间回拨(now < last_seen;此时 earned=0)
static func settle(last_seen: float, now: float, rate_per_sec: float, cap_seconds: float = DEFAULT_CAP_SECONDS) -> Dictionary:
	var cap: float = cap_seconds if cap_seconds > 0.0 else DEFAULT_CAP_SECONDS
	# 无有效上次时间戳(首次运行)或时间回拨:不结算
	if last_seen <= 0.0 or now <= last_seen:
		return {"earned": 0.0, "elapsed": 0.0, "capped": false, "rolled_back": now < last_seen}
	var raw := now - last_seen
	var elapsed: float = minf(raw, cap)
	var earned := 0.0
	if rate_per_sec > 0.0:
		earned = elapsed * rate_per_sec
	return {"earned": earned, "elapsed": elapsed, "capped": raw > cap, "rolled_back": false}
