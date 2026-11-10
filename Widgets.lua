-- Widget helpers shared by the window and the settings page, the scrolling "flow" list that
-- draws journal-style rows, and the Wowhead link popup.

local _, SB = ...
local W = {}
SB.W = W
local Skin = SB.Skin

local function TemplateExists(name)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
        return ok and info ~= nil
    end
    return true
end

function W.CreateWithTemplate(kind, name, parent, templates)
    for _, tpl in ipairs(templates) do
        if TemplateExists(tpl) then
            local ok, frame = pcall(CreateFrame, kind, name, parent, tpl)
            if ok and frame then return frame, tpl end
        end
    end
    return CreateFrame(kind, name, parent), nil
end

-- The templates' close button goes through the panel manager, which is locked in combat.
function W.FixCloseButton(frame)
    local close = frame.CloseButton or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    if type(close) == "table" and close.SetScript then
        close:SetScript("OnClick", function() frame:Hide() end)
    end
end

function W.Font(name, fallback)
    return _G[name] and name or fallback
end

function W.Text(parent, font, layer)
    return parent:CreateFontString(nil, layer or "OVERLAY", font)
end

function W.Button(parent, text, width, height, onClick)
    local b, tpl = W.CreateWithTemplate("Button", nil, parent, { "UIPanelButtonTemplate", "UIPanelDynamicResizeButtonTemplate" })
    b:SetSize(width, height or 22)
    if not tpl then
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.35, 0.08, 0.05, 0.9)
        b:SetNormalFontObject("GameFontNormalSmall")
        b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetDisabledFontObject("GameFontDisableSmall")
    end
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function W.Tooltip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then GameTooltip:AddLine(line, nil, nil, nil, true) end
    end
    GameTooltip:Show()
end

