local computer = require("computer")
local component = require("component")
local event = require("event")
local os = require("os")
local term = require("term")
local colors = require("colors")
local sides = require("sides")

-- Reactor configuration
address_rsio_control = "bfac2715-c9d0-4890-8874-6b84257b875d"
address_transposer = "25798479-84cf-4299-834b-791ccd2f2db7"
address_reactor_chamber = "87736b6a-2eb3-4f58-9d6f-bcbaa8dde5c1"

transposer_side_reactor = sides.top
transposer_side_input = sides.west
transposer_side_output = sides.east

rsio_side = sides.east
rsio_color_on_state = colors.green
rsio_color_error_state = colors.orange
rsio_color_ext_state = colors.white
rsio_color_scram = colors.red

config = {
    pattern = {
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
    overheat_threshold = 7000,
    eeactor_status_interval = 1,
    reactor_watchdog_interval = 0.2,
    start_error_retry_interval = 5
}

-- Component list
local rsio_control = component.proxy(address_rsio_control)
local transposer = component.proxy(address_transposer)
local reactor_chamber = component.proxy(address_reactor_chamber)

-- Restone IO bundle output
local function rsio_set_bundle_output_all(side, level)
    for i = 0, 15 do
        rsio_control.setBundledOutput(side, i, level)
    end
end

-- Reactor structure
local reactor_state = {
    current_state = "init_state",
    next_state = "init_state",

    start_error_time = 0,
    count_down_end = false,

    ext_start = false,

    producesEnergy = false,
    EUOutput = 0,
    heat = 0,
    maxHeat = 10000
}

local function is_empty(tbl)
    local next = next
    if next(tbl) == nil then
        return true
    else
        return false
    end
end

local function ternary (cond, T, F)
    if cond then return T else return F end
end

local function append(tbl, key, value)
    if tbl[key] == nil then
        tbl[key] = {value}
    else
        table.insert(tbl[key], value)
    end
end

-- error code
local error_msg = {
    [-1] = "unknown_error",
    [0] = "no_error",
    [1] = "not_enough_output_space",
    [2] = "missing_input_item",
    [3] = "item_transfer_error",
    [4] = "configuration_error",
    [5] = "missing_reactor_item",
    [6] = "mistach_depleted_reactor_item",
    [7] = "damaged_reactor_item",
    [8] = "reactor_overheat"
}

-- Display
local function display(msg)
    print("  info> " .. msg)
end

local function display_error(err)
    if error_msg[err] == nil then
        err = -1  -- unknown error
    end
    print("*error> " .. error_msg[err])
end

-- Component check
local function check_component()
    if rsio_control == nil then
        display("Cannot access redstone I/O.")
        return 4
    elseif rsio_control.getBundledInput(rsio_side, rsio_color_ext_state) > 15 then
        display("Start signal is high.")
    elseif rsio_control.getBundledInput(rsio_side, rsio_color_scram) > 15 then
        display("SCRAM signal is high.")
    end

    if transposer == nil then
        display("Cannot access transposer.")
        return 4
    elseif transposer.getInventoryName(transposer_side_reactor) ~= "blockReactorChamber" then
        display("Transposer cannot access reactor chamber.")
        return 4
    elseif transposer.getInventoryName(transposer_side_input) == nil then
        display("Transposer cannot access input inventory.")
        return 4
    elseif transposer.getInventoryName(transposer_side_output) == nil then
        display("Transposer cannot access output inventory.")
        return 4
    end

    if reactor_chamber == nil then
        display("Cannot access reactor chamber.")
        return 4
    elseif reactor_chamber.producesEnergy() then
        display("Reactor is running.")
        stop_reactor()
    end
    return 0
end

-- Check reactor damage
local function check_reactor_damage(quick)
    local reactor_box = transposer.getAllStacks(transposer_side_reactor).getAll()
    for i = 1, #config.pattern do
        pattern = config.pattern[i]
        for j = 1, #pattern.slot do
            local reactor_box_slot = reactor_box[pattern.slot[j] - 1]
            if reactor_box_slot.name == nil then
                return 5
            elseif reactor_box_slot.name ~= pattern.name then
                return 6
            elseif pattern.damage ~= -1 and reactor_box_slot.damage >= pattern.damage then
                return 7
            end
        end
    end
    return 0
end

-- Update reactor chamber items
local function update_reactor_item()
    -- Generate input box item lookup table
    local input_box = transposer.getAllStacks(transposer_side_input).getAll()
    local input_item_list = {}
    for i = 0, #input_box-1 do
        local input_box_slot = input_box[i]
        if input_box_slot.name then
            append(input_item_list, input_box_slot.name, i)
        end
    end

    local function try_output(slot)
        -- transfer index start with 0
        return transposer.transferItem(
            transposer_side_reactor, transposer_side_output, 1, slot)
    end

    local missing_item_list = {}
    local function try_input(name, slot)
        -- Get input item slot
        local input_slot = -1
        if input_item_list[name] ~= nil then
            local item_list_slot = input_item_list[name]
            while #item_list_slot > 0 do
                local slot = item_list_slot[#item_list_slot]
                if input_box[slot].size > 0 then
                    input_slot = slot
                    input_box[slot].size = input_box[slot].size - 1
                    break
                else
                    item_list_slot[#item_list_slot] = nil
                end
            end
            if #item_list_slot == 0 then
                input_item_list[name] = nil
            end
        end

        -- Input not available
        if input_slot == -1 then
            append(missing_item_list, pattern.name, slot)
            return 0
        end

        -- Try to transfer
        -- transfer index start with 1
        return transposer.transferItem(
            transposer_side_input, transposer_side_reactor, 1, input_slot + 1, slot)
    end

    local reactor_box = transposer.getAllStacks(transposer_side_reactor).getAll()
    for i = 1, #config.pattern do
        pattern = config.pattern[i]
        for j = 1, #pattern.slot do
            local reactor_slot = pattern.slot[j]
            local reactor_box_slot = reactor_box[reactor_slot - 1]  -- inventory index start with 0
            if reactor_box_slot.name == nil then
                try_input(pattern.name, reactor_slot)
            elseif reactor_box_slot.name ~= pattern.name then
                if try_output(reactor_slot) == 0 then
                    return 1
                end
                try_input(pattern.name, reactor_slot)
            elseif pattern.damage ~= -1 and reactor_box_slot.damage >= pattern.damage then
                if try_output(reactor_slot) == 0 then
                    return 1
                end
                try_input(pattern.name, reactor_slot)
            end
        end
    end

    -- Report missing item
    if not is_empty(missing_item_list) then
        for name, slot in pairs(missing_item_list) do
            display("Missing \"" .. name .. "\" x" .. tostring(#slot))
        end
        return 2    -- error code
    end

    return 0
end

-- Reactor control
local function start_reactor()
    if reactor_chamber.getHeat() > config.overheat_threshold then
        return 8
    end
    reactor_chamber.setActive(true)
    display("Reactor started.")
    return 0
end

local function stop_reactor()
    reactor_chamber.setActive(false)
    display("Reactor stopped.")
    return 0
end

-- SCRAM
local function scram()
    display("SCRAM")
    reactor_state.current_state = "off_state"
    reactor_state.next_state = "off_state"
    reactor_state.ext_start = false
    stop_reactor()
end

local function reactor_watchdog()
    reactor_state.producesEnergy = reactor_chamber.producesEnergy()
    reactor_state.EUOutput = reactor_chamber.getReactorEUOutput()
    reactor_state.heat = reactor_chamber.getHeat()
    reactor_state.maxHeat = reactor_chamber.getMaxHeat()

    if reactor_state.heat >= config.overheat_threshold then
        display("WDT: Detected reactor overheat.")
        scram()
    end

    if reactor_state == off_state and reactor_state.producesEnergy then
        display("WDT: Detected unexpected reactor activation.")
        scram()
    end
end

local function reactor_status_header()
    term.setCursor(1, 1)
    term.write("==================================================\n")
    term.write("  VNR Program -- by Kerel                         \n")
    term.write("  Heat/Max = " .. tostring(reactor_state.heat) .. "/" .. tostring(reactor_state.maxHeat) .. "                         \n", false)

    if reactor_state.producesEnergy then
    term.write("  Energy = " .. tostring(reactor_state.EUOutput) .. " EU/t                         \n", false)
    else
    term.write("  Energy = 0 EU/t                                 \n")
    end
    term.write("==================================================\n")
end

local function reactor_status()
    local cx, cy
    cx, cy = term.getCursor()
    reactor_status_header()
    term.setCursor(cx, cy)
    
    rsio_control.setBundledOutput(rsio_side, rsio_color_ext_state, ternary(reactor_state.current_state == "off_state", 15, 0))
    rsio_control.setBundledOutput(rsio_side, rsio_color_error_state, ternary(reactor_state.current_state == "start_error_state", 15, 0))
    rsio_control.setBundledOutput(rsio_side, rsio_color_on_state, ternary(reactor_state.current_state == "on_state", 15, 0))
    rsio_control.setBundledOutput(rsio_side, rsio_color_scram, ternary(reactor_state.current_state ~= "off_state", 15, 0))
end

local exit_signal = false
local function key_down_handler(eventName, keyboardAddress, char, code, playerName)
    if code == 0x10 then
        scram()
        exit_signal = true
    end
end

local function redstone_changed_handler(eventName, address, side, oldValue, newValue, color)
    if address == address_rsio_control then
        if side == rsio_side and color == rsio_color_scram and newValue > 15 then
            scram()
        end
        if side == rsio_side and color == rsio_color_ext_state and newValue > 15 then
            if reactor_state.current_state == "off_state" then
                reactor_state.ext_start = true
            end
        end
    end
end

-- Register event
local event_handler = {}
local function register_event()
    table.insert(event_handler, event.listen("key_down", key_down_handler))
    table.insert(event_handler, event.listen("redstone_changed", redstone_changed_handler))

    table.insert(event_handler, event.timer(config.reactor_watchdog_interval, reactor_watchdog, math.huge))
    table.insert(event_handler, event.timer(config.eeactor_status_interval, reactor_status, math.huge))
end

local function unregister_event()
    for _, id in pairs(event_handler) do
        event.cancel(id)
    end
end

-- Reactor control FSM
local reactor_control_fsm = {
    init_state = 
        function()
            display("Self-checking...")
            local ret = check_component()
            if ret ~= 0 then
                display_error(ret)
                exit_signal = true
                return "init_state"
            end
            display("Self-check passed.")
            return "off_state"
        end,
    off_state =
        function()
            if reactor_state.ext_start then
                return "start_state"
            end
            return "off_state"
        end,
    start_state = 
        function()
            reactor_state.ext_start = false
            display("Updating reactor chamber items...")
            local ret = update_reactor_item()
            if ret ~= 0 then
                display_error(ret)
                reactor_state.last_error_time = os.time()
                display("Retry in ".. tostring(config.start_error_retry_interval) .." seconds...")
                return "start_error_state"
            end
            ret = start_reactor()
            if ret ~= 0 then
                display_error(ret)
                return "off_state"
            end
            return "on_state"
        end,
    on_state = 
        function()
            local ret = check_reactor_damage()
            if ret ~= 0 then
                display_error(ret)
                stop_reactor()
                return "start_state"
            end
            return "on_state"
        end,
    start_error_state = 
        function()
            elapsed_second = (os.time() - reactor_state.last_error_time)*5.55  -- convert to second
            if elapsed_second >= config.start_error_retry_interval then
                return "start_state"
            end
            return "start_error_state"
        end
}

-- Main control logic for vaccum nuclear reactor
local function main()
    os.execute("cls")
    reactor_status_header()
    rsio_set_bundle_output_all(rsio_side, 15)
    register_event()
    
    while not exit_signal do
        reactor_state.next_state = reactor_control_fsm[reactor_state.current_state]()
        reactor_state.current_state = reactor_state.next_state
        os.sleep(0.05)
    end

    display("Exiting...")
    unregister_event()
    rsio_set_bundle_output_all(rsio_side, 0)
end

main()
