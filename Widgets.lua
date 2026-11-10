-- Widget helpers shared by the window and the settings page, plus the Wowhead link popup.

local _, SB = ...
local W = {}
SB.W = W

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

function W.Panel(parent, alpha)
    local p = CreateFrame("Frame", nil, parent)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, alpha or 0.35)
    p.bg = bg
    local edges = {
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }
    for _, e in ipairs(edges) do
        local line = p:CreateTexture(nil, "BORDER")
        line:SetColorTexture(1, 1, 1, 0.07)
        line:SetPoint(e[1])
        line:SetPoint(e[2])
        if e[3] then line:SetWidth(e[3]) else line:SetHeight(e[4]) end
    end
    return p
end

function W.Button(parent, text, width, height, onClick)
    local b, tpl = W.CreateWithTemplate("Button", nil, parent, { "UIPanelButtonTemplate", "UIPanelDynamicResizeButtonTemplate" })
    b:SetSize(width, height or 22)
    if not tpl then
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.35, 0.2, 0.05, 0.9)
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
    c:SetSize(22, 22)
    if not tpl then
        c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    c.label = W.Text(c, "GameFontHighlightSmall")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 1)
    c.label:SetText(label)
    c:SetHitRectInsets(0, -c.label:GetStringWidth() - 4, 0, 0)
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    c:SetScript("OnEnter", function(self) if tooltip then W.Tooltip(self, label, tooltip) end end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.Refresh = function(self) self:SetChecked(get() and true or false) end
    return c
end

-- A button that cycles through choices: { {value, "Label"}, ... }
function W.Cycle(parent, label, tooltip, choices, get, set, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize((width or 150) + 120, 22)
    f.label = W.Text(f, "GameFontHighlightSmall")
    f.label:SetPoint("LEFT", 2, 0)
    f.label:SetText(label)
    f.button = W.Button(f, "", width or 150, 20, function()
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
    end
    return f
end

-- [-] n [+]
function W.Stepper(parent, label, min, max, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(200, 22)
    f.label = W.Text(f, "GameFontHighlightSmall")
    f.label:SetPoint("LEFT", 2, 0)
    f.label:SetText(label)
    f.minus = W.Button(f, "-", 22, 20, function() set(math.max(min, get() - 1)); f:Refresh() end)
    f.minus:SetPoint("LEFT", f.label, "RIGHT", 8, 0)
    f.value = W.Text(f, "GameFontHighlight")
    f.value:SetPoint("LEFT", f.minus, "RIGHT", 4, 0)
    f.value:SetWidth(24)
    f.plus = W.Button(f, "+", 22, 20, function() set(math.min(max, get() + 1)); f:Refresh() end)
    f.plus:SetPoint("LEFT", f.value, "RIGHT", 4, 0)
    f.Refresh = function(self) self.value:SetText(tostring(get())) end
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

------------------------------------------------------------------------------
-- Scrolling row list
--
-- rows are tables: { kind = "header"|"text"|"kv"|"item"|"npc"|"spell"|"quest"|"columns",
--                    text/left, mid, right, icon, color, id, onClick, tooltip = fn(row) }
------------------------------------------------------------------------------

local ROW_H = 20

local function RowTooltip(btn)
    local r = btn.row
    if not r then return end
    if r.kind == "item" and r.id then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetItemByID, GameTooltip, r.id)
        if not ok then GameTooltip:AddLine(SB.ItemText(r.id)) end
        GameTooltip:AddLine("|cff888888Click: open its page · Shift-click: link in chat|r")
        GameTooltip:Show()
    elseif r.kind == "spell" and r.id then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, r.id)
        if not ok then GameTooltip:AddLine(SB.SpellInfo(r.id) or ("Spell " .. r.id), 1, 1, 1) end
        if r.note then GameTooltip:AddLine(r.note, 0.53, 0.8, 1, true) end
        GameTooltip:AddLine("|cff888888Spell " .. r.id .. " · Click: Wowhead link · Shift-click: link in chat|r")
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
        local link = it.link or select(2, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(r.id))
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

function W.RowList(parent)
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.buttons, list.offset = {}, {}, 0

    list.bar = CreateFrame("Slider", nil, list)
    list.bar:SetWidth(8)
    list.bar:SetPoint("TOPRIGHT", 0, 0)
    list.bar:SetPoint("BOTTOMRIGHT", 0, 0)
    list.bar:SetOrientation("VERTICAL")
    local track = list.bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.05)
    local thumb = list.bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 0.6, 0.2, 0.6)
    thumb:SetSize(8, 30)
    list.bar:SetThumbTexture(thumb)
    list.bar:SetValueStep(1)
    list.bar:SetScript("OnValueChanged", function(_, v)
        v = math.floor((v or 0) + 0.5)
        if v ~= list.offset then list.offset = v; list:Draw() end
    end)

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list:Scroll(-delta * 3)
    end)

    function list:Visible()
        return math.max(1, math.floor((self:GetHeight() or 300) / ROW_H))
    end

    function list:MaxOffset()
        return math.max(0, #self.rows - self:Visible())
    end

    function list:Scroll(delta)
        local o = math.max(0, math.min(self:MaxOffset(), self.offset + delta))
        if o ~= self.offset then
            self.offset = o
            self.bar:SetValue(o)
            self:Draw()
        end
    end

    function list:Button(i)
        local b = self.buttons[i]
        if b then return b end
        b = CreateFrame("Button", nil, self)
        b:SetHeight(ROW_H)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        b:SetPoint("RIGHT", self.bar, "LEFT", -4, 0)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.06)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 4, 0)
        b.left = W.Text(b, "GameFontHighlightSmall")
        b.left:SetJustifyH("LEFT")
        b.left:SetWordWrap(false)
        b.right = W.Text(b, "GameFontHighlightSmall")
        b.right:SetPoint("RIGHT", -6, 0)
        b.right:SetJustifyH("RIGHT")
        b.right:SetWidth(90)
        b.mid = W.Text(b, "GameFontHighlightSmall")
        b.mid:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
        b.mid:SetJustifyH("RIGHT")
        b.mid:SetWidth(110)
        b:SetScript("OnEnter", RowTooltip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", RowClick)
        self.buttons[i] = b
        return b
    end

    function list:SetRows(rows, keepOffset)
        self.rows = rows or {}
        if not keepOffset then self.offset = 0 end
        self.offset = math.min(self.offset, self:MaxOffset())
        self.bar:SetMinMaxValues(0, self:MaxOffset())
        self.bar:SetValue(self.offset)
        self.bar:SetShown(self:MaxOffset() > 0)
        self:Draw()
    end

    function list:Draw()
        local vis = self:Visible()
        for i = 1, vis do
            local b = self:Button(i)
            local r = self.rows[i + self.offset]
            b.row = r
            if not r then
                b:Hide()
            else
                b:Show()
                b.left:ClearAllPoints()
                b.left:SetPoint("RIGHT", (r.mid or r.right) and b.mid or b, (r.mid or r.right) and "LEFT" or "RIGHT", -6, 0)
                b.bg:SetColorTexture(0, 0, 0, 0)
                b.left:SetFontObject("GameFontHighlightSmall")
                if r.icon then
                    b.icon:Show()
                    W.SetIcon(b.icon, r.icon)
                    b.left:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
                else
                    b.icon:Hide()
                    b.left:SetPoint("LEFT", (r.kind == "header" or r.kind == "columns") and 4 or (r.indent or 8), 0)
                end
                if r.kind == "header" then
                    b.left:SetFontObject("GameFontNormal")
                    b.bg:SetColorTexture(1, 0.6, 0.2, 0.08)
                end
                local c = r.color
                if c then b.left:SetTextColor(c[1], c[2], c[3]) else b.left:SetTextColor(1, 1, 1) end
                if r.kind == "kv" then
                    b.left:SetText("|cffffd100" .. (r.key or "") .. "|r  " .. (r.text or ""))
                else
                    b.left:SetText(r.text or "")
                end
                b.mid:SetText(r.mid or "")
                b.right:SetText(r.right or "")
                if r.kind == "columns" then
                    b.left:SetTextColor(0.6, 0.6, 0.6)
                    b.mid:SetTextColor(0.6, 0.6, 0.6)
                    b.right:SetTextColor(0.6, 0.6, 0.6)
                else
                    b.mid:SetTextColor(0.8, 0.8, 0.8)
                    b.right:SetTextColor(0.53, 0.8, 1)
                end
                local interactive = r.onClick or r.tooltip or r.kind == "item" or r.kind == "spell"
                b:EnableMouse(interactive and true or false)
            end
        end
        for i = vis + 1, #self.buttons do self.buttons[i]:Hide() end
    end

    list:SetScript("OnSizeChanged", function(self) if self.rows then self:SetRows(self.rows, true) end end)
    return list
end

------------------------------------------------------------------------------
-- Wowhead link popup (the game can't open a browser, so you copy the link)
------------------------------------------------------------------------------

local popup
function SB.ShowLink(kind, id, label)
    if not popup then
        popup = W.CreateWithTemplate("Frame", "TotalIntelLinkFrame", UIParent, { "BasicFrameTemplateWithInset", "ButtonFrameTemplate" })
        popup:SetSize(460, 110)
        W.FixCloseButton(popup)
        popup:SetPoint("CENTER", 0, 120)
        popup:SetFrameStrata("DIALOG")
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        tinsert(UISpecialFrames, "TotalIntelLinkFrame")
        popup.title = W.Text(popup, "GameFontHighlight")
        popup.title:SetPoint("TOP", 0, -6)
        popup.hint = W.Text(popup, "GameFontNormalSmall")
        popup.hint:SetPoint("TOP", 0, -34)
        popup.hint:SetText("Press Ctrl+C to copy, then paste it in your browser.")
        local eb = CreateFrame("EditBox", nil, popup)
        eb:SetSize(420, 24)
        eb:SetPoint("TOP", 0, -56)
        eb:SetFontObject(ChatFontNormal)
        eb:SetAutoFocus(false)
        local bg = eb:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", -4, 2)
        bg:SetPoint("BOTTOMRIGHT", 4, -2)
        bg:SetColorTexture(0, 0, 0, 0.6)
        eb:SetScript("OnEscapePressed", function() popup:Hide() end)
        eb:SetScript("OnEnterPressed", function() popup:Hide() end)
        eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(popup.url); self:HighlightText() end end)
        eb:SetScript("OnKeyUp", function(_, key)
            if key == "C" and IsControlKeyDown() then
                SB.After(0.05, function() popup:Hide() end)
            end
        end)
        popup.edit = eb
    end
    popup.url = SB.WowheadURL(kind, id)
    popup.title:SetText("Wowhead: " .. (label or (kind .. " " .. id)))
    popup.edit:SetText(popup.url)
    popup:Show()
    popup.edit:SetFocus()
    popup.edit:HighlightText()
end
