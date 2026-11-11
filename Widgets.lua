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
    c.label = W.Text(c, W.Font("GameFontBlackMedium", "GameFontHighlight"))
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
    f.label = W.Text(f, W.Font("GameFontBlackMedium", "GameFontHighlight"))
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
    f.label = W.Text(f, W.Font("GameFontBlackMedium", "GameFontHighlight"))
    f.label:SetPoint("LEFT", 4, 0)
    f.label:SetText(label)
    f.minus = W.Button(f, "-", 24, 22, function() set(math.max(min, get() - 1)); f:Refresh() end)
    f.minus:SetPoint("LEFT", f.label, "RIGHT", 8, 0)
    f.value = W.Text(f, W.Font("GameFontBlackMedium", "GameFontNormal"))
    f.value:SetPoint("LEFT", f.minus, "RIGHT", 4, 0)
    f.value:SetWidth(24)
    f.plus = W.Button(f, "+", 24, 22, function() set(math.min(max, get() + 1)); f:Refresh() end)
    f.plus:SetPoint("LEFT", f.value, "RIGHT", 4, 0)
    f.Refresh = function(self)
        self.value:SetText(tostring(get()))
        Skin.Color(self.label, "text")
        Skin.Color(self.value, "text")
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
    elseif (r.kind == "spell" or r.kind == "teach") and r.id then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, r.id)
        if not ok then GameTooltip:AddLine(SB.SpellInfo(r.id) or ("Spell " .. r.id), 1, 1, 1) end
        GameTooltip:AddLine("|cff888888Spell " .. r.id .. (r.kind == "spell" and " · Click: show or hide details" or " · Click: Wowhead link")
            .. " · Shift-click: link in chat|r")
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
    if IsShiftKeyDown() and (r.kind == "spell" or r.kind == "teach") and r.id then
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

local BODY = W.Font("GameFontBlackMedium", W.Font("GameFontBlack", "GameFontHighlight"))

