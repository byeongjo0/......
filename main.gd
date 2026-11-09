extends Node2D

const GRID_SIZE: int = 64
const UI_WIDTH: int = 190

const BELT_SPEED: float = 1.2
const MINING_INTERVAL: float = 2.0
const SMELTING_TIME: float = 4.0

const POWER_PER_PLANT: int = 10
const COAL_BURN_INTERVAL: float = 6.0

const MINER_POWER: int = 2
const FURNACE_POWER: int = 3

const POLE_CONNECTION_RANGE: int = 4
const BUILDING_CONNECTION_RANGE: int = 2

const BUILD_COSTS: Dictionary = {
	"채굴기": 5,
	"용광로": 10,
	"발전기": 8,
	"컨베이어": 1,
	"창고": 15,
	"석탄 광산": 8,
	"석탄 발전소": 10,
	"전봇대": 3
}

const BASE_STORAGE: int = 50
const WAREHOUSE_CAPACITY: int = 100

var iron_ingots: int = 30

var total_ore_mined: int = 0
var total_coal_mined: int = 0
var total_ingots_produced: int = 0
var total_ingots_spent: int = 0

var power_output: int = 0
var power_demand: int = 0
var power_used: int = 0
var power_remaining: int = 0
var power_shortage: int = 0
var power_available: bool = false

var powered_poles: Dictionary = {}
var powered_buildings: Dictionary = {}

var starter_fuel_given: bool = false

var buildings: Dictionary = {}
var belts: Dictionary = {}
var items: Array = []

var selected_building: String = "채굴기"

var dragging_belt: bool = false
var last_drag_cell: Vector2i = Vector2i.ZERO
var drag_direction: Vector2i = Vector2i.RIGHT

var miner_timers: Dictionary = {}

var furnace_ore: Dictionary = {}
var furnace_ingots: Dictionary = {}
var furnace_timers: Dictionary = {}

var power_plant_coal: Dictionary = {}
var power_plant_timers: Dictionary = {}

var mouse_cell: Vector2i = Vector2i.ZERO
var mouse_in_game: bool = false

# STEP 19: 전력 범위 표시
var show_power_ranges: bool = true

# STEP 21: 전봇대 마우스 오버 및 전력망 강조 표시
var hovered_pole_cell: Vector2i = Vector2i.ZERO
var has_hovered_pole: bool = false

# 통합 업데이트: 연구, 저장, 자동 저장
var research_panel_open: bool = false
var research_points: int = 0
var mining_research_level: int = 0
var smelting_research_level: int = 0
var fuel_research_level: int = 0
var autosave_timer: float = 0.0
const AUTOSAVE_INTERVAL: float = 60.0
const SAVE_PATH: String = "user://nova_industria_save.json"
var save_message: String = ""
var save_message_timer: float = 0.0


func _ready() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	update_power_plants(delta)
	calculate_power()

	update_miners(delta)
	update_items(delta)
	update_furnaces(delta)

	autosave_timer += delta
	if autosave_timer >= AUTOSAVE_INTERVAL:
		autosave_timer = 0.0
		save_game()

	if save_message_timer > 0.0:
		save_message_timer = maxf(0.0, save_message_timer - delta)
		if save_message_timer == 0.0:
			save_message = ""

	queue_redraw()


func _input(event: InputEvent) -> void:
	# V 키로 전력 범위 표시 전환
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_V:
				show_power_ranges = not show_power_ranges
				queue_redraw()
			elif event.keycode == KEY_R:
				research_panel_open = not research_panel_open
				queue_redraw()
			elif event.keycode == KEY_F5:
				save_game()
			elif event.keycode == KEY_F9:
				load_game()
			elif research_panel_open and event.keycode == KEY_1:
				buy_research("채굴 효율")
			elif research_panel_open and event.keycode == KEY_2:
				buy_research("제련 기술")
			elif research_panel_open and event.keycode == KEY_3:
				buy_research("연료 효율")

	if event is InputEventMouseMotion:
		mouse_cell = get_grid_cell(event.position)
		mouse_in_game = event.position.x >= UI_WIDTH
		update_hovered_pole()

		if dragging_belt and mouse_in_game:
			handle_belt_drag(mouse_cell)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.position.x < UI_WIDTH:
					select_from_menu(event.position)
				else:
					mouse_cell = get_grid_cell(event.position)
					mouse_in_game = true
					update_hovered_pole()

					if selected_building == "컨베이어":
						dragging_belt = true
						last_drag_cell = mouse_cell
						place_belt(mouse_cell, drag_direction)
					else:
						place_building(mouse_cell)
			else:
				dragging_belt = false


# --------------------------------
# 좌표 및 메뉴
# --------------------------------

func get_grid_cell(pos: Vector2) -> Vector2i:
	var x: int = int(floor((pos.x - UI_WIDTH) / GRID_SIZE))
	var y: int = int(floor(pos.y / GRID_SIZE))
	return Vector2i(x, y)


func grid_to_screen(cell: Vector2i) -> Vector2:
	return Vector2(
		UI_WIDTH + cell.x * GRID_SIZE + GRID_SIZE / 2.0,
		cell.y * GRID_SIZE + GRID_SIZE / 2.0
	)


func grid_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func update_hovered_pole() -> void:
	has_hovered_pole = false

	if not mouse_in_game:
		return

	if buildings.get(mouse_cell, "") == "전봇대":
		hovered_pole_cell = mouse_cell
		has_hovered_pole = true


