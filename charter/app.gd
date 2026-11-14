extends Node

signal chart_changed
signal chart_replaced
signal chart_live_changed
signal selection_changed
signal playhead_changed(beat: float)
## 用户主动跳转（点时间轴、拖进度条）。播放中收到它会重新对齐音频。
signal seek_requested(beat: float)
signal tool_changed(tool: String)
signal status_changed
signal save_state_changed
signal validation_changed(issues: Array)
signal notice(message: String, level: String)
signal appearance_changed
signal preview_sfx
signal snap_changed(division: int)
signal flow_changed(down: bool)
signal stretch_changed(value: float)
signal audio_import_requested
signal audio_detect_requested(path: String)

var chart: Chart = null
var chart_path: String = ""
var dirty: bool = false
var playhead_beat: float = 0.0
var last_import_report: String = ""
var playtest_offset_ms: float = 0.0
## 输出延迟回退（ms）。驱动报告 0 时使用（Android/Web 常见）；0 = 自动。
var audio_latency_ms: float = 0.0
## Music / SFX 总线音量（0–100），编辑器「音频」弹窗和试玩设置共用。
var music_volume: float = 100.0
var sfx_volume: float = 100.0
var flow_scale: float = 1.0
var ffmpeg_path: String = "ffmpeg"
var star_speed: float = 1.0
## Path 等待阶段的启动提示（全局外观设置，不参与判定）。
const PATH_WAIT_MODES: Array[String] = ["off", "progress", "shrink"]
const PATH_WAIT_LABELS: Array[String] = ["关闭", "环形进度", "淡蓝收缩圆环"]
var path_wait_indicator: String = "progress"
## Trace 门框主色（默认银白）。
var note_skin: String = "candy"
## 画质选项（视图 → 画质）。全部只影响渲染，不碰判定。
var quality_preset: String = "high"
## 0 = 关，1 = 2×，2 = 4×（2D 层的 MSAA）。高画质用 2×，极高才上 4×。
var aa_2d_level: int = 1
## 3D 环抗锯齿：0 = 关，1 = 2x，2 = 4x
var msaa_3d_level: int = 1
## 环编辑 2D 形状浮层的位置/大小：[x, y, w, h]，空 = 居中默认。
var ring_pad_rect: Array = []
var note_detail_fine: bool = true
var note_glow: bool = true
## long / short / off
var cursor_trail: String = "long"
## full / light / off
var fx_budget: String = "full"
## high / mid / low（3D 背景渲染分辨率 0.8 / 0.65 / 0.5）
var ring_3d_scale: String = "high"
## 3D 背景刷新率上限 60 / 30（只在视角或形变变化时重画；2D 与判定永远按游戏帧率）
var ring_3d_hz: int = 30
var bar_lines: bool = true
## HUD 选项（视图 → 界面）。只影响显示，不碰判定。
## 80 / 100 / 120
var hud_scale: int = 100
## center / corner / off
var hud_combo_mode: String = "center"
## ring / off
var hud_progress_style: String = "ring"
## note / ring_in / ring_out / center / off
var hud_judge_position: String = "ring_out"
## 100 / 85 / 70
var hud_opacity: int = 100
var hud_show_title: bool = true
var hud_show_difficulty: bool = true
var hud_show_percent: bool = false
var hud_show_time: bool = false
var hud_show_watermark: bool = false
## 背景明暗（百分比，100 = 默认观感）：静图和 BGA 共用。
var background_brightness: int = 100
## 试玩时鼠标左右键是否算 Tap（关掉后移动/滚轮照常）。
var mouse_keys: bool = true
## 右侧预览宽度与折叠状态（编辑器布局记忆）。
var preview_width: float = 340.0
var preview_collapsed: bool = false
var hit_fx_style: String = "burst"
var hit_sfx_style: String = "default"
## 试玩光标大小倍率（1.0 = 默认）。
var cursor_scale: float = 1.0
## 帧率上限："60" / "120" / "144" / "240" / "vsync" / "unlimited"。
## 默认 120：240Hz 屏上跑不满 240 会按 240/120 交替出帧，反而比稳定 120 更抖。
var frame_cap: String = "120"
## 音频缓冲（ms）。Godot 只在启动时读它，改动写进 override.cfg，重启生效。
var audio_buffer_ms: int = 3
## 局内动态校准判定偏移（默认关）。
var dynamic_offset: bool = false
## AUTO 自动演示：试玩时自动完美演奏，用来快速检查谱面（成绩不计入）。
var playtest_auto: bool = false
## 上一局的平均判定偏差，供试玩设置显示。
var last_bias_ms: float = 0.0

## 在线 osu! 谱面的星标收藏（谱面包 id）。
var osu_favorites: Array[int] = []

var selected_notes: Array[int] = []
var clipboard_notes: Array[Dictionary] = []
var selected_region_id: int = -1
var selected_event_id: String = ""
var selected_shape_id: String = "S0"
var selected_segment_index: int = -1
var selected_view_index: int = -1

var tool: String = "select"
var snap_division: int = GridDivisions.DEFAULT_DIVISION
var beat_subdivisions: int = 4
var vertical_lines: int = 11
var vertical_stretch: float = 0.0
var zoom_px_per_beat: float = 28.0
var time_flows_down: bool = true
var hud_visible: bool = true
var use_3d_ring: bool = true
var mouse_tilt: bool = true
var debug_overlay: bool = false
var waveform_visible: bool = true
var ghost_regions: bool = false
var boundary_mode: bool = false

var undo := UndoStack.new()
var _edit_before: Dictionary = {}
var _editing: bool = false
var _live_change_pending: bool = false
## 环工作区打开时，被盖住的检查器不用跟着重建。
var ring_editor_open: bool = false
var _validation_pending: bool = false
var _validation_timer: float = 0.0
var _commands_since_autosave: int = 0
var _autosave_timer: Timer

## ── 转谱窗口 ─────────────────────────────────────────────────────────────
## 导入（osu / 舞萌）不再覆盖当前谱面：另开一个窗口，窗口顶部能切难度。
signal import_set_changed
## 同一个来源（或同一首歌）下的难度组：每项 {"name": String, "chart": Chart}。
## 下拉框直接读它；导入时一次性把来源里的所有难度都转好放进来。
signal difficulties_changed
## 标签栏变化（新建/切换/关闭）。
signal tabs_changed
var difficulties: Array[Dictionary] = []
var difficulty_index: int = 0
var _switching_difficulty: bool = false
## 当前窗口在编辑的是一个难度套组文件（非空时保存写回套组）。
var set_path: String = ""
var import_source: String = ""
var import_kind: String = ""                       # "osu" | "simai"
var import_difficulties: Array[Dictionary] = []     # [{index, name, label}]（兼容旧下拉）
var import_index: int = 0
var child_window: bool = false
## 打开过的谱面标签页；每个标签保存一份完整文档状态。
var tabs: Array[DocTab] = []
var active_tab: int = -1


