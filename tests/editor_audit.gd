extends Control

var passed := 0
var failed := 0
var partial := 0


func _ready() -> void:
	var app := get_node_or_null("/root/App")
	print("=== EDITOR AUDIT ===")
	_audit_notes()
	_audit_validation()
	_audit_boundary()
	_audit_undo_io()
	_audit_edit_ops()
	await _audit_note_inspector(app)
	await _audit_ui(app)
	_audit_source()
	print("=== EDITOR AUDIT RESULT passed=%d failed=%d partial=%d ===" % [passed, failed, partial])
	get_tree().quit()


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("[PASS] %s%s" % [name, ("  " + detail) if not detail.is_empty() else ""])
	else:
		failed += 1
		print("[FAIL] %s%s" % [name, ("  " + detail) if not detail.is_empty() else ""])


func _part(name: String, detail: String) -> void:
	partial += 1
	print("[PARTIAL] %s  %s" % [name, detail])


func _make_note(chart: Chart, type: String, beat: float) -> Note:
	var note := Note.new(type, beat, 30.0, 60.0)
	note.id = chart.next_note_id()
	if type in ["hold", "path"]:
		note.end_beat = beat + 2.0
	if type == "path":
		note.tail_angle = 150.0
		note.trace_pts = [
			{"x": 1.0, "y": 0.0, "db": 0.0},
			{"x": 0.0, "y": 1.0, "db": 2.0},
		]
		note.trace_pts = [
			{"x": 0.8, "y": 0.0, "db": 0.0},
			{"x": 0.0, "y": 0.8, "db": 2.0},
		]
	if type == "bell":
		note.center_u = 0.25
		note.radius = 40.0
	chart.notes.append(note)
	return note


func _audit_notes() -> void:
	_check("六类音符都存在", Note.TYPES.size() == 6, str(Note.TYPES))
	var chart := Chart.new()
	for i in Note.TYPES.size():
		_make_note(chart, Note.TYPES[i], float(i) * 2.0)
	_check("六类音符可写入 Chart", chart.notes.size() == 6)
	var roundtrip_ok := true
	for note in chart.notes:
		var copy := Note.from_dict(note.to_dict())
		if copy.type != note.type or absf(copy.beat - note.beat) > 0.001 or copy.id != note.id:
			roundtrip_ok = false
	_check("Note JSON 往返", roundtrip_ok)
	_check("Tap 保留可变宽度", _find(chart, "tap").width == 60.0, "width=%.0f" % _find(chart, "tap").width)
	_check("Hold 头部+持续", _find(chart, "hold").duration() > 0.0)
	_check("Path 头尾+平面点", _find(chart, "path").trace_pts.size() >= 2 and _find(chart, "path").duration() > 0.0)
	_check("Bell 圆心+半径", _find(chart, "bell").radius > 0.0 and _find(chart, "bell").center_u >= 0.0)
	_check("Anchor 配对字段", _find(chart, "anchor").pair_id == "" and _find(chart, "anchor").anchor_pair == -1)


func _find(chart: Chart, type: String) -> Note:
	for note in chart.notes:
		if note.type == type:
			return note
	return null


func _audit_validation() -> void:
	var good := Chart.new()
	_make_note(good, "tap", 0.0)
	_make_note(good, "hold", 2.0)
	_make_note(good, "path", 4.0)
	var anchor_a := _make_note(good, "anchor", 8.0)
	var anchor_b := _make_note(good, "anchor", 8.0)
	anchor_a.angle = 0.0
	anchor_b.angle = 180.0
	anchor_a.pair_id = "A0"
	anchor_b.pair_id = "A0"
	_make_note(good, "bell", 10.0)
	_check("有效谱面通过校验", Validator.errors(Validator.validate(good)).is_empty(), str(Validator.errors(Validator.validate(good))))

	var conflict := Chart.new()
	_make_note(conflict, "tap", 0.0).angle = 0.0
	_make_note(conflict, "tap", 0.0).angle = 180.0
	_check("同刻无公共角度被拒绝", not Validator.errors(Validator.validate(conflict)).is_empty())

	var red := Chart.new()
	_make_note(red, "tap", 0.0)
	var region := Region.new(red.next_region_id(), 0.0, 5.0)
	region.angle = 0.0
	region.width = 30.0
	red.regions.append(region)
	_check("Red 超过 4 拍被拒绝", not Validator.errors(Validator.validate(red)).is_empty())

	var anchor := Chart.new()
	var lone := _make_note(anchor, "anchor", 2.0)
	lone.pair_id = "A0"
	lone.anchor_pair = 0
	_check("Anchor 缺配对被拒绝", not Validator.errors(Validator.validate(anchor)).is_empty())

	var triple := Chart.new()
	for i in 3:
		_make_note(triple, "anchor", 4.0).angle = float(i) * 120.0
	_check("同拍超过双押上限被拒绝", not Validator.errors(Validator.validate(triple)).is_empty())

	var free_angle := Chart.new()
	var free_a := _make_note(free_angle, "anchor", 6.0)
	var free_b := _make_note(free_angle, "anchor", 6.0)
	free_a.angle = 10.0
	free_b.angle = 95.0
	free_a.pair_id = "A1"
	free_b.pair_id = "A1"
	_check("任意角度仍可配对", Validator.errors(Validator.validate(free_angle)).is_empty())

	var shape := BoundaryShape.star("S", 380.0, 190.0, 5)
	var shape_issues := shape.validate()
	_check("凹形允许保存", shape_issues.is_empty(), str(shape_issues))
	var bow := BoundaryShape.new()
	bow.id = "BOW"
	bow.closed = true
	var pts: Array[Vector2] = [Vector2(-300, -300), Vector2(300, 300), Vector2(-300, 300), Vector2(300, -300)]
	for i in 4:
		bow.segments.append(BoundarySegment.new(float(i) / 4.0, float(i + 1) / 4.0, pts[i], pts[(i + 1) % 4], "l", "l"))
	_check("自交边界被识别", not bow.validate().is_empty())

	var gap := BoundaryShape.circle("G", 330.0, 8)
	gap.segments[0].gap = true
	_check("缺口段可存", gap.segments[0].gap and gap.point_at(gap.segments[0].u0 + 0.001).get("gap", false))


