local NAME, ADDON = ...
local options --
-- compat
local GetContainerNumSlots = C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetItemInfo = C_Item.GetItemInfo or GetItemInfo

-- item price/level

local function tooltip_price(tooltip)
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
			count = container.count or tonumber(container.Count:GetText()) or 1
		end
		tooltip:AddDoubleLine(GetMoneyString(count * price), show_level and "Lv(" .. level .. ")" or "")
	elseif show_level ~= false then
		tooltip:AddLine(format(ITEM_LEVEL, level))
	end
end

--

local function opt_changed(_, setting, value)
	local key = setting:GetVariable()
	options[key] = value
end

local function init(frame)
	-- TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, tooltip_price)
	GameTooltip:HookScript("OnTooltipSetItem", tooltip_price)
	ItemRefTooltip:HookScript("OnTooltipSetItem", tooltip_price)

	-- options
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("针线盒")
	local booltype = type(true)
	do
		local key = "level"
		local label = "显示物品等级"
		local tooltip = "在鼠标提示中显示物品等级"
		local defaultValue = options[key] or true
		local setting = Settings.RegisterAddOnSetting(category, label, key, booltype, defaultValue)
		Settings.CreateCheckBox(category, setting, tooltip)
		Settings.SetOnValueChangedCallback(key, opt_changed)
	end
	do
		-- local has = Auctionator and Auctionator.Config.Get(Auctionator.Config.Options.VENDOR_TOOLTIPS)
		local key = "price"
		local label = "显示物品价格"
		local tooltip = "在鼠标提示中显示物品价格"
		local defaultValue = options[key] or false
		local setting = Settings.RegisterAddOnSetting(category, label, key, booltype, defaultValue)
		Settings.CreateCheckBox(category, setting, tooltip)
		Settings.SetOnValueChangedCallback(key, opt_changed)
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
