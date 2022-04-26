-- Author: Toastery
-- GitHub: https://github.com/Toast732
-- Workshop: 
--
--- Developed using LifeBoatAPI - Stormworks Lua plugin for VSCode - https://code.visualstudio.com/download (search "Stormworks Lua with LifeboatAPI" extension)
--- If you have any issues, please report them here: https://github.com/nameouschangey/STORMWORKS_VSCodeExtension/issues - by Nameous Changey

-- library prefixes
local debugging = {} -- functions related to debugging
local cache = {}

-- shortened library names
local d = debugging
local s = server
local m = matrix

local STORMHAUL_VERSION = "(0.1.0.3)"
local IS_DEVELOPMENT_VERSION = string.match(STORMHAUL_VERSION, "(%d%.%d%.%d%.%d)")

-- valid values:
-- "TRUE" if this version will be able to run perfectly fine on old worlds
-- "FULL_RELOAD" if this version will need to do a full reload to work properly
-- "FALSE" if this version has not been tested or its not compatible with older versions
local IS_COMPATIBLE_WITH_OLDER_VERSIONS = "FALSE"

local time = { -- the time unit in ticks, irl time, not in game
	second = 60,
	minute = 3600,
	hour = 216000,
	day = 5184000
}

local CARGO_TYPE_BASIC = "basic"
local CARGO_TYPE_FRAGILE = "fragile"
local CARGO_TYPE_FLAMMABLE = "flammable"
local CARGO_TYPE_EXPLOSIVE = "explosive"

g_savedata = {
	tick_counter = 0,
	player_data = {},
	prefabs = {
		cargo = {},
		vehicles = {},
		structures = {}
	},
	depots = {},
	cargo = {},
	cache = {
		depot_distances = {}
	},
	cache_stats = {
		reads = 0,
		writes = 0,
		failed_writes = 0,
		resets = 0
	},
	profiler = {
		working = {},
		total = {},
		display = {
			average = {},
			max = {},
			current = {}
		},
		ui_id = nil
	},
	debug = {
		chat = false,
		profiler = false,
		map = false
	}
}

function onCreate(is_world_create)
	local world_setup_time = s.getTimeMillisec()
	s.announce("Loading Script: " .. s.getAddonData((s.getAddonIndex())).name, "Complete, Version: "..STORMHAUL_VERSION, -1)

	if is_world_create then
		setupWorld()
	end
	d.print(("%s%.3f%s"):format("World setup complete! took: ", millisecondsSince(world_setup_time)/1000, "s"), true, -1)
end

function setupWorld()
	for i in iterPlaylists() do
		for j in iterLocations(i) do
			build_locations(i, j)
		end
	end
	for i = 1, #built_locations do
		buildPrefabs(i)
	end
end

-- tick the cargo timers
function tickCargo()
	for cargo_index, cargo in pairs(g_savedata.cargo) do -- for all cargo
		if isTickID(cargo_index, time.second) then -- tick every second
			
		end
	end
end

-- tick the depot timers
function tickDepots()

end

function onTick()
	g_savedata.tick_counter = g_savedata.tick_counter + 1
	d.startProfiler("onTick()", true)
	tickCargo()
	tickDepots()
	d.stopProfiler("onTick()", true, "onTick()")
end

function onPlayerJoin(steam_id, name, peer_id)
	-- create playerdata if it does not already exist
	if not g_savedata.player_data[tostring(steam_id)] then
		g_savedata.player_data[tostring(steam_id)] = {
			peer_id = peer_id,
			name = name,
			debug = {
				chat = false,
				profiler = false,
				map = false
			},
			stats = {
				rep = 0,
				completed_deliveries = 0
			}
		}
	end

	-- update the player's peer_id
	g_savedata.player_data[tostring(steam_id)].peer_id = peer_id
end

--------------------------------------------------------------------------------
--
-- WORLD SETUP
--
--------------------------------------------------------------------------------

