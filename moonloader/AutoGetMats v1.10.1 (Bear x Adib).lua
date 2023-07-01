-----------------------------------------------------
-- INFO
-----------------------------------------------------


script_name("Bear x Adib AutoGetMats")
script_authors("Bear, Adib")
script_version("1.10.1")


-----------------------------------------------------
-- HEADERS & CONFIG
-----------------------------------------------------


require "moonloader"
require "sampfuncs"

local sampev = require "lib.samp.events"
local inicfg = require "inicfg"
local ig = require "lib.moon-imgui-1-1-5.imgui"

local config_dir_path = getWorkingDirectory() .. "\\config\\"
if not doesDirectoryExist(config_dir_path) then createDirectory(config_dir_path) end

local config_file_path = config_dir_path .. "AutoGetMats (Bear x Adib) v" .. script.this.version .. ".ini"

config_dir_path = nil

local config

if doesFileExist(config_file_path) then
	config = inicfg.load(nil, config_file_path)
	
	if not type(config.General.hasPlayerDisabledPickup) == "boolean" then config.General.hasPlayerDisabledPickup = false end
	
	if not type(config.Messages.p1) == "string" then config.Messages.p1 = "" end
	if not type(config.Messages.isP1Enabled) == "boolean" then config.Messages.isP1Enabled = true end
	if not type(config.Messages.p2) == "string" then config.Messages.p2 = "" end
	if not type(config.Messages.isP2Enabled) == "boolean" then config.Messages.isP2Enabled = true end
	if not type(config.Messages.p3) == "string" then config.Messages.p3 = "" end
	if not type(config.Messages.isP3Enabled) == "boolean" then config.Messages.isP3Enabled = true end
	
	if not type(config.Messages.d1) == "string" then config.Messages.d1 = "" end
	if not type(config.Messages.isD1Enabled) == "boolean" then config.Messages.isD1Enabled = true end
	if not type(config.Messages.d2) == "string" then config.Messages.d2 = "" end
	if not type(config.Messages.isD2Enabled) == "boolean" then config.Messages.isD3Enabled = true end
	if not type(config.Messages.d3) == "string" then config.Messages.d3 = "" end
	if not type(config.Messages.isD3Enabled) == "boolean" then config.Messages.isD3Enabled = true end
	
	if not inicfg.save(config, config_file_path) then
		sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Config integrity reinforcement failed - contact the developer for help.", -1)
	end
else
	local new_config = io.open(config_file_path, "w")
	new_config:close()
	new_config = nil
	
	config = {
		General = {
			hasPlayerDisabledPickup = false, -- Automatic pickup toggle, linked to the .ini file, created for more localized read access
		},
		
		Messages = {
			p1 = "", isP1Enabled,
			p2 = "", isP2Enabled,
			p3 = "", isP3Enabled,
			
			d1 = "", isD1Enabled,
			d2 = "", isD2Enabled,
			d3 = "", isD3Enabled
		}
		
	}
	
	if not inicfg.save(config, config_file_path) then
		sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Config file creation failed - contact the developer for help.", -1)
	end
end


-----------------------------------------------------
-- GLOBAL VARIABLES & FUNCTIONS
-----------------------------------------------------


-- Indicates to the imgui menu that the screen resolution has changed, so that the menu window and size can be recalibrated
local hasResChanged = true

-- Indicates, if true, that material packages are certainly held by the player
local isACheckpointActive = false

-- Opens a detection window for the server's response to a pickup attempt
local isPickupAttemptResponseAwaited = false

-- Indicates if the server has responded with a proximity failure message
local hasProximityTestFailed = false

-- Indicates if the player is muted from sending server commands
local isPlayerMuted = false

-- Turns on if pickup fails from not having a required job
local isJobRequirementNotMet = false

-- A failsafe flag in case the server sees the player as still being outside a vehicle of the required type although that check has been completed locally
local hasVehicleRequirementFailed = false

-- Indicates if a checkpoint is already present, as determined by a server message
local isPickupAttemptRedundant = false

