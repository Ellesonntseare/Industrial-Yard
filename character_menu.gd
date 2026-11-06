extends VBoxContainer

const Catalog = preload("res://characters_catalog.gd")
var arena: Node
var buttons: Dictionary = {}
var selected_label: Label

func setup(owner_arena: Node) -> void:
	arena = owner_arena
	var heading := Label.new()
	heading.text = "CHOOSE YOUR CHARACTER"
	heading.add_theme_font_size_override("font_size",15)
	add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	add_child(row)
	for id in Catalog.IDS:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(70,94)
		b.tooltip_text = Catalog.display_name(id)
		var path: String = Catalog.portrait_path(id)
		if ResourceLoader.exists(path): b.icon = load(path)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = Catalog.display_name(id)
		b.add_theme_font_size_override("font_size",11)
		b.pressed.connect(func(): arena.select_character(id); refresh())
		row.add_child(b)
		buttons[id] = b
	selected_label = Label.new()
	selected_label.add_theme_font_size_override("font_size",14)
	add_child(selected_label)
	refresh()

func refresh() -> void:
	if not arena:return
	for id in buttons:
		buttons[id].set_pressed_no_signal(id==arena.selected_character)
		buttons[id].modulate = Color("8deaf2") if id==arena.selected_character else Color.WHITE
	selected_label.text = "YOUR CHARACTER: " + Catalog.display_name(arena.selected_character)
