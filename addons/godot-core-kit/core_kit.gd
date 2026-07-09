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

const VERSION := "0.4.1"

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
	log.info("CoreKit v%s ready" % VERSION)
