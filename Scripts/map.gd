extends Node2D

@export var soldier_scene: PackedScene = preload("res://Scenes/soldier.tscn")
var soldiers: Array = []
var rulers: Array = []
var tiles: Array = []


@export var grid_size = Vector2(10, 10) # Map dimensions
@export var tile_size = 32


func getRulerStrength() -> int:
	return rulers[0].strength

func getCount(type) -> int:
	var tileCount: int = 0
	for row in tiles:
		for tile in row:
			if tile.get_state() == type:
				tileCount += 1
	return tileCount

func moveSoldiers() -> void:
	for soldier in soldiers:
		# Find a target if none exists
		if soldier.target_tile == null:
			var found = soldier.find_target_tile(tiles, grid_size)
			if not found:
				print("No valid target for soldier at:", soldier.position)
				continue

		# Move soldier toward the target
		var reached = soldier.move_to_target()
		if reached:
			# Check if the soldier can build a town
			if GameManager.money >= GameManager.townCost and soldier.target_tile.get_state() in ["empty", "farm"]:
				soldier.target_tile.set_state("town")
				GameManager.money -= GameManager.townCost
			else:
				print("Cannot build town: Not enough money or invalid location")
			soldier.target_tile = null  # Clear the target after action



func getSoldierCount() -> int:
	return soldiers.size()

func rulersGrow() -> void:
	print("growing rulers")
	for ruler in rulers:
		ruler.strength += 10
		if ruler.strength >= 100:
			ruler.strength -= 100
			spawn_soldiers(ruler)
			print("spawning soliders at ruler")

func grow() -> int:
	for row in tiles:
		for tile in row:
			if tile.get_state() == "farm":
				tile.tileStrength += 1
				if tile.tileStrength > 255:
					tile.tileStrength = 1
	return 1

func spawn_soldiers(parentScene):
	var soldier = soldier_scene.instantiate()
	soldier.position = parentScene.position
	add_child(soldier)
	soldiers.append(soldier)

func is_tile_valid_for_town(tile: Node2D) -> bool:
	var neighbors = get_neighbors(tile)
	for neighbor in neighbors:
		if neighbor.tile_type == "town":
			return false
	return true

# TODO - return all tiles neighbording current tile
func get_neighbors(tile: Node2D) -> Array:
	var neighbors = []
	var tile_position = tile.position / tile_size
	var x = int(tile_position.x)
	var y = int(tile_position.y)

	# Define the relative positions of neighbors (N, E, S, W)
	var directions = [
		Vector2(-1, 0),  # West
		Vector2(1, 0),   # East
		Vector2(0, -1),  # North
		Vector2(0, 1),   # South
		Vector2(-1, -1), # NorthWest
		Vector2(1, -1),  # NorthEast
		Vector2(-1, 1),  # SouthWest
		Vector2(1, 1)    # SouthEast
	]

	for direction in directions:
		var neighbor_x = x + int(direction.x)
		var neighbor_y = y + int(direction.y)

		# Check if the neighbor is within bounds
		if neighbor_x >= 0 and neighbor_x < grid_size.x and neighbor_y >= 0 and neighbor_y < grid_size.y:
			neighbors.append(tiles[neighbor_x][neighbor_y])

	return neighbors


func initialize_map():
	for x in range(grid_size.x):
		var row = []
		for y in range(grid_size.y):
			var tile = preload("res://Scenes/tile.tscn").instantiate()
			tile.position = Vector2(x, y) * tile_size
			tile.tileResource.state = "empty"
			add_child(tile)
			row.append(tile)
		tiles.append(row)

func spawn_ruler():
	var ruler = preload("res://Scenes/ruler.tscn").instantiate()
	ruler.position = Vector2(2, 2) * tile_size
	add_child(ruler)
	rulers.append(ruler)

func _process(_delta: float) -> void:
	pass
	#print( "Farms: %d" % getCount("farm") )

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
