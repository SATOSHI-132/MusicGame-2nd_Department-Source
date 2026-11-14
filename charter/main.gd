extends Control

const TOOL_ORDER := [
	["select", "选择 V"],
	["boundary", "边界 B"],
	["event", "事件 E"],
]

var _app: Node = null
var _preview: Preview3D
var _preview_box: VBoxContainer
var _main_row: Control
var _ring_workspace: Control
var _view_menu: MenuButton
var _preview_panel: PanelContainer
var _preview_grip: Control
var _preview_reopen: Button
var _preview_gear: MenuButton
var _preview_dragging: bool = false
var _preview_drag_start_x: float = 0.0
var _preview_drag_width: float = 340.0
var _preview_manual_open: bool = false
var _audio_popup: PopupPanel = null
var _settings_dialog: AcceptDialog = null
var _quality_widgets: Dictionary = {}
var _hud_widgets: Dictionary = {}

## 画质菜单：每项一行子菜单，行标题带当前值，子项打勾。只影响渲染，不碰判定。
const QUALITY_OPTIONS := [
	{"key": "preset", "label": "预设", "choices": [["极高（4× 抗锯齿）", 80], ["高（2× 抗锯齿）", 81], ["中", 82], ["低", 83]]},
	{"key": "frame_cap", "label": "帧率上限", "choices": [["60", 90], ["120", 91], ["144", 92], ["240", 93], ["垂直同步", 94], ["不限", 95]]},
	{"key": "aa_2d_level", "label": "2D 抗锯齿", "choices": [["关", 60], ["MSAA 2×", 61], ["MSAA 4×", 62], ["MSAA 8×", 84]]},
	{"key": "msaa_3d_level", "label": "3D 抗锯齿", "choices": [["关", 150], ["MSAA 2×", 151], ["MSAA 4×", 152], ["MSAA 8×", 153], ["FXAA（便宜）", 154], ["TAA（平滑，可能拖影）", 155], ["MSAA 2× + FXAA", 156], ["MSAA 4× + FXAA", 157]]},
	{"key": "use_3d_ring", "label": "3D 环", "choices": [["开", 158], ["关", 159]]},
	{"key": "note_detail_fine", "label": "音符精细度", "choices": [["全画质", 63], ["省电", 64]]},
	{"key": "note_glow", "label": "音符光晕", "choices": [["开", 65], ["关", 66]]},
	{"key": "cursor_trail", "label": "光标拖尾", "choices": [["长", 67], ["短", 68], ["关", 69]]},
	{"key": "fx_budget", "label": "命中特效", "choices": [["完整", 70], ["精简", 71], ["关", 72]]},
	{"key": "ring_3d_scale", "label": "3D 环分辨率", "choices": [["原生", 160], ["超采样 1.25×", 161], ["超采样 1.5×", 162], ["高 0.85", 163], ["中 0.65", 164], ["低 0.5", 165]]},
	{"key": "ring_3d_hz", "label": "3D 环刷新", "choices": [["60Hz", 76], ["30Hz", 77]]},
	{"key": "bar_lines", "label": "小节线", "choices": [["开", 78], ["关", 79]]},
	{"key": "background_brightness", "label": "背景明暗", "choices": [["关", 96], ["25%", 97], ["50%", 98], ["75%", 99], ["100%（默认）", 100]]},
]

## 界面（HUD）选项：和 视图 → 画质 同样的菜单结构，只影响显示。
const HUD_OPTIONS := [
	{"key": "hud_scale", "label": "HUD 缩放", "choices": [["80%", 120], ["100%", 121], ["120%", 122]]},
	{"key": "hud_combo_mode", "label": "连击", "choices": [["屏幕中心", 123], ["右侧", 124], ["关", 125]]},
	{"key": "hud_progress_style", "label": "进度仪表", "choices": [["环外弧", 126], ["关", 127]]},
	{"key": "hud_judge_position", "label": "判定字位置", "choices": [["跟音符", 128], ["环内", 129], ["环外", 130], ["屏幕中心", 146], ["关", 147]]},
	{"key": "hud_opacity", "label": "HUD 透明度", "choices": [["100%", 133], ["85%", 134], ["70%", 135]]},
	{"key": "hud_show_title", "label": "左上：曲名", "choices": [["显示", 136], ["隐藏", 137]]},
	{"key": "hud_show_difficulty", "label": "左上：难度", "choices": [["显示", 138], ["隐藏", 139]]},
	{"key": "hud_show_percent", "label": "左上：进度%", "choices": [["显示", 140], ["隐藏", 141]]},
	{"key": "hud_show_time", "label": "左上：用时", "choices": [["显示", 142], ["隐藏", 143]]},
	{"key": "hud_show_watermark", "label": "左上：试玩水印", "choices": [["显示", 144], ["隐藏", 145]]},
]
var _canvas: ChartCanvas
var _event_track: EventTrack
var _inspector: Inspector
var _palette: NotePalette
var _validation_label: Label
var _play_button: Button
var _time_label: Label
var _progress: SeekBar
var _beat_label: Label
var _bpm_label: Label
var _save_label: Label
var _status_u: Label
var _status_beat: Label
var _status_snap: Label
var _status_sel: Label
var _status_shape: Label
var _status_error: Label
var _toast_label: Label
var _toast_timer: Timer
var _last_transport_msec: int = 0

var _tool_buttons: Dictionary = {}
var _tool_group: ButtonGroup
var _beat_subdiv_edit: LineEdit
var _beat_subdiv_error: Label
var _vertical_lines_edit: LineEdit
var _vertical_lines_error: Label
var _stretch_edit: LineEdit
var _stretch_slider: HSlider
var _stretch_error: Label
var _stretch_syncing: bool = false
var _audio: AudioStreamPlayer
var _audio_path: String = ""
var _audio_token: int = 0
## 当前 _audio.stream 的时间伸缩倍率（1 = 原始；>1 = 已经 atempo 过）。
var _audio_stream_rate: float = 1.0
## 当前流是按哪个倍速准备的；倍速变了要重新加载。
var _audio_rate_key: float = 1.0
var _audio_loading := false
var _playing: bool = false
var _loop_enabled: bool = false
var _loop_start: float = 0.0
var _loop_end: float = 0.0
var _rate: float = 1.0
var _loop: bool = false
var _metronome: bool = true
var _sfx: HitSfx
var _sfx_enabled: bool = true
var _sfx_events: Array[Dictionary] = []
var _sfx_event_index: int = 0
var _sfx_last_beat: float = -INF
var _play_start_usec: int = 0
var _play_start_chart_ms: float = 0.0
var _last_beat_int: int = -1

var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _import_dialog: FileDialog
var _import_diff: OptionButton = null
var _import_diff_label: Label = null
var _tabs: TabBar = null
var _tab_close_index: int = -1
var _tab_close_dialog: ConfirmationDialog = null
var _syncing_tabs: bool = false
var _snap_option: OptionButton
var _lbp_dialog: FileDialog
var _report_dialog: AcceptDialog
var _difficulty_dialog: ConfirmationDialog
var _difficulty_list: ItemList
var _pending_osz: String = ""
var _pending_kind: String = "osu"
var _import_dir_dialog: FileDialog
var _audio_dialog: FileDialog
var _song_dialog: SongImportDialog
var _chart_browser: ChartBrowser
## 独立的“在线 osu! 谱面”窗口（卡片式，只列 osu!std）。
var _osu_browser: OsuBrowser
## 设置里「转码缓存」体积显示。
var _cache_label: Label = null
var _import_progress: AcceptDialog = null
var _import_progress_label: Label = null
var _import_progress_bar: ProgressBar = null
var _new_dialog: NewChartDialog
var _playtest: Playtest
## 导出视频的子进程：放完自动退出。
## 试玩前的设置窗口：倍速 / 流速 / 星速 / 星显。
var _playtest_dialog: AcceptDialog = null
var _playtest_rate: SpinBox = null
var _playtest_flow: SpinBox = null
var _playtest_star: SpinBox = null
var _playtest_cursor: SpinBox = null
var _playtest_offset: SpinBox = null
var _playtest_latency: SpinBox = null
var _playtest_sfx: OptionButton = null
var _playtest_dynamic: CheckBox = null
var _playtest_auto: CheckBox = null
var _playtest_mouse: CheckBox = null
var _playtest_bias: Label = null
## 试玩设置底部的「从头开始玩」按钮（试玩中隐藏）。
var _playtest_start_button: Button = null
var _calibration_dialog: CalibrationDialog = null
## 校准窗口关掉后要回到哪里："" / "settings" / "playtest"。
var _calibration_return := ""
var _playtest_from_start: bool = false
## 制谱界面保留的流速输入框（试玩设置改流速后要同步回来）。
var _editor_flow_spin: SpinBox = null
## 制谱界面保留的「星显」输入框，和试玩设置共用同一个值。
var _cursor_u: float = 0.0
var _issues: Array = []
## 所有音量滑条（编辑器音频弹窗 + 设置 + 试玩设置），打开面板时统一同步。
var _volume_sliders: Array = []


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_audio_buses()
	_build_ui()
	resized.connect(_on_editor_resized)
	get_window().size_changed.connect(_on_editor_resized)
	call_deferred("_on_editor_resized")
	_build_audio()
	_sfx = HitSfx.new()
	_sfx.name = "EditorHitSfx"
	add_child(_sfx)
	_sfx.set_style(String(_app.hit_sfx_style) if _app != null else "default")
	_build_dialogs()
	_build_audio_popup()
	if _app != null:
		_app.chart_changed.connect(_on_chart_changed)
		_app.chart_live_changed.connect(_on_chart_live_changed)
		_app.playhead_changed.connect(_on_playhead_changed)
		_app.seek_requested.connect(_on_seek_requested)
		_app.selection_changed.connect(_update_status)
		_app.tool_changed.connect(_on_tool_changed)
		_app.status_changed.connect(_update_status)
		_app.save_state_changed.connect(_update_status)
		_app.notice.connect(_show_toast)
		_app.appearance_changed.connect(_sync_appearance)
		_app.preview_sfx.connect(func() -> void:
			if _sfx != null:
				_sfx.play("don")
		)
		_app.validation_changed.connect(_update_validation)
		# App 在 main 之后才连上信号，启动时那次校验已经错过，这里补一次。
		_update_validation(_app.validation_issues())
		_app.snap_changed.connect(_on_snap_changed)
		_app.stretch_changed.connect(_on_stretch_value_changed)
		_app.audio_import_requested.connect(_on_audio_import_requested)
		_app.audio_detect_requested.connect(_on_audio_detect_requested)
		_app.import_set_changed.connect(_refresh_import_difficulty)
		_app.tabs_changed.connect(_refresh_tabs)
		_app.chart_changed.emit()
	_sync_from_app()
	if _app != null:
		_app.ensure_tab()
		_refresh_tabs()
	for intro_control in [_canvas, _inspector, _palette, _preview]:
		intro_control.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(intro_control, "modulate:a", 1.0, 0.45).set_delay(0.05)
	set_process(true)
	if "--bench" in OS.get_cmdline_user_args():
		call_deferred("_run_bench")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--replay="):
			call_deferred("_open_replay_file", arg.get_slice("=", 1))


## 无人值守性能基准：载入 Apollo 谱，从扫圈段自动打 25 秒后退出。
## --bench-osz=路径 可改用导入的 .osz 复现问题，--bench-from=拍 指定起始拍。
func _run_bench() -> void:
	var start_beat := 0.0 if "--bench-start0" in OS.get_cmdline_user_args() else 312.0
	var osz := ""
	var plain := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-osz="):
			osz = arg.get_slice("=", 1)
		elif arg.begins_with("--bench-chart="):
			plain = arg.get_slice("=", 1)
		elif arg.begins_with("--bench-from="):
			start_beat = float(arg.get_slice("=", 1))
	if not plain.is_empty():
		var plain_chart: Chart = ChartIO.load_chart(plain)
		if plain_chart == null:
			print("[bench] chart load failed: ", plain)
			get_tree().quit()
			return
		_app.set_chart(plain_chart, plain, false)
	elif osz.is_empty():
		var chart: Chart = ChartIO.load_chart("user://autosave.json")
		if chart != null:
			_app.set_chart(chart, "user://autosave.json", false)
	else:
		var imported := OsuIO.import_osz(osz, 0)
		if imported.is_empty():
			print("[bench] osz import failed: ", OsuIO.last_error)
			get_tree().quit()
			return
		_app.set_chart(imported["chart"], "", false)
	_app.playhead_beat = start_beat
	_start_playtest(false)
	if _playtest == null:
		print("[bench] playtest failed to start")
		get_tree().quit()
		return
	if "--bench-unlimited" in OS.get_cmdline_user_args():
		# 基准量的是真实开销，不被垂直同步的 120/240Hz 挡住。
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var first: Note = _playtest._ordered_notes[0]
	print("[bench] start playhead=%.1f playtest_beat=%.1f first_id=%d first_beat=%.1f" % [_app.playhead_beat, _playtest.start_beat, first.id, first.beat])
	if "--bench-shot" in OS.get_cmdline_user_args():
		# --bench-shot-at=秒 按墙钟截图；--bench-shot-beat=拍 等谱面播放到该拍再截（更准）。
		var shot_at := 3.0
		var shot_beat := NAN
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--bench-shot-at="):
				shot_at = float(arg.get_slice("=", 1))
			elif arg.begins_with("--bench-shot-beat="):
				shot_beat = float(arg.get_slice("=", 1))
		if is_nan(shot_beat):
			await get_tree().create_timer(shot_at).timeout
		else:
			var target_ms := _playtest.chart.beat_to_ms(shot_beat)
			while is_instance_valid(_playtest) and _playtest._chart_ms() < target_ms:
				await get_tree().process_frame
			print("[bench] shot beat=%.2f" % _playtest._chart_ms())
		var shot := get_viewport().get_texture().get_image()
		if shot != null:
			shot.save_png("/tmp/bench_shot.png")
			print("[bench] screenshot saved")
		await get_tree().create_timer(17.0).timeout
	else:
		await get_tree().create_timer(95.0 if "--bench-start0" in OS.get_cmdline_user_args() else 20.0).timeout
	print("[bench] stop")
	get_tree().quit()


## 预览齿轮：HUD / 调试 / 收起。
func _on_preview_menu(id: int) -> void:
	if _app == null or _preview == null:
		return
	match id:
		0:
			_app.hud_visible = not _app.hud_visible
			_preview.show_hud = _app.hud_visible
		1:
			_app.debug_overlay = not _app.debug_overlay
			_preview.show_debug = _app.debug_overlay
		2:
			_set_preview_collapsed(true, true)
			return
	_update_status()


