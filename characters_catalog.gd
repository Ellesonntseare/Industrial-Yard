extends RefCounted

const IDS := ["soldier", "cyborg", "android", "man", "ninja"]
const NAMES := {"soldier":"Soldier", "cyborg":"Cyborg", "android":"Porcelain Android", "man":"Casual Man", "ninja":"Ninja"}

static func valid(id: String) -> bool:
	return id in IDS

static func model_path(id: String) -> String:
	return "res://assets/characters/%s.glb" % (id if valid(id) else "soldier")

static func portrait_path(id: String) -> String:
	return "res://assets/characters/portraits/%s.png" % (id if valid(id) else "soldier")

static func display_name(id: String) -> String:
	return NAMES.get(id,"Soldier")

static func ids() -> Array[String]:
	var result: Array[String] = []
	result.assign(IDS)
	return result

static func name_for(id: String) -> String:
	return display_name(id)

static func scene_for(id: String) -> PackedScene:
	return load(model_path(id)) as PackedScene
