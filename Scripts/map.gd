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
	for i in range(soldiers.size()):
		var soldier = soldiers[i]

		# Find a target if none exists
		if soldier.target_tile == null:
			var found = soldier.find_target_tile(tiles, grid_size)
			if not found:
				#print("No valid target for soldier at:", soldier.position)
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

		# Check for collisions with other soldiers
		for j in range(soldiers.size()):
			if i == j:
				continue  # Skip self-check

			var other_soldier = soldiers[j]
			if soldier.position == other_soldier.position:
				soldier.combine_with(other_soldier)
				soldiers.erase(j)  # Remove the combined soldier
				break




func getSoldierCount() -> int:
	return soldiers.size()

func rulersGrow() -> void:
	#print("growing rulers")
	for ruler in rulers:
		ruler.strength += 10
		if ruler.strength >= 100:
			ruler.strength -= 100
			spawn_soldiers(ruler)
			#print("spawning soliders at ruler")

func grow() -> int:
	var taxIncome = 0
	for row in tiles:
		for tile in row:
			var tileType = tile.get_state()
			if tileType == "town" or tileType == "farm":
				tile.tileStrength += 1
				if tile.tileStrength > 255:
					tile.tileStrength = 255
				taxIncome += tile.tileStrength
			if tileType == "town":
				var neighbors = get_neighbors(tile)
				var farmCount = getAdjCount(neighbors, "farm")
				#print( "Farms: " + str(farmCount) )
				print("Farm count: %s" % str(farmCount))
				tile.tileStrength += farmCount
				# Check if open slots
				if getAdjCount(neighbors, "empty") > 0:
					print("Str: %s" % str(tile.tileStrength))
					if tile.tileStrength > GameManager.farmStengthCost:
						if GameManager.money > GameManager.farmCost:
							GameManager.money -= GameManager.farmCost
							tile.tileStrength -= GameManager.farmStengthCost
							# Pick a random neighbor tile to build a tile
							neighbors.pick_random().set_state("farm")
	return taxIncome * GameManager.tax_rate / 1000

func getAdjCount(tiles, type):
	var farmCount = 0
	for tile in tiles:
		if tile.get_state() == type:
			farmCount += 1
	return farmCount


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
