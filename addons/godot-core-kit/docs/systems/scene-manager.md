# SceneManager —— 全局场景切换

> `CoreKit.scenes` · `systems/scene_manager.gd`

## 职责

统一场景替换入口(首版:仅替换,无场景栈)。把散落各处的 `get_tree().change_scene_to_*()` 调用收敛为一个可选带淡入淡出过渡、带切换生命周期信号的协程 `change_scene(target, options)`。同步 `load()`(不用线程,Web 导出安全);第 2 参接受 `KitTransition`(FADE/SLIDE)或 legacy options 字典,默认无过渡(CanvasLayer + ColorRect + Tween 遮罩常驻本节点下、不受场景替换影响)。拒绝重入(`_is_changing` 守卫),不做排队。

## 公开 API

```gdscript
signal scene_changing(target_path: String)
signal scene_changed(scene_path: String, scene: Node)
signal scene_change_failed(target_path: String, error: int)  # error 为 Error 枚举取值

enum Transition { NONE, FADE }

# target 为 res:// 路径(String)或 PackedScene;第 2 参接受 KitTransition 或 legacy options
# 字典({transition/duration/color},未识别键静默回退)。可 fire-and-forget,也可 await。
func change_scene(target, transition = {}) -> void

func is_changing() -> bool                  # 是否正在切换中
func get_current_scene() -> Node
func get_current_scene_path() -> String
```

## 依赖

零跨子系统依赖(仅用 `CoreKit.log` 记录警告/错误)。

## 用法示例

```gdscript
# 无过渡,直接替换
CoreKit.scenes.change_scene("res://levels/level_2.tscn")

# 带淡入淡出,原地等待切换完成
await CoreKit.scenes.change_scene(
    preload("res://levels/boss.tscn"),
    {"transition": CoreKit.scenes.Transition.FADE}
)

# 感知结果
CoreKit.scenes.scene_changed.connect(func(path, scene): print("已切换到 ", path))
CoreKit.scenes.scene_change_failed.connect(func(path, err): CoreKit.log.error("切换失败 %s: %d" % [path, err]))

# 用可复用转场资源（推荐，支持 SLIDE + 缓动曲线，可存 .tres）
var slide := KitTransition.new()
slide.type = KitTransition.Type.SLIDE
slide.direction = KitTransition.Dir.LEFT
await CoreKit.scenes.change_scene("res://levels/level_2.tscn", slide)
```

## 注意事项

- **拒绝重入**:切换进行中再次调用 `change_scene` 会被静默拒绝(`scene_change_failed` 携 `ERR_BUSY`),不排队、不覆盖当前切换。
- **target 校验**:`String` 必须以 `res://` 开头且以 `.tscn`/`.scn` 结尾(不检查文件是否真实存在);`PackedScene` 检查 `can_instantiate()`;其余类型一律非法。
- **延迟一帧再动树**:即使 `Transition.NONE`,内部也会 `await get_tree().process_frame` 后才真正替换场景,避免在触发调用的信号回调栈内(如按钮 `pressed` 冒泡途中)直接冻结/移除仍在处理事件的旧场景节点,语义与内置 `change_scene_to_*` 的"延迟切换"一致。
- **淡入淡出遮罩幂等常驻**:`FADE` 过渡用的 CanvasLayer+ColorRect 挂在 `SceneManager` 节点下,首次使用时创建、之后复用,不受场景替换影响。
- 淡入淡出可见度完全由 `modulate:a` 驱动(遮罩色的 alpha 归一化为 1.0),避免与 `color.a` 相乘导致淡入淡出不到位。
- **转场定义**:过渡由 [KitTransition](../transitions/kit-transition.md) 资源承载(FADE/SLIDE + 缓动 + 可存 .tres);legacy `enum Transition { NONE, FADE }` + 字典 API 保留兼容。