func _ready() -> void:
	_load_settings()
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 60.0
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_on_autosave_timer)
	add_child(_autosave_timer)
	child_window = "--child-window" in OS.get_cmdline_user_args()
	if child_window:
		# 新开的转谱窗口默认最大化：编辑器三栏 + 顶部工具在 1600×900 以下会挤掉右侧控件。
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	var set_arg := cmdline_value("--open-set=")
	if not set_arg.is_empty():
		# 转谱窗口：先放一张空谱占位，等主界面建好再载入套组。
		set_chart(Chart.new(), "", false)
		call_deferred("_boot_set_window", set_arg)
		return
	var import_arg := cmdline_value("--import-source=")
	if not import_arg.is_empty():
		# 转谱窗口：先放一张空谱占位，等主界面建好再导入，
		# 这样 main.gd 不会在 _ready 里拿到 null chart。
		set_chart(Chart.new(), "", false)
		call_deferred("_boot_import_window", import_arg)
		return
	var demo_path := "user://charts/demo.json"
	var start_chart: Chart = null
	if FileAccess.file_exists(demo_path):
		start_chart = ChartIO.load_chart(demo_path)
	if start_chart == null and FileAccess.file_exists("res://charts/demo.json"):
		start_chart = ChartIO.load_chart("res://charts/demo.json")
	if start_chart == null:
		start_chart = DemoChart.make_demo()
	# 启动时载入的示例谱不算“改过”：否则自动保存会把用户上一次的
	# user://autosave.json 覆盖成示例谱（真正的谱面只剩 .bak.1..5）。
	set_chart(start_chart, demo_path, false)
	call_deferred("_set_initial_focus_notice")


static func cmdline_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


## 转谱窗口的启动流程：解析来源 → 建难度列表 → 导入第一份。
func _boot_import_window(source: String) -> void:
	if open_import_source(source):
		ensure_tab()
		return
	notice.emit("转谱窗口：读不出 %s 的难度列表" % source.get_file(), "error")
	set_chart(DemoChart.make_demo(), "user://charts/demo.json", false)
	ensure_tab()


## 转谱窗口的启动流程（套组版）：读 set.json，把里面每个难度都装进下拉框。
func _boot_set_window(path: String) -> void:
	if open_set_file(path):
		ensure_tab()
		return
	notice.emit("转谱窗口：打不开 %s" % path.get_file(), "error")
	set_chart(DemoChart.make_demo(), "user://charts/demo.json", false)
	ensure_tab()


## 打开一个导入来源（.osz/.zip/maidata.txt），把来源里的所有难度都转好放进难度组，
## 所以不管在哪个窗口导入，顶部都会出现难度下拉框。
func open_import_source(source: String) -> bool:
	if source.is_empty() or not FileAccess.file_exists(source):
		return false
	import_source = source
	import_kind = ""
	import_difficulties.clear()
	import_index = 0
	difficulties.clear()
	var simai := SimaiIO.list_maidata(source)
	if not simai.is_empty():
		import_kind = "simai"
		for i in simai.size():
			var item: Dictionary = simai[i]
			var version := String(item.get("version", ""))
			import_difficulties.append({
				"index": int(item.get("index", i)),
				"name": version if not version.is_empty() else "未命名难度",
				"label": import_label(version, String(item.get("title", "")), String(item.get("creator", "")), ""),
			})
	else:
		var diffs := OsuIO.list_osz_difficulties(source)
		if diffs.is_empty():
			import_source = ""
			return false
		import_kind = "osu"
		for i in diffs.size():
			var item: Dictionary = diffs[i]
			var mode_label := "taiko" if int(item.get("mode", 0)) == 1 else "std"
			var version := String(item.get("version", ""))
			import_difficulties.append({
				"index": i,
				"name": version if not version.is_empty() else "未命名难度",
				"label": import_label(version, String(item.get("title", "")), String(item.get("creator", "")), mode_label),
			})
	# 一次性把每个难度都转出来：切换是瞬时的，也不会因为重新导入丢改动。
	for i in import_difficulties.size():
		var entry: Dictionary = import_difficulties[i]
		var converted: Chart = null
		if import_kind == "simai":
			converted = SimaiIO.import_maidata(source, int(entry.get("index", i)))
		else:
			var result := OsuIO.import_osz(source, int(entry.get("index", i)))
			if not result.is_empty():
				converted = result.get("chart")
		if converted != null:
			difficulties.append({"name": String(entry.get("name", "难度")), "chart": converted})
	if difficulties.is_empty():
		return false
	# 先把所有转好的谱面落盘成一个难度套组文件，再切第一个进去。
	set_path = import_set_target(source)
	ChartIO.save_set(set_path, difficulties, String((difficulties[0].get("chart") as Chart).metadata.get("title", "")), source)
	import_set_changed.emit()
	return switch_difficulty(0)


## 导入时套组写到 user://sets/<曲名> [导入].set.json。
func import_set_target(source: String) -> String:
	var base := source.get_file().get_basename()
	var title := base
	if not difficulties.is_empty():
		var first: Chart = difficulties[0].get("chart", null)
		if first != null:
			title = String(first.metadata.get("title", base))
	var slug := _safe_file_name("%s [导入]" % title)
	if slug.is_empty():
		slug = "imported"
	var dir := "user://sets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir.path_join(slug + ".set.json")


## 打开一个难度套组文件（.set.json）。
func open_set_file(path: String) -> bool:
	var loaded := ChartIO.load_set(path)
	if not bool(loaded.get("ok", false)):
		notice.emit("打开难度套组失败：%s" % String(loaded.get("error", "")), "error")
		return false
	difficulties.clear()
	for entry in loaded.get("entries", []):
		difficulties.append(entry)
	difficulty_index = 0
	set_path = path
	import_source = String(loaded.get("source", ""))
	import_set_changed.emit()
	return switch_difficulty(0)


## 把难度组写回套组文件；path 为空时写回当前 set_path。
func save_set_file(path: String = "") -> bool:
	if difficulties.is_empty():
		return false
	var target := path if not path.is_empty() else set_path
	if target.is_empty():
		return false
	var title := ""
	var first: Chart = difficulties[0].get("chart", null)
	if first != null:
		title = String(first.metadata.get("title", ""))
	if ChartIO.save_set(target, difficulties, title, import_source) != OK:
		notice.emit("保存难度套组失败：%s" % ChartIO.last_error, "error")
		return false
	set_path = target
	chart_path = target
	dirty = false
	save_state_changed.emit()
	status_changed.emit()
	var faint := 0
	for entry in difficulties:
		faint += _low_contrast_count(entry.get("chart", null))
	if faint > 0:
		notice.emit("已保存 %d 个难度到 %s；其中 %d 个音符的配色对比度偏低（不影响保存）" % [difficulties.size(), target.get_file(), faint], "warning")
	else:
		notice.emit("已保存 %d 个难度到 %s" % [difficulties.size(), target.get_file()], "info")
	return true