func select_from_menu(pos: Vector2) -> void:
	if pos.y >= 86 and pos.y < 120:
		selected_building = "채굴기"
	elif pos.y >= 126 and pos.y < 160:
		selected_building = "석탄 광산"
	elif pos.y >= 166 and pos.y < 200:
		selected_building = "용광로"
	elif pos.y >= 206 and pos.y < 240:
		selected_building = "발전기"
	elif pos.y >= 246 and pos.y < 280:
		selected_building = "석탄 발전소"
	elif pos.y >= 286 and pos.y < 320:
		selected_building = "컨베이어"
	elif pos.y >= 326 and pos.y < 360:
		selected_building = "창고"
	elif pos.y >= 366 and pos.y < 400:
		selected_building = "전봇대"


# --------------------------------
# 자원 및 건물 설치
# --------------------------------

func get_storage_capacity() -> int:
	var warehouse_count: int = 0

	for cell in buildings.keys():
		if buildings[cell] == "창고":
			warehouse_count += 1

	return BASE_STORAGE + warehouse_count * WAREHOUSE_CAPACITY


func get_total_coal() -> int:
	var total: int = 0

	for cell in power_plant_coal.keys():
		total += power_plant_coal[cell]

	return total


func place_building(cell: Vector2i) -> void:
	if buildings.has(cell) or belts.has(cell):
		return

	var cost: int = BUILD_COSTS[selected_building]

	if iron_ingots < cost:
		return

	iron_ingots -= cost
	total_ingots_spent += cost

	buildings[cell] = selected_building

	if selected_building == "채굴기":
		miner_timers[cell] = 0.0

	if selected_building == "석탄 광산":
		miner_timers[cell] = 0.0

	if selected_building == "용광로":
		furnace_ore[cell] = 0
		furnace_ingots[cell] = 0
		furnace_timers[cell] = 0.0

	if selected_building == "석탄 발전소":
		power_plant_coal[cell] = 0
		power_plant_timers[cell] = 0.0

		if not starter_fuel_given:
			power_plant_coal[cell] = 5
			starter_fuel_given = true

	calculate_power()


func place_belt(cell: Vector2i, direction: Vector2i) -> void:
	if buildings.has(cell) or belts.has(cell):
		return

	var cost: int = BUILD_COSTS["컨베이어"]

	if iron_ingots < cost:
		return

	iron_ingots -= cost
	total_ingots_spent += cost

	belts[cell] = direction


func handle_belt_drag(cell: Vector2i) -> void:
	if cell == last_drag_cell:
		return

	var difference: Vector2i = cell - last_drag_cell

	if abs(difference.x) >= abs(difference.y):
		drag_direction = Vector2i.RIGHT if difference.x > 0 else Vector2i.LEFT
	else:
		drag_direction = Vector2i.DOWN if difference.y > 0 else Vector2i.UP

	var distance: int = abs(difference.x) + abs(difference.y)

	for i in range(1, distance + 1):
		var target: Vector2i = last_drag_cell + drag_direction * i
		place_belt(target, drag_direction)

	last_drag_cell = cell


# --------------------------------
# 전력망 계산
# --------------------------------

func has_pole_in_range(cell: Vector2i) -> bool:
	for other_cell in buildings.keys():
		if buildings[other_cell] != "전봇대":
			continue

		if grid_distance(cell, other_cell) <= POLE_CONNECTION_RANGE:
			return true

	return false


func calculate_power() -> void:
	power_output = 0
	power_demand = 0
	power_used = 0
	power_remaining = 0
	power_shortage = 0

	powered_poles.clear()
	powered_buildings.clear()

	var power_sources: Array[Vector2i] = []

	# 1. 연료가 있고 전봇대에 연결된 발전소의 발전량 합산
	for cell in buildings.keys():
		if buildings[cell] != "석탄 발전소":
			continue

		if power_plant_coal.get(cell, 0) <= 0:
			continue

		if has_pole_in_range(cell):
			power_output += POWER_PER_PLANT
			power_sources.append(cell)

	# 2. 발전소에 연결된 전봇대 찾기
	for source in power_sources:
		for pole_cell in buildings.keys():
			if buildings[pole_cell] != "전봇대":
				continue

			if grid_distance(source, pole_cell) <= POLE_CONNECTION_RANGE:
				powered_poles[pole_cell] = true

	# 3. 연결된 전봇대를 통해 전력망 확장
	var changed: bool = true

	while changed:
		changed = false

		for pole_cell in buildings.keys():
			if buildings[pole_cell] != "전봇대":
				continue

			if powered_poles.has(pole_cell):
				continue

			for connected_pole in powered_poles.keys():
				if grid_distance(pole_cell, connected_pole) <= POLE_CONNECTION_RANGE:
					powered_poles[pole_cell] = true
					changed = true
					break

	# 4. 전력망에 연결된 기계의 전체 요구량 계산
	for cell in buildings.keys():
		var demand: int = get_building_power_demand(cell)

		if demand > 0 and is_building_connected_to_grid(cell):
			power_demand += demand

	# 5. 우선순위에 따라 전력 배분
	# 1순위: 석탄 광산 / 2순위: 철광석 채굴기 / 3순위: 용광로
	var available_power: int = power_output

	for priority in range(1, 4):
		for cell in buildings.keys():
			if get_building_priority(cell) != priority:
				continue

			var demand: int = get_building_power_demand(cell)

			if demand <= 0 or not is_building_connected_to_grid(cell):
				continue

			if available_power >= demand:
				powered_buildings[cell] = true
				available_power -= demand
				power_used += demand

	power_remaining = available_power
	power_shortage = max(0, power_demand - power_used)
	power_available = power_shortage == 0