function build_locations(playlist_index, location_index)
    local location_data = s.getLocationData(playlist_index, location_index)

    local addon_components = {
        vehicles = {},
        objects = {},
		zones = {},
		fires = {}
    }

    local is_valid_location = false

    for object_index, object_data in iterObjects(playlist_index, location_index) do

        for tag_index, tag_object in pairs(object_data.tags) do
            if tag_object == "from=StormHaul" then
                is_valid_location = true
            end
        end

        if object_data.type == "vehicle" then
			table.insert(addon_components.vehicles, object_data)
		elseif object_data.type == "fire" then
			table.insert(addon_components.fires, object_data)
        elseif object_data.type == "object" then
            table.insert(addon_components.objects, object_data)
		elseif object_data.type == "zone" then
			table.insert(addon_components.zones, object_data)
        end
    end

    if is_valid_location then
    	table.insert(built_locations, { playlist_index = playlist_index, location_index = location_index, data = location_data, objects = addon_components} )
    end
end

function buildPrefabs(location_index)
    local location = built_locations[location_index]

	-- construct prefab list
	local vehicle_index = #g_savedata.vehicle_list + 1 or 1
	for key, vehicle in pairs(location.objects.vehicles) do

		local prefab_data = {location = location, vehicle = vehicle, fires = {}}

		for key, fire in pairs(location.objects.fires) do
			table.insert(prefab_data.fires, fire)
		end

		local vehicle_type = getTagValue(vehicle.tags, "vehicle_type", true) -- cargo, depot, forklift
		
		table.insert(g_savedata.prefabs[prefab_type], prefab_data)
	end
end

--------------------------------------------------------------------------------
--
-- UTILITIES
--
--------------------------------------------------------------------------------

---@param id integer the tick you want to check that it is
---@param rate integer the total amount of ticks, for example, a rate of 60 means it returns true once every second* (if the tps is not low)
---@return boolean isTick if its the current tick that you requested
function isTickID(id, rate)
	return (g_savedata.tick_counter + id) % rate == 0
end

-- iterator function for iterating over all playlists, skipping any that return nil data
function iterPlaylists()
	local playlist_count = s.getAddonCount()
	local playlist_index = 0

	return function()
		local playlist_data = nil
		local index = playlist_count

		while playlist_data == nil and playlist_index < playlist_count do
			playlist_data = s.getAddonData(playlist_index)
			index = playlist_index
			playlist_index = playlist_index + 1
		end

		if playlist_data ~= nil then
			return index, playlist_data
		else
			return nil
		end
	end
end

-- iterator function for iterating over all locations in a playlist, skipping any that return nil data
function iterLocations(playlist_index)
	local playlist_data = s.getAddonData(playlist_index)
	local location_count = 0
	if playlist_data ~= nil then location_count = playlist_data.location_count end
	local location_index = 0

	return function()
		local location_data = nil
		local index = location_count

		while not location_data and location_index < location_count do
			location_data = s.getLocationData(playlist_index, location_index)
			index = location_index
			location_index = location_index + 1
		end

		if location_data ~= nil then
			return index, location_data
		else
			return nil
		end
	end
end

function hasTag(tags, tag)
	if type(tags) == "table" then
		for k, v in pairs(tags) do
			if v == tag then
				return true
			end
		end
	else
		d.print("hasTag() was expecting a table, but got a "..type(tags).." instead! searching for tag: "..tag.." (this can be safely ignored)", true, 1)
	end
	return false
end

-- gets the value of the specifed tag, returns nil if tag not found
function getTagValue(tags, tag, as_string)
	if type(tags) == "table" then
		for k, v in pairs(tags) do
			if string.match(v, tag.."=") then
				if not as_string then
					return tonumber(tostring(string.gsub(v, tag.."=", "")))
				else
					return tostring(string.gsub(v, tag.."=", ""))
				end
			end
		end
	else
		d.print("getTagValue() was expecting a table, but got a "..type(tags).." instead! searching for tag: "..tag.." (this can be safely ignored)", true, 1)
	end
	return nil
