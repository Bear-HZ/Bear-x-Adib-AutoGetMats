-----------------------------------------------------
-- INFO
-----------------------------------------------------


script_name("Bear x Adib AutoGetMats")
script_description("This bot automatically picks material packages at any of the four pickups without any player input.")
script_authors("Bear, Adib")
script_version("1.9.0-beta")
local script_version = "1.9.0-beta"


-----------------------------------------------------
-- HEADERS & CONFIG
-----------------------------------------------------


require "moonloader"
require "sampfuncs"

local sampev = require "lib.samp.events"
local inicfg = require "inicfg"
local imgui = require "lib.moon-imgui-1-1-5.imgui"

local dir = getWorkingDirectory() .. "\\config\\"
local config = dir .. "AutoGetMats (Bear x Adib).ini"

if not doesDirectoryExist(dir) then createDirectory(dir) end

if not doesFileExist(config) then	
	print("The script failed to load. Read the instructions and make sure to install correctly.")
	thisScript():unload()
end

local directIni = config
local mainIni = inicfg.load(nil, directIni)


-----------------------------------------------------
-- GLOBAL VARIABLES
-----------------------------------------------------


-- Indicates, if true, that material packages are certainly held by the player
local isACheckpointActive = false

-- Opens a detection window for the server's response to a pickup attempt
local isPickupAttemptResponseAwaited = false

-- Indicates if the player is muted from sending server commands
local isPlayerMuted = false

-- Turns on if pickup fails from not having a required job
local isJobRequirementNotMet = false

-- Indicates if a checkpoint is already present, as determined by a server message
local isPickupAttemptRedundant = false

-- Player's on-hand cash, updated every time it changes
local onHandCash -- the initialized value has to be nil to indicate that it's unknown

-- Indicates what amount the player couldn't afford to pay for pickup
local lackedPickupFeeAmount = 0

-- Player position coordinates
local posX, posY, posZ = 0, 0, 0

-- Automatic pickup toggle, linked to the .ini file, created for more localized read access
local hasPlayerDisabledPickup = mainIni.General.hasPlayerDisabledPickup

-- Unit pause time, linked to the .ini file, used in multiples of 1 or 2 for adding a delay b/w tracking or pickup attempts
local pauseUnit = mainIni.General.pauseUnit
	
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

-- Pickup command string
local gm_str = "/getmats"


-- Initializing the GMMENU bool(s) & buffers
local gmmenu = {
	imbool_hasPlayerEnabledPickup, -- as opposed to imbool_hasPlayerDisabledPickup because the imbool table has to be used for a checkbox function without the option to negate the bool value
	
	messagesData = {
		pickup = {
			imbool_areAllEnabled,
			m1 = {
				buffer = imgui.ImBuffer(129)
			},
			m2 = {
				buffer = imgui.ImBuffer(129)
			},
			m3 = {
				buffer = imgui.ImBuffer(129)
			}
		},
		delivery = {
			imbool_areAllEnabled,
			m1 = {
				buffer = imgui.ImBuffer(129)
			},
			m2 = {
				buffer = imgui.ImBuffer(129)
			},
			m3 = {
				buffer = imgui.ImBuffer(129)
			}
		}
	}
}

-- Configuring the GMMENU style
local gmmenu_style = imgui.GetStyle()

gmmenu_style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
gmmenu_style.WindowRounding = 0
gmmenu_style.WindowPadding = imgui.ImVec2(10, 10)
gmmenu_style.ItemSpacing = imgui.ImVec2(30, 5)

gmmenu_style.Colors[imgui.Col.WindowBg] = imgui.ImVec4(0, 0, 0, 0.9)
gmmenu_style.Colors[imgui.Col.TitleBg] = imgui.ImVec4(0, 0, 0, 0.9)
gmmenu_style.Colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0, 0, 0, 0.9)
gmmenu_style.Colors[imgui.Col.TitleBgCollapsed] = imgui.ImVec4(0, 0, 0, 0.2)


-----------------------------------------------------
-- LOCALLY DECLARED FUNCTIONS
-----------------------------------------------------


local function awaitSpamCooldown()
	sampAddChatMessage("{FFFFFF}--- {FFFF00}AutoGetMats: {FFFFFF}Awaiting spam cooldown...", -1)
	while isPlayerMuted do wait(0) end
end

