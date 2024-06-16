local NAME = ...
local options

-- compat
local GetContainerItemInfo = C_Container.GetContainerItemInfo or GetContainerItemInfo
local GetContainerNumSlots = C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetItemInfo = C_Item.GetItemInfo or GetItemInfo

-- item price/level

local function tip_price(tooltip)
	if tooltip:IsForbidden() then
		return
	end
	local _, link = tooltip:GetItem()
	if not link then
		return
	end
	-- name, link, quality, level, min-level, type, subtype, stackcount, equiploc, texture, price
	local _, _, _, level, _, _, _, _, equip, _, price = GetItemInfo(link)

	local show_price = price and options.price          and price > 0 and not tooltip.shownMoneyFrames
	local show_level = level and options.level ~= false and level > 1 and equip

	if show_price then
		local container = GetMouseFocus()
		if not container then
			return
		end
		local object = container:GetObjectType()
		local count = 1
		if object == "Button" then
			count = container.count
		elseif object == "CheckButton" then
			count = container.count or tonumber(container.Count:GetText())
		end
		tooltip:AddDoubleLine(GetMoneyString((count or 1) * price), show_level and "Lv(" .. level .. ")" or "")
	elseif show_level ~= false then
		tooltip:AddLine(format(ITEM_LEVEL, level))
	end
end

-- selljunk

local selljunk = { }
function selljunk.flush(sell)
	if sell.price > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cff17a2b8获得|r: " .. GetMoneyString(sell.price))
	end
	sell.price = nil -- clear
end
function selljunk.next()
	local sell = selljunk
	local state = sell.state
	local bag, slot, snum = unpack(state)
	if slot > snum then
		bag = bag + 1
		slot = 1
		snum = GetContainerNumSlots(bag)
		if snum == 0 then
			sell.flush(sell)
			return
		end
		state[1] = bag
		state[2] = slot
		state[3] = snum
	end
	sell.routine(sell, bag, slot)
	state[2] = slot + 1
	if sell.price then
		C_Timer.After(0.02, selljunk.next)
	end
end
function selljunk.routine(sell, bag, slot)
	local info = GetContainerItemInfo(bag, slot)
	if not info or info.isLocked or info.quality > 0 then
		return
	end
	local name, _, _, _, _, _, _, _, _, _, price = GetItemInfo(info.itemID)
	if not price or price == 0 or not MerchantFrame:IsShown() then
		return
	end
	C_Container.UseContainerItem(bag, slot)
	sell.price = sell.price + price * info.stackCount
	DEFAULT_CHAT_FRAME:AddMessage("|cffbfffff卖出|r: [" .. name .. "]")
end
function selljunk.begin(sell)
	if sell.price then
		sell.flush(sell) -- prevent deadlocks
		return
	end
	sell.price = 0
	sell.state = {0, 1, GetContainerNumSlots(0)}
	sell.next() -- TODO : switch to coroutine.yield ?
end
function selljunk.init()
	local button = CreateFrame("Button", nil, MerchantBuyBackItem)
	button:SetSize(32, 32)
	button:SetPoint("TOPRIGHT", MerchantFrame, -8, -26)
	local backdrop = button:CreateTexture(nil, "BACKGROUND")
	backdrop:SetAllPoints()
	backdrop:SetTexture("Interface/Icons/inv_misc_coin_06")

	button:SetPushedTexture("Interface/Buttons/UI-Quickslot-Depress");
	button:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")

	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("点击卖出背包内的垃圾物品")
		-- SetCursor("TODO")/ResetCursor()
	end)
	button:SetScript("OnMouseUp", function(_, _, inside)
		if not inside then
			return
		end
		selljunk:begin()
	end)
	selljunk.owner = button
end
function selljunk.destory()
	local button = selljunk.owner
	if not button then
		return
	end
	selljunk.owner = nil
	button:SetParent(nil)
	button:SetScript("OnLeave", nil)
	button:SetScript("OnEnter", nil)
	button:SetScript("OnMouseUp", nil)
end