end

--------------------------------------------------------------------------------
--
-- Cache Functions
--
--------------------------------------------------------------------------------

---@param location ?g_savedata.cache[] where to reset the data, if left blank then resets all cache data
---@param boolean success returns true if successfully cleared the cache
function cache.reset(location) -- resets the cache
	if not location then
		g_savedata.cache = {}
	else
		if g_savedata.cache[location] then
			g_savedata.cache[location] = nil
		else
			if not g_savedata.cache_stats.failed_resets then
				g_savedata.cache_stats.failed_resets = 0
			end
			g_savedata.cache_stats.failed_resets = g_savedata.cache_stats.failed_resets + 1
			return false
		end
	end
	g_savedata.cache_stats.resets = g_savedata.cache_stats.resets + 1
	return true
end

---@param location g_savedata.cache[] where to write the data
---@param data any the data to write at the location
---@return boolean write_successful if writing the data to the cache was successful
function cache.write(location, data)

	if type(g_savedata.cache[location]) ~= "table" then
		d.print("Data currently at the cache of "..tostring(location)..": "..tostring(g_savedata.cache[location]), true, 0)
	else
		d.print("Data currently at the cache of "..tostring(location)..": (table)", true, 0)
	end

	g_savedata.cache[location] = data

	if type(g_savedata.cache[location]) ~= "table" then
		d.print("Data written to the cache of "..tostring(location)..": "..tostring(g_savedata.cache[location]), true, 0)
	else
		d.print("Data written to the cache of "..tostring(location)..": (table)", true, 0)
	end

	if g_savedata.cache[location] == data then
		g_savedata.cache_stats.writes = g_savedata.cache_stats.writes + 1
		return true
	else
		g_savedata.cache_stats.failed_writes = g_savedata.cache_stats.failed_writes + 1
		return false
	end
end

---@param location g_savedata.cache[] where to read the data from
---@return any data the data that was at the location
function cache.read(location)
	g_savedata.cache_stats.reads = g_savedata.cache_stats.reads + 1
	if type(g_savedata.cache[location]) ~= "table" then
		d.print("reading cache data at\ng_savedata.cache."..tostring(location).."\n\nData: "..g_savedata.cache[location], true, 0)
	else
		d.print("reading cache data at\ng_savedata.cache."..tostring(location).."\n\nData: (table)", true, 0)
	end
	return g_savedata.cache[location]
end

---@param location g_savedata.cache[] where to check
---@return boolean exists if the data exists at the location
function cache.exists(location)
	if g_savedata.cache[location] or g_savedata.cache[location] == false then
		d.print("g_savedata.cache."..location.." exists", true, 0)
		return true
	end
	d.print("g_savedata.cache."..location.." doesn't exist", true, 0)
	return false
end

--------------------------------------------------------------------------------
--
-- Debugging Functions
--
--------------------------------------------------------------------------------