local function isPlayerInSupZone(pickup)
	return isCharInArea2d(PLAYER_PED, pickup.superZone_X1, pickup.superZone_Y1, pickup.superZone_X2, pickup.superZone_Y2, false)
end

local function isPlayerInPickupZone(pickup)
	posX, posY, posZ = getCharCoordinates(PLAYER_PED)
	if getDistanceBetweenCoords3d(posX, posY, posZ, pickup.cen_x, pickup.cen_y, pickup.cen_z) < pickup.rad then return true else return false end
end

local function attemptPickupOnce()
	isPickupAttemptResponseAwaited = true
	sampSendChat(gm_str)
end

local function getMessageBufferValuesFromConfig()
	gmmenu.messagesData.pickup.m1.buffer.v = mainIni.PickupMessages.m1
	gmmenu.messagesData.pickup.m2.buffer.v = mainIni.PickupMessages.m2
	gmmenu.messagesData.pickup.m3.buffer.v = mainIni.PickupMessages.m3
	
	gmmenu.messagesData.delivery.m1.buffer.v = mainIni.DeliveryMessages.m1
	gmmenu.messagesData.delivery.m2.buffer.v = mainIni.DeliveryMessages.m2
	gmmenu.messagesData.delivery.m3.buffer.v = mainIni.DeliveryMessages.m3
end

