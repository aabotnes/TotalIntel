-- Minimal WoW client mock for Super Bestiary's headless tests.
local M = { log = {}, now = 0, timers = {}, frames = {}, units = {}, quests = {}, loot = {}, secret = {} }

local NoOp = setmetatable({}, {})
getmetatable(NoOp).__call = function() return nil end
getmetatable(NoOp).__index = function() return NoOp end

local Widget = {}
local function NewWidget()
    local w = { _scripts = {}, _shown = false, _text = "", _checked = false, _events = {} }
    return setmetatable(w, { __index = function(_, k)
        if Widget[k] then return Widget[k] end
        if type(k) == "string" and k:match("^%u") then return NoOp end
        return nil
    end })
end
M.NewWidget = NewWidget
function Widget.SetScript(self, k, fn) self._scripts[k] = fn end
function Widget.HookScript(self, k, fn)
    local old = self._scripts[k]
    self._scripts[k] = old and function(...) old(...); fn(...) end or fn
end
function Widget.GetScript(self, k) return self._scripts[k] end
function Widget.Show(self) self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
function Widget.Hide(self) self._shown = false end
function Widget.IsShown(self) return self._shown end
function Widget.SetShown(self, v) if v then self:Show() else self:Hide() end end
function Widget.SetText(self, t) self._text = t end
function Widget.GetText(self) return self._text end
function Widget.SetChecked(self, v) self._checked = v end
function Widget.GetChecked(self) return self._checked end
function Widget.CreateFontString() return NewWidget() end
function Widget.CreateTexture() return NewWidget() end
function Widget.GetStringWidth() return 80 end
function Widget.GetHeight() return 300 end
function Widget.GetWidth() return 140 end
function Widget.GetCenter() return 0, 0 end
function Widget.GetEffectiveScale() return 1 end
function Widget.GetFrameLevel() return 1 end
function Widget.IsForbidden() return false end
function Widget.HasFocus() return false end
function Widget.RegisterEvent(self, ev)
    if ev == "COMBAT_LOG_EVENT_UNFILTERED" and M.noCombatLog then error("unknown event") end
    self._events[ev] = true
end
function Widget.Click(self, button) self._scripts.OnClick(self, button or "LeftButton") end

