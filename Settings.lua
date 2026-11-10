-- Settings: what goes on mob and item tooltips, plus general options. Shown inside the
-- Total Intel window (/tits options) and linked from the game's AddOns settings.

local _, SB = ...
local W = SB.W

local QUALITY_CHOICES = {
    { 0, "|cff9d9d9dPoor|r and up" }, { 1, "Common and up" }, { 2, "|cff1eff00Uncommon|r and up" },
    { 3, "|cff0070ddRare|r and up" }, { 4, "|cffa335eeEpic|r and up" },
}
local MODIFIER_CHOICES = { { "NONE", "Always" }, { "SHIFT", "While Shift is held" }, { "CTRL", "While Ctrl is held" }, { "ALT", "While Alt is held" } }
local SITE_CHOICES = { { "forever", "wowhead.com/forever" }, { "classic", "wowhead.com/classic" } }
local CLICK_CHOICES = { { "ALT", "Alt-click" }, { "CTRL-ALT", "Ctrl+Alt-click" }, { "SHIFT-ALT", "Shift+Alt-click" }, { "NONE", "Off" } }

local function Tip(key) return function() return SB.db.tip[key] end end
local function SetTip(key) return function(v) SB.db.tip[key] = v end end

StaticPopupDialogs.TOTALINTEL_FORGET = {
    text = "Forget everything Total Intel has recorded (kills, loot, spells, notes and recent targets) on all your characters?",
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
    local page = W.Panel(parent, 0.25)
    page.controls = {}
    local function Track(c) page.controls[#page.controls + 1] = c return c end

    local title = W.Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Settings")
    local done = W.Button(page, "Done", 100, 22, function() page:Hide(); SB.CloseSettings() end)
    done:SetPoint("TOPRIGHT", -12, -10)

    local columns = {}
    for i = 1, 2 do
        local col = CreateFrame("Frame", nil, page)
        col:SetPoint("TOPLEFT", 16 + (i - 1) * 330, -44)
        col:SetSize(320, 480)
        col.y = 0
        columns[i] = col
    end
    local function Place(col, widget, indent, height)
        widget:SetPoint("TOPLEFT", col, "TOPLEFT", indent or 0, -col.y)
        col.y = col.y + (height or 24)
        return widget
    end
    local function Heading(col, text)
        col.y = col.y + (col.y > 0 and 8 or 0)
        local h = W.Text(col, "GameFontNormal")
        Place(col, h, 0, 20)
        h:SetText(text)
    end
    local function Check(col, label, tip, key, indent)
        return Track(Place(col, W.Check(col, label, tip, Tip(key), SetTip(key)), indent))
    end

    -- column 1: mob tooltips
    local c1 = columns[1]
    Heading(c1, "Mob tooltips")
    Check(c1, "Add Total Intel lines to tooltips", "Turn every extra tooltip line on or off at once.", "enabled")
    Track(Place(c1, W.Cycle(c1, "Show them", "Show the extra lines all the time, or only while you hold a key.",
        MODIFIER_CHOICES, Tip("modifier"), SetTip("modifier"), 140), 4, 26))
    Check(c1, "Type, rank and skinning", "\"Elite · Humanoid\", \"Beast · Wolf · Skinnable\".", "info")
    Check(c1, "Your quests that need it", "Quests in your log where you kill this mob or loot something from it, with your progress.", "quests")
    Check(c1, "Quests it gives / turn-ins", "Quests this NPC starts that you can still do, and quests you can turn in here.", "questGiver")
    Check(c1, "Notable drops", "Its best drops with their Classic drop chance. Quest drops always show.", "drops")
    Track(Place(c1, W.Stepper(c1, "How many", 1, 10, Tip("dropsCount"), SetTip("dropsCount")), 24))
    Track(Place(c1, W.Cycle(c1, "Quality", "The lowest quality worth showing.", QUALITY_CHOICES,
        Tip("dropsMinQuality"), SetTip("dropsMinQuality"), 140), 24, 26))
    Check(c1, "Abilities", "Spells it casts, from the database and from what you've seen.", "abilities")
    Track(Place(c1, W.Stepper(c1, "How many", 1, 10, Tip("abilitiesCount"), SetTip("abilitiesCount")), 24))
    Check(c1, "Your kills and loot", "How many you've killed and looted, and your own drop counts once you've looted 5.", "kills")
    Check(c1, "Health and mana", "Its health (and mana) from the database.", "health")
    Check(c1, "Coin it drops", "How much money it drops.", "gold")
    Check(c1, "NPC ID", "Its ID, handy for Wowhead.", "npcId")
    Check(c1, "Hint line", "A grey reminder that /tits opens the full page.", "hint")

    -- column 2: item tooltips + general
    local c2 = columns[2]
    Heading(c2, "Item tooltips")
    Check(c2, "Add Total Intel lines to item tooltips", nil, "itemEnabled")
    Check(c2, "Quests that use it", "Quests in your log that need it, quests it starts, and other quests that need it.", "itemQuests")
    Check(c2, "Dropped by", "The mobs with the best chance to drop it.", "itemDroppedBy")
    Track(Place(c2, W.Stepper(c2, "How many", 1, 10, Tip("itemDroppedByCount"), SetTip("itemDroppedByCount")), 24))
    Check(c2, "Sold by", "A vendor that sells it.", "itemVendors")
    Check(c2, "Where you looted it", "The mob you've looted it from most.", "itemYourLoot")
    Check(c2, "Item ID", nil, "itemId")

    Heading(c2, "General")
    Track(Place(c2, W.Cycle(c2, "Wowhead links", "Which Wowhead the link buttons point to.", SITE_CHOICES,
        function() return SB.db.wowhead end, function(v) SB.db.wowhead = v end, 150), 4, 26))
    Track(Place(c2, W.Cycle(c2, "Item page", "Click an item in your bags, chat or loot with this to open its page.",
        CLICK_CHOICES, function() return SB.db.itemClick end, function(v) SB.db.itemClick = v end, 150), 4, 26))
    Track(Place(c2, W.Check(c2, "Record kills, loot and spells", "Count your kills and loot per mob and remember the spells mobs cast at you.",
        function() return SB.db.learn end, function(v) SB.db.learn = v end)))
    Track(Place(c2, W.Check(c2, "Minimap button", nil, function() return not SB.db.minimap.hide end,
        function(v) SB.db.minimap.hide = not v; if SB.UpdateMinimap then SB.UpdateMinimap() end end)))
    c2.y = c2.y + 8
    local reset = W.Button(c2, "Reset tooltip settings", 170, 22, function()
        SB.ResetTooltipSettings()
        page:Refresh()
    end)
    Place(c2, reset, 0, 28)
    local forget = W.Button(c2, "Forget my bestiary...", 170, 22, function() StaticPopup_Show("TOTALINTEL_FORGET") end)
    Place(c2, forget, 0, 28)

    local note = W.Text(page, "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 16, 12)
    note:SetPoint("RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Inside dungeons and raids the game hides which mob a tooltip belongs to, so mob tooltips there have no extra lines. Use the Zone list to browse an instance's mobs.")

    function page:Refresh()
        for _, c in ipairs(self.controls) do if c.Refresh then c:Refresh() end end
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
    d:SetText("Loot tables, abilities and quest info for every mob.\nType /tits to open the window, /tits options for these settings.")
    d:SetJustifyH("LEFT")
    local b = W.Button(panel, "Open settings", 160, 24, function()
        if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel, true) end
        SB.OpenSettings()
    end)
    b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -14)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Total Intel on Targets & Spoils")
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end)
