local computer = require("computer")
local component = require("component")
local os = require("os")
local event = require("event")
local string = require("string")
local sides = require("sides")
local term = require("term")

local solar_tower = component.gt_machine
local transposer = component.transposer
local coolant_tank_side = sides.east
local input_side = sides.bottom

local coolant_name = "molten.solarsaltcold"
local heat_threshold = 50000
local heat = 0
local update_interval = 10

-- print
local function print_header()
    term.setCursor(1, 1)
    term.write("--------------------------------------------------\n", false)
    term.write(string.format("HEAT : %8d                                   \n", heat), false)
    term.write("------------------------------Kerel The Top UwU---\n", false)
    term.write("                                                  \n", false)
    term.write("                                                  \n", false)
    term.setCursor(1, 4)
end

-- control
local exit_signal = false
local function key_down_handler(eventName, keyboardAddress, char, code, playerName)
    if code == 0x10 then
        exit_signal = true
    end
end

-- event control
local event_handler = {}
local function register_event()
    table.insert(event_handler, event.listen("key_down", key_down_handler))
end

local function unregister_event()
    for _, id in pairs(event_handler) do
        event.cancel(id)
    end
end

-- transfer coolant from tank to fluid input hatch
function transfer_coolant(amount)
    local fluid_info = transposer.getFluidInTank(coolant_tank_side)[1]
    -- example fluid information
    -- {{amount=1000, capacity=64000, hasTag=false, label="Solar Salt (Cold)", name="molten.solarsaltcold"}}
    if fluid_info.name ~= coolant_name then
        print(string.format("Wrong fluid type, expected '%s' but detected '%s'.", coolant_name, fluid_info.name))
        return 0
    end

    if fluid_info.amount < amount then
        print("Insufficient coolant.")
    end

    local status, xfer_amount = transposer.transferFluid(coolant_tank_side, input_side, amount)
    if status then
        print(string.format("Transfer %d.", xfer_amount))
        return xfer_amount
    end
    return 0
end

-- example sensor information of solar tower
-- {"solartower.controller.tier.single", "Internal Heat Level: 100000", ...}
-- return heat
function parse_heat(sensor_info)
    return tonumber(string.sub(sensor_info[2], 22))
end

function main()
    register_event()
    while not exit_signal do
        local status, ret = pcall(solar_tower.getSensorInformation)
        if not status then
            print("Unable to obtain solar tower sensor information.")
        else
            heat = parse_heat(ret)
            print_header()
            -- coolant transfer when internal heat is higher than heat_threshold
            if heat > heat_threshold then
                transfer_coolant(heat - heat_threshold)
            end
        end
        -- sleep to reduce resource usage
        os.sleep(update_interval)
    end
    unregister_event()
    os.execute("cls")
end

main()