-- Indicates if a "You can't do this right now." message has been received in response to a pickup attempt
local isPlayerRestrainedOrInjured = false

-- Player's on-hand cash, updated every time it changes
local onHandCash = 0

-- Indicates what amount the player couldn't afford to pay for pickup
local lackedPickupFeeAmount

-- Player position coordinates
local posX, posY, posZ = 0, 0, 0
	
-- Pickup-specific data
local pickups = {
	mp2 = {
		-- Coordinate boundaies of the rectangular pickup super-zones
		superZone_X1 = 2360, superZone_Y1 = -2060, superZone_X2 = 2420, superZone_Y2 = -1990,
		
		-- Boolean flag indicating if appropriate vehicle is being used (if any required)
		isVehicleRequirementNotMet = function () return false end,
		
		-- Centre coordinates and the radius of a spherical pickup zone
		cen_x = 2390.510009, cen_y = -2007.939941, cen_z = 13.55, rad = 3
	},

	mp1 = {
		superZone_X1 = 1410, superZone_Y1 = -1360, superZone_X2 = 1440, superZone_Y2 = -1250,
		isVehicleRequirementNotMet = function () return false end,
		cen_x = 1423.660034, cen_y = -1320.589965, cen_z = 13.55, rad = 3
	},

	air = {
		superZone_X1 = 1300, superZone_Y1 = -2720, superZone_X2 = 1550, superZone_Y2 = -2500,
		isVehicleRequirementNotMet = function () return not isCharInFlyingVehicle(PLAYER_PED) end,
		cen_x = 1418.983643, cen_y = -2593.296387, cen_z = 13.546875, rad = 50
	},

	boat = {
		superZone_X1 = 2030, superZone_Y1 = -210, superZone_X2 = 2130, superZone_Y2 = -60,
		isVehicleRequirementNotMet = function () return not isCharInAnyBoat(PLAYER_PED) end,
		cen_x = 2102.709961, cen_y = -103.970001, cen_z = 2.28, rad = 25
	}
}

local menu = {
	p1_buffer = ig.ImBuffer(129), p2_buffer = ig.ImBuffer(129), p3_buffer = ig.ImBuffer(129),
	d1_buffer = ig.ImBuffer(129), d2_buffer = ig.ImBuffer(129), d3_buffer = ig.ImBuffer(129),
	clear_btns_posX
}

menu.p1_buffer.v, menu.p2_buffer.v, menu.p3_buffer.v = config.Messages.p1, config.Messages.p2, config.Messages.p3
menu.d1_buffer.v, menu.d2_buffer.v, menu.d3_buffer.v = config.Messages.d1, config.Messages.d2, config.Messages.d3

-- Configuring the menu style
local ig_style = ig.GetStyle()

ig_style.WindowTitleAlign = ig.ImVec2(0.5, 0.5)

ig_style.Colors[ig.Col.WindowBg] = ig.ImVec4(0, 0, 0, 0.9)
ig_style.Colors[ig.Col.TitleBg] = ig.ImVec4(0, 0, 0, 0.9)
ig_style.Colors[ig.Col.TitleBgActive] = ig.ImVec4(0, 0, 0, 0.9)
ig_style.Colors[ig.Col.TitleBgCollapsed] = ig.ImVec4(0, 0, 0, 0.2)

ig_style.Colors[ig.Col.FrameBg] = ig.ImVec4(0.1, 0.1, 0.1, 1)
ig_style.Colors[ig.Col.FrameBgHovered] = ig.ImVec4(0.2, 0.2, 0.2, 1)
ig_style.Colors[ig.Col.FrameBgActive] = ig.ImVec4(0.3, 0.3, 0.3, 1)

ig_style.Colors[ig.Col.Button] = ig.ImVec4(0.1, 0.1, 0.1, 1)
ig_style.Colors[ig.Col.ButtonHovered] = ig.ImVec4(0.2, 0.2, 0.2, 1)
ig_style.Colors[ig.Col.ButtonActive] = ig.ImVec4(0.3, 0.3, 0.3, 1)