func get_building_power_demand(cell: Vector2i) -> int:
	var building_name: String = buildings.get(cell, "")

	if building_name == "채굴기" or building_name == "석탄 광산":
		return MINER_POWER

	if building_name == "용광로":
		return FURNACE_POWER

	return 0


func get_building_priority(cell: Vector2i) -> int:
	var building_name: String = buildings.get(cell, "")

	if building_name == "석탄 광산":
		return 1

	if building_name == "채굴기":
		return 2

	if building_name == "용광로":
		return 3

	return 99


func is_building_connected_to_grid(cell: Vector2i) -> bool:
	for pole_cell in powered_poles.keys():
		if grid_distance(cell, pole_cell) <= BUILDING_CONNECTION_RANGE:
			return true

	return false

func is_building_powered(cell: Vector2i) -> bool:
	return powered_buildings.has(cell)


# --------------------------------
# 발전소 및 석탄 연소
# --------------------------------

func update_power_plants(delta: float) -> void:
	for cell in buildings.keys():
		if buildings[cell] != "석탄 발전소":
			continue

		var coal: int = power_plant_coal.get(cell, 0)
		var timer: float = power_plant_timers.get(cell, 0.0)

		if coal > 0 and has_pole_in_range(cell):
			timer += delta

			while timer >= COAL_BURN_INTERVAL and coal > 0:
				timer -= COAL_BURN_INTERVAL * (1.0 + float(fuel_research_level) * 0.2)
				coal -= 1
		elif coal <= 0:
			timer = 0.0

		power_plant_coal[cell] = coal
		power_plant_timers[cell] = timer


# --------------------------------
# 채굴
# --------------------------------

func update_miners(delta: float) -> void:
	for cell in buildings.keys():
		var building_name: String = buildings[cell]

		if building_name != "채굴기" and building_name != "석탄 광산":
			continue

		if not is_building_powered(cell):
			continue

		var timer: float = miner_timers.get(cell, 0.0)
		timer += delta

		if timer >= MINING_INTERVAL / (1.0 + float(mining_research_level) * 0.2):
			if building_name == "채굴기":
				if try_spawn_resource(cell, "철광석"):
					timer = 0.0
				else:
					timer = MINING_INTERVAL / (1.0 + float(mining_research_level) * 0.2)

			elif building_name == "석탄 광산":
				if try_spawn_resource(cell, "석탄"):
					timer = 0.0
				else:
					timer = MINING_INTERVAL / (1.0 + float(mining_research_level) * 0.2)

		miner_timers[cell] = timer


func try_spawn_resource(miner_cell: Vector2i, resource_type: String) -> bool:
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.UP
	]

	for direction in directions:
		var belt_cell: Vector2i = miner_cell + direction

		if belts.has(belt_cell):
			if belts[belt_cell] == direction:
				items.append({
					"cell": belt_cell,
					"progress": 0.0,
					"type": resource_type
				})

				if resource_type == "철광석":
					total_ore_mined += 1
				elif resource_type == "석탄":
					total_coal_mined += 1

				return true

	return false


# --------------------------------
# 컨베이어 및 자원 이동
# --------------------------------

func update_items(delta: float) -> void:
	for i in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[i]

		var current_cell: Vector2i = item["cell"]
		var progress: float = item["progress"]
		var resource_type: String = item["type"]

		progress += BELT_SPEED * delta

		var remove_item: bool = false

		while progress >= 1.0:
			progress -= 1.0

			if not belts.has(current_cell):
				remove_item = true
				break

			var next_cell: Vector2i = current_cell + belts[current_cell]

			if belts.has(next_cell):
				current_cell = next_cell

			elif buildings.has(next_cell):
				var target_building: String = buildings[next_cell]

				if resource_type == "철광석" and target_building == "용광로":
					furnace_ore[next_cell] = furnace_ore.get(next_cell, 0) + 1

				elif resource_type == "석탄" and target_building == "석탄 발전소":
					power_plant_coal[next_cell] = power_plant_coal.get(next_cell, 0) + 1

				remove_item = true
				break

			else:
				remove_item = true
				break

		if remove_item:
			items.remove_at(i)
		else:
			item["cell"] = current_cell
			item["progress"] = progress
			items[i] = item


# --------------------------------
# 용광로
# --------------------------------

func update_furnaces(delta: float) -> void:
	for cell in buildings.keys():
		if buildings[cell] != "용광로":
			continue

		if not is_building_powered(cell):
			continue

		var ore: int = furnace_ore.get(cell, 0)
		var timer: float = furnace_timers.get(cell, 0.0)

		if ore > 0 and iron_ingots < get_storage_capacity():
			timer += delta

			if timer >= SMELTING_TIME / (1.0 + float(smelting_research_level) * 0.2):
				furnace_ore[cell] -= 1
				furnace_ingots[cell] = furnace_ingots.get(cell, 0) + 1

				iron_ingots += 1
				total_ingots_produced += 1
				research_points += 1

				timer = 0.0
		else:
			timer = 0.0

		furnace_timers[cell] = timer


# --------------------------------
# 화면 그리기
# --------------------------------

func _draw() -> void:
	draw_background()
	draw_grid()
	draw_power_ranges()
	draw_menu()
	draw_research_panel()
	draw_belts()
	draw_power_lines()
	draw_buildings()
	draw_hovered_power_network()
	draw_items()
	draw_mouse_highlight()


func draw_background() -> void:
	draw_rect(
		Rect2(0, 0, 1280, 720),
		Color("#26302e")
	)