function W.Check(parent, label, tooltip, get, set)
    local c, tpl = W.CreateWithTemplate("CheckButton", nil, parent, { "UICheckButtonTemplate", "ChatConfigCheckButtonTemplate" })
    c:SetSize(24, 24)
    if not tpl then
        c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    if c.Text then c.Text:SetText("") end
    c.label = W.Text(c, "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 1)
    c.label:SetText(label)
    c:SetHitRectInsets(0, -(c.label:GetStringWidth() or 100) - 4, 0, 0)
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    c:SetScript("OnEnter", function(self) if tooltip then W.Tooltip(self, label, tooltip) end end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.Refresh = function(self)
        self:SetChecked(get() and true or false)
        Skin.Color(self.label, "text")
    end
    return c
end

-- A button that cycles through choices: { {value, "Label"}, ... }
function W.Cycle(parent, label, tooltip, choices, get, set, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize((width or 150) + 130, 24)
    f.label = W.Text(f, "GameFontHighlight")
    f.label:SetPoint("LEFT", 4, 0)
    f.label:SetText(label)
    f.button = W.Button(f, "", width or 150, 22, function()
        local cur, idx = get(), 1
        for i, c in ipairs(choices) do if c[1] == cur then idx = i end end
        local step = IsShiftKeyDown() and -1 or 1
        idx = (idx - 1 + step) % #choices + 1
        set(choices[idx][1])
        f:Refresh()
    end)
    f.button:SetPoint("LEFT", f.label, "RIGHT", 8, 0)
    f.button:SetScript("OnEnter", function(self) W.Tooltip(self, label, tooltip, "|cff888888Click for the next choice, shift-click for the previous.|r") end)
    f.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.Refresh = function(self)
        local cur = get()
        for _, c in ipairs(choices) do if c[1] == cur then self.button:SetText(c[2]) end end
        Skin.Color(self.label, "text")
    end
    return f
end

-- [-] n [+]
function W.Stepper(parent, label, min, max, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(200, 24)
    f.label = W.Text(f, "GameFontHighlight")
    f.label:SetPoint("LEFT", 4, 0)
    f.label:SetText(label)
    f.minus = W.Button(f, "-", 24, 22, function() set(math.max(min, get() - 1)); f:Refresh() end)
    f.minus:SetPoint("LEFT", f.label, "RIGHT", 8, 0)
    f.value = W.Text(f, "GameFontNormal")
    f.value:SetPoint("LEFT", f.minus, "RIGHT", 4, 0)
    f.value:SetWidth(24)
    f.plus = W.Button(f, "+", 24, 22, function() set(math.min(max, get() + 1)); f:Refresh() end)
    f.plus:SetPoint("LEFT", f.value, "RIGHT", 4, 0)
    f.Refresh = function(self)
        self.value:SetText(tostring(get()))
        Skin.Color(self.label, "text")
        Skin.Color(self.value, "key")
    end
    return f
end

function W.Input(parent, width, placeholder)
    local eb, tpl = W.CreateWithTemplate("EditBox", nil, parent, { "SearchBoxTemplate", "InputBoxTemplate" })
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    if not tpl then
        eb:SetFontObject("ChatFontNormal")
        local bg = eb:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", -4, 2)
        bg:SetPoint("BOTTOMRIGHT", 4, -2)
        bg:SetColorTexture(0, 0, 0, 0.6)
    end
    if tpl ~= "SearchBoxTemplate" then
        eb.placeholder = W.Text(eb, "GameFontDisable")
        eb.placeholder:SetPoint("LEFT", 2, 0)
        eb.placeholder:SetText(placeholder)
        local function update() eb.placeholder:SetShown(eb:GetText() == "" and not eb:HasFocus()) end
        eb:HookScript("OnEditFocusGained", update)
        eb:HookScript("OnEditFocusLost", update)
        eb:HookScript("OnTextChanged", update)
    elseif eb.Instructions then
        eb.Instructions:SetText(placeholder)
    end
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

function W.SetIcon(tex, icon)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
end

-- A scroll frame with the game's slim modern scrollbar (or a plain slider on older clients).
function W.Scroll(parent)
    local holder = CreateFrame("Frame", nil, parent)
    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -14, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(10, 10)
    scroll:SetScrollChild(child)
    holder.scroll, holder.child = scroll, child

    local ok = pcall(function()
        if not (ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar) then error("no ScrollUtil") end
        local bar = CreateFrame("EventFrame", nil, holder, "MinimalScrollBar")
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -2)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 2)
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
        holder.bar = bar
    end)
    if not ok then
        local bar = CreateFrame("Slider", nil, holder)
        bar:SetWidth(6)
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, 0)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 0)
        bar:SetOrientation("VERTICAL")
        local track = bar:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(0, 0, 0, 0.25)
        local thumb = bar:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(0.6, 0.45, 0.25, 0.9)
        thumb:SetSize(6, 30)
        bar:SetThumbTexture(thumb)
        bar:SetMinMaxValues(0, 0)
        bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v or 0) end)
        scroll:SetScript("OnScrollRangeChanged", function(self, _, range)
            range = range or 0
            bar:SetMinMaxValues(0, range)
            bar:SetShown(range > 0)
        end)
        holder.slider = bar
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local v = math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 45))
        self:SetVerticalScroll(v)
        if holder.slider then holder.slider:SetValue(v) end
    end)
    function holder:ScrollToTop()
        scroll:SetVerticalScroll(0)
        if self.slider then self.slider:SetValue(0) end
    end
    return holder
end

------------------------------------------------------------------------------
-- Flow list: rows of different kinds and heights, laid out top to bottom.
--
-- row = { kind = "boss"|"npc"|"item"|"header"|"spell"|"text"|"kv"|"quest"|"line"|"tiles"|"columns",
--         text, sub, mid, right, icon, portrait (display ID), color (palette name or {r,g,b}),
--         id, onClick, tooltip = fn(tt, row), selected, expanded, tiles = { ... } }
------------------------------------------------------------------------------

local function TextColor(fs, c, default)
    if type(c) == "table" then Skin.Ink(fs, c)
    else Skin.Color(fs, c or default or "text") end
end

local function RowTooltip(btn)
    local r = btn.row
    if not r then return end
    if r.kind == "item" and r.id then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetItemByID, GameTooltip, r.id)
        if not ok then GameTooltip:AddLine(SB.ItemText(r.id)) end
        GameTooltip:AddLine("|cff888888Click: open its page · Shift-click: link in chat|r")
        GameTooltip:Show()
    elseif (r.kind == "spell") and r.id then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, r.id)
        if not ok then GameTooltip:AddLine(SB.SpellInfo(r.id) or ("Spell " .. r.id), 1, 1, 1) end
        GameTooltip:AddLine("|cff888888Spell " .. r.id .. " · Click: show or hide details · Shift-click: link in chat|r")
        GameTooltip:Show()
    elseif r.tooltip then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        r.tooltip(GameTooltip, r)
        GameTooltip:Show()
    end