func _set_preview_collapsed(value: bool, manual: bool) -> void:
	if _app == null or _preview_panel == null:
		return
	if manual:
		_preview_manual_open = not value
	var changed: bool = value != _app.preview_collapsed
	_app.preview_collapsed = value
	_preview_panel.visible = not value
	_preview_grip.visible = not value
	_preview_reopen.visible = value
	if _preview != null:
		_preview.set_suspended(value)
	if changed:
		_app.save_settings()


func _on_preview_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_preview_dragging = true
			_preview_drag_start_x = event.global_position.x
			_preview_drag_width = _preview_panel.custom_minimum_size.x
		else:
			_preview_dragging = false
			if _app != null:
				_app.preview_width = _preview_panel.custom_minimum_size.x
				_app.save_settings()
	elif event is InputEventMouseMotion and _preview_dragging:
		var dx: float = event.global_position.x - _preview_drag_start_x
		var width := clampf(_preview_drag_width - dx, 280.0, 720.0)
		_preview_panel.custom_minimum_size.x = width
		if _app != null:
			_app.preview_width = width


## 窄窗口自动收起预览；用户手动开/关过之后不再抢。
func _on_editor_resized() -> void:
	if _app == null or _preview_panel == null or _preview_manual_open:
		return
	# 拉伸模式下 Control 的虚拟宽度固定 1600，得看真实窗口宽度。
	var width := float(DisplayServer.window_get_size().x)
	if width < 1180.0 and not _app.preview_collapsed:
		_set_preview_collapsed(true, false)
	elif width >= 1180.0 and _app.preview_collapsed:
		_set_preview_collapsed(false, false)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var top := PanelContainer.new()
	top.name = "TopBar"
	top.custom_minimum_size = Vector2(0, 116)
	root.add_child(top)
	var top_box := VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 2)
	top.add_child(top_box)

	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 12)
	top_box.add_child(brand_row)
	_tabs = TabBar.new()
	_tabs.name = "Tabs"
	_tabs.clip_tabs = false
	_tabs.custom_minimum_size = Vector2(0, 30)
	_tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	_tabs.tab_changed.connect(_on_tab_changed)
	_tabs.tab_close_pressed.connect(_on_tab_close)
	top_box.add_child(_tabs)
	var brand := Label.new()
	brand.text = "TAMAKI₃"
	brand.add_theme_font_override("font", UITheme.bold_font())
	brand.add_theme_font_size_override("font_size", 20)
	brand.add_theme_color_override("font_color", UITheme.INK)
	brand_row.add_child(brand)
	var subtitle := Label.new()
	subtitle.text = "制谱器 / CHART EDITOR"
	subtitle.add_theme_font_override("font", UITheme.mono_font())
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", UITheme.MUTED)
	brand_row.add_child(subtitle)
	# 转谱窗口：难度选择器放在左边，窗口窄的时候也不会被右侧菜单挤掉。
	_import_diff_label = Label.new()
	_import_diff_label.text = "难度"
	UITheme.style_mono(_import_diff_label, 11, UITheme.MUTED)
	_import_diff_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_import_diff_label.visible = false
	brand_row.add_child(_import_diff_label)
	_import_diff = OptionButton.new()
	_import_diff.custom_minimum_size = Vector2(280, 26)
	_import_diff.add_theme_font_size_override("font_size", 12)
	_import_diff.tooltip_text = "转谱窗口：切换要编辑/试玩的难度"
	_import_diff.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_import_diff.visible = false
	_import_diff.item_selected.connect(_on_import_difficulty_selected)
	brand_row.add_child(_import_diff)
	# 菜单和试玩按钮统一排到右上角：这里先放一个弹性占位，把它们顶过去。
	var brand_spacer := Control.new()
	brand_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_row.add_child(brand_spacer)
	# 菜单 id 全局唯一（_on_menu 的 match 先匹配先得，重复 id 会让后面的分支永远收不到）：
	# 文件 0–9 / 15–19、编辑 10–14、视图 20–25、插入 30–38、事件 40–41、试玩 50–51。
	brand_row.add_child(_menu("文件", [
		["新建", 0], ["打开", 1], ["保存", 2], ["另存为", 3], ["-", 0],
		["导入", [["歌曲 / 识别 BPM…", 9], ["导入视频…", 19], ["谱面 (.osz/.zip/.txt)", 6], ["舞萌文件夹", 8], ["在线舞萌谱面…", 15], ["在线 osu! 谱面…", 18]]],
		["导出", [["导出 .lbp", 7]]],
		["-", 0], ["恢复自动保存", 4], ["-", 0], ["退出", 5],
	]))
	brand_row.add_child(_menu("编辑", [
		["撤销", 10], ["重做", 11], ["-", 0], ["删除", 12], ["取消选择", 13], ["全选可见", 14],
		["-", 0], ["设置…", 26],
	]))
	_view_menu = _menu("视图", [
		["显示/隐藏 HUD", 20], ["调试叠层", 21], ["波形", 22], ["从上往下写入", 25], ["-", 0],
		["环编辑…", 39], ["时间 / BPM (F6)", 24],
	])
	brand_row.add_child(_view_menu)
	brand_row.add_child(_menu("插入", [
		["Tap", 30], ["Hold", 31], ["Path", 32], ["Seek", 33], ["Anchor", 34], ["Bell", 35], ["Limit", 36],
	]))
	# 试玩只保留一个黄色按钮；F5 / Shift+F5 快捷键照旧生效。
	var playtest_button := Button.new()
	playtest_button.text = "试玩 F5"
	playtest_button.add_theme_color_override("font_color", UITheme.BG)
	playtest_button.add_theme_color_override("font_hover_color", UITheme.BG)
	playtest_button.add_theme_color_override("font_pressed_color", UITheme.BG)
	playtest_button.add_theme_stylebox_override("normal", UITheme._box(UITheme.ACCENT, UITheme.ACCENT, 3, 12, 5))
	playtest_button.add_theme_stylebox_override("hover", UITheme._box(UITheme.ACCENT, Color.WHITE, 3, 12, 5))
	playtest_button.add_theme_stylebox_override("pressed", UITheme._box(UITheme.ACCENT_DARK, UITheme.ACCENT_DARK, 3, 12, 5))
	playtest_button.tooltip_text = "打开试玩设置：可选「继续游玩」（从播放头）或「从头开始玩」；F5 从播放头，Shift+F5 从头"
	playtest_button.pressed.connect(func() -> void: _open_playtest_setup(false))
	brand_row.add_child(playtest_button)

	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 4)
	# 1024 窗口下工具行会超出；给一条横向滚动，而不是把字段挤没。
	var tool_scroll := ScrollContainer.new()
	tool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tool_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tool_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_box.add_child(tool_scroll)
	tool_scroll.add_child(tool_row)
	_tool_group = ButtonGroup.new()
	for spec in TOOL_ORDER:
		var button := Button.new()
		button.text = spec[1]
		button.toggle_mode = true
		button.button_group = _tool_group
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_set_tool.bind(spec[0]))
		tool_row.add_child(button)
		_tool_buttons[spec[0]] = button

	var beat_divider := VSeparator.new()
	tool_row.add_child(beat_divider)
	var grid_label := Label.new()
	grid_label.text = "网格"
	grid_label.add_theme_font_size_override("font_size", 10)
	grid_label.add_theme_color_override("font_color", UITheme.MUTED)
	grid_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tool_row.add_child(grid_label)
	var beat_div_label := Label.new()
	beat_div_label.text = "小节线："
	beat_div_label.add_theme_font_size_override("font_size", 11)
	beat_div_label.add_theme_color_override("font_color", UITheme.MUTED)
	beat_div_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tool_row.add_child(beat_div_label)
	_beat_subdiv_edit = LineEdit.new()
	_beat_subdiv_edit.text = str(_app.beat_subdivisions if _app != null else 4)
	_beat_subdiv_edit.custom_minimum_size = Vector2(48, 26)
	_beat_subdiv_edit.max_length = 3
	_beat_subdiv_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_beat_subdiv_edit.select_all_on_focus = true
	_beat_subdiv_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_beat_subdiv_edit.tooltip_text = "每拍等分为 N 份（输入 4 → 3 条细小节线）；仅接受 1–%d 的整数" % TimingMap.MAX_BEAT_SUBDIVISIONS
	_beat_subdiv_edit.text_changed.connect(_on_beat_subdivision_changed)
	_beat_subdiv_edit.text_submitted.connect(_on_beat_subdivision_submitted)
	_beat_subdiv_edit.focus_exited.connect(_on_beat_subdivision_focus_exited)
	tool_row.add_child(_beat_subdiv_edit)
	_beat_subdiv_error = Label.new()
	_beat_subdiv_error.text = ""
	_beat_subdiv_error.visible = false
	_beat_subdiv_error.add_theme_font_size_override("font_size", 10)
	_beat_subdiv_error.add_theme_color_override("font_color", UITheme.RED)
	_beat_subdiv_error.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tool_row.add_child(_beat_subdiv_error)

	var vertical_divider := VSeparator.new()
	tool_row.add_child(vertical_divider)
	var vertical_label := Label.new()
	vertical_label.text = "竖线"
	vertical_label.add_theme_font_size_override("font_size", 11)
	vertical_label.add_theme_color_override("font_color", UITheme.MUTED)
	vertical_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tool_row.add_child(vertical_label)
	_vertical_lines_edit = LineEdit.new()
	_vertical_lines_edit.text = str(_app.vertical_lines if _app != null else 11)
	_vertical_lines_edit.custom_minimum_size = Vector2(48, 26)
	_vertical_lines_edit.max_length = 3
	_vertical_lines_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vertical_lines_edit.select_all_on_focus = true
	_vertical_lines_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vertical_lines_edit.tooltip_text = "竖线数量（1–%d），等距分布在编辑区；放置音符靠近时自动吸附" % TimingMap.MAX_VERTICAL_LINES
	_vertical_lines_edit.text_changed.connect(_on_vertical_lines_changed)
	_vertical_lines_edit.text_submitted.connect(_on_vertical_lines_submitted)
	_vertical_lines_edit.focus_exited.connect(_on_vertical_lines_focus_exited)
	tool_row.add_child(_vertical_lines_edit)
	_vertical_lines_error = Label.new()
	_vertical_lines_error.text = ""
	_vertical_lines_error.visible = false
	_vertical_lines_error.add_theme_font_size_override("font_size", 10)
	_vertical_lines_error.add_theme_color_override("font_color", UITheme.RED)
	_vertical_lines_error.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tool_row.add_child(_vertical_lines_error)

	var stretch_divider := VSeparator.new()
	tool_row.add_child(stretch_divider)
	var layout_label := Label.new()
	layout_label.text = "布局"
	layout_label.add_theme_font_size_override("font_size", 10)
	layout_label.add_theme_color_override("font_color", UITheme.MUTED)
	layout_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tool_row.add_child(layout_label)
	var stretch_label := Label.new()
	stretch_label.text = "纵向拉伸"
	stretch_label.add_theme_font_size_override("font_size", 11)
	stretch_label.add_theme_color_override("font_color", UITheme.MUTED)
	stretch_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tool_row.add_child(stretch_label)
	_stretch_edit = LineEdit.new()
	_stretch_edit.text = _format_stretch(_app.vertical_stretch if _app != null else 0.0)
	_stretch_edit.custom_minimum_size = Vector2(52, 26)
	_stretch_edit.max_length = 5
	_stretch_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stretch_edit.select_all_on_focus = true
	_stretch_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stretch_edit.tooltip_text = "0–10；每 +1 让每 bar 的距离变为原来的 1.5 倍，音符大小不变"
	_stretch_edit.text_changed.connect(_on_stretch_changed)
	_stretch_edit.text_submitted.connect(_on_stretch_submitted)
	_stretch_edit.focus_exited.connect(_on_stretch_focus_exited)
	tool_row.add_child(_stretch_edit)
	_stretch_slider = HSlider.new()
	_stretch_slider.min_value = 0.0
	_stretch_slider.max_value = 10.0
	_stretch_slider.step = 0.1
	_stretch_slider.value = _app.vertical_stretch if _app != null else 0.0
	_stretch_slider.custom_minimum_size = Vector2(96, 18)
	_stretch_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stretch_slider.tooltip_text = "拖动调节纵向拉伸"
	_stretch_slider.value_changed.connect(_on_stretch_slider_changed)
	tool_row.add_child(_stretch_slider)
	_stretch_error = Label.new()
	_stretch_error.text = ""
	_stretch_error.visible = false
	_stretch_error.add_theme_font_size_override("font_size", 10)
	_stretch_error.add_theme_color_override("font_color", UITheme.RED)
	_stretch_error.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tool_row.add_child(_stretch_error)

	var tool_spacer := Control.new()
	tool_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_row.add_child(tool_spacer)
	var snap_text := Label.new()
	snap_text.text = "SNAP"
	snap_text.add_theme_font_override("font", UITheme.mono_font())
	snap_text.add_theme_font_size_override("font_size", 9)
	snap_text.add_theme_color_override("font_color", UITheme.MUTED)
	snap_text.visible = false
	tool_row.add_child(snap_text)
	var snap_option := OptionButton.new()
	for item in GridDivisions.LABELS:
		snap_option.add_item(item)
	var initial_division: int = _app.snap_division if _app != null else GridDivisions.DEFAULT_DIVISION
	snap_option.selected = GridDivisions.index_of(initial_division)
	snap_option.item_selected.connect(func(index: int) -> void:
		if _app != null:
			_app.set_snap_division(GridDivisions.ITEMS[index])
		_update_status()
	)
	snap_option.visible = false
	tool_row.add_child(snap_option)
	_snap_option = snap_option

	var main_row := HBoxContainer.new()
	main_row.name = "MainRow"
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 0)
	root.add_child(main_row)

	_preview_panel = PanelContainer.new()
	_preview_panel.custom_minimum_size = Vector2(clampf(float(_app.preview_width) if _app != null else 340.0, 280.0, 720.0), 0)
	_preview_panel.size_flags_horizontal = Control.SIZE_FILL
	_preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_child(_preview_panel)
	var preview_box := VBoxContainer.new()
	_preview_box = preview_box
	preview_box.add_theme_constant_override("separation", 6)
	_preview_panel.add_child(preview_box)
	var preview_header := HBoxContainer.new()
	preview_box.add_child(preview_header)
	var preview_title := Label.new()
	preview_title.text = "预览"
	UITheme.style_section(preview_title)
	preview_header.add_child(preview_title)
	var preview_tag := Label.new()
	preview_tag.text = "3D STAGE"
	preview_tag.add_theme_font_override("font", UITheme.mono_font())
	preview_tag.add_theme_font_size_override("font_size", 9)
	preview_tag.add_theme_color_override("font_color", UITheme.CYAN)
	preview_header.add_child(preview_tag)
	var preview_spacer := Control.new()
	preview_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_header.add_child(preview_spacer)
	# HUD / 调试 / 收起都收进齿轮，避免预览标题栏被按钮占满。
	_preview_gear = MenuButton.new()
	_preview_gear.text = "⋯"
	_preview_gear.flat = true
	_preview_gear.add_theme_font_size_override("font_size", 13)
	_preview_gear.tooltip_text = "预览选项"
	var gear_popup := _preview_gear.get_popup()
	gear_popup.add_check_item("HUD", 0)
	gear_popup.add_check_item("调试叠层", 1)
	gear_popup.add_separator()
	gear_popup.add_item("收起预览", 2)
	gear_popup.about_to_popup.connect(func() -> void:
		gear_popup.set_item_checked(0, bool(_app.hud_visible) if _app != null else true)
		gear_popup.set_item_checked(1, bool(_app.debug_overlay) if _app != null else false)
	)
	gear_popup.id_pressed.connect(_on_preview_menu)
	preview_header.add_child(_preview_gear)
	_preview = Preview3D.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.cursor_changed.connect(_on_cursor_changed)
	_preview.notice.connect(_show_toast)
	preview_box.add_child(_preview)

	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(520, 0)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 47.0
	center.add_theme_constant_override("separation", 0)
	main_row.add_child(center)
	_event_track = EventTrack.new()
	_event_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(_event_track)
	_canvas = ChartCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.hover_changed.connect(_on_hover_changed)
	_canvas.notice.connect(_show_toast)
	center.add_child(_canvas)
	_event_track.canvas = _canvas

	var inspector_wrap := VBoxContainer.new()
	inspector_wrap.custom_minimum_size = Vector2(310, 0)
	inspector_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_wrap.size_flags_stretch_ratio = 24.0
	inspector_wrap.add_theme_constant_override("separation", 4)
	main_row.add_child(inspector_wrap)
	_preview_grip = Control.new()
	_preview_grip.name = "PreviewGrip"
	_preview_grip.custom_minimum_size = Vector2(6, 0)
	_preview_grip.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	_preview_grip.tooltip_text = "拖动调整预览宽度"
	_preview_grip.gui_input.connect(_on_preview_grip_input)
	main_row.add_child(_preview_grip)
	_preview_reopen = Button.new()
	_preview_reopen.name = "PreviewReopen"
	_preview_reopen.text = "预览"
	_preview_reopen.add_theme_font_size_override("font_size", 10)
	_preview_reopen.custom_minimum_size = Vector2(44, 0)
	_preview_reopen.visible = false
	_preview_reopen.pressed.connect(func() -> void: _set_preview_collapsed(false, true))
	main_row.add_child(_preview_reopen)
	_palette = NotePalette.new()
	_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_wrap.add_child(_palette)
	_validation_label = Label.new()
	_validation_label.add_theme_font_size_override("font_size", 11)
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.custom_minimum_size = Vector2(0, 30)
	inspector_wrap.add_child(_validation_label)
	_inspector = Inspector.new()
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_wrap.add_child(_inspector)
	main_row.move_child(center, 0)
	main_row.move_child(inspector_wrap, 1)
	main_row.move_child(_preview_grip, 2)
	main_row.move_child(_preview_panel, 3)
	main_row.move_child(_preview_reopen, 4)
	_main_row = main_row
	_ring_workspace = preload("res://charter/ring_workspace.gd").new()
	add_child(_ring_workspace)
	_ring_workspace.closed.connect(func() -> void:
		_preview.set_process(true)
		_preview.queue_redraw()
	)
	_ring_workspace.play_toggled.connect(_toggle_play)
	_ring_workspace.loop_requested.connect(_set_loop)
	if _app != null and _app.preview_collapsed:
		_set_preview_collapsed(true, false)

	var transport := PanelContainer.new()
	transport.name = "Transport"
	transport.custom_minimum_size = Vector2(0, 52)
	transport.add_theme_stylebox_override("panel", UITheme._box(UITheme.PANEL, UITheme.BORDER, 0, 8, 6))
	root.add_child(transport)
	var transport_row := HBoxContainer.new()
	transport_row.add_theme_constant_override("separation", 10)
	transport.add_child(transport_row)
	_play_button = Button.new()
	_play_button.text = "▶"
	_play_button.custom_minimum_size = Vector2(42, 30)
	_play_button.pressed.connect(_toggle_play)
	transport_row.add_child(_play_button)
	var stop_button := Button.new()
	stop_button.text = "■"
	stop_button.custom_minimum_size = Vector2(38, 30)
	stop_button.tooltip_text = "停止并回到 0:00"
	stop_button.pressed.connect(_reset_playhead)
	transport_row.add_child(stop_button)
	_time_label = Label.new()
	UITheme.style_mono(_time_label, 12, UITheme.INK)
	_time_label.custom_minimum_size = Vector2(150, 0)
	transport_row.add_child(_time_label)
	_progress = SeekBar.new()
	_progress.seek_to.connect(_on_seek_fraction)
	transport_row.add_child(_progress)
	_beat_label = Label.new()
	UITheme.style_mono(_beat_label, 12, UITheme.GOLD)
	_beat_label.custom_minimum_size = Vector2(92, 0)
	transport_row.add_child(_beat_label)
	_bpm_label = Label.new()
	UITheme.style_mono(_bpm_label, 12, UITheme.MUTED)
	transport_row.add_child(_bpm_label)
	# 制谱界面单独保留「流速」，只影响编辑预览的预读速度；试玩里另有同名设置。
	var flow_label := Label.new()
	UITheme.style_mono(flow_label, 11, UITheme.MUTED)
	flow_label.text = "流速"
	transport_row.add_child(flow_label)
	var flow_spin := SpinBox.new()
	flow_spin.min_value = 0.05
	flow_spin.max_value = 3.0
	flow_spin.step = 0.01
	flow_spin.value = _app.flow_scale
	flow_spin.suffix = "×"
	flow_spin.custom_minimum_size = Vector2(92, 0)
	flow_spin.tooltip_text = "编辑预览的预读速度（0.05–3.0，步进 0.01）；试玩流速在「试玩设置」里单独设"
	flow_spin.focus_mode = Control.FOCUS_NONE
	flow_spin.get_line_edit().focus_mode = Control.FOCUS_NONE
	flow_spin.value_changed.connect(func(value: float) -> void:
		_app.flow_scale = clampf(value, 0.05, 3.0)
		_preview.flow_scale = _app.flow_scale
		_preview.request_redraw()
	)
	transport_row.add_child(flow_spin)
	_editor_flow_spin = flow_spin
	var loop_check := CheckBox.new()
	loop_check.text = "循环"
	loop_check.toggled.connect(func(pressed: bool) -> void: _loop = pressed)
	transport_row.add_child(loop_check)
	transport_row.add_child(VSeparator.new())
	# 节拍器 / 打击音 / 音量收进一个音频弹出，底部只留一个入口。
	var audio_button := Button.new()
	audio_button.text = "音频"
	audio_button.add_theme_font_size_override("font_size", 11)
	audio_button.tooltip_text = "节拍器、打击音、音乐/音效音量"
	audio_button.pressed.connect(func() -> void: _show_audio_popup(audio_button))
	transport_row.add_child(audio_button)
	var transport_spacer := Control.new()
	transport_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transport_row.add_child(transport_spacer)
	_save_label = Label.new()
	UITheme.style_mono(_save_label, 11, UITheme.MUTED)
	transport_row.add_child(_save_label)

	var status := PanelContainer.new()
	status.name = "StatusBar"
	status.custom_minimum_size = Vector2(0, 24)
	status.add_theme_stylebox_override("panel", UITheme._box(UITheme.PANEL, UITheme.BORDER, 0, 6, 2))
	root.add_child(status)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 14)
	status.add_child(status_row)
	_status_u = _status_label("u 0.0°")
	_status_beat = _status_label("bar 0:0:4")
	_status_snap = _status_label("吸附 1/4")
	_status_snap.visible = false
	_status_sel = _status_label("选中 0")
	_status_shape = _status_label("边界 S0")
	_status_error = _status_label("校验 —")
	for label in [_status_u, _status_beat, _status_snap, _status_sel, _status_shape, _status_error]:
		status_row.add_child(label)
	var status_spacer := Control.new()
	status_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(status_spacer)
	_toast_label = _status_label("")
	_toast_label.add_theme_color_override("font_color", UITheme.CYAN)
	status_row.add_child(_toast_label)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 3.0
	_toast_timer.timeout.connect(func() -> void: _toast_label.text = "")
	add_child(_toast_timer)