local function awaitSpamCooldown()
	sampAddChatMessage("--- {FFFF00}AutoGetMats: {FFFFFF}Awaiting spam cooldown...", -1)
	while isPlayerMuted do wait(100) end
end

local function isPlayerInSupZone(pickup)
	return isCharInArea2d(PLAYER_PED, pickup.superZone_X1, pickup.superZone_Y1, pickup.superZone_X2, pickup.superZone_Y2, false)
end

local function isPlayerInPickupZone(pickup)
	posX, posY, posZ = getCharCoordinates(PLAYER_PED)
	if getDistanceBetweenCoords3d(posX, posY, posZ, pickup.cen_x, pickup.cen_y, pickup.cen_z) < pickup.rad then return true else return false end
end

local function attemptPickup()
	isPickupAttemptResponseAwaited = true
	sampSendChat("/getmats")
end


-----------------------------------------------------
-- MAIN
-----------------------------------------------------


function main()
	---------------
	-- INITIALIZING
	---------------
	
	-- Waiting to meet startup conditions
	repeat wait(50) until isSampAvailable()
	repeat wait(50) until string.find(sampGetCurrentServerName(), "Horizon Roleplay")
	sampAddChatMessage("--- {FFFF00}AutoGetMats v" .. script.this.version .. " {FFFFFF}by Bear and Adib | Use {FFFF00}/gmmenu", -1)
	
	-- Command registry
	sampRegisterChatCommand("autogm", cmd_autogm)
	sampRegisterChatCommand("gmpt", cmd_gmpt)
	sampRegisterChatCommand("gmdt", cmd_gmdt)
	sampRegisterChatCommand("gmmenu", cmd_gmmenu)
	sampRegisterChatCommand("gmhelp", cmd_gmmenu) -- alias to the above
	
	---------------------
	-- ADDITIONAL THREADS
	---------------------
	
	-- An extra thread that initiates a 13-second spam cooldown if the player is muted under certain circumstances
	lua_thread.create(function()
		while true do
			wait(100)
			if isPlayerMuted then wait(13000) isPlayerMuted = false end
		end
	end)
	
	-- Resolution change detector
	lua_thread.create(function()
		local r1_x, r1_y
		
		while true do
			r1_x, r1_y = getScreenResolution()
			wait(1000)
			r2_x, r2_y = getScreenResolution()
			
			if not (r1_x == r2_x and r1_y == r2_y) then hasResChanged = true end
		end
	end)
	
	-- An extra thread that sends pickup/delivery Messages (if any needed) when certain flags are detected
	lua_thread.create(function()
		while true do
			wait(0)
			if isPickupDone then
				isPickupDone = false
				
				if config.Messages.isP1Enabled and string.find(config.Messages.p1, "%S") then sampSendChat(config.Messages.p1) end
				if config.Messages.isP2Enabled and string.find(config.Messages.p2, "%S") then sampSendChat(config.Messages.p2) end
				if config.Messages.isP3Enabled and string.find(config.Messages.p3, "%S") then sampSendChat(config.Messages.p3) end
			end
			
			if isDeliveryDone then
				isDeliveryDone = false
				
				if config.Messages.isD1Enabled and string.find(config.Messages.d1, "%S") then sampSendChat(config.Messages.d1) end
				if config.Messages.isD2Enabled and string.find(config.Messages.d2, "%S") then sampSendChat(config.Messages.d2) end
				if config.Messages.isD3Enabled and string.find(config.Messages.d3, "%S") then sampSendChat(config.Messages.d3) end
			end
		end
	end)
	
	------------------------
	-- MAIN THREAD CONTINUED
	------------------------
	
	-- How long the player has to stay inside a pickup zone, after entering one, for an attempt to be made
	local retrackCooldown = 75
	
	-- Passenger tracking data
	local posX_a, posY_a, posZ_a, posX_b, posY_b, posZ_b
	local projectionOffset1, projectionOffset2 = 2, 10
	
	--------------
	-- FOR TESTING
	
	sampRegisterChatCommand("gmrc", function(args)
		if tonumber(args) then
			sampAddChatMessage("{FFFF00}Retrack cooldown: {FFFFFF}" .. args .. " (prev: " ..  retrackCooldown .. ")", -1)
			retrackCooldown = tonumber(args)
		else
			sampAddChatMessage("{FFFF00}Retrack cooldown: {FF4444}Not a number", -1)
		end
	end)
	sampRegisterChatCommand("gmpo", function(args)
		if tonumber(args) then
			sampAddChatMessage("{FFFF00}Offset 1 & 2: {FFFFFF}" .. args .. " (prev: " ..  projectionOffset1 .. " & " .. projectionOffset2 .. ")", -1)
			projectionOffset1 = tonumber(args)
			projectionOffset2 = tonumber(args)
		else
			sampAddChatMessage("{FFFF00}Offset 1 & 2: {FF4444}Not a number", -1)
		end
	end)
	sampRegisterChatCommand("gmpo1", function(args)
		if tonumber(args) then
			sampAddChatMessage("{FFFF00}Offset 1: {FFFFFF}" .. args .. " (prev: " .. projectionOffset1 .. " & " .. projectionOffset2 .. ")", -1)
			projectionOffset1 = tonumber(args)
		else
			sampAddChatMessage("{FFFF00}Offset 1: {FF4444}Not a number", -1)
		end
	end)
	sampRegisterChatCommand("gmpo2", function(args)
		if tonumber(args) then
			sampAddChatMessage("{FFFF00}Offset 2: {FFFFFF}" .. args .. " (prev: " .. projectionOffset1 .. " & " .. projectionOffset2 .. ")", -1)
			projectionOffset2 = tonumber(args)
		else
			sampAddChatMessage("{FFFF00}Offset 2: {FF4444}Not a number", -1)
		end
	end)
	--------------
	
	-- Tracking loop
	repeat
		-- Alternating through all the pickups
		for _, selectedPickup in pairs(pickups) do
			::track::
			wait(0)
			-- Super-zone test as a loop entering condition
			while isPlayerInSupZone(selectedPickup) do
				-- Perform checks required for pickup approval
				while config.General.hasPlayerDisabledPickup do wait(100) end
				if selectedPickup.isVehicleRequirementNotMet() then
					wait(250) -- creates a buffer that makes it far less likely for the server to still perceive the player as being outside the vehicle while approving pickup
					goto track
				end
				
				if isCharInAnyCar(PLAYER_PED) and getDriverOfCar(getCarCharIsUsing(PLAYER_PED)) ~= PLAYER_PED then
					-- the player is a passenger
					posX_a, posY_a, posZ_a = getCharCoordinates(PLAYER_PED)
					wait(1)
					posX_b, posY_b, posZ_b = getCharCoordinates(PLAYER_PED)
					
					if
						getDistanceBetweenCoords3d(posX_b + projectionOffset1 * (posX_b - posX_a), posY_b + projectionOffset1 * (posY_b - posY_a), posZ_b + projectionOffset1 * (posZ_b - posZ_a), selectedPickup.cen_x, selectedPickup.cen_y, selectedPickup.cen_z) < selectedPickup.rad
						and getDistanceBetweenCoords3d(posX_b + projectionOffset2 * (posX_b - posX_a), posY_b + projectionOffset2 * (posY_b - posY_a), posZ_b + projectionOffset2 * (posZ_b - posZ_a), selectedPickup.cen_x, selectedPickup.cen_y, selectedPickup.cen_z) < selectedPickup.rad
						then
							if isPlayerMuted then awaitSpamCooldown() goto track
							else attemptPickup()
							end
					else goto track
					end
				elseif isPlayerInPickupZone(selectedPickup) then
					-- the player is a non-passenger (driver or pedestrian), present in the pickup zone
					-- Wait and see if the player is still in the zone after the specified time period, and attempt pickup if so
					wait(retrackCooldown)
					
					if isPlayerInPickupZone(selectedPickup) then
						if isPlayerMuted then awaitSpamCooldown() goto track
						else attemptPickup()
						end
					else goto track
					end
				
				else goto track -- No attempt has been made as the tracking condition wasn't met
				
				end -- An attempt has been made
				
				-- Wait until a response to the pickup attempt is detected
				while isPickupAttemptResponseAwaited do wait(0) end
				
				if hasProximityTestFailed and isCharInAnyCar(PLAYER_PED) and getDriverOfCar(getCarCharIsUsing(PLAYER_PED)) ~= PLAYER_PED then
					hasProximityTestFailed = false
					wait(250) -- a buffer to reduce pickup re-attempt frequency for vehicle passengers in case of proximity failure
				end
				
				-- React, if needed, to the server's response to the pickup attempt
				if isJobRequirementNotMet then
					while isJobRequirementNotMet and isPlayerInSupZone(selectedPickup) do wait(100) end
				end
				
				if lackedPickupFeeAmount then -- the value being non-nil indicates that pickup has failed due to fund insufficiency
					while lackedPickupFeeAmount and isPlayerInSupZone(selectedPickup) and onHandCash < lackedPickupFeeAmount do wait(100) end
						
					lackedPickupFeeAmount = nil
				end
				
				if hasVehicleRequirementFailed then
					-- Since the requirement failed almost certainly due to the server processing the pickup attempt before the vehicle situation has updated, a short buffer is added before re-attempt
					wait(250)
					hasVehicleRequirementFailed = false
				end
				
				if isPickupAttemptRedundant then
					isACheckpointActive = true
					isPickupAttemptRedundant = false
				end
				
				if isPlayerRestrainedOrInjured then
					while isPlayerRestrainedOrInjured and isPlayerInSupZone(selectedPickup) do wait(100) end
				end
				
				while isACheckpointActive do wait(100) end
			end
			
			while config.General.hasPlayerDisabledPickup do wait(100) end
			
			wait(250)
		end
		
		wait(0)
	until false
