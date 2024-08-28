
local computer = require('computer')
local component = require('component')

-- Reactor configuration
config = {
	resource = {
		{
			name = "gregtech:gt.360k_Helium_Coolantcell",
			damage = 90,
			slot = { 3, 6, 9, 10, 15, 22, 26, 29, 33, 40, 45, 46, 49, 52 }
		},
		{
			name = "gregtech:gt.reactorUraniumQuad",
			damage = -1,
			slot = {
				1, 2, 4, 5, 7, 8, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 23, 24, 25, 27, 28, 30, 31, 32, 34, 35, 36, 37,
				38, 39, 41, 42, 43, 44, 47, 48, 50, 51, 53, 54 }
		}
	},
	address_rsio_control = xx,
	address_transposer = xx,
	address_reactor_chamber = xx,

	transposer_side_reactor = xx,
	transposer_side_sink = xx,
	transposer_side_source = xx,

	rsio_side_on_state = xx,
	rsio_side_off_state = xx,
	rsio_side_error_state = xx,
	rsio_side_ext_start = xx,
	rsio_side_scram = xx,

	overheat_threshold = 9000,
	reactor_status_report_interval = 10,
	reactor_watchdog_interval = 0.5,
	start_error_retry_interval = 5
}

-- Error code
local error_code = {
	[0] = "no_error",
	[1] = "not_enough_sink_space",
	[2] = "not_eought_source_item",
	[3] = "item_transfer_error",
}

-- Component list
local rsio_control = component.proxy(address_rsio_control)
local transposer = component.proxy(address_transposer)
local reactor_chamber = component.proxy(address_reactor_chamber)

-- Configuration check
local function checkConfiguration()
end

-- Generate item report of reactor chamber
local function checkReactorItem()
	local export = {}
	local import = {}
	local function exportAppend(slot) table.insert(export, slot) end
	local function importAppend(name, slot)
		if import[name] == nil then
			import[name] = {}
		end
		table.insert(import[name], slot)
	end
	
	for i = 1, #config.resource do
		local resourcce = config.resource[i]
		for s = 1, #resource.slot do
			local slot = resource.slot[s]
			local target = transposer.getStackInSlot(config.transposer_side_reactor, slot)
			if target == nil then
				importAppend(resource.name, slot)
			elseif target.name ~= resource.name then
				exportAppend(slot)
				importAppend(resource.name, slot)
			elseif resource.damage ~= -1 and target.damage >= resource.damage then
				exportAppend(slot)
				importAppend(resource.name, slot)
			end
		end
	end
	return export, import
end

