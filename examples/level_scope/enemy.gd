extends Node
## 关卡内的实体。_ready 时经 KitContext 向上解析它需要的服务:
## - 关卡专属服务("spawner"/"config"/"difficulty")命中最近的关卡容器;
## - 全局服务("audio" 等内置,或 CoreKit.provide 注册的全局服务)在关卡 miss 后
##   逐层向上回退,树顶兜底到 CoreKit 全局根。
##
## 实体自己不必是 KitContext——KitContext.resolve(self, key) 会从自己向上找最近的容器。


func _ready() -> void:
	var spawner = KitContext.resolve(self, "spawner")       # 命中本关 provide_child 的 Node 服务
	var config = KitContext.resolve(self, "config")         # 命中本关 provide 的纯数据(ref)
	var difficulty = KitContext.resolve(self, "difficulty") # 命中本关值(shadow 了全局默认)
	var audio = KitContext.resolve(self, "audio")           # 本关 miss → 回退 CoreKit 内置

	CoreKit.log.info("[%s] resolved scoped: difficulty=%s wave_count=%s | fallback: audio_is_builtin=%s" % [
		name, difficulty, config.get("wave_count"), audio == CoreKit.audio])

	if spawner != null:
		spawner.spawn_wave(config.get("wave_count", 1))