## 当前窗口能切的所有难度名（下拉框用）。
func difficulty_names() -> Array[String]:
	var names: Array[String] = []
	for entry in difficulties:
		names.append(String(entry.get("name", "难度")))
	return names


func difficulty_name(index: int) -> String:
	if index < 0 or index >= difficulties.size():
		return ""
	return String(difficulties[index].get("name", "难度"))


## 切到难度组里的第 index 个（0 起）。
func switch_difficulty(index: int) -> bool:
	if index < 0 or index >= difficulties.size():
		return false
	var target: Chart = difficulties[index].get("chart", null)
	if target == null:
		return false
	difficulty_index = index
	import_index = index
	var keep_path := set_path if not set_path.is_empty() else chart_path
	_switching_difficulty = true
	set_chart(target, keep_path, false)
	_switching_difficulty = false
	_update_window_title()
	import_set_changed.emit()
	difficulties_changed.emit()
	return true


## 给同一首歌加一个难度：把当前谱面复制一份放进难度组。
func add_difficulty_copy(label: String) -> int:
	if chart == null:
		return -1
	# 组还不存在时，先把当前谱面当成第 1 个难度放进去，才有“同一首歌”的容器。
	if difficulties.is_empty():
		var current_name := String(chart.metadata.get("version", "难度 1"))
		difficulties.append({"name": current_name if not current_name.is_empty() else "难度 1", "chart": chart})
		difficulty_index = 0
	var copy := ChartIO.chart_from_dict(ChartIO.chart_to_dict(chart))
	var name := label.strip_edges()
	if name.is_empty():
		name = "难度 %d" % (difficulties.size() + 1)
	copy.metadata["version"] = name
	difficulties.append({"name": name, "chart": copy})
	difficulty_index = difficulties.size() - 1
	difficulties_changed.emit()
	import_set_changed.emit()
	return difficulty_index


func remove_difficulty(index: int) -> bool:
	if difficulties.size() <= 1 or index < 0 or index >= difficulties.size():
		return false
	difficulties.remove_at(index)
	difficulty_index = clampi(difficulty_index, 0, difficulties.size() - 1)
	switch_difficulty(difficulty_index)
	return true


func clear_difficulties() -> void:
	if difficulties.is_empty():
		return
	difficulties.clear()
	difficulty_index = 0
	difficulties_changed.emit()
	import_set_changed.emit()


## 把难度组里每一份都存成单独文件，返回写成功的个数。
func save_all_difficulties(dir: String) -> int:
	if difficulties.is_empty():
		return 0
	var target_dir := dir if not dir.is_empty() else "user://charts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))
	var written := 0
	for i in difficulties.size():
		var entry: Dictionary = difficulties[i]
		var c: Chart = entry.get("chart", null)
		if c == null:
			continue
		var name := _safe_file_name("%s [%s]" % [String(c.metadata.get("title", "chart")), String(entry.get("name", i))])
		var path := target_dir.path_join(name + ".json")
		if ChartIO.atomic_write(path, ChartIO.to_json(c)) == OK:
			written += 1
	return written


static func _safe_file_name(text: String) -> String:
	var out := ""
	for ch in text:
		if ch in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
			out += "_"
		else:
			out += ch
	return out.strip_edges()


static func import_label(version: String, title: String, creator: String, mode_label: String) -> String:
	var head := version if not version.is_empty() else "未命名难度"
	if not mode_label.is_empty():
		head += "  [%s]" % mode_label
	if title.is_empty() and creator.is_empty():
		return head
	if creator.is_empty():
		return "%s  %s" % [head, title]
	return "%s  %s  (%s)" % [head, title, creator]


func import_difficulty_label(position: int) -> String:
	if position < 0 or position >= import_difficulties.size():
		return ""
	return String(import_difficulties[position].get("label", ""))


## 切换转谱窗口里的难度（position 是下拉列表下标）。旧名字保留，等价于 switch_difficulty。
func select_import_difficulty(position: int) -> bool:
	return switch_difficulty(position)


func _update_window_title() -> void:
	if chart == null or DisplayServer.get_name() == "headless":
		return
	var title := String(chart.metadata.get("title", "Tamaki₃ 制谱器"))
	var version := difficulty_name(difficulty_index)
	var suffix := "  %s" % version if not version.is_empty() else ""
	DisplayServer.window_set_title("Tamaki₃ 制谱器  —  %s%s" % [title, suffix])


const SETTINGS_PATH := "user://settings.json"
## 舞台底色（project.godot 的 default_clear_color），用于对比度提示。
const STAGE_BACKGROUND := Color(0.043137, 0.047059, 0.062745)