---@param message string the message you want to print
---@param requires_debug boolean if it requires <debug_type> debug to be enabled
---@param debug_type integer the type of message, 0 = debug (debug.chat) | 1 = error (debug.chat) | 2 = profiler (debug.profiler) 
---@param peer_id integer if you want to send it to a specific player, leave empty to send to all players
function debugging.print(message, requires_debug, debug_type, peer_id) -- glorious debug function

	if IS_DEVELOPMENT_VERSION or not requires_debug or requires_debug and d.getDebug(debug_type, peer_id) or requires_debug and debug_type == 2 and d.getDebug(0, peer_id) then
		local suffix = debug_type == 1 and " Error:" or debug_type == 2 and " Profiler:" or " Debug:"
		local prefix = string.gsub(s.getAddonData((s.getAddonIndex())).name, "%(.*%)", STORMHAUL_VERSION)..suffix

		if type(message) ~= "table" and IS_DEVELOPMENT_VERSION then
			if message then
				debug.log("SW STORMHAUL "..suffix.." | "..string.gsub(message, "\n", " \\n "))
			else
				debug.log("SW STORMHAUL "..suffix.." | (d.print) message is nil!")
			end
		end
		
		if type(message) == "table" then
			printTable(message, requires_debug, debug_type, peer_id)

		elseif requires_debug then
			if isPlayer(peer_id) and peer_id then
				if g_savedata.player_data.is_debugging.toPlayer then
					s.announce(prefix, message, peer_id)
				end
			else
				local player_list = s.getPlayers()
				for peer_index, player in pairs(player_list) do
					if d.getDebug(debug_type, player.id) or debug_type == 2 and d.getDebug(0, player.id) then
						s.announce(prefix, message, player_id)
					end
				end
			end
		else
			s.announce(prefix, message, peer_id or "-1")
		end
	end
end

---@param debug_type integer the type of debug | 0 = debug | 1 = error | 2 = profiler | 3 = map
---@param peer_id ?integer the peer_id of the player you want to check if they have it enabled, leave blank to check globally
---@return boolean enabled if the specified type of debug is enabled
function debugging.getDebug(debug_type, peer_id)
	if not peer_id or notPlayer(peer_id) then -- if any player has it enabled
		if debug_type == -1 then -- any debug
			if g_savedata.debug.chat or g_savedata.debug.profiler or g_savedata.debug.map then
				return true
			end
		elseif not debug_type or debug_type == 0 or debug_type == 1 then -- chat debug
			if g_savedata.debug.chat then
				return true
			end
		elseif debug_type == 2 then -- profiler debug
			if g_savedata.debug.profiler then
				return true
			end
		elseif debug_type == 3 then -- map debug
			if g_savedata.debug.map then
				return true
			end
		else
			d.print("(d.getDebug) debug_type "..tostring(debug_type).." is not a valid debug type!", true, 1)
		end
	else -- if a specific player has it enabled
		local steam_id = getSteamID(peer_id)
		if steam_id and g_savedata.player_data[steam_id] then -- makes sure the steam id and player data exists
			if debug_type == -1 then -- any debug
				if g_savedata.player_data[steam_id].debug.chat or g_savedata.player_data[steam_id].debug.profiler or g_savedata.player_data[steam_id].debug.map then
					return true
				end
			elseif not debug_type or debug_type == 0 or debug_type == 1 then -- chat debug
				if g_savedata.player_data[steam_id].debug.chat then
					return true
				end
			elseif debug_type == 2 then -- profiler debug
				if g_savedata.player_data[steam_id].debug.profiler then
					return true
				end
			elseif debug_type == 3 then -- map debug
				if g_savedata.player_data[steam_id].debug.map then
					return true
				end
			else
				d.print("(d.getDebug) debug_type "..tostring(debug_type).." is not a valid debug type! peer_id requested: "..tostring(peer_id), true, 1)
			end
		end
	end
	return false
end