end

local function RowClick(btn, mouse)
    local r = btn.row
    if not r then return end
    if IsShiftKeyDown() and r.kind == "item" and r.id then
        local it = SB.GetItem(r.id)
        local link = it.link
        if not link then
            local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            if f then link = select(2, f(r.id)) end
        end
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        return
    end
    if IsShiftKeyDown() and r.kind == "spell" and r.id then
        local f = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
        local link = f and f(r.id)
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        return
    end
    if r.onClick then r.onClick(r, mouse) end
end

local function Interactive(b)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", RowTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", RowClick)
end

local B = {}

-- Boss buttons, as in the journal's encounter list.
B.boss = {
    new = function(parent)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(325, 55)
        b.bg = Skin.New(b, "BossButtonUp", "BACKGROUND")
        b.bg:SetAllPoints()
        b.sel = Skin.New(b, "BossButtonDown", "BACKGROUND", 1)
        b.sel:SetAllPoints()
        b.hl = Skin.New(b, "BossButtonHighlight", "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.portrait = Skin.Portrait(b, 38)
        b.portrait:SetPoint("LEFT", 16, 0)
        b.name = W.Text(b, W.Font("GameFontNormalMed3", "GameFontNormal"))
        b.name:SetPoint("TOPLEFT", 66, -12)
        b.name:SetPoint("RIGHT", -50, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.sub = W.Text(b, "GameFontHighlightSmall")
        b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -4)
        b.sub:SetPoint("RIGHT", -12, 0)
        b.sub:SetJustifyH("LEFT")
        b.sub:SetWordWrap(false)
        b.right = W.Text(b, "GameFontNormalSmall")
        b.right:SetPoint("TOPRIGHT", -14, -12)
        Interactive(b)
        return b
    end,
    set = function(b, r, width)
        local w = math.max(260, width - 8)
        b:SetWidth(w)
        b.name:SetText(r.text or "")
        TextColor(b.name, r.color, "boss")
        b.sub:SetText(r.sub or "")
        Skin.Color(b.sub, "bossSub")
        b.right:SetText(r.right or "")
        Skin.Color(b.right, "boss")
        b.sel:SetShown(r.selected and true or false)
        Skin.SetPortrait(b.portrait, r.portrait, r.icon)
        return 55, math.floor((width - w) / 2)
    end,
    gap = 2,
}

-- Loot rows, as in the journal's loot tab. Also used for mobs (with a portrait).
local function LootRow(parent, round)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(321, 45)
    b.bg = Skin.New(b, "LootFrame", "BORDER")
    b.bg:SetPoint("LEFT")
    b.bg:SetSize(321, 45)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 0.85, 0.5, 0.1)
    hl:SetBlendMode("ADD")
    if round then
        b.icon = Skin.Portrait(b, 34)
        b.icon:SetPoint("LEFT", 6, 0)
    else
        b.icon = b:CreateTexture(nil, "BACKGROUND")
        b.icon:SetSize(42, 42)
        b.icon:SetPoint("TOPLEFT", 2, -2)
    end
    b.name = W.Text(b, W.Font("GameFontNormalMed3", "GameFontNormal"))
    b.name:SetPoint("TOPLEFT", 51, -7)
    b.name:SetPoint("RIGHT", -110, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.sub = W.Text(b, "GameFontHighlightSmall")
    b.sub:SetPoint("BOTTOMLEFT", 51, 7)
    b.sub:SetPoint("RIGHT", -130, 0)
    b.sub:SetJustifyH("LEFT")
    b.sub:SetWordWrap(false)
    b.mid = W.Text(b, W.Font("GameFontNormalMed3", "GameFontNormal"))
    b.mid:SetPoint("TOPRIGHT", -10, -7)
    b.mid:SetJustifyH("RIGHT")
    b.right = W.Text(b, "GameFontHighlightSmall")
    b.right:SetPoint("BOTTOMRIGHT", -10, 7)
    b.right:SetJustifyH("RIGHT")
    Interactive(b)
    return b
end

local function SetLootRow(b, r, width, round)
    local w = math.max(260, width - 4)
    b:SetWidth(w)
    b.bg:SetWidth(w)
    if round then Skin.SetPortrait(b.icon, r.portrait, r.icon)
    else W.SetIcon(b.icon, r.icon) end
    b.name:SetText(r.text or "")
    TextColor(b.name, r.color, "boss")
    b.sub:SetText(r.sub or "")
    Skin.Color(b.sub, "lootSub")
    b.mid:SetText(r.mid or "")
    Skin.Color(b.mid, "lootMid")
    b.right:SetText(r.right or "")
    Skin.Color(b.right, "you")
    return 45, math.floor((width - w) / 2)
end

B.item = { new = function(p) return LootRow(p, false) end, set = function(b, r, w) return SetLootRow(b, r, w, false) end, gap = 3 }
B.npc = { new = function(p) return LootRow(p, true) end, set = function(b, r, w) return SetLootRow(b, r, w, true) end, gap = 3 }

-- Paper headers: section titles, and abilities that open to show their description.
B.header = {
    new = function(parent)
        local b = CreateFrame("Button", nil, parent)
        b:SetHeight(29)
        Skin.PaperHeader(b, false)
        b.hlFrame = CreateFrame("Frame", nil, b)
        b.hlFrame:SetAllPoints()
        Skin.PaperHeader(b, true)
        b.expand = W.Text(b, "GameFontNormalLarge")
        b.expand:SetPoint("LEFT", 8, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        b.border = Skin.New(b, "AbilityIconBorder", "OVERLAY")
        b.border:SetPoint("CENTER", b.icon)
        b.border:SetSize(22, 22)
        b.title = W.Text(b, "GameFontNormal")
        b.title:SetJustifyH("LEFT")
        b.title:SetWordWrap(false)
        b.right = W.Text(b, "GameFontNormalSmall")
        b.right:SetPoint("RIGHT", -12, 0)
        Interactive(b)
        return b
    end,
    set = function(b, r, width)
        b:SetWidth(width)
        local x = 12
        if r.kind == "spell" then
            b.expand:SetText(r.expanded and "–" or "+")
            b.expand:Show()
            x = 24
        else
            b.expand:Hide()
        end
        if r.icon then
            b.icon:SetTexture(r.icon)
            b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            b.icon:SetPoint("LEFT", x, 0)
            b.icon:Show(); b.border:Show()
            x = x + 24
        else
            b.icon:Hide(); b.border:Hide()
        end
        b.title:SetPoint("LEFT", x, 0)
        b.title:SetPoint("RIGHT", -60, 0)
        b.title:SetText(r.text or "")
        TextColor(b.title, r.color, "header")
        b.right:SetText(r.right or "")
        Skin.Color(b.right, "title")
        b:EnableMouse((r.onClick or r.tooltip or r.kind == "spell") and true or false)
        return 29, 0
    end,
    gap = 4, before = 8,
}
B.spell = B.header

B.text = {
    new = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.text = W.Text(f, W.Font("GameFontBlackMedium", W.Font("GameFontBlack", "GameFontHighlight")))
        f.text:SetPoint("TOPLEFT")
        f.text:SetJustifyH("LEFT")
        f.text:SetJustifyV("TOP")
        f.text:SetSpacing(2)
        return f
    end,
    set = function(f, r, width)
        local indent = r.indent or 8
        f:SetWidth(width - indent)
        f.text:SetWidth(width - indent - 8)
        f.text:SetText(r.text or "")
        TextColor(f.text, r.color, "text")
        local h = (f.text:GetStringHeight() or 14) + 4
        f:SetHeight(h)
        return h, indent
    end,
    gap = 2,
}
B.columns = B.text

B.kv = {
    new = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.key = W.Text(f, W.Font("GameFontNormal", "GameFontHighlight"))
        f.key:SetPoint("TOPLEFT")
        f.key:SetWidth(130)
        f.key:SetJustifyH("LEFT")
        f.key:SetWordWrap(false)
        f.value = W.Text(f, W.Font("GameFontBlackMedium", W.Font("GameFontBlack", "GameFontHighlight")))
        f.value:SetPoint("TOPLEFT", 136, 0)
        f.value:SetJustifyH("LEFT")
        f.value:SetJustifyV("TOP")
        return f
    end,
    set = function(f, r, width)
        f:SetWidth(width - 12)
        f.key:SetText(r.key or "")
        Skin.Color(f.key, "key")
        f.value:SetWidth(width - 12 - 144)
        f.value:SetText(r.text or "")
        TextColor(f.value, r.color, "text")
        local h = math.max(f.key:GetStringHeight() or 14, f.value:GetStringHeight() or 14) + 6
        f:SetHeight(h)
        return h, 12
    end,
    gap = 1,
}

-- One-line rows with a small icon: quests, zones.
B.line = {
    new = function(parent)
        local b = CreateFrame("Button", nil, parent)
        b:SetHeight(26)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.55, 0.35, 0.1, 0.18)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 8, 0)
        b.text = W.Text(b, W.Font("GameFontBlackMedium", W.Font("GameFontBlack", "GameFontHighlight")))
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b.mid = W.Text(b, W.Font("GameFontBlack", "GameFontHighlightSmall"))
        b.mid:SetJustifyH("RIGHT")
        b.right = W.Text(b, W.Font("GameFontBlack", "GameFontHighlightSmall"))
        b.right:SetPoint("RIGHT", -8, 0)
        b.right:SetJustifyH("RIGHT")
        b.mid:SetPoint("RIGHT", b.right, "LEFT", -10, 0)
        b.text:SetPoint("RIGHT", b.mid, "LEFT", -8, 0)
        Interactive(b)
        return b
    end,
    set = function(b, r, width)
        b:SetWidth(width)
        if r.icon then b.icon:SetTexture(r.icon); b.icon:SetTexCoord(0, 1, 0, 1); b.icon:Show() else b.icon:Hide() end
        b.text:SetText(r.text or "")
        TextColor(b.text, r.color, "text")
        b.mid:SetText(r.mid or "")
        Skin.Color(b.mid, "dim")
        b.right:SetText(r.right or "")
        TextColor(b.right, r.rightColor, "key")
        b:EnableMouse((r.onClick or r.tooltip) and true or false)
        return 26, 4
    end,
    gap = 0,
}
B.quest = B.line
B.zone = B.line