func _status_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.mono_font())
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UITheme.MUTED)
	return label


func _on_beat_subdivision_changed(text: String) -> void:
	var value := TimingMap.parse_beat_subdivision(text)
	if value > 0:
		_set_beat_subdivision_error(false)
		if _app != null and _app.beat_subdivisions != value:
			_app.beat_subdivisions = value
			if _canvas != null:
				_canvas.queue_redraw()
		return
	# Empty is a transient typing state; only submit/focus loss decides it.
	if text.strip_edges().is_empty():
		_set_beat_subdivision_error(false)
		return
	_set_beat_subdivision_error(true)


func _on_beat_subdivision_submitted(text: String) -> void:
	_commit_beat_subdivision(text)


func _on_beat_subdivision_focus_exited() -> void:
	if _beat_subdiv_edit != null:
		_commit_beat_subdivision(_beat_subdiv_edit.text)


func _commit_beat_subdivision(text: String) -> void:
	if _beat_subdiv_edit == null:
		return
	var value := TimingMap.parse_beat_subdivision(text)
	if value > 0:
		_beat_subdiv_edit.text = str(value)
		_set_beat_subdivision_error(false)
		if _app != null and _app.beat_subdivisions != value:
			_app.beat_subdivisions = value
			if _canvas != null:
				_canvas.queue_redraw()
		return
	_set_beat_subdivision_error(true)
	_show_toast("小节线数据有误：请输入 1–%d 的整数。" % TimingMap.MAX_BEAT_SUBDIVISIONS, "error")


func _set_beat_subdivision_error(has_error: bool) -> void:
	if _beat_subdiv_error == null or _beat_subdiv_edit == null:
		return
	_beat_subdiv_error.text = "数据有误" if has_error else ""
	_beat_subdiv_error.visible = has_error
	if has_error:
		_beat_subdiv_edit.add_theme_color_override("font_color", UITheme.RED)
	else:
		_beat_subdiv_edit.remove_theme_color_override("font_color")


func _on_vertical_lines_changed(text: String) -> void:
	var value := TimingMap.parse_vertical_lines(text)
	if value > 0:
		_set_vertical_lines_error(false)
		if _app != null and _app.vertical_lines != value:
			_app.vertical_lines = value
			if _canvas != null:
				_canvas.queue_redraw()
		return
	if text.strip_edges().is_empty():
		_set_vertical_lines_error(false)
		return
	_set_vertical_lines_error(true)


func _on_vertical_lines_submitted(text: String) -> void:
	_commit_vertical_lines(text)


func _on_vertical_lines_focus_exited() -> void:
	if _vertical_lines_edit != null:
		_commit_vertical_lines(_vertical_lines_edit.text)


func _commit_vertical_lines(text: String) -> void:
	if _vertical_lines_edit == null:
		return
	var value := TimingMap.parse_vertical_lines(text)
	if value > 0:
		_vertical_lines_edit.text = str(value)
		_set_vertical_lines_error(false)
		if _app != null and _app.vertical_lines != value:
			_app.vertical_lines = value
			if _canvas != null:
				_canvas.queue_redraw()
		return
	_set_vertical_lines_error(true)
	_show_toast("竖线数据有误：请输入 1–%d 的整数。" % TimingMap.MAX_VERTICAL_LINES, "error")


func _set_vertical_lines_error(has_error: bool) -> void:
	if _vertical_lines_error == null or _vertical_lines_edit == null:
		return
	_vertical_lines_error.text = "数据有误" if has_error else ""
	_vertical_lines_error.visible = has_error
	if has_error:
		_vertical_lines_edit.add_theme_color_override("font_color", UITheme.RED)
	else:
		_vertical_lines_edit.remove_theme_color_override("font_color")


func _parse_stretch(text: String) -> float:
	var clean := text.strip_edges().replace(",", ".")
	if clean.is_empty() or not clean.is_valid_float():
		return -1.0
	var value := float(clean)
	if not is_finite(value) or value < 0.0 or value > 10.0:
		return -1.0
	return value