func _audit_boundary() -> void:
	var chart := Chart.new()
	var shape := BoundaryShape.circle("S1", 300.0, 16)
	chart.shapes["S1"] = shape
	var event := BoundaryEvent.new("E1", 0.0, 4.0, 0.0, 0.5, "S1", "S1")
	chart.events.append(event)
	_check("BoundaryEvent 可写入", chart.events.size() == 1 and event.restore_duration >= 0.0)
	_check("ViewState 关键帧存在", chart.view_states.size() >= 1)
	_check("BPM/拍号字段", chart.timing.points[0].bpm > 0.0 and chart.timing.points[0].beats_per_bar >= 1)


func _audit_edit_ops() -> void:
	var app = load("res://charter/app.gd").new()
	var chart := Chart.new()
	var note := _make_note(chart, "tap", 2.0)
	note.angle = 30.0
	app.chart = chart
	app.chart_path = ""
	app.playhead_beat = 10.0
	app.select_note(note.id)
	app.copy_selected_notes()
	app.paste_notes()
	_check("复制/粘贴可用", chart.notes.size() == 2)
	if chart.notes.size() == 2:
		_check("粘贴落在播放头", absf(chart.notes[1].beat - 10.0) < 0.001, "beat=%.2f" % chart.notes[1].beat)
	app.select_note(note.id)
	app.mirror_selected_notes()
	_check("镜像角度", absf(note.angle - 210.0) < 0.001, "angle=%.1f" % note.angle)
	app.rotate_selected_notes(90.0)
	_check("旋转角度", absf(note.angle - 300.0) < 0.001, "angle=%.1f" % note.angle)
	app.free()


func _audit_undo_io() -> void:
	var undo := UndoStack.new()
	for i in 205:
		undo.record({"i": i})
	_check("撤销上限 200", undo.undo_items.size() == 200 and int(undo.undo_items[0].get("i", -1)) == 5)
	var chart := Chart.new()
	_make_note(chart, "tap", 0.0)
	var path := "/tmp/tamaki_audit_chart.json"
	ChartIO.save_chart(chart, path)
	ChartIO.save_chart(chart, path)
	var loaded := ChartIO.load_chart(path)
	_check("JSON 保存/打开", loaded != null and loaded.notes.size() == 1)
	_check("保存备份 .bak.1", FileAccess.file_exists(path + ".bak.1"))
	var lbp := "/tmp/tamaki_audit_chart.lbp"
	var lbp_err := LBPIO.export_to_file(chart, lbp)
	_check("LBP v2 导出", lbp_err == OK and FileAccess.get_file_as_string(lbp).contains("[Notes]"))


func _audit_note_inspector(app: Node) -> void:
	var chart := Chart.new()
	var tap := _make_note(chart, "tap", 0.0)
	var hold := _make_note(chart, "hold", 2.0)
	var path := _make_note(chart, "path", 4.0)
	var bell := _make_note(chart, "bell", 6.0)
	app.chart = chart
	app.chart_path = ""
	app.selected_notes.clear()
	var inspector := Inspector.new()
	inspector.theme = UITheme.build()
	add_child(inspector)
	await get_tree().process_frame
	await get_tree().process_frame
	app.select_note(tap.id)
	await get_tree().process_frame
	_check("Inspector 单音符页", inspector._note_groups["common"].visible and not inspector._note_groups["hold"].visible)
	app.select_note(hold.id)
	await get_tree().process_frame
	_check("Inspector 切到 Hold", inspector._note_groups["hold"].visible and not inspector._note_groups["path"].visible)
	app.select_note(path.id)
	await get_tree().process_frame
	_check("Inspector 切到 Path", inspector._note_groups["path_edit"].visible and not inspector._note_groups["hold"].visible)
	app.select_note(bell.id)
	await get_tree().process_frame
	_check("Inspector 切到 Bell", inspector._note_groups["bell"].visible and not inspector._note_groups["path"].visible)
	inspector.queue_free()


