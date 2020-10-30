tool
extends Control
const FlowChartNode = preload("FlowChartNode.gd")
const FlowChartNodeScene = preload("FlowChartNode.tscn")
const FlowChartLine = preload("FlowChartLine.gd")
const FlowChartLineScene = preload("FlowChartLine.tscn")

signal connection(from, to)
signal disconnection(from, to)
signal node_selected(node)
signal node_unselected(node)

export var scroll_margin = 100
export var interconnection_offset = 10

var _Lines # Node that hold all lines
var _connections = {}
var _is_connecting = false
var _current_connection
var _moving_node
var _mouse_offset = Vector2.ZERO


func _ready():
	if Engine.editor_hint:
		return

	_Lines = Control.new()
	_Lines.name = "Lines"
	add_child(_Lines)
	move_child(_Lines, 0) # Make sure lines always behind nodes

	for child in get_children():
		if child is FlowChartNode:
			_init_node_signals(child)

func add_child(node, legible_unique_name=false):
	.add_child(node, legible_unique_name)
	_init_node_signals(node)

func _init_node_signals(node):
	node.connect("focus_entered", self, "_on_node_focused_entered", [node])
	node.connect("focus_exited", self, "_on_node_focused_exited", [node])

func _unhandled_key_input(event):
	match event.scancode:
		KEY_DELETE:
			var selected = get_selected()
			if selected:
				if selected is FlowChartLine:
					# TODO: More efficient way to get connection from Line node
					for connections_from in _connections.values():
						for connection in connections_from.values():
							if connection.line == selected:
								disconnect_node(connection.from_node.name, connection.to_node.name)
								return
				elif selected is FlowChartNode:
					for connection_pair in get_connection_list():
						if connection_pair.from == selected.name or connection_pair.to == selected.name:
							disconnect_node(connection_pair.from, connection_pair.to)
					selected.queue_free()

func _gui_input(event):
	if Engine.editor_hint:
		return

	if event is InputEventMouseButton:
		var hit_node
		for i in get_child_count():
			var child = get_child(get_child_count()-1 - i) # Inverse order to check from top to bottom of canvas
			if child is FlowChartNode:
				if child.get_rect().has_point(event.position):
					hit_node = child
					break

		match event.button_index:
			BUTTON_LEFT:
				if event.pressed:
					if hit_node:
						# Select node
						hit_node.grab_focus()
						move_child(hit_node, get_child_count()-1) # Raise selected node to top
						if event.shift:
							# Connection start
							prints("start", hit_node.name)
							var line = create_line_instance()
							var connection = Connection.new(line, hit_node, null)
							_connect_node(line, connection.get_from_pos(), get_local_mouse_position())
							_current_connection = connection
						else:
							# Move node
							_moving_node = hit_node
							_mouse_offset = _moving_node.rect_position - event.position
					else:
						var focus_owner = get_focus_owner()
						if focus_owner:
							focus_owner.release_focus()
				else:
					if _current_connection:
						if hit_node:
							# Connection end
							_disconnect_node(_current_connection.line)
							_current_connection.to_node = hit_node
							connect_node(_current_connection.from_node.name, _current_connection.to_node.name)
						else:
							_current_connection.line.queue_free()
					_current_connection = null
					_moving_node = null
					_mouse_offset = Vector2.ZERO

func _process(_delta):
	if Engine.editor_hint:
		return

	if _current_connection:
		_current_connection.line.join(_current_connection.get_from_pos(), get_local_mouse_position())
	if _moving_node: # TODO: Immediate dragging right after selected, cause ScrollContainer unable focus properly
		_moving_node.rect_position =  get_local_mouse_position() + _mouse_offset
		rect_min_size = get_minimum_size() # Update minimum size so ScrollContainer can handle scrolling
		for from in _connections:
			var connections_from = _connections[from]
			for to in connections_from:
				if from == _moving_node.name or to == _moving_node.name:
					var connection = _connections[from][to]
					connection.join()

func _get_minimum_size():
	var rect = Rect2()
	for child in get_children():
		rect = rect.merge(child.get_rect())
	rect = rect.grow(scroll_margin)
	return rect.size

func _on_node_focused_entered(node):
	prints("focus", node.name)
	emit_signal("node_selected", node)

func _on_node_focused_exited(node):
	prints("unfocus", node.name)
	emit_signal("node_unselected", node)

func _connect_node(line, from_pos, to_pos):
	_Lines.add_child(line)
	line.join(from_pos, to_pos)

func _disconnect_node(line):
	_Lines.remove_child(line)
	line.queue_free()

func create_line_instance():
	return FlowChartLineScene.instance()

func connect_node(from, to):
	var connections_from = _connections.get(from)
	if connections_from:
		if to in connections_from:
			return # Connection existed
	var line = create_line_instance()
	var connection = Connection.new(line, get_node(from), get_node(to))
	if not connections_from:
		connections_from = {}
		_connections[from] = connections_from
	connections_from[to] = connection
	_connect_node(line, connection.get_from_pos(), connection.get_to_pos())

	# Check if connection in both ways
	connections_from = _connections.get(to)
	if connections_from:
		var inv_connection = connections_from.get(from)
		if inv_connection:
			connection.offset = interconnection_offset
			inv_connection.offset = interconnection_offset
			connection.join()
			inv_connection.join()
	emit_signal("connection", from, to)

func disconnect_node(from, to):
	var connections_from = _connections.get(from)
	var connection = connections_from.get(to)
	if not connection:
		return

	_disconnect_node(connection.line)
	if connections_from.size() == 1:
		_connections.erase(from)
	else:
		connections_from.erase(to)

	connections_from = _connections.get(to)
	if connections_from:
		var inv_connection = connections_from[from]
		if inv_connection:
			inv_connection.offset = 0
			inv_connection.join()
	emit_signal("disconnection", from, to)

func clear_connections():
	for connections_from in _connections.values():
		for connection in connections_from.values():
			connection.line.queue_free()
	_connections.clear()

func get_connection_list():
	var connection_list = []
	for connections_from in _connections.values():
		for connection in connections_from.values():
			connection_list.append({"from": connection.from_node.name, "to": connection.to_node.name})
	return connection_list

func get_selected():
	var focused_owner = get_focus_owner()
	if focused_owner:
		if focused_owner.get_parent() == self or focused_owner.get_parent() == _Lines:
			return focused_owner
	return null

func set_selected(node):
	node.grab_focus()

class Connection:
	var line # Control node that draw line
	var from_node
	var to_node
	var offset = 0

	func _init(p_line, p_from_node, p_to_node):
		line = p_line
		from_node = p_from_node
		to_node = p_to_node

	func join():
		line.join(get_from_pos(), get_to_pos(), offset)

	func get_from_pos():
		return from_node.rect_position + from_node.rect_size / 2

	func get_to_pos():
		return to_node.rect_position + to_node.rect_size / 2 if to_node else line.rect_position