-- Update reactor chamber items
local function updateReactorItem(export, import)
	-- Export item
	for i = 1, #export do
		local transfer_count = transposer.transferItem(transposer_side_reactor, transposer_side_sink, 1, export[i])
		if transfer_count == 0 then
			return 1  -- error code
		end
	end
	
	-- Generate transfer list
	local transfer_list = {}
	local source_size = transposer.getInventorySize(transposer_side_source)
	for i = 1, source_size do
		local source_item = transposer.getStackInSlot(transposer_side_source, i)
		local import_item_slot = import[source_item.name]
		if source_item ~= nil and import_item_slot ~= nil then
			table.insert(transfer_list, {i, import_item_slot[#import_item_slot]})
			import_item_slot[#import_item_slot] = nil
			if #import_item_slot == 0 then
				import[source_item.name] = nil
				if #import == 0 then
					break
				end
			end
		end
	end

	-- Not enough item
	if #import ~= 0 then
		return 2  -- error code
	end

	-- Transfer item
	for i = 1, #transfer_list do
		local transfer_count = transposer.transferItem(
			transposer_side_source, transposer_side_reactor, 1, transfer_list[i][1], transfer_list[i][2])
		if transfer_count == 0 then
			return 3  -- error code
		end
	end

	return 0
end

-- Reactor control
local function startReactor()
	reactor_chamber.setActive(true)
end

local function stopReactor()
	reactor_chamber.setActive(false)
end

-- Redstone IO
local function redstoneInputAny(rsio, level)
	if type(level) ~= "number" then
		level = 15
	end
	input = rsio.getInput()
	for i = 0, 5 do
		if input[i] >= level then
			return true
		end
	end
	return false
end

-- Display
local function display(msg)
	print("  INFO > " .. msg)
end

local function display_error(msg)
	print(" ERROR > " .. msg)
end

local function display_header()
	os.execute("cls")
	print("==========================")
	print("  Vaccum Nuclear Reactor")
	print("  Version:     1.0")
	print("  Author:      Kerel")
	print("==========================")
end

-- Reactor structure
local reactor_state = {
	current_state = "init_state",
	next_state = "init_state",

	start_error_code = 0,
	start_error_time = 0,

	ext_start = false,
	start_success = false,

	item_update = false,
	item_export = {},
	item_import = {}
}

local function scram()
	display("SCRAM activated.")
	reactor_state.current_state = "off_state"
	reactor_state.next_state = "off_state"
end

-- Register event
local exit_signal = false
local function key_down_handler(eventName, keyboardAddress, char, code, playerName)
	if code == 0x10 then
		scram()
		exit_signal = true
	end
end

local function reactor_status_report()
	local producesEnergy = reactor_chamber.producesEnergy()
	local EUOutput = reactor_chamber.getReactorEUOutput()
	local heat = reactor_chamber.getHeat()
	local maxHeat = reactor_chamber.getMaxHeat()
	if producesEnergy then
		display("Active, Energy: " .. tostring(EUOutput) .. " EU/t, Heat/Max: " .. tostring(heat) .. " /" .. tostring(maxHeat))
	else
		display("Inactive, Heat/Max: " .. tostring(heat) .. " /" .. tostring(maxHeat))
	end
end

local function reactor_watchdog()
	local heat = reactor_chamber.getHeat()
	if heat >= config.overheat_threshold then
		scram()
	end

	rsio_control.setOutput(rsio_side_error_state, (reactor_state.current_state == "error_state") and 15 or 0)
	rsio_control.setOutput(rsio_side_off_state, (reactor_state.current_state == "off_state") and 15 or 0)
	rsio_control.setOutput(rsio_side_on_state, (reactor_state.current_state == "on_state") and 15 or 0)
	rsio_control.setOutput(rsio_side_on_state, (reactor_state.current_state ~= "off_state") and 1 or 0)
end

local function redstone_changed_handler(address, side, oldValue, newValue, color)
	if address == address_rsio_control and side == rsio_side_scram then
		if newValue == 15 then
			scram()
		end
	end
end

local listener = {}
local function register_listener()
	table.insert(listener, event.register("key_down", key_down_handler))
	table.insert(listener, event.timer(reactor_watchdog_interval, reactor_watchdog))
	table.insert(listener, event.timer(reactor_status_report_interval, reactor_status_report))
	table.insert(listener, event.register("redstone_changed", redstone_changed_handler))
end

local function unregister_listener()
	for i = 1, #listener do
		event.unregister(listener[i])
	end
end

local function update_reactor_state()
	-- Check external control
	reactor_state.ext_start = rsio_control.getInput(rsio_side_ext_start)
	
	-- Check item
	item_export, item_import = checkReactorItem()
	local next = next
	if next(item_export) == nil and next(item_import) == nil then
		reactor_state.item_update = false
		reactor_state.item_export = {}
		reactor_state.item_import = {}
	else
		reactor_state.item_update = true
		reactor_state.item_export = item_export
		reactor_state.item_import = item_import
	end
end

-- Reactor control FSM
local reactor_control_fsm = {
	init_state =
		function()
			return "off_state"
		end,
	off_state =
		function()
			if reactor_state.ext_start then
				return "start_state"
			else
				return "off_state"
			end
		end,
	start_state = 
		function()
			if reactor_state.start_error_code ~= 0 then
				return "start_error_state"
			else
				return "on_state"
			end
		end
	on_state = 
		function()
			if not reactor_state.ext_start then
				return "off_state"
			elseif reactor_state.item_update then
				return "start_state"
			else
				return "on_state"
			end
		end,
	start_error_state = 
		function()
			elapsed_second = (os.time() - reactor_state.start_error_time)*1000/60/60
			if elapsed_second >= start_error_retry_interval then
				return "start_state"
			else
				return "start_error_state"
		end
}
local reactor_control_action = {
	init_state = 
		function()
			display("Initializing...")
			update_reactor_state()
		end,
	start_state = 
		function()
			display("Reactor stopped. Fuel rod loading...")
			stopReactor()
			if reactor_state.item_update then
				reactor_state.start_error_code = updateReactorItem(reactor_state.item_export, reactor_state.item_import)
				if reactor_state.start_error_code ~= 0 then
					display_error(error_code[reactor_state.start_error_code])
					reactor_state.start_error_time = os.time()
					display("Retry in 5 seconds...")
					return
				end
			end
			display("Fuel rod loaded. Reactor Starting")
			startReactor()
		end,
	on_state = 
		function()
			update_reactor_state()
		end,
	off_state =
		function()
			stopReactor()
			display("Reactor stopped.")
		end
	start_error_state = 
		function()
		end
}

-- Main control logic for vaccum nuclear reactor
local function main()
	display_header()
	register_listener()
	
    while not exit_signal do
		reactor_control_action[reactor_state.current_state]()
		reactor_state.next_state = reactor_control_fsm[reactor_state.current_state]()

		reactor_state.current_state = reactor_state.next_state
		os.sleep(0.05)
	end

	unregister_listener()
end

main()
