extends Node2D

const GREEN_TOWN = preload("res://Art/Temp/LMO/green_town.png")
const GREEN_FARM = preload("res://Art/Temp/LMO/green_farm.png")

var tileStrength: int

@onready var texture_rect: TextureRect = $TextureRect
@export var tileResource: Tile

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	texture_rect.texture = tileResource.background
	tileStrength = 1

func get_state():
	return tileResource.state

func set_state(new_state):
	#print("updating state to " + new_state)
	tileResource.set_tile_type(new_state)
	match new_state:
		"farm":
			texture_rect.texture = GREEN_FARM
		"town":
			texture_rect.texture = GREEN_TOWN
