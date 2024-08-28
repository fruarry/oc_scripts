local computer = require('computer')
local component = require('component')
local event = require("event")
local os = require("os")

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
    address_rsio_control = "bfac2715-c9d0-4890-8874-6b84257b875d",
    address_transposer = "2bb79ebf-f634-4c1c-a48a-2f08963ff4f7",
    address_reactor_chamber = "45f43739-d56e-4f52-b402-8b37767e0faf",

    transposer_side_reactor = 2,
    transposer_side_sink = 5,
    transposer_side_source = 4,

    rsio_side_on_state = 1,
    rsio_side_off_state = 3,
    rsio_side_error_state = 4,
    rsio_side_ext_start = 2,
    rsio_side_scram = 5,

    overheat_threshold = 9000,
    reactor_status_report_interval = 10,
    reactor_watchdog_interval = 0.5,
    reactor_light_signal_interval = 1,
    start_error_retry_interval = 5
}

-- Component list
local rsio_control = component.proxy(config.address_rsio_control)
local transposer = component.proxy(config.address_transposer)
local reactor_chamber = component.proxy(config.address_reactor_chamber)

-- Error code
local error_code = {
    [0] = "no_error",
    [1] = "not_enough_sink_space",
    [2] = "not_eought_source_item",
    [3] = "item_transfer_error",
    [4] = "unknown_start_error"
}

-- Reactor structure
local reactor_state = {
    current_state = "init_state",
    next_state = "init_state",

    start_error_code = 0,
    start_error_time = 0,
    count_down_end = false,

    ext_start = false,

    item_update = false,
    item_export = {},
    item_import = {},

    producesEnergy = false,
    EUOutput = 0,
    heat = 0,
    maxHeat = 10000
}

-- Check
local function is_empty(tbl)
    local next = next
    if next(tbl) == nil then
        return true
    else
        return false
    end
end

-- Configuration check
local function check_configuration()
end

-- Generate item report of reactor chamber
local function check_reactor_item()
    reactor_state.item_export = {}
    reactor_state.item_import = {}
    local export = reactor_state.item_export
    local import = reactor_state.item_import
    
    for _, resource in pairs(config.resource) do
        import[resource.name] = {}
        for _, slot in pairs(resource.slot) do
            local target = transposer.getStackInSlot(config.transposer_side_reactor, slot)
            if target == nil then
                table.insert(import[resource.name], slot)
            elseif target.name ~= resource.name then
                table.insert(export, slot)  -- export list
                table.insert(import[resource.name], slot)
            elseif resource.damage ~= -1 and target.damage >= resource.damage then
                table.insert(export, slot)  -- export list
                table.insert(import[resource.name], slot)
            end
        end
        if is_empty(import[resource.name]) then
            import[resource.name] = nil
        end
    end

    if is_empty(export) and is_empty(import) then
        reactor_state.item_update = false
    else
        reactor_state.item_update = true
    end
end

