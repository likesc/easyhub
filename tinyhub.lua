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
	if not sell.price then
		return
	end
	local state = sell.state
	local bag, slot, snum = unpack(state)
	while true do
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
		if sell:routine(bag, slot) then
			state[2] = slot + 1
			C_Timer.After(0.02, selljunk.next)
			return
		end
		slot = slot + 1
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
	return true
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
		if frame:GetID() == bag and frame:IsShown() then
			item = _G["ContainerFrame"..i.."Item"..(GetContainerNumSlots(bag) + 1 - slot)]
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
	local min = 2147483647 -- 0x7fffffff
	local x
	local y
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local info = GetContainerItemInfo(bag, slot)
			if info then
				local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(info.itemID)
				if quality == 0 and price > 0 then
					local sum = price * info.stackCount
					if min > sum then
						min = sum
						x = bag
						y = slot
					end
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
}
function fastloot.run(self, checked)
	local now = GetTime()
	if checked == IsModifiedClick("AUTOLOOTTOGGLE") or now - self.epoch < self.DELAY then
		return
	end
	self.epoch = now
	for i = GetNumLootItems(), 1, -1 do
		LootSlot(i)
	end
end

-- global
local frame = CreateFrame("Frame")

local function PF(key) return NAME .. "-" .. key end
local function UNPF(key)
	local p = NAME .. "-"
	local w = #p
	return strsub(key, 1, w) == p and strsub(key, w + 1) or key
end

local function opt_changed(_, setting, value)
	local key = UNPF(setting:GetVariable())
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
		local label = "显示物品等级"
		local tooltip = "在鼠标提示中显示物品等级"
		local setting = Settings.RegisterAddOnSetting(category, label, PF(key), booltype, true)
		local control = Settings.CreateCheckBox(category, setting, tooltip)
		Settings.SetOnValueChangedCallback(setting.variable, opt_changed)
		if options[key] == false then
			control:GetSetting():SetValueInternal(false)
		end
	end
	do -- item price
		-- local has = Auctionator and Auctionator.Config.Get(Auctionator.Config.Options.VENDOR_TOOLTIPS)
		local key = "price"
		local label = "显示物品价格"
		local tooltip = "在鼠标提示中显示物品价格"
		local setting = Settings.RegisterAddOnSetting(category, label, PF(key), booltype, false)
		local control = Settings.CreateCheckBox(category, setting, tooltip)
		Settings.SetOnValueChangedCallback(setting.variable, opt_changed)
		if options[key] then
			control:GetSetting():SetValueInternal(true)
		end
	end
	do -- cheapest
		local key = "cheapest"
		local label = "高亮背包垃圾"
		local tooltip = "按下 Ctrl 时高亮背包内最便宜的垃圾物品"
		local setting = Settings.RegisterAddOnSetting(category, label, PF(key), booltype, true)
		local control = Settings.CreateCheckBox(category, setting, tooltip)
		Settings.SetOnValueChangedCallback(setting.variable, opt_changed)
		if options[key] == false then
			control:GetSetting():SetValueInternal(false)
		else
			frame:RegisterEvent("MODIFIER_STATE_CHANGED")
		end
	end
	do -- selljunk
		local key = "selljunk"
		local label = "垃圾出售"
		local tooltip = "在商人对话框的右上角添加一个垃圾出售的图标按钮"
		local setting = Settings.RegisterAddOnSetting(category, label, PF(key), booltype, true)
		local control = Settings.CreateCheckBox(category, setting, tooltip)
		Settings.SetOnValueChangedCallback(setting.variable, opt_changed)
		if options[key] == false then
			control:GetSetting():SetValueInternal(false)
		else
			selljunk.init()
		end
	end
	do -- fastloot
		local key = "fastloot"
		local label = "快速拾取"
		local tooltip = "不打开拾取框直接拾取"
		local setting = Settings.RegisterAddOnSetting(category, label, PF(key), booltype, false)
		local control = Settings.CreateCheckBox(category, setting, tooltip)
		Settings.SetOnValueChangedCallback(setting.variable, opt_changed)
		if options[key] then
			control:GetSetting():SetValueInternal(true)
			frame:RegisterEvent("LOOT_READY")
		end
	end
	Settings.RegisterAddOnCategory(category)
end

local function onevent(self, event, arg1, arg2)
	if event == "LOOT_READY" then
		fastloot:run(arg1)
	elseif event == "MODIFIER_STATE_CHANGED" then
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
