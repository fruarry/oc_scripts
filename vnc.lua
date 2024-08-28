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
 	overheat_threshold = 9000,
	transposer_side_reactor = xx,
}

-- Component list
local rsio_ext_control = component.proxy(address_rsio_ext_control)
local transposer = component.proxy(address_transposer)
local reactor_chamber = component.proxy(address_reactor_chamber)

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
		resourcce = config.resource[i]
		for s = 1, #resource.slot do
			slot = resource.slot[s]
			target = transposer.getStackInSlot(config.transposer_side_reactor, slot)
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
local function updateReactorItem()
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

-- Reactor structure
local reactor_state = {
	-- scram
	ext_start = false,
	start_success = false,
	heat = 0,

	item_update = false,
	item_export = {},
	item_import = {},
}

local function update_reactor_state()
	-- Check external control
	reactor_state.ext_start = redstoneInputAny(rsio_ext_control)
	
	-- Check heaet
	reactor_state.heat = reactor_chamber.getHeat()

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
			if reactor_state.start_success then
				return "on_state"
			else
				return "failure_state"
			end
		end,
	on_state = 
		function()
		
		end,
	failure_state = 0,
}
local reactor_control_action = {
	init_state = 
		function()
		end,
	start_state = 
		function()
			if reactor_state.item_update then
				update_ret = updateReactorItem()
				if update_ret then
					startReactor()
					reactor_state.start_success = true
				else
					reactor_state.start_success = false
			end
		end,
	on_state = 
		function()
		end,
			
}

-- Main control logic for vaccum nuclear reactor
local function main()
	display_info()
	register_listener()
	
	local current_state = "init_state"
    while true do
		update_reactor_state()
		reactor_control_action[current_state]()
		next_state = reactor_control_fsm[current_state]()
		current_state = next_state
		os.sleep(0.5)
	end
	unregister_listener()
end

main()