-- Update reactor chamber items
local function update_reactor_item()
    local export = reactor_state.item_export
    local import = reactor_state.item_import
    -- Export item
    for _, slot in pairs(export) do
        local transfer_count = transposer.transferItem(config.transposer_side_reactor, config.transposer_side_sink, 1, slot)
        if transfer_count == 0 then
            return 1    -- error code
        end
    end

    -- Not enough item
    if is_empty(import) then
        return 4    -- error code
    end

    -- Generate transfer list
    local transfer_list = {}
    local source_size = transposer.getInventorySize(config.transposer_side_source)
    for i = 1, source_size do
        local source_item = transposer.getStackInSlot(config.transposer_side_source, i)
        if source_item ~= nil and import[source_item.name] ~= nil then
            local slot = import[source_item.name]
            for j = 1, source_item.size do
                table.insert(transfer_list, {i, slot[#slot]})
                slot[#slot] = nil
                if is_empty(slot) then
                    import[source_item.name] = nil
                    break
                end
            end
            if is_empty(import) then
                break
            end
        end
    end

    -- Not enough item
    if not is_empty(import) then
        return 2    -- error code
    end

    -- Transfer item
    for _, transfer_pair in pairs(transfer_list) do
        local transfer_count = transposer.transferItem(
            config.transposer_side_source, config.transposer_side_reactor, 1, transfer_pair[1], transfer_pair[2])
        if transfer_count == 0 then
            return 3    -- error code
        end
    end

    return 0
end

-- Reactor control
local function start_reactor()
    reactor_chamber.setActive(true)
end

local function stop_reactor()
    reactor_chamber.setActive(false)
end

-- Display
local function display(msg)
    print("  INFO > " .. msg)
end

local function display_error(msg)
    print("*ERROR > " .. msg)
end

-- SCRAM
local function scram()
    display("SCRAM activated.")
    reactor_state.current_state = "shut_state"
    reactor_state.next_state = "off_state"
end

local function reactor_watchdog()
    reactor_state.producesEnergy = reactor_chamber.producesEnergy()
    reactor_state.EUOutput = reactor_chamber.getReactorEUOutput()
    reactor_state.heat = reactor_chamber.getHeat()
    reactor_state.maxHeat = reactor_chamber.getMaxHeat()

    if reactor_state.heat >= config.overheat_threshold then
        scram()
    end

    if reactor_state == off_state and reactor_state.producesEnergy then
        scram()
    end
end

local function reactor_status_report()
    os.execute("cls")
    print("==================================")
    print("  Vaccum Nuclear Reactor")
    print("  Version:     1.0")
    print("  Author:      Kerel")

    if reactor_state.producesEnergy then
    print("  Status:      Active")
    print("  Energy:      " .. tostring(reactor_state.EUOutput) .. " EU/t")
    print("  Heat/Max:    " .. tostring(reactor_state.heat) .. " /" .. tostring(reactor_state.maxHeat))
    else
    print("  Status:      Inactive")
    print("  Heat/Max:    " .. tostring(reactor_state.heat) .. " /" .. tostring(reactor_state.maxHeat))
    end
    
    print("  Debug:       " .. reactor_state.current_state)
    print("==================================")
end

local function ternary ( cond , T , F )
    if cond then return T else return F end
end

local function reactor_light_signal()
    rsio_control.setOutput(config.rsio_side_error_state, ternary(reactor_state.current_state == "start_count_down_state", 15, 0))
    rsio_control.setOutput(config.rsio_side_off_state, ternary(reactor_state.current_state == "off_state", 15, 0))
    rsio_control.setOutput(config.rsio_side_on_state, ternary(reactor_state.current_state == "on_state", 15, 0))
    rsio_control.setOutput(config.rsio_side_scram, ternary(reactor_state.current_state ~= "off_state", 1, 0))
end

local exit_signal = false
local function key_down_handler(eventName, keyboardAddress, char, code, playerName)
    if code == 0x10 then
        scram()
        exit_signal = true
    end
end

local function redstone_changed_handler(eventName, address, side, oldValue, newValue, color)
    if address == config.address_rsio_control then
        if side == config.rsio_side_scram and newValue == 15 then
            scram()
        end
        if side == config.rsio_side_ext_start and newValue == 15 then
            reactor_state.ext_start = true
        end
    end
end

-- Register event
local timer = {}
local function register_event()
    event.listen("key_down", key_down_handler)
    event.listen("redstone_changed", redstone_changed_handler)

    table.insert(timer, event.timer(config.reactor_watchdog_interval, reactor_watchdog, math.huge))
    table.insert(timer, event.timer(config.reactor_status_report_interval, reactor_status_report, math.huge))
    table.insert(timer, event.timer(config.reactor_light_signal_interval, reactor_light_signal, math.huge))
end

local function unregister_event()
    event.ignore("key_down", key_down_handler)
    event.ignore("redstone_changed", redstone_changed_handler)

    for _, timer_id in pairs(timer) do
        event.cancel(timer_id)
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
        end,
    on_state = 
        function()
            if reactor_state.item_update then
                return "start_state"
            else
                return "on_state"
            end
        end,
    shut_state = 
        function()
            return "off_state"
        end,
    start_error_state = 
        function()
            return "start_count_down_state"
        end,
    start_count_down_state =
        function()
            if reactor_state.count_down_end then
                return "start_state"
            else
                return "start_count_down_state"
            end
        end
}
local reactor_control_action = {
    init_state = 
        function()
            display("Initializing...")
            check_configuration()
        end,
    off_state =
        function()
        end,
    start_state = 
        function()
            reactor_state.ext_start = false
            stop_reactor()
            display("Reactor stopped. Fuel rod loading...")
            check_reactor_item()
            if reactor_state.item_update then
                reactor_state.start_error_code = update_reactor_item()
                if reactor_state.start_error_code ~= 0 then
                    return
                end
            end
            display("Fuel rod loaded. Reactor Starting")
            start_reactor()
        end,
    on_state = 
        function()
            check_reactor_item()
        end,
    shut_state =
        function()
            stop_reactor()
            display("Reactor stopped.")
        end,
    start_error_state = 
        function()
            display_error(error_code[reactor_state.start_error_code])
            reactor_state.start_error_time = os.time()
            reactor_state.count_down_end = false
            display("Retry in 5 seconds...")
        end,
    start_count_down_state = 
        function()
            elapsed_second = (os.time() - reactor_state.start_error_time)*1000/60/60
            if elapsed_second >= config.start_error_retry_interval then
                reactor_state.count_down_end = true
            end
        end
}

-- Main control logic for vaccum nuclear reactor
local function main()
    reactor_status_report()
    register_event()
    
    while not exit_signal do
        reactor_control_action[reactor_state.current_state]()
        reactor_state.next_state = reactor_control_fsm[reactor_state.current_state]()

        reactor_state.current_state = reactor_state.next_state
        os.sleep(0.05)
    end

    unregister_event()
end

main()
