local INTERFACE_NAME = "save_safe_bridge"
local MAX_RADIUS = 32

local AGENT_ID = "mira"
local AGENT_DISPLAY_NAME = "Mira"
local AGENT_COLOR = {r = 0.2, g = 0.6, b = 1.0, a = 1.0}
local NAME_OFFSET = {0, -2.6}
local NAME_SCALE = 3.2
local LOCATOR_INTERVAL = 120
local LOCATOR_MOVE_THRESHOLD = 2
local PLACEABLE_ITEMS = {
  ["stone-furnace"] = "stone-furnace",
}
local INSERT_ITEMS = {
  fuel = {coal = true, wood = true},
  input = {["iron-ore"] = true, ["copper-ore"] = true, stone = true},
}
local TAKE_ITEMS = {
  fuel = {coal = true, wood = true},
  input = {["iron-ore"] = true, ["copper-ore"] = true, stone = true},
  output = {["iron-plate"] = true, ["copper-plate"] = true, ["stone-brick"] = true},
}

local function ensure_storage()
  if storage.save_safe_bridge == nil then
    storage.save_safe_bridge = {}
  end
  local data = storage.save_safe_bridge
  data.schema = 6
  data.query_count = data.query_count or 0
  data.agent_id = data.agent_id or AGENT_ID
  data.display_name = AGENT_DISPLAY_NAME
  data.name_render_id = data.name_render_id or 0
  data.name_scale = data.name_scale or 0
  data.chart_tag_number = data.chart_tag_number or 0
  data.locator_x = data.locator_x or 0
  data.locator_y = data.locator_y or 0
  data.locator_tick = data.locator_tick or 0
  if data.agent_unit_number == nil then
    data.agent_unit_number = 0
  end
  data.movement = data.movement or {
    state = "idle",
    path_id = 0,
    target_x = 0,
    target_y = 0,
    waypoints = {},
    waypoint_index = 0,
    reason = "",
    last_x = 0,
    last_y = 0,
    stuck_ticks = 0,
    repaths = 0,
    direction = nil,
  }
  data.action = data.action or {
    kind = "idle",
    resource = "",
    target_x = 0,
    target_y = 0,
    requested = 0,
    mined = 0,
    crafted = 0,
    started_tick = 0,
    reason = "",
    saw_progress = false,
    next_tick = 0,
  }
  data.action.next_tick = data.action.next_tick or 0
end

local function finite_number(value, name)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    error(name .. " must be a finite number")
  end
  return value
end

local function get_entities(request)
  ensure_storage()
  if type(request) ~= "table" then
    error("request must be a table")
  end

  local surface_name = request.surface or "nauvis"
  local force_name = request.force or "player"
  local x = finite_number(request.x, "x")
  local y = finite_number(request.y, "y")
  local radius = finite_number(request.radius, "radius")
  if radius < 0 or radius > MAX_RADIUS then
    error("radius must be between 0 and " .. MAX_RADIUS)
  end

  local surface = game.surfaces[surface_name]
  if surface == nil then
    error("unknown surface")
  end
  local force = game.forces[force_name]
  if force == nil then
    error("unknown force")
  end

  local entities = surface.find_entities_filtered({
    position = {x = x, y = y},
    radius = radius,
    force = force,
  })

  local result = {}
  local counts = {}
  for _, entity in pairs(entities) do
    counts[entity.name] = (counts[entity.name] or 0) + 1
    result[#result + 1] = {
      name = entity.name,
      type = entity.type,
      x = entity.position.x,
      y = entity.position.y,
      unit_number = entity.unit_number,
    }
  end

  storage.save_safe_bridge.query_count = storage.save_safe_bridge.query_count + 1
  return {
    surface = surface.name,
    force = force.name,
    tick = game.tick,
    speed = game.speed,
    query_count = storage.save_safe_bridge.query_count,
    entity_count = #result,
    entity_counts = counts,
    entities = result,
  }
end

