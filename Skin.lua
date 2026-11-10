-- Look and feel. The "journal" style uses the game's own Adventure Guide (Encounter Journal)
-- art: the open-book background, boss buttons, loot frames, paper headers and side tabs.
-- WoW: Forever ships that journal, so the textures are in the client. The "dark" style is a
-- plain fallback for clients that don't have them (pick it in the settings).

local _, SB = ...
local Skin = {}
SB.Skin = Skin

local F = "Interface\\EncounterJournal\\UI-EncounterJournalTextures"
local FT = "Interface\\EncounterJournal\\UI-EncounterJournalTextures_Tile"

-- name = { file, width, height, left, right, top, bottom }   (from Blizzard_EncounterJournal.xml)
Skin.TEX = {
    BossButtonUp        = { F, 325, 55, 0.00195313, 0.63671875, 0.21386719, 0.26757813 },
    BossButtonDown      = { F, 325, 55, 0.00195313, 0.63671875, 0.10253906, 0.15625000 },
    BossButtonHighlight = { F, 325, 55, 0.00195313, 0.63671875, 0.15820313, 0.21191406 },
    LootFrame           = { F, 321, 45, 0.00195313, 0.62890625, 0.61816406, 0.66210938 },
    TabUnselected       = { F, 63, 57, 0.25585938, 0.37890625, 0.90332031, 0.95898438 },
    TabSelected         = { F, 63, 57, 0.12890625, 0.25195313, 0.90332031, 0.95898438 },
    TabHighlight        = { F, 63, 57, 0.00195313, 0.12500000, 0.90332031, 0.95898438 },
    TabBossOff          = { F, 48, 43, 0.85546875, 0.94921875, 0.52441406, 0.56640625 },
    TabBossOn           = { F, 48, 43, 0.90234375, 0.99609375, 0.26953125, 0.31152344 },
    TabLootOff          = { F, 48, 43, 0.73046875, 0.82421875, 0.61816406, 0.66015625 },
    TabLootOn           = { F, 48, 43, 0.63281250, 0.72656250, 0.61816406, 0.66015625 },
    TabAbilitiesOff     = { F, 48, 43, 0.904296875, 0.99609375, 0.70703125, 0.748046875 },
    TabAbilitiesOn      = { F, 48, 43, 0.806640625, 0.8984375, 0.70703125, 0.748046875 },
    TabModelOff         = { F, 48, 43, 0.90234375, 1, 0.662109375, 0.705078125 },
    TabModelOn          = { F, 48, 43, 0.8046875, 0.900390625, 0.662109375, 0.705078125 },
    LeftPageHeader      = { F, 386, 39, 0, 0.755859375, 0.9599609375, 1 },
    RightPageHeader     = { F, 386, 39, 0.755859375, 0, 0.9599609375, 1 },
    PaperLeft           = { F, 64, 29, 0.84960938, 0.97460938, 0.49023438, 0.51855469 },
    PaperRight          = { F, 64, 29, 0.72656250, 0.85156250, 0.52441406, 0.55273438 },
    PaperMid            = { FT, 64, 29, 0, 1, 0.34375000, 0.40039063, tile = true },
    PaperHLLeft         = { F, 64, 29, 0.74218750, 0.86718750, 0.15820313, 0.18652344 },
    PaperHLRight        = { F, 64, 29, 0.87109375, 0.99609375, 0.15820313, 0.18652344 },
    PaperHLMid          = { FT, 64, 29, 0, 1, 0.46484375, 0.52148438, tile = true },
    AbilityIconBorder   = { F, 20, 20, 0.00195313, 0.04101563, 0.00097656, 0.02050781 },
    DungeonButtonUp     = { F, 174, 96, 0.00195313, 0.34179688, 0.42871094, 0.52246094 },
    DungeonButtonHL     = { F, 174, 96, 0.34570313, 0.68554688, 0.33300781, 0.42675781 },
    DungeonNameBg       = { F, 256, 64, 0.34570313, 0.84570313, 0.42871094, 0.49121094 },
    BossNameShadow      = { F, 395, 63, 0.00195313, 0.77343750, 0.26953125, 0.33105469 },
    HeaderOverview      = { F, 327, 30, 0.359375, 0.99609375, 0.8525390625, 0.880859375 },
    JournalBG           = { "Interface\\EncounterJournal\\UI-EJ-JournalBG", 785, 425, 0, 0.766601562, 0, 0.830078125 },
    DungeonBG           = { "Interface\\EncounterJournal\\UI-EJ-BACKGROUND-Default", 394, 425, 0.76953125, 0, 0, 0.830078125 },
    ModelPaperFrame     = { "Interface\\EncounterJournal\\UI-EJ-BossModelPaperFrame", 393, 424, 0.767578125, 0, 0, 0.828125 },
}