func draw_grid() -> void:
	for x in range(0, 1200, GRID_SIZE):
		var screen_x: float = UI_WIDTH + x

		draw_line(
			Vector2(screen_x, 0),
			Vector2(screen_x, 720),
			Color("#394541"),
			1.0
		)

	for y in range(0, 720, GRID_SIZE):
		draw_line(
			Vector2(UI_WIDTH, y),
			Vector2(1280, y),
			Color("#394541"),
			1.0
		)


# --------------------------------
# STEP 19: 전력 범위 시각화
# --------------------------------

func draw_power_ranges() -> void:
	if not show_power_ranges:
		return

	for pole_cell in powered_poles.keys():
		# 전봇대의 전체 연결 범위
		for x in range(-POLE_CONNECTION_RANGE, POLE_CONNECTION_RANGE + 1):
			for y in range(-POLE_CONNECTION_RANGE, POLE_CONNECTION_RANGE + 1):
				if abs(x) + abs(y) > POLE_CONNECTION_RANGE:
					continue

				var target_cell: Vector2i = pole_cell + Vector2i(x, y)
				var target_pos: Vector2 = grid_to_screen(target_cell)

				draw_rect(
					Rect2(
						target_pos - Vector2(GRID_SIZE / 2.0, GRID_SIZE / 2.0),
						Vector2(GRID_SIZE, GRID_SIZE)
					),
					Color(0.25, 0.8, 0.45, 0.055)
				)

		# 기계에 전력을 공급하는 범위
		for x in range(-BUILDING_CONNECTION_RANGE, BUILDING_CONNECTION_RANGE + 1):
			for y in range(-BUILDING_CONNECTION_RANGE, BUILDING_CONNECTION_RANGE + 1):
				if abs(x) + abs(y) > BUILDING_CONNECTION_RANGE:
					continue

				var target_cell: Vector2i = pole_cell + Vector2i(x, y)
				var target_pos: Vector2 = grid_to_screen(target_cell)

				draw_rect(
					Rect2(
						target_pos - Vector2(30, 30),
						Vector2(60, 60)
					),
					Color(0.3, 0.65, 1.0, 0.08)
				)


# --------------------------------
# 메뉴
# --------------------------------

func draw_menu() -> void:
	draw_rect(
		Rect2(0, 0, UI_WIDTH, 720),
		Color("#171e1c")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 42),
		"NOVA INDUSTRIA",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		Color("#d9e6dc")
	)

	draw_line(
		Vector2(15, 60),
		Vector2(175, 60),
		Color("#53645a"),
		2.0
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 78),
		"BUILD MENU",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color("#91a69a")
	)

	draw_menu_button(86, "채굴기")
	draw_menu_button(126, "석탄 광산")
	draw_menu_button(166, "용광로")
	draw_menu_button(206, "발전기")
	draw_menu_button(246, "석탄 발전소")
	draw_menu_button(286, "컨베이어")
	draw_menu_button(326, "창고")
	draw_menu_button(366, "전봇대")

	draw_line(
		Vector2(15, 410),
		Vector2(175, 410),
		Color("#53645a"),
		2.0
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 432),
		"RESOURCE STATUS",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("#91a69a")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 455),
		"철괴: " + str(iron_ingots),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color("#e5c77c")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 475),
		"보관 한도: " + str(get_storage_capacity()),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("#d9e6dc")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 497),
		"석탄 재고: " + str(get_total_coal()),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("#d9e6dc")
	)

	var power_color: Color = Color("#e66b55")

	if power_shortage == 0:
		power_color = Color("#8ed18a")

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 521),
		"발전: " + str(power_output) + " kW",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		power_color
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 539),
		"소비: " + str(power_used) + " / " + str(power_demand),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("#d9e6dc")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 557),
		"잔여 전력: " + str(power_remaining),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("#8ed18a")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 575),
		"부족 전력: " + str(power_shortage),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("#e66b55") if power_shortage > 0 else Color("#d9e6dc")
	)

	var power_status: String = "전력 공급 정상"

	if power_demand == 0:
		power_status = "전력 소비 없음"
	elif power_shortage > 0:
		power_status = "우선순위에 따라 차단"

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 593),
		power_status,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		power_color
	)
	draw_line(
		Vector2(15, 610),
		Vector2(175, 610),
		Color("#53645a"),
		1.0
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 630),
		"PRODUCTION STATS",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("#91a69a")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 649),
		"철광석: " + str(total_ore_mined),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("#d9e6dc")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 666),
		"석탄: " + str(total_coal_mined),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("#d9e6dc")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 683),
		"철괴 생산: " + str(total_ingots_produced),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("#d9e6dc")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 700),
		"건설 소비: " + str(total_ingots_spent),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("#d9e6dc")
	)

	var range_status: String = "V: 범위 표시 ON"

	if not show_power_ranges:
		range_status = "V: 범위 표시 OFF"

	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 715),
		range_status,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("#a9c6a5")
	)


func draw_menu_button(y: int, label: String) -> void:
	var button_color: Color = Color("#46564d")

	if selected_building == label:
		button_color = Color("#728d72")

	draw_rect(
		Rect2(15, y, 160, 34),
		button_color
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(25, y + 23),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color("#ffffff")
	)


# --------------------------------
# 전력선 그리기
# --------------------------------

