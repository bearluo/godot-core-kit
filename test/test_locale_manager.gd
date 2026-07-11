extends SceneTree
## LocaleManager headless 断言测试。直接实例化脚本(不经门面),TranslationServer
## 全局单例在 headless 下可用。LocaleManager 无树依赖(无 _ready 逻辑),故 new()
## 后直接调方法,无需 add_child / await。
## 运行:godot --headless --path . -s res://test/test_locale_manager.gd
##
## 加载注:settings.gd 运行期引用全局 autoload 标识符 CoreKit(_save_to_disk 里
## CoreKit.log.error),故不在类作用域 preload,延迟到 _initialize() 内 load()。
## LocaleManager 本身零 CoreKit 引用,一并 load() 保持一致。
##
## 隔离:TranslationServer 是全局单例;开头存原 locale,结尾恢复(各 test 虽独立
## 进程,仍稳妥)。测试期间 add_translation 的若干 Translation 不逐一 remove——依赖
## "每个 test 文件独立 godot 进程,退出即释放"这一前提(run_all 亦逐个起进程)。

var LocaleManagerScript
var SettingsScript

const SETTINGS_PATH := "user://__test_locale_settings__.json"
const TMP_TRES := "user://__test_locale.tres"
const TMP_DIR := "user://__test_locale_dir__"


