# SceneManager —— 全局场景切换

> `CoreKit.scenes` · `systems/scene_manager.gd`

## 职责

统一场景替换入口(仅替换,无场景栈)。把散落各处的 `get_tree().change_scene_to_*()` 调用收敛为一个可选带转场、带切换生命周期信号的协程 `change_scene(target, transition, options)`。第 2 参只管「转场长什么样」(`KitTransition` 的 FADE/SLIDE/MASK,或 legacy 字典),第 3 参 `options` 管其余能力:遮住期间的钩子、预载 + 加载屏。另有 `reload_scene` 重开当前场景,`cover` / `reveal` 做同场景内的黑屏(传送)。默认同步 `load()`;预载不用线程,经 `CoreKit.res` 走它的平台通道(Web/微信分帧、桌面线程)。拒绝重入(`_is_changing` 守卫,`cover` 期间同样占用),不做排队。

## 公开 API

```gdscript
signal scene_changing(target_path: String)
signal scene_changed(scene_path: String, scene: Node)
signal scene_change_failed(target_path: String, error: int)  # error 为 Error 枚举取值
signal scene_load_progress(loaded: int, total: int)          # 仅 options.preload 时;单位是资源个数

enum Transition { NONE, FADE }   # legacy 字典用

# target 为 res:// 路径(String)或 PackedScene。可 fire-and-forget,也可 await。
func change_scene(target, transition = {}, options: Dictionary = {}) -> void
func reload_scene(transition = {}, options: Dictionary = {}) -> void
func cover(transition = {}) -> void      # 同场景黑屏:遮住并占用切换守卫
func reveal(transition = {}) -> void     # 揭开并释放守卫;没先 cover 只 warn

func is_changing() -> bool
func get_current_scene() -> Node
func get_current_scene_path() -> String
```

`options` 识别的键(未识别键静默忽略):

| 键 | 类型 | 作用 |
|---|---|---|
| `preload` | `bool` | 只对路径形式的 target 生效。遮住后经 `CoreKit.res.preload_batch` 预载场景的**直接依赖**,转发 `scene_load_progress`;预载期间新进 `CoreKit.res` 缓存的资源在换完场景后 `release`(原本就在缓存里的不动) |
| `loading_screen` | `PackedScene` | 预载期间实例化并挂在遮罩之上,先画一帧再开始加载;kit 不调用它的任何方法,它自己连 `scene_load_progress` 更新进度条。换完场景、揭开之前移除 |
| `before_swap` | `Callable()` | 已遮住、旧场景还在。存档、记录玩家状态 |
| `after_swap` | `Callable(new_scene: Node)` | 新场景已入树并是 `current_scene`、还没揭开。挪玩家、设出生点 |

一次切换的顺序:`scene_changing` → 遮住 → (加载屏 + 预载)→ 加载场景 → `before_swap` → 换场景 → `after_swap` → 移除加载屏 → 揭开 → `scene_changed`。两个钩子都会被 `await`,可以是协程;无转场(NONE)时钩子照样按顺序调用。

## 依赖

`bind_resources(res)` 注入 `ResourceManager`(在 `core_kit.gd:_ready()` 接线)。未注入时 `preload` 选项退化为普通同步加载,不发进度。日志走 `CoreKit.log`。

## 用法示例

```gdscript
# 无过渡,直接替换
CoreKit.scenes.change_scene("res://levels/level_2.tscn")

# 淡入淡出,原地等待切换完成
var fade := KitTransition.new()
await CoreKit.scenes.change_scene("res://levels/boss.tscn", fade)

# 黑屏期间存档、把玩家放到出生点
await CoreKit.scenes.change_scene("res://levels/town.tscn", fade, {
	"before_swap": func(): CoreKit.saves.save("auto", Game.to_dict()),
	"after_swap": func(scene): scene.get_node("Player").position = scene.get_node("Spawn").position,
})

# 预载 + 加载屏(加载屏自己连 scene_load_progress)
CoreKit.scenes.change_scene("res://levels/big_level.tscn", fade, {
	"preload": true,
	"loading_screen": preload("res://ui/loading.tscn"),
})
# loading.gd:
#   func _ready(): CoreKit.scenes.scene_load_progress.connect(func(l, t): bar.value = float(l) / t)

# 重开当前关卡
CoreKit.scenes.reload_scene(fade)

# 同场景传送:遮住 → 挪位置 → 揭开
await CoreKit.scenes.cover(fade)
player.position = door_target
await CoreKit.scenes.reveal(fade)
```

## 注意事项

- **拒绝重入**:切换进行中(含 `cover` 之后、`reveal` 之前)再调 `change_scene` 会被拒绝(`scene_change_failed` 携 `ERR_BUSY`),不排队。`cover` 在切换中调用只 warn 返回。
- **不拆成两个公开步骤**:黑屏期间要做的事放进 `before_swap` / `after_swap`,而不是暴露 `fade_out` / `fade_in`,避免调用方只调一半把屏幕留在黑屏。同场景黑屏用 `cover` / `reveal`,两者必须配对。
- **钩子出错不卡流程**:钩子里的脚本错误不影响后续,照常揭开并发 `scene_changed`。
- **预载粒度**:只展开一层依赖(`ResourceLoader.get_dependencies`,`uid://…::Type::res://…` 取 `res://` 段),加载直接依赖时引擎会顺带加载它的子依赖,所以进度格数偏少但能用。`target` 是 `PackedScene` 时 `preload` 被忽略(已经加载好了)。预载中个别依赖失败照常推进度,最后加载场景失败才走失败分支(揭开 + `ERR_CANT_OPEN`,加载屏同样被移除)。
- **reload_scene**:当前场景不是从文件来的(路径为空)→ `scene_change_failed("", ERR_UNAVAILABLE)`。kit 没有「场景参数」,重开时要还原的状态用钩子自己处理。
- **target 校验**:`String` 必须以 `res://` 开头且以 `.tscn`/`.scn` 结尾;`PackedScene` 检查 `can_instantiate()`;其余类型一律非法。
- **延迟一帧再动树**:即使无转场,也会 `await get_tree().process_frame` 后才替换场景,避免在信号回调栈内移除仍在处理事件的旧场景。
- **遮罩常驻**:CanvasLayer(layer = `CoreKit.layers.TRANSITION` = 4096)+ ColorRect 挂在 `SceneManager` 下,首次使用时创建、之后复用;加载屏挂在同一层、遮罩之上。
- **转场定义**:见 [KitTransition](../transitions/kit-transition.md)(FADE/SLIDE/MASK + 缓动 + 可存 .tres);legacy 字典 API 保留兼容。
- **平台**:MASK 转场和带 `preload` 的切换已在微信开发者工具(WebGL2、无线程)实测通过。