func _format_stretch(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	var text := String.num(value, 2)
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	text = text.trim_suffix(".")
	return text


func _on_stretch_changed(text: String) -> void:
	if _stretch_syncing:
		return
	var value := _parse_stretch(text)
	if value >= 0.0:
		_set_stretch_error(false)
		_apply_stretch(value)
		return
	if text.strip_edges().is_empty():
		_set_stretch_error(false)
		return
	_set_stretch_error(true)


func _on_stretch_submitted(text: String) -> void:
	_commit_stretch(text)


func _on_stretch_focus_exited() -> void:
	if _stretch_edit != null:
		_commit_stretch(_stretch_edit.text)


func _commit_stretch(text: String) -> void:
	if _stretch_edit == null:
		return
	var value := _parse_stretch(text)
	if value < 0.0:
		_set_stretch_error(true)
		_show_toast("纵向拉伸数据有误：请输入 0–10 的数值。", "error")
		return
	_stretch_syncing = true
	_stretch_edit.text = _format_stretch(value)
	_stretch_syncing = false
	_set_stretch_error(false)
	_apply_stretch(value)


func _on_stretch_value_changed(value: float) -> void:
	_stretch_syncing = true
	if _stretch_edit != null:
		_stretch_edit.text = _format_stretch(value)
	if _stretch_slider != null:
		_stretch_slider.set_value_no_signal(value)
	_stretch_syncing = false
	_set_stretch_error(false)
	if _canvas != null:
		_canvas.queue_redraw()


func _on_stretch_slider_changed(value: float) -> void:
	_stretch_syncing = true
	if _stretch_edit != null:
		_stretch_edit.text = _format_stretch(value)
	_stretch_syncing = false
	_set_stretch_error(false)
	_apply_stretch(value)


func _apply_stretch(value: float) -> void:
	var stretched := clampf(value, 0.0, 10.0)
	if _stretch_slider != null:
		_stretch_slider.set_value_no_signal(stretched)
	if _app == null or is_equal_approx(_app.vertical_stretch, stretched):
		return
	_app.vertical_stretch = stretched
	if _canvas != null:
		_canvas.queue_redraw()
	if _event_track != null:
		_event_track.queue_redraw()
	_update_transport()


func _set_stretch_error(has_error: bool) -> void:
	if _stretch_error == null or _stretch_edit == null:
		return
	_stretch_error.text = "数据有误" if has_error else ""
	_stretch_error.visible = has_error
	if has_error:
		_stretch_edit.add_theme_color_override("font_color", UITheme.RED)
	else:
		_stretch_edit.remove_theme_color_override("font_color")


func _hud_index(key: String) -> int:
	match key:
		"hud_scale":
			return [80, 100, 120].find(_app.hud_scale)
		"hud_combo_mode":
			return ["center", "corner", "off"].find(_app.hud_combo_mode)
		"hud_progress_style":
			return ["ring", "off"].find(_app.hud_progress_style)
		"hud_judge_position":
			return ["note", "ring_in", "ring_out", "center", "off"].find(_app.hud_judge_position)
		"hud_opacity":
			return [100, 85, 70].find(_app.hud_opacity)
		"hud_show_title":
			return 0 if _app.hud_show_title else 1
		"hud_show_difficulty":
			return 0 if _app.hud_show_difficulty else 1
		"hud_show_percent":
			return 0 if _app.hud_show_percent else 1
		"hud_show_time":
			return 0 if _app.hud_show_time else 1
		"hud_show_watermark":
			return 0 if _app.hud_show_watermark else 1
	return -1


func _set_hud_index(key: String, index: int) -> void:
	match key:
		"hud_scale":
			_app.hud_scale = [80, 100, 120][clampi(index, 0, 2)]
		"hud_combo_mode":
			_app.hud_combo_mode = ["center", "corner", "off"][clampi(index, 0, 2)]
		"hud_progress_style":
			_app.hud_progress_style = ["ring", "off"][clampi(index, 0, 1)]
		"hud_judge_position":
			_app.hud_judge_position = ["note", "ring_in", "ring_out", "center", "off"][clampi(index, 0, 4)]
		"hud_opacity":
			_app.hud_opacity = [100, 85, 70][clampi(index, 0, 2)]
		"hud_show_title":
			_app.hud_show_title = index == 0
		"hud_show_difficulty":
			_app.hud_show_difficulty = index == 0
		"hud_show_percent":
			_app.hud_show_percent = index == 0
		"hud_show_time":
			_app.hud_show_time = index == 0
		"hud_show_watermark":
			_app.hud_show_watermark = index == 0


## 当前选项落在第几个子项（-1 = 自定义，不勾任何一项）。
func _quality_index(key: String) -> int:
	match key:
		"preset":
			return ["ultra", "high", "mid", "low"].find(_app.quality_preset)
		"frame_cap":
			return ["60", "120", "144", "240", "vsync", "unlimited"].find(_app.frame_cap)
		"aa_2d_level":
			return clampi(_app.aa_2d_level, 0, 3)
		"msaa_3d_level":
			return clampi(_app.msaa_3d_level, 0, 7)
		"use_3d_ring":
			return 0 if _app.use_3d_ring else 1
		"note_detail_fine":
			return 0 if _app.note_detail_fine else 1
		"note_glow":
			return 0 if _app.note_glow else 1
		"cursor_trail":
			return ["long", "short", "off"].find(_app.cursor_trail)
		"fx_budget":
			return ["full", "light", "off"].find(_app.fx_budget)
		"ring_3d_scale":
			return ["native", "ssaa12", "ssaa15", "high", "mid", "low"].find(_app.ring_3d_scale)
		"ring_3d_hz":
			return 0 if _app.ring_3d_hz >= 60 else 1
		"bar_lines":
			return 0 if _app.bar_lines else 1
		"background_brightness":
			return [0, 25, 50, 75, 100].find(_app.background_brightness)
	return -1


func _set_quality_index(key: String, index: int) -> void:
	if key == "preset":
		_app.apply_quality_preset(["ultra", "high", "mid", "low"][clampi(index, 0, 3)])
		return
	match key:
		"frame_cap":
			_app.frame_cap = ["60", "120", "144", "240", "vsync", "unlimited"][clampi(index, 0, 5)]
			_app.apply_frame_cap()
			return
		"aa_2d_level":
			_app.aa_2d_level = clampi(index, 0, 3)
		"msaa_3d_level":
			_app.msaa_3d_level = clampi(index, 0, 7)
		"use_3d_ring":
			_app.use_3d_ring = index == 0
		"note_detail_fine":
			_app.note_detail_fine = index == 0
		"note_glow":
			_app.note_glow = index == 0
		"cursor_trail":
			_app.cursor_trail = ["long", "short", "off"][clampi(index, 0, 2)]
		"fx_budget":
			_app.fx_budget = ["full", "light", "off"][clampi(index, 0, 2)]
		"ring_3d_scale":
			_app.ring_3d_scale = ["native", "ssaa12", "ssaa15", "high", "mid", "low"][clampi(index, 0, 5)]
		"ring_3d_hz":
			_app.ring_3d_hz = 60 if index == 0 else 30
		"bar_lines":
			_app.bar_lines = index == 0
		"background_brightness":
			_app.background_brightness = [0, 25, 50, 75, 100][clampi(index, 0, 4)]
			# 背景明暗不是画质参数，别把预设打成「自定义」。
			return
	_app.quality_preset = "custom"


## 把画质设置推给预览与视口。
func _apply_visual_options() -> void:
	if _app == null:
		return
	_app.apply_visual_quality()
	if _preview == null:
		return
	_preview.use_3d_ring = _app.use_3d_ring
	_preview.note_detail_fine = _app.note_detail_fine
	_preview.note_glow = _app.note_glow
	_preview.cursor_trail_mode = _app.cursor_trail
	_preview.fx_budget = _app.fx_budget
	_preview.ring_3d_scale = _app.ring_3d_scale
	_preview.msaa_3d_level = _app.msaa_3d_level
	_preview.ring_3d_hz = _app.ring_3d_hz
	_preview.bar_lines_visible = _app.bar_lines
	_preview.set_background_brightness(float(_app.background_brightness) / 100.0)
	_preview.hud_options = _app.hud_options()
	_preview.apply_ring_quality()
	_preview.request_redraw()
	# 试玩里有自己的 Preview3D：局内改画质要同时推给它。
	if _playtest != null and _playtest._preview != null:
		var inner: Preview3D = _playtest._preview
		inner.note_detail_fine = _app.note_detail_fine
		inner.note_glow = _app.note_glow
		inner.cursor_trail_mode = _app.cursor_trail
		inner.fx_budget = _app.fx_budget
		inner.ring_3d_scale = _app.ring_3d_scale
		inner.ring_3d_hz = _app.ring_3d_hz
		inner.bar_lines_visible = _app.bar_lines
		inner.set_background_brightness(float(_app.background_brightness) / 100.0)
		inner.hud_options = _app.hud_options()
		inner.apply_ring_quality()
		inner.request_redraw()


## 把当前画质填回菜单（行标题带数值，子项打勾）。
func _refresh_view_menu() -> void:
	if _app == null:
		return
	for key in _quality_widgets.keys():
		var index := _quality_index(String(key))
		for pick in (_quality_widgets[key] as Array):
			if pick is OptionButton:
				var option: OptionButton = pick
				if index < 0:
					option.select(maxi(0, option.item_count - 1))
				elif index < option.item_count:
					option.select(index)
	for key in _hud_widgets.keys():
		var hud_index := _hud_index(String(key))
		for pick in (_hud_widgets[key] as Array):
			if pick is OptionButton and hud_index >= 0:
				(pick as OptionButton).select(hud_index)


## 试玩设置里的画质行（和 视图 → 画质 同一份数据）。
func _build_quality_rows(parent: Control) -> void:
	var title := Label.new()
	title.text = "画质（只影响画面，不影响判定）"
	title.add_theme_font_size_override("font_size", 12)
	parent.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	for option in QUALITY_OPTIONS:
		var key := String(option["key"])
		var label := Label.new()
		label.text = String(option["label"])
		label.add_theme_font_size_override("font_size", 11)
		grid.add_child(label)
		var pick := OptionButton.new()
		pick.add_theme_font_size_override("font_size", 11)
		for choice in option["choices"]:
			pick.add_item(String(choice[0]))
		if key == "preset":
			pick.add_item("自定义")
		pick.item_selected.connect(func(index: int) -> void:
			if key == "preset" and index > 3:
				return
			_set_quality_index(key, index)
			_app.save_settings()
			_apply_visual_options()
			_refresh_view_menu()
		)
		grid.add_child(pick)
		var picks: Array = _quality_widgets.get(key, [])
		picks.append(pick)
		_quality_widgets[key] = picks


## 试玩设置里的界面行（和 视图 → 界面 同一份数据）。
func _build_hud_rows(parent: Control) -> void:
	var title := Label.new()
	title.text = "界面（只影响显示）"
	title.add_theme_font_size_override("font_size", 12)
	parent.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	for option in HUD_OPTIONS:
		var key := String(option["key"])
		var label := Label.new()
		label.text = String(option["label"])
		label.add_theme_font_size_override("font_size", 11)
		grid.add_child(label)
		var pick := OptionButton.new()
		pick.add_theme_font_size_override("font_size", 11)
		for choice in option["choices"]:
			pick.add_item(String(choice[0]))
		pick.item_selected.connect(func(index: int) -> void:
			_set_hud_index(key, index)
			_app.save_settings()
			_apply_visual_options()
			_refresh_view_menu()
		)
		grid.add_child(pick)
		var picks: Array = _hud_widgets.get(key, [])
		picks.append(pick)
		_hud_widgets[key] = picks


func _menu(title: String, items: Array) -> MenuButton:
	var menu := MenuButton.new()
	menu.text = title
	menu.add_theme_font_size_override("font_size", 12)
	var popup := menu.get_popup()
	for item in items:
		if item[0] == "-":
			popup.add_separator()
		elif item[1] is Array:
			_add_submenu(popup, String(item[0]), item[1])
		else:
			popup.add_item(item[0], int(item[1]))
	popup.id_pressed.connect(_on_menu)
	return menu


func _add_submenu(parent: PopupMenu, title: String, items: Array) -> void:
	var child := PopupMenu.new()
	child.name = "Sub_" + title
	parent.add_child(child)
	for item in items:
		if item[0] == "-":
			child.add_separator()
		else:
			child.add_item(item[0], int(item[1]))
	child.id_pressed.connect(_on_menu)
	parent.add_submenu_node_item(title, child)


func _setup_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	# 总线由这里创建，所以保存的音量也在这里恢复（App 先于主场景初始化）。
	if _app != null:
		_set_bus_volume("Music", _app.music_volume)
		_set_bus_volume("SFX", _app.sfx_volume)


func _set_bus_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var linear := clampf(value / 100.0, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, linear)))
	AudioServer.set_bus_mute(index, linear <= 0.001)


## 把总线当前音量反算回 0–100，滑条重新打开时不会跳回 100。
func _bus_volume_percent(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0 or AudioServer.is_bus_mute(index):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(index)) * 100.0, 0.0, 100.0)


func _store_volume(bus_name: String, value: float) -> void:
	if _app == null:
		return
	if bus_name == "Music":
		_app.music_volume = clampf(value, 0.0, 100.0)
	elif bus_name == "SFX":
		_app.sfx_volume = clampf(value, 0.0, 100.0)
	else:
		return
	_app.save_settings()


func _sync_volume_sliders() -> void:
	for entry in _volume_sliders:
		var slider: HSlider = entry.get("slider")
		if is_instance_valid(slider):
			slider.set_value_no_signal(_bus_volume_percent(String(entry.get("bus", ""))))


func _build_audio_popup() -> void:
	_audio_popup = PopupPanel.new()
	_audio_popup.name = "AudioPopup"
	add_child(_audio_popup)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_audio_popup.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(230, 0)
	margin.add_child(box)
	var metro := CheckBox.new()
	metro.text = "节拍器"
	metro.button_pressed = true
	metro.toggled.connect(func(pressed: bool) -> void: _metronome = pressed)
	box.add_child(metro)
	var sfx := CheckBox.new()
	sfx.text = "打击音"
	sfx.button_pressed = true
	sfx.toggled.connect(func(pressed: bool) -> void: _sfx_enabled = pressed)
	box.add_child(sfx)
	box.add_child(_volume_slider("音乐", "Music"))
	box.add_child(_volume_slider("音效", "SFX"))
	var more := Button.new()
	more.text = "更多音频设置…"
	more.add_theme_font_size_override("font_size", 11)
	more.pressed.connect(func() -> void:
		_audio_popup.hide()
		_open_settings()
	)
	box.add_child(more)


func _show_audio_popup(button: Button) -> void:
	if _audio_popup == null:
		return
	_sync_volume_sliders()
	var size := Vector2i(250, 190)
	var at := Vector2i(button.global_position.x, button.global_position.y - size.y - 6)
	_audio_popup.popup(Rect2i(at, size))


func _volume_slider(label_text: String, bus_name: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UITheme.MUTED)
	label.custom_minimum_size = Vector2(28, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = _bus_volume_percent(bus_name)
	slider.custom_minimum_size = Vector2(0, 16)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void:
		_set_bus_volume(bus_name, value)
		_store_volume(bus_name, value)
	)
	box.add_child(slider)
	_volume_sliders.append({"slider": slider, "bus": bus_name})
	return box


func _build_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "EditorAudio"
	_audio.bus = "Music"
	add_child(_audio)
	_audio.finished.connect(_on_audio_finished)