-- cheapest (Stolen from https://github.com/ketho-wow/FlashCheapestGrey)

local cheapest = {}
function cheapest.light(bag, slot)
	local item
	for i = 1, NUM_CONTAINER_FRAMES, 1 do
		local frame = _G["ContainerFrame"..i]
		if frame:GetID() == bagId and frame:IsShown() then
			item = _G["ContainerFrame"..i.."Item"..(GetContainerNumSlots(bagId) + 1 - slot)]
		end
	end
	if item then
		item.NewItemTexture:SetAtlas("bags-glow-orange")
		item.NewItemTexture:Show()
		item.flashAnim:Play()
		item.newitemglowAnim:Play()
	end
end
function cheapest.mark(key, state)
	if not (key =="LCTRL" and state == 1) then
		return
	end
	local max = 0
	local x
	local y
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local info = GetContainerItemInfo(bag, slot)
			if info then
				local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(info.itemID)
				local sum = quality == 0 and price > 0 and price * info.stackCount or 0
				if sum > max then
					max = sum
					x = bag
					y = slot
				end
			end
		end
	end
	if x and IsBagOpen(x) then
		cheapest.light(x, y)
	end
end

-- fastloot (Stolen from https://github.com/Xarano-GIT/Faster-Loot)

local fastloot = {
	epoch = 0.,
	DELAY = 0.3,
	run = function(s)
		if GetTime() - fastloot.epoch < fastloot.DELAY then
			return
		end
		print("fastloot : " .. tostring(GetNumLootItems()))
		for i = GetNumLootItems(), 1, -1 do
			LootSlot(i)
		end
		fastloot.epoch = GetTime()
	end
}

-- global
local frame = CreateFrame("Frame")

local function opt_changed(_, setting, value)
	local key = setting:GetVariable()
	options[key] = value

	if key == "selljunk" then
		selljunk.destory()
		if value then
			selljunk.init()
		end
	elseif key == "cheapest" then
		frame:UnregisterEvent("MODIFIER_STATE_CHANGED")
		if value then
			frame:RegisterEvent("MODIFIER_STATE_CHANGED")
		end
	elseif key == "fastloot" then
		frame:UnregisterEvent("LOOT_READY")
		if value then
			frame:RegisterEvent("LOOT_READY")
		end
	end
end

local function init(frame)
	-- item price and level
	-- TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, tip_price)
	GameTooltip:HookScript("OnTooltipSetItem", tip_price)
	ItemRefTooltip:HookScript("OnTooltipSetItem", tip_price)
	-- options
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory(GetAddOnMetadata(NAME, "Title"))
	local booltype = type(true)
	do -- item level
		local key = "level"
		local desc = "在鼠标提示中显示物品等级"
		local label = "显示物品等级"
		local value = options[key] or (options[key] == nil and true)
		local setting = Settings.RegisterAddOnSetting(category, label, key, booltype, value)
		Settings.CreateCheckBox(category, setting, desc)
		Settings.SetOnValueChangedCallback(key, opt_changed)
	end
	do -- item price
		-- local has = Auctionator and Auctionator.Config.Get(Auctionator.Config.Options.VENDOR_TOOLTIPS)
		local key = "price"
		local desc = "在鼠标提示中显示物品价格"
		local label = "显示物品价格"
		local value = options[key] or false
		local setting = Settings.RegisterAddOnSetting(category, label, key, booltype, value)
		Settings.CreateCheckBox(category, setting, desc)
		Settings.SetOnValueChangedCallback(key, opt_changed)
	end
	do -- selljunk
		local key = "selljunk"
		local desc = "在商人对话框的右上角添加一个垃圾出售按钮"
		local label = "添加垃圾出售按钮"
		local value = options[key] or (options[key] == nil and true)
		local setting = Settings.RegisterAddOnSetting(category, label, key, booltype, value)
		Settings.CreateCheckBox(category, setting, desc)
		Settings.SetOnValueChangedCallback(key, opt_changed)
		if value then
			selljunk.init()
		end
	end
	do -- cheapest
		local key = "cheapest"
		local desc = "按下 Ctrl 时高亮背包内最便宜的垃圾物品"
		local label = "高亮最便宜的垃圾"
		local value = options[key] or (options[key] == nil and true)
		local setting = Settings.RegisterAddOnSetting(category, label, key, booltype, value)
		Settings.CreateCheckBox(category, setting, desc)
		Settings.SetOnValueChangedCallback(key, opt_changed)
		if value then
			frame:RegisterEvent("MODIFIER_STATE_CHANGED")
		end
	end
	do -- fastloot
		local key = "fastloot"
		local desc = "快速拾取"
		local label = "快速拾取"
		local value = options[key] or false
		local setting = Settings.RegisterAddOnSetting(category, label, key, booltype, value)
		Settings.CreateCheckBox(category, setting, desc)
		Settings.SetOnValueChangedCallback(key, opt_changed)
		if value then
			frame:RegisterEvent("LOOT_READY")
		end
	end
	Settings.RegisterAddOnCategory(category)
end

local function onevent(self, event, arg1, arg2)
	if event == "LOOT_READY" then
		fastloot.run(arg1)
	if event == "MODIFIER_STATE_CHANGED" then
		cheapest.mark(arg1, arg2)
	end
end

local function main()
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:SetScript("OnEvent", function(self)
		if not tinyhub_options then
			tinyhub_options = {}
		end
		options = tinyhub_options
		init(self)
		self:SetScript("OnEvent", onevent)
	end)
end

local _ = main()