function debugging.setDebug(requested_debug_type, peer_id)
	if requested_debug_type then
		if peer_id then
			local steam_id = getSteamID(peer_id)
			if requested_debug_type == -1 then -- all debug
				local none_true = true
				for debug_type, _ in pairs(g_savedata.player_data[steam_id].debug) do -- disable all debug
					if g_savedata.player_data[steam_id].debug[debug_type] then
						none_true = false
						g_savedata.player_data[steam_id].debug[debug_type] = false
					end
				end

				if none_true then -- if none was enabled, then enable all
					for debug_type, _ in pairs(g_savedata.player_data[steam_id].debug) do
						g_savedata.player_data[steam_id].debug[debug_type] = true
					end
					g_savedata.debug.chat = true
					g_savedata.debug.profiler = true
					g_savedata.debug.map = true
					return "Enabled All Debug"
				else
					d.checkDebug()


					-- remove map debug
					for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
						for vehicle_id, vehicle_object in pairs(squad.vehicles) do
							s.removeMapObject(peer_id, vehicle_object.map_id)
							s.removeMapLine(peer_id, vehicle_object.map_id)
							for i = 1, #vehicle_object.path - 1 do
								local waypoint = vehicle_object.path[i]
								s.removeMapLine(peer_id, waypoint.ui_id)
							end
						end
					end

					-- remove profiler debug
					s.removePopup(peer_id, g_savedata.profiler.ui_id)

					for island_index, island in pairs(g_savedata.controllable_islands) do
						updatePeerIslandMapData(peer_id, island)
					end

					updatePeerIslandMapData(peer_id, g_savedata.player_base_island)
					updatePeerIslandMapData(peer_id, g_savedata.ai_base_island)


					return "Disabled All Debug"
				end
				
			elseif requested_debug_type == 0 or requested_debug_type == 1 then -- chat debug
				g_savedata.player_data[steam_id].debug.chat = not g_savedata.player_data[steam_id].debug.chat
				if g_savedata.player_data[steam_id].debug.chat then
					g_savedata.debug.chat = true
					return "Enabled Chat Debug"
				else
					d.checkDebug()
					return "Disabled Chat Debug"
				end
			elseif requested_debug_type == 2 then -- profiler debug
				g_savedata.player_data[steam_id].debug.profiler = not g_savedata.player_data[steam_id].debug.profiler
				if g_savedata.player_data[steam_id].debug.profiler then
					g_savedata.debug.profiler = true
					return "Enabled Profiler Debug"
				else
					d.checkDebug()

					-- remove profiler debug
					s.removePopup(peer_id, g_savedata.profiler.ui_id)

					-- clean all the profiler debug, if its disabled globally
					d.cleanProfilers()

					return "Disabled Profiler Debug"
				end
			elseif requested_debug_type == 3 then -- map debug
				g_savedata.player_data[steam_id].debug.map = not g_savedata.player_data[steam_id].debug.map
				if g_savedata.player_data[steam_id].debug.map then
					g_savedata.debug.map = true
					return "Enabled Map Debug"
				else
					d.checkDebug()

					-- remove map debug
					for squad_index, squad in pairs(g_savedata.ai_army.squadrons) do
						for vehicle_id, vehicle_object in pairs(squad.vehicles) do
							s.removeMapObject(peer_id, vehicle_object.map_id)
							s.removeMapLine(peer_id, vehicle_object.map_id)
							for i = 1, #vehicle_object.path - 1 do
								local waypoint = vehicle_object.path[i]
								s.removeMapLine(peer_id, waypoint.ui_id)
							end
						end
					end

					for island_index, island in pairs(g_savedata.controllable_islands) do
						updatePeerIslandMapData(peer_id, island)
					end
					
					updatePeerIslandMapData(peer_id, g_savedata.player_base_island)
					updatePeerIslandMapData(peer_id, g_savedata.ai_base_island)


					return "Disabled Map Debug"
				end
			end
		else
			d.print("(d.setDebug) a peer_id was not specified! debug type: "..tostring(debug_type), true, 1)
		end
	else
		d.print("(d.setDebug) the debug type was not specified!", true, 1)
	end
end

function debugging.checkDebug() -- checks all debugging types to see if anybody has it enabled, if not, disable them to save on performance
	local keep_enabled = {}

	-- check all debug types for all players to see if they have it enabled or disabled
	local player_list = s.getPlayers()
	for peer_index, peer in pairs(player_list) do
		local steam_id = getSteamID(peer.id)
		for debug_type, debug_type_enabled in pairs(g_savedata.player_data[steam_id].debug) do
			-- if nobody's known to have it enabled
			if not keep_enabled[debug_type] then
				-- then set it to whatever this player's value was
				keep_enabled[debug_type] = debug_type_enabled
			end
		end
	end

	-- any debug types that are disabled for all players, we want to disable globally to save on performance
	for debug_type, should_keep_enabled in pairs(keep_enabled) do
		-- if its not enabled for anybody
		if not should_keep_enabled then
			-- disable the debug globally
			g_savedata.debug[debug_type] = should_keep_enabled
		end
	end