func _build_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.filters = PackedStringArray(["*.json ; Tamaki 谱面"])
	_open_dialog.title = "打开谱面"
	_open_dialog.file_selected.connect(func(path: String) -> void:
		_app.ensure_tab()
		if _app.load_chart(path):
			_app.add_tab_from_current()
			_sync_from_app()
			_refresh_tabs()
		else:
			_app.restore_active_tab()
	)
	add_child(_open_dialog)
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.filters = PackedStringArray(["*.json ; Tamaki 谱面"])
	_save_dialog.title = "另存为"
	_save_dialog.current_file = "chart.json"
	_save_dialog.file_selected.connect(func(path: String) -> void:
		if not path.to_lower().ends_with(".json"):
			path += ".json"
		_app.save_chart_as(path)
		_sync_from_app()
	)
	add_child(_save_dialog)
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.osz,*.zip,*.txt ; osu! / Simai 谱面"])
	_import_dialog.title = "导入 osu! / 舞萌 Simai"
	_import_dialog.file_selected.connect(_on_import_osz_selected)
	add_child(_import_dialog)
	_import_dir_dialog = FileDialog.new()
	_import_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_import_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dir_dialog.title = "选择解压后的舞萌谱面文件夹（含 maidata.txt）"
	_import_dir_dialog.dir_selected.connect(func(path: String) -> void:
		_on_import_osz_selected(path.path_join("maidata.txt"))
	)
	add_child(_import_dir_dialog)
	_audio_dialog = FileDialog.new()
	_audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_audio_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_audio_dialog.filters = PackedStringArray(["*.wav, *.mp3, *.ogg, *.flac, *.m4a, *.aac, *.opus ; 音频文件", "*.* ; 全部文件"])
	_audio_dialog.title = "导入歌曲（自动识别 BPM 与 offset）"
	_audio_dialog.file_selected.connect(func(path: String) -> void: _song_dialog.open_for(path))
	add_child(_audio_dialog)
	_song_dialog = SongImportDialog.new()
	_song_dialog.applied.connect(func() -> void:
		_sync_from_app()
		_show_toast("已写入识别结果；可在“时间”页继续微调 BPM / offset。", "info")
	)
	add_child(_song_dialog)
	_chart_browser = ChartBrowser.new()
	# 在线谱面：下载完的 maidata.txt 走和本地导入完全一样的流程
	# （转好所有难度 → 存套组 → 开新窗口），新窗口顶部可切难度。
	_chart_browser.source_ready.connect(func(source_path: String) -> void:
		_on_import_osz_selected(source_path)
	)
	_chart_browser.warning.connect(func(message: String) -> void:
		_show_toast(message, "warning")
	)
	add_child(_chart_browser)
	_osu_browser = OsuBrowser.new()
	_osu_browser.source_ready.connect(func(source_path: String) -> void:
		_on_import_osz_selected(source_path, _osu_browser.take_include_video())
	)
	add_child(_osu_browser)
	_lbp_dialog = FileDialog.new()
	_lbp_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_lbp_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_lbp_dialog.filters = PackedStringArray(["*.lbp ; Tamaki LBP v2"])
	_lbp_dialog.title = "导出 .lbp"
	_lbp_dialog.current_file = "chart.lbp"
	_lbp_dialog.file_selected.connect(func(path: String) -> void:
		if not path.to_lower().ends_with(".lbp"):
			path += ".lbp"
		_app.export_lbp(path)
	)
	add_child(_lbp_dialog)
	_report_dialog = AcceptDialog.new()
	_report_dialog.title = "导入报告"
	_report_dialog.dialog_autowrap = true
	add_child(_report_dialog)
	_difficulty_dialog = ConfirmationDialog.new()
	_difficulty_dialog.title = "选择导入难度"
	_difficulty_dialog.dialog_text = "谱面包含多个难度，请选择："
	_difficulty_dialog.ok_button_text = "导入"
	_difficulty_dialog.cancel_button_text = "取消"
	var diff_box := VBoxContainer.new()
	diff_box.add_theme_constant_override("separation", 6)
	_difficulty_list = ItemList.new()
	_difficulty_list.custom_minimum_size = Vector2(520, 240)
	diff_box.add_child(_difficulty_list)
	_difficulty_dialog.add_child(diff_box)
	_difficulty_dialog.confirmed.connect(func() -> void:
		var selected := _difficulty_list.get_selected_items()
		if selected.size() > 0 and not _pending_osz.is_empty():
			if _pending_kind == "simai":
				_import_maimai(_pending_osz, int(_difficulty_list.get_item_metadata(selected[0])))
			else:
				_import_osz(_pending_osz, selected[0])
	)
	add_child(_difficulty_dialog)
	_new_dialog = NewChartDialog.new()
	_new_dialog.created.connect(func(meta: Dictionary) -> void:
		_app.new_chart(meta)
		_new_dialog.hide()
		_sync_from_app()
	)
	add_child(_new_dialog)
	var charts_dir := ProjectSettings.globalize_path("user://charts")
	DirAccess.make_dir_recursive_absolute(charts_dir)


func _sync_appearance() -> void:
	if _app == null:
		return
	_preview.note_skin = _app.note_skin
	_apply_visual_options()
	_refresh_view_menu()
	_preview.hit_fx_style = _app.hit_fx_style
	_preview.cursor_scale = _app.cursor_scale
	_preview.refresh_style()
	if _sfx != null:
		_sfx.set_style(_app.hit_sfx_style)


func _sync_from_app() -> void:
	if _app == null or _app.chart == null:
		return
	_refresh_import_difficulty()
	_preview.show_hud = _app.hud_visible
	_preview.use_3d_ring = _app.use_3d_ring
	_preview.mouse_tilt = _app.mouse_tilt
	_preview.show_debug = _app.debug_overlay
	_preview.flow_scale = _app.flow_scale
	_preview.star_speed = _app.star_speed
	_preview.note_skin = _app.note_skin
	_preview.hit_fx_style = _app.hit_fx_style
	_preview.cursor_scale = _app.cursor_scale
	_sfx.set_style(_app.hit_sfx_style)
	_canvas.px_per_beat = _app.zoom_px_per_beat
	if _beat_subdiv_edit != null:
		_beat_subdiv_edit.text = str(_app.beat_subdivisions)
		_set_beat_subdivision_error(false)
	if _vertical_lines_edit != null:
		_vertical_lines_edit.text = str(_app.vertical_lines)
		_set_vertical_lines_error(false)
	if _stretch_edit != null:
		_stretch_syncing = true
		_stretch_edit.text = _format_stretch(_app.vertical_stretch)
		_stretch_syncing = false
		if _stretch_slider != null:
			_stretch_slider.set_value_no_signal(_app.vertical_stretch)
		_set_stretch_error(false)
	_ensure_audio()
	_sync_tools()
	_update_transport()
	_update_status()
	_update_validation(Validator.validate(_app.chart))


func _ensure_audio() -> void:
	if _app == null or _app.chart == null:
		return
	var path: String = _app.chart.audio_path
	if path == _audio_path and is_equal_approx(_rate, _audio_rate_key):
		if _audio_loading:
			# 同一份音频正在准备：等它完成，避免 _start_play 用空流开跑。
			while _audio_loading:
				await get_tree().process_frame
		return
	_audio_path = path
	_audio_rate_key = _rate
	_audio_token += 1
	var token := _audio_token
	_audio_loading = true
	_audio.stop()
	_playing = false
	var resolved := path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path() and not _app.chart_path.is_empty():
		resolved = ChartIO.resolve_path(_app.chart_path, path)
	var prepared := resolved
	if MediaIO.is_native_audio(resolved) or FileAccess.file_exists(MediaIO.audio_cache_path(resolved)):
		# 原生格式 / 已有缓存：立刻返回，不阻塞。
		prepared = MediaIO.prepare_audio(resolved)
	else:
		# FLAC / M4A 等要跑 ffmpeg：带进度异步转，编辑界面不冻结。
		_show_import_progress()
		prepared = await MediaIO.prepare_audio_async(resolved, get_tree(), func(ratio: float, seconds: float) -> void:
			_import_progress_text("转码音频：%s" % resolved.get_file(), ratio, seconds))
		_hide_import_progress()
		if token != _audio_token:
			return
	if prepared.is_empty():
		_audio.stream = null
		_audio_loading = false
		_show_toast("音频不可用：%s" % MediaIO.last_error, "warning")
		return
	var base := ChartIO.audio_stream_from_path(prepared)
	var stream := base
	var stream_rate := 1.0
	if absf(_rate - 1.0) >= 0.001:
		if not MediaIO.has_ffmpeg():
			_show_toast("变速不变调需要 ffmpeg（当前 PATH 找不到）；已回退变调", "warning")
		else:
			var cached := MediaIO.rate_audio_cache_path(prepared, _rate)
			var total_sec := base.get_length() / maxf(0.1, _rate) if base != null else 0.0
			var stretched := cached if FileAccess.file_exists(cached) else ""
			if stretched.is_empty():
				_show_import_progress()
				stretched = await MediaIO.prepare_audio_at_rate_async(prepared, _rate, get_tree(), func(_ratio: float, seconds: float) -> void:
					var ratio := clampf(seconds / total_sec, 0.0, 0.99) if total_sec > 0.0 else -1.0
					_import_progress_text("变速音频：%s（%.2f×）" % [resolved.get_file(), _rate], ratio, seconds))
				_hide_import_progress()
				if token != _audio_token:
					return
			if not stretched.is_empty():
				var fast := ChartIO.audio_stream_from_path(stretched)
				if fast != null:
					stream = fast
					stream_rate = _rate
			if stream_rate == 1.0:
				_show_toast("变速音频生成失败，已回退变调：%s" % MediaIO.last_error, "warning")
	_audio.stream = stream if stream is AudioStream else null
	_audio_stream_rate = stream_rate
	_audio.pitch_scale = _rate / maxf(0.01, _audio_stream_rate)
	_audio_loading = false
	print("[audio] editor ", prepared, " -> ", _audio.stream, " stream_rate=", _audio_stream_rate, " bus=", _audio.bus)
	if _audio.stream == null:
		_show_toast("音频不可用：预览使用系统时钟。", "warning")


func _sync_tools() -> void:
	for key in _tool_buttons.keys():
		_tool_buttons[key].button_pressed = (_app.tool == key)


func _on_chart_changed() -> void:
	_ensure_audio()
	_build_sfx_events()
	if _playing and _app != null:
		_sfx_event_index = _first_sfx_event(_app.playhead_beat)
		_sfx_last_beat = _app.playhead_beat - 0.001
	_update_transport()
	_update_status()


func _on_chart_live_changed() -> void:
	_update_transport()
	_update_status()


func _on_playhead_changed(_beat: float) -> void:
	_update_transport()


func _on_tool_changed(_tool: String) -> void:
	_sync_tools()
	_update_status()


func _on_cursor_changed(u: float, _valid: bool) -> void:
	_cursor_u = u
	_update_status()


func _on_hover_changed(_u: float, _beat: float) -> void:
	pass


func _open_ring_workspace() -> void:
	if _ring_workspace == null or _app == null or _app.chart == null:
		return
	_app.ring_editor_open = true
	# 工作区是全屏覆盖层；底下那套编辑界面先藏起来，否则每帧还要再画一遍。
	if _main_row != null:
		_main_row.visible = false
	_ring_workspace.open_workspace(_preview, func(preview: Preview3D) -> void:
		var parent := _preview_box
		if parent != null and preview.get_parent() != parent:
			if preview.get_parent() != null:
				preview.get_parent().remove_child(preview)
			parent.add_child(preview)
			preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
			parent.move_child(preview, parent.get_child_count() - 1)
		preview.ring_edit_mode = false
		_app.ring_editor_open = false
		if _main_row != null:
			_main_row.visible = true
		_app.chart_changed.emit()
	)


func _set_tool(tool: String) -> void:
	_app.set_tool(tool)
	_sync_tools()
	if tool == "boundary":
		_show_toast("边界模式：在预览中拖动控制点；双击分段拆分。", "info")
	elif tool == "seek":
		_show_toast("Seek：在画布点选时间放置，再用 W/S 选择朝里/朝外。", "info")
	elif tool == "limit":
		_show_toast("Limit：在画布按住横向拖角度、纵向拖时长（最多 4 拍）。", "info")


func _toggle_play() -> void:
	if _playing:
		_stop_play()
	else:
		_start_play(_app.playhead_beat)


func _start_play(beat: float) -> void:
	if _app == null or _app.chart == null:
		return
	# 倍速音频第一次要等 ffmpeg 生成；加载完再起播，别用旧流或空流开跑。
	await _ensure_audio()
	if _app == null or _app.chart == null:
		return
	_last_beat_int = -1
	_build_sfx_events()
	_playing = true
	_preview.playing = true
	_play_button.text = "❚❚"
	_rebase_playback(beat)


## 把播放时钟重新对到 beat：播放中拖动进度条 / 点时间轴都走这里。
## 不重建音效表，所以可以跟着鼠标连续调用。
func _rebase_playback(beat: float) -> void:
	if _app == null or _app.chart == null:
		return
	_play_start_chart_ms = _app.chart.timing.beat_to_chart_ms(beat)
	_play_start_usec = Time.get_ticks_usec()
	_sfx_event_index = _first_sfx_event(beat)
	_sfx_last_beat = beat - 0.001
	if _audio.stream != null:
		_audio.pitch_scale = _rate / maxf(0.01, _audio_stream_rate)
		var from_sec := maxf(0.0, (_play_start_chart_ms - _app.chart.offset_ms) / 1000.0) / maxf(0.01, _audio_stream_rate)
		# 音频比谱面短（或跳到了音频末尾之后）就别播了，交给墙钟继续推，
		# 否则 play() 立刻 finished，播放会被误停。
		if from_sec < _audio.stream.get_length():
			_audio.play(from_sec)
		else:
			_audio.stop()
	_app.set_playhead(beat)


func _on_seek_requested(beat: float) -> void:
	if _app == null or _app.chart == null:
		return
	if _playing:
		_rebase_playback(beat)
	_update_transport(true)
	_preview.request_redraw()


## 进度条拖动 → 拍号。进度条和时间轴共用谱面本身的长度，避免两边刻度不一致。
func _on_seek_fraction(fraction: float) -> void:
	if _app == null or _app.chart == null:
		return
	_app.seek(clampf(fraction, 0.0, 1.0) * _timeline_total_beats())
	_update_transport(true)


func _set_loop(start: float, end: float, enabled: bool) -> void:
	_loop_enabled = enabled and end > start
	_loop_start = start
	_loop_end = end


func _stop_play() -> void:
	_loop_enabled = false
	if _audio != null:
		_audio.stop()
	_playing = false
	if _preview != null:
		_preview.playing = false
	if _play_button != null:
		_play_button.text = "▶"


## 停止并重置播放进度：黄线回到 0:00。
func _reset_playhead() -> void:
	_stop_play()
	if _app != null:
		_app.set_playhead(0.0)
	_sync_from_app()


func _on_audio_finished() -> void:
	if not _playing:
		return
	if _loop:
		_start_play(0.0)
		return
	# 音频可能比谱面短（示例谱、纯节拍音轨）。播完别急停播放：
	# _process 里的墙钟会接着推进，到达谱面末尾后自己会停。
	if _app == null or _app.chart == null:
		_stop_play()
		return
	if _app.playhead_beat >= _app.chart.duration_beats():
		_stop_play()


func _build_sfx_events() -> void:
	_sfx_events.clear()
	if _app == null or _app.chart == null:
		return
	for note in _app.chart.notes:
		match note.type:
			"tap":
				_add_sfx_event(note.beat, HitSfx.kind_for_note(note))
			"hold":
				_add_sfx_event(note.beat, "don")
			"path":
				_add_sfx_event(note.beat, HitSfx.kind_for_note(note))
				_add_sfx_event(note.end_beat, "tail")
			"anchor":
				_add_sfx_event(note.beat, "anchor", 1.0)
			"bell":
				_add_sfx_event(note.beat, "bell")
			"seek":
				_add_sfx_event(note.beat, "bell")
	_sfx_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["beat"]) < float(b["beat"]))


func _add_sfx_event(beat: float, kind: String, pitch: float = 1.0) -> void:
	_sfx_events.append({"beat": beat, "kind": kind, "pitch": pitch})