func _initialize() -> void:
	LocaleManagerScript = load("res://addons/godot-core-kit/systems/locale_manager.gd")
	SettingsScript = load("res://addons/godot-core-kit/core/settings.gd")
	var failures := 0
	var original_locale := TranslationServer.get_locale()

	# 预置两语内存翻译
	var en_tr := Translation.new()
	en_tr.locale = "en"
	en_tr.add_message("GREETING", "Hello")
	var zh_tr := Translation.new()
	zh_tr.locale = "zh"
	zh_tr.add_message("GREETING", "你好")

	var lm = LocaleManagerScript.new()
	lm.add_translation(en_tr)
	lm.add_translation(zh_tr)

	# 1. 核心切换 + 信号:建立 en 基线(直改 TS,不经 lm,无信号),lm 切 zh 为真迁移
	var locale_events := []
	lm.locale_changed.connect(func(loc): locale_events.append(loc))
	TranslationServer.set_locale("en")   # 基线,不经 lm
	lm.set_locale("zh")                   # en -> zh 真迁移
	if lm.get_locale() != "zh":
		print("FAIL 1: set_locale('zh') 后 get_locale 应为 zh,实际 %s" % lm.get_locale())
		failures += 1
	if lm.t("GREETING") != "你好":
		print("FAIL 1: zh 下 t(GREETING) 应为 你好,实际 %s" % lm.t("GREETING"))
		failures += 1
	if locale_events != ["zh"]:
		print("FAIL 1: locale_changed 应广播一次 zh,实际 %s" % [locale_events])
		failures += 1
	lm.set_locale("en")                   # zh -> en 真迁移
	if lm.t("GREETING") != "Hello":
		print("FAIL 1: en 下 t(GREETING) 应为 Hello,实际 %s" % lm.t("GREETING"))
		failures += 1

	# 2. 同 locale 去重 no-op + 空串 no-op:不再发信号
	var count_before := locale_events.size()   # 此刻 ["zh","en"]
	lm.set_locale("en")                        # 与当前相同 -> no-op
	if locale_events.size() != count_before:
		print("FAIL 2: 同 locale set_locale 应 no-op 不发信号")
		failures += 1
	lm.set_locale("")                          # 空串 -> 警告 no-op
	if locale_events.size() != count_before:
		print("FAIL 2: 空 locale 应 no-op")
		failures += 1

	# 3. 缺翻译:t 返回 key,has_translation 假(告警是副作用,只验返回值)
	if lm.t("NOPE_KEY") != "NOPE_KEY":
		print("FAIL 3: 缺翻译 t 应返回原 key")
		failures += 1
	if lm.has_translation("NOPE_KEY"):
		print("FAIL 3: 缺翻译 has_translation 应为 false")
		failures += 1
	if not lm.has_translation("GREETING"):
		print("FAIL 3: 已有翻译 has_translation 应为 true")
		failures += 1

	# 4. available / display
	var locs: PackedStringArray = lm.available_locales()
	if not (locs.has("en") and locs.has("zh")):
		print("FAIL 4: available_locales 应含 en/zh,实际 %s" % [locs])
		failures += 1
	if lm.locale_display_name("en") != "English":
		print("FAIL 4: locale_display_name('en') 应为 English,实际 %s" % lm.locale_display_name("en"))
		failures += 1

	# 5. 字体:注册 zh 字体 + bind_theme;切 zh 换 default_font;切无字体 locale 不清
	var zh_font := FontFile.new()
	var theme := Theme.new()
	lm.register_locale_font("zh", zh_font)
	lm.bind_theme(theme)                       # 当前 en 无字体,default_font 保持 null
	if theme.default_font != null:
		print("FAIL 5: bind_theme 时当前 locale(en)无字体,default_font 应为 null")
		failures += 1
	lm.set_locale("zh")                        # en -> zh,zh 有字体
	if theme.default_font != zh_font:
		print("FAIL 5: 切 zh 后 default_font 应为注册字体")
		failures += 1
	lm.set_locale("en")                        # zh -> en,en 无字体 -> 不清
	if theme.default_font != zh_font:
		print("FAIL 5: 切到无字体 locale 应保留旧 default_font(不清)")
		failures += 1
	if lm.font_for_locale("zh") != zh_font:
		print("FAIL 5: font_for_locale('zh') 应返回注册字体")
		failures += 1
	if lm.font_for_locale("fr") != null:
		print("FAIL 5: 未注册 locale font_for_locale 应为 null")
		failures += 1
	lm.register_locale_font("de", null)        # null -> 警告忽略,不崩
	if lm.font_for_locale("de") != null:
		print("FAIL 5: null 字体不应注册")
		failures += 1
	# bind_theme(null) 清除:解绑后切到有字体的 locale 不应再改该 theme 的 default_font
	lm.bind_theme(null)                        # 当前 en;解绑托管 theme
	var prev_font := theme.default_font        # 解绑时 default_font(= zh_font)
	lm.set_locale("zh")                        # en -> zh(zh 有字体),但已解绑 -> theme 不应变
	if theme.default_font != prev_font:
		print("FAIL 5: bind_theme(null) 解绑后不应再改该 theme 的 default_font")
		failures += 1

	# 6. 运行时加载:save 一个 fr 翻译到 user://,load_translation 注册后可用
	var fr_tr := Translation.new()
	fr_tr.locale = "fr"
	fr_tr.add_message("GREETING", "Bonjour")
	ResourceSaver.save(fr_tr, TMP_TRES)
	if not lm.load_translation(TMP_TRES):
		print("FAIL 6: load_translation 应成功")
		failures += 1
	TranslationServer.set_locale("en")         # 基线
	lm.set_locale("fr")                        # en -> fr
	if lm.t("GREETING") != "Bonjour":
		print("FAIL 6: 加载后 fr 下 t(GREETING) 应为 Bonjour,实际 %s" % lm.t("GREETING"))
		failures += 1
	# 非 Translation 资源 -> false(用一个 .gd 脚本资源,避免不存在路径的引擎 error 噪音)
	if lm.load_translation("res://addons/godot-core-kit/core/log.gd"):
		print("FAIL 6: 非 Translation 资源 load_translation 应返回 false")
		failures += 1
	# load_translations 目录扫描:两个 .tres -> 2
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	ResourceSaver.save(en_tr, TMP_DIR.path_join("a.tres"))
	ResourceSaver.save(zh_tr, TMP_DIR.path_join("b.tres"))
	var loaded_n: int = lm.load_translations(TMP_DIR)
	if loaded_n != 2:
		print("FAIL 6: load_translations 应加载 2 个,实际 %d" % loaded_n)
		failures += 1

	# 7. 持久化:预置 settings 的 locale/current;bind 时应用;set_locale 后写透
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	var settings = SettingsScript.new()
	settings.settings_path = SETTINGS_PATH
	settings.set_value("locale", "current", "zh")   # 预置
	var lm2 = LocaleManagerScript.new()
	var lm2_events := []
	lm2.locale_changed.connect(func(loc): lm2_events.append(loc))
	TranslationServer.set_locale("en")              # 基线,保证 bind 的 zh 是真迁移
	lm2.bind_settings(settings)                     # 静默恢复 zh:应用但不重放 locale_changed
	if lm2.get_locale() != "zh":
		print("FAIL 7: bind_settings 应恢复持久化 locale 到 zh,实际 %s" % lm2.get_locale())
		failures += 1
	if not lm2_events.is_empty():
		print("FAIL 7: bind_settings 静默恢复不应重放 locale_changed,实际 %s" % [lm2_events])
		failures += 1
	lm2.set_locale("en")                            # 真迁移(公开 setter),应发信号 + 写透 settings
	if settings.get_value("locale", "current") != "en":
		print("FAIL 7: set_locale 应写透 settings.locale.current,实际 %s" % [settings.get_value("locale", "current")])
		failures += 1

	# 清理
	TranslationServer.set_locale(original_locale)
	lm.free()
	lm2.free()
	settings.free()
	if FileAccess.file_exists(TMP_TRES):
		DirAccess.remove_absolute(TMP_TRES)
	if FileAccess.file_exists(TMP_DIR.path_join("a.tres")):
		DirAccess.remove_absolute(TMP_DIR.path_join("a.tres"))
	if FileAccess.file_exists(TMP_DIR.path_join("b.tres")):
		DirAccess.remove_absolute(TMP_DIR.path_join("b.tres"))
	if DirAccess.dir_exists_absolute(TMP_DIR):
		DirAccess.remove_absolute(TMP_DIR)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)

	if failures == 0:
		print("test_locale_manager: ALL PASS")
		quit(0)
	else:
		print("test_locale_manager: %d FAILURE(S)" % failures)
		quit(1)