-- Instance tiles, as in the journal's dungeon and raid grid (up to 4 per row).
local TILE_W, TILE_H = 174, 96
B.tiles = {
    new = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.tiles = {}
        for i = 1, 4 do
            local t = CreateFrame("Button", nil, f)
            t:SetSize(TILE_W, TILE_H)
            t.art = t:CreateTexture(nil, "BACKGROUND")
            t.art:SetAllPoints()
            t.portrait = Skin.Portrait(t, 44)
            t.portrait:SetPoint("TOPLEFT", 14, -12)
            t.frame = Skin.New(t, "DungeonButtonUp", "BORDER")
            t.frame:SetAllPoints()
            t.hl = Skin.New(t, "DungeonButtonHL", "HIGHLIGHT")
            t.hl:SetAllPoints()
            t.name = W.Text(t, W.Font("QuestFont_Large", "GameFontNormalLarge"))
            t.name:SetPoint("BOTTOMLEFT", 12, 26)
            t.name:SetPoint("RIGHT", -10, 0)
            t.name:SetJustifyH("LEFT")
            t.name:SetTextColor(1, 0.92, 0.75)
            t.name:SetShadowOffset(1, -1)
            t.sub = W.Text(t, "GameFontHighlightSmall")
            t.sub:SetPoint("BOTTOMLEFT", 12, 10)
            t.sub:SetTextColor(0.85, 0.8, 0.7)
            t.sub:SetShadowOffset(1, -1)
            t:SetScript("OnEnter", RowTooltip)
            t:SetScript("OnLeave", function() GameTooltip:Hide() end)
            t:SetScript("OnClick", RowClick)
            f.tiles[i] = t
        end
        return f
    end,
    set = function(f, r, width)
        local gap = math.max(6, math.floor((width - 4 * TILE_W) / 5))
        f:SetSize(width, TILE_H)
        for i, t in ipairs(f.tiles) do
            local d = r.tiles[i]
            t.row = d
            if d then
                t:Show()
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", gap + (i - 1) * (TILE_W + gap), 0)
                if d.art then
                    t.art:SetTexture(d.art)
                    t.art:SetTexCoord(0, 1, 0, 1)
                    t.portrait:Hide(); t.portrait.ring:Hide()
                else
                    Skin.Apply(t.art, "DungeonBG")
                    t.art:SetTexCoord(0.1, 0.6, 0.1, 0.4)
                    t.portrait:Show(); t.portrait.ring:Show()
                    Skin.SetPortrait(t.portrait, d.portrait, d.icon)
                end
                t.name:SetText(d.text or "")
                t.sub:SetText(d.sub or "")
            else
                t:Hide()
            end
        end
        return TILE_H, 0
    end,
    gap = 14,
}