-- plain colors for the dark style: r, g, b, a
local DARK = {
    BossButtonUp = { 0.12, 0.09, 0.06, 0.95 }, BossButtonDown = { 0.2, 0.14, 0.08, 1 }, BossButtonHighlight = { 1, 0.8, 0.5, 0.12 },
    LootFrame = { 0.1, 0.1, 0.12, 0.9 }, TabUnselected = { 0.12, 0.1, 0.08, 0.95 }, TabSelected = { 0.3, 0.2, 0.08, 1 },
    TabHighlight = { 1, 1, 1, 0.1 }, LeftPageHeader = { 0, 0, 0, 0.5 }, RightPageHeader = { 0, 0, 0, 0.5 },
    PaperLeft = { 0.25, 0.17, 0.08, 0.9 }, PaperRight = { 0.25, 0.17, 0.08, 0.9 }, PaperMid = { 0.25, 0.17, 0.08, 0.9 },
    PaperHLLeft = { 1, 1, 1, 0.08 }, PaperHLRight = { 1, 1, 1, 0.08 }, PaperHLMid = { 1, 1, 1, 0.08 },
    DungeonButtonUp = { 0, 0, 0, 0 }, DungeonButtonHL = { 1, 1, 1, 0.12 }, DungeonNameBg = { 0, 0, 0, 0.7 },
    BossNameShadow = { 0, 0, 0, 0.6 }, JournalBG = { 0.06, 0.06, 0.07, 0.97 }, DungeonBG = { 0.08, 0.08, 0.1, 1 },
    ModelPaperFrame = { 0, 0, 0, 0 }, HeaderOverview = { 0.25, 0.17, 0.08, 0.9 },
}

-- colors per style
local PALETTE = {
    journal = {
        -- ink on the parchment
        text = { 0.18, 0.1, 0.02 },           -- dark brown body text
        dim = { 0.33, 0.22, 0.1 },
        key = { 0.42, 0.18, 0.0 },
        good = { 0.05, 0.36, 0.02 }, warn = { 0.5, 0.25, 0 }, off = { 0.4, 0.35, 0.3 },
        -- light text on the dark bands, boss buttons and loot frames
        title = { 0.96, 0.87, 0.72 },         -- page titles on the header band
        boss = { 1, 0.86, 0.6 },              -- names on boss buttons
        bossSub = { 0.9, 0.82, 0.68 },
        header = { 1, 0.82, 0 },              -- text on paper headers
        lootSub = { 0.88, 0.8, 0.66 },
        lootMid = { 1, 0.92, 0.7 },
        you = { 0.55, 0.85, 1 },
    },
    dark = {
        text = { 0.9, 0.9, 0.9 }, dim = { 0.65, 0.65, 0.65 }, key = { 1, 0.82, 0 },
        title = { 1, 0.82, 0 }, boss = { 1, 0.86, 0.6 }, bossSub = { 0.75, 0.75, 0.75 }, header = { 1, 0.82, 0 },
        good = { 0.4, 1, 0.4 }, warn = { 1, 0.82, 0 }, off = { 0.55, 0.55, 0.55 }, you = { 0.55, 0.85, 1 },
        lootSub = { 0.75, 0.75, 0.75 }, lootMid = { 1, 0.92, 0.7 },
    },
}

function Skin.Journal()
    return not SB.db or SB.db.style ~= "dark"
end

function Skin.C(name)
    return (Skin.Journal() and PALETTE.journal or PALETTE.dark)[name]
end

