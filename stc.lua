local computer = require("computer")
local component = require("component")
local os = require("os")
local sides = require("sides")

local solar_tower = component.gt_machine
local transposer = nil

function transfer_coolant(amount)
end

function parse(sensor_info)
    return {}
end

function main()
    if solar_tower == nil then
        print("Solar tower not found.")
        return
    end

    while true do
        local raw_info = solar_tower.getSensorInformation()
        info = parse(raw_info)

        -- coolant transfer when internal heat is higher than 50000
        if info.heat > 50000 then
            transfer_coolant(info.heat - 50000)
        end
    end
end

main()