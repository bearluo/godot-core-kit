extends SceneTree
## 造一个最小的真 `.pck`(GDPC 头)当 CDN 探针的内容包。
##   godot --headless --path . --script res://cdn/make_pck.gd -- <内容文件> <输出.pck>
## 用 PCKPacker 而非 --export-pack:不需要 export preset,也不会把整个工程打进去。
## pck 头戳的是**运行引擎版本**,所以要用导出游戏的同一个 Godot 跑。

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src := args[0]
	var out := args[1]
	var packer := PCKPacker.new()
	var err := packer.pck_start(out)
	if err != OK:
		printerr("pck_start failed err=%d" % err)
		quit(1)
		return
	packer.add_file("res://probe_cdn.txt", src)
	err = packer.flush()
	print("make_pck: %s -> %s (err=%d, %d bytes)" % [
		src, out, err, FileAccess.get_file_as_bytes(out).size()])
	quit(0 if err == OK else 1)