end


-----------------------------------------------------
-- API-SPECIFIC FUNCTIONS
-----------------------------------------------------


function sampev.onGivePlayerMoney(newAmount)
	onHandCash = newAmount
end

function sampev.onDisableCheckpoint()
	isACheckpointActive = false
end

function sampev.onServerMessage(_, msg_text)
	if not string.find(sampGetCurrentServerName(), "Horizon Roleplay") then return true end
	
	-- (Pickup done) "* You bought xy Material Packages for $ab(c)."
	if string.sub(msg_text, 1, 13) == "* You bought " and string.sub(msg_text, 16, 34) == " Material Packages " then
		isACheckpointActive = true
		isPickupAttemptResponseAwaited = false
		-- Signals that pickup is complete so that Messages can be triggered
		isPickupDone = true
	
	-- (AGM attempt failure) "You are not at a Materials Pickup!"
	elseif msg_text == "You are not at a Materials Pickup!" then
		hasProximityTestFailed = true
		isPickupAttemptResponseAwaited = false
	
	-- (Checkpoint already exists) "Please ensure that your current checkpoint is destroyed first (you either have material packages, or another existing checkpoint)."
	elseif
		string.sub(msg_text, 1, 56) == "Please ensure that your current checkpoint is destroyed "
		and string.sub(msg_text, 127, 130) == "nt)."
		and isPickupAttemptResponseAwaited
		then
			isPickupAttemptRedundant = true
			isPickupAttemptResponseAwaited = false
	
	-- (Job required) "   You are not an Arms Dealer or Craftsman!"
	elseif msg_text == "   You are not an Arms Dealer or Craftsman!" then
		isJobRequirementNotMet = true
		isPickupAttemptResponseAwaited = false

	-- (Player muted from spamming CMDs) "You have been muted automatically for spamming. Please ..."
	elseif string.sub(msg_text, 1, 48) == "You have been muted automatically for spamming. " then
		isPlayerMuted = true
		isPickupAttemptResponseAwaited = false
	
	-- (Player lacks pickup funds) " You can't afford the $xy(z)!"
	elseif string.sub(msg_text, 1, 23) == " You can't afford the $" then
		lackedPickupFeeAmount = tonumber(msg_text:match("%d+"))
		isPickupAttemptResponseAwaited = false
	
	-- (Player is not using a vehicle of the required type) " You are not (in a plane/on a boat)!"
	elseif msg_text == " You are not in a plane!" or msg_text == " You are not on a boat!" then
		hasVehicleRequirementFailed = true
		isPickupAttemptResponseAwaited = false

	-- (Delivery done) "The factory gave you xyz materials for your delivery, ..."
	elseif string.sub(msg_text, 1, 21) == "The factory gave you " and string.sub(msg_text, 25, 54) == " materials for your delivery, " then
		-- Signals that delivery is complete so that Messages can be triggered
		isDeliveryDone = true

	-- (Getting Craftsman) "* You are now a Craftsman, type ..."
	elseif string.sub(msg_text, 1, 27) == "* You are now a Craftsman, " then
		isJobRequirementNotMet = false

	-- (Getting Arms Dealer) "* You are now an Arms Dealer, type ..."
	elseif string.sub(msg_text, 1, 30) == "* You are now an Arms Dealer, " then
		isJobRequirementNotMet = false
	
	-- (Attempting while cuffed/tied/injured)
	elseif isPickupAttemptResponseAwaited and msg_text == "You can't do this right now." then
		isPlayerRestrainedOrInjured = true
		isPickupAttemptResponseAwaited = false
	
	-- (Admin revival)
	elseif msg_text == "You have been revived by an Admin." then
		isPlayerRestrainedOrInjured = false
	
	-- (Uncuffed)
	elseif msg_text:sub(1, 28) == "* You have been uncuffed by " then
		isPlayerRestrainedOrInjured = false
	
	-- (Untied)
	elseif msg_text:sub(1, 21) == "* You were untied by " then
		isPlayerRestrainedOrInjured = false
	
	-- (Server reconnection) "Welcome to Horizon Roleplay, ..."
	elseif string.sub(msg_text, 1, 29) == "Welcome to Horizon Roleplay, " then
		-- Re-initialize some state variables after a new character login to clear up the pre-reconnection state
		isACheckpointActive = false
		isPlayerMuted = false
		isJobRequirementNotMet = false
		isPickupAttemptRedundant = false
		hasProximityTestFailed = false
		isPlayerRestrainedOrInjured = false
		lackedPickupFeeAmount = nil
		isPickupAttemptResponseAwaited = false
	
	end
