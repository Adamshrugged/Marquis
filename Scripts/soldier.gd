extends CharacterBody2D

var target_tile: Node2D
@export var tile_size = 32

func find_target_tile(tiles, grid_size) -> bool:
	# BFS to find a valid tile for a town
	var soldier_tile_position = position / tile_size
	var x = int(soldier_tile_position.x)
	var y = int(soldier_tile_position.y)

	var visited = []
	var queue = [Vector2(x, y)]
	while queue.size() > 0:
		var current = queue.pop_front()
		var current_x = int(current.x)
		var current_y = int(current.y)

		if current in visited:
			continue
		visited.append(current)

		var tile = tiles[current_x][current_y]
		if tile.get_state() in ["empty", "farm"] and not is_adjacent_to_town(tile, tiles, grid_size):
			target_tile = tile
			return true

		# Add neighbors
		for direction in [
			Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)
		]:
			var neighbor_x = current_x + int(direction.x)
			var neighbor_y = current_y + int(direction.y)
			if neighbor_x >= 0 and neighbor_x < grid_size.x and neighbor_y >= 0 and neighbor_y < grid_size.y:
				var neighbor = Vector2(neighbor_x, neighbor_y)
				if neighbor not in visited:
					queue.append(neighbor)

	return false

func is_adjacent_to_town(tile, tiles, grid_size) -> bool:
	# Check if any of the 8 neighbors is a town
	var tile_position = tile.position / tile_size
	var x = int(tile_position.x)
	var y = int(tile_position.y)
	for direction in [
		Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
		Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)
	]:
		var neighbor_x = x + int(direction.x)
		var neighbor_y = y + int(direction.y)
		if neighbor_x >= 0 and neighbor_x < grid_size.x and neighbor_y >= 0 and neighbor_y < grid_size.y:
			var neighbor_tile = tiles[neighbor_x][neighbor_y]
			if neighbor_tile.get_state() == "town":
				return true
	return false

func move_to_target() -> bool:
	if target_tile == null:
		return false

	var move_direction = (target_tile.position - position).normalized()
	move_direction.x = sign(move_direction.x)
	move_direction.y = sign(move_direction.y)
	position += move_direction * tile_size

	# Check if reached the target
	if position == target_tile.position:
		return true
	return false
