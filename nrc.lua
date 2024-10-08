local computer = require("computer")
local component = require("component")
local event = require("event")
local os = require("os")
local term = require("term")
local colors = require("colors")
local sides = require("sides")
local nr_pattern = require("nr_pattern")
local config = require("config")

-- Reactor configuration
local global_cfg = config.global_config
local reactor_cfg = config.reactor_config

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
    obj = nil,
    inv = nil,
    
    enable = false,
    auto_start = false,
    EUStored = 0,
    EUmax = 100,
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
    local reactor_box = reactor[no].transposer.getAllStacks(reactor_cfg[no].side_reactor).getAll()
    for i = 1, #reactor[no].pattern.resource do
        local resource = reactor[no].pattern.resource[i]
        for j = 1, #resource.slot do
            local reactor_box_slot = reactor_box[resource.slot[j] - 1]
            if reactor_box_slot.name == nil then
                return 5
            elseif reactor_box_slot.name ~= resource.name then
                return 6
            elseif resource.damage ~= -1 and reactor_box_slot.damage >= resource.damage then
                return 7
            end
        end
    end
    return 0
end

-- Update reactor chamber items
local function update_reactor_item(no)
    -- Generate input box item lookup table
    local input_box = reactor[no].transposer.getAllStacks(reactor_cfg[no].side_input).getAll()
    local input_item_list = {}
    for i = 0, #input_box do
        local input_box_slot = input_box[i]
        if input_box_slot.name then
            append(input_item_list, input_box_slot.name, i)
        end
    end

    local missing_item_list = {}
    local reactor_box = reactor[no].transposer.getAllStacks(reactor_cfg[no].side_reactor).getAll()
    for i = 1, #reactor[no].pattern.resource do
        local resource = reactor[no].pattern.resource[i]
        for j = 1, #resource.slot do
            local reactor_slot = resource.slot[j]
            local reactor_box_slot = reactor_box[reactor_slot - 1]  -- inventory index start with 0
            local need_output = false
            local need_input = false
            if reactor_box_slot.name == nil then
                need_input = true
            elseif reactor_box_slot.name ~= resource.name then
                need_output = true
                need_input = true
            elseif resource.damage ~= -1 and reactor_box_slot.damage >= resource.damage then
                need_output = true
                need_input = true
            end

            -- Transfer
            local transfer_ret = 0
            if need_output then
                -- Transfer output
                transfer_ret = reactor[no].transposer.transferItem(
                    reactor_cfg[no].side_reactor, reactor_cfg[no].side_output, 1, reactor_slot)
                if transfer_ret == 0 then
                    return 1  -- error code
                end
            end
            if need_input then
                -- Get input item slot
                local input_slot = -1
                if input_item_list[resource.name] ~= nil then
                    local item_list_slot = input_item_list[resource.name]
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
                        input_item_list[resource.name] = nil
                    end
                end

                if input_slot == -1 then
                    append(missing_item_list, resource.name, reactor_slot)
                else
                    -- Transfer input
                    transfer_ret = reactor[no].transposer.transferItem(
                        reactor_cfg[no].side_input, reactor_cfg[no].side_reactor, 1, input_slot + 1, reactor_slot)
                    if transfer_ret == 0 then
                       return 3  -- error code
                    end
                end
            end
        end
    end

    -- Report missing item
    if not is_empty(missing_item_list) then
        for name, slot in pairs(missing_item_list) do
            info(no, string.format("Missing %dx\"%s\"", #slot, name))
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

    local machine_slot = buffer.inv.getAllStacks(global_cfg.side_buffer).getAll()
    for i = 0, #machine_slot do
        if machine_slot[i].charge then
            buffer.EUStored = buffer.EUStored + machine_slot[i].charge
            buffer.EUmax = buffer.EUmax + machine_slot[i].maxCharge
        end
    end
    buffer.EUStored = buffer.EUStored + buffer.obj.getEUStored()
    buffer.EUmax = buffer.EUmax + buffer.obj.getEUMaxStored()
    buffer.EUPrec = buffer.EUStored / buffer.EUmax
    buffer.EUNetChange = buffer.obj.getAverageElectricInput() - buffer.obj.getAverageElectricOutput()
end

local function auto_start()
    for i = 1, #reactor do
        if reactor_cfg[i].allow_auto_start and reactor[i].state == 'OFF' then
            info(i, "Auto starting...")
            reactor[i].start_en = true
        end
    end
end

local function auto_stop()
    for i = 1, #reactor do
        if reactor_cfg[i].allow_auto_start and reactor[i].state == 'ON' then
            info(i, "Auto stopping...")
            reactor[i].stop_en = true
        end
    end
end

local function watchdog_handler()
    for i = 1, #reactor do
        if not pcall(get_reactor_reading, i) then
            info(i, "WDT detected reactor abnormal.")
        end

        if reactor[i].state == "ON" and reactor[i].heat >= reactor[i].pattern.overheat then
            info(i, "WDT detected reactor overheat.")
            reactor[i].stop_en = true
        end

        if reactor[i].state == "OFF" and reactor[i].producesEnergy then
            info(i, "WDT detected unexpected reactor activation.")
            reactor[i].stop_en = true
        end
    end

    if buffer.enable and pcall(get_buffer_reading) then
        if buffer.auto_start then
            if buffer.EUPrec < global_cfg.buffer_on_level then
                pcall(auto_start)
            elseif buffer.EUPrec > global_cfg.buffer_off_level then
                pcall(auto_stop)
            end
        end
    end
end

local function print_header()
    term.setCursor(1, 1)
    term.write("reactor |state   |heat/EU%|energy                 \n", false)
    term.write("--------+--------+--------+-----------------------\n", false)
    for i = 1, #reactor do
        term.write(string.format("%-8d|%8s|%7.1f%%|%19.fEU/t\n", i, reactor[i].state, reactor[i].heatPrec * 100, reactor[i].EUOutput), false)
    end
    term.write("--------+--------+--------+-----------------------\n", false)
    
    local buffer_state
    if buffer.enable then
        if buffer.auto_start then
            buffer_state = "AUTO"
        else
            buffer_state = "MANUAL"
        end
    else
        buffer_state = "DISABLE"
    end
    term.write(string.format("%-8s|%8s|%7.1f%%|%10.fk|%9.fk/t\n", "buffer", buffer_state, buffer.EUPrec*100, buffer.EUStored/1e3, buffer.EUNetChange/1e3), false)
    term.write("--------+--------+--------+---Kerel The Top UwU---\n", false)
end

local function status_handler()
    local cx, cy
    cx, cy = term.getCursor()
    print_header()
    term.setCursor(cx, cy)
    
    for i = 1, #reactor do
        reactor[i].rsio.setBundledOutput(reactor_cfg[i].side_rsio, reactor_cfg[i].color_start_en, ternary(reactor[i].state == "OFF", 15, 0))
        reactor[i].rsio.setBundledOutput(reactor_cfg[i].side_rsio, reactor_cfg[i].color_error, ternary(reactor[i].state == "ERROR", 15, 0))
        reactor[i].rsio.setBundledOutput(reactor_cfg[i].side_rsio, reactor_cfg[i].color_on, ternary(reactor[i].state == "ON", 15, 0))
        reactor[i].rsio.setBundledOutput(reactor_cfg[i].side_rsio, reactor_cfg[i].color_stop_en, ternary(reactor[i].state ~= "OFF", 15, 0))
    end
end

local exit_signal = false
local function key_down_handler(eventName, keyboardAddress, char, code, playerName)
    if code == 0x10 then
        for i = 1, #reactor do
            reactor[i].stop_en = true
        end
        exit_signal = true
    elseif code == 0x20 then
        buffer.auto_start = not buffer.auto_start
        if buffer.auto_start then
            info(0, "Auto control enabled.")
        else
            info(0, "Auto control disabled.")
        end
    end
end

local function redstone_changed_handler(eventName, address, side, oldValue, newValue, color)
    for i = 1, #reactor do
        if address == reactor_cfg[i].addr_rsio and side == reactor_cfg[i].side_rsio then
            if color == reactor_cfg[i].color_stop_en and newValue > 15 then
                info(i, "Stop signal received.")
                reactor[i].stop_en = true
            elseif color == reactor_cfg[i].color_start_en and newValue > 15 then
                if reactor[i].state == "OFF" then
                    info(i, "Start signal received.")
                    reactor[i].start_en = true
                end
            end
        end
    end
end

-- Register event
local event_handler = {}
local function register_event()
    table.insert(event_handler, event.listen("key_down", key_down_handler))
    table.insert(event_handler, event.listen("redstone_changed", redstone_changed_handler))
--    table.insert(event_handler, event.timer(global_cfg.watchdog_interval, watchdog_handler, math.huge))
--    table.insert(event_handler, event.timer(global_cfg.status_interval, status_handler, math.huge))
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
                info(no, string.format("Retry in %d seconds...", global_cfg.error_retry_interval))
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
            local elapsed_second = (os.time() - reactor[no].error_time) * 0.014  -- convert to second
            if elapsed_second >= global_cfg.error_retry_interval then
                return "START"
            end
            return "ERROR"
        end
}

-- Component check
local function init_component(no)
    info(no, "Self-checking reactor...")
    
    reactor[no] = reactor_init()
    reactor[no].pattern = nr_pattern[reactor_cfg[no].pattern_name]
    if reactor[no].pattern == nil then
        err(no, "Invalid pattern name.")
    end

    reactor[no].rsio = component.proxy(reactor_cfg[no].addr_rsio)
    reactor[no].transposer = component.proxy(reactor_cfg[no].addr_transposer)
    reactor[no].reactor_chamber = component.proxy(reactor_cfg[no].addr_reactor_chamber)

    if reactor[no].rsio == nil then
        err(no, "Cannot access redstone I/O.")
    elseif reactor[no].rsio.getBundledInput(reactor_cfg[no].side_rsio, reactor_cfg[no].color_start_en) > 15 then
        info(no, "Start signal is high.")
    elseif reactor[no].rsio.getBundledInput(reactor_cfg[no].side_rsio, reactor_cfg[no].color_stop_en) > 15 then
        info(no, "SCRAM signal is high.")
    end

    if reactor[no].transposer == nil then
        err(no, "Cannot access transposer.")
    elseif reactor[no].transposer.getInventoryName(reactor_cfg[no].side_reactor) ~= "blockReactorChamber" then
        err(no, "Transposer cannot access reactor chamber.")
    elseif reactor[no].transposer.getInventoryName(reactor_cfg[no].side_input) == nil then
        err(no, "Transposer cannot access input inventory.")
    elseif reactor[no].transposer.getInventoryName(reactor_cfg[no].side_output) == nil then
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
    for i = 1, #reactor_cfg do
        init_component(i)
    end

    buffer.obj = component.proxy(global_cfg.addr_buffer)
    buffer.inv = component.proxy(global_cfg.addr_buffer_inv)
    if buffer.obj == nil then
        print("Cannot access battery buffer, buffer disabled.")
        buffer.enable = false
    elseif buffer.inv == nil then
        print("Cannot access battery buffer inventory, buffer disabled.")
        buffer.enable = false
    elseif buffer.inv.getInventoryName(global_cfg.side_buffer) == nil then
        print("Cannot access battery buffer inventory, buffer disabled.")
        buffer.enable = false
    else
        print("Battery buffer detected, auto control can be enabled.")
        buffer.auto_start = false
        buffer.enable = true
    end
end

local function light_control(level)
    for i = 1, #reactor do
        reactor[i].rsio.setBundledOutput(reactor_cfg[i].side_rsio, reactor_cfg[i].color_start_en, level)
        reactor[i].rsio.setBundledOutput(reactor_cfg[i].side_rsio, reactor_cfg[i].color_error, level)
        reactor[i].rsio.setBundledOutput(reactor_cfg[i].side_rsio, reactor_cfg[i].color_on, level)
        reactor[i].rsio.setBundledOutput(reactor_cfg[i].side_rsio, reactor_cfg[i].color_stop_en, level)
    end
end

-- Main control logic for vaccum nuclear reactor
-- Handles potential error caused by component disconnection
local function main()
    print("Starting...")
    init()

    pcall(light_control, 15)
    os.execute("cls")
    print_header()

    register_event()

    while not exit_signal do
        watchdog_handler()  -- call directly
        status_handler()  -- call directly

        for i = 1, #reactor do
            local status, ret = pcall(reactor_control_fsm[reactor[i].state], i)
            if not status then
                info(i, ret)
                info(i, "Unexpected error. Please check reactor.")
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
        os.sleep(0.1)
    end

    for i = 1, #reactor do
        pcall(stop_reactor, i)
    end

    print("Exiting...")
    unregister_event()
    pcall(light_control, 0)
end

main()
