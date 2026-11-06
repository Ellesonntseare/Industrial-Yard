extends RefCounted

const DEFINITIONS := {
	"carbine": {"name": "CARBINE", "magazine": 30, "damage": 26.0, "interval": 0.12, "reload": 1.8, "range": 220.0, "pellets": 1, "spread": 0.004},
	"ak47": {"name": "AK RIFLE", "magazine": 30, "damage": 31.0, "interval": 0.14, "reload": 2.2, "range": 210.0, "pellets": 1, "spread": 0.008},
	"pistol": {"name": "PISTOL", "magazine": 12, "damage": 24.0, "interval": 0.28, "reload": 1.35, "range": 100.0, "pellets": 1, "spread": 0.006},
	"shotgun": {"name": "PUMP SHOTGUN", "magazine": 6, "damage": 12.0, "interval": 0.9, "reload": 2.8, "range": 45.0, "pellets": 8, "spread": 0.065},
	"knife": {"name": "COMBAT KNIFE", "magazine": 1, "damage": 45.0, "interval": 0.55, "reload": 0.0, "range": 2.1, "pellets": 1, "spread": 0.0},
	"smg": {"name": "MP5 SMG", "magazine": 32, "damage": 17.0, "interval": 0.085, "reload": 1.55, "range": 105.0, "pellets": 1, "spread": 0.016},
	"battle_rifle": {"name": "SCAR BATTLE RIFLE", "magazine": 20, "damage": 38.0, "interval": 0.22, "reload": 2.35, "range": 255.0, "pellets": 1, "spread": 0.006},
	"marksman": {"name": "SVD MARKSMAN", "magazine": 10, "damage": 62.0, "interval": 0.63, "reload": 2.65, "range": 320.0, "pellets": 1, "spread": 0.002},
}
const MODEL_DIRECTORY := "res://assets/items/tactical/"
static var model_cache: Dictionary = {}

static func definition(id: String) -> Dictionary:
	return DEFINITIONS.get(id, DEFINITIONS.carbine).duplicate()

static func ids() -> Array:
	return DEFINITIONS.keys()

static func create_world_model(id: String) -> Node3D:
	var chosen := id if DEFINITIONS.has(id) else "carbine"
	var model := create_item_model(MODEL_DIRECTORY + chosen + ".glb")
	if model and chosen == "knife": model.rotation.x = -PI * 0.5
	return model

static func create_item_model(path: String) -> Node3D:
	if not model_cache.has(path):
		model_cache[path] = load(path) as PackedScene
	var packed := model_cache[path] as PackedScene
	if not packed:
		push_error("Missing item model: " + path)
		return null
	var model := packed.instantiate() as Node3D
	model.name = path.get_file().get_basename()
	return model