-- Colors a FontString. Dark ink on parchment gets no drop shadow (it smudges); light text keeps one.
function Skin.Ink(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
    if fs.SetShadowColor then
        if c[1] + c[2] + c[3] < 1.3 then fs:SetShadowColor(0, 0, 0, 0) else fs:SetShadowColor(0, 0, 0, 1) end
    end
end

function Skin.Color(fs, name)
    Skin.Ink(fs, Skin.C(name))
end

function Skin.Hex(name)
    local c = Skin.C(name)
    return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Paints a texture with a journal piece (or its dark-style color). sized = also set its size.
function Skin.Apply(tex, name, sized)
    local t = Skin.TEX[name]
    if Skin.Journal() and t then
        tex:SetTexture(t[1], t.tile and "REPEAT" or nil)
        tex:SetTexCoord(t[4], t[5], t[6], t[7])
        if t.tile and tex.SetHorizTile then tex:SetHorizTile(true) end
        tex:SetVertexColor(1, 1, 1, 1)
    else
        local c = DARK[name] or { 0, 0, 0, 0.5 }
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    if sized and t then tex:SetSize(t[2], t[3]) end
    return tex
end

function Skin.New(parent, name, layer, sub, sized)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    tex.skin = name
    Skin.Apply(tex, name, sized)
    return tex
end

-- Re-applies every skinned texture under a frame (after switching style).
function Skin.Refresh(frame)
    if not frame or not frame.GetRegions then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.skin then Skin.Apply(r, r.skin) end
    end
    for _, c in ipairs({ frame:GetChildren() }) do Skin.Refresh(c) end
end

-- A paper header bar (left cap, tiled middle, right cap) like the journal's ability headers.
function Skin.PaperHeader(frame, highlight)
    local l = Skin.New(frame, highlight and "PaperHLLeft" or "PaperLeft", highlight and "HIGHLIGHT" or "BACKGROUND")
    l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(32)
    local r = Skin.New(frame, highlight and "PaperHLRight" or "PaperRight", highlight and "HIGHLIGHT" or "BACKGROUND")
    r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(32)
    local m = Skin.New(frame, highlight and "PaperHLMid" or "PaperMid", highlight and "HIGHLIGHT" or "BACKGROUND")
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
end

-- A round portrait of a creature (from its display ID), or a round icon.
function Skin.Portrait(parent, size)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size, size)
    if parent.CreateMaskTexture then
        local ok = pcall(function()
            local mask = parent:CreateMaskTexture()
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(tex)
            tex:AddMaskTexture(mask)
        end)
        tex.masked = ok
    end
    local ring = parent:CreateTexture(nil, "OVERLAY")
    ring:SetPoint("CENTER", tex)
    ring:SetSize(size * 1.28, size * 1.28)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("adventureguide-ring") then
        ring:SetAtlas("adventureguide-ring")
    else
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetTexCoord(0, 0.6, 0, 0.6)
    end
    tex.ring = ring
    return tex
end

function Skin.SetPortrait(tex, displayID, fallbackIcon)
    if displayID and displayID > 0 and SetPortraitTextureFromCreatureDisplayID then
        tex:SetTexCoord(0, 1, 0, 1)
        if pcall(SetPortraitTextureFromCreatureDisplayID, tex, displayID) then return end
    end
    tex:SetTexture(fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

------------------------------------------------------------------------------
-- Adventure Guide data for instances: button art, background and lore, by game map ID.
------------------------------------------------------------------------------

local journal
function Skin.InstanceArt(mapID)
    if journal == nil then
        journal = {}
        if EJ_GetInstanceByIndex and EJ_GetNumTiers and EJ_SelectTier then
            pcall(function()
                local current = EJ_GetCurrentTier and EJ_GetCurrentTier()
                for tier = 1, EJ_GetNumTiers() or 0 do
                    EJ_SelectTier(tier)
                    for _, raid in ipairs({ false, true }) do
                        local i = 1
                        while true do
                            local id, name, desc, bg, button, lore, _, _, _, _, map = EJ_GetInstanceByIndex(i, raid)
                            if not id then break end
                            if map and not journal[map] then
                                journal[map] = { id = id, name = name, description = desc, bg = bg, button = button, lore = lore, raid = raid }
                            end
                            i = i + 1
                        end
                    end
                end
                if current then EJ_SelectTier(current) end
            end)
        end
    end
    return journal[mapID]
end