func _first_sfx_event(beat: float) -> int:
	var index := 0
	while index < _sfx_events.size() and float(_sfx_events[index]["beat"]) < beat - 0.0001:
		index += 1
	return index


func _fire_editor_sfx(beat: float) -> void:
	# Forward progress can span many beats after a slow frame. Explicit seeks
	# already reset the event index in _rebase_playback; do not drop crossed hits.
	if beat < _sfx_last_beat - 0.001:
		_sfx_event_index = _first_sfx_event(beat)
		_sfx_last_beat = beat
		return
	while _sfx_event_index < _sfx_events.size():
		var event: Dictionary = _sfx_events[_sfx_event_index]
		if float(event["beat"]) > beat + 0.0001:
			break
		if _sfx_enabled:
			_sfx.play(String(event["kind"]), float(event.get("pitch", 1.0)) * randf_range(0.99, 1.01))
		_sfx_event_index += 1
	_sfx_last_beat = beat


func _process(_delta: float) -> void:
	if _app == null or _app.chart == null:
		return
	if _playing:
		var chart_ms := 0.0
		if _audio.stream != null and _audio.playing:
			# 变速音频流里 1 秒 = 谱面 _audio_stream_rate 秒；驱动延迟/混音间隔
			# 是真实秒，换算成谱面时间要乘倍速。
			chart_ms = (_audio.get_playback_position() * _audio_stream_rate
				+ (AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * _rate) * 1000.0 + _app.chart.offset_ms
		else:
			chart_ms = _play_start_chart_ms + float(Time.get_ticks_usec() - _play_start_usec) / 1000.0 * _rate
		var beat: float = _app.chart.timing.chart_ms_to_beat(chart_ms)
		if _loop_enabled and _loop_end > _loop_start and beat >= _loop_end:
			_rebase_playback(_loop_start)
			beat = _loop_start
		_app.set_playhead(beat)
		_fire_editor_sfx(beat)
		var beat_int := floori(beat)
		if _metronome and beat_int != _last_beat_int and _beat_label != null:
			_last_beat_int = beat_int
			_beat_label.add_theme_color_override("font_color", UITheme.CORAL)
			create_tween().tween_interval(0.08).finished.connect(func() -> void:
				if _beat_label != null:
					_beat_label.add_theme_color_override("font_color", UITheme.GOLD)
			)
		var audio_playing := _audio.stream != null and _audio.playing
		if beat >= _app.chart.duration_beats() + 2.0 and not audio_playing:
			_stop_play()


func _playback_total_ms() -> float:
	if _app == null or _app.chart == null:
		return 0.0
	var total_ms: float = _app.chart.timing.beat_to_chart_ms(_app.chart.duration_beats())
	if _audio != null and _audio.stream != null:
		total_ms = maxf(total_ms, _audio.stream.get_length() * 1000.0 * _audio_stream_rate + _app.chart.offset_ms)
	return total_ms


## 进度条、时间标签、时间轴共用同一条时间线：谱面本身的长度。
func _timeline_total_beats() -> float:
	if _app == null or _app.chart == null:
		return 1.0
	return maxf(1.0, _app.chart.duration_beats())


func _update_transport(force: bool = false) -> void:
	if _app == null or _app.chart == null or _time_label == null:
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_transport_msec < 50:
		return
	_last_transport_msec = now
	var total_beats := _timeline_total_beats()
	var total_ms: float = _app.chart.timing.beat_to_chart_ms(total_beats)
	var current_ms: float = _app.chart.timing.beat_to_chart_ms(clampf(_app.playhead_beat, 0.0, total_beats))
	_time_label.text = "%s / %s" % [_format_ms(current_ms), _format_ms(total_ms)]
	_progress.set_progress(_app.playhead_beat / total_beats)
	_beat_label.text = _app.chart.timing.format_beat(_app.playhead_beat)
	_bpm_label.text = "%.1f BPM" % _app.chart.timing.bpm_at(_app.playhead_beat)
	_save_label.text = ("● 未保存" if _app.dirty else "已保存") + ("  %s" % _app.chart_path.get_file() if not _app.chart_path.is_empty() else "")


func _update_status() -> void:
	if _app == null or _app.chart == null:
		return
	_preview.use_3d_ring = _app.use_3d_ring
	_preview.mouse_tilt = _app.mouse_tilt
	if _status_u != null:
		_status_u.text = "u %.1f°" % (_cursor_u * 360.0)
		_status_beat.text = "bar " + _app.chart.timing.format_beat(_app.playhead_beat)
		_status_snap.text = "吸附 " + GridDivisions.label(_app.snap_division) + ("" if _app.time_flows_down else "（反向）")
		_status_sel.text = "选中 %d" % _app.selected_notes.size()
		_status_shape.text = "边界 " + _app.chart.default_shape_id
		var errors: Array = Validator.errors(_issues)
		var warnings: Array = Validator.warnings(_issues)
		if not errors.is_empty():
			_status_error.text = "校验 %d 错误" % errors.size()
			_status_error.add_theme_color_override("font_color", UITheme.RED)
		elif not warnings.is_empty():
			_status_error.text = "校验 %d 警告" % warnings.size()
			_status_error.add_theme_color_override("font_color", UITheme.GOLD)
		else:
			_status_error.text = "校验通过"
			_status_error.add_theme_color_override("font_color", UITheme.GREEN)
	_update_transport(true)


func _update_validation(issues: Array) -> void:
	_issues = issues
	if _validation_label == null:
		return
	var errors: Array = issues.filter(func(item: Dictionary) -> bool: return item.get("level", "") == "error")
	var warnings: Array = issues.filter(func(item: Dictionary) -> bool: return item.get("level", "") == "warning")
	if not errors.is_empty():
		_validation_label.text = "● %s" % errors[0].get("message", "")
		_validation_label.add_theme_color_override("font_color", UITheme.RED)
	elif not warnings.is_empty():
		_validation_label.text = "● %s" % warnings[0].get("message", "")
		_validation_label.add_theme_color_override("font_color", UITheme.GOLD)
	else:
		_validation_label.text = "● 校验通过"
		_validation_label.add_theme_color_override("font_color", UITheme.GREEN)
	_update_status()


func _on_snap_changed(division: int) -> void:
	if _snap_option == null:
		return
	var index := GridDivisions.index_of(division)
	if _snap_option.selected != index:
		_snap_option.select(index)


func _on_audio_import_requested() -> void:
	_audio_dialog.popup_centered_ratio(0.8)


func _on_audio_detect_requested(path: String) -> void:
	if path.strip_edges().is_empty():
		_audio_dialog.popup_centered_ratio(0.8)
		return
	_song_dialog.open_for(path)


func _on_audio_selected(path: String) -> void:
	_song_dialog.open_for(path)


func _on_song_timing_applied() -> void:
	_sync_from_app()
	_show_toast("已写入识别结果；可在“时间”页继续微调 BPM / offset。", "info")


func _on_tab_changed(index: int) -> void:
	if _syncing_tabs or _app == null:
		return
	_app.activate_tab(index)
	_sync_from_app()
	_refresh_tabs()


func _refresh_tabs() -> void:
	if _tabs == null or _app == null:
		return
	_syncing_tabs = true
	_tabs.clear_tabs()
	for i in _app.tabs.size():
		_tabs.add_tab(_app.tab_label(i))
	if _app.active_tab >= 0 and _app.active_tab < _tabs.tab_count:
		_tabs.current_tab = _app.active_tab
	_syncing_tabs = false


func _on_tab_close(index: int) -> void:
	if _app == null or index < 0 or index >= _app.tabs.size():
		return
	var dirty: bool = _app.dirty if index == _app.active_tab else bool(_app.tabs[index].dirty)
	if not dirty:
		_close_tab_now(index)
		return
	_tab_close_index = index
	if _tab_close_dialog == null:
		_tab_close_dialog = ConfirmationDialog.new()
		_tab_close_dialog.title = "关闭标签页"
		_tab_close_dialog.ok_button_text = "保存并关闭"
		_tab_close_dialog.cancel_button_text = "取消"
		_tab_close_dialog.add_button("直接关闭", true, "discard")
		_tab_close_dialog.confirmed.connect(_on_tab_close_save)
		_tab_close_dialog.custom_action.connect(func(action: StringName) -> void:
			if action == &"discard":
				_tab_close_dialog.hide()
				_close_tab_now(_tab_close_index)
		)
		add_child(_tab_close_dialog)
	_tab_close_dialog.dialog_text = "「%s」有未保存的修改。" % _app.tab_label(index).trim_prefix("● ")
	_tab_close_dialog.popup_centered()


func _on_tab_close_save() -> void:
	var index := _tab_close_index
	if index < 0 or _app == null:
		return
	_app.activate_tab(index)
	_sync_from_app()
	_refresh_tabs()
	if _app.chart_path.is_empty() and _app.set_path.is_empty():
		# 没保存过：先让用户选路径，选完再关。
		_save()
		return
	if _app.save_chart():
		_close_tab_now(index)


func _close_tab_now(index: int) -> void:
	if _app == null:
		return
	_tab_close_index = -1
	_app.close_tab(index)
	_sync_from_app()
	_refresh_tabs()


func _on_import_osz_selected(path: String, include_video: bool = true) -> void:
	# 转谱：把来源里的所有难度转好，作为一个新标签页打开，不覆盖当前谱面。
	if _app == null:
		return
	_app.ensure_tab()
	if not _app.open_import_source(path):
		_app.restore_active_tab()
		_show_toast("导入失败：%s" % _import_error_text(), "error")
		return
	if not include_video:
		# osu 详情页选了「不带视频」：先清掉再转码，别为不要的视频干活。
		_drop_import_video()
	await _prepare_import_media()
	var count: int = _app.difficulties.size()
	var title: String = _app.set_path.get_file().get_basename()
	if title.is_empty():
		title = "导入"
	_app.add_tab_from_current(title)
	_sync_from_app()
	_refresh_tabs()
	_show_report("转谱完成：%d 个难度已放进新标签页「%s」，顶部可以切换难度。" % [count, title])


## 「不带视频」：解绑所有难度的 BGA，并删掉导入目录里的视频副本（源 .osz 不动）。
func _drop_import_video() -> void:
	if _app == null:
		return
	var removed := 0
	for entry in _app.difficulties:
		var chart: Chart = entry.get("chart", null)
		if chart == null or chart.video_path.is_empty():
			continue
		var path := chart.video_path
		chart.video_path = ""
		removed += 1
		if path.begins_with("user://imports/"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if removed > 0:
		_app.save_set_file()


## 导入时先把 BGA / 需要转码的音频转好：带百分比进度，UI 不冻结。
## 预览也会自己异步转码，但那里没有进度条；这里先转完，打开就是成品。
func _prepare_import_media() -> void:
	if _app == null or _app.difficulties.is_empty():
		return
	var videos: Array[String] = []
	var audios: Array[String] = []
	for entry in _app.difficulties:
		var chart: Chart = entry.get("chart", null)
		if chart == null:
			continue
		var video := chart.video_path
		if not video.is_empty() and not ChartIO.can_decode_video_directly(video) and not FileAccess.file_exists(MediaIO.video_cache_path(video)) and not videos.has(video):
			videos.append(video)
		var audio := chart.audio_path
		if audio.begins_with("user://imports/simai_zip_") and audio.get_extension().to_lower() != "ogg" and not audios.has(audio):
			audios.append(audio)
	if videos.is_empty() and audios.is_empty():
		return
	var total := videos.size() + audios.size()
	var done := 0
	_show_import_progress()
	var tree := get_tree()
	for video in videos:
		var label := "转码 BGA %d/%d：%s" % [done + 1, total, video.get_file()]
		_import_progress_text(label, 0.0, 0.0)
		await MediaIO.prepare_video_async(video, tree, func(ratio: float, seconds: float) -> void:
			_import_progress_text(label, ratio, seconds))
		done += 1
	for audio in audios:
		var label := "转码音频 %d/%d：%s" % [done + 1, total, audio.get_file()]
		_import_progress_text(label, 0.0, 0.0)
		var prepared := await MediaIO.prepare_audio_async(audio, tree, func(ratio: float, seconds: float) -> void:
			_import_progress_text(label, ratio, seconds))
		done += 1
		if prepared.is_empty():
			continue
		for entry in _app.difficulties:
			var chart: Chart = entry.get("chart", null)
			if chart != null and chart.audio_path == audio:
				chart.audio_path = prepared
	_hide_import_progress()
	_app.save_set_file()


func _show_import_progress() -> void:
	if _import_progress == null:
		_import_progress = AcceptDialog.new()
		_import_progress.title = "媒体处理"
		_import_progress.min_size = Vector2i(460, 150)
		# 进度条只是告知，不抢独占焦点：否则试玩/设置对话框开着时会报
		# "already has another exclusive child"。
		_import_progress.exclusive = false
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		_import_progress.add_child(box)
		_import_progress_label = Label.new()
		_import_progress_label.text = "准备转码…"
		box.add_child(_import_progress_label)
		_import_progress_bar = ProgressBar.new()
		_import_progress_bar.max_value = 100.0
		_import_progress_bar.show_percentage = true
		_import_progress_bar.custom_minimum_size = Vector2(420, 24)
		box.add_child(_import_progress_bar)
		_import_progress.get_ok_button().visible = false
		add_child(_import_progress)
	_import_progress.popup_centered(Vector2i(460, 150))
	_import_progress_bar.visible = true
	_import_progress_bar.value = 0.0


func _import_progress_text(label: String, ratio: float, seconds: float) -> void:
	if _import_progress_label == null:
		return
	_import_progress_label.text = "%s，已转 %d 秒" % [label, int(maxf(0.0, seconds))]
	if _import_progress_bar != null:
		# 音频拿不到时长时只显示已转秒数，别把进度条钉在 0%。
		_import_progress_bar.visible = ratio >= 0.0
		if ratio >= 0.0:
			_import_progress_bar.value = clampf(ratio, 0.0, 1.0) * 100.0


func _hide_import_progress() -> void:
	if _import_progress != null:
		_import_progress.hide()


func _import_error_text() -> String:
	if not OsuIO.last_error.is_empty():
		return OsuIO.last_error
	return SimaiIO.last_error


func _on_import_difficulty_selected(position: int) -> void:
	if _app == null:
		return
	if _app.switch_difficulty(position):
		_sync_from_app()
		_show_toast("已切换到难度：%s" % _app.difficulty_name(position), "info")


func _refresh_import_difficulty() -> void:
	if _import_diff == null:
		return
	var names: Array[String] = _app.difficulty_names() if _app != null else []
	var show: bool = names.size() > 1
	if _import_diff_label != null:
		_import_diff_label.visible = show
	_import_diff.visible = show
	if not show:
		return
	_import_diff.clear()
	for name in names:
		_import_diff.add_item(name)
	_import_diff.select(clampi(_app.difficulty_index, 0, maxi(0, names.size() - 1)))


## 同一首歌多难度：复制当前谱面成一个新难度（之后用「保存全部难度」落盘）。
func _add_difficulty_copy() -> void:
	if _app == null or _app.chart == null:
		return
	var index: int = _app.add_difficulty_copy("难度 %d" % (_app.difficulties.size() + 1))
	if index < 0:
		_show_toast("复制难度失败", "error")
		return
	_sync_from_app()
	_show_toast("已新增难度 %s（改完记得「保存全部难度」）" % _app.difficulty_name(index), "info")


func _save_all_difficulties() -> void:
	if _app == null or _app.difficulties.is_empty():
		_show_toast("当前没有多难度组，先导入或新增一个难度", "warning")
		return
	if _app.save_set_file():
		_sync_from_app()
	else:
		_show_toast("保存难度套组失败", "error")


## 新窗口起不来时的退路：老流程（多难度弹窗选一个，直接在当前窗口导入）。
func _import_into_current_window(path: String) -> void:
	# 直接走难度组：多难度来源会一次性转好，顶部会出现难度下拉。
	if _app != null and _app.open_import_source(path):
		await _prepare_import_media()
		_sync_from_app()
		_show_report(_app.last_import_report)
		return
	var simai := SimaiIO.list_maidata(path)
	if not simai.is_empty():
		_pending_kind = "simai"
		_pending_osz = path
		_difficulty_list.clear()
		for i in simai.size():
			var item: Dictionary = simai[i]
			_difficulty_list.add_item("%s — %s  %s" % [String(item.get("title", "")), String(item.get("version", "")), String(item.get("creator", ""))])
			_difficulty_list.set_item_metadata(i, int(item.get("index", 0)))
		_difficulty_list.select(0)
		_difficulty_dialog.popup_centered_ratio(0.58)
		return
	_pending_kind = "osu"
	var difficulties := OsuIO.list_osz_difficulties(path)
	if difficulties.is_empty():
		_show_toast("导入失败：%s" % OsuIO.last_error, "error")
		return
	if difficulties.size() == 1:
		_import_osz(path, 0)
		return
	_pending_osz = path
	_difficulty_list.clear()
	for item in difficulties:
		_difficulty_list.add_item("%s — %s  [%s]  %s" % [
			String(item.get("title", "")), String(item.get("version", "")),
			"taiko" if int(item.get("mode", 0)) == 1 else "std",
			String(item.get("creator", "")),
		])
	_difficulty_list.select(0)
	_difficulty_dialog.popup_centered_ratio(0.58)


func _import_osz(path: String, difficulty_index: int) -> void:
	if _app.import_osz(path, difficulty_index):
		_sync_from_app()
		_show_report(_app.last_import_report)


func _import_maimai(path: String, difficulty_index: int) -> void:
	if _app.import_maimai(path, difficulty_index):
		_sync_from_app()
		_show_report(_app.last_import_report)


func _show_report(text: String) -> void:
	if _report_dialog == null or text.is_empty():
		return
	# 在线浏览器还开着时再弹报告，两个 AcceptDialog 会抢独占焦点（日志报错）。
	if _chart_browser != null:
		_chart_browser.hide()
	if _osu_browser != null:
		_osu_browser.hide()
	_report_dialog.dialog_text = text
	_report_dialog.popup_centered_ratio(0.62)


func _show_toast(message: String, level: String = "info") -> void:
	if _toast_label == null:
		return
	_toast_label.text = message
	_toast_label.add_theme_color_override("font_color", UITheme.RED if level == "error" else (UITheme.GOLD if level == "warning" else UITheme.CYAN))
	if _toast_timer != null:
		_toast_timer.start()


func _format_ms(ms: float) -> String:
	var value := maxi(0, int(ms))
	var minutes := value / 60000
	var seconds := (value % 60000) / 1000
	var millis := value % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, millis]


func _on_menu(id: int) -> void:
	match id:
		26:
			_open_settings()
		52:
			_open_calibration()
		0:
			_new_dialog.popup_centered_ratio(0.62)
		1:
			_open_dialog.popup_centered_ratio(0.75)
		2:
			_save()
		3:
			_save_dialog.popup_centered_ratio(0.75)
		16:
			_add_difficulty_copy()
		17:
			_save_all_difficulties()
		4:
			_app.load_autosave()
			_sync_from_app()
		6:
			_import_dialog.popup_centered_ratio(0.75)
		8:
			_import_dir_dialog.popup_centered_ratio(0.75)
		9:
			_audio_dialog.popup_centered_ratio(0.75)
		19:
			if _inspector != null:
				_inspector.open_video_picker()
		15:
			_chart_browser.popup_centered_ratio(0.8)
		18:
			_osu_browser.popup_centered_ratio(0.8)
		7:
			_lbp_dialog.popup_centered_ratio(0.75)
		5:
			get_tree().quit()
		10:
			_app.undo_chart()
			_sync_from_app()
		11:
			_app.redo_chart()
			_sync_from_app()
		12:
			_canvas._delete_selection()
		13:
			_app.clear_selection()
		14:
			_canvas._select_visible()
		20:
			_app.hud_visible = not _app.hud_visible
			_preview.show_hud = _app.hud_visible
		21:
			_app.debug_overlay = not _app.debug_overlay
			_preview.show_debug = _app.debug_overlay
		22:
			_app.waveform_visible = not _app.waveform_visible
		25:
			_app.set_time_flows_down(not _app.time_flows_down)
		23, 37, 38, 39:
			_open_ring_workspace()
		24:
			_inspector.current_tab = 3
		30, 31, 32, 33, 34, 35, 36:
			_set_tool(["tap", "hold", "path", "seek", "anchor", "bell", "limit"][id - 30])
		40:
			_show_toast("形变事件在「视图 → 环编辑」里做：复制成 B 再拖时间轴。", "info")
		41:
			_set_tool("limit")
		50:
			_open_playtest_setup(false)
		51:
			_open_playtest_setup(true)
	_update_status()


func _save() -> void:
	if _app.chart_path.is_empty():
		_save_dialog.popup_centered_ratio(0.75)
	else:
		_app.save_chart()
		_sync_from_app()


func _open_calibration(return_to: String = "") -> void:
	_calibration_return = return_to
	if _app == null:
		return
	if _calibration_dialog == null:
		_calibration_dialog = CalibrationDialog.new()
		_calibration_dialog.setup(_app)
		_calibration_dialog.closed.connect(func() -> void:
			if _playtest_offset != null:
				_playtest_offset.value = float(_app.playtest_offset_ms)
			if _playtest_latency != null:
				_playtest_latency.value = float(_app.audio_latency_ms)
			var target := _calibration_return
			_calibration_return = ""
			if target == "settings":
				_open_settings()
			elif target == "playtest":
				_open_playtest_setup(_playtest_from_start)
		)
		add_child(_calibration_dialog)
	if _playtest_dialog != null:
		_playtest_dialog.hide()
	if _settings_dialog != null:
		_settings_dialog.hide()
	_calibration_dialog.open()


func _open_playtest_setup(from_start: bool) -> void:
	if _app == null or _app.chart == null:
		return
	_playtest_from_start = from_start
	if _playtest_dialog == null:
		_build_playtest_dialog()
	# 试玩中从暂停菜单打开时，确认键是"完成"而不是"开始"。
	if _playtest != null:
		# 试玩中打开：只能应用设置并返回。
		_playtest_dialog.ok_button_text = "完成"
		if _playtest_start_button != null:
			_playtest_start_button.visible = false
	else:
		_playtest_dialog.ok_button_text = "继续游玩"
		if _playtest_start_button != null:
			_playtest_start_button.visible = true
	_playtest_rate.value = _rate
	_playtest_flow.value = _app.flow_scale
	_playtest_star.value = _app.star_speed
	if _playtest_cursor != null:
		_playtest_cursor.value = _app.cursor_scale
	if _playtest_offset != null:
		_playtest_offset.value = float(_app.playtest_offset_ms)
	if _playtest_dynamic != null:
		_playtest_dynamic.button_pressed = bool(_app.dynamic_offset)
	if _playtest_auto != null:
		_playtest_auto.button_pressed = bool(_app.playtest_auto)
	if _playtest_mouse != null:
		_playtest_mouse.button_pressed = bool(_app.mouse_keys)
	if _playtest_latency != null:
		_playtest_latency.value = float(_app.audio_latency_ms)
	if _playtest_sfx != null:
		_playtest_sfx.selected = maxi(0, ["default", "crisp", "deep"].find(_app.hit_sfx_style))
	if _playtest_bias != null:
		_playtest_bias.text = "上次平均偏差 %+.1fms" % float(_app.last_bias_ms)
	_sync_volume_sliders()
	_playtest_dialog.popup_centered(Vector2i(470, 520))


## 统一设置窗口：画质 / 界面 / 音频 / 校准。视图菜单只留显示开关。
func _open_settings() -> void:
	if _app == null:
		return
	if _settings_dialog == null:
		_settings_dialog = AcceptDialog.new()
		_settings_dialog.title = "设置"
		_settings_dialog.ok_button_text = "关闭"
		_settings_dialog.min_size = Vector2i(560, 680)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(520, 600)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_settings_dialog.add_child(scroll)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 10)
		scroll.add_child(box)
		_build_quality_rows(box)
		box.add_child(HSeparator.new())
		_build_hud_rows(box)
		box.add_child(HSeparator.new())
		_build_audio_rows(box)
		box.add_child(HSeparator.new())
		_build_cache_rows(box)
		box.add_child(HSeparator.new())
		_build_calibration_rows(box)
		add_child(_settings_dialog)
	_refresh_view_menu()
	_sync_volume_sliders()
	_settings_dialog.popup_centered_ratio(0.72)