end

-- GMMENU
function ig.OnDrawFrame()
	local screenWidth, screenHeight = getScreenResolution()
	local setWindowWidth, setWindowHeight = screenHeight * 1.08, screenHeight / 1.9
	
	if hasResChanged then
		-- Window sizing & positioning
		ig.SetNextWindowPos(ig.ImVec2(screenWidth / 2, screenHeight / 2), ig.Cond.Always, ig.ImVec2(0.5, 0.5))
		ig.SetNextWindowSize(ig.ImVec2(setWindowWidth, setWindowHeight), ig.Cond.Always)
		
		hasResChanged = false
	end
	
	---------------------------
	-- USER-CONTROLLED SETTINGS
	---------------------------
	
	ig.Begin("Bear x Adib AutoGetMats v" .. script.this.version)
	ig.SetWindowFontScale(screenHeight / 900)
	ig.PushItemWidth(-1 * screenHeight / 10.7)
	ig_style.WindowRounding = screenHeight / 100
	ig_style.WindowPadding = ig.ImVec2(screenHeight / 144, screenHeight / 144)
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 100, 0)
	
	-- Pickup toggle
	if ig.RadioButton("Automatic Package Pickup [/autogm]", not config.General.hasPlayerDisabledPickup) then
		config.General.hasPlayerDisabledPickup = not config.General.hasPlayerDisabledPickup
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig.NewLine() ig.NewLine()
	
	-- Pickup message boxes
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 100, screenHeight / 144)
	
	local clear_btns_size = ig.ImVec2(screenHeight / 15, screenHeight / 50)
	
	if ig.RadioButton("Package Pickup Text [gmpt]", (config.Messages.isP1Enabled or config.Messages.isP2Enabled or config.Messages.isP3Enabled) and true or false) then
		if config.Messages.isP1Enabled or config.Messages.isP2Enabled or config.Messages.isP3Enabled then
			config.Messages.isP1Enabled, config.Messages.isP2Enabled, config.Messages.isP3Enabled = false, false, false
		else
			config.Messages.isP1Enabled, config.Messages.isP2Enabled, config.Messages.isP3Enabled = true, true, true
		end
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig.Text("Example: /me collects some material packages.")
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 100, screenHeight / 288)
	
	if ig.RadioButton("P1", config.Messages.isP1Enabled and true or false) then
		config.Messages.isP1Enabled = not config.Messages.isP1Enabled
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 150, screenHeight / 288)
	ig.SameLine()
	
	if ig.InputText("P1 ", menu.p1_buffer) then
		config.Messages.p1 = menu.p1_buffer.v
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 200, screenHeight / 288)
	ig.SameLine()
	
	if menu.clear_btns_posX then ig.SetCursorPosX(menu.clear_btns_posX) end
	if ig.Button("CLEAR P1", clear_btns_size) then
		config.Messages.p1, menu.p1_buffer.v = "", ""
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	if ig.RadioButton("P2", config.Messages.isP2Enabled and true or false) then
		config.Messages.isP2Enabled = not config.Messages.isP2Enabled
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 150, screenHeight / 288)
	ig.SameLine()
	
	if ig.InputText("P2 ", menu.p2_buffer) then
		config.Messages.p2 = menu.p2_buffer.v
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 200, screenHeight / 288)
	ig.SameLine()
	
	if menu.clear_btns_posX then ig.SetCursorPosX(menu.clear_btns_posX) end
	if ig.Button("CLEAR P2", clear_btns_size) then
		config.Messages.p2, menu.p2_buffer.v = "", ""
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	if ig.RadioButton("P3", config.Messages.isP3Enabled and true or false) then
		config.Messages.isP3Enabled = not config.Messages.isP3Enabled
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 150, screenHeight / 288)
	ig.SameLine()
	
	if ig.InputText("P3 ", menu.p3_buffer) then
		config.Messages.p3 = menu.p3_buffer.v
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 200, screenHeight / 288)
	ig.SameLine()
	
	if menu.clear_btns_posX then ig.SetCursorPosX(menu.clear_btns_posX) end
	if ig.Button("CLEAR P3", clear_btns_size) then
		config.Messages.p3, menu.p3_buffer.v = "", ""
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig.NewLine() ig.NewLine()
	
	-- Delivery message boxes
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 100, screenHeight / 144)
	
	if ig.RadioButton("Package Delivery Text [gmdt]", (config.Messages.isD1Enabled or config.Messages.isD2Enabled or config.Messages.isD3Enabled) and true or false) then
		if config.Messages.isD1Enabled or config.Messages.isD2Enabled or config.Messages.isD3Enabled then
			config.Messages.isD1Enabled, config.Messages.isD2Enabled, config.Messages.isD3Enabled = false, false, false
		else
			config.Messages.isD1Enabled, config.Messages.isD2Enabled, config.Messages.isD3Enabled = true, true, true
		end
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig.Text("Example: I delivered.")
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 100, screenHeight / 288)
	
	if ig.RadioButton("D1", config.Messages.isD1Enabled and true or false) then
		config.Messages.isD1Enabled = not config.Messages.isD1Enabled
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 150, screenHeight / 288)
	ig.SameLine()
	
	if ig.InputText("D1 ", menu.d1_buffer) then
		config.Messages.d1 = menu.d1_buffer.v
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 200, screenHeight / 288)
	ig.SameLine()
	
	menu.clear_btns_posX = ig.GetCursorPosX()
	if ig.Button("CLEAR D1", clear_btns_size) then
		config.Messages.d1, menu.d1_buffer.v = "", ""
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	if ig.RadioButton("D2", config.Messages.isD2Enabled and true or false) then
		config.Messages.isD2Enabled = not config.Messages.isD2Enabled
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 150, screenHeight / 288)
	ig.SameLine()
	
	if ig.InputText("D2 ", menu.d2_buffer) then
		config.Messages.d2 = menu.d2_buffer.v
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 200, screenHeight / 288)
	ig.SameLine()
	
	if ig.Button("CLEAR D2", clear_btns_size) then
		config.Messages.d2, menu.d2_buffer.v = "", ""
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	if ig.RadioButton("D3", config.Messages.isD3Enabled and true or false) then
		config.Messages.isD3Enabled = not config.Messages.isD3Enabled
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 150, screenHeight / 288)
	ig.SameLine()
	
	if ig.InputText("D3 ", menu.d3_buffer) then
		config.Messages.d3 = menu.d3_buffer.v
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig_style.ItemSpacing = ig.ImVec2(screenHeight / 200, screenHeight / 288)
	ig.SameLine()
	
	if ig.Button("CLEAR D3", clear_btns_size) then
		config.Messages.d3, menu.d3_buffer.v = "", ""
		
		if not inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Saving data to config failed - contact the developer for help.", -1)
		end
	end
	
	ig.NewLine() ig.NewLine()
	
	-- Credits
	ig.Text("Credits: Bear (Swapnil#9308), Adib23704#8947, Brad#6219, Ezio (PriPat#9969), Hr1doy#6038")
	
	--------
	-- CLOSE
	--------
	
	ig.SetCursorPosY(setWindowHeight * 0.923)
	
	if ig.Button("CLOSE", ig.ImVec2(ig.GetWindowWidth() - (ig_style.WindowPadding.x * 2), (screenHeight / 30))) then
		menu.p1_buffer.v, menu.p2_buffer.v, menu.p3_buffer.v = config.Messages.p1, config.Messages.p2, config.Messages.p3
		menu.d1_buffer.v, menu.d2_buffer.v, menu.d3_buffer.v = config.Messages.d1, config.Messages.d2, config.Messages.d3
		
		ig.Process = false
	end
	
	ig.End()