function W.Flow(parent)
    local list = W.Scroll(parent)
    list.pools, list.rows = {}, {}
    list.frames = {}

    function list:Acquire(kind, used)
        local b = B[kind] or B.text
        self.pools[b] = self.pools[b] or {}
        used[b] = (used[b] or 0) + 1
        local f = self.pools[b][used[b]]
        if not f then
            f = b.new(self.child)
            self.pools[b][used[b]] = f
        end
        return f, b
    end

    function list:SetRows(rows, keepScroll)
        self.rows = rows or {}
        local used = {}
        local width = math.max(200, (self.width or self:GetWidth() or 360) - 24)
        self.child:SetWidth(width)
        local y = 0
        for i, r in ipairs(self.rows) do
            local f, b = self:Acquire(r.kind, used)
            f.row = r
            f:Show()
            if b.before and i > 1 then y = y + b.before end
            local h, x = b.set(f, r, width)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self.child, "TOPLEFT", x or 0, -y)
            y = y + (h or 20) + (b.gap or 2)
        end
        for b, pool in pairs(self.pools) do
            for i = (used[b] or 0) + 1, #pool do pool[i]:Hide(); pool[i].row = nil end
        end
        self.child:SetHeight(math.max(1, y))
        if not keepScroll then self:ScrollToTop() end
    end

    return list