local function agent_snapshot(entity, created)
  return {
    created = created,
    valid = entity ~= nil and entity.valid,
    unit_number = entity and entity.unit_number or nil,
    x = entity and entity.position.x or nil,
    y = entity and entity.position.y or nil,
    force = entity and entity.force.name or nil,
    player = (entity and entity.player) and entity.player.name or "",
  }
end

local function stored_agent()
  ensure_storage()
  local data = storage.save_safe_bridge
  local entity = data.agent_entity
  if entity ~= nil and entity.valid and entity.type == "character" and entity.player == nil and entity.unit_number == data.agent_unit_number then
    return entity
  end
  if data.agent_unit_number ~= 0 then
    error("stored AI character reference is missing or does not match its unit number")
  end
  return nil
end

local function distance(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function inventory_counts(inventory)
  local counts = {}
  if inventory == nil then
    return counts
  end
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read then
      counts[stack.name] = (counts[stack.name] or 0) + stack.count
    end
  end
  return counts
end

local function entity_status_name(entity)
  if entity.status == nil then
    return ""
  end
  for name, value in pairs(defines.entity_status) do
    if value == entity.status then
      return name
    end
  end
  return tostring(entity.status)
end

local function get_name_object()
  local data = storage.save_safe_bridge
  if data.name_render_id == nil or data.name_render_id == 0 then
    return nil
  end
  return rendering.get_object_by_id(data.name_render_id)
end

local function ensure_nameplate(agent)
  local data = storage.save_safe_bridge
  local object = get_name_object()
  if object ~= nil and object.valid and data.name_scale == NAME_SCALE then
    return object
  end
  if object ~= nil and object.valid then
    object.destroy()
  end
  object = rendering.draw_text({
    text = AGENT_DISPLAY_NAME,
    surface = agent.surface,
    target = {entity = agent, offset = NAME_OFFSET},
    color = {r = 1, g = 1, b = 1, a = 1},
    scale = NAME_SCALE,
    alignment = "center",
    vertical_alignment = "bottom",
    scale_with_zoom = true,
  })
  data.name_render_id = object.id
  data.name_scale = NAME_SCALE
  return object
end

local function destroy_extra_mira_tags(agent, keep_number)
  local tags = agent.force.find_chart_tags(agent.surface)
  for _, tag in pairs(tags) do
    if tag.valid and tag.text == AGENT_DISPLAY_NAME and tag.tag_number ~= keep_number then
      tag.destroy()
    end
  end
end

local function find_chart_tag(agent)
  local data = storage.save_safe_bridge
  local tags = agent.force.find_chart_tags(agent.surface)
  local found = nil
  for _, tag in pairs(tags) do
    if tag.valid and tag.text == AGENT_DISPLAY_NAME then
      if data.chart_tag_number ~= 0 and tag.tag_number == data.chart_tag_number then
        found = tag
      elseif found == nil then
        found = tag
      end
    end
  end
  if found ~= nil then
    data.chart_tag_number = found.tag_number
    destroy_extra_mira_tags(agent, found.tag_number)
  end
  return found
end

local function chart_around(agent)
  local position = agent.position
  agent.force.chart(agent.surface, {
    {x = position.x - 32, y = position.y - 32},
    {x = position.x + 32, y = position.y + 32},
  })
end

local function ensure_locator(agent, force_update)
  local data = storage.save_safe_bridge
  local tag = find_chart_tag(agent)
  local position = agent.position
  if tag == nil or not tag.valid then
    chart_around(agent)
    tag = agent.force.add_chart_tag(agent.surface, {
      position = position,
      text = AGENT_DISPLAY_NAME,
      icon = {type = "virtual", name = "signal-info"},
    })
    if tag == nil then
      data.chart_tag_number = 0
      return nil
    end
    data.chart_tag_number = tag.tag_number
    data.locator_x = position.x
    data.locator_y = position.y
    data.locator_tick = game.tick
    destroy_extra_mira_tags(agent, tag.tag_number)
    return tag
  end
  local moved = distance(position, {x = data.locator_x, y = data.locator_y})
  if force_update or moved >= LOCATOR_MOVE_THRESHOLD then
    chart_around(agent)
    tag.position = position
    tag.text = AGENT_DISPLAY_NAME
    data.locator_x = position.x
    data.locator_y = position.y
    data.locator_tick = game.tick
  end
  destroy_extra_mira_tags(agent, tag.tag_number)
  return tag
end

local function ensure_identity(agent, force_update)
  if agent == nil or not agent.valid then
    return {
      agent_id = AGENT_ID,
      display_name = AGENT_DISPLAY_NAME,
      name_visible = false,
      marker_valid = false,
    }
  end
  local name_object = ensure_nameplate(agent)
  local tag = ensure_locator(agent, force_update)
  return {
    agent_id = AGENT_ID,
    display_name = AGENT_DISPLAY_NAME,
    unit_number = agent.unit_number,
    surface = agent.surface.name,
    x = agent.position.x,
    y = agent.position.y,
    name_visible = name_object ~= nil and name_object.valid or false,
    marker_valid = tag ~= nil and tag.valid or false,
    marker_x = tag and tag.position.x or nil,
    marker_y = tag and tag.position.y or nil,
    marker_tag_number = tag and tag.tag_number or 0,
  }
end

local function update_locator()
  if game.tick % LOCATOR_INTERVAL ~= 0 then
    return
  end
  local agent = stored_agent()
  if agent == nil then
    return
  end
  ensure_identity(agent, false)
end

local function ensure_agent_character()
  local existing = stored_agent()
  if existing ~= nil then
    ensure_identity(existing, true)
    return agent_snapshot(existing, false)
  end

  local surface = game.surfaces["nauvis"]
  local target = {x = 8, y = 0}
  local position = surface.find_non_colliding_position("character", target, 30, 0.5)
  if position == nil then
    error("no non-colliding position found for AI character")
  end

  local entity = surface.create_entity({
    name = "character",
    position = position,
    force = "player",
  })
  if entity == nil then
    error("failed to create AI character")
  end
  entity.color = AGENT_COLOR

  local data = storage.save_safe_bridge
  data.agent_entity = entity
  data.agent_unit_number = entity.unit_number
  ensure_identity(entity, true)
  return agent_snapshot(entity, true)
end

local function agent_status()
  local agent = stored_agent()
  if agent ~= nil then
    ensure_identity(agent, false)
  end
  return agent_snapshot(agent, false)
end

local DIRECTIONS = {
  defines.direction.east,
  defines.direction.southeast,
  defines.direction.south,
  defines.direction.southwest,
  defines.direction.west,
  defines.direction.northwest,
  defines.direction.north,
  defines.direction.northeast,
}

local function direction_between(from_position, to_position, current_direction)
  local dx = to_position.x - from_position.x
  local dy = to_position.y - from_position.y
  if math.abs(dx) < 0.15 and math.abs(dy) < 0.15 then
    return nil
  end
  local angle = math.atan2(dy, dx)
  local sector = math.pi / 4
  local hysteresis = current_direction and (sector * 0.35) or (sector * 0.5)
  local octant = math.floor((angle + hysteresis) / sector)
  return DIRECTIONS[(octant % 8) + 1]
end

local function line_is_walkable(agent, target)
  local start = agent.position
  local length = distance(start, target)
  local step = 0.5
  local count = math.max(1, math.ceil(length / step))
  for index = 1, count do
    local t = index / count
    local point = {
      x = start.x + (target.x - start.x) * t,
      y = start.y + (target.y - start.y) * t,
    }
    if agent.surface.entity_prototype_collides("character", point, false) then
      return false
    end
  end
  return true
end

local function choose_lookahead(agent, movement)
  local chosen = movement.waypoint_index
  local limit = math.min(#movement.waypoints, movement.waypoint_index + 8)
  for index = movement.waypoint_index + 1, limit do
    if not line_is_walkable(agent, movement.waypoints[index]) then
      break
    end
    chosen = index
  end
  return chosen
end

local function stop_walking(agent)
  agent.walking_state = {walking = false, direction = defines.direction.north}
end

local function movement_snapshot()
  ensure_storage()
  local agent = stored_agent()
  local movement = storage.save_safe_bridge.movement
  local target = movement.waypoints[movement.waypoint_index]
  return {
    state = movement.state,
    reason = movement.reason,
    path_id = movement.path_id,
    target_x = movement.target_x,
    target_y = movement.target_y,
    waypoint_index = movement.waypoint_index,
    waypoint_count = #movement.waypoints,
    lookahead_index = movement.lookahead_index,
    next_x = target and target.x or nil,
    next_y = target and target.y or nil,
    stuck_ticks = movement.stuck_ticks,
    repaths = movement.repaths,
    agent_unit_number = agent and agent.unit_number or nil,
    agent_x = agent and agent.position.x or nil,
    agent_y = agent and agent.position.y or nil,
    speed = game.speed,
  }
end

local function locate()
  local agent = stored_agent()
  local identity = ensure_identity(agent, true)
  local movement = movement_snapshot()
  identity.movement = {
    state = movement.state,
    reason = movement.reason,
    agent_x = movement.agent_x,
    agent_y = movement.agent_y,
  }
  return identity
end

local function fail_movement(reason)
  local movement = storage.save_safe_bridge.movement
  movement.state = "failed"
  movement.reason = reason
  movement.waypoints = {}
  movement.waypoint_index = 0
  local agent = stored_agent()
  if agent ~= nil then
    stop_walking(agent)
  end
end

local function request_agent_path(agent, x, y, repath)
  local movement = storage.save_safe_bridge.movement
  movement.state = "pathing"
  movement.reason = ""
  movement.target_x = x
  movement.target_y = y
  movement.waypoints = {}
  movement.waypoint_index = 0
  movement.lookahead_index = 0
  movement.last_x = agent.position.x
  movement.last_y = agent.position.y
  movement.stuck_ticks = 0
  if not repath then
    movement.repaths = 0
  end
  stop_walking(agent)

  local prototype = prototypes.entity["character"]
  local path_id = agent.surface.request_path({
    bounding_box = prototype.collision_box,
    collision_mask = prototype.collision_mask,
    start = agent.position,
    goal = {x = x, y = y},
    force = agent.force,
    radius = 1,
    can_open_gates = true,
    path_resolution_modifier = -1,
    entity_to_ignore = agent,
  })
  movement.path_id = path_id
end

local function walk_to(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  local x = finite_number(request.x, "x")
  local y = finite_number(request.y, "y")
  request_agent_path(agent, x, y, false)
  return movement_snapshot()
end

local function stop_agent()
  local movement = storage.save_safe_bridge.movement
  movement.state = "idle"
  movement.reason = "stopped"
  movement.waypoints = {}
  movement.waypoint_index = 0
  local agent = stored_agent()
  if agent ~= nil then
    stop_walking(agent)
  end
  return movement_snapshot()
end

local function update_walking()
  local data = storage.save_safe_bridge
  if data == nil or data.movement == nil or data.movement.state ~= "walking" then
    return
  end
  local agent = stored_agent()
  if agent == nil then
    fail_movement("AI character is missing")
    return
  end
  local movement = data.movement
  local goal = {x = movement.target_x, y = movement.target_y}
  if distance(agent.position, goal) <= 0.8 then
    movement.state = "arrived"
    movement.reason = ""
    stop_walking(agent)
    return
  end

  local moved = distance(agent.position, {x = movement.last_x, y = movement.last_y})
  if moved < 0.01 then
    movement.stuck_ticks = movement.stuck_ticks + 1
  else
    movement.stuck_ticks = 0
    movement.last_x = agent.position.x
    movement.last_y = agent.position.y
  end
  if movement.stuck_ticks >= 90 then
    stop_walking(agent)
    if movement.repaths >= 1 then
      fail_movement("stuck")
      return
    end
    movement.repaths = 1
    request_agent_path(agent, movement.target_x, movement.target_y, true)
    return
  end

  local waypoint = movement.waypoints[movement.waypoint_index]
  if waypoint == nil then
    movement.state = "arrived"
    stop_walking(agent)
    return
  end
  local tolerance = movement.waypoint_index == #movement.waypoints and 0.8 or 1.2
  if distance(agent.position, waypoint) <= tolerance then
    movement.waypoint_index = movement.waypoint_index + 1
  end
  if movement.waypoint_index > #movement.waypoints then
    movement.state = "arrived"
    stop_walking(agent)
    return
  end

  movement.lookahead_index = choose_lookahead(agent, movement)
  local aim = movement.waypoints[movement.lookahead_index]
  local direction = direction_between(agent.position, aim, movement.direction)
  if direction == nil then
    movement.state = "arrived"
    stop_walking(agent)
    return
  end
  movement.direction = direction
  agent.walking_state = {walking = true, direction = direction}
end

local function on_path_finished(event)
  local data = storage.save_safe_bridge
  if data == nil or data.movement == nil or event.id ~= data.movement.path_id or data.movement.state ~= "pathing" then
    return
  end
  if event.path == nil then
    fail_movement("no path")
    return
  end
  local waypoints = {}
  for _, waypoint in pairs(event.path) do
    waypoints[#waypoints + 1] = {x = waypoint.position.x, y = waypoint.position.y}
  end
  waypoints[#waypoints + 1] = {x = data.movement.target_x, y = data.movement.target_y}
  data.movement.waypoints = waypoints
  data.movement.waypoint_index = 1
  data.movement.state = "walking"
end

local function give_stone_furnace()
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  local inserted = agent.insert({name = "stone-furnace", count = 1})
  return {
    inserted = inserted,
    inventory_count = agent.get_item_count("stone-furnace"),
    agent_unit_number = agent.unit_number,
  }
end

local function place_stone_furnace(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  if storage.save_safe_bridge.movement.state == "walking" or storage.save_safe_bridge.movement.state == "pathing" then
    error("AI character is still moving")
  end
  local x = finite_number(request.x, "x")
  local y = finite_number(request.y, "y")
  local target = {x = x, y = y}
  if not agent.can_place_entity({name = "stone-furnace", position = target}) then
    if distance(agent.position, target) > agent.build_distance then
      error("target is outside the AI character build distance")
    end
    error("target is blocked")
  end
  if agent.get_item_count("stone-furnace") < 1 then
    error("AI inventory has no stone furnace")
  end
  local surface = agent.surface
  local created = surface.create_entity({
    name = "stone-furnace",
    position = target,
    force = agent.force,
    build_check_type = defines.build_check_type.manual,
  })
  if created == nil then
    error("placement failed")
  end
  local removed = agent.remove_item({name = "stone-furnace", count = 1})
  return {
    placed = true,
    item = "stone-furnace",
    unit_number = created.unit_number,
    x = created.position.x,
    y = created.position.y,
    force = created.force.name,
    removed = removed,
    inventory_count = agent.get_item_count("stone-furnace"),
    agent_unit_number = agent.unit_number,
  }
end

local function place_item(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local item = request.item
  local entity_name = PLACEABLE_ITEMS[item]
  if entity_name == nil then
    error("item is not allowed for placement")
  end
  request.item = item
  if item == "stone-furnace" then
    return place_stone_furnace(request)
  end
  error("item is not allowed for placement")
end

local function require_agent()
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  return agent
end

local function find_machine(request)
  local agent = require_agent()
  local found = nil
  if request.unit_number ~= nil then
    local unit_number = math.floor(finite_number(request.unit_number, "unit_number"))
    if game.get_entity_by_unit_number ~= nil then
      found = game.get_entity_by_unit_number(unit_number)
    end
    if found == nil then
      local nearby = agent.surface.find_entities_filtered({
        position = agent.position,
        radius = 96,
        type = "furnace",
      })
      for _, entity in pairs(nearby) do
        if entity.unit_number == unit_number then
          found = entity
          break
        end
      end
    end
  else
    local x = finite_number(request.x, "x")
    local y = finite_number(request.y, "y")
    local nearby = agent.surface.find_entities_filtered({
      position = {x = x, y = y},
      radius = 0.6,
      type = "furnace",
      limit = 1,
    })
    found = nearby[1]
  end
  if found == nil or not found.valid then
    error("machine does not exist")
  end
  if found.type ~= "furnace" or found.name ~= "stone-furnace" then
    error("only stone-furnace interaction is allowed")
  end
  if found.force.name ~= agent.force.name then
    error("machine belongs to another force")
  end
  return agent, found
end

local function require_reach(agent, entity)
  if not agent.can_reach_entity(entity) then
    error("machine is outside interaction reach")
  end
end

local function furnace_inventory(entity, kind)
  if kind == "fuel" then
    return entity.get_fuel_inventory()
  end
  if kind == "input" then
    return entity.get_inventory(defines.inventory.furnace_source)
  end
  if kind == "output" then
    return entity.get_output_inventory()
  end
  error("inventory kind must be fuel, input, or output")
end

local function inspect_entity(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local agent, entity = find_machine(request)
  local fuel = furnace_inventory(entity, "fuel")
  local input = furnace_inventory(entity, "input")
  local output = furnace_inventory(entity, "output")
  return {
    name = entity.name,
    type = entity.type,
    unit_number = entity.unit_number,
    x = entity.position.x,
    y = entity.position.y,
    status = entity_status_name(entity),
    reachable = agent.can_reach_entity(entity),
    is_crafting = entity.is_crafting(),
    crafting_progress = entity.crafting_progress or 0,
    fuel = inventory_counts(fuel),
    input = inventory_counts(input),
    output = inventory_counts(output),
  }
end

local function insert_into_entity(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local kind = request.inventory_kind
  local item = request.item
  local count = math.floor(finite_number(request.count, "count"))
  if count < 1 or count > 20 then
    error("count must be between 1 and 20")
  end
  if INSERT_ITEMS[kind] == nil or not INSERT_ITEMS[kind][item] then
    error("item is not allowed for this inventory")
  end
  local agent, entity = find_machine(request)
  require_reach(agent, entity)
  if agent.get_item_count(item) < count then
    error("AI inventory does not have enough items")
  end
  local inventory = furnace_inventory(entity, kind)
  if inventory == nil then
    error("machine inventory is missing")
  end
  local inserted = inventory.insert({name = item, count = count})
  if inserted < 1 then
    error("machine could not accept items")
  end
  local removed = agent.remove_item({name = item, count = inserted})
  if removed < inserted then
    inventory.remove({name = item, count = inserted - removed})
    error("failed to deduct items from AI inventory")
  end
  return {
    inserted = inserted,
    item = item,
    inventory_kind = kind,
    unit_number = entity.unit_number,
    agent_count = agent.get_item_count(item),
    machine = inspect_entity({unit_number = entity.unit_number}),
  }
end

local function take_from_entity(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local kind = request.inventory_kind or "output"
  local item = request.item
  local count = math.floor(finite_number(request.count, "count"))
  if count < 1 or count > 20 then
    error("count must be between 1 and 20")
  end
  if TAKE_ITEMS[kind] == nil or not TAKE_ITEMS[kind][item] then
    error("item is not allowed for this inventory")
  end
  local agent, entity = find_machine(request)
  require_reach(agent, entity)
  local inventory = furnace_inventory(entity, kind)
  if inventory == nil then
    error("machine inventory is missing")
  end
  local available = inventory.get_item_count(item)
  if available < 1 then
    error("machine does not contain that item")
  end
  local want = math.min(count, available)
  local extracted = inventory.remove({name = item, count = want})
  if extracted < 1 then
    error("failed to take items from machine")
  end
  local inserted = agent.insert({name = item, count = extracted})
  if inserted < extracted then
    inventory.insert({name = item, count = extracted - inserted})
    if inserted < 1 then
      error("AI inventory is full")
    end
  end
  return {
    taken = inserted,
    item = item,
    inventory_kind = kind,
    unit_number = entity.unit_number,
    agent_count = agent.get_item_count(item),
    machine = inspect_entity({unit_number = entity.unit_number}),
  }
end

local function inspect_smelting_recipe(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local query = request.item or request.resource
  if type(query) ~= "string" or query == "" then
    error("item is required")
  end
  local force = game.forces.player
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and recipe.category == "smelting" then
      local uses_query = false
      local ingredients = {}
      for _, ingredient in pairs(recipe.ingredients) do
        ingredients[#ingredients + 1] = {name = ingredient.name, amount = ingredient.amount}
        if ingredient.name == query then
          uses_query = true
        end
      end
      local products = {}
      for _, product in pairs(recipe.products) do
        products[#products + 1] = {name = product.name, amount = product.amount}
        if product.name == query then
          uses_query = true
        end
      end
      if uses_query then
        return {
          item = query,
          recipe = recipe.name,
          category = recipe.category,
          enabled = recipe.enabled,
          energy = recipe.energy,
          ingredients = ingredients,
          products = products,
        }
      end
    end
  end
  error("no enabled smelting recipe found")
end

local function inventory_summary()
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  local inventory = agent.get_main_inventory()
  return {unit_number = agent.unit_number, items = inventory_counts(inventory)}
end

local function scan_resources(request)
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  local radius = 32
  if type(request) == "table" and request.radius ~= nil then
    radius = finite_number(request.radius, "radius")
  end
  if radius < 1 or radius > 96 then
    error("radius must be between 1 and 96")
  end
  local resources = agent.surface.find_entities_filtered({
    position = agent.position,
    radius = radius,
    type = "resource",
  })
  local grouped = {}
  for _, resource in pairs(resources) do
    local key = resource.name
    local entry = grouped[key]
    local resource_distance = distance(agent.position, resource.position)
    if entry == nil or resource_distance < entry.distance then
      grouped[key] = {
        name = resource.name,
        x = resource.position.x,
        y = resource.position.y,
        amount = resource.amount,
        distance = resource_distance,
      }
    end
  end
  local result = {}
  for _, entry in pairs(grouped) do
    result[#result + 1] = entry
  end
  return {radius = radius, generated_only = true, resources = result}
end

local function action_snapshot()
  local action = storage.save_safe_bridge.action
  return {
    kind = action.kind,
    resource = action.resource,
    target_x = action.target_x,
    target_y = action.target_y,
    requested = action.requested,
    mined = action.mined,
    crafted = action.crafted,
    started_tick = action.started_tick,
    reason = action.reason,
    tick = game.tick,
  }
end

local function mine_resource(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  local count = math.floor(finite_number(request.count, "count"))
  if count < 1 or count > 10 then
    error("count must be between 1 and 10")
  end
  local x = finite_number(request.x, "x")
  local y = finite_number(request.y, "y")
  local target = {x = x, y = y}
  if distance(agent.position, target) > agent.resource_reach_distance then
    error("resource is outside mining reach")
  end
  local found = agent.surface.find_entities_filtered({
    position = target,
    radius = 0.6,
    name = request.resource,
    type = "resource",
    limit = 1,
  })
  if #found == 0 then
    error("resource does not exist at target")
  end
  local action = storage.save_safe_bridge.action
  action.kind = "mining"
  action.resource = request.resource
  action.target_x = x
  action.target_y = y
  action.requested = count
  action.mined = 0
  action.crafted = 0
  action.started_tick = game.tick
  action.reason = ""
  action.saw_progress = false
  local mining_time = prototypes.entity[request.resource].mineable_properties.mining_time
  action.next_tick = game.tick + math.ceil(mining_time * 60)
  agent.mining_state = {mining = true, position = target}
  return action_snapshot()
end

local function inspect_recipe(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local recipe = prototypes.recipe[request.item]
  if recipe == nil then
    error("unknown recipe")
  end
  local technology = game.forces.player.recipes[request.item]
  local ingredients = {}
  for _, ingredient in pairs(recipe.ingredients) do
    ingredients[#ingredients + 1] = {name = ingredient.name, amount = ingredient.amount}
  end
  local products = {}
  for _, product in pairs(recipe.products) do
    products[#products + 1] = {name = product.name, amount = product.amount}
  end
  return {
    item = request.item,
    enabled = technology ~= nil and technology.enabled or false,
    energy = recipe.energy,
    ingredients = ingredients,
    products = products,
  }
end

local function craft_item(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  local count = math.floor(finite_number(request.count, "count"))
  if count < 1 or count > 5 then
    error("count must be between 1 and 5")
  end
  local started = agent.begin_crafting({count = count, recipe = request.item, silent = true})
  local action = storage.save_safe_bridge.action
  action.kind = started > 0 and "crafting" or "failed"
  action.resource = request.item
  action.requested = count
  action.crafted = started
  action.started_tick = game.tick
  action.reason = started > 0 and "" or "crafting did not start"
  return action_snapshot()
end

local function update_action()
  local data = storage.save_safe_bridge
  if data == nil or data.action == nil or data.action.kind ~= "mining" then
    return
  end
  local agent = stored_agent()
  local action = data.action
  if agent == nil then
    action.kind = "failed"
    action.reason = "AI character is missing"
    return
  end
  agent.mining_state = {mining = true, position = {x = action.target_x, y = action.target_y}}
  if game.tick < (action.next_tick or 0) then
    return
  end
  local before = agent.get_item_count(action.resource)
  local found = agent.surface.find_entities_filtered({
    position = {x = action.target_x, y = action.target_y},
    radius = 0.6,
    name = action.resource,
    type = "resource",
    limit = 1,
  })
  if #found == 0 then
    action.kind = action.mined > 0 and "mined" or "failed"
    action.reason = "resource depleted"
    agent.mining_state = {mining = false}
    return
  end
  local resource = found[1]
  local amount_before = resource.amount
  resource.amount = math.max(0, amount_before - 1)
  local inserted = agent.insert({name = action.resource, count = 1})
  if inserted < 1 then
    resource.amount = amount_before
    action.kind = "failed"
    action.reason = "inventory is full"
    agent.mining_state = {mining = false}
    return
  end
  local gained = agent.get_item_count(action.resource) - before
  if gained < 1 then
    action.kind = "failed"
    action.reason = "mining failed"
    agent.mining_state = {mining = false}
    return
  end
  action.mined = action.mined + gained
  action.next_tick = game.tick + math.ceil(prototypes.entity[action.resource].mineable_properties.mining_time * 60)
  if action.mined >= action.requested then
    action.kind = "mined"
    agent.mining_state = {mining = false}
    return
  end
  agent.mining_state = {mining = true, position = {x = action.target_x, y = action.target_y}}
end

local function status()
  ensure_storage()
  return {
    schema = storage.save_safe_bridge.schema,
    query_count = storage.save_safe_bridge.query_count,
  }
end

script.on_init(ensure_storage)
script.on_configuration_changed(ensure_storage)
script.on_event(defines.events.on_tick, function()
  update_walking()
  update_action()
  update_locator()
end)
script.on_event(defines.events.on_script_path_request_finished, on_path_finished)

remote.add_interface(INTERFACE_NAME, {
  get_entities = get_entities,
  status = status,
  ensure_agent_character = ensure_agent_character,
  agent_status = agent_status,
  walk_to = walk_to,
  movement_status = movement_snapshot,
  stop_agent = stop_agent,
  give_stone_furnace = give_stone_furnace,
  place_stone_furnace = place_stone_furnace,
  place_item = place_item,
  inventory = inventory_summary,
  scan_resources = scan_resources,
  mine_resource = mine_resource,
  inspect_recipe = inspect_recipe,
  inspect_smelting_recipe = inspect_smelting_recipe,
  inspect_entity = inspect_entity,
  insert_into_entity = insert_into_entity,
  take_from_entity = take_from_entity,
  craft_item = craft_item,
  action_status = action_snapshot,
  locate = locate,
})