func draw_power_lines() -> void:
	# 발전소와 전봇대 사이의 실제 연결 관계를 항상 표시
	for source in buildings.keys():
		if buildings[source] != "석탄 발전소":
			continue

		for pole_cell in buildings.keys():
			if buildings[pole_cell] != "전봇대":
				continue

			if grid_distance(source, pole_cell) <= POLE_CONNECTION_RANGE:
				var line_color: Color = Color("#69756d")

				if powered_poles.has(pole_cell) and power_plant_coal.get(source, 0) > 0:
					line_color = Color("#e5d28b")

				draw_line(
					grid_to_screen(source) + Vector2(0, -15),
					grid_to_screen(pole_cell) + Vector2(0, -15),
					line_color,
					2.0
				)

	# 전봇대끼리의 연결 관계 표시
	for pole_cell in buildings.keys():
		if buildings[pole_cell] != "전봇대":
			continue

		for other_pole in buildings.keys():
			if buildings[other_pole] != "전봇대":
				continue

			if pole_cell == other_pole or not is_cell_before(pole_cell, other_pole):
				continue

			if grid_distance(pole_cell, other_pole) <= POLE_CONNECTION_RANGE:
				var line_color: Color = Color("#69756d")

				if powered_poles.has(pole_cell) and powered_poles.has(other_pole):
					line_color = Color("#e5d28b")

				draw_line(
					grid_to_screen(pole_cell) + Vector2(0, -15),
					grid_to_screen(other_pole) + Vector2(0, -15),
					line_color,
					2.0
				)


func get_hovered_power_network() -> Dictionary:
	var result: Dictionary = {
		"poles": {},
		"generators": {},
		"machines": {}
	}

	if not has_hovered_pole:
		return result

	# 마우스가 올라간 전봇대부터 연결된 전봇대를 탐색
	var network_poles: Dictionary = {hovered_pole_cell: true}
	var queue: Array[Vector2i] = [hovered_pole_cell]

	while not queue.is_empty():
		var current_pole: Vector2i = queue.pop_front()

		for candidate in buildings.keys():
			if buildings[candidate] != "전봇대":
				continue

			if network_poles.has(candidate):
				continue

			if grid_distance(current_pole, candidate) <= POLE_CONNECTION_RANGE:
				network_poles[candidate] = true
				queue.append(candidate)

	result["poles"] = network_poles

	# 해당 전봇대 네트워크에 닿는 발전소와 기계를 찾음
	for cell in buildings.keys():
		var building_name: String = buildings[cell]

		if building_name == "석탄 발전소":
			for pole_cell in network_poles.keys():
				if grid_distance(cell, pole_cell) <= POLE_CONNECTION_RANGE:
					result["generators"][cell] = true
					break

		elif get_building_power_demand(cell) > 0:
			for pole_cell in network_poles.keys():
				if grid_distance(cell, pole_cell) <= BUILDING_CONNECTION_RANGE:
					result["machines"][cell] = true
					break

	return result


func draw_hovered_power_network() -> void:
	if not has_hovered_pole:
		return

	var network: Dictionary = get_hovered_power_network()
	var network_poles: Dictionary = network["poles"]
	var network_generators: Dictionary = network["generators"]
	var network_machines: Dictionary = network["machines"]

	# 연결된 전봇대와 기계에 반투명 강조 표시
	for pole_cell in network_poles.keys():
		var pole_pos: Vector2 = grid_to_screen(pole_cell)
		draw_circle(pole_pos, 25.0, Color(0.25, 0.85, 1.0, 0.16))
		draw_arc(pole_pos, 29.0, 0.0, TAU, 32, Color("#55dfff"), 3.0)

	for generator_cell in network_generators.keys():
		var generator_pos: Vector2 = grid_to_screen(generator_cell)
		draw_rect(
			Rect2(generator_pos - Vector2(29, 29), Vector2(58, 58)),
			Color(0.25, 0.85, 1.0, 0.12)
		)
		draw_rect(
			Rect2(generator_pos - Vector2(29, 29), Vector2(58, 58)),
			Color("#55dfff"),
			false,
			2.0
		)

	for machine_cell in network_machines.keys():
		var machine_pos: Vector2 = grid_to_screen(machine_cell)
		draw_rect(
			Rect2(machine_pos - Vector2(29, 29), Vector2(58, 58)),
			Color(0.25, 0.85, 1.0, 0.12)
		)
		draw_rect(
			Rect2(machine_pos - Vector2(29, 29), Vector2(58, 58)),
			Color("#55dfff"),
			false,
			2.0
		)

	# 선택한 전봇대 네트워크의 전선을 밝은 청록색으로 덧그림
	for pole_cell in network_poles.keys():
		for other_pole in network_poles.keys():
			if pole_cell == other_pole or not is_cell_before(pole_cell, other_pole):
				continue

			if grid_distance(pole_cell, other_pole) <= POLE_CONNECTION_RANGE:
				draw_line(
					grid_to_screen(pole_cell) + Vector2(0, -15),
					grid_to_screen(other_pole) + Vector2(0, -15),
					Color("#55dfff"),
					4.0
				)

	for generator_cell in network_generators.keys():
		for pole_cell in network_poles.keys():
			if grid_distance(generator_cell, pole_cell) <= POLE_CONNECTION_RANGE:
				draw_line(
					grid_to_screen(generator_cell) + Vector2(0, -15),
					grid_to_screen(pole_cell) + Vector2(0, -15),
					Color("#55dfff"),
					4.0
				)


func is_cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.x < b.x:
		return true

	if a.x == b.x and a.y < b.y:
		return true

	return false


# --------------------------------
# 컨베이어
# --------------------------------