end

-----
-- Profilers
-----

---@param unique_name string a unique name for the profiler  
function debugging.startProfiler(unique_name, requires_debug)
	-- if it doesnt require debug or
	-- if it requires debug and debug for the profiler is enabled or
	-- if this is a development version
	if not requires_debug or requires_debug and g_savedata.debug.profiler then
		if unique_name then
			if not g_savedata.profiler.working[unique_name] then
				g_savedata.profiler.working[unique_name] = s.getTimeMillisec()
			else
				d.print("A profiler named "..unique_name.." already exists", true, 1)
			end
		else
			d.print("A profiler was attempted to be started without a name!", true, 1)
		end
	end
end

function debugging.stopProfiler(unique_name, requires_debug, profiler_group)
	-- if it doesnt require debug or
	-- if it requires debug and debug for the profiler is enabled or
	-- if this is a development version
	if not requires_debug or requires_debug and g_savedata.debug.profiler then
		if unique_name then
			if g_savedata.profiler.working[unique_name] then
				tabulate(g_savedata.profiler.total, profiler_group, unique_name, "timer")
				g_savedata.profiler.total[profiler_group][unique_name]["timer"][g_savedata.tick_counter] = s.getTimeMillisec()-g_savedata.profiler.working[unique_name]
				g_savedata.profiler.total[profiler_group][unique_name]["timer"][(g_savedata.tick_counter-60)] = nil
				g_savedata.profiler.working[unique_name] = nil
			else
				d.print("A profiler named "..unique_name.." doesn't exist", true, 1)
			end
		else
			d.print("A profiler was attempted to be started without a name!", true, 1)
		end
	end
end

function debugging.showProfilers(requires_debug)
	if g_savedata.debug.profiler then
		if g_savedata.profiler.total then
			if not g_savedata.profiler.ui_id then
				g_savedata.profiler.ui_id = s.getMapID()
			end
			d.generateProfilerDisplayData()

			local debug_message = "Profilers\navg|max|cur (ms)"
			debug_message = d.getProfilerData(debug_message)

			local player_list = s.getPlayers()
			for peer_index, peer in pairs(player_list) do
				if d.getDebug(2, peer.id) then
					s.setPopupScreen(peer.id, g_savedata.profiler.ui_id, "Profilers", true, debug_message, -0.92, 0.2)
				end
			end
		end
	end
end

function debugging.getProfilerData(debug_message)
	for debug_name, debug_data in pairs(g_savedata.profiler.display.average) do
		debug_message = ("%s\n--\n%s: %.2f|%.2f|%.2f"):format(debug_message, debug_name, debug_data, g_savedata.profiler.display.max[debug_name], g_savedata.profiler.display.current[debug_name])
	end
	return debug_message
end

