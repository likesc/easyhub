local NAME, ADDON = ...
local LANG = GetLocale()
local options --
-- compat
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
		local container  = GetMouseFocus()
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
	local bag, bcc, slot, send = unpack(sell.state)
	if slot > send then
		bag = bag + 1
		slot = 1
		send = C_Container.GetContainerNumSlots(bag)
		if send == 0 then
			sell.flush(sell)
			return
		end
		sell.state[1] = bag
		sell.state[3] = slot
		sell.state[4] = send
	end
	sell.routine(sell, bag, slot)
	sell.state[3] = slot + 1
	if sell.price then
		C_Timer.After(0.02, selljunk.next)
	end
end
function selljunk.routine(sell, bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or info.isLocked or info.quality > 0 or then
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
	sell.state = {0, NUM_BAG_SLOTS, 1, C_Container.GetContainerNumSlots(0)}
	sell.next() -- coroutine.yield ?
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
	ADDON.selljunk = button -- button:SetParentKey("selljunk")
end
function selljunk.destory()
	local button = ADDON.selljunk
	if not button then
		return
	end
	ADDON.selljunk = nil -- button:SetParentKey(nil)
	button:SetParent(nil)
	button:SetScript("OnLeave", nil)
	button:SetScript("OnEnter", nil)
	button:SetScript("OnMouseUp", nil)
	print("removed" .. tostring(MerchantBuyBackItem.selljunk))
end

--

local function opt_changed(_, setting, value)
	local key = setting:GetVariable()
	options[key] = value

	if key == "selljunk" then
		selljunk.destory()
		if value == true then
			selljunk.init()
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
	local category = Settings.RegisterVerticalLayoutCategory("针线盒")
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
	Settings.RegisterAddOnCategory(category)
end

local function main()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_LOADED")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("MODIFIER_STATE_CHANGED") -- cheapest
	frame:SetScript("OnEvent", function(self, event, name)
		if event == "ADDON_LOADED" and NAME == name then
			if not tinyhub_options then tinyhub_options = {} end
			options = tinyhub_options
		elseif event == "PLAYER_LOGIN" then
			init(self)
		end
	end)
end

local _ = main()