-- A clickable row on a dark bar that fills its whole width.
local function BarRow(parent, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height)
    b.bg = Skin.Bar(b, "RowBg")
    b.sel = Skin.New(b, "RowBgSel", "BACKGROUND", 1)
    b.sel:SetAllPoints()
    b.sel:Hide()
    b.accent = Skin.New(b, "Accent", "BORDER", 1)
    b.accent:SetPoint("TOPLEFT"); b.accent:SetPoint("BOTTOMLEFT"); b.accent:SetWidth(3)
    b.accent:Hide()
    local hl = Skin.New(b, "RowHL", "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    Interactive(b)
    return b
end

-- Mobs in the left page's list: portrait, name, a line of details.
B.boss = {
    new = function(parent)
        local b = BarRow(parent, 44)
        b.portrait = Skin.Portrait(b, 32)
        b.portrait:SetPoint("LEFT", 10, 0)
        b.name = W.Text(b, W.Font("GameFontNormalMed3", "GameFontNormal"))
        b.name:SetPoint("TOPLEFT", 54, -7)
        b.name:SetPoint("RIGHT", -56, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.sub = W.Text(b, "GameFontHighlightSmall")
        b.sub:SetPoint("BOTTOMLEFT", 54, 8)
        b.sub:SetPoint("RIGHT", -12, 0)
        b.sub:SetJustifyH("LEFT")
        b.sub:SetWordWrap(false)
        b.right = W.Text(b, "GameFontNormal")
        b.right:SetPoint("RIGHT", -12, 0)
        return b
    end,
    set = function(b, r, width)
        b:SetWidth(width)
        b.name:SetText(r.text or "")
        TextColor(b.name, r.color, "boss")
        b.sub:SetText(r.sub or "")
        Skin.Color(b.sub, "bossSub")
        b.right:SetText(r.right or "")
        Skin.Color(b.right, "boss")
        b.sel:SetShown(r.selected and true or false)
        b.accent:SetShown(r.selected and true or false)
        Skin.SetPortrait(b.portrait, r.portrait, r.icon)
        return 44, 0
    end,
    gap = 3,
}

-- Items, mobs on the right page, and things a trainer teaches: icon, name and a line of details
-- on the left, two values on the right.
local function IconRow(parent, round)
    local b = BarRow(parent, 40)
    if round then
        b.icon = Skin.Portrait(b, 30)
        b.icon:SetPoint("LEFT", 8, 0)
    else
        b.edge = Skin.New(b, "IconEdge", "ARTWORK")
        b.edge:SetSize(34, 34)
        b.edge:SetPoint("LEFT", 3, 0)
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetSize(30, 30)
        b.icon:SetPoint("CENTER", b.edge)
    end
    b.name = W.Text(b, W.Font("GameFontNormalMed3", "GameFontNormal"))
    b.name:SetPoint("TOPLEFT", 46, -6)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.sub = W.Text(b, "GameFontHighlightSmall")
    b.sub:SetPoint("BOTTOMLEFT", 46, 7)
    b.sub:SetJustifyH("LEFT")
    b.sub:SetWordWrap(false)
    b.mid = W.Text(b, W.Font("GameFontNormalMed3", "GameFontNormal"))
    b.mid:SetPoint("TOPRIGHT", -10, -6)
    b.mid:SetJustifyH("RIGHT")
    b.right = W.Text(b, "GameFontHighlightSmall")
    b.right:SetPoint("BOTTOMRIGHT", -10, 7)
    b.right:SetJustifyH("RIGHT")
    b.name:SetPoint("RIGHT", b.mid, "LEFT", -8, 0)
    b.sub:SetPoint("RIGHT", b.right, "LEFT", -8, 0)
    return b
end

local function SetIconRow(b, r, width, round)
    b:SetWidth(width)
    if round then
        Skin.SetPortrait(b.icon, r.portrait, r.icon)
    else
        W.SetIcon(b.icon, r.icon)
        local hex = r.quality and r.quality >= 2 and SB.QUALITY_HEX[r.quality]
        if hex then
            b.edge:SetColorTexture(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1)
        else
            Skin.Apply(b.edge, "IconEdge")
        end
    end
    b.name:SetText(r.text or "")
    TextColor(b.name, r.color, r.faded and "lootSub" or "light")
    b.sub:SetText(r.sub or "")
    Skin.Color(b.sub, "lootSub")
    b.mid:SetText(r.mid or "")
    Skin.Color(b.mid, "lootMid")
    b.right:SetText(r.right or "")
    TextColor(b.right, r.rightColor, "you")
    return 40, 0
end

B.item = { new = function(p) return IconRow(p, false) end, set = function(b, r, w) return SetIconRow(b, r, w, false) end, gap = 3 }
B.teach = B.item
B.npc = { new = function(p) return IconRow(p, true) end, set = function(b, r, w) return SetIconRow(b, r, w, true) end, gap = 3 }

-- Section headers, and abilities that open to show their description.
B.header = {
    new = function(parent)
        local b = CreateFrame("Button", nil, parent)
        b:SetHeight(26)
        Skin.PaperHeader(b, false)
        Skin.PaperHeader(b, true)
        b.expand = W.Text(b, "GameFontNormalLarge")
        b.expand:SetPoint("LEFT", 8, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        b.title = W.Text(b, "GameFontNormal")
        b.title:SetJustifyH("LEFT")
        b.title:SetWordWrap(false)
        b.right = W.Text(b, "GameFontHighlightSmall")
        b.right:SetPoint("RIGHT", -10, 0)
        Interactive(b)
        return b
    end,
    set = function(b, r, width)
        b:SetWidth(width)
        local x = 10
        if r.kind == "spell" then
            b.expand:SetText(r.expanded and "-" or "+")
            b.expand:Show()
            x = 26
        else
            b.expand:Hide()
        end
        if r.icon then
            b.icon:SetTexture(r.icon)
            b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            b.icon:SetPoint("LEFT", x, 0)
            b.icon:Show()
            x = x + 24
        else
            b.icon:Hide()
        end
        b.title:ClearAllPoints()
        b.title:SetPoint("LEFT", x, 0)
        b.title:SetPoint("RIGHT", b.right, "LEFT", -8, 0)
        b.title:SetText(r.text or "")
        TextColor(b.title, r.color, r.kind == "spell" and "light" or "header")
        b.right:SetText(r.right or "")
        Skin.Color(b.right, "lootSub")
        b:EnableMouse((r.onClick or r.tooltip or r.kind == "spell") and true or false)
        return 26, 0
    end,
    gap = 3, before = 8,
}
B.spell = { new = B.header.new, set = B.header.set, gap = 3 }

-- Notes and descriptions: ink on a light paper backing.
B.text = {
    new = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.bg = Skin.Paper(f)
        f.bg:SetAllPoints()
        f.text = W.Text(f, BODY)
        f.text:SetPoint("TOPLEFT", 8, -5)
        f.text:SetJustifyH("LEFT")
        f.text:SetJustifyV("TOP")
        f.text:SetSpacing(2)
        return f
    end,
    set = function(f, r, width)
        local indent = r.indent or 0
        f:SetWidth(width - indent)
        f.text:SetWidth(width - indent - 16)
        f.text:SetText(r.text or "")
        TextColor(f.text, r.color, "text")
        local h = (f.text:GetStringHeight() or 14) + 10
        f:SetHeight(h)
        return h, indent
    end,
    gap = 3,
}
B.columns = B.text

-- Label and value, as a table row on a dark bar.
B.kv = {
    new = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        Skin.Bar(f, "RowBg")
        f.key = W.Text(f, "GameFontNormal")
        f.key:SetPoint("TOPLEFT", 10, -5)
        f.key:SetWidth(128)
        f.key:SetJustifyH("LEFT")
        f.key:SetWordWrap(false)
        f.value = W.Text(f, "GameFontHighlight")
        f.value:SetPoint("TOPLEFT", 144, -5)
        f.value:SetJustifyH("LEFT")
        f.value:SetJustifyV("TOP")
        return f
    end,
    set = function(f, r, width)
        f:SetWidth(width)
        f.key:SetText(r.key or "")
        Skin.Color(f.key, "lootMid")
        f.value:SetWidth(width - 154)
        f.value:SetText(r.text or "")
        TextColor(f.value, r.color, "light")
        local h = math.max(24, (f.value:GetStringHeight() or 14) + 10)
        f:SetHeight(h)
        return h, 0
    end,
    gap = 1,
}

-- One-line rows with a small icon: quests, zones, links.
B.line = {
    new = function(parent)
        local b = BarRow(parent, 26)
        b.expand = W.Text(b, "GameFontNormalLarge")
        b.expand:SetPoint("LEFT", 8, 0)
        b.expand:SetWidth(12)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.text = W.Text(b, "GameFontHighlight")
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b.mid = W.Text(b, "GameFontHighlightSmall")
        b.mid:SetJustifyH("RIGHT")
        b.right = W.Text(b, "GameFontNormalSmall")
        b.right:SetPoint("RIGHT", -10, 0)
        b.right:SetJustifyH("RIGHT")
        b.mid:SetPoint("RIGHT", b.right, "LEFT", -10, 0)
        b.text:SetPoint("RIGHT", b.mid, "LEFT", -8, 0)
        return b
    end,
    set = function(b, r, width)
        b:SetWidth(width)
        b.icon:ClearAllPoints()
        if r.expandable then
            b.expand:SetText(r.expanded and "-" or "+")
            Skin.Color(b.expand, "header")
            b.expand:Show()
            b.icon:SetPoint("LEFT", 24, 0)
        else
            b.expand:Hide()
            b.icon:SetPoint("LEFT", 8, 0)
        end
        if r.icon then b.icon:SetTexture(r.icon); b.icon:SetTexCoord(0, 1, 0, 1); b.icon:Show() else b.icon:Hide() end
        b.sel:SetShown(r.expanded and true or false)
        b.accent:SetShown(r.expanded and true or false)
        b.text:SetText(r.text or "")
        TextColor(b.text, r.color, "light")
        b.mid:SetText(r.mid or "")
        Skin.Color(b.mid, "lootSub")
        b.right:SetText(r.right or "")
        TextColor(b.right, r.rightColor, "key")
        b:EnableMouse((r.onClick or r.tooltip) and true or false)
        return 26, 0
    end,
    gap = 1,
}
B.quest = B.line
B.zone = B.line

-- A skill bar like the ones in the game's skill window: "Fishing  [#####   37 / 75]".
B.bar = {
    new = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f:SetHeight(28)
        Skin.Bar(f, "RowBg")
        f.label = W.Text(f, "GameFontNormal")
        f.label:SetPoint("LEFT", 10, 0)
        f.label:SetWidth(150)
        f.label:SetJustifyH("LEFT")
        f.label:SetWordWrap(false)
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetPoint("LEFT", 166, 0)
        bar:SetPoint("RIGHT", -10, 0)
        bar:SetHeight(16)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        local bg = Skin.New(bar, "BarBg", "BACKGROUND")
        bg:SetAllPoints()
        f.bar = bar
        f.value = W.Text(bar, "GameFontHighlightSmall")
        f.value:SetPoint("CENTER", 0, 1)
        return f
    end,
    set = function(f, r, width)
        f:SetWidth(width)
        f.label:SetText(r.text or "")
        Skin.Color(f.label, "header")
        local max = math.max(1, r.max or 1)
        f.bar:SetMinMaxValues(0, max)
        f.bar:SetValue(math.min(r.value or 0, max))
        if r.value then
            f.bar:SetStatusBarColor(0.1, 0.42, 0.95, 1)
            f.value:SetText(("%d / %d"):format(r.value, r.max or r.value))
            f.value:SetTextColor(1, 1, 1)
        else
            f.bar:SetStatusBarColor(0.4, 0.1, 0.1, 1)
            f.value:SetText(r.missing or "Not learned")
            f.value:SetTextColor(1, 0.35, 0.35)
        end
        return 28, 0
    end,
    gap = 3,
}

-- Filter chips: toggles on one or more lines, with an optional Reset at the end.
-- row.chips = { { text, color = {r,g,b}, on = bool, onClick = fn, tip = "..." }, ... }
B.filters = {
    new = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.chips = {}
        return f
    end,
    set = function(f, r, width)
        f:SetWidth(width)
        local x, y, lineH = 0, 0, 24
        for i, c in ipairs(r.chips or {}) do
            local chip = f.chips[i]
            if not chip then
                chip = CreateFrame("Button", nil, f)
                chip:SetHeight(22)
                Skin.Bar(chip, "RowBg")
                chip.mark = chip:CreateTexture(nil, "ARTWORK")
                chip.mark:SetPoint("BOTTOMLEFT", 1, 1)
                chip.mark:SetPoint("BOTTOMRIGHT", -1, 1)
                chip.mark:SetHeight(2)
                local hl = Skin.New(chip, "RowHL", "HIGHLIGHT")
                hl:SetAllPoints()
                chip.text = W.Text(chip, "GameFontHighlightSmall")
                chip.text:SetPoint("CENTER", 0, 1)
                chip:SetScript("OnClick", function(self) if self.def and self.def.onClick then self.def.onClick() end end)
                chip:SetScript("OnEnter", function(self)
                    if self.def and self.def.tip then W.Tooltip(self, self.def.text, self.def.tip) end
                end)
                chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
                f.chips[i] = chip
            end
            chip.def = c
            chip.text:SetText(c.text or "")
            local col = c.color or { 1, 0.82, 0 }
            if c.on then
                chip.text:SetTextColor(col[1], col[2], col[3])
                chip.mark:SetColorTexture(col[1], col[2], col[3], 1)
                chip:SetAlpha(1)
            else
                chip.text:SetTextColor(0.78, 0.78, 0.78)
                chip.mark:SetColorTexture(0, 0, 0, 0)
                chip:SetAlpha(0.8)
            end
            local w = math.floor((chip.text:GetStringWidth() or 50) + 18)
            if x > 0 and x + w > width then x, y = 0, y + lineH end
            chip:SetWidth(w)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", x, -y)
            chip:Show()
            x = x + w + 4
        end
        for i = #(r.chips or {}) + 1, #f.chips do f.chips[i]:Hide() end
        f:SetHeight(y + lineH)
        return y + lineH, 0
    end,
    gap = 4,
}

-- Instance tiles, as in the journal's dungeon and raid grid.
local TILE_W, TILE_H = 174, 96
local function Tile(f)
    local t = CreateFrame("Button", nil, f)
    t:SetSize(TILE_W, TILE_H)
    t.art = t:CreateTexture(nil, "BACKGROUND")
    t.art:SetAllPoints()
    t.portrait = Skin.Portrait(t, 40)
    t.portrait:SetPoint("BOTTOMRIGHT", -14, 12)
    t.frame = Skin.New(t, "DungeonButtonUp", "BORDER")
    t.frame:SetAllPoints()
    t.hl = Skin.New(t, "DungeonButtonHL", "HIGHLIGHT")
    t.hl:SetAllPoints()
    t.name = W.Text(t, W.Font("QuestTitleFontBlackShadow", "GameFontNormalLarge"))
    t.name:SetPoint("TOP", 0, -15)
    t.name:SetWidth(150)
    t.name:SetTextColor(1, 0.92, 0.75)
    t.sub = W.Text(t, "GameFontNormal")
    t.sub:SetPoint("BOTTOMLEFT", 9, 9)
    t:SetScript("OnEnter", RowTooltip)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    t:SetScript("OnClick", RowClick)
    return t
end

B.tiles = {
    new = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.tiles = {}
        return f
    end,
    set = function(f, r, width)
        local per = r.perRow or #r.tiles
        local gap = math.max(6, math.floor((width - per * TILE_W) / (per + 1)))
        f:SetSize(width, TILE_H)
        for i, d in ipairs(r.tiles) do
            local t = f.tiles[i]
            if not t then t = Tile(f); f.tiles[i] = t end
            t.row = d
            t:Show()
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", gap + (i - 1) * (TILE_W + gap), 0)
            if d.art then
                t.art:SetTexture(d.art)
                t.art:SetTexCoord(0, 0.68359375, 0, 0.7421875)
                t.portrait:Hide(); t.portrait.ring:Hide()
            else
                Skin.Apply(t.art, "RowBg")
                t.portrait:Show(); t.portrait.ring:Show()
                Skin.SetPortrait(t.portrait, d.portrait, d.icon)
            end
            t.name:SetText(d.text or "")
            t.sub:SetText(d.sub or "")
        end
        for i = #r.tiles + 1, #f.tiles do f.tiles[i]:Hide(); f.tiles[i].row = nil end
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
            if b.before and i > 1 and not r.inset then y = y + b.before end
            local inset = r.inset or 0
            local h, x = b.set(f, r, width - inset)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self.child, "TOPLEFT", (x or 0) + inset, -y)
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
