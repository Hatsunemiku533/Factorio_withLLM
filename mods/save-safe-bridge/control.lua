local INTERFACE_NAME = "save_safe_bridge"
local MAX_RADIUS = 32

local function ensure_storage()
  if storage.save_safe_bridge == nil then
    storage.save_safe_bridge = {
      schema = 1,
      query_count = 0,
    }
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
})