end


-----------------------------------------------------
-- COMMAND-SPECIFIC FUNCTIONS
-----------------------------------------------------


function cmd_autogm()
	config.General.hasPlayerDisabledPickup = not config.General.hasPlayerDisabledPickup
	
	if config.General.hasPlayerDisabledPickup then
		if inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Off", -1)
		else
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Pickup toggle in config failed - contact the developer for help.", -1)
		end
	else
		if inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetMats: {FFFFFF}On", -1)
		else
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Pickup toggle in config failed - contact the developer for help.", -1)
		end
	end
end

function cmd_gmpt()
	if config.Messages.isP1Enabled or config.Messages.isP2Enabled or config.Messages.isP3Enabled then
		config.Messages.isP1Enabled, config.Messages.isP2Enabled, config.Messages.isP3Enabled = false, false, false
		
		if inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetMats: {FFFFFF}Pickup Text Off", -1)
		else
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Pickup toggle in config failed - contact the developer for help.", -1)
		end
	else
		config.Messages.isP1Enabled, config.Messages.isP2Enabled, config.Messages.isP3Enabled = true, true, true
		
		if inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Pickup Text On", -1)
		else
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Pickup toggle in config failed - contact the developer for help.", -1)
		end
	end
end

function cmd_gmdt()
	if config.Messages.isD1Enabled or config.Messages.isD2Enabled or config.Messages.isD3Enabled then
		config.Messages.isD1Enabled, config.Messages.isD2Enabled, config.Messages.isD3Enabled = false, false, false
		
		if inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetMats: {FFFFFF}Delivery Text Off", -1)
		else
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Pickup toggle in config failed - contact the developer for help.", -1)
		end
	else
		config.Messages.isD1Enabled, config.Messages.isD2Enabled, config.Messages.isD3Enabled = true, true, true
		
		if inicfg.save(config, config_file_path) then
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Delivery Text On", -1)
		else
			sampAddChatMessage("--- {FFFF00}AutoGetmats: {FFFFFF}Pickup toggle in config failed - contact the developer for help.", -1)
		end
	end
end

function cmd_gmmenu()
	ig.Process = not ig.Process
end
