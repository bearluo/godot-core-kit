extends Node
## HttpPackTransport —— PackUpdater 的生产传输适配器(基于 HTTPRequest)。
##
## 满足 PackUpdater 的「传输接缝」:
##   fetch_text(url, on_done: Callable(ok: bool, text: String))
##   fetch_file(url, dest_path, on_done: Callable(ok: bool, reason: String))
##
## 这是真实网络适配器。kit 的 headless 测试门(run_all)无网络,故 HTTP 收发部分不被
## 门覆盖;PackUpdater 的行为单测经注入内存假件覆盖传输路径。但 Web 的「字节落盘」要害
## (_store_body_to_file)已抽出、由 test_http_pack_transport.gd 覆盖(纯写盘,无网络)。
## 真机/真浏览器联网验证在 fortune-mill 接入轮次(Android + Web 均已端到端跑通)。
##
## 每次请求各起一个 HTTPRequest 子节点、完成即释放,避免单个 HTTPRequest 复用
## 时的串扰;PackUpdater 的下载本就串行,不存在并发压力。


## 拉取文本(manifest)。成功 = RESULT_SUCCESS 且 HTTP 200。
func fetch_text(url: String, on_done: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		on_done.call(false, "")
		return
	var res: Array = await req.request_completed
	req.queue_free()
	var ok := int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200
	var body: PackedByteArray = res[3]
	on_done.call(ok, body.get_string_from_utf8() if ok else "")


## 下载文件到 dest_path。
## - 桌面/移动:HTTPRequest.download_file 直接流式落盘,不整读进内存(大包省内存)。
## - Web/HTML5:download_file **不可靠**——request 会报 RESULT_SUCCESS/200,但字节并未
##   真正写进 user://(IDBFS),导致随后按内容做的 sha256 校验读到空/残缺、误判 checksum
##   失败(2026-07 实测坐实,见研究文档 §7c)。故 Web 上改「整包收进内存 body →
##   FileAccess.store_buffer 落盘」(store_buffer 在 Web 已验证可靠;Web 本就整个跑在内存里)。
func fetch_file(url: String, dest_path: String, on_done: Callable) -> void:
	var buffer_in_memory := OS.has_feature("web")
	var req := HTTPRequest.new()
	if not buffer_in_memory:
		DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
		req.download_file = dest_path
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		on_done.call(false, "request_error")
		return
	var res: Array = await req.request_completed
	req.queue_free()
	var result := int(res[0])
	var code := int(res[1])
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		on_done.call(false, "http:%d/%d" % [result, code])
		return
	if buffer_in_memory and not _store_body_to_file(res[3], dest_path):
		on_done.call(false, "write_error")
		return
	on_done.call(true, "")


## 把内存里的字节落盘到 dest_path(含建父目录)。Web 传输路径用。抽成独立方法,便于
## headless 门单测:download_file 那条路需真网络无法测,这条纯写盘可测——且它正是
## download_file 在 Web 上失守的那一步(字节没落进 user://)。
func _store_body_to_file(body: PackedByteArray, dest_path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
	var f := FileAccess.open(dest_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(body)
	f.close()
	return true
