local INTERFACE_NAME = "save_safe_bridge"
local MAX_RADIUS = 32

local AGENT_COLOR = {r = 0.2, g = 0.6, b = 1.0, a = 1.0}

local function ensure_storage()
  if storage.save_safe_bridge == nil then
    storage.save_safe_bridge = {}
  end
  local data = storage.save_safe_bridge
  data.schema = 2
  data.query_count = data.query_count or 0
  if data.agent_unit_number == nil then
    data.agent_unit_number = 0
  end
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

local function status()
  ensure_storage()
  return {
    schema = storage.save_safe_bridge.schema,
    query_count = storage.save_safe_bridge.query_count,
  }
end

script.on_init(ensure_storage)
script.on_configuration_changed(ensure_storage)

remote.add_interface(INTERFACE_NAME, {
  get_entities = get_entities,
  status = status,
  ensure_agent_character = ensure_agent_character,
  agent_status = agent_status,
})