end

------------------------------------------------------------------------------
-- Wowhead link popup (the game can't open a browser, so you copy the link)
------------------------------------------------------------------------------

local popup
function SB.ShowLink(kind, id, label)
    if not popup then
        popup = W.CreateWithTemplate("Frame", "TotalIntelLinkFrame", UIParent, { "PortraitFrameTemplate", "BasicFrameTemplateWithInset" })
        popup:SetSize(480, 120)
        W.FixCloseButton(popup)
        popup:SetPoint("CENTER", 0, 140)
        popup:SetFrameStrata("DIALOG")
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        if popup.SetPortraitToAsset then pcall(popup.SetPortraitToAsset, popup, SB.ICON) end
        if popup.PortraitContainer and popup.PortraitContainer.portrait then popup.PortraitContainer.portrait:SetTexture(SB.ICON) end
        tinsert(UISpecialFrames, "TotalIntelLinkFrame")
        popup.titleText = W.Text(popup, "GameFontNormal")
        popup.titleText:SetPoint("TOP", 0, -5)
        popup.hint = W.Text(popup, "GameFontHighlightSmall")
        popup.hint:SetPoint("TOPLEFT", 70, -38)
        popup.hint:SetText("Press Ctrl+C to copy, then paste it in your browser.")
        local eb = W.CreateWithTemplate("EditBox", nil, popup, { "InputBoxTemplate" })
        eb:SetSize(380, 24)
        eb:SetPoint("TOPLEFT", 74, -62)
        eb:SetFontObject(ChatFontNormal)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() popup:Hide() end)
        eb:SetScript("OnEnterPressed", function() popup:Hide() end)
        eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(popup.url); self:HighlightText() end end)
        eb:SetScript("OnKeyUp", function(_, key)
            if key == "C" and IsControlKeyDown() then SB.After(0.05, function() popup:Hide() end) end
        end)
        popup.edit = eb
    end
    popup.url = SB.WowheadURL(kind, id)
    local title = "Wowhead: " .. (label or (kind .. " " .. id))
    if popup.SetTitle then popup:SetTitle(title) else popup.titleText:SetText(title) end
    popup.edit:SetText(popup.url)
    popup:Show()
    popup.edit:SetFocus()
    popup.edit:HighlightText()
end
