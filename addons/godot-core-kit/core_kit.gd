extends Node
## CoreKit —— godot-core-kit 门面根节点,唯一 autoload。
## 各子系统经短属性名访问:CoreKit.log / .bus / .scenes / .pool / .saves /
## .settings / .ticker / .input / .audio / .res。
## 子系统仍是各自独立的脚本与 Node(保留各自 _process 与信号),由本节点在
## _init 按依赖序构造并 add_child;子节点树顺序 = _ready 触发顺序(子先于父),
## 因此各子系统的自身初始化按构造序完成,消费方没有弄乱顺序的入口。
## _ready(全部子系统 _ready 完毕后)是唯一的跨子系统接线点(bind_*)。
##
## 命名坑:属性 log 会遮蔽全局函数 log()(与旧 Log autoload 同款遮蔽);本脚本
## 内部不需要数学 log(),不受影响。

const VERSION := "0.8.0"

## 全局根的保留键 = 10 个内置子系统的属性名。CoreKit.provide 拒绝覆盖这些键;
## 子作用域(KitContext)不受此限,可 shadow。
const RESERVED_KEYS := ["log", "settings", "bus", "scenes", "pool", "saves",
	"ticker", "input", "audio", "res"]

const LogScript := preload("res://addons/godot-core-kit/core/log.gd")
const SettingsScript := preload("res://addons/godot-core-kit/core/settings.gd")
const EventBusScript := preload("res://addons/godot-core-kit/core/event_bus.gd")
const SceneManagerScript := preload("res://addons/godot-core-kit/systems/scene_manager.gd")
const ObjectPoolScript := preload("res://addons/godot-core-kit/systems/object_pool.gd")
const SaveManagerScript := preload("res://addons/godot-core-kit/systems/save_manager.gd")
const FrameSchedulerScript := preload("res://addons/godot-core-kit/systems/frame_scheduler.gd")
const InputManagerScript := preload("res://addons/godot-core-kit/systems/input_manager.gd")
const AudioManagerScript := preload("res://addons/godot-core-kit/systems/audio_manager.gd")
const ResourceManagerScript := preload("res://addons/godot-core-kit/systems/resource_manager.gd")

var log: LogScript
var settings: SettingsScript
var bus: EventBusScript
var scenes: SceneManagerScript
var pool: ObjectPoolScript
var saves: SaveManagerScript
var ticker: FrameSchedulerScript
var input: InputManagerScript
var audio: AudioManagerScript
var res: ResourceManagerScript

## 全局根服务注册表:key:String -> service:Variant。内置在 _ready 预注册,
## 游戏代码经 provide/service 增删查;KitContext 作用域向上回退最终兜底到这里。
var _services: Dictionary = {}


func _init() -> void:
	log = LogScript.new()
	log.name = "Log"
	add_child(log)

	settings = SettingsScript.new()
	settings.name = "Settings"
	add_child(settings)

	bus = EventBusScript.new()
	bus.name = "EventBus"
	add_child(bus)

	scenes = SceneManagerScript.new()
	scenes.name = "SceneManager"
	add_child(scenes)

	pool = ObjectPoolScript.new()
	pool.name = "ObjectPool"
	add_child(pool)

	saves = SaveManagerScript.new()
	saves.name = "SaveManager"
	add_child(saves)

	ticker = FrameSchedulerScript.new()
	ticker.name = "FrameScheduler"
	add_child(ticker)

	input = InputManagerScript.new()
	input.name = "InputManager"
	add_child(input)

	audio = AudioManagerScript.new()
	audio.name = "AudioManager"
	add_child(audio)

	res = ResourceManagerScript.new()
	res.name = "ResourceManager"
	add_child(res)


func _ready() -> void:
	# 唯一的跨子系统接线点:此时全部子系统已各自 _ready 完毕。
	input.bind_settings(settings)
	audio.bind_settings(settings)
	res.bind_ticker(ticker)

	# 内置子系统按 key 预注册进全局根(强类型属性照旧保留),使 service("audio") 及
	# 任意 KitContext 作用域向上回退可达内置。直接写 _services,绕过 provide 的保留键自拒。
	_services["log"] = log
	_services["settings"] = settings
	_services["bus"] = bus
	_services["scenes"] = scenes
	_services["pool"] = pool
	_services["saves"] = saves
	_services["ticker"] = ticker
	_services["input"] = input
	_services["audio"] = audio
	_services["res"] = res

	log.info("CoreKit v%s ready" % VERSION)


## --- 全局根服务定位器(对外扩展点)------------------------------------------

## 注册一个全局服务。保留键(内置)拒绝;重复键覆盖并告警。
func provide(key: String, svc: Variant) -> void:
	if key in RESERVED_KEYS:
		push_error("CoreKit.provide('%s'): 保留键(内置子系统),不可覆盖" % key)
		return
	if _services.has(key):
		push_warning("CoreKit.provide('%s'): 覆盖已注册全局服务" % key)
	_services[key] = svc


## 取全局服务;未注册 → push_error + null(整条解析链唯一的"未找到"报错点)。
func service(key: String) -> Variant:
	if _services.has(key):
		return _services[key]
	push_error("CoreKit.service('%s'): 未注册" % key)
	return null


## 不报错的存在性检查。
func has(key: String) -> bool:
	return _services.has(key)


## 取全局服务;未注册返回 fallback,不报错。
func service_or(key: String, fallback: Variant) -> Variant:
	return _services[key] if _services.has(key) else fallback
