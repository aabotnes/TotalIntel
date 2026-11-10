-- Minimap button: left-click opens the window on your target, right-click opens the settings,
-- drag to move it around the minimap.

local _, SB = ...
local btn

local function UpdatePosition()
    local angle = math.rad(SB.db.minimap.angle or 215)
    local radius = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    SB.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
    UpdatePosition()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(SB.TITLE)
    local kills, mobs = 0, 0
    for _, m in pairs(SB.db.mobs) do
        if (m.k or 0) > 0 then mobs = mobs + 1; kills = kills + m.k end
    end
    GameTooltip:AddLine(("Your bestiary: %s, %s"):format(SB.Plural(mobs, "mob"), SB.Plural(kills, "kill")), 0.53, 0.8, 1)
    if not SB.db.learn then GameTooltip:AddLine("Recording is off (/tits learn)", 1, 0.3, 0.3) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open (on your target)", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: settings", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Create()
    if btn or not Minimap then return end
    btn = CreateFrame("Button", "TotalIntelMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(21, 21)
    btn.icon:SetPoint("TOPLEFT", 6, -5)
    btn.icon:SetTexture(SB.ICON)
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    btn:SetScript("OnClick", function(_, button)
        GameTooltip:Hide()
        if button == "RightButton" then SB.OpenSettings() else SB.Toggle() end
    end)
    btn:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", ShowTooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    btn:SetShown(not SB.db.minimap.hide)
end

function SB.UpdateMinimap()
    if btn then btn:SetShown(not SB.db.minimap.hide) end
end

SB.On("PLAYER_LOGIN", Create)