function CreateFrame(kind, name, parent, template)
    local w = NewWidget()
    w._kind = kind
    if template and template:find("FrameTemplate") then w.CloseButton = NewWidget() end
    M.frames[#M.frames + 1] = w
    if name then _G[name] = w end
    return w
end

function M.Fire(ev, ...)
    for _, fr in ipairs(M.frames) do
        if fr._events[ev] and fr._scripts.OnEvent then fr._scripts.OnEvent(fr, ev, ...) end
    end
end

C_Timer = { After = function(sec, fn) M.timers[#M.timers + 1] = { t = M.now + sec, fn = fn } end,
            NewTicker = function() return {} end }
function M.Advance(sec)
    local target = M.now + sec
    while true do
        table.sort(M.timers, function(a, b) return a.t < b.t end)
        local nxt = M.timers[1]
        if not nxt or nxt.t > target then break end
        table.remove(M.timers, 1)
        M.now = nxt.t
        nxt.fn()
    end
    M.now = target
end
function GetTime() return M.now end
time, date = os.time, os.date

function strsplit(sep, s)
    local out = {}
    for f in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = f end
    return unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
bit = { band = function(a, b)
    local r, bitv = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
        a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
    end
    return r
end }

-- secret values: anything registered in M.secret is "secret"
function issecretvalue(v) return M.secret[v] == true end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) M.log[#M.log + 1] = m end }
UIParent = NewWidget()
Minimap = NewWidget()
UISpecialFrames = {}
StaticPopupDialogs = {}
function StaticPopup_Show() end
SlashCmdList = {}
ChatFontNormal = {}
function hooksecurefunc(name, fn) local orig = _G[name]; _G[name] = function(...) orig(...); fn(...) end end
function HandleModifiedItemClick() end
function GetCursorPosition() return 10, 10 end
function IsShiftKeyDown() return M.shift or false end
function IsControlKeyDown() return M.ctrl or false end
function IsAltKeyDown() return M.alt or false end
function InCombatLockdown() return false end
function IsInInstance() return M.inInstance or false end
function IsStealthed() return M.stealthed or false end
function IsInGroup() return false end
function GetZoneText() return "Elwynn Forest" end
function GetBuildInfo() return "1.60.1", "70790", "Nov 3 2026", 16001 end
function GetCoinTextureString(c) return c .. "c" end

-- tooltips: record lines
local function NewTooltip()
    local tt = NewWidget()
    tt.lines = {}
    tt.AddLine = function(self, t) self.lines[#self.lines + 1] = tostring(t) end
    tt.AddDoubleLine = function(self, l, r) self.lines[#self.lines + 1] = tostring(l) .. " || " .. tostring(r) end
    tt.SetOwner = function(self) wipe(self.lines) end
    tt.GetUnit = function(self) return self.unitName, self.unit end
    return tt
end
GameTooltip = NewTooltip()
ItemRefTooltip = NewTooltip()
M.NewTooltip = NewTooltip

Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
M.postCalls = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) M.postCalls[kind] = fn end }

-- units: M.units[token] = { guid=, name=, player=, dead=, level= }
function UnitExists(u) return M.units[u] ~= nil end
function UnitGUID(u) return M.units[u] and M.units[u].guid end
function UnitName(u) return M.units[u] and M.units[u].name end
function UnitIsPlayer(u) return M.units[u] and M.units[u].player or false end
function UnitPlayerControlled(u) return UnitIsPlayer(u) end
function UnitIsDead(u) return M.units[u] and M.units[u].dead or false end
function UnitIsTapDenied() return false end
function UnitCanAttack() return true end
function UnitAffectingCombat(u) return M.units[u] and M.units[u].combat or false end
function UnitLevel(u) return u == "player" and (M.level or 12) or (M.units[u] and M.units[u].level or 1) end
function UnitClass() return "Rogue", "ROGUE", 4 end
function UnitFactionGroup() return M.faction or "Alliance", M.faction or "Alliance" end

-- quest log: M.quests = { {id, title, complete, objectives = {...}} }
C_QuestLog = {
    GetNumQuestLogEntries = function() return #M.quests end,
    GetInfo = function(i) local q = M.quests[i]; return q and { questID = q.id, title = q.title, isHeader = false } end,
    IsComplete = function(id) for _, q in ipairs(M.quests) do if q.id == id then return q.complete end end end,
    GetQuestObjectives = function(id) for _, q in ipairs(M.quests) do if q.id == id then return q.objectives end end end,
    IsQuestFlaggedCompleted = function(id) return M.done and M.done[id] or false end,
}

-- loot: M.loot = { {link=, qty=, sources = {guid, n, ...}} }
function GetNumLootItems() return #M.loot end
function GetLootSlotLink(i) return M.loot[i].link end
function GetLootSlotInfo(i) return nil, "item", M.loot[i].qty or 1 end
function GetLootSourceInfo(i) return unpack(M.loot[i].sources) end

C_Spell = { GetSpellInfo = function(id) return { name = "Spell" .. id, iconID = 136000 + (id % 100) } end }
C_Item = { GetItemInfo = function() return nil end, GetItemIconByID = function(id) return 130000 + (id % 1000) end }
C_Map = { GetBestMapForUnit = function() return 1429 end, GetMapInfo = function() return { name = "Elwynn Forest" } end }

function M.Load(dir, files)
    local SB = {}
    for _, f in ipairs(files) do
        local chunk = assert(loadfile(dir .. "/" .. f))
        chunk("SuperBestiary", SB)
    end
    M.Fire("ADDON_LOADED", "SuperBestiary")
    M.Fire("PLAYER_LOGIN")
    return SB
end

function M.TocFiles(dir)
    local files = {}
    for line in io.lines(dir .. "/SuperBestiary.toc") do
        if line:match("%.lua%s*$") and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", "")) end
    end
    return files
end

function M.Has(lines, pattern)
    for _, l in ipairs(lines) do if l:find(pattern) then return l end end
end

function M.check(cond, msg, lines)
    if not cond then
        print("FAIL: " .. msg)
        for _, l in ipairs(lines or M.log) do print("   | " .. l) end
        os.exit(1)
    end
    print("ok   " .. msg)
end

return M
