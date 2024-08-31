local computer = require("computer")
local component = require("component")
local event = require("event")
local os = require("os")
local term = require("term")
local colors = require("colors")
local sides = require("sides")
local nr_pattern = require("nr_pattern")

-- Reactor configuration
local global_config = {
    addr_buffer = "xx",
    addr_buffer_inv = "xx",
    side_buffer = sides.top,

    buffer_level = 0.9,

    error_retry_interval = 5,

    status_interval = 1,
    watchdog_interval = 0.2,
}

local config = {
    [1] = {
        pattern_name = "quad_uranium",

        addr_rsio = "185e3c6b-b187-4b69-9e53-e05e12ffdaa0",
        addr_transposer = "7f80ab5e-a78d-4ef9-abf6-0f374425139f",
        addr_reactor_chamber = "ed33ff55-73c0-44ea-af14-4a84744bd936",

        side_reactor = sides.north,
        side_input = sides.west,
        side_output = sides.east,
        side_rsio = sides.west,
        color_on = colors.green,
        color_error = colors.orange,
        color_start_en = colors.white,
        color_stop_en = colors.red,
        allow_auto_start = true
    },
    [2] = {
        pattern_name = "glowstone",

        addr_rsio = "185e3c6b-b187-4b69-9e53-e05e12ffdaa0",
        addr_transposer = "532c3e2a-2841-4a16-8ba9-fbd8109eaa72",
        addr_reactor_chamber = "8a1823fe-5693-4917-ba97-bf184da9b2c3",

        side_reactor = sides.north,
        side_input = sides.west,
        side_output = sides.east,
        side_rsio = sides.west,
        color_on = colors.lime,
        color_error = colors.yellow,
        color_start_en = colors.gray,
        color_stop_en = colors.pink,
        allow_auto_start = false
    }
}

local function reactor_init()
    return {
        rsio = nil,
        transposer = nil,
        reactor_chamber = nil,

        pattern = nil,

        state = "OFF",

        start_en = false,
        stop_en = false,
        error_time = 0,

        producesEnergy = false,
        EUOutput = 0,
        heat = 0,
        maxHeat = 10000,
        heatPrec = 0
    }
end

-- Reactor structure
local reactor = {}
local buffer = {
    enable = false,
    machine = nil,
    machine_inv = nil,
    EUStored = 0,
    EUmax = 0,
    EUNetChange = 0,
    EUPrec = 0
}

local function is_empty(tbl)
    local next = next
    if next(tbl) == nil then
        return true
    else
        return false
    end
end

local function ternary(cond, T, F)
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
    [0] = "no_error",
    [1] = "not_enough_output_space",
    [2] = "missing_input_item",
    [3] = "item_transfer_error",
    [4] = "",
    [5] = "missing_reactor_item",
    [6] = "mistach_depleted_reactor_item",
    [7] = "damaged_reactor_item",
    [8] = "reactor_overheat"
}

-- Display
local function info(no, msg)
    print(string.format("%2d> %s", no, msg))
end

local function err(no, msg)
    error(string.format("%2d> %s", no, msg))
end