func _audit_ui(app: Node) -> void:
	var inspector := Inspector.new()
	inspector.theme = UITheme.build()
	add_child(inspector)
	await get_tree().process_frame
	await get_tree().process_frame
	inspector.current_tab = 2
	await get_tree().process_frame
	await get_tree().process_frame
	var page: VBoxContainer = inspector._pages["视图"]
	var options: Array[OptionButton] = []
	for child in page.get_children():
		if child is OptionButton:
			options.append(child)
		elif child is HBoxContainer:
			for sub in child.get_children():
				if sub is OptionButton:
					options.append(sub)
	var all_text := ""
	for option in options:
		for i in option.item_count:
			all_text += option.get_item_text(i) + "|"
	_check("设置页有皮肤选项", all_text.contains("糖霜胶囊") and all_text.contains("街机贴纸"))
	_check("设置页有特效选项", all_text.contains("迸裂") and all_text.contains("墨滴"))
	_check("设置页有音效选项", all_text.contains("原声") and all_text.contains("静音"))
	_check("设置页可持久化入口", app != null and app.has_method("save_settings"))
	inspector.queue_free()


func _audit_source() -> void:
	var main_text := FileAccess.get_file_as_string("res://charter/main.gd")
	var canvas_text := FileAccess.get_file_as_string("res://charter/chart_canvas.gd")
	var preview_text := FileAccess.get_file_as_string("res://charter/preview_3d.gd")
	var inspector_text := FileAccess.get_file_as_string("res://charter/inspector.gd")
	var workspace_text := FileAccess.get_file_as_string("res://charter/ring_workspace.gd")
	_check("工具 1–7", main_text.contains("KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7"))
	_check("边界 B/事件 E", main_text.contains("KEY_B") and main_text.contains("KEY_E"))
	_check("HUD H", main_text.contains("KEY_H"))
	_check("F5 试玩", main_text.contains("KEY_F5"))
	_check("波形/时间轴", canvas_text.contains("_draw_waveform") and canvas_text.contains("_draw_notes"))
	_check("Path 预览绘制", preview_text.contains("_draw_one_path"))
	_check("框选", canvas_text.contains("_finish_marquee"))
	_check("皮肤/特效设置", main_text.contains("_sync_appearance"))
	var hold_start := preview_text.find("func _draw_holds(")
	var hold_end := preview_text.find("func _draw_notes(", hold_start)
	_check("Hold 体节点渲染", hold_start >= 0 and hold_end > hold_start and preview_text.substr(hold_start, hold_end - hold_start).contains("visual_pts"))
	_check("复制/粘贴快捷键", main_text.contains("KEY_C") and main_text.contains("KEY_V"))
	_check("全选快捷键", canvas_text.contains("KEY_A"))
	_check("镜像/旋转", main_text.contains("mirror") or main_text.contains("rotate_selected"))
	_check("Ctrl+滚轮缩放", canvas_text.contains("MOUSE_BUTTON_WHEEL"))
	_check("Alt+单击重叠循环", canvas_text.contains("alt_pressed"))
	_check("K 形变关键帧快捷键", main_text.contains("KEY_K"))
	# 回归：第二次打开环编辑器时预览必须重新挂进工作区，否则预览槽为空、
	# 关闭后主界面也回不来。
	_check("环编辑器可重复打开", not workspace_text.contains("preview != _preview"))
	_check("X 擦除快捷键", main_text.contains("KEY_X"))
	_check("Ctrl+Shift+V 视频属性", main_text.contains("KEY_V") and main_text.contains("ctrl_pressed") and main_text.contains("shift_pressed"))
	_check("Anchor 双锚点创建", inspector_text.contains("_add_anchor_pair"))
	_check("多语言切换", main_text.contains("TranslationServer") or FileAccess.file_exists("res://assets/translations"))
	_check("色盲/减少动效设置", main_text.contains("colorblind") or main_text.contains("reduce_motion"))
	if not (main_text.contains("KEY_C") and main_text.contains("KEY_V")):
		_part("编辑快捷键", "复制/粘贴只有检查器按钮，无 Ctrl+C/V 剪贴板")
	if not (main_text.contains("mirror") or main_text.contains("rotate_selected")):
		_part("选择变换", "无镜像/旋转")
	if not (main_text.contains("colorblind") or main_text.contains("reduce_motion")):
		_part("可访问性", "无色盲模式/减少动效/多语言")
	if not inspector_text.contains("_add_anchor_pair"):
		_part("Anchor 配对", "字段可手填，但没有双锚点一次创建工具")
