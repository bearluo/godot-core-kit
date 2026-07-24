extends Node
## HttpPackTransport —— PackUpdater 的生产传输适配器(基于 HTTPRequest)。
##
## 满足 PackUpdater 的「传输接缝」:
##   fetch_text(url, on_done: Callable(ok: bool, text: String))
##   fetch_file(url, dest_path, on_done: Callable(ok: bool, reason: String))
##
## 这是真实网络适配器。kit 的 headless 测试门(run_all)无网络,故本类不被门
## 覆盖;PackUpdater 的行为单测经注入内存假件覆盖传输路径。真机联网验证排在
## fortune-mill 接入的后续轮次。
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


## 下载文件到 dest_path(HTTPRequest.download_file 直接落盘,不整读进内存)。
func fetch_file(url: String, dest_path: String, on_done: Callable) -> void:
	DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
	var req := HTTPRequest.new()
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
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	on_done.call(ok, "" if ok else "http:%d/%d" % [result, code])
