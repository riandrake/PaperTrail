package.path = package.path .. ";data/scripts/lib/?.lua"
include("bit32")
local Config = include("ConfigLoader")

-- namespace PaperTrail
PaperTrail = {}

if onClient() then

function PaperTrail.djb2(name)
  local hash = 5381
  local n = #name
  for i=1, n do
    hash = (bit32.lshift(hash, 5) + hash) + string.byte(name:sub(i,i))
  end
  return hash;
end

function PaperTrail.hashStringToColor(name)
  local hash = PaperTrail.djb2(name)
  local r = bit32.rshift(bit32.band(hash, 0xFF0000), 16);
  local g = bit32.rshift(bit32.band(hash, 0x00FF00), 8);
  local b = bit32.band(hash, 0x0000FF);
  return {r = r/512, g = g/512, b = b/512}
end

function PaperTrail.toColor(pod, a, m)
	return ColorARGB(a, pod.r * m, pod.g * m, pod.b * m)
end

function PaperTrail.initialize()
	-- Register callbacks
	local player = Player()
	player:registerCallback("onShipInfoAdded", "onShipInfoAdded")
	player:registerCallback("onShipInfoRemoved", "onShipInfoRemoved")
	player:registerCallback("onShipPositionUpdated", "onShipPositionUpdated")
	player:registerCallback("onShipNameUpdated", "onShipNameUpdated")
    player:registerCallback("onGalaxyMapUpdate", "onGalaxyMapUpdate")
    player:registerCallback("onPostRenderHud", "onPostRenderHud")

	-- Create root container
    PaperTrail.routesContainer = GalaxyMap():createContainer(Rect())

    -- Create empty table to hold all ship data
    PaperTrail.shipContainers = {}
end

function PaperTrail.refreshVisibility(timeStep)
    local sx, sy = GalaxyMap():getSelectedCoordinates()
    local selected_pos = ivec2(sx, sy)

	-- Show all containers in selected sector
	for _, shipData in pairs(PaperTrail.shipContainers) do
		if shipData.pos ~= selected_pos then
			shipData.container:hide()
		else
			shipData.container:show()
		end

		shipData.is_selected = false
	end

	-- Show all containers that are selected ships
    local selected_portraits = MapCommands.getSelectedPortraits()
    for _, portrait in pairs(selected_portraits) do
    	local shipData = PaperTrail.shipContainers[portrait.name]
    	if shipData ~= nil then
			shipData.is_selected = true
			shipData.container:show()
		end
    end

    -- Show containers for piloted ships
    local player = Player()
    if player and player.craft then
    	local shipData = PaperTrail.shipContainers[player.craft.name]
    	if shipData ~= nil then
    		shipData.is_selected = true
    		shipData.container:show()
    	end
    end

    -- Update colors for all visible containers
	for _, shipData in pairs(PaperTrail.shipContainers) do
		if shipData.container.visible then
			assert(shipData.line_head, "bad line_head")
			PaperTrail.updateColor(shipData)
		end
	end
end

function PaperTrail.onGalaxyMapUpdate(timeStep)
	PaperTrail.refreshVisibility()
end

function PaperTrail.onPostRenderHud(timeStep)
	PaperTrail.refreshVisibility()
end

function PaperTrail.onShipInfoAdded(name)

	-- Create a new table for this ship
	local shipData = { name=name, is_selected=false, pos=nil, line_head=nil, color_hash=nil }
	shipData.container = PaperTrail.routesContainer:createContainer(Rect())
	shipData.container:hide()

	-- Allocate the arrows for this ship
	local current = nil
	local first = nil

    shipData.color_hash = PaperTrail.hashStringToColor(name)

    for i=1,Config.maxTrails do

    	-- Create a new arrow
	    local line = shipData.container:createMapArrowLine()
	    line.from = ivec2(0,0)
	    line.to = ivec2(0,0)
	    line.width = 10
	    line.tooltip = name
	    line:hide()

	    -- Wrap it in a linked list node
	    local pod = { arrow=line, next_item=nil }

	    -- Set next of current node, or cache this node as the first node
	    if current ~= nil then
	    	current.next_item = pod
	    else
	    	first = pod
	    end

	    -- Set new pod as the current
	    current = pod
	end

	-- Close the linked list so that it's circular
	current.next_item = first

	-- Save the list to ship data
	shipData.line_head = current
	assert(shipData.line_head, "bad line_head")

	local portraits = MapCommands.getPortraits()
	for _, portrait in pairs(portraits) do
		if portrait.name == name then
			shipData.pos = ivec2(portrait.coordinates.x,portrait.coordinates.y)
			break
		end
	end

    PaperTrail.updateColor(shipData)

	-- Store the data
	PaperTrail.shipContainers[name] = shipData
end

function PaperTrail.onShipInfoRemoved(name)
	-- Clear data
	PaperTrail.shipContainers[name] = nil
end

function PaperTrail.updateColor(shipData)
	local max_alpha = 0.5
	local max = Config.maxTrails
	local alpha_per = max_alpha / max

	local m = 1.0
	if shipData.is_selected == true then
		m = 2.0
	end

	local idx = 1
	local pod = shipData.line_head
	assert(pod, "bad node")
    pod.arrow.color = PaperTrail.toColor(shipData.color_hash, idx * alpha_per, m)

    pod = pod.next_item
    idx = idx + 1

    while pod ~= shipData.line_head do
	    pod.arrow.color = PaperTrail.toColor(shipData.color_hash, idx * alpha_per, m)
	    pod = pod.next_item
	    idx = idx + 1
    end
end

function PaperTrail.onShipNameUpdated(name, newName)
	local shipData = PaperTrail.shipContainers[name]
	if shipData ~= nil then
	    shipData.color_hash = PaperTrail.hashStringToColor(newName)
	    PaperTrail.updateColor(shipData)
	end
end

function PaperTrail.onShipPositionUpdated(name, x, y)
	-- Get the ship data
	local shipData = PaperTrail.shipContainers[name]

	-- Temp workaround because onShipInfoAdded isn't being called
	if shipData == nil then
		PaperTrail.onShipInfoAdded(name)
		shipData = PaperTrail.shipContainers[name]
	end

	-- Ignore net-zero changes
	local new_to = ivec2(x,y)
	if new_to == shipData.pos then
		return
	end

	if shipData.pos ~= nil then
		-- Get the arrow at the top of the list
		local pod = shipData.line_head
		local arrow = pod.arrow

		-- Move it to the new location
		arrow:show()
		arrow.from = shipData.pos
		arrow.to = new_to

		-- Fade out older trails
		PaperTrail.updateColor(shipData)

		-- Rotate the list
		shipData.line_head = pod.next_item
		assert(shipData.line_head, "bad line_head")
	end

	-- Cache the new location
	shipData.pos = new_to
end

end