local function getConfigMessageValuesFromBuffers()
	mainIni.PickupMessages.m1 = gmmenu.messagesData.pickup.m1.buffer.v
	mainIni.PickupMessages.m2 = gmmenu.messagesData.pickup.m2.buffer.v
	mainIni.PickupMessages.m3 = gmmenu.messagesData.pickup.m3.buffer.v

	mainIni.DeliveryMessages.m1 = gmmenu.messagesData.delivery.m1.buffer.v
	mainIni.DeliveryMessages.m2 = gmmenu.messagesData.delivery.m2.buffer.v
	mainIni.DeliveryMessages.m3 = gmmenu.messagesData.delivery.m3.buffer.v
	
	if not inicfg.save(mainIni, directIni) then
		sampAddChatMessage("{FFFFFF}--- {FFFF00}AutoGetmats: {FFFFFF}Saving failed - Contact the developer for help.", -1)
	end
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
	
	sampAddChatMessage("{FFFFFF}--- {FFFF00}AutoGetMats v" .. script_version .. " {FFFFFF}by Bear and Adib | Use {FFFF00}/gmmenu", -1)
	
	-- Initializing some data for the "gmmenu" GUI
	if hasPlayerDisabledPickup then gmmenu.imbool_hasPlayerEnabledPickup = imgui.ImBool(false)
	else gmmenu.imbool_hasPlayerEnabledPickup = imgui.ImBool(true)
	end
	
	if mainIni.PickupMessages.areAllEnabled then gmmenu.messagesData.pickup.imbool_areAllEnabled = imgui.ImBool(true)
	else gmmenu.messagesData.pickup.imbool_areAllEnabled = imgui.ImBool(false)
	end
	
	if mainIni.DeliveryMessages.areAllEnabled then gmmenu.messagesData.delivery.imbool_areAllEnabled = imgui.ImBool(true)
	else gmmenu.messagesData.delivery.imbool_areAllEnabled = imgui.ImBool(false)
	end
	
	getMessageBufferValuesFromConfig()
	
	-- Command registry
	sampRegisterChatCommand("autogm", cmd_autogm)
	sampRegisterChatCommand("gmmenu", cmd_gmmenu)
	sampRegisterChatCommand("gmhelp", cmd_gmmenu)
	
	---------------------
	-- ADDITIONAL THREADS
	---------------------
	
	-- An extra thread that initiates a 13-second spam cooldown if the player is muted under certain circumstances
	lua_thread.create(function()
		while true do
			wait(0)
			if isPlayerMuted then wait(13000) isPlayerMuted = false end
		end
	end)
	
	-- An extra thread that sends pickup/delivery messages (if any needed) when certain flags are detected
	lua_thread.create(function()
		while true do
			wait(0)
			if isPickupDone then
				isPickupDone = false
				
				if mainIni.PickupMessages.areAllEnabled then
					if string.find(mainIni.PickupMessages.m1, "%S") then sampSendChat(mainIni.PickupMessages.m1) end
					if string.find(mainIni.PickupMessages.m2, "%S") then sampSendChat(mainIni.PickupMessages.m2) end
					if string.find(mainIni.PickupMessages.m3, "%S") then sampSendChat(mainIni.PickupMessages.m3) end
				end
			end
			
			if isDeliveryDone then
				isDeliveryDone = false
				
				if mainIni.DeliveryMessages.areAllEnabled then
					if string.find(mainIni.DeliveryMessages.m1, "%S") then sampSendChat(mainIni.DeliveryMessages.m1) end
					if string.find(mainIni.DeliveryMessages.m2, "%S") then sampSendChat(mainIni.DeliveryMessages.m2) end
					if string.find(mainIni.DeliveryMessages.m3, "%S") then sampSendChat(mainIni.DeliveryMessages.m3) end
				end
			end
		end
	end)
	
	------------------------
	-- MAIN THREAD CONTINUED
	------------------------
	
	-- Tracking loop
	repeat
		-- Iterating through the four pickups
		for _, selectedPickup in pairs(pickups) do
			::track::
			wait(0)
			-- Super-zone test as a loop entering condition
			while isPlayerInSupZone(selectedPickup) do
				-- Perform checks required for pickup approval
				while hasPlayerDisabledPickup do wait(0) end
				if selectedPickup.isVehicleRequirementNotMet() then goto track end
				
				-- Check if the player is a passenger, and initiate passenger-specific tracking/picking routine
				if isCharInAnyCar(PLAYER_PED)
				and getDriverOfCar(getCarCharIsUsing(PLAYER_PED)) ~= PLAYER_PED
				and isPlayerInPickupZone(selectedPickup)
				then
					if isPlayerMuted then awaitSpamCooldown() goto track
					else attemptPickupOnce()
					end
				
				-- Pickup zone test for non-passengers
				elseif isPlayerInPickupZone(selectedPickup) then
					-- Wait and see if the player is still in the zone after the specified time period, and attempt pickup if so
					wait(pauseUnit)
					if isPlayerInPickupZone(selectedPickup) then
						if isPlayerMuted then awaitSpamCooldown() goto track
						else attemptPickupOnce()
						end
					end
					
				else goto track -- No attempt has been made as the tracking conditions aren't met
				
				end -- An attempt has been made
				
				-- Wait until a response to the pickup attempt is detected
				while isPickupAttemptResponseAwaited do wait(0) end
				
				-- React, if needed, to the server's response to the pickup attempt
				if isPickupAttemptRedundant then
					isACheckpointActive = true
					isPickupAttemptRedundant = false
				end
				
				if isACheckpointActive then
					while isACheckpointActive do wait(0) end
					goto track
				end
				
				if isJobRequirementNotMet then
					while isJobRequirementNotMet and isPlayerInSupZone(selectedPickup) do wait(0) end
					goto track
				end
				
				if lackedPickupFeeAmount ~= 0 then -- the value being non-zero indicates that pickup has failed due to fund insufficiency
					repeat
						wait(0)
						if onHandCash ~= nil and tonumber(onHandCash) >= tonumber(lackedPickupFeeAmount) then break end -- the on-hand cash is measured against the pickup fee only if the first condition is met, i.e. the value being non-nil
					until not isPlayerInSupZone(selectedPickup) -- if the pickup super-zone is exited, the loop terminates and pickup can be re-attempted whether or not required funds have been received
						
					lackedPickupFeeAmount = 0
				end
			end
			
			while hasPlayerDisabledPickup do wait(0) end
			
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