func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if parsed is Dictionary:
			var data: Dictionary = parsed
			note_skin = String(data.get("note_skin", note_skin))
			# 旧版只有 aa_2d 布尔值，读进来换算成三档。
			aa_2d_level = clampi(int(data.get("aa_2d_level", 2 if bool(data.get("aa_2d", true)) else 0)), 0, 3)
			msaa_3d_level = clampi(int(data.get("msaa_3d_level", 1)), 0, 7)
			if data.get("ring_pad_rect") is Array:
				ring_pad_rect = data["ring_pad_rect"]
			note_detail_fine = bool(data.get("note_detail_fine", note_detail_fine))
			note_glow = bool(data.get("note_glow", note_glow))
			var trail_mode := String(data.get("cursor_trail", cursor_trail))
			cursor_trail = trail_mode if trail_mode in ["long", "short", "off"] else "long"
			var fx_mode := String(data.get("fx_budget", fx_budget))
			fx_budget = fx_mode if fx_mode in ["full", "light", "off"] else "full"
			var ring_scale := String(data.get("ring_3d_scale", ring_3d_scale))
			ring_3d_scale = ring_scale if ring_scale in ["high", "mid", "low"] else "high"
			ring_3d_hz = 30 if int(data.get("ring_3d_hz", ring_3d_hz)) == 30 else 60
			bar_lines = bool(data.get("bar_lines", bar_lines))
			var preset := String(data.get("quality_preset", "high"))
			quality_preset = preset if preset in ["ultra", "high", "mid", "low", "custom"] else "high"
			hud_scale = int(data.get("hud_scale", hud_scale))
			hud_scale = hud_scale if hud_scale in [80, 100, 120] else 100
			var combo_mode := String(data.get("hud_combo_mode", hud_combo_mode))
			hud_combo_mode = combo_mode if combo_mode in ["center", "corner", "off"] else "center"
			var progress_style := String(data.get("hud_progress_style", hud_progress_style))
			hud_progress_style = progress_style if progress_style in ["ring", "off"] else "ring"
			var judge_pos := String(data.get("hud_judge_position", hud_judge_position))
			hud_judge_position = judge_pos if judge_pos in ["note", "ring_in", "ring_out", "center", "off"] else "ring_out"
			hud_opacity = int(data.get("hud_opacity", hud_opacity))
			hud_opacity = hud_opacity if hud_opacity in [100, 85, 70] else 100
			hud_show_title = bool(data.get("hud_show_title", hud_show_title))
			hud_show_difficulty = bool(data.get("hud_show_difficulty", hud_show_difficulty))
			hud_show_percent = bool(data.get("hud_show_percent", hud_show_percent))
			hud_show_time = bool(data.get("hud_show_time", hud_show_time))
			hud_show_watermark = bool(data.get("hud_show_watermark", hud_show_watermark))
			background_brightness = clampi(int(data.get("background_brightness", background_brightness)), 0, 100)
			mouse_keys = bool(data.get("mouse_keys", mouse_keys))
			preview_width = clampf(float(data.get("preview_width", preview_width)), 280.0, 720.0)
			preview_collapsed = bool(data.get("preview_collapsed", preview_collapsed))
			hit_fx_style = String(data.get("hit_fx_style", hit_fx_style))
			hit_sfx_style = String(data.get("hit_sfx_style", hit_sfx_style))
			ffmpeg_path = String(data.get("ffmpeg", ffmpeg_path))
			frame_cap = String(data.get("frame_cap", frame_cap))
			audio_buffer_ms = clampi(int(data.get("audio_buffer_ms", audio_buffer_ms)), 3, 40)
			playtest_offset_ms = float(data.get("playtest_offset_ms", playtest_offset_ms))
			audio_latency_ms = clampf(float(data.get("audio_latency_ms", audio_latency_ms)), 0.0, 250.0)
			music_volume = clampf(float(data.get("music_volume", music_volume)), 0.0, 100.0)
			sfx_volume = clampf(float(data.get("sfx_volume", sfx_volume)), 0.0, 100.0)
			dynamic_offset = bool(data.get("dynamic_offset", dynamic_offset))
			playtest_auto = bool(data.get("playtest_auto", playtest_auto))
			osu_favorites.clear()
			for value in data.get("osu_favorites", []):
				osu_favorites.append(int(value))
			last_bias_ms = float(data.get("last_bias_ms", last_bias_ms))
			var wait_mode := String(data.get("path_wait_indicator", "progress"))
			path_wait_indicator = wait_mode if wait_mode in PATH_WAIT_MODES else "progress"
			cursor_scale = clampf(float(data.get("cursor_scale", cursor_scale)), 0.5, 2.0)
			flow_scale = clampf(float(data.get("flow_scale", flow_scale)), 0.05, 3.0)
			star_speed = clampf(float(data.get("star_speed", star_speed)), 0.5, 2.0)
	MediaIO.set_ffmpeg_exe(ffmpeg_path)
	apply_frame_cap()
	apply_visual_quality()


## HUD 选项打包给 Preview3D（试玩 HUD 全部从这里读）。
func hud_options() -> Dictionary:
	return {
		"scale": hud_scale,
		"combo_mode": hud_combo_mode,
		"progress_style": hud_progress_style,
		"judge_position": hud_judge_position,
		"opacity": hud_opacity,
		"show_title": hud_show_title,
		"show_difficulty": hud_show_difficulty,
		"show_percent": hud_show_percent,
		"show_time": hud_show_time,
		"show_watermark": hud_show_watermark,
	}


## 2D 抗锯齿在运行时就能改：关掉能省 1.5–2.5ms 的填充开销。
func apply_visual_quality() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	match aa_2d_level:
		0:
			viewport.msaa_2d = Viewport.MSAA_DISABLED
		1:
			viewport.msaa_2d = Viewport.MSAA_2X
		2:
			viewport.msaa_2d = Viewport.MSAA_4X
		_:
			viewport.msaa_2d = Viewport.MSAA_8X


## 预设：一次把画质项调成一组常用组合（单项改动后预设显示为「自定义」）。
func apply_quality_preset(name: String) -> void:
	quality_preset = name
	match name:
		"ultra":
			aa_2d_level = 3
			msaa_3d_level = 2
			note_detail_fine = true
			note_glow = true
			cursor_trail = "long"
			fx_budget = "full"
			ring_3d_scale = "native"
			ring_3d_hz = 60
			bar_lines = true
		"low":
			aa_2d_level = 0
			msaa_3d_level = 0
			note_detail_fine = false
			note_glow = false
			cursor_trail = "off"
			fx_budget = "light"
			ring_3d_scale = "low"
			ring_3d_hz = 30
			bar_lines = false
		"mid":
			aa_2d_level = 1
			msaa_3d_level = 1
			note_detail_fine = true
			note_glow = true
			cursor_trail = "short"
			fx_budget = "light"
			ring_3d_scale = "mid"
			ring_3d_hz = 30
			bar_lines = true
		_:
			quality_preset = "high"
			aa_2d_level = 1
			msaa_3d_level = 1
			note_detail_fine = true
			note_glow = true
			cursor_trail = "long"
			fx_budget = "full"
			ring_3d_scale = "native"
			ring_3d_hz = 30
			bar_lines = true


## 帧率选项：60 / 120 保留垂直同步（跑不满就自动落到下一个整除，稳定优先）；
## vsync 完全跟随显示器；unlimited 才关垂直同步、能吃多少吃多少。
func apply_frame_cap() -> void:
	match frame_cap:
		# 显式档位关掉垂直同步：否则 120/144 在 60Hz 屏上永远不起作用。
		"60":
			Engine.max_fps = 60
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"120":
			Engine.max_fps = 120
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"144":
			Engine.max_fps = 144
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"240":
			Engine.max_fps = 240
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"unlimited":
			Engine.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_:
			Engine.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


## override.cfg 的位置：导出包写游戏目录，源码运行写工程目录；Godot 两种都会读。
func audio_override_path() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("override.cfg")
	return "res://override.cfg"


## 音频缓冲是启动期设置（引擎不给运行时接口），只能写 override.cfg 后重启生效。
static func write_buffer_override(path: String, ms: int) -> bool:
	var config := ConfigFile.new()
	if FileAccess.file_exists(path):
		config.load(path)
	config.set_value("audio", "driver/output_latency", clampi(ms, 3, 40))
	return config.save(path) == OK


func set_audio_buffer(ms: int) -> void:
	audio_buffer_ms = clampi(ms, 3, 40)
	save_settings()
	if not write_buffer_override(audio_override_path(), audio_buffer_ms):
		notice.emit("写入 override.cfg 失败，音频缓冲没改", "error")
		return
	var running := int(ProjectSettings.get_setting("audio/driver/output_latency", 15))
	notice.emit("音频缓冲 %dms（重启后生效，当前 %dms）" % [audio_buffer_ms, running], "info")


