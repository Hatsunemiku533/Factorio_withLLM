local INTERFACE_NAME = "save_safe_bridge"
local MAX_RADIUS = 32

local AGENT_COLOR = {r = 0.2, g = 0.6, b = 1.0, a = 1.0}

local function ensure_storage()
  if storage.save_safe_bridge == nil then
    storage.save_safe_bridge = {}
  end
  local data = storage.save_safe_bridge
  data.schema = 3
  data.query_count = data.query_count or 0
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
  }
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

local function ensure_agent_character()
  local existing = stored_agent()
  if existing ~= nil then
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
  return agent_snapshot(entity, true)
end

local function agent_status()
  return agent_snapshot(stored_agent(), false)
end

local function distance(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function direction_between(from_position, to_position)
  local dx = to_position.x - from_position.x
  local dy = to_position.y - from_position.y
  if math.abs(dx) < 0.05 and math.abs(dy) < 0.05 then
    return nil
  end
  local angle = math.atan2(dy, dx)
  local octant = math.floor((angle + math.pi / 8) / (math.pi / 4))
  local directions = {
    defines.direction.east,
    defines.direction.southeast,
    defines.direction.south,
    defines.direction.southwest,
    defines.direction.west,
    defines.direction.northwest,
    defines.direction.north,
    defines.direction.northeast,
  }
  return directions[(octant % 8) + 1]
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
    next_x = target and target.x or nil,
    next_y = target and target.y or nil,
    agent_unit_number = agent and agent.unit_number or nil,
    agent_x = agent and agent.position.x or nil,
    agent_y = agent and agent.position.y or nil,
    speed = game.speed,
  }
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
  local movement = storage.save_safe_bridge.movement
  movement.path_id = movement.path_id + 1
  movement.state = "pathing"
  movement.reason = ""
  movement.target_x = x
  movement.target_y = y
  movement.waypoints = {}
  movement.waypoint_index = 0
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
  local waypoint = movement.waypoints[movement.waypoint_index]
  if waypoint == nil then
    movement.state = "arrived"
    stop_walking(agent)
    return
  end
  if distance(agent.position, waypoint) <= 0.6 then
    movement.waypoint_index = movement.waypoint_index + 1
    waypoint = movement.waypoints[movement.waypoint_index]
    if waypoint == nil or distance(agent.position, {x = movement.target_x, y = movement.target_y}) <= 1 then
      movement.state = "arrived"
      stop_walking(agent)
      return
    end
  end
  local direction = direction_between(agent.position, waypoint)
  if direction == nil then
    movement.state = "arrived"
    stop_walking(agent)
    return
  end
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
  local reach = agent.reach_distance + agent.build_distance
  if distance(agent.position, target) > reach then
    error("target is outside the AI character build reach")
  end
  if agent.get_item_count("stone-furnace") < 1 then
    error("AI inventory has no stone furnace")
  end
  local surface = agent.surface
  if not surface.can_place_entity({
    name = "stone-furnace",
    position = target,
    force = agent.force,
    build_check_type = defines.build_check_type.manual,
  }) then
    error("target is blocked")
  end
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
    unit_number = created.unit_number,
    x = created.position.x,
    y = created.position.y,
    force = created.force.name,
    removed = removed,
    inventory_count = agent.get_item_count("stone-furnace"),
    agent_unit_number = agent.unit_number,
  }
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
script.on_event(defines.events.on_tick, update_walking)
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
})