func _build_audio_rows(parent: Control) -> void:
	var title := Label.new()
	title.text = "音频"
	title.add_theme_font_size_override("font_size", 12)
	parent.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	# 输出延迟：0 = 用驱动值；>0 = 强制覆盖。
	var lat_label := Label.new()
	lat_label.text = "输出延迟"
	lat_label.add_theme_font_size_override("font_size", 11)
	grid.add_child(lat_label)
	var lat := SpinBox.new()
	lat.min_value = 0.0
	lat.max_value = 250.0
	lat.step = 1.0
	lat.suffix = "ms"
	lat.value = float(_app.audio_latency_ms)
	lat.tooltip_text = "0 = 用驱动报告值；>0 = 强制覆盖。驱动明显不准时才手动填"
	lat.value_changed.connect(func(value: float) -> void:
		_app.audio_latency_ms = clampf(value, 0.0, 250.0)
		_app.save_settings()
	)
	grid.add_child(lat)
	# 音频缓冲是启动期设置，写 override.cfg 后重启生效。
	var buf_label := Label.new()
	buf_label.text = "音频缓冲"
	buf_label.add_theme_font_size_override("font_size", 11)
	grid.add_child(buf_label)
	var buf_row := HBoxContainer.new()
	buf_row.add_theme_constant_override("separation", 6)
	var buf := SpinBox.new()
	buf.min_value = 3
	buf.max_value = 40
	buf.step = 1
	buf.suffix = "ms"
	buf.value = float(_app.audio_buffer_ms)
	buf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buf_row.add_child(buf)
	var apply_buf := Button.new()
	apply_buf.text = "应用（重启）"
	apply_buf.pressed.connect(func() -> void: _app.set_audio_buffer(int(buf.value)))
	buf_row.add_child(apply_buf)
	grid.add_child(buf_row)
	# 打击音色。
	var sfx_label := Label.new()
	sfx_label.text = "打击音色"
	sfx_label.add_theme_font_size_override("font_size", 11)
	grid.add_child(sfx_label)
	var sfx_pick := OptionButton.new()
	for label in ["默认", "清脆", "低沉"]:
		sfx_pick.add_item(label)
	sfx_pick.selected = maxi(0, ["default", "crisp", "deep"].find(_app.hit_sfx_style))
	sfx_pick.item_selected.connect(func(index: int) -> void:
		var styles := ["default", "crisp", "deep"]
		_app.hit_sfx_style = styles[clampi(index, 0, 2)]
		_app.save_settings()
		_sfx.set_style(_app.hit_sfx_style)
		if _playtest != null:
			_playtest._sync_sfx_style()
	)
	grid.add_child(sfx_pick)


func _build_cache_rows(parent: Control) -> void:
	var title := Label.new()
	title.text = "转码 / 变速缓存"
	title.add_theme_font_size_override("font_size", 12)
	parent.add_child(title)
	_cache_label = Label.new()
	_cache_label.add_theme_font_size_override("font_size", 11)
	_cache_label.add_theme_color_override("font_color", UITheme.MUTED)
	parent.add_child(_cache_label)
	_refresh_cache_label()
	var clear := Button.new()
	clear.text = "清理转码 / 变速缓存…"
	clear.pressed.connect(func() -> void:
		var dialog := ConfirmationDialog.new()
		dialog.title = "清理转码 / 变速缓存"
		dialog.dialog_text = "删除 %s 的 BGA / 音频转码 / 变速音频文件；源文件不动，下次需要时重新生成。要继续吗？" % _format_bytes(MediaIO.cache_size())
		dialog.confirmed.connect(func() -> void:
			var freed := MediaIO.clear_cache()
			_refresh_cache_label()
			_show_toast("已清理缓存 %s" % _format_bytes(freed), "info")
		)
		add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
	)
	parent.add_child(clear)


func _refresh_cache_label() -> void:
	if _cache_label == null:
		return
	_cache_label.text = "user://media 当前占用 %s；音频转码、变速音频和无解码库时的视频兜底会写这里。" % _format_bytes(MediaIO.cache_size())


func _format_bytes(value: int) -> String:
	if value >= 1024 * 1024 * 1024:
		return "%.1f GB" % (float(value) / (1024.0 * 1024.0 * 1024.0))
	if value >= 1024 * 1024:
		return "%.0f MB" % (float(value) / (1024.0 * 1024.0))
	if value >= 1024:
		return "%.0f KB" % (float(value) / 1024.0)
	return "%d B" % value


func _build_calibration_rows(parent: Control) -> void:
	var title := Label.new()
	title.text = "校准"
	title.add_theme_font_size_override("font_size", 12)
	parent.add_child(title)
	var hint := Label.new()
	hint.text = "跟声音或脉冲点 8 次，写回判定偏移；也可以直接改试玩设置里的偏移。"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)
	var open_cal := Button.new()
	open_cal.text = "打开校准…"
	open_cal.pressed.connect(func() -> void:
		if _settings_dialog != null:
			_settings_dialog.hide()
		_open_calibration("settings")
	)
	parent.add_child(open_cal)