## Output latency used by playtest/calibration. A positive setting overrides the
## driver value in both directions; 0 means "trust the driver".
func effective_latency_sec() -> float:
	if audio_latency_ms > 0.0:
		return clampf(audio_latency_ms / 1000.0, 0.0, 0.25)
	return maxf(0.0, AudioServer.get_output_latency())


func save_settings() -> void:
	var data := {"path_wait_indicator": path_wait_indicator, "note_skin": note_skin, "hit_fx_style": hit_fx_style, "hit_sfx_style": hit_sfx_style, "ffmpeg": ffmpeg_path, "frame_cap": frame_cap, "audio_buffer_ms": audio_buffer_ms, "playtest_offset_ms": playtest_offset_ms, "audio_latency_ms": audio_latency_ms, "music_volume": music_volume, "sfx_volume": sfx_volume, "dynamic_offset": dynamic_offset, "playtest_auto": playtest_auto, "osu_favorites": osu_favorites, "last_bias_ms": last_bias_ms, "cursor_scale": cursor_scale, "flow_scale": flow_scale, "star_speed": star_speed, "aa_2d_level": aa_2d_level, "msaa_3d_level": msaa_3d_level, "ring_pad_rect": ring_pad_rect, "note_detail_fine": note_detail_fine, "note_glow": note_glow, "cursor_trail": cursor_trail, "fx_budget": fx_budget, "ring_3d_scale": ring_3d_scale, "ring_3d_hz": ring_3d_hz, "bar_lines": bar_lines, "quality_preset": quality_preset,
		"hud_scale": hud_scale, "hud_combo_mode": hud_combo_mode, "hud_progress_style": hud_progress_style,
		"hud_judge_position": hud_judge_position, "hud_opacity": hud_opacity,
		"hud_show_title": hud_show_title, "hud_show_difficulty": hud_show_difficulty,
		"hud_show_percent": hud_show_percent, "hud_show_time": hud_show_time,
		"hud_show_watermark": hud_show_watermark,
		"background_brightness": clampi(background_brightness, 0, 100), "mouse_keys": mouse_keys,
		"preview_width": preview_width, "preview_collapsed": preview_collapsed}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func _set_initial_focus_notice() -> void:
	notice.emit("已载入示例谱：按空格播放，F5 试玩，Ctrl+S 保存。", "info")


func set_ffmpeg_path(path: String) -> void:
	ffmpeg_path = path.strip_edges()
	if ffmpeg_path.is_empty():
		ffmpeg_path = "ffmpeg"
	MediaIO.set_ffmpeg_exe(ffmpeg_path)
	save_settings()
	notice.emit("ffmpeg 路径：%s" % ffmpeg_path, "info")


func set_chart(new_chart: Chart, path: String = "", mark_dirty: bool = false) -> void:
	_live_change_pending = false
	# 打开别的谱面（不是难度组内部切换）时，旧的难度组作废。
	if not _switching_difficulty:
		set_path = ""
		if not difficulties.is_empty():
			difficulties.clear()
			difficulty_index = 0
			difficulties_changed.emit()
			import_set_changed.emit()
	chart_replaced.emit()
	chart = new_chart
	chart_path = path
	dirty = mark_dirty
	playhead_beat = 0.0
	undo.clear()
	selected_notes.clear()
	selected_region_id = -1
	selected_event_id = ""
	selected_shape_id = chart.default_shape_id if chart != null else "S0"
	selected_segment_index = -1
	selected_view_index = -1
	if chart != null:
		snap_division = GridDivisions.normalize(int(chart.editor.get("snap", snap_division)))
		time_flows_down = bool(chart.editor.get("flow_down", time_flows_down))
	chart_changed.emit()
	snap_changed.emit(snap_division)
	flow_changed.emit(time_flows_down)
	selection_changed.emit()
	playhead_changed.emit(playhead_beat)
	save_state_changed.emit()
	status_changed.emit()
	_emit_validation()
	if chart != null and not chart.load_warnings.is_empty():
		notice.emit("；".join(chart.load_warnings), "warning")
		chart.load_warnings.clear()


func apply_detected_timing(bpm: float, offset_ms: float, apply_offset: bool, audio_path: String) -> bool:
	if chart == null:
		return false
	if not is_finite(bpm) or bpm <= 0.0:
		notice.emit("BPM 无效，未应用音频。", "error")
		return false
	if not is_finite(offset_ms):
		notice.emit("offset 无效，未应用音频。", "error")
		return false
	if apply_offset:
		var period_ms := 60000.0 / maxf(1.0, bpm)
		if absf(offset_ms) > period_ms + 1.0:
			notice.emit("offset 超出单拍范围，未应用音频。", "error")
			return false
	var prepared := MediaIO.prepare_audio(audio_path)
	if prepared.is_empty():
		notice.emit("音频读取失败：%s" % MediaIO.last_error, "error")
		return false
	var stream := ChartIO.audio_stream_from_path(prepared)
	if stream == null or stream.get_length() <= 0.0:
		notice.emit("音频播放流加载失败：%s" % audio_path.get_file(), "error")
		return false
	var length_ms := stream.get_length() * 1000.0
	begin_edit()
	chart.audio_path = audio_path
	if not chart.timing.points.is_empty():
		chart.timing.points[0].bpm = clampf(bpm, 20.0, 600.0)
		chart.timing.sort_points()
	if apply_offset:
		chart.offset_ms = offset_ms
		chart.timing.offset_ms = offset_ms
	finish_edit()
	notice.emit("已应用 %s：%.1f BPM，offset %.0f ms，音频 %.2f 秒。" % [
		audio_path.get_file(), chart.timing.bpm_at(0.0), chart.offset_ms, length_ms / 1000.0,
	], "info")
	return true


func snapshot() -> Dictionary:
	if chart == null:
		return {}
	return ChartIO.chart_to_dict(chart)


func restore_snapshot(data: Dictionary) -> void:
	var restored := ChartIO.chart_from_dict(data)
	if restored == null:
		notice.emit("撤销失败：%s" % ChartIO.last_error, "error")
		return
	chart = restored
	_prune_selection()
	chart_changed.emit()
	selection_changed.emit()
	save_state_changed.emit()
	status_changed.emit()
	_emit_validation()


func mutate(callback: Callable) -> void:
	if chart == null:
		return
	var before := snapshot()
	callback.call()
	var after := snapshot()
	if before == after:
		return
	undo.record(before)
	dirty = true
	_after_change()


func begin_edit() -> void:
	if _editing or chart == null:
		return
	_edit_before = snapshot()
	_editing = true


func finish_edit() -> void:
	if not _editing:
		return
	_flush_live_change()
	_editing = false
	var after := snapshot()
	if _edit_before == after:
		return
	undo.record(_edit_before)
	dirty = true
	_after_change()