func draw_belts() -> void:
	for cell in belts.keys():
		var center: Vector2 = grid_to_screen(cell)
		var direction: Vector2i = belts[cell]

		draw_rect(
			Rect2(center - Vector2(25, 25), Vector2(50, 50)),
			Color("#39413e")
		)

		draw_rect(
			Rect2(center - Vector2(21, 8), Vector2(42, 16)),
			Color("#a18b55")
		)

		draw_line(
			center - Vector2(15, 0),
			center + Vector2(15, 0),
			Color("#e0c17b"),
			3.0
		)

		var arrow_end: Vector2 = center + Vector2(direction) * 17.0
		var perpendicular: Vector2 = Vector2(-direction.y, direction.x)

		var triangle: PackedVector2Array = [
			arrow_end + Vector2(direction) * 7.0,
			arrow_end - Vector2(direction) * 5.0 + perpendicular * 6.0,
			arrow_end - Vector2(direction) * 5.0 - perpendicular * 6.0
		]

		draw_colored_polygon(triangle, Color("#fff0bd"))


# --------------------------------
# 건물 그리기 및 전력 상태 표시
# --------------------------------

func draw_buildings() -> void:
	for cell in buildings.keys():
		var pos: Vector2 = grid_to_screen(cell)
		var building_name: String = buildings[cell]

		draw_pixel_building(pos, building_name)

		# 전력 소비 건물에 상태 표시
		if building_name == "채굴기" or building_name == "석탄 광산" or building_name == "용광로":
			var status_color: Color = Color("#e65e50")

			if is_building_powered(cell):
				status_color = Color("#72e08a")

			draw_rect(
				Rect2(pos + Vector2(16, -25), Vector2(10, 10)),
				status_color
			)

			# 전력 공급 우선순위 표시
			var priority_label: String = "P" + str(get_building_priority(cell))
			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-8, -30),
				priority_label,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				8,
				Color("#f1d58b")
			)

			var connection_label: String = "망 미연결"
			var connection_color: Color = Color("#e65e50")

			if is_building_connected_to_grid(cell):
				connection_label = "망 연결"
				connection_color = Color("#8ed18a")

			if is_building_connected_to_grid(cell) and not is_building_powered(cell):
				connection_label = "전력 부족"
				connection_color = Color("#e5a45b")

			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-25, 55),
				connection_label,
				HORIZONTAL_ALIGNMENT_CENTER,
				50,
				8,
				connection_color
			)

			# 공급 중인 건물은 은은한 초록색 표시
			if is_building_powered(cell):
				draw_rect(
					Rect2(pos - Vector2(25, 25), Vector2(50, 50)),
					Color(0.25, 0.9, 0.4, 0.10)
				)

		if building_name == "용광로":
			var ore: int = furnace_ore.get(cell, 0)
			var ingots: int = furnace_ingots.get(cell, 0)
			var timer: float = furnace_timers.get(cell, 0.0)

			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-29, 30),
				"광석 " + str(ore),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				Color("#e3c078")
			)

			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-29, 43),
				"생산 " + str(ingots),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				Color("#d4dce0")
			)

			if ore > 0 and is_building_powered(cell) and iron_ingots < get_storage_capacity():
				var progress: float = clampf(timer / (SMELTING_TIME / (1.0 + float(smelting_research_level) * 0.2)), 0.0, 1.0)

				draw_rect(
					Rect2(pos + Vector2(-23, -34), Vector2(46, 5)),
					Color("#493c32")
				)

				draw_rect(
					Rect2(pos + Vector2(-23, -34), Vector2(46 * progress, 5)),
					Color("#e9a04b")
				)

		elif building_name == "석탄 발전소":
			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-27, -31),
				"최대 " + str(POWER_PER_PLANT) + " kW",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				9,
				Color("#8ed18a")
			)

			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-27, 34),
				"석탄 " + str(power_plant_coal.get(cell, 0)),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				Color("#e0c17b")
			)

		elif building_name == "전봇대":
			var pole_status: String = "대기"
			var pole_color: Color = Color("#aaaaaa")

			if powered_poles.has(cell):
				pole_status = "연결"
				pole_color = Color("#8ed18a")

			draw_circle(
				pos + Vector2(0, -27),
				6.0,
				pole_color
			)

			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-17, 35),
				pole_status,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				10,
				pole_color
			)


			if has_hovered_pole and hovered_pole_cell == cell:
				draw_string(
					ThemeDB.fallback_font,
					pos + Vector2(-30, -43),
					"전력망 강조 중",
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					9,
				Color("#55dfff")
			)