function sampev.onServerMessage(msg_color, msg_text)
	if not string.find(sampGetCurrentServerName(), "Horizon Roleplay") then return true end

	-- (Pickup done) "* You bought xy Material Packages for $ab(c)."
	if string.sub(msg_text, 1, 13) == "* You bought " and string.sub(msg_text, 16, 34) == " Material Packages " then
		isACheckpointActive = true
		isPickupAttemptResponseAwaited = false
		-- Signals that pickup is complete so that messages can be triggered
		isPickupDone = true
	
	-- (AGM attempt failure) "You are not at a Materials Pickup!"
	elseif msg_text == "You are not at a Materials Pickup!" then
		isPickupAttemptResponseAwaited = false
	
	-- (Checkpoint already exists) "Please ensure that your current checkpoint is destroyed first (you either have material packages, or another existing checkpoint)."
	elseif string.sub(msg_text, 1, 56) == "Please ensure that your current checkpoint is destroyed " and string.sub(msg_text, 127, 130) == "nt)." then
		if isPickupAttemptResponseAwaited then
			isPickupAttemptRedundant = true
			isPickupAttemptResponseAwaited = false
		end
	
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
		lackedPickupFeeAmount = string.match(msg_text, "%d+")
		isPickupAttemptResponseAwaited = false

	-- (Delivery done) "The factory gave you xyz materials for your delivery, ..."
	elseif string.sub(msg_text, 1, 21) == "The factory gave you " and string.sub(msg_text, 25, 54) == " materials for your delivery, " then
		-- Signals that delivery is complete so that messages can be triggered
		isDeliveryDone = true

	-- (Getting Craftsman) "* You are now a Craftsman, type ..."
	elseif string.sub(msg_text, 1, 27) == "* You are now a Craftsman, " then
		isJobRequirementNotMet = false

	-- (Getting Arms Dealer) "* You are now an Arms Dealer, type ..."
	elseif string.sub(msg_text, 1, 30) == "* You are now an Arms Dealer, " then
		isJobRequirementNotMet = false
	
	-- (Server reconnection) "Welcome to Horizon Roleplay, ..."
	elseif string.sub(msg_text, 1, 29) == "Welcome to Horizon Roleplay, " then
		-- Re-initialize some state variables after a new character login to clear up the pre-reconnection state
		isACheckpointActive = false
		isPickupAttemptResponseAwaited = false
		isPlayerMuted = false
		isJobRequirementNotMet = false
		isPickupAttemptRedundant = false
		onHandCash = nil
		lackedPickupFeeAmount = 0
	
	end
end