func _build_playtest_dialog() -> void:
	_playtest_dialog = AcceptDialog.new()
	_playtest_dialog.title = "试玩设置"
	_playtest_dialog.ok_button_text = "开始"
	_playtest_dialog.min_size = Vector2i(360, 220)
	# 选项越加越多，内容放进滚动区，小窗口也不会把按钮挤出屏幕。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 350)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_playtest_dialog.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	_playtest_rate = _playtest_spin_row(box, "倍速", 0.5, 2.0, 0.05, 1.0, "×")
	_playtest_rate.tooltip_text = "试玩和编辑器试听都按这个速度走；声音不变调（每个新倍速首次生成缓存）；局中修改在重开本局后生效；只对本次运行有效"
	_playtest_flow = _playtest_spin_row(box, "流速", 0.05, 3.0, 0.01, 1.0, "×")
	_playtest_star = _playtest_spin_row(box, "星速", 0.5, 2.0, 0.05, 1.0, "×")
	_playtest_cursor = _playtest_spin_row(box, "光标大小", 0.5, 2.0, 0.05, 1.0, "×")
	_playtest_offset = _playtest_spin_row(box, "判定偏移", -200.0, 200.0, 1.0, 0.0, "ms")
	_playtest_latency = _playtest_spin_row(box, "输出延迟", 0.0, 250.0, 1.0, 0.0, "ms")
	_playtest_latency.tooltip_text = "0 = 用驱动报告值；>0 = 强制覆盖（可升可降）。驱动明显不准时才手动填"
	var calib_hint := Label.new()
	calib_hint.text = "判定偏移校准在「设置 → 校准」里（8 次点击后自动写回）"
	calib_hint.add_theme_font_size_override("font_size", 11)
	calib_hint.add_theme_color_override("font_color", UITheme.MUTED)
	calib_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(calib_hint)
	_playtest_dynamic = CheckBox.new()
	_playtest_dynamic.text = "动态 offset（局内自动校准，≤±50ms）"
	_playtest_dynamic.tooltip_text = "至少 8 次命中后，每次命中按偏差的 5% 自动微调判定偏移"
	box.add_child(_playtest_dynamic)
	_playtest_auto = CheckBox.new()
	_playtest_auto.text = "AUTO 自动演示（游戏内 F8 切换）"
	_playtest_auto.tooltip_text = "自动完美演奏所有音符，用来快速看谱面；结算会标注 AUTO"
	box.add_child(_playtest_auto)
	_playtest_mouse = CheckBox.new()
	_playtest_mouse.text = "鼠标左右键算 Tap"
	_playtest_mouse.tooltip_text = "关掉后左右键不参与判定；鼠标移动、滚轮 Seek 照常（暂停菜单也能改）"
	box.add_child(_playtest_mouse)
	_playtest_bias = Label.new()
	_playtest_bias.text = "上次平均偏差 +0.0ms"
	_playtest_bias.add_theme_font_size_override("font_size", 11)
	_playtest_bias.add_theme_color_override("font_color", UITheme.MUTED)
	box.add_child(_playtest_bias)
	# 音频：和编辑器「音频」弹窗、设置窗口共用 Music / SFX 总线与持久化字段。
	var audio_title := Label.new()
	audio_title.text = "音频"
	audio_title.add_theme_font_size_override("font_size", 12)
	box.add_child(audio_title)
	box.add_child(_volume_slider("音乐", "Music"))
	box.add_child(_volume_slider("音效", "SFX"))
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 6)
	var sfx_label := Label.new()
	sfx_label.text = "打击音色"
	sfx_label.custom_minimum_size = Vector2(56, 0)
	UITheme.style_mono(sfx_label, 12, UITheme.MUTED)
	sfx_row.add_child(sfx_label)
	_playtest_sfx = OptionButton.new()
	for label in ["默认", "清脆", "低沉"]:
		_playtest_sfx.add_item(label)
	_playtest_sfx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playtest_sfx.item_selected.connect(func(index: int) -> void:
		_app.hit_sfx_style = ["default", "crisp", "deep"][clampi(index, 0, 2)]
		_app.save_settings()
		_sfx.set_style(_app.hit_sfx_style)
		if _playtest != null:
			_playtest._sync_sfx_style()
	)
	sfx_row.add_child(_playtest_sfx)
	box.add_child(sfx_row)
	box.add_child(HSeparator.new())
	var open_settings := Button.new()
	open_settings.text = "画质 / 界面 / 音频 / 校准设置…"
	open_settings.tooltip_text = "统一设置窗口：画质、界面、音频与校准"
	open_settings.pressed.connect(_open_settings)
	box.add_child(open_settings)
	# 底部只留两种开始方式：继续游玩（播放头）、从头开始玩；
	# 试玩中从暂停菜单打开时只剩「完成」。
	_playtest_start_button = _playtest_dialog.add_button("从头开始玩", true, "start_from_beginning")
	add_child(_playtest_dialog)
	_playtest_dialog.confirmed.connect(_begin_playtest_with_settings)
	_playtest_dialog.custom_action.connect(func(action: StringName) -> void:
		if String(action) == "start_from_beginning":
			_playtest_from_start = true
			_playtest_dialog.hide()
			_begin_playtest_with_settings()
	)
	# × 或 Esc 关闭时同样保留设置（只保存，不开始试玩）。
	_playtest_dialog.canceled.connect(_commit_playtest_settings)


func _playtest_spin_row(parent: VBoxContainer, label_text: String, lo: float, hi: float, step: float, value: float, suffix: String) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(64, 0)
	UITheme.style_mono(label, 12, UITheme.MUTED)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = value
	spin.suffix = suffix
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return spin


func _begin_playtest_with_settings() -> void:
	_commit_playtest_settings()
	_start_playtest(_playtest_from_start)


## 把试玩设置写回 _app 并落盘。确认按钮和右上角 × 都走这里，
## 否则用 × / Esc 关掉对话框时设置会退回默认值。
func _commit_playtest_settings() -> void:
	if _app == null:
		return
	_rate = _playtest_rate.value
	if _playtest_latency != null:
		_app.audio_latency_ms = clampf(_playtest_latency.value, 0.0, 250.0)
	_app.flow_scale = _playtest_flow.value
	_app.star_speed = _playtest_star.value
	if _playtest_cursor != null:
		_app.cursor_scale = clampf(_playtest_cursor.value, 0.5, 2.0)
	if _playtest_offset != null:
		_app.playtest_offset_ms = _playtest_offset.value
	if _playtest_dynamic != null:
		_app.dynamic_offset = _playtest_dynamic.button_pressed
	if _playtest_auto != null:
		_app.playtest_auto = _playtest_auto.button_pressed
	if _playtest_mouse != null:
		_app.mouse_keys = _playtest_mouse.button_pressed
	_app.save_settings()
	_preview.flow_scale = _app.flow_scale
	_preview.star_speed = _app.star_speed
	_preview.playback_rate = _rate
	_preview.cursor_scale = _app.cursor_scale
	_preview.request_redraw()
	# 试玩中从暂停菜单改设置：直接应用到正在跑的预览。
	if _playtest != null:
		# 倍速不即时改：写进下一局，重开本局才换速度。
		_playtest.next_playback_rate = _rate
		_playtest._preview.flow_scale = _app.flow_scale
		_playtest._preview.star_speed = _app.star_speed
		_playtest._preview.cursor_scale = _app.cursor_scale
		_playtest._preview.request_redraw()
	if _editor_flow_spin != null:
		_editor_flow_spin.value = _app.flow_scale

## 命令行打开一个 .tmkrpl：载入它记的谱面，然后直接进回放。
func _open_replay_file(path: String) -> void:
	var data := Replay.load_from(path)
	if data == null:
		print("[replay] 读不出回放：", path)
		return
	var chart_path := data.chart_path
	if chart_path.is_empty() or not FileAccess.file_exists(chart_path):
		print("[replay] 找不到回放对应的谱面：", chart_path)
		return
	var chart: Chart = ChartIO.load_chart(chart_path)
	if chart == null:
		print("[replay] 谱面读取失败：", ChartIO.last_error)
		return
	_app.set_chart(chart, chart_path, false)
	_sync_from_app()
	_start_replay(data)


func _start_playtest(from_start: bool) -> void:
	if _app == null or _app.chart == null or _playtest != null:
		return
	var errors := Validator.errors(Validator.validate(_app.chart))
	if not errors.is_empty():
		_show_toast("先修复 %d 个校验错误再试玩：%s" % [errors.size(), errors[0].get("message", "")], "error")
		return
	_stop_play()
	# The full-screen playtest covers the editor. Suspend its preview and input
	# rather than continuing to render a second 3D scene underneath it.
	var editor_root := get_node("Root") as Control
	editor_root.hide()
	editor_root.process_mode = Node.PROCESS_MODE_DISABLED
	_preview.set_suspended(true)
	_playtest = Playtest.new()
	_playtest.bench_mode = "--bench" in OS.get_cmdline_user_args()
	_playtest.auto_play = bool(_app.playtest_auto) or "--auto" in OS.get_cmdline_user_args()
	_playtest.next_playback_rate = _rate
	add_child(_playtest)
	_playtest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_playtest.setup(_app.chart, 0.0 if from_start else _app.playhead_beat, _app.chart_path)
	_playtest.exit_requested.connect(_end_playtest)
	_playtest.settings_requested.connect(_open_settings)
	_playtest.playtest_settings_requested.connect(func() -> void: _open_playtest_setup(false))
	_playtest.replay_requested.connect(func(data: Replay) -> void: _start_replay.call_deferred(data))


## 结算页点「回放本局」：按同一份谱面重开一局，输入全部来自录制。
func _start_replay(data: Replay) -> void:
	if data == null or _app == null or _app.chart == null:
		return
	if _playtest != null:
		_end_playtest()
	var editor_root := get_node("Root") as Control
	editor_root.hide()
	editor_root.process_mode = Node.PROCESS_MODE_DISABLED
	_preview.set_suspended(true)
	if not data.chart_hash.is_empty() and data.chart_hash != Replay.hash_chart(_app.chart):
		_show_toast("谱面在录制之后被改过，回放结果可能和当时不同", "error")
	_playtest = Playtest.new()
	_playtest.replay_source = data
	add_child(_playtest)
	_playtest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_playtest.setup(_app.chart, data.start_beat, _app.chart_path)
	_playtest.exit_requested.connect(_end_playtest)
	_playtest.settings_requested.connect(_open_settings)
	_playtest.playtest_settings_requested.connect(func() -> void: _open_playtest_setup(false))
	_playtest.replay_requested.connect(func(next: Replay) -> void: _start_replay.call_deferred(next))


func _end_playtest() -> void:
	if _playtest != null:
		_playtest.queue_free()
		_playtest = null
	var editor_root := get_node("Root") as Control
	editor_root.process_mode = Node.PROCESS_MODE_INHERIT
	editor_root.show()
	_preview.set_suspended(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_sync_from_app()


func _input(event: InputEvent) -> void:
	if _playtest != null:
		return
	if _calibration_dialog != null and _calibration_dialog.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		# 数值框（SpinBox）内部的 LineEdit 不当作"正在打字"，否则它会吃掉空格等全局快捷键。
		var typing := focus is TextEdit
		if focus is LineEdit and not (focus.get_parent() is SpinBox):
			typing = true
		if typing and event.keycode != KEY_F5 and event.keycode != KEY_F6:
			return
		if _canvas != null and _canvas.has_pending_seek() and event.keycode in [KEY_W, KEY_S]:
			_canvas.set_pending_seek_orientation(1 if event.keycode == KEY_W else 0)
			accept_event()
			return
		# While a numeric editor (SpinBox or its inner LineEdit) has focus, let
		# 1–7 reach the field instead of switching the note tool. Returning
		# without accept_event is important: GUI input still receives the digit.
		var spin_focus := focus is SpinBox or (focus is LineEdit and focus.get_parent() is SpinBox)
		if spin_focus and event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7]:
			return
		match event.keycode:
			KEY_SPACE:
				if event.ctrl_pressed:
					_loop = not _loop
					_show_toast("循环 %s" % ("开" if _loop else "关"), "info")
				elif event.shift_pressed:
					_start_play(0.0)
				else:
					_toggle_play()
				accept_event()
			KEY_S:
				if event.ctrl_pressed:
					if event.shift_pressed:
						_save_dialog.popup_centered_ratio(0.75)
					else:
						_save()
					accept_event()
			KEY_O:
				if event.ctrl_pressed:
					_open_dialog.popup_centered_ratio(0.75)
					accept_event()
			KEY_N:
				if event.ctrl_pressed:
					_new_dialog.popup_centered_ratio(0.62)
					accept_event()
			KEY_Z:
				if event.ctrl_pressed:
					_app.undo_chart()
					_sync_from_app()
					accept_event()
			KEY_Y:
				if event.ctrl_pressed:
					_app.redo_chart()
					_sync_from_app()
					accept_event()
			KEY_F5:
				_open_playtest_setup(event.shift_pressed)
				accept_event()
			KEY_F6:
				_inspector.current_tab = 3
				accept_event()
			KEY_H:
				_app.hud_visible = not _app.hud_visible
				_preview.show_hud = _app.hud_visible
				_update_status()
				accept_event()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				_set_tool(["tap", "hold", "path", "seek", "anchor", "bell", "limit"][event.keycode - KEY_1])
				accept_event()
			KEY_B:
				_set_tool("boundary")
				accept_event()
			KEY_E:
				_set_tool("event")
				accept_event()
			KEY_C:
				if event.ctrl_pressed:
					_canvas.copy_selection(false)
					accept_event()
			KEY_X:
				if event.ctrl_pressed:
					_canvas.copy_selection(true)
				else:
					_canvas._delete_selection()
				accept_event()
			KEY_V:
				if event.ctrl_pressed and event.shift_pressed:
					_inspector.current_tab = 2
					_show_toast("视频属性在「视图/设置」页；offset / FPS / 透明度 / 隐藏都在那里。", "info")
					accept_event()
				elif event.ctrl_pressed:
					_canvas.paste_clipboard(false)
					accept_event()
			KEY_A:
				if event.ctrl_pressed:
					if _canvas.has_clipboard():
						_canvas.paste_clipboard(true)
					else:
						_canvas._select_visible()
					accept_event()
				elif _canvas.mirror_selected_note():
					accept_event()
			KEY_M:
				_app.mirror_selected_notes()
				accept_event()
			KEY_R:
				_app.rotate_selected_notes(90.0)
				accept_event()
			KEY_K:
				_open_ring_workspace()
				accept_event()
			KEY_DELETE:
				_canvas._delete_selection()
				accept_event()
			KEY_ESCAPE:
				_canvas._cancel_pending()
				_app.set_tool("select")
				if _playing:
					_stop_play()
				elif _canvas.has_clipboard():
					_canvas.cancel_clipboard()
				else:
					_app.clear_selection()
				accept_event()