func draw_pixel_building(pos: Vector2, building_name: String) -> void:
	if building_name == "채굴기":
		draw_rect(Rect2(pos - Vector2(25, 25), Vector2(50, 50)), Color("#596b5b"))
		draw_rect(Rect2(pos - Vector2(16, 16), Vector2(32, 32)), Color("#a9b3a1"))
		draw_rect(Rect2(pos - Vector2(7, 7), Vector2(14, 14)), Color("#39443c"))
		draw_rect(Rect2(pos + Vector2(-4, -28), Vector2(8, 12)), Color("#d3b56b"))

	elif building_name == "석탄 광산":
		draw_rect(Rect2(pos - Vector2(25, 25), Vector2(50, 50)), Color("#343b3b"))
		draw_rect(Rect2(pos - Vector2(18, -1), Vector2(36, 36)), Color("#59636a"))
		draw_rect(Rect2(pos - Vector2(12, -7), Vector2(24, 24)), Color("#24292d"))
		draw_rect(Rect2(pos - Vector2(5, -10), Vector2(10, 18)), Color("#a6a6a0"))
		draw_rect(Rect2(pos + Vector2(-20, -20), Vector2(40, 5)), Color("#d0a45d"))

	elif building_name == "용광로":
		draw_rect(Rect2(pos - Vector2(25, 25), Vector2(50, 50)), Color("#704b3c"))
		draw_rect(Rect2(pos - Vector2(16, 16), Vector2(32, 32)), Color("#a85e3c"))
		draw_rect(Rect2(pos - Vector2(8, 8), Vector2(16, 16)), Color("#f0a54e"))
		draw_rect(Rect2(pos - Vector2(4, 4), Vector2(8, 8)), Color("#ffe19a"))

	elif building_name == "발전기":
		draw_rect(Rect2(pos - Vector2(25, 25), Vector2(50, 50)), Color("#485d69"))
		draw_rect(Rect2(pos - Vector2(16, 16), Vector2(32, 32)), Color("#829ba2"))
		draw_rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), Color("#e4c66f"))
		draw_rect(Rect2(pos + Vector2(-20, -29), Vector2(40, 6)), Color("#a9b8b5"))

	elif building_name == "석탄 발전소":
		draw_rect(Rect2(pos - Vector2(25, 25), Vector2(50, 50)), Color("#424b50"))
		draw_rect(Rect2(pos - Vector2(18, -1), Vector2(36, 34)), Color("#68777a"))
		draw_rect(Rect2(pos - Vector2(10, -9), Vector2(20, 22)), Color("#30383b"))
		draw_rect(Rect2(pos - Vector2(6, -6), Vector2(12, 12)), Color("#e49a48"))
		draw_rect(Rect2(pos + Vector2(-17, -29), Vector2(12, 12)), Color("#9ca8a5"))
		draw_rect(Rect2(pos + Vector2(5, -35), Vector2(12, 18)), Color("#7f8988"))

	elif building_name == "창고":
		draw_rect(Rect2(pos - Vector2(25, 25), Vector2(50, 50)), Color("#695c48"))
		draw_rect(Rect2(pos - Vector2(19, 17), Vector2(38, 34)), Color("#b18d58"))
		draw_rect(Rect2(pos - Vector2(4, 17), Vector2(8, 34)), Color("#72583c"))
		draw_rect(Rect2(pos + Vector2(-19, -21), Vector2(38, 5)), Color("#e0c28b"))

	elif building_name == "전봇대":
		draw_rect(Rect2(pos - Vector2(5, 25), Vector2(10, 50)), Color("#76634b"))
		draw_rect(Rect2(pos - Vector2(21, -10), Vector2(42, 6)), Color("#a58c65"))
		draw_rect(Rect2(pos - Vector2(17, -4), Vector2(5, 10)), Color("#d1c6a3"))
		draw_rect(Rect2(pos + Vector2(12, 4), Vector2(5, 10)), Color("#d1c6a3"))


# --------------------------------
# 아이템
# --------------------------------

func draw_items() -> void:
	for item in items:
		var cell: Vector2i = item["cell"]
		var progress: float = item["progress"]
		var resource_type: String = item["type"]

		var direction: Vector2i = belts.get(cell, Vector2i.ZERO)

		var start: Vector2 = grid_to_screen(cell)
		var end: Vector2 = start + Vector2(direction) * GRID_SIZE

		var item_position: Vector2 = start.lerp(end, progress)

		var item_color: Color = Color("#d8a64f")

		if resource_type == "석탄":
			item_color = Color("#282d30")

		draw_rect(
			Rect2(item_position - Vector2(7, 7), Vector2(14, 14)),
			item_color
		)

		if resource_type == "철광석":
			draw_rect(
				Rect2(item_position - Vector2(3, 3), Vector2(6, 6)),
				Color("#f5d58a")
			)
		else:
			draw_rect(
				Rect2(item_position - Vector2(3, 3), Vector2(6, 6)),
				Color("#777f82")
			)


# --------------------------------
# 마우스 표시
# --------------------------------

func draw_mouse_highlight() -> void:
	if not mouse_in_game:
		return

	var pos: Vector2 = grid_to_screen(mouse_cell)

	draw_rect(
		Rect2(pos - Vector2(30, 30), Vector2(60, 60)),
		Color(0.8, 0.9, 0.7, 0.15)
	)

	draw_rect(
		Rect2(pos - Vector2(30, 30), Vector2(60, 60)),
		Color("#b5d4a0"),
		false,
		2.0
	)

# --------------------------------
# 연구 시스템 / 저장 및 불러오기
# --------------------------------

func buy_research(research_name: String) -> void:
	var current_level: int = 0
	if research_name == "채굴 효율":
		current_level = mining_research_level
	elif research_name == "제련 기술":
		current_level = smelting_research_level
	elif research_name == "연료 효율":
		current_level = fuel_research_level

	if current_level >= 3:
		save_message = "최대 연구 단계입니다."
		save_message_timer = 2.0
		return

	var cost: int = (current_level + 1) * 5
	if research_points < cost:
		save_message = "연구 포인트가 부족합니다."
		save_message_timer = 2.0
		return

	research_points -= cost
	if research_name == "채굴 효율":
		mining_research_level += 1
	elif research_name == "제련 기술":
		smelting_research_level += 1
	elif research_name == "연료 효율":
		fuel_research_level += 1

	save_message = research_name + " 연구 완료!"
	save_message_timer = 2.0


