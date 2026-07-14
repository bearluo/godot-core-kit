extends Node
## 一株已播种的作物(农田的子节点)。订阅 CoreKit.bus 的 clock:day_changed,
## 每过一天生长 1 格,到 grow_days 即成熟。演示三件事:
## - 跨子系统解耦:作物不认识时钟,只订阅 bus 事件名常量 CoreKit.clock.EV_DAY_CHANGED;
## - bus 事件命名约定 namespace:event 的消费端(payload 为 clock.snapshot() 快照 Dictionary);
## - Node 监听者在 _exit_tree 显式 unsubscribe_all(收获 free 时随之清理,不留悬空订阅)。

var def                     ## CropDef Resource(由 Farm 播种时注入)
var crop_id: StringName = &""
var _stage := 0             ## 已生长天数


func _ready() -> void:
	CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_day)


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)


## 是否已成熟可收。
func is_ready() -> bool:
	return _stage >= def.grow_days


func _on_day(snap: Dictionary) -> void:
	if is_ready():
		return  # 已成熟:不再生长,也不再刷屏
	_stage += 1
	var grown := is_ready()
	CoreKit.log.info("[Crop:%s] 第 %d 天 生长 %d/%d%s" % [
		crop_id, int(snap.get("day", 0)), _stage, def.grow_days, "  已成熟" if grown else ""])
