local INTERFACE_NAME = "save_safe_bridge"
local MAX_RADIUS = 32
local SCHEMA = 8

local AGENT_ID = "mira"
local AGENT_DISPLAY_NAME = "Mira"
local AGENT_COLOR = {r = 0.2, g = 0.6, b = 1.0, a = 1.0}
local NAME_OFFSET = {0, -2.6}
local NAME_SCALE = 3.2
local LOCATOR_INTERVAL = 120
local LOCATOR_MOVE_THRESHOLD = 2
local MACHINE_NAMES = {
  ["stone-furnace"] = true,
  ["burner-mining-drill"] = true,
}
local PLACEABLE_ITEMS = {
  ["stone-furnace"] = "stone-furnace",
  ["burner-mining-drill"] = "burner-mining-drill",
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

-- Forward declarations resolve definition order between later sections.
local validate_run
local begin_run
local end_run
local action_snapshot
local stop_all_actions

local HISTORICAL_REPAIRS = {
  [27] = {name = "stone-furnace", x = -70, y = -8},
  [28] = {name = "stone-furnace", x = -68, y = -7},
  [29] = {name = "burner-mining-drill", x = -73, y = -9},
  [30] = {name = "stone-furnace", x = -73, y = -13},
  [31] = {name = "stone-furnace", x = -71, y = -10},
}

local function record_owner(data, entity)
  data.owned_machines[entity.unit_number] = {
    agent_id = AGENT_ID,
    unit_number = entity.unit_number,
    entity_name = entity.name,
    surface = entity.surface.name,
    x = entity.position.x,
    y = entity.position.y,
    placed_tick = game.tick,
  }
end

local function migrate_owned_machines(data, previous_schema)
  data.owned_machines = data.owned_machines or {}
  local durable = {}
  for unit_number, record in pairs(data.owned_machines) do
    if type(record) == "table" and record.agent_id ~= nil then
      durable[unit_number] = record
    end
  end
  data.owned_machines = durable
  -- One-time repair for records lost by the schema-7 boolean table serialization bug.
  if data.historical_provenance_repaired ~= true and previous_schema ~= nil and previous_schema <= 7 then
    local surface = game.surfaces["nauvis"]
    if surface ~= nil then
      local found = surface.find_entities_filtered({type = {"furnace", "mining-drill"}, force = "player"})
      for _, entity in pairs(found) do
        local expected = HISTORICAL_REPAIRS[entity.unit_number]
        if expected ~= nil and entity.valid and entity.name == expected.name and entity.position.x == expected.x and entity.position.y == expected.y then
          record_owner(data, entity)
        end
      end
    end
    data.historical_provenance_repaired = true
  end
end

local function ensure_storage()
  if storage.save_safe_bridge == nil then
    storage.save_safe_bridge = {}
  end
  local data = storage.save_safe_bridge
  local previous_schema = data.schema
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
  data.owned_machines = data.owned_machines or {}
  if previous_schema == nil or previous_schema < SCHEMA then
    migrate_owned_machines(data, previous_schema)
  end
  data.run = data.run or {token = "", active = false, deadline = 0}
  data.schema = SCHEMA
end

local function claim_historical_furnace()
  ensure_storage()
  local data = storage.save_safe_bridge
  if data.historical_furnace_claimed == true then
    return {claimed = false, reason = "already claimed"}
  end
  local surface = game.surfaces["nauvis"]
  local found = surface.find_entities_filtered({
    name = "stone-furnace",
    position = {x = -70, y = -8},
    radius = 0.1,
    force = "player",
    limit = 1,
  })
  local furnace = found[1]
  if furnace == nil or not furnace.valid or furnace.position.x ~= -70 or furnace.position.y ~= -8 or furnace.unit_number ~= 27 then
    return {claimed = false, reason = "historical furnace not found"}
  end
  data.owned_machines[furnace.unit_number] = true
  data.historical_furnace_claimed = true
  return {claimed = true, unit_number = furnace.unit_number}
end

local function claim_units(request)
  ensure_storage()
  local claimed = {}
  local unit_number = request.unit_number
  local entity = nil
  if unit_number ~= nil then
    local agent = stored_agent()
    local nearby = agent.surface.find_entities_filtered({position = agent.position, radius = 96, force = agent.force})
    for _, candidate in pairs(nearby) do
      if candidate.unit_number == unit_number then
        entity = candidate
        break
      end
    end
    if entity ~= nil and entity.valid and (entity.name == "stone-furnace" or entity.name == "burner-mining-drill") and entity.force.name == "player" then
      record_owner(storage.save_safe_bridge, entity)
      claimed[#claimed + 1] = entity.unit_number
    end
  end
  return {claimed = claimed, requested = unit_number or 0, found = entity ~= nil and entity.valid or false}
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
  validate_run(request)
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  local x = finite_number(request.x, "x")
  local y = finite_number(request.y, "y")
  request_agent_path(agent, x, y, false)
  return movement_snapshot()
end

function stop_all_actions()
  local data = storage.save_safe_bridge
  local movement = data.movement
  movement.state = "idle"
  movement.reason = "stopped"
  movement.waypoints = {}
  movement.waypoint_index = 0
  movement.lookahead_index = 0
  movement.path_id = 0
  local action = data.action
  action.kind = "idle"
  action.reason = "stopped"
  local agent = stored_agent()
  local crafting_queue_size = 0
  if agent ~= nil then
    stop_walking(agent)
    agent.mining_state = {mining = false}
    local guard = 0
    while agent.crafting_queue_size > 0 and guard < 1000 do
      agent.cancel_crafting(1, 1)
      guard = guard + 1
    end
    crafting_queue_size = agent.crafting_queue_size or 0
  end
  return {
    movement = movement_snapshot(),
    action = action_snapshot(),
    crafting_queue_size = crafting_queue_size,
    stopped = true,
  }
end

local function stop_agent()
  ensure_storage()
  return stop_all_actions()
end

function validate_run(request)
  ensure_storage()
  local run = storage.save_safe_bridge.run
  local token = nil
  if type(request) == "table" then
    token = request.run_token
  end
  if run ~= nil and run.active then
    if token == nil then
      error("an active run requires a matching run_token")
    end
    if token ~= run.token then
      error("run_token does not match the active run")
    end
    if game.tick >= run.deadline then
      error("the active run has reached its deadline")
    end
  elseif token ~= nil then
    error("no active run for the provided run_token")
  end
end

function begin_run(request)
  ensure_storage()
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local data = storage.save_safe_bridge
  local token = request.token
  if type(token) ~= "string" or token == "" then
    error("token must be a non-empty string")
  end
  local duration = finite_number(request.duration_seconds, "duration_seconds")
  if duration <= 0 or duration > 1500 then
    error("duration_seconds must be greater than 0 and at most 1500")
  end
  if data.run ~= nil and data.run.active then
    error("a run is already active")
  end
  data.run = {
    token = token,
    active = true,
    deadline = game.tick + math.floor(duration * 60),
  }
  return {
    token = data.run.token,
    active = true,
    deadline = data.run.deadline,
    started_tick = game.tick,
  }
end

function end_run()
  ensure_storage()
  local data = storage.save_safe_bridge
  if data.run ~= nil then
    data.run.active = false
  end
  local stopped = stop_all_actions()
  stopped.active = false
  return stopped
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

local DIRECTION_VALUES = {
  north = defines.direction.north,
  east = defines.direction.east,
  south = defines.direction.south,
  west = defines.direction.west,
}
local DIRECTION_NAMES = {
  [defines.direction.north] = "north",
  [defines.direction.east] = "east",
  [defines.direction.south] = "south",
  [defines.direction.west] = "west",
}

local function parse_direction(value)
  if value == nil then
    return nil
  end
  if type(value) ~= "string" or DIRECTION_VALUES[value] == nil then
    error("direction must be north, east, south, or west")
  end
  return DIRECTION_VALUES[value]
end

local function direction_name(value)
  return DIRECTION_NAMES[value] or tostring(value)
end

local function machine_owned(entity)
  local record = storage.save_safe_bridge.owned_machines[entity.unit_number]
  return type(record) == "table" and record.agent_id == AGENT_ID and record.entity_name == entity.name and record.surface == entity.surface.name
end

local function drop_target_ok(entity)
  local target = entity.drop_target
  if target == nil or not target.valid then
    return true
  end
  return machine_owned(target)
end

local function drop_target_summary(entity)
  local target = entity.drop_target
  if target == nil or not target.valid then
    return nil
  end
  return {
    name = target.name,
    unit_number = target.unit_number,
    x = target.position.x,
    y = target.position.y,
    owned = machine_owned(target),
  }
end

local function place_entity_core(request, entity_name)
  local agent = stored_agent()
  if agent == nil then
    error("AI character does not exist")
  end
  local movement = storage.save_safe_bridge.movement
  if movement.state == "walking" or movement.state == "pathing" then
    error("AI character is still moving")
  end
  local target = {x = finite_number(request.x, "x"), y = finite_number(request.y, "y")}
  local direction = parse_direction(request.direction) or defines.direction.north
  local buildable = agent.can_place_entity({name = entity_name, position = target, direction = direction})
  local clear = agent.surface.can_place_entity({
    name = entity_name,
    position = target,
    direction = direction,
    force = agent.force,
    build_check_type = defines.build_check_type.manual,
  })
  if not buildable or not clear then
    if distance(agent.position, target) > agent.build_distance then
      error("target is outside the AI character build distance")
    end
    error("target is blocked")
  end
  if agent.get_item_count(entity_name) < 1 then
    error("AI inventory has no " .. entity_name)
  end
  local created = agent.surface.create_entity({
    name = entity_name,
    position = target,
    force = agent.force,
    direction = direction,
  })
  if created == nil then
    error("placement failed")
  end
  -- Reject placements whose engine-chosen drop point feeds a non-owned building.
  if not drop_target_ok(created) then
    created.destroy()
    error("placement would output into a non-owned building")
  end
  local removed = agent.remove_item({name = entity_name, count = 1})
  if removed < 1 then
    created.destroy()
    error("failed to deduct the item from AI inventory")
  end
  record_owner(storage.save_safe_bridge, created)
  return {
    placed = true,
    item = entity_name,
    unit_number = created.unit_number,
    x = created.position.x,
    y = created.position.y,
    force = created.force.name,
    direction = direction_name(created.direction),
    owned = true,
    removed = removed,
    inventory_count = agent.get_item_count(entity_name),
    agent_unit_number = agent.unit_number,
  }
end

local function place_stone_furnace(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  validate_run(request)
  return place_entity_core(request, "stone-furnace")
end

local function place_item(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  validate_run(request)
  local entity_name = PLACEABLE_ITEMS[request.item]
  if entity_name == nil then
    error("item is not allowed for placement")
  end
  return place_entity_core(request, entity_name)
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
    if found == nil or not found.valid then
      for _, kind in pairs({"furnace", "mining-drill"}) do
        local nearby = agent.surface.find_entities_filtered({
          position = agent.position,
          radius = 96,
          type = kind,
        })
        for _, entity in pairs(nearby) do
          if entity.unit_number == unit_number then
            found = entity
            break
          end
        end
        if found ~= nil then
          break
        end
      end
    end
  else
    local x = finite_number(request.x, "x")
    local y = finite_number(request.y, "y")
    found = agent.surface.find_entity("stone-furnace", {x = x, y = y})
    if found == nil then
      found = agent.surface.find_entity("burner-mining-drill", {x = x, y = y})
    end
  end
  if found == nil or not found.valid or not MACHINE_NAMES[found.name] then
    error("machine does not exist or is not supported")
  end
  if found.surface ~= agent.surface then
    error("machine is on another surface")
  end
  if found.force.name ~= agent.force.name then
    error("machine belongs to another force")
  end
  if distance(agent.position, found.position) > 96 then
    error("machine is farther than 96 tiles from the agent")
  end
  return agent, found
end

local function require_reach(agent, entity)
  if not agent.can_reach_entity(entity) then
    error("machine is outside interaction reach")
  end
end

local function require_owned(entity)
  if not machine_owned(entity) then
    error("machine is not owned by the agent")
  end
end

local function machine_inventory(entity, kind)
  if entity.type == "mining-drill" then
    if kind ~= "fuel" then
      error("mining drills only support the fuel inventory")
    end
    return entity.get_fuel_inventory()
  end
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

local function burner_remaining_fuel(entity)
  if entity.burner == nil then
    return nil
  end
  return entity.burner.remaining_burning_fuel
end

local function inspect_entity_core(agent, entity)
  local base = {
    name = entity.name,
    type = entity.type,
    unit_number = entity.unit_number,
    x = entity.position.x,
    y = entity.position.y,
    status = entity_status_name(entity),
    direction = direction_name(entity.direction),
    owned = machine_owned(entity),
    reachable = agent ~= nil and agent.can_reach_entity(entity) or false,
  }
  if entity.type == "mining-drill" then
    -- Mining drills are not crafting machines; read drill-specific fields only.
    base.mining_progress = entity.mining_progress
    local target = entity.mining_target
    base.mining_target = (target ~= nil and target.valid) and {
      name = target.name,
      amount = target.amount,
      x = target.position.x,
      y = target.position.y,
    } or nil
    base.drop_position = {x = entity.drop_position.x, y = entity.drop_position.y}
    base.drop_target = drop_target_summary(entity)
    base.fuel = inventory_counts(entity.get_fuel_inventory())
    base.burner_remaining_fuel = burner_remaining_fuel(entity)
  else
    base.is_crafting = entity.is_crafting()
    base.crafting_progress = entity.crafting_progress or 0
    base.products_finished = entity.products_finished or 0
    base.fuel = inventory_counts(entity.get_fuel_inventory())
    base.input = inventory_counts(entity.get_inventory(defines.inventory.furnace_source))
    base.output = inventory_counts(entity.get_output_inventory())
    base.burner_remaining_fuel = burner_remaining_fuel(entity)
  end
  return base
end

local function inspect_entity(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local agent, entity = find_machine(request)
  return inspect_entity_core(agent, entity)
end

local function insert_into_entity(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  validate_run(request)
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
  require_owned(entity)
  require_reach(agent, entity)
  if agent.get_item_count(item) < count then
    error("AI inventory does not have enough items")
  end
  local inventory = machine_inventory(entity, kind)
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
  validate_run(request)
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
  require_owned(entity)
  require_reach(agent, entity)
  local inventory = machine_inventory(entity, kind)
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

local function rotate_entity(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  validate_run(request)
  local agent, entity = find_machine(request)
  require_owned(entity)
  require_reach(agent, entity)
  if entity.type ~= "mining-drill" then
    error("only mining drills can be rotated")
  end
  local direction = parse_direction(request.direction)
  if direction == nil then
    error("direction is required")
  end
  -- The drill must not feed a non-owned building before or after rotating.
  if not drop_target_ok(entity) then
    error("drill currently outputs into a non-owned building")
  end
  local previous = entity.direction
  entity.direction = direction
  if not drop_target_ok(entity) then
    entity.direction = previous
    error("rotation would output into a non-owned building")
  end
  return {
    unit_number = entity.unit_number,
    rotated = true,
    direction = direction_name(entity.direction),
    drop_position = {x = entity.drop_position.x, y = entity.drop_position.y},
    drop_target = drop_target_summary(entity),
  }
end

local function production_snapshot()
  ensure_storage()
  local data = storage.save_safe_bridge
  local agent = stored_agent()
  local machines = {}
  local drills = {}
  local total_resource_amount = 0
  local stale = {}
  for unit_number, record in pairs(data.owned_machines) do
    if type(record) == "table" and record.agent_id == AGENT_ID then
      local entity = nil
      if game.get_entity_by_unit_number ~= nil then
        entity = game.get_entity_by_unit_number(unit_number)
      end
      if entity == nil or not entity.valid then
        -- get_entity_by_unit_number is unreliable here; fall back to the stored placement position.
        local surface = game.surfaces[record.surface]
        if surface ~= nil then
          local found = surface.find_entities_filtered({name = record.entity_name, position = {x = record.x, y = record.y}, radius = 0.5, force = "player"})
          for _, candidate in pairs(found) do
            if candidate.valid and candidate.unit_number == unit_number then
              entity = candidate
              break
            end
          end
        end
      end
      if entity ~= nil and entity.valid and machine_owned(entity) then
        machines[#machines + 1] = inspect_entity_core(agent, entity)
        if entity.type == "mining-drill" then
          local resources = {}
          local amount = 0
          local found = entity.surface.find_entities_filtered({area = entity.mining_area, type = "resource"})
          for _, resource in pairs(found) do
            resources[resource.name] = (resources[resource.name] or 0) + resource.amount
            amount = amount + resource.amount
          end
          total_resource_amount = total_resource_amount + amount
          drills[#drills + 1] = {
            unit_number = entity.unit_number,
            mining_area = {
              left_top = {x = entity.mining_area.left_top.x, y = entity.mining_area.left_top.y},
              right_bottom = {x = entity.mining_area.right_bottom.x, y = entity.mining_area.right_bottom.y},
            },
            resource_amount = amount,
            resources = resources,
          }
        end
      end
    end
  end
  return {
    tick = game.tick,
    machine_count = #machines,
    machines = machines,
    mining_coverage = {
      total_resource_amount = total_resource_amount,
      drills = drills,
    },
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

function action_snapshot()
  ensure_storage()
  local action = storage.save_safe_bridge.action
  local agent = storage.save_safe_bridge.agent_entity
  local crafting_queue_size = 0
  if agent ~= nil and agent.valid then
    crafting_queue_size = agent.crafting_queue_size or 0
  end
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
    crafting_queue_size = crafting_queue_size,
    tick = game.tick,
  }
end

local function mine_resource(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  validate_run(request)
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

local function read_prototype_field(prototype, field)
  local ok, value = pcall(function()
    return prototype[field]
  end)
  if not ok then
    return nil
  end
  return value
end

local function inspect_item(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  local item_name = request.item
  if type(item_name) ~= "string" or item_name == "" then
    error("item is required")
  end
  local prototype = prototypes.item[item_name]
  if prototype == nil then
    error("unknown item")
  end
  local place_result = prototype.place_result
  local result = {
    item = item_name,
    place_result_name = place_result ~= nil and place_result.name or nil,
  }
  if place_result == nil then
    return result
  end
  -- Report raw prototype facts only, never layout advice.
  local collision_box = read_prototype_field(place_result, "collision_box")
  if collision_box ~= nil then
    result.collision_box = {
      left_top = {x = collision_box.left_top.x, y = collision_box.left_top.y},
      right_bottom = {x = collision_box.right_bottom.x, y = collision_box.right_bottom.y},
    }
  end
  result.tile_width = read_prototype_field(place_result, "tile_width")
  result.tile_height = read_prototype_field(place_result, "tile_height")
  result.type = place_result.type
  result.mining_speed = read_prototype_field(place_result, "mining_speed")
  result.resource_searching_radius = read_prototype_field(place_result, "resource_searching_radius")
  result.vector_to_place_result = read_prototype_field(place_result, "vector_to_place_result")
  return result
end

local function craft_item(request)
  if type(request) ~= "table" then
    error("request must be a table")
  end
  validate_run(request)
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
  if data == nil or data.action == nil then
    return
  end
  local action = data.action
  local agent = stored_agent()
  if action.kind == "crafting" then
    if agent == nil then
      action.kind = "failed"
      action.reason = "AI character is missing"
      return
    end
    if agent.crafting_queue_size == 0 then
      action.kind = action.crafted > 0 and "crafted" or "failed"
      action.reason = action.crafted > 0 and "" or "crafting did not complete"
    end
    return
  end
  if action.kind ~= "mining" then
    return
  end
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

local function ownership_debug()
  ensure_storage()
  local keys = {}
  for unit_number, record in pairs(storage.save_safe_bridge.owned_machines) do
    keys[#keys + 1] = {unit_number = unit_number, agent_id = type(record) == "table" and record.agent_id or ""}
  end
  return {schema = storage.save_safe_bridge.schema, count = #keys, records = keys}
end

script.on_init(ensure_storage)
script.on_configuration_changed(ensure_storage)
script.on_event(defines.events.on_tick, function()
  ensure_storage()
  local run = storage.save_safe_bridge.run
  if run ~= nil and run.active and game.tick >= run.deadline then
    run.active = false
    stop_all_actions()
    update_locator()
    return
  end
  update_walking()
  update_action()
  update_locator()
end)
script.on_event(defines.events.on_script_path_request_finished, on_path_finished)

remote.add_interface(INTERFACE_NAME, {
  get_entities = get_entities,
  status = status,
  ownership_debug = ownership_debug,
  ensure_agent_character = ensure_agent_character,
  agent_status = agent_status,
  walk_to = walk_to,
  movement_status = movement_snapshot,
  stop_agent = stop_agent,
  place_stone_furnace = place_stone_furnace,
  place_item = place_item,
  inventory = inventory_summary,
  scan_resources = scan_resources,
  mine_resource = mine_resource,
  inspect_recipe = inspect_recipe,
  inspect_smelting_recipe = inspect_smelting_recipe,
  inspect_item = inspect_item,
  inspect_entity = inspect_entity,
  insert_into_entity = insert_into_entity,
  take_from_entity = take_from_entity,
  rotate_entity = rotate_entity,
  production_snapshot = production_snapshot,
  craft_item = craft_item,
  action_status = action_snapshot,
  locate = locate,
  begin_run = begin_run,
  claim_historical_furnace = claim_historical_furnace,
  claim_units = claim_units,
  end_run = end_run,
})
