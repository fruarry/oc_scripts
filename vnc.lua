local address_rsio_ext_control
local rsio_nuclear_control

local computer = require('computer')
local component = require('component')


local redstone1 = component.proxy("XXXXX") -- 1号红石io为控制反应堆
local redstone2 = component.proxy("XXXXX") -- 2号红石io为控制全局开关

-- 北:2
-- 东:5
-- 西:4
-- 南:3
local sourceBoxSide = 4 -- 输入箱子
local reactorChamberSide = 5 -- 核电仓
local outPutBoxSide = 3 -- 输出箱子
local outPutDrawerSide = 0 -- 输出抽屉
local runTime = 0 -- 正常运行时间
local controlside = 2  --控制红石接收器方向

-- 检查原材料箱中原材料数量
local function checkSourceBoxItems(itemName, itemCount)
    local itemSum = 0
    local sourceBoxitemList = transposer.getAllStacks(sourceBoxSide).getAll()

    for index, item in pairs(sourceBoxitemList) do
        if item.name then
            if item.name == itemName then
                itemSum = itemSum + item.size
            end
        end
    end

    if itemSum >= itemCount then
        return true
    else
        return false
    end
end

-- 停止核电仓
local function stop()
    redstone1.setOutput(reactorChamberSide, 0)
end

--启动核电仓
local function start()
    redstone1.setOutput(reactorChamberSide, 1)
end


-- 向核电仓中转移原材料
local function insertItemsIntoReactorChamber(project)
    local sourceBoxitemList = transposer.getAllStacks(sourceBoxSide).getAll()
    local reactorChamber = transposer.getAllStacks(reactorChamberSide)
    local reactorChamberLenth = reactorChamber.count()
    local projectLenth = #project

    for i = 1, projectLenth do
        for indexJ, j in pairs(project[i].slot) do
            for index, item in pairs(sourceBoxitemList) do
                if item.name == project[i].name then
                    transposer.transferItem(sourceBoxSide, reactorChamberSide, 1, index + 1, j)
                end
            end
        end
    end
end

-- 物品移除核电仓
local function remove(removeSlot, removeSide)
    while true do
        if transposer.transferItem(reactorChamberSide, removeSide, 1, removeSlot) == 0 then
            print("outPutBox is Full!")
            for i = 10, 1, -1 do
                print("Recheck after " .. i .. " seconds")
                os.sleep(1)
            end
            os.execute("cls")
        else
            break
        end
    end
end

-- 物品移入核电仓
local function insert(sinkSlot, insertItemName)
    while true do
        local sourceBoxitemList = transposer.getAllStacks(sourceBoxSide).getAll()
        if checkSourceBoxItems(insertItemName, 1) then
            for index, item in pairs(sourceBoxitemList) do
                if item.name == insertItemName then
                    transposer.transferItem(sourceBoxSide, reactorChamberSide, 1, index + 1, sinkSlot)
                    break
                end
            end
            break
        else
            print(insertItemName .. "-------is not enough")
            for i = 10, 1, -1 do
                print("Recheck after " .. i .. " seconds")
                os.sleep(1)
            end
            os.execute("cls")
        end
    end
end

-- 物品移除和移入核电仓
local function removeAndInsert(removeSlot, removeSide, insertItemName)
    stop()
    remove(removeSlot, removeSide)
    insert(removeSlot, insertItemName)
end

-- 物品监测（需要监测DMG和不需要监测DMG）
local function checkItemDMG(project)
    local reactorChamber = transposer.getAllStacks(reactorChamberSide)
    local reactorChamberLenth = reactorChamber.count()
    local reactorChamberList = reactorChamber.getAll()

    for i = 1, #project do
        for index, slot in pairs(project[i].slot) do
            if project[i].dmg ~= -1 then
                if reactorChamberList[slot - 1].damage ~= nil then
                    if reactorChamberList[slot - 1].damage >= project[i].dmg then
                        removeAndInsert(slot, outPutBoxSide, project[i].name)
                    end
                else
                    stop()
                    insert(slot, project[i].name)
                end

            elseif project[i].dmg == -1 then
                if reactorChamberList[slot - 1].name ~= nil then
                    if reactorChamberList[slot - 1].name ~= project[i].name and
                        reactorChamberList[slot - 1].name == project[i].changeName then
                        removeAndInsert(slot, outPutDrawerSide, project[i].name)
                    end
                else
                    stop()
                    insert(slot, project[i].name)
                end
            end
        end
    end
end

-- Reactor configuration
config = {
	resource = {
		{
			name = "gregtech:gt.360k_Helium_Coolantcell",
			changeName = -1,
			dmg = 90,
			count = 14,
			slot = { 3, 6, 9, 10, 15, 22, 26, 29, 33, 40, 45, 46, 49, 52 }
		},
		{
			name = "gregtech:gt.reactorUraniumQuad",
			changeName = "IC2:reactorUraniumQuaddepleted",
			dmg = -1,
			count = 40,
			slot = {
				1, 2, 4, 5, 7, 8, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 23, 24, 25, 27, 28, 30, 31, 32, 34, 35, 36, 37,
				38, 39, 41, 42, 43, 44, 47, 48, 50, 51, 53, 54 }
		}
	},
 	overheat_threshold = 9000
}

-- Component list
local rsio_ext_control = component.proxy(address_rsio_ext_control)
local rsio_nuclear_control = component.proxy(address_rsio_nuclear_control)
local transposer = component.transposer
local reactor_chamber = component.reactor_chamber

-- Component function
local function checkReactorItem()
	local discard_list,  = {}
	local report_idx = 0
	for i = 1, #config.resource do
		slots = config.resource[i]
		for s = 1, #slots do
			report_idx += 1
			report[report_idx]
	end
end

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

local function redstoneOutputAll(rsio, level)
	if type(level) ~= "number" then
		level = 1
	end
	local output = {}
	for i = 0, 5 do
		output[i] = level
	end
	rsio.setOutput(output)
end

-- Display help info
local function display_info()
	os.execute("cls")
	print("==========================")
	print("  Vaccum Nuclear Reactor")
	print("  Version:     1.0")
	print("  Author:      Kerel")
	print("==========================")
end

-- Register keyboard control
local function register_listener()
end

local function unregister_listener()
end

-- Nuclear reactor control signal structure
local control_signal = {
	-- scram
	start_success = false,
	heat = 0,
}

local function update_control_signal()
	control_signal.heat = reactor_chamber.getHeat()
end

-- Nuclear control FSM
local reactor_control_fsm = {
	init_state =
		function()
			return "off_state"
		end,
	off_state =
		function()
			if control_signal.start then
				return "start_state"
			else
				return "off_state"
			end
		end,
	start_state = 
		function()
			if control_signal.start_success then
				return "on_state"
			else
				return "failure_state"
			end
		end,
	on_state = 
		function()
		
		end,
	failure_state = 0,
	change_coolant_state = 
		function()
		end,
	change_fuel_state = 
		function()
		end,
	
}
local reactor_control_action = {
	init_state = 
		function()
		end,
	start_state = 
		function()
			checkReactorItem()
			checkInputItem()
			insertItem()
			if COND then
				control_signal.start_success = true
			else
				control_signal.start_success = false
			end
		end,
	on_state = 
		function()
			checkReactorItem()
			
}

-- Main control logic for vaccum nuclear reactor
local function main()
	display_info()
	register_listener()
	
	local current_state = "init_state"
    while true do
		update_control_signal()
		next_state = reactor_control_fsm[current_state]()
		reactor_control_action[current_state]()
		current_state = next_state
		os.sleep(0.05)
	end
	unregister_listener()
end

main()