-- Check reactor damage
local function check_reactor_damage(no)
    local reactor_box = reactor[no].transposer.getAllStacks(config[no].side_reactor).getAll()
    for i = 1, #reactor[no].pattern do
        local pattern = reactor[no].pattern[i]
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
local function update_reactor_item(no)
    -- Generate input box item lookup table
    local input_box = reactor[no].transposer.getAllStacks(config[no].side_input).getAll()
    local input_item_list = {}
    for i = 0, #input_box-1 do
        local input_box_slot = input_box[i]
        if input_box_slot.name then
            append(input_item_list, input_box_slot.name, i)
        end
    end

    local function try_output(slot)
        -- Transfer index start with 0
        return reactor[no].transposer.transferItem(
            config[no].side_reactor, config[no].side_output, 1, slot)
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
        return reactor[no].transposer.transferItem(
            config[no].side_input, config[no].side_reactor, 1, input_slot + 1, slot)
    end

    local reactor_box = reactor[no].transposer.getAllStacks(config[no].side_reactor).getAll()
    for i = 1, #reactor[no].pattern do
        local pattern = reactor[no].pattern[i]
        for j = 1, #pattern.slot do
            local reactor_slot = pattern.slot[j]
            local reactor_box_slot = reactor_box[reactor_slot - 1]  -- inventory index start with 0
            if reactor_box_slot.name == nil then
                try_input(pattern.name, reactor_slot)
            elseif reactor_box_slot.name ~= pattern.name then
                if try_output(reactor_slot) == 0 then
                    return 1  -- error code
                end
                try_input(pattern.name, reactor_slot)
            elseif pattern.damage ~= -1 and reactor_box_slot.damage >= pattern.damage then
                if try_output(reactor_slot) == 0 then
                    return 1  -- error code
                end
                try_input(pattern.name, reactor_slot)
            end
        end
    end

    -- Report missing item
    if not is_empty(missing_item_list) then
        for name, slot in pairs(missing_item_list) do
            info(no, string.format("Missing $dx\"%s\"", #slot, name))
        end
        return 2    -- error code
    end

    return 0
end

-- Reactor control
local function start_reactor(no)
    if reactor[no].reactor_chamber.getHeat() > reactor[no].pattern.overheat then
        return 8
    end
    reactor[no].reactor_chamber.setActive(true)
    info(no, "Reactor started.")
    return 0
end

local function stop_reactor(no)
    reactor[no].reactor_chamber.setActive(false)
    info(no, "Reactor stopped.")
    return 0
end

local function get_reactor_reading(no)
    reactor[no].producesEnergy = reactor[no].reactor_chamber.producesEnergy()
    reactor[no].EUOutput = reactor[no].reactor_chamber.getReactorEUOutput()
    reactor[no].heat = reactor[no].reactor_chamber.getHeat()
    reactor[no].maxHeat = reactor[no].reactor_chamber.getMaxHeat()
    reactor[no].heatPrec = reactor[no].heat / reactor[no].maxHeat
end

local function get_buffer_reading()
    -- Get battery level
    buffer.EUStored = 0
    buffer.EUmax = 0

    local machine_slot = buffer.machine_inv.getAllStacks()
    local differenceCharge = 0
    for i = 0, #machine_slot do
        if machine_slot[i] then
            buffer.EUStored = buffer.EUStored + machine_slot[i].charge
            buffer.EUmax = buffer.EUmax + machine_slot[i].maxCharge
        end
    end
    buffer.EUStored = buffer.EUStored + buffer.machine.getEUStored()
    buffer.EUmax = buffer.EUmax + buffer.machine.getEUMaxStored()
    buffer.EUPrec = buffer.EUStored / buffer.EUmax
    buffer.EUNetChange = buffer.machine.getAverageElectricityInput() - buffer.machine.getAverageElectricityOutput()
end

local function auto_start()
    for i = 1, #reactor do
        if config[i].allow_auto_start and reactor[i].state == 'OFF' then
            reactor[i].start_en = true
        end
    end
end

local function auto_stop()
    for i = 1, #reactor do
        if config[i].allow_auto_start and reactor[i].state == 'ON' then
            reactor[i].stop_en = true
        end
    end
end

local function watchdog_handler()
    for i = 1, #reactor do
        if not pcall(get_reactor_reading, i) then
            info(i, "WDT detected reactor abnormal.")
            reactor[i].stop_en = true
        end

        if reactor[i].heat >= reactor[i].pattern.overheat then
            info(i, "WDT detected reactor overheat.")
            reactor[i].stop_en = true
        end

        if reactor[i].state == "OFF" and reactor[i].producesEnergy then
            info(i, "WDT detected unexpected reactor activation.")
            reactor[i].stop_en = true
        end
    end

    if buffer.enable and pcall(get_buffer_reading) then
        if buffer.EUPrec < global_config.buffer_level then
            pcall(auto_start)
        else
            pcall(auto_stop)
        end
    end
end

local function print_header()
    term.setCursor(1, 1)
    term.write("--------+--------+--------+-----------------------\n")
    term.write("reactor |state   |heat%   |energy                 \n")
    term.write("--------+--------+--------+-----------------------\n")
    for i = 1, #reactor do
        term.write(string.format("%-8d|%-8s|%7.1f%%|%19dEU/t\n", i, reactor[i].state, reactor[i].heatPrec * 100, reactor[i].EUOutput))
    end
    term.write("--------+--------+--------+-----------------------\n")
    term.write(string.format("%15dEU|%7.1f%%|%19dEU/t\n", buffer.EUStored, buffer.EUPrec * 100, buffer.EUNetChange))
    term.write("-----------------+--------+----Kerel The Top UwU--\n")
end

local function status_handler()
    local cx, cy
    cx, cy = term.getCursor()
    print_header()
    term.setCursor(cx, cy)
    
    for i = 1, #reactor do
        reactor[i].rsio.setBundledOutput(config[i].side_rsio, config[i].color_start_en, ternary(reactor[i].state == "OFF", 15, 0))
        reactor[i].rsio.setBundledOutput(config[i].side_rsio, config[i].color_error, ternary(reactor[i].state == "ERROR", 15, 0))
        reactor[i].rsio.setBundledOutput(config[i].side_rsio, config[i].color_on, ternary(reactor[i].state == "ON", 15, 0))
        reactor[i].rsio.setBundledOutput(config[i].side_rsio, config[i].color_stop_en, ternary(reactor[i].state ~= "OFF", 15, 0))
    end
end

local exit_signal = false
local function key_down_handler(eventName, keyboardAddress, char, code, playerName)
    if code == 0x10 then
        for i = 1, #reactor do
            reactor[i].stop_en = true
        end
        exit_signal = true
    end
end

local function redstone_changed_handler(eventName, address, side, oldValue, newValue, color)
    for i = 1, #config do
        if address == config[i].addr_rsio then
            if side == config[i].side_rsio and color == config[i].color_stop_en and newValue > 15 then
                info(i, "Stop signal received.")
                reactor[i].stop_en = true
            end
            if side == config[i].side_rsio and color == config[i].color_start_en and newValue > 15 then
                if reactor[i].state == "OFF" then
                    info(i, "Start signal received.")
                    reactor[i].start_en = true
                end
            end
            break
        end
    end
end

-- Register event
local event_handler = {}
local function register_event()
    table.insert(event_handler, event.listen("key_down", key_down_handler))
    table.insert(event_handler, event.listen("redstone_changed", redstone_changed_handler))
    table.insert(event_handler, event.timer(global_config.watchdog_interval, watchdog_handler, math.huge))
    table.insert(event_handler, event.timer(global_config.status_interval, status_handler, math.huge))
end

local function unregister_event()
    for _, id in pairs(event_handler) do
        event.cancel(id)
    end
end

-- Reactor control FSM
local reactor_control_fsm = {
    OFF =
        function(no)
            if reactor[no].start_en then
                return "START"
            end
            return "OFF"
        end,
    START = 
        function(no)
            reactor[no].start_en = false
            info(no, "Updating reactor chamber items...")
            local ret = update_reactor_item(no)
            if ret ~= 0 then
                info(no, error_msg[ret])
                info(no, string.format("Retry in %d seconds...", global_config.error_retry_interval))
                reactor[no].error_time = os.time()
                return "ERROR"
            end
            ret = start_reactor(no)
            if ret ~= 0 then
                info(no, error_msg[ret])
                return "OFF"
            end
            return "ON"
        end,
    ON = 
        function(no)
            local ret = check_reactor_damage(no)
            if ret ~= 0 then
                info(no, error_msg[ret])
                stop_reactor(no)
                return "START"
            end
            return "ON"
        end,
    ERROR = 
        function(no)
            local elapsed_second = (os.time() - reactor[no].error_time)*0.014  -- convert to second
            if elapsed_second >= global_config.error_retry_interval then
                return "START"
            end
            return "ERROR"
        end
}

-- Component check
local function init_component(no)
    info(no, "Self-checking reactor...")
    
    reactor[no] = reactor_init()
    reactor[no].pattern = nr_pattern[config[no].pattern_name]
    if reactor[no].pattern == nil then
        err(no, "Invalid pattern name.")
    end

    reactor[no].rsio = component.proxy(config[no].addr_rsio)
    reactor[no].transposer = component.proxy(config[no].addr_transposer)
    reactor[no].reactor_chamber = component.proxy(config[no].addr_reactor_chamber)

    if reactor[no].rsio == nil then
        err(no, "Cannot access redstone I/O.")
    elseif reactor[no].rsio.getBundledInput(config[no].side_rsio, config[no].color_start_en) > 15 then
        info(no, "Start signal is high.")
    elseif reactor[no].rsio.getBundledInput(config[no].side_rsio, config[no].color_stop_en) > 15 then
        info(no, "SCRAM signal is high.")
    end

    if reactor[no].transposer == nil then
        err(no, "Cannot access transposer.")
    elseif reactor[no].transposer.getInventoryName(config[no].side_reactor) ~= "blockReactorChamber" then
        err(no, "Transposer cannot access reactor chamber.")
    elseif reactor[no].transposer.getInventoryName(config[no].side_input) == nil then
        err(no, "Transposer cannot access input inventory.")
    elseif reactor[no].transposer.getInventoryName(config[no].side_output) == nil then
        err(no, "Transposer cannot access output inventory.")
    end

    if reactor[no].reactor_chamber == nil then
        err(no, "Cannot access reactor chamber.")
    elseif reactor[no].reactor_chamber.producesEnergy() then
        info(no, "Reactor is running.")
        stop_reactor(no)
    end
    info(no, "Self-check passed.")
    return 0
end

local function init()
    for i = 1, #config do
        init_component(i)
    end

    buffer.machine = component.proxy(global_config.addr_buffer)
    buffer.machine_inv = component.proxy(global_config.addr_buffer_inv)
    if buffer.machine == nil then
        print("Cannot access battery machine, buffer disabled.")
        buffer.enable = false
    elseif buffer.machine_inv == nil then
        print("Cannot access battery machine inventory, buffer disabled.")
        buffer.enable = false
    elseif buffer.machine_inv.getInventoryName(global_config.side_buffer) == nil then
        print("Cannot access battery machine inventory, buffer disabled.")
        buffer.enable = false
    else
        print("Battery machine detected, buffer enabled.")
        buffer.enable = true
    end
end

local function light_control(level)
    for i = 1, #reactor do
        reactor[i].rsio.setBundledOutput(config[i].side_rsio, config[i].color_start_en, level)
        reactor[i].rsio.setBundledOutput(config[i].side_rsio, config[i].color_error, level)
        reactor[i].rsio.setBundledOutput(config[i].side_rsio, config[i].color_on, level)
        reactor[i].rsio.setBundledOutput(config[i].side_rsio, config[i].color_stop_en, level)
    end
end

-- Main control logic for vaccum nuclear reactor
-- Handles potential error caused by component disconnection
local function main()
    print("Starting...")
    init()

    register_event()
    pcall(light_control, 15)
    os.execute("cls")
    print_header()

    while not exit_signal do
        local status = false
        for i = 1, #reactor do
            status, ret = pcall(reactor_control_fsm[reactor[i].state], i)
            if not status then
                info(i, ret)
                info(i, "Unexpected error. Please check nuclear reactor.")
                reactor[i].stop_en = true
            else
                reactor[i].state = ret
            end
            if reactor[i].stop_en then  -- if stop_en is set by the watchdog
                pcall(stop_reactor, i)
                reactor[i].stop_en = false  -- clear stop_en signal
                reactor[i].start_en = false -- clear start signal
                reactor[i].state = "OFF"
            end
        end
        os.sleep(0.2)
    end

    print("Exiting...")
    unregister_event()
    pcall(light_control, 0)
end

main()