func _after_change() -> void:
	_commands_since_autosave += 1
	chart_changed.emit()
	save_state_changed.emit()
	status_changed.emit()
	_emit_validation()
	if _commands_since_autosave >= 20:
		autosave()


func touch_chart() -> void:
	## Emit live updates during a drag; the undo entry is recorded on finish_edit().
	# Mouse input may arrive several times per rendered frame. Full validation
	# belongs to the committed edit, not to every intermediate mouse position.
	_live_change_pending = true


func _process(delta: float) -> void:
	_flush_live_change()
	# 校验会扫全谱（自交/可玩性），编辑时没必要每改一格就跑一次。
	if _validation_pending:
		_validation_timer -= delta
		if _validation_timer <= 0.0:
			_validation_pending = false
			if chart != null:
				validation_changed.emit(Validator.validate(chart))


func _flush_live_change() -> void:
	if not _live_change_pending:
		return
	_live_change_pending = false
	chart_live_changed.emit()
	status_changed.emit()


func undo_chart() -> void:
	if chart == null or not undo.can_undo():
		return
	var current := snapshot()
	restore_snapshot(undo.undo(current))
	dirty = true


func redo_chart() -> void:
	if chart == null or not undo.can_redo():
		return
	var current := snapshot()
	restore_snapshot(undo.redo(current))
	dirty = true


func save_chart() -> bool:
	if chart == null:
		return false
	# 难度套组：保存写回 set.json（所有难度一起），不是单张谱面。
	if not set_path.is_empty():
		return save_set_file()
	if chart_path.is_empty():
		notice.emit("请先另存为（Ctrl+Shift+S）", "warning")
		return false
	var errors := Validator.errors(Validator.validate(chart))
	if not errors.is_empty():
		notice.emit("有 %d 个校验错误，已阻止保存：%s" % [errors.size(), errors[0].get("message", "")], "error")
		return false
	var faint := low_contrast_note_count()
	chart.offset_ms = chart.timing.offset_ms
	var err := ChartIO.save_chart(chart, chart_path)
	if err != OK:
		notice.emit("保存失败：%s" % ChartIO.last_error, "error")
		return false
	dirty = false
	_commands_since_autosave = 0
	save_state_changed.emit()
	status_changed.emit()
	if faint > 0:
		notice.emit("已保存 %s；其中 %d 个音符的配色与背景对比度偏低，可能看不清（不影响保存）" % [chart_path.get_file(), faint], "warning")
	else:
		notice.emit("已保存 %s" % chart_path.get_file(), "info")
	return true


func save_chart_as(path: String) -> bool:
	# 另存为单张谱面时，把当前难度从套组里摘出来，避免之后误写回套组。
	if not set_path.is_empty():
		set_path = ""
	chart_path = path
	return save_chart()


func load_chart(path: String) -> bool:
	# .set.json 是难度套组：走套组流程，顶部会出现难度下拉。
	if _is_set_file(path):
		return open_set_file(path)
	var loaded := ChartIO.load_chart(path)
	if loaded == null:
		notice.emit("打开失败：%s" % ChartIO.last_error, "error")
		return false
	set_chart(loaded, path)
	notice.emit("已打开 %s" % path.get_file(), "info")
	return true


## ── 标签页 ─────────────────────────────────────────────────────────────────
## 每个标签保存一份完整的文档状态；切换时把当前状态存回去，再把目标状态装进来。
class DocTab:
	var title: String = "未命名"
	var chart: Chart = null
	var chart_path: String = ""
	var set_path: String = ""
	var difficulties: Array[Dictionary] = []
	var difficulty_index: int = 0
	var dirty: bool = false
	var playhead_beat: float = 0.0
	var undo := UndoStack.new()


func ensure_tab() -> void:
	if not tabs.is_empty():
		stash_active_tab()
		tabs_changed.emit()
		return
	var tab := DocTab.new()
	tab.title = _tab_title_for_current()
	_copy_current_to(tab)
	tabs.append(tab)
	active_tab = 0
	tabs_changed.emit()


func stash_active_tab() -> void:
	if active_tab < 0 or active_tab >= tabs.size():
		return
	_copy_current_to(tabs[active_tab])
	tabs[active_tab].title = _tab_title_for_current()


func _copy_current_to(tab: DocTab) -> void:
	tab.chart = chart
	tab.chart_path = chart_path
	tab.set_path = set_path
	tab.difficulties = difficulties.duplicate()
	tab.difficulty_index = difficulty_index
	tab.dirty = dirty
	tab.playhead_beat = playhead_beat
	tab.undo = undo


## 把当前文档作为新标签放进标签栏（导入/打开新谱面时调用）。
func add_tab_from_current(title: String = "") -> void:
	var tab := DocTab.new()
	_copy_current_to(tab)
	tab.title = title if not title.is_empty() else _tab_title_for_current()
	tabs.append(tab)
	active_tab = tabs.size() - 1
	tabs_changed.emit()


func activate_tab(index: int) -> void:
	if index < 0 or index >= tabs.size() or index == active_tab:
		return
	stash_active_tab()
	active_tab = index
	var tab: DocTab = tabs[index]
	# set_chart 会清空 undo；先换成临时栈，免得洗掉上一个标签的历史。
	undo = UndoStack.new()
	_switching_difficulty = true
	set_chart(tab.chart, tab.chart_path, tab.dirty)
	_switching_difficulty = false
	set_path = tab.set_path
	difficulties = tab.difficulties.duplicate()
	difficulty_index = tab.difficulty_index
	undo = tab.undo
	playhead_beat = tab.playhead_beat
	import_set_changed.emit()
	difficulties_changed.emit()
	playhead_changed.emit(playhead_beat)
	_update_window_title()
	tabs_changed.emit()


