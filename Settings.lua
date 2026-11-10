-- Settings, on the journal's two pages: mob tooltips on the left, item tooltips and general
-- options on the right. Open with /tits options, the Settings tab, or the game's AddOns settings.

local _, SB = ...
local W, Skin = SB.W, SB.Skin

local QUALITY_CHOICES = {
    { 0, "|cff9d9d9dPoor|r and up" }, { 1, "Common and up" }, { 2, "|cff1eff00Uncommon|r and up" },
    { 3, "|cff0070ddRare|r and up" }, { 4, "|cffa335eeEpic|r and up" },
}
local MODIFIER_CHOICES = { { "NONE", "Always" }, { "SHIFT", "While Shift is held" }, { "CTRL", "While Ctrl is held" }, { "ALT", "While Alt is held" } }
local SITE_CHOICES = { { "forever", "wowhead.com/forever" }, { "classic", "wowhead.com/classic" } }
local CLICK_CHOICES = { { "ALT", "Alt-click" }, { "CTRL-ALT", "Ctrl+Alt-click" }, { "SHIFT-ALT", "Shift+Alt-click" }, { "NONE", "Off" } }
local STYLE_CHOICES = { { "journal", "Adventure Guide" }, { "dark", "Dark" } }

local function Tip(key) return function() return SB.db.tip[key] end end
local function SetTip(key) return function(v) SB.db.tip[key] = v end end