function debugging.generateProfilerDisplayData(t, old_node_name)
	if not t then
		for node_name, node_data in pairs(g_savedata.profiler.total) do
			if type(node_data) == "table" then
				d.generateProfilerDisplayData(node_data, node_name)
			elseif type(node_data) == "number" then
				-- average the data over the past 60 ticks and save the result
				local data_total = 0
				local valid_ticks = 0
				for i = 0, 60 do
					valid_ticks = valid_ticks + 1
					data_total = data_total + g_savedata.profiler.total[node_name][(g_savedata.tick_counter-i)]
				end
				g_savedata.profiler.display.average[node_name] = data_total/valid_ticks -- average usage over the past 60 ticks
				g_savedata.profiler.display.max[node_name] = max_node -- max usage over the past 60 ticks
				g_savedata.profiler.display.current[node_name] = g_savedata.profiler.total[node_name][(g_savedata.tick_counter)] -- usage in the current tick
			end
		end
	else
		for node_name, node_data in pairs(t) do
			if type(node_data) == "table" and node_name ~= "timer" then
				d.generateProfilerDisplayData(node_data, node_name)
			elseif node_name == "timer" then
				-- average the data over the past 60 ticks and save the result
				local data_total = 0
				local valid_ticks = 0
				local max_node = 0
				for i = 0, 60 do
					if t[node_name] and t[node_name][(g_savedata.tick_counter-i)] then
						valid_ticks = valid_ticks + 1
						-- set max tick time
						if max_node < t[node_name][(g_savedata.tick_counter-i)] then
							max_node = t[node_name][(g_savedata.tick_counter-i)]
						end
						-- set average tick time
						data_total = data_total + t[node_name][(g_savedata.tick_counter-i)]
					end
				end
				g_savedata.profiler.display.average[old_node_name] = data_total/valid_ticks -- average usage over the past 60 ticks
				g_savedata.profiler.display.max[old_node_name] = max_node -- max usage over the past 60 ticks
				g_savedata.profiler.display.current[old_node_name] = t[node_name][(g_savedata.tick_counter)] -- usage in the current tick
			end
		end
	end
end

function debugging.cleanProfilers() -- resets all profiler data in g_savedata
	if not d.getDebug(2) then
		g_savedata.profiler.working = {}
		g_savedata.profiler.total = {}
		g_savedata.profiler.display = {
			average = {},
			max = {},
			current = {}
		}
		d.print("cleaned all profiler data", true, 2)
	end
end

--------------------------------------------------------------------------------
--
-- Custom String Functions
--
--------------------------------------------------------------------------------

---@param str string the string to make the first letter uppercase
---@return string str the string with the first letter uppercase
function string.upperFirst(str)
	if type(str) == "string" then
		return (str:gsub("^%l", string.upper))
	end
	return nil
end

---@param str string the string the make friendly
---@return string friendly_string friendly string, nil if input_string was not a string
function string.friendly(str) -- function that replaced underscores with spaces and makes it all lower case, useful for player commands so its not extremely picky
	if type(str) == "string" then
		return string.gsub(string.lower(str), "_", " ")
	end
	return nil
end

--------------------------------------------------------------------------------
--
-- Custom Matrix Functions
--
--------------------------------------------------------------------------------

---@param matrix1 Matrix the first matrix
---@param matrix2 Matrix the second matrix
function matrix.xzDistance(matrix1, matrix2) -- returns the distance between two matrixes, ignoring the y axis
	ox, oy, oz = m.position(matrix1)
	tx, ty, tz = m.position(matrix2)
	return m.distance(m.translation(ox, 0, oz), m.translation(tx, 0, tz))
end

--------------------------------------------------------------------------------
--
-- Other Functions
--
--------------------------------------------------------------------------------

---@param peer_id integer the peer_id of the player you want to get the steam id of
---@return string steam_id the steam id of the player, nil if not found
function getSteamID(peer_id)
	local player_list = s.getPlayers()
	for peer_index, peer in pairs(player_list) do
		if peer.id == peer_id then
			return tostring(peer.steam_id)
		end
	end
	d.print("(getSteamID) unable to get steam_id for peer_id: "..peer_id, true, 1)
	return nil
end

---@param start_tick number the time you want to see how long its been since (in ticks)
---@return number ticks_since how many ticks its been since <start_tick>
function ticksSince(start_tick)
	return g_savedata.tick_counter - start_tick
end

---@param start_ms number the time you want to see how long its been since (in ms)
---@return number ms_since how many ms its been since <start_ms>
function millisecondsSince(start_ms)
	return s.getTimeMillisec() - start_ms
end