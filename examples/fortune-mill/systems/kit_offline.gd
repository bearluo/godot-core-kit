class_name KitOffline
extends RefCounted
## 离线结算器(纯函数,不挂树、无 autoload 依赖)。给定上次在线墙钟、当前墙钟、
## 每秒产率、封顶秒数,算离线收益;检测系统时间回拨(now<last → 按 0,防作弊)。
##
## 当前恒定产率:离线期间进程关闭、玩家无操作,产率不变,故 elapsed×rate 即精确解。
## 「跨升级边界分段积分」(spec §4)是多房/在线追赶的未来扩展,P0/P1 单房用不到(YAGNI)。
##
## 与 DartsRoom.auto_gold_rate() 配合:在线 produce 与离线 settle 同用一个确定性期望产率,
## 保证「离线 1h ≈ 在线 1h」。孵化于 example,P2+ 定型后再随 kit cycle 移入 addons/。

const DEFAULT_CAP_SECONDS := 28800.0   # 封顶 8 小时(spec §5.7)


## 结算离线收益。
##   last_seen / now:Unix 秒(Time.get_unix_time_from_system())。
##   rate_per_sec:每秒产出;<=0 → earned 0。
##   cap_seconds:计入的最大秒数;<=0 → 用 DEFAULT_CAP_SECONDS。
## 返回 {earned, elapsed, capped, rolled_back}。
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
