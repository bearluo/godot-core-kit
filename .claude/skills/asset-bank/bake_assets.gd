# bake_assets.gd —— 确定性资源烘焙器(Godot headless 工具,通用)
# 用法(在游戏项目根,从源码跑):
#   godot --headless --path . -s res://.claude/skills/asset-bank/bake_assets.gd -- \
#       --art res://<game>/gfx/art_bank.gd --sound res://<game>/sfx/sound_bank.gd
# 把每个 bank 的 bake_keys() 逐 key 生成 Image/AudioStreamWAV,save 成真文件到各自 generated_dir()。
# 同时写 BRIEF-*.md(每 key 尺寸/调色/参数 + 一句 prompt),作为 AI/真素材的生成简报。
# bank 需实现烘焙契约:generated_dir()、bake_keys()、bake_image(key)|bake_stream(key)、brief(key)。
extends SceneTree


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var total := 0
	if args.has("art"):
		total += _bake_art(args["art"])
	if args.has("sound"):
		total += _bake_sound(args["sound"])
	if total == 0:
		push_warning("bake_assets: 没有烘焙任何文件(缺 --art/--sound?)")
	print("bake_assets: DONE baked=%d" % total)
	quit(0)


func _parse(a: PackedStringArray) -> Dictionary:
	var d := {}
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			d[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	return d


func _bake_art(script_path: String) -> int:
	var bank = load(script_path).new()
	var dir: String = bank.generated_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var briefs := []
	var n := 0
	for key in bank.bake_keys():
		var img: Image = bank.bake_image(key)
		var path := "%s/%s.png" % [dir, key]
		var err := img.save_png(path)
		if err == OK:
			n += 1
			print("  art  %s -> %s" % [key, path])
		else:
			push_error("bake_assets: save_png 失败 %s (err=%d)" % [key, err])
		briefs.append(bank.brief(key))
	_write_brief(dir, "art", briefs)
	return n


func _bake_sound(script_path: String) -> int:
	var bank = load(script_path).new()
	var dir: String = bank.generated_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var briefs := []
	var n := 0
	for key in bank.bake_keys():
		var s: AudioStreamWAV = bank.bake_stream(key)
		var path := "%s/%s.wav" % [dir, key]
		var err := s.save_to_wav(path)
		if err == OK:
			n += 1
			print("  sfx  %s -> %s" % [key, path])
		else:
			push_error("bake_assets: save_to_wav 失败 %s (err=%d)" % [key, err])
		briefs.append(bank.brief(key))
	_write_brief(dir, "sound", briefs)
	return n


func _write_brief(dir: String, tag: String, briefs: Array) -> void:
	var f := FileAccess.open("%s/BRIEF-%s.md" % [dir, tag], FileAccess.WRITE)
	if f == null:
		push_error("bake_assets: 写 BRIEF 失败 %s" % dir)
		return
	f.store_line("# %s 生成简报(AI / 真素材投放用)" % tag)
	f.store_line("")
	f.store_line("把真/AI 素材按 `<key>` 命名丢进上一级 `assets/` 目录(不是本 generated/)即自动顶替基线。")
	f.store_line("")
	for b in briefs:
		f.store_line("## %s" % str(b.get("key", "?")))
		for k in b.keys():
			if k == "key":
				continue
			f.store_line("- %s: %s" % [k, str(b[k])])
		f.store_line("")
	f.close()