function imgui.OnDrawFrame()
	-- Window sizing & positioning
	local screenWidth, screenHeight = getScreenResolution()
	imgui.SetNextWindowPos(imgui.ImVec2(screenWidth / 2, screenHeight / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
	imgui.SetNextWindowSize(imgui.ImVec2(970, 505), imgui.Cond.FirstUseEver)
	
	---------------------------
	-- USER-CONTROLLED SETTINGS
	---------------------------
	
	imgui.Begin("Bear x Adib AutoGetMats v" .. script_version)
	imgui.PushItemWidth(-110)
	
	-- Pickup toggle
	imgui.Checkbox("AUTOMATIC PACKAGE PICKUP - /autogm", gmmenu.imbool_hasPlayerEnabledPickup)
	
	imgui.NewLine() imgui.NewLine()
	
	-- Color settings for the message box clearing buttons
	gmmenu_style.Colors[imgui.Col.Button] = imgui.ImVec4(0.2, 0.2, 0.2, 0.5)
	gmmenu_style.Colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.3, 0.3, 0.3, 0.5)
	gmmenu_style.Colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.45, 0.45, 0.45, 0.5)
	
	-- Pickup message boxes
	imgui.Checkbox("PACKAGE PICKUP TEXT (OPTIONAL) - EXAMPLE: /me collects some material packages.", gmmenu.messagesData.pickup.imbool_areAllEnabled)
	if gmmenu.messagesData.pickup.imbool_areAllEnabled.v then
		imgui.InputText("P1", gmmenu.messagesData.pickup.m1.buffer)
		imgui.SameLine() if imgui.Button("CLEAR P1") then gmmenu.messagesData.pickup.m1.buffer.v = "" end
		
		imgui.InputText("P2", gmmenu.messagesData.pickup.m2.buffer)
		imgui.SameLine() if imgui.Button("CLEAR P2") then gmmenu.messagesData.pickup.m2.buffer.v = "" end
		
		imgui.InputText("P3", gmmenu.messagesData.pickup.m3.buffer)
		imgui.SameLine() if imgui.Button("CLEAR P3") then gmmenu.messagesData.pickup.m3.buffer.v = "" end
	end
	
	imgui.NewLine() imgui.NewLine()
	
	-- Delivery message boxes
	imgui.Checkbox("PACKAGE DELIVERY TEXT (OPTIONAL) - EXAMPLE: I delivered.", gmmenu.messagesData.delivery.imbool_areAllEnabled)
	
	if gmmenu.messagesData.delivery.imbool_areAllEnabled.v then
		imgui.InputText("D1", gmmenu.messagesData.delivery.m1.buffer)
		imgui.SameLine() if imgui.Button("CLEAR D1") then gmmenu.messagesData.delivery.m1.buffer.v = "" end
		
		imgui.InputText("D2", gmmenu.messagesData.delivery.m2.buffer)
		imgui.SameLine() if imgui.Button("CLEAR D2") then gmmenu.messagesData.delivery.m2.buffer.v = "" end
		
		imgui.InputText("D3", gmmenu.messagesData.delivery.m3.buffer)
		imgui.SameLine() if imgui.Button("CLEAR D3") then gmmenu.messagesData.delivery.m3.buffer.v = "" end
	end
	
	imgui.NewLine() imgui.NewLine()
	
	-- Credits
	imgui.Text("CREDITS: Bear (Swapnil#9308), Adib23704#8947, Brad#6219, Ezio (PriPat#9969), Hr1doy#6038")
	
	imgui.NewLine() imgui.NewLine() imgui.NewLine() imgui.NewLine()
	
	------------------
	-- CLOSING OPTIONS
	------------------
	
	local closing_btns_size = imgui.ImVec2(160, 30)
	imgui.SetCursorPosX(imgui.GetCursorPosX() + ((imgui.GetWindowWidth() - 370) / 2))
	
	-- Option 1: Save & close
	gmmenu_style.Colors[imgui.Col.Button] = imgui.ImVec4(0.2, 0.4, 0.2, 0.5)
	gmmenu_style.Colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.3, 0.6, 0.3, 0.5)
	gmmenu_style.Colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.45, 0.9, 0.45, 0.5)
	
	if imgui.Button("SAVE & CLOSE", closing_btns_size) then
		hasPlayerDisabledPickup, mainIni.General.hasPlayerDisabledPickup = not gmmenu.imbool_hasPlayerEnabledPickup.v, not gmmenu.imbool_hasPlayerEnabledPickup.v
		mainIni.PickupMessages.areAllEnabled = gmmenu.messagesData.pickup.imbool_areAllEnabled.v
		mainIni.DeliveryMessages.areAllEnabled = gmmenu.messagesData.delivery.imbool_areAllEnabled.v
		getConfigMessageValuesFromBuffers()
		
		imgui.Process = false
	end
	
	imgui.SameLine(0)
	
	-- Option 2: Close without saving
	gmmenu_style.Colors[imgui.Col.Button] = imgui.ImVec4(0.4, 0.2, 0.2, 0.5)
	gmmenu_style.Colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.6, 0.3, 0.3, 0.5)
	gmmenu_style.Colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.9, 0.6, 0.6, 0.5)
	
	if imgui.Button("CLOSE WITHOUT SAVING", closing_btns_size) then
		gmmenu.imbool_hasPlayerEnabledPickup.v = not hasPlayerDisabledPickup
		gmmenu.messagesData.pickup.imbool_areAllEnabled.v = mainIni.PickupMessages.areAllEnabled
		gmmenu.messagesData.delivery.imbool_areAllEnabled.v = mainIni.DeliveryMessages.areAllEnabled
		getMessageBufferValuesFromConfig()
		
		imgui.Process = false
	end
	
	imgui.End()
end


-----------------------------------------------------
-- COMMAND-SPECIFIC FUNCTIONS
-----------------------------------------------------


function cmd_autogm()
	hasPlayerDisabledPickup = mainIni.General.hasPlayerDisabledPickup
	
	if hasPlayerDisabledPickup then
		hasPlayerDisabledPickup, mainIni.General.hasPlayerDisabledPickup = false, false
		gmmenu.imbool_hasPlayerEnabledPickup.v = true
		if inicfg.save(mainIni, directIni) then
			sampAddChatMessage("{FFFFFF}--- {FFFF00}AutoGetmats: {FFFFFF}Enabled", -1)
		end
	else
		hasPlayerDisabledPickup, mainIni.General.hasPlayerDisabledPickup = true, true
		gmmenu.imbool_hasPlayerEnabledPickup.v = false
		if inicfg.save(mainIni, directIni) then
			sampAddChatMessage("{FFFFFF}--- {FFFF00}AutoGetMats: {888888}Disabled", -1)
		end
	end
end

function cmd_gmmenu()
	imgui.Process = not imgui.Process
end