func close_tab(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	if index == active_tab:
		tabs.remove_at(index)
		if tabs.is_empty():
			set_chart(DemoChart.make_empty({"bpm": 120.0}), "", false)
			add_tab_from_current("未命名")
			return
		active_tab = -1
		activate_tab(clampi(index, 0, tabs.size() - 1))
	else:
		tabs.remove_at(index)
		if index < active_tab:
			active_tab -= 1
	tabs_changed.emit()


func tab_label(index: int) -> String:
	if index == active_tab:
		return ("● " if dirty else "") + _tab_title_for_current()
	if index < 0 or index >= tabs.size():
		return ""
	var tab: DocTab = tabs[index]
	return ("● " if tab.dirty else "") + tab.title


func _tab_title_for_current() -> String:
	if not set_path.is_empty():
		return set_path.get_file().get_basename()
	if not chart_path.is_empty():
		return chart_path.get_file().get_basename()
	var title := String(chart.metadata.get("title", "")) if chart != null else ""
	return title if not title.is_empty() else "未命名"


## 导入失败时把当前标签的难度组/路径恢复回来（open_import_source 会先清空它们）。
func restore_active_tab() -> void:
	if active_tab < 0 or active_tab >= tabs.size():
		return
	var tab: DocTab = tabs[active_tab]
	set_path = tab.set_path
	difficulties = tab.difficulties.duplicate()
	difficulty_index = tab.difficulty_index
	import_set_changed.emit()
	difficulties_changed.emit()


func _is_set_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var head := file.get_as_text()
	file.close()
	return head.contains("\"tamaki3-set\"")


func new_chart(meta: Dictionary) -> void:
	set_chart(DemoChart.make_empty(meta), "", true)
	notice.emit("新谱面已创建；先设置 BPM/offset，再画第一条边界。", "info")


func import_osz(path: String, difficulty_index: int = 0) -> bool:
	var result := OsuIO.import_osz(path, difficulty_index)
	last_import_report = String(result.get("report", ""))
	if result.is_empty():
		notice.emit("osu! 导入失败：%s" % OsuIO.last_error, "error")
		return false
	var imported: Chart = result["chart"]
	set_chart(imported, "", true)
	var stream := ChartIO.audio_stream_from_path(imported.audio_path)
	if stream is AudioStream:
		last_import_report += "\n音频流已加载：%s（%.1fs）" % [imported.audio_path.get_file(), stream.get_length()]
		print("[audio] imported ", imported.audio_path, " len=", stream.get_length())
	else:
		last_import_report += "\n音频流未加载：%s" % imported.audio_path
		print("[audio] FAILED to load ", imported.audio_path)
	notice.emit("已导入 %s：%d 个音符，%d 个 BPM 点。请另存为 JSON。" % [path.get_file(), imported.notes.size(), imported.timing.points.size()], "info")
	return true


func import_maimai(path: String, difficulty_index: int = 0) -> bool:
	var imported := SimaiIO.import_maidata(path, difficulty_index)
	last_import_report = SimaiIO.last_report
	if imported == null:
		notice.emit("舞萌导入失败：%s" % SimaiIO.last_error, "error")
		return false
	set_chart(imported, "", true)
	notice.emit("已导入 %s：%d 个音符，%d 个 BPM 点。请另存为 JSON。" % [path.get_file(), imported.notes.size(), imported.timing.points.size()], "info")
	return true


func export_lbp(path: String) -> bool:
	if chart == null:
		return false
	var err := LBPIO.export_to_file(chart, path)
	if err != OK:
		notice.emit("导出 .lbp 失败：%s" % LBPIO.last_error, "error")
		return false
	notice.emit("已导出 %s" % path.get_file(), "info")
	return true


func autosave() -> void:
	# 基准与无头测试（单元测试、编辑器审计）会临时换掉当前谱面，
	# 自动保存会把用户正在编辑的 autosave.json 覆盖成测试谱面。
	if DisplayServer.get_name() == "headless" or "--bench" in OS.get_cmdline_user_args():
		return
	if chart == null or not dirty:
		return
	var data := ChartIO.to_json(chart)
	# 转谱窗口不覆盖主窗口的 autosave.json。
	var target := "user://autosave_import.json" if child_window else "user://autosave.json"
	var err := ChartIO.atomic_write(target, data)
	if err == OK:
		_commands_since_autosave = 0
		status_changed.emit()


func load_autosave() -> bool:
	if not FileAccess.file_exists("user://autosave.json"):
		notice.emit("没有自动保存文件", "warning")
		return false
	var loaded := ChartIO.load_chart("user://autosave.json")
	if loaded == null:
		notice.emit("自动保存损坏：%s" % ChartIO.last_error, "error")
		return false
	set_chart(loaded, "", true)
	notice.emit("已恢复自动保存；请另存为正式文件。", "info")
	return true


func _on_autosave_timer() -> void:
	autosave()


func set_playhead(beat: float) -> void:
	if chart == null:
		return
	playhead_beat = clampf(beat, -4.0, chart.duration_beats() + 8.0)
	playhead_changed.emit(playhead_beat)


## 用户发起的跳转：点时间轴、拖进度条、按定位按钮都走这里。
## 播放中光改 playhead_beat 会被下一帧的音频推进覆盖，所以要先发信号让播放器重新对齐。
func seek(beat: float) -> void:
	if chart == null:
		return
	var target := clampf(beat, -4.0, chart.duration_beats() + 8.0)
	seek_requested.emit(target)
	set_playhead(target)


func snap_beat(beat: float, bypass: bool = false) -> float:
	return GridDivisions.snap(beat, snap_division, bypass)


func set_snap_division(division: int) -> void:
	var normalized := GridDivisions.normalize(division)
	if chart != null:
		chart.editor["snap"] = normalized
	if snap_division == normalized:
		return
	snap_division = normalized
	snap_changed.emit(snap_division)
	status_changed.emit()


func set_time_flows_down(down: bool) -> void:
	if chart != null:
		chart.editor["flow_down"] = down
	if time_flows_down == down:
		return
	time_flows_down = down
	flow_changed.emit(down)
	status_changed.emit()


func set_vertical_stretch(value: float) -> void:
	var clamped := clampf(snappedf(value, 0.1), 0.0, 10.0)
	if is_equal_approx(vertical_stretch, clamped):
		return
	vertical_stretch = clamped
	stretch_changed.emit(vertical_stretch)


func request_audio_import() -> void:
	audio_import_requested.emit()


func request_audio_detect() -> void:
	audio_detect_requested.emit(chart.audio_path if chart != null else "")


## Writes an auto-detected tempo into the chart. The base BPM always lives on
## the first timing point (the inspector labels it "基准 BPM"), and the offset is
## mirrored into both Chart.offset_ms and TimingMap.offset_ms because the save
## path treats the timing map as authoritative.
func set_tool(new_tool: String) -> void:
	tool = new_tool
	boundary_mode = new_tool == "boundary"
	tool_changed.emit(tool)
	status_changed.emit()


func select_note(note_id: int, additive: bool = false) -> void:
	if not additive:
		selected_notes.clear()
		selected_region_id = -1
		selected_event_id = ""
		selected_view_index = -1
	if note_id >= 0 and not selected_notes.has(note_id):
		selected_notes.append(note_id)
	selection_changed.emit()
	status_changed.emit()


func toggle_note_selection(note_id: int) -> void:
	if note_id < 0:
		return
	selected_region_id = -1
	selected_event_id = ""
	selected_view_index = -1
	if selected_notes.has(note_id):
		selected_notes.erase(note_id)
	else:
		selected_notes.append(note_id)
	selection_changed.emit()
	status_changed.emit()


func mirror_selected_notes() -> void:
	var notes := selection_with_partners()
	if notes.is_empty():
		return
	begin_edit()
	for note in notes:
		note.mirror_u()
	finish_edit()
	notice.emit("已镜像 %d 个音符" % notes.size(), "info")


func rotate_selected_notes(degrees: float) -> void:
	var notes := get_selected_notes()
	if notes.is_empty():
		return
	begin_edit()
	for note in notes:
		note.angle = fposmod(note.angle + degrees, 360.0)
		note.tail_angle = fposmod(note.tail_angle + degrees, 360.0)
		for point in note.visual_pts:
			point["da"] = float(point.get("da", 0.0)) + degrees
		if note.type == "bell":
			note.center_u = fposmod(note.center_u + degrees / 360.0, 1.0)
		if note.type == "path":
			var rad := deg_to_rad(degrees)
			for point in note.trace_pts:
				var x := float(point.get("x", 0.0))
				var y := float(point.get("y", 0.0))
				point["x"] = x * cos(rad) - y * sin(rad)
				point["y"] = x * sin(rad) + y * cos(rad)
	finish_edit()
	notice.emit("已旋转 %d 个音符 %.0f°" % [notes.size(), degrees], "info")


func copy_selected_notes() -> void:
	clipboard_notes.clear()
	var notes := selection_with_partners()
	if notes.is_empty():
		return
	var base_beat := notes[0].beat
	for note in notes:
		var data := note.to_dict()
		data["beat"] = note.beat - base_beat
		data["end_beat"] = note.end_beat - base_beat
		clipboard_notes.append(data)
	notice.emit("已复制 %d 个音符" % notes.size(), "info")


func paste_notes() -> void:
	if chart == null or clipboard_notes.is_empty():
		return
	var base_beat := playhead_beat
	var pasted: Array[int] = []
	begin_edit()
	for data in clipboard_notes:
		var note := Note.from_dict(data)
		note.id = chart.next_note_id()
		note.beat = base_beat + float(data.get("beat", 0.0))
		note.end_beat = base_beat + float(data.get("end_beat", 0.0))
		chart.notes.append(note)
		pasted.append(note.id)
	finish_edit()
	select_notes(pasted)
	notice.emit("已粘贴 %d 个音符" % pasted.size(), "info")


func select_notes(ids: Array[int]) -> void:
	selected_notes = ids.duplicate()
	selected_region_id = -1
	selected_event_id = ""
	selected_view_index = -1
	selection_changed.emit()
	status_changed.emit()


func select_region(region_id: int) -> void:
	selected_notes.clear()
	selected_region_id = region_id
	selected_event_id = ""
	selected_view_index = -1
	selection_changed.emit()
	status_changed.emit()


func select_event(event_id: String) -> void:
	selected_notes.clear()
	selected_region_id = -1
	selected_event_id = event_id
	selected_view_index = -1
	selection_changed.emit()
	status_changed.emit()


func select_shape(shape_id: String) -> void:
	selected_shape_id = shape_id
	selection_changed.emit()
	status_changed.emit()


func select_segment(index: int) -> void:
	selected_segment_index = index
	selection_changed.emit()
	status_changed.emit()


func select_view(index: int) -> void:
	selected_view_index = index
	selection_changed.emit()
	status_changed.emit()


func clear_selection() -> void:
	selected_notes.clear()
	selected_region_id = -1
	selected_event_id = ""
	selected_view_index = -1
	selection_changed.emit()
	status_changed.emit()


func get_selected_notes() -> Array[Note]:
	var result: Array[Note] = []
	if chart == null:
		return result
	for note in chart.notes:
		if selected_notes.has(note.id):
			result.append(note)
	return result


## 选中 Anchor 时把同拍、同 pairId 的伙伴一并带上：删除/复制/镜像按整对处理。
func with_anchor_partners(notes: Array[Note]) -> Array[Note]:
	var result: Array[Note] = []
	var seen := {}
	for note in notes:
		if seen.has(note.id):
			continue
		seen[note.id] = true
		result.append(note)
		if note.type == "anchor" and chart != null:
			var partner := chart.anchor_partner(note)
			if partner != null and not seen.has(partner.id):
				seen[partner.id] = true
				result.append(partner)
	return result


func selection_with_partners() -> Array[Note]:
	return with_anchor_partners(get_selected_notes())


func get_selected_note() -> Note:
	var notes := get_selected_notes()
	return notes[0] if notes.size() == 1 else null


func get_selected_region() -> Region:
	if chart == null or selected_region_id < 0:
		return null
	for region in chart.regions:
		if region.id == selected_region_id:
			return region
	return null


func get_selected_event() -> BoundaryEvent:
	if chart == null or selected_event_id.is_empty():
		return null
	for event in chart.events:
		if event.id == selected_event_id:
			return event
	return null


func get_selected_shape() -> BoundaryShape:
	if chart == null:
		return null
	return chart.get_shape(selected_shape_id)


func get_selected_segment() -> BoundarySegment:
	var shape := get_selected_shape()
	if shape == null:
		return null
	var sorted := shape.sorted_segments()
	if selected_segment_index < 0 or selected_segment_index >= sorted.size():
		return null
	return sorted[selected_segment_index]


func get_selected_view() -> ViewState:
	if chart == null or selected_view_index < 0 or selected_view_index >= chart.view_states.size():
		return null
	return chart.view_states[selected_view_index]


func _prune_selection() -> void:
	var valid_notes: Array[int] = []
	for note in chart.notes:
		if selected_notes.has(note.id):
			valid_notes.append(note.id)
	selected_notes = valid_notes
	if selected_region_id >= 0:
		var found := false
		for region in chart.regions:
			if region.id == selected_region_id:
				found = true
				break
		if not found:
			selected_region_id = -1
	if not selected_event_id.is_empty():
		var found := false
		for event in chart.events:
			if event.id == selected_event_id:
				found = true
				break
		if not found:
			selected_event_id = ""
	if chart.get_shape(selected_shape_id) == null:
		selected_shape_id = chart.default_shape_id
	selected_segment_index = -1


func _emit_validation() -> void:
	_validation_pending = true
	_validation_timer = 0.12


func validation_issues() -> Array[Dictionary]:
	if chart == null:
		return []
	return Validator.validate(chart)


## 保存时的颜色提示：统计自定义色或配色组色与舞台背景对比度过低的音符。
## 设计文档要求“提示但不阻止保存”，所以只发 warning，不做拦截。
func low_contrast_note_count() -> int:
	return _low_contrast_count(chart)


func _low_contrast_count(target: Chart) -> int:
	if target == null:
		return 0
	var count := 0
	for note in target.notes:
		if not note.supports_custom_color():
			continue
		var picked := Color(0, 0, 0, 0)
		if note.has_custom_color:
			picked = note.custom_color
		elif note.color > 0:
			picked = target.palette_color(note.color, note.type)
		if picked.a <= 0.0:
			continue
		if Note.contrast_ratio(picked, STAGE_BACKGROUND) < Note.MIN_CONTRAST:
			count += 1
	return count