StaticPopupDialogs.TOTALINTEL_FORGET = {
    text = "Forget everything Total Intel has recorded (kills, loot, spells, notes and recent targets) on all your characters? Recipes are kept.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        wipe(SB.db.mobs)
        wipe(SB.db.recent)
        SB.Print("your bestiary is empty again.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function SB.CreateSettingsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page.controls = {}
    local function Track(c) page.controls[#page.controls + 1] = c return c end

    local columns = {}
    for i = 1, 2 do
        local half = CreateFrame("Frame", nil, page)
        half:SetPoint(i == 1 and "TOPLEFT" or "TOPRIGHT")
        half:SetPoint(i == 1 and "BOTTOMLEFT" or "BOTTOMRIGHT")
        half:SetWidth(392)
        local band = Skin.New(half, i == 1 and "LeftPageHeader" or "RightPageHeader", "BACKGROUND", 3)
        band:SetPoint(i == 1 and "TOPLEFT" or "TOPRIGHT", 0, -11)
        band:SetPoint(i == 1 and "RIGHT" or "LEFT", i == 1 and -6 or 6, 0)
        band:SetHeight(39)
        local title = W.Text(half, "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 32, -24)
        title:SetText(i == 1 and "Mob tooltips" or "Item tooltips")
        half.title = title
        local col = CreateFrame("Frame", nil, half)
        col:SetPoint("TOPLEFT", i == 1 and 30 or 36, -60)
        col:SetSize(350, 360)
        col.y = 0
        columns[i] = col
        page["half" .. i] = half
    end
    local function Place(col, widget, indent, height)
        widget:SetPoint("TOPLEFT", col, "TOPLEFT", indent or 0, -col.y)
        col.y = col.y + (height or 22)
        return widget
    end
    local function Heading(col, text)
        col.y = col.y + 6
        local h = CreateFrame("Frame", nil, col)
        h:SetSize(330, 24)
        Skin.PaperHeader(h, false)
        local t = W.Text(h, "GameFontNormal")
        t:SetPoint("LEFT", 12, 0)
        t:SetText(text)
        Place(col, h, 0, 28)
    end
    local function Check(col, label, tip, key, indent)
        return Track(Place(col, W.Check(col, label, tip, Tip(key), SetTip(key)), indent))
    end

    local c1 = columns[1]
    Check(c1, "Add Total Intel lines to tooltips", "Turn every extra line on mob tooltips on or off at once.", "enabled")
    Track(Place(c1, W.Cycle(c1, "Show them", "Show the extra lines all the time, or only while you hold a key.",
        MODIFIER_CHOICES, Tip("modifier"), SetTip("modifier"), 140), 0, 26))
    Check(c1, "Type, rank and skinning", "\"Elite · Humanoid\", \"Beast · Wolf · Skinnable\".", "info")
    Check(c1, "Your quests that need it", "Quests in your log where you kill this mob or loot something from it, with your progress.", "quests")
    Check(c1, "Quests it gives and turn-ins", "Quests this NPC starts that you can still do, and quests you can turn in here.", "questGiver")
    Check(c1, "Notable drops", "Its best drops with their drop chance. Quest drops always show.", "drops")
    Track(Place(c1, W.Stepper(c1, "How many", 1, 15, Tip("dropsCount"), SetTip("dropsCount")), 26))
    Track(Place(c1, W.Cycle(c1, "Quality", "The lowest quality worth showing.", QUALITY_CHOICES,
        Tip("dropsMinQuality"), SetTip("dropsMinQuality"), 140), 26, 26))
    Check(c1, "Abilities", "Spells it casts, from the reference data and from what you've seen.", "abilities")
    Track(Place(c1, W.Stepper(c1, "How many", 1, 15, Tip("abilitiesCount"), SetTip("abilitiesCount")), 26))
    Check(c1, "Your kills and loot", "How many you've killed and looted, and your own drop counts once you've looted 5.", "kills")
    Check(c1, "Health and mana", "Its health and mana (Classic reference numbers).", "health")
    Check(c1, "Coin it drops", nil, "gold")
    Check(c1, "NPC ID", nil, "npcId")
    Check(c1, "Hint line", "A grey reminder of how to open the full page.", "hint")

    local c2 = columns[2]
    Check(c2, "Add Total Intel lines to item tooltips", nil, "itemEnabled")
    Check(c2, "Quests that use it", "Quests in your log that need it, quests it starts, and other quests that need it.", "itemQuests")
    Check(c2, "Crafted by", "The profession and skill that make it, from recipes read in the game.", "itemCrafted")
    Check(c2, "Dropped by", "The mobs with the best chance to drop it.", "itemDroppedBy")
    Track(Place(c2, W.Stepper(c2, "How many", 1, 15, Tip("itemDroppedByCount"), SetTip("itemDroppedByCount")), 26))
    Check(c2, "Sold by", "A vendor that sells it.", "itemVendors")
    Check(c2, "Where you looted it", "The mob you've looted it from most.", "itemYourLoot")
    Check(c2, "Item ID", nil, "itemId")
    Heading(c2, "General")
    Track(Place(c2, W.Cycle(c2, "Window style", "Adventure Guide parchment, or a plain dark window.", STYLE_CHOICES,
        function() return SB.db.style end, function(v) SB.db.style = v; SB.Restyle() end, 150), 0, 26))
    Track(Place(c2, W.Cycle(c2, "Open with", "Click an item, a mob in the world, a nameplate or your target frame with this to open its page.",
        CLICK_CHOICES, function() return SB.db.itemClick end, function(v) SB.db.itemClick = v end, 150), 0, 26))
    Track(Place(c2, W.Cycle(c2, "Wowhead links", "Which Wowhead the link buttons point to.", SITE_CHOICES,
        function() return SB.db.wowhead end, function(v) SB.db.wowhead = v end, 150), 0, 26))
    Track(Place(c2, W.Check(c2, "Record kills, loot and spells", "Count your kills and loot per mob and remember the spells mobs cast at you.",
        function() return SB.db.learn end, function(v) SB.db.learn = v end)))
    Track(Place(c2, W.Check(c2, "Minimap button", nil, function() return not SB.db.minimap.hide end,
        function(v) SB.db.minimap.hide = not v; if SB.UpdateMinimap then SB.UpdateMinimap() end end)))
    c2.y = c2.y + 6
    local reset = W.Button(c2, "Reset tooltips", 120, 22, function() SB.ResetTooltipSettings(); page:Refresh() end)
    Place(c2, reset, 0, 0)
    local forget = W.Button(c2, "Forget my bestiary...", 150, 22, function() StaticPopup_Show("TOTALINTEL_FORGET") end)
    forget:SetPoint("LEFT", reset, "RIGHT", 8, 0)

    function page:Layout(halfWidth)
        self.half1:SetWidth(halfWidth)
        self.half2:SetWidth(halfWidth)
    end

    function page:Refresh()
        for _, c in ipairs(self.controls) do if c.Refresh then c:Refresh() end end
        Skin.Color(self.half1.title, "title")
        Skin.Color(self.half2.title, "title")
    end
    return page
end

-- An entry in the game's own AddOns settings that opens the real settings.
SB.AddLoad(function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local t = W.Text(panel, "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText(SB.TITLE)
    local d = W.Text(panel, "GameFontHighlight")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -10)
    d:SetText("Loot, abilities, quests and recipes for every mob and item.\nType /tits to open the window, /tits options for these settings.")
    d:SetJustifyH("LEFT")
    local b = W.Button(panel, "Open settings", 160, 24, function()
        if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel, true) end
        SB.OpenSettings()
    end)
    b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -14)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Total Intel on Targets & Spoils")
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end)