func draw_research_panel() -> void:
	if not research_panel_open:
		if save_message != "":
			draw_string(ThemeDB.fallback_font, Vector2(210, 30), save_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#ffe09a"))
		return

	var panel_rect := Rect2(850, 35, 390, 250)
	draw_rect(panel_rect, Color(0.08, 0.11, 0.10, 0.96))
	draw_rect(panel_rect, Color("#8ba995"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(870, 65), "RESEARCH LAB", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#e1eadf"))
	draw_string(ThemeDB.fallback_font, Vector2(870, 92), "연구 포인트: " + str(research_points), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e7c978"))
	draw_string(ThemeDB.fallback_font, Vector2(870, 130), "1. 채굴 효율  Lv." + str(mining_research_level) + "/3  (다음 비용 " + str((mining_research_level + 1) * 5) + ")", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#d9e6dc"))
	draw_string(ThemeDB.fallback_font, Vector2(870, 166), "2. 제련 기술  Lv." + str(smelting_research_level) + "/3  (다음 비용 " + str((smelting_research_level + 1) * 5) + ")", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#d9e6dc"))
	draw_string(ThemeDB.fallback_font, Vector2(870, 202), "3. 연료 효율  Lv." + str(fuel_research_level) + "/3  (다음 비용 " + str((fuel_research_level + 1) * 5) + ")", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#d9e6dc"))
	draw_string(ThemeDB.fallback_font, Vector2(870, 245), "숫자 1 / 2 / 3 키로 연구 · R 키로 닫기", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fc6a8"))

	if save_message != "":
		draw_string(ThemeDB.fallback_font, Vector2(870, 270), save_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffe09a"))


func save_game() -> void:
	var data: Dictionary = {}
	var building_records: Array = []
	for cell in buildings.keys():
		building_records.append({
			"x": cell.x,
			"y": cell.y,
			"name": buildings[cell],
			"miner_timer": miner_timers.get(cell, 0.0),
			"furnace_ore": furnace_ore.get(cell, 0),
			"furnace_ingots": furnace_ingots.get(cell, 0),
			"furnace_timer": furnace_timers.get(cell, 0.0),
			"plant_coal": power_plant_coal.get(cell, 0),
			"plant_timer": power_plant_timers.get(cell, 0.0)
		})

	var belt_records: Array = []
	for cell in belts.keys():
		var direction: Vector2i = belts[cell]
		belt_records.append({"x": cell.x, "y": cell.y, "dx": direction.x, "dy": direction.y})

	var item_records: Array = []
	for item in items:
		var item_cell: Vector2i = item.get("cell", Vector2i.ZERO)
		item_records.append({
			"x": item_cell.x,
			"y": item_cell.y,
			"progress": item.get("progress", 0.0),
			"type": item.get("type", "철광석")
		})

	data = {
		"version": 2,
		"iron_ingots": iron_ingots,
		"total_ore_mined": total_ore_mined,
		"total_coal_mined": total_coal_mined,
		"total_ingots_produced": total_ingots_produced,
		"total_ingots_spent": total_ingots_spent,
		"starter_fuel_given": starter_fuel_given,
		"research_points": research_points,
		"mining_research_level": mining_research_level,
		"smelting_research_level": smelting_research_level,
		"fuel_research_level": fuel_research_level,
		"buildings": building_records,
		"belts": belt_records,
		"items": item_records
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		save_message = "저장 파일을 열 수 없습니다."
		save_message_timer = 3.0
		return

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	save_message = "게임 저장 완료"
	save_message_timer = 2.5


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		save_message = "저장 파일이 없습니다."
		save_message_timer = 3.0
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		save_message = "저장 파일을 읽을 수 없습니다."
		save_message_timer = 3.0
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		save_message = "저장 파일 형식이 올바르지 않습니다."
		save_message_timer = 3.0
		return

	var data: Dictionary = parsed
	buildings.clear()
	belts.clear()
	items.clear()
	miner_timers.clear()
	furnace_ore.clear()
	furnace_ingots.clear()
	furnace_timers.clear()
	power_plant_coal.clear()
	power_plant_timers.clear()

	iron_ingots = int(data.get("iron_ingots", 30))
	total_ore_mined = int(data.get("total_ore_mined", 0))
	total_coal_mined = int(data.get("total_coal_mined", 0))
	total_ingots_produced = int(data.get("total_ingots_produced", 0))
	total_ingots_spent = int(data.get("total_ingots_spent", 0))
	starter_fuel_given = bool(data.get("starter_fuel_given", false))
	research_points = int(data.get("research_points", 0))
	mining_research_level = int(data.get("mining_research_level", 0))
	smelting_research_level = int(data.get("smelting_research_level", 0))
	fuel_research_level = int(data.get("fuel_research_level", 0))

	for record in data.get("buildings", []):
		var cell := Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))
		var building_name: String = str(record.get("name", ""))
		if building_name == "":
			continue
		buildings[cell] = building_name
		if building_name == "채굴기" or building_name == "석탄 광산":
			miner_timers[cell] = float(record.get("miner_timer", 0.0))
		elif building_name == "용광로":
			furnace_ore[cell] = int(record.get("furnace_ore", 0))
			furnace_ingots[cell] = int(record.get("furnace_ingots", 0))
			furnace_timers[cell] = float(record.get("furnace_timer", 0.0))
		elif building_name == "석탄 발전소":
			power_plant_coal[cell] = int(record.get("plant_coal", 0))
			power_plant_timers[cell] = float(record.get("plant_timer", 0.0))

	for record in data.get("belts", []):
		var belt_cell := Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))
		var direction := Vector2i(int(record.get("dx", 1)), int(record.get("dy", 0)))
		belts[belt_cell] = direction

	for record in data.get("items", []):
		items.append({
			"cell": Vector2i(int(record.get("x", 0)), int(record.get("y", 0))),
			"progress": float(record.get("progress", 0.0)),
			"type": str(record.get("type", "철광석"))
		})

	autosave_timer = 0.0
	calculate_power()
	save_message = "게임 불러오기 완료"
	save_message_timer = 2.5
	queue_redraw()
