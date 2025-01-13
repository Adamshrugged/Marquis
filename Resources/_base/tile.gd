extends Resource
class_name Tile

@export var is_occupied: bool = false
@export var background: Texture
@export var state = "empty" # States: "empty", "farm", "town"

func set_tile_type(new_type: String):
	state = new_type
	is_occupied = new_type != "empty"
