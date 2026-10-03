--[[
    Steal an Egg — Elite Menu
    Executor-ready single-file Luau
    Load: loadstring(game:HttpGet("<raw url>"))()
]]

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------
local Services = {}
for _, name in ipairs({
    "Players", "ReplicatedStorage", "ReplicatedFirst", "RunService",
    "UserInputService", "ContextActionService", "TweenService",
    "HttpService", "TeleportService", "Workspace", "Lighting",
    "StarterGui", "CoreGui", "VirtualUser", "GuiService",
}) do
    local ok, svc = pcall(function() return game:GetService(name) end)
    if ok and svc then Services[name] = svc end
end

local Players           = Services.Players
local RS                = Services.ReplicatedStorage
local RunService        = Services.RunService
local UIS               = Services.UserInputService
local TweenService      = Services.TweenService
local HttpService       = Services.HttpService
local Workspace         = Services.Workspace
local CoreGui           = Services.CoreGui

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

----------------------------------------------------------------
-- EXECUTOR SHIM (fallback-safe)
----------------------------------------------------------------
local function envGet(k, default)
    if getgenv then
        local g = getgenv()
        if g[k] ~= nil then return g[k] end
    end
    return default
end

local function hui()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    return CoreGui
end

local function wFile(path, data)
    if writefile then pcall(writefile, path, data) end
end
local function rFile(path)
    if readfile and isfile and isfile(path) then
        local ok, d = pcall(readfile, path)
        if ok then return d end
    end
    return nil
end
local function fileExists(path)
    if isfile then
        local ok, r = pcall(isfile, path)
        return ok and r
    end
    return false
end

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Config = {
    File = "stealanegg_cfg.json",

    Game = {
        EggFolder      = "Eggs",
        BaseFolder     = "Bases",
        CollectRemote  = "CollectEgg",
        RemoteFolder   = "Remotes",
        RoundTimeName  = "RoundTime",
    },

    Theme = {
        Background = Color3.fromRGB(18, 18, 18),
        Panel      = Color3.fromRGB(26, 26, 26),
        Accent     = Color3.fromRGB(74, 144, 226),
        Text       = Color3.fromRGB(234, 234, 234),
        SubText    = Color3.fromRGB(150, 150, 150),
        Border     = Color3.fromRGB(40, 40, 40),
        Success    = Color3.fromRGB(76, 175, 80),
        Danger     = Color3.fromRGB(229, 57, 53),
    },

    Font = Enum.Font.GothamMedium,
    FontBold = Enum.Font.GothamBold,
    CornerRadius = UDim.new(0, 8),
    ToggleKey = Enum.KeyCode.RightShift,

    Player = {
        WalkEnabled   = false, WalkSpeed   = 32,
        JumpEnabled   = false, JumpPower   = 80,
        InfJump       = false,
        FlyEnabled    = false, FlySpeed    = 60,
        Noclip        = false,
    },

    Egg = {
        ESPEnabled    = false, ESPBox = true, ESPName = true, ESPDist = true, ESPRespawn = true,
        AutoCollect   = false, AutoCollectRadius = 25,
        AutoReturn    = false, AutoReturnCount = 5,
    },

    Combat = {
        PlayerESP     = false, PlayerBox = true, PlayerName = true, PlayerDist = true, PlayerHP = true, PlayerEgg = true,
        AntiSteal     = false, AntiStealRadius = 15, AntiStealBoost = 8, AntiStealDuration = 1.5,
        FreezeEnabled = false, FreezeDuration = 2, FreezeKey = Enum.KeyCode.F,
        TeleportKey   = Enum.KeyCode.T,
    },

    Round = {
        AutoJoin      = false,
    },

    Stats = {
        EggsThisRound = 0,
        EggsLifetime  = 0,
    },

    Keybinds = {},
}

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
local Utils = {}

function Utils.notify(text, color)
    local g = envGet("__SAE_NOTIFY", nil)
    if g then g(text, color) end
end

function Utils.getChar()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

function Utils.getHum()
    local c = Utils.getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

function Utils.getRoot()
    local c = Utils.getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

function Utils.distance(a, b)
    if not a or not b then return math.huge end
    return (a.Position - b.Position).Magnitude
end

function Utils.saveConfig()
    local data = {
        Player = Config.Player, Egg = Config.Egg, Combat = Config.Combat,
        Round = Config.Round, Keybinds = Config.Keybinds, Stats = Config.Stats,
        ToggleKey = tostring(Config.ToggleKey),
    }
    local ok, json = pcall(HttpService.JSONEncode, HttpService, data)
    if ok then wFile(Config.File, json) end
end

function Utils.loadConfig()
    local raw = rFile(Config.File)
    if not raw then return end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok or type(data) ~= "table" then return end
    for k, v in pairs(data) do
        if k == "ToggleKey" then
            local kc = Enum.KeyCode[v]
            if kc then Config.ToggleKey = kc end
        elseif type(v) == "table" and Config[k] then
            for kk, vv in pairs(v) do
                if Config[k][kk] ~= nil then Config[k][kk] = vv end
            end
        elseif Config[k] ~= nil then
            Config[k] = v
        end
    end
end

----------------------------------------------------------------
-- CONNECTIONS TABLE
----------------------------------------------------------------
local Connections = {}
local function track(conn)
    table.insert(Connections, conn)
    return conn
end
local function untrackAll()
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    Connections = {}
end

----------------------------------------------------------------
-- PLAYER MODULES
----------------------------------------------------------------
local Player = {}

function Player.applyWalk()
    local hum = Utils.getHum()
    if not hum then return end
    if Config.Player.WalkEnabled then
        hum.WalkSpeed = Config.Player.WalkSpeed
    else
        hum.WalkSpeed = 16
    end
end

function Player.applyJump()
    local hum = Utils.getHum()
    if not hum then return end
    if Config.Player.JumpEnabled then
        hum.UseJumpPower = true
        hum.JumpPower = Config.Player.JumpPower
    else
        hum.UseJumpPower = true
        hum.JumpPower = 50
    end
end

function Player.startInfJump()
    track(UIS.JumpRequest:Connect(function()
        if Config.Player.InfJump then
            local hum = Utils.getHum()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end))
end

local flyBV, flyBG, flyConn
function Player.startFly()
    Player.stopFly()
    local root = Utils.getRoot()
    if not root then return end
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = root
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flyBG.P = 9e4
    flyBG.Parent = root
    flyConn = track(RunService.RenderStepped:Connect(function()
        if not Config.Player.FlyEnabled then return end
        local cam = Camera.CFrame
        local move = Vector3.zero
        if UIS:IsKeyDown(Enum.KeyCode.W) then move += cam.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then move -= cam.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then move -= cam.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then move += cam.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
        if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then move -= Vector3.yAxis end
        if move.Magnitude > 0 then move = move.Unit end
        flyBV.Velocity = move * Config.Player.FlySpeed
        flyBG.CFrame = cam
    end))
end

function Player.stopFly()
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    if flyConn then flyConn:Disconnect(); flyConn = nil end
end

local noclipConn
function Player.startNoclip()
    if noclipConn then return end
    noclipConn = track(RunService.Stepped:Connect(function()
        if not Config.Player.Noclip then return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end))
end

function Player.bindChar()
    track(LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.6)
        Player.applyWalk()
        Player.applyJump()
        if Config.Player.FlyEnabled then Player.startFly() end
    end))
end

----------------------------------------------------------------
-- EGG MODULE
----------------------------------------------------------------
local Egg = {}

local function getEggFolder()
    return Workspace:FindFirstChild(Config.Game.EggFolder)
        or Workspace:FindFirstChild("Map")
        or Workspace
end

function Egg.getEggs()
    local folder = getEggFolder()
    if not folder then return {} end
    local out = {}
    for _, d in ipairs(folder:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Model") then
            local name = (d.Name or ""):lower()
            if name:find("egg") then
                table.insert(out, d)
            end
        end
    end
    return out
end

function Egg.getPos(egg)
    if egg:IsA("BasePart") then return egg.Position end
    local pp = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
    return pp and pp.Position
end

local espFolder
local function ensureEspFolder()
    if espFolder and espFolder.Parent then return espFolder end
    espFolder = Instance.new("Folder")
    espFolder.Name = "SAE_EggESP"
    espFolder.Parent = hui()
    return espFolder
end

local eggEsp = {}
function Egg.renderEsp()
    if not Config.Egg.ESPEnabled then
        for _, v in pairs(eggEsp) do
            if v.hl then v.hl:Destroy() end
            if v.bg then v.bg:Destroy() end
        end
        eggEsp = {}
        return
    end
    local folder = ensureEspFolder()
    local root = Utils.getRoot()
    local eggs = Egg.getEggs()
    local live = {}

    for _, egg in ipairs(eggs) do
        local key = tostring(egg)
        live[key] = true
        local pos = Egg.getPos(egg)
        if pos then
            local e = eggEsp[key]
            if not e then
                e = {}
                if Config.Egg.ESPBox then
                    e.hl = Instance.new("Highlight")
                    e.hl.FillTransparency = 0.6
                    e.hl.OutlineTransparency = 0
                    e.hl.OutlineColor = Config.Theme.Accent
                    e.hl.FillColor = Config.Theme.Accent
                    e.hl.Adornee = egg
                    e.hl.Parent = folder
                end
                e.bg = Instance.new("BillboardGui")
                e.bg.Size = UDim2.fromOffset(160, 44)
                e.bg.StudsOffset = Vector3.new(0, 3, 0)
                e.bg.AlwaysOnTop = true
                e.bg.Adornee = egg
                e.bg.Parent = folder

                e.name = Instance.new("TextLabel")
                e.name.BackgroundTransparency = 1
                e.name.Size = UDim2.new(1, 0, 0, 16)
                e.name.Position = UDim2.new(0, 0, 0, 0)
                e.name.Font = Config.FontBold
                e.name.TextSize = 12
                e.name.TextColor3 = Config.Theme.Accent
                e.name.TextStrokeTransparency = 0.4
                e.name.Text = egg.Name
                e.name.Parent = e.bg

                e.dist = Instance.new("TextLabel")
                e.dist.BackgroundTransparency = 1
                e.dist.Size = UDim2.new(1, 0, 0, 14)
                e.dist.Position = UDim2.new(0, 0, 0, 16)
                e.dist.Font = Config.Font
                e.dist.TextSize = 11
                e.dist.TextColor3 = Config.Theme.Text
                e.dist.TextStrokeTransparency = 0.4
                e.dist.Parent = e.bg

                e.resp = Instance.new("TextLabel")
                e.resp.BackgroundTransparency = 1
                e.resp.Size = UDim2.new(1, 0, 0, 14)
                e.resp.Position = UDim2.new(0, 0, 0, 30)
                e.resp.Font = Config.Font
                e.resp.TextSize = 11
                e.resp.TextColor3 = Config.Theme.SubText
                e.resp.TextStrokeTransparency = 0.4
                e.resp.Parent = e.bg
                eggEsp[key] = e
            end
            -- live updates
            if not Config.Egg.ESPBox and e.hl then e.hl:Destroy(); e.hl = nil end
            e.name.Visible = Config.Egg.ESPName
            e.dist.Visible = Config.Egg.ESPDist
            e.resp.Visible = Config.Egg.ESPRespawn

            if root then
                e.dist.Text = string.format("[%d studs]", math.floor(Utils.distance(root.Position, pos)))
            end
            if Config.Egg.ESPRespawn then
                local rt = egg:GetAttribute("RespawnTime") or egg:GetAttribute("respawnTime")
                if type(rt) == "number" then
                    e.resp.Text = string.format("respawn in %.1fs", math.max(0, rt - workspace:GetServerTimeNow()))
                else
                    e.resp.Text = "—"
                end
            end
        end
    end

    for k, v in pairs(eggEsp) do
        if not live[k] then
            if v.hl then v.hl:Destroy() end
            if v.bg then v.bg:Destroy() end
            eggEsp[k] = nil
        end
    end
end

function Egg.teleportNearest()
    local root = Utils.getRoot()
    if not root then return false end
    local eggs = Egg.getEggs()
    local best, bestD = nil, math.huge
    for _, egg in ipairs(eggs) do
        local pos = Egg.getPos(egg)
        if pos then
            local d = Utils.distance(root.Position, pos)
            if d < bestD then best, bestD = pos, d end
        end
    end
    if not best then return false end
    root.CFrame = CFrame.new(best + Vector3.new(0, 4, 0))
    return true
end

function Egg.teleportTo(egg)
    local root = Utils.getRoot()
    local pos = Egg.getPos(egg)
    if root and pos then root.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)); return true end
    return false
end

local function fireCollectRemote()
    local folder = RS:FindFirstChild(Config.Game.RemoteFolder) or RS:FindFirstChild("Remotes")
    if not folder then return false end
    local remote = folder:FindFirstChild(Config.Game.CollectRemote)
    if remote and remote:IsA("RemoteEvent") then
        pcall(function() remote:FireServer() end)
        return true
    end
    return false
end

function Egg.autoCollect()
    if not Config.Egg.AutoCollect then return end
    local root = Utils.getRoot()
    if not root then return end
    local eggs = Egg.getEggs()
    for _, egg in ipairs(eggs) do
        local pos = Egg.getPos(egg)
        if pos and Utils.distance(root.Position, pos) <= Config.Egg.AutoCollectRadius then
            if fireCollectRemote() then
                Config.Stats.EggsThisRound += 1
                Config.Stats.EggsLifetime += 1
                Utils.notify("Collected " .. egg.Name, Config.Theme.Success)
            else
                -- fallback: activate held tool
                local char = LocalPlayer.Character
                if char then
                    for _, t in ipairs(char:GetChildren()) do
                        if t:IsA("Tool") and t:FindFirstChild("Handle") then
                            pcall(function() t:Activate() end)
                        end
                    end
                end
            end
            break
        end
    end
end

function Egg.returnToBase()
    if not Config.Egg.AutoReturn then return end
    if Config.Stats.EggsThisRound < Config.Egg.AutoReturnCount then return end
    local baseFolder = Workspace:FindFirstChild(Config.Game.BaseFolder)
    local basePos
    if baseFolder then
        for _, b in ipairs(baseFolder:GetChildren()) do
            local pp = b:IsA("BasePart") and b or b.PrimaryPart or b:FindFirstChildWhichIsA("BasePart")
            if pp then basePos = pp.Position; break end
        end
    end
    if not basePos then return end
    local root = Utils.getRoot()
    if root then
        root.CFrame = CFrame.new(basePos + Vector3.new(0, 4, 0))
        task.wait(0.4)
        fireCollectRemote()
        Config.Stats.EggsThisRound = 0
        Utils.notify("Returned to base", Config.Theme.Accent)
    end
end

----------------------------------------------------------------
-- COMBAT MODULE
----------------------------------------------------------------
local Combat = {}
local playerEsp = {}
local antiStealUntil = 0

local function ensurePlayerEspFolder()
    if playerEsp.folder and playerEsp.folder.Parent then return playerEsp.folder end
    playerEsp.folder = Instance.new("Folder")
    playerEsp.folder.Name = "SAE_PlayerESP"
    playerEsp.folder.Parent = hui()
    return playerEsp.folder
end

function Combat.renderPlayerEsp()
    local folder = ensurePlayerEspFolder()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local key = tostring(plr)
        local e = playerEsp[key]

        if not char or not hrp or not hum or hum.Health <= 0 then
            if e then
                if e.hl then e.hl:Destroy() end
                if e.bg then e.bg:Destroy() end
                playerEsp[key] = nil
            end
            continue
        end

        if not e then
            e = {}
            e.hl = Instance.new("Highlight")
            e.hl.Adornee = char
            e.hl.FillTransparency = 0.65
            e.hl.OutlineColor = Config.Theme.Danger
            e.hl.FillColor = Config.Theme.Danger
            e.hl.Parent = folder

            e.bg = Instance.new("BillboardGui")
            e.bg.Size = UDim2.fromOffset(180, 64)
            e.bg.StudsOffset = Vector3.new(0, 3, 0)
            e.bg.AlwaysOnTop = true
            e.bg.Adornee = char
            e.bg.Parent = folder

            local function mk(y, size, color, bold)
                local l = Instance.new("TextLabel")
                l.BackgroundTransparency = 1
                l.Size = UDim2.new(1, 0, 0, size)
                l.Position = UDim2.new(0, 0, 0, y)
                l.Font = bold and Config.FontBold or Config.Font
                l.TextSize = size - 1
                l.TextColor3 = color
                l.TextStrokeTransparency = 0.4
                l.Parent = e.bg
                return l
            end
            e.name = mk(0,  16, Config.Theme.Text,  true)
            e.hp   = mk(16, 14, Config.Theme.Success,false)
            e.dist = mk(30, 14, Config.Theme.SubText,false)
            e.egg  = mk(44, 14, Config.Theme.Accent,  false)
            playerEsp[key] = e
        end

        e.hl.Enabled = Config.Combat.PlayerESP
        e.bg.Enabled = Config.Combat.PlayerESP
        e.name.Visible = Config.Combat.PlayerName
        e.hp.Visible   = Config.Combat.PlayerHP
        e.dist.Visible = Config.Combat.PlayerDist
        e.egg.Visible  = Config.Combat.PlayerEgg

        e.name.Text = plr.Name
        e.hp.Text   = string.format("HP %d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth))
        local root = Utils.getRoot()
        if root then e.dist.Text = string.format("[%d]", math.floor(Utils.distance(root.Position, hrp.Position))) end

        local held = "—"
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then held = t.Name; break end
        end
        e.egg.Text = "held: " .. held
    end
end

function Combat.antiStealTick()
    if not Config.Combat.AntiSteal then return end
    local root = Utils.getRoot()
    local hum = Utils.getHum()
    if not root or not hum then return end
    if tick() < antiStealUntil then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and Utils.distance(root.Position, hrp.Position) <= Config.Combat.AntiStealRadius then
            local delta = (hrp.Position - root.Position).Unit
            local toward = root.CFrame.LookVector:Dot(delta)
            if toward > 0.2 then
                local orig = hum.WalkSpeed
                hum.WalkSpeed = orig + Config.Combat.AntiStealBoost
                antiStealUntil = tick() + Config.Combat.AntiStealDuration
                task.delay(Config.Combat.AntiStealDuration, function()
                    if hum and hum.Parent then
                        hum.WalkSpeed = Config.Player.WalkEnabled and Config.Player.WalkSpeed or 16
                    end
                end)
                break
            end
        end
    end
end

function Combat.freezeNearest()
    local root = Utils.getRoot()
    if not root then return end
    local nearest, best = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local d = Utils.distance(root.Position, hrp.Position)
            if d < best then nearest, best = hrp, d end
        end
    end
    if not nearest then Utils.notify("No target", Config.Theme.Danger); return end
    local wasAnchored = nearest.Anchored
    nearest.Anchored = true
    Utils.notify("Froze " .. tostring(nearest.Parent and nearest.Parent.Name), Config.Theme.Accent)
    task.delay(Config.Combat.FreezeDuration, function()
        if nearest and nearest.Parent then nearest.Anchored = wasAnchored end
    end)
end

function Combat.teleportBehind()
    local root = Utils.getRoot()
    if not root then return end
    local nearest, best = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local d = Utils.distance(root.Position, hrp.Position)
            if d < best then nearest, best = hrp, d end
        end
    end
    if not nearest then Utils.notify("No target", Config.Theme.Danger); return end
    root.CFrame = nearest.CFrame * CFrame.new(0, 0, 4)
    Utils.notify("Teleported", Config.Theme.Success)
end

----------------------------------------------------------------
-- ROUND MODULE
----------------------------------------------------------------
local Round = {}

function Round.readTimer()
    local rt = Workspace:FindFirstChild(Config.Game.RoundTimeName)
    if rt and (rt:IsA("NumberValue") or rt:IsA("IntValue")) then return rt.Value end
    local sg = LocalPlayer:FindFirstChild("PlayerGui")
    if sg then
        local gui = sg:FindFirstChild("RoundTimer", true)
        if gui and gui:IsA("TextLabel") then
            local n = tonumber(gui.Text:match("%d+"))
            if n then return n end
        end
    end
    return nil
end

function Round.autoJoinTick()
    if not Config.Round.AutoJoin then return end
    -- fires the common join remote names if present; harmless if absent
    local folder = RS:FindFirstChild(Config.Game.RemoteFolder)
    if not folder then return end
    for _, n in ipairs({"JoinRound", "Join", "Play", "Start"}) do
        local r = folder:FindFirstChild(n)
        if r and r:IsA("RemoteEvent") then
            pcall(function() r:FireServer() end)
            return
        end
    end
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local UI = {}
UI.Objects = {}
UI.Connections = {}

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(parent, r)
    new("UICorner", { CornerRadius = r or Config.CornerRadius }, parent)
end

local function stroke(parent, color)
    new("UIStroke", { Color = color or Config.Theme.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

function UI.build()
    local gui = new("ScreenGui", {
        Name = "SAE_Menu",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, hui())
    UI.Gui = gui

    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.fromOffset(480, 340),
        Position = UDim2.new(0.5, -240, 0.5, -170),
        BackgroundColor3 = Config.Theme.Background,
        BorderSizePixel = 0,
        Active = true,
        Draggable = true,
    }, gui)
    corner(main, UDim.new(0, 10))
    stroke(main, Config.Theme.Border)
    UI.Main = main

    local header = new("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Config.Theme.Panel,
        BorderSizePixel = 0,
    }, main)
    corner(header, UDim.new(0, 10))
    -- square off bottom of header
    new("Frame", {
        Size = UDim2.new(1, 0, 0, 10),
        Position = UDim2.new(0, 0, 1, -10),
        BackgroundColor3 = Config.Theme.Panel,
        BorderSizePixel = 0,
    }, header)

    new("TextLabel", {
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1,
        Font = Config.FontBold,
        TextSize = 15,
        TextColor3 = Config.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "Steal an Egg  •  Elite",
    }, header)

    UI.RoundLabel = new("TextLabel", {
        Size = UDim2.fromOffset(140, 40),
        Position = UDim2.new(1, -150, 0, 0),
        BackgroundTransparency = 1,
        Font = Config.Font,
        TextSize = 13,
        TextColor3 = Config.Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = "round: —",
    }, header)

    local tabBar = new("Frame", {
        Size = UDim2.new(1, -20, 0, 30),
        Position = UDim2.fromOffset(10, 48),
        BackgroundTransparency = 1,
    }, main)

    local tabList = new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, tabBar)

    local content = new("Frame", {
        Size = UDim2.new(1, -20, 1, -96),
        Position = UDim2.fromOffset(10, 84),
        BackgroundColor3 = Config.Theme.Panel,
        BorderSizePixel = 0,
    }, main)
    corner(content, UDim.new(0, 8))
    stroke(content, Config.Theme.Border)

    local scroll = new("ScrollingFrame", {
        Size = UDim2.new(1, -16, 1, -16),
        Position = UDim2.fromOffset(8, 8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Config.Theme.Accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, content)

    local list = new("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, scroll)
    UI.Scroll = scroll
    UI.TabBar = tabBar
    UI.TabList = tabList

    UI.Tabs = {}
    UI.CurrentTab = nil

    function UI.addTab(name, order)
        local btn = new("TextButton", {
            Size = UDim2.new(0, 88, 1, 0),
            BackgroundColor3 = Config.Theme.Panel,
            BorderSizePixel = 0,
            Font = Config.Font,
            TextSize = 13,
            TextColor3 = Config.Theme.SubText,
            Text = name,
            LayoutOrder = order,
        }, tabBar)
        corner(btn, UDim.new(0, 6))
        local frame = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Visible = false,
        }, scroll)

        UI.Tabs[name] = { btn = btn, frame = frame }

        btn.MouseButton1Click:Connect(function()
            for n, t in pairs(UI.Tabs) do
                t.frame.Visible = (n == name)
                t.btn.BackgroundColor3 = (n == name) and Config.Theme.Accent or Config.Theme.Panel
                t.btn.TextColor3 = (n == name) and Color3.new(1,1,1) or Config.Theme.SubText
            end
            UI.CurrentTab = name
        end)

        return frame
    end

    function UI.section(parent, label)
        local wrap = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, parent)
        new("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, wrap)
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            Font = Config.FontBold,
            TextSize = 12,
            TextColor3 = Config.Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = string.upper(label),
        }, wrap)
        return wrap
    end

    -- toggle switch
    function UI.toggle(parent, label, get, set, order)
        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            LayoutOrder = order or 0,
        }, parent)
        new("TextLabel", {
            Size = UDim2.new(1, -60, 1, 0),
            BackgroundTransparency = 1,
            Font = Config.Font,
            TextSize = 13,
            TextColor3 = Config.Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = label,
        }, row)

        local track = new("Frame", {
            Size = UDim2.fromOffset(42, 22),
            Position = UDim2.new(1, -42, 0.5, -11),
            BackgroundColor3 = Config.Theme.Border,
            BorderSizePixel = 0,
        }, row)
        corner(track, UDim.new(1, 0))
        local knob = new("Frame", {
            Size = UDim2.fromOffset(18, 18),
            Position = UDim2.fromOffset(2, 2),
            BackgroundColor3 = Color3.fromRGB(220, 220, 220),
            BorderSizePixel = 0,
        }, track)
        corner(knob, UDim.new(1, 0))

        local function refresh()
            local on = get()
            TweenService:Create(track, TweenInfo.new(0.15), {
                BackgroundColor3 = on and Config.Theme.Accent or Config.Theme.Border,
            }):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), {
                Position = on and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2),
            }):Play()
        end
        refresh()

        local btn = new("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
        }, track)
        btn.MouseButton1Click:Connect(function()
            set(not get())
            refresh()
        end)

        return { row = row, refresh = refresh }
    end

    function UI.slider(parent, label, min, max, get, set, order)
        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 44),
            BackgroundTransparency = 1,
            LayoutOrder = order or 0,
        }, parent)
        local top = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            Font = Config.Font,
            TextSize = 13,
            TextColor3 = Config.Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = label,
        }, row)
        local val = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            Font = Config.Font,
            TextSize = 13,
            TextColor3 = Config.Theme.Accent,
            TextXAlignment = Enum.TextXAlignment.Right,
            Text = tostring(get()),
        }, row)

        local track = new("Frame", {
            Size = UDim2.new(1, 0, 0, 6),
            Position = UDim2.fromOffset(0, 30),
            BackgroundColor3 = Config.Theme.Border,
            BorderSizePixel = 0,
        }, row)
        corner(track, UDim.new(1, 0))
        local fill = new("Frame", {
            Size = UDim2.new((get() - min) / (max - min), 0, 1, 0),
            BackgroundColor3 = Config.Theme.Accent,
            BorderSizePixel = 0,
        }, track)
        corner(fill, UDim.new(1, 0))

        local dragging = false
        local function update(input)
            local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local v = math.floor(min + (max - min) * rel + 0.5)
            set(v)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            val.Text = tostring(v)
        end

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; update(input) end
        end)
        track.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        track.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then update(input) end
        end)

        return { set = function(v) set(v); fill.Size = UDim2.new((v-min)/(max-min),0,1,0); val.Text = tostring(v) end }
    end

    function UI.button(parent, label, cb, order)
        local btn = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundColor3 = Config.Theme.Background,
            BorderSizePixel = 0,
            Font = Config.Font,
            TextSize = 13,
            TextColor3 = Config.Theme.Text,
            Text = label,
            LayoutOrder = order or 0,
        }, parent)
        corner(btn, UDim.new(0, 6))
        stroke(btn, Config.Theme.Border)
        btn.MouseEnter:Connect(function() btn.BackgroundColor3 = Config.Theme.Panel end)
        btn.MouseLeave:Connect(function() btn.BackgroundColor3 = Config.Theme.Background end)
        btn.MouseButton1Click:Connect(function() pcall(cb) end)
        return btn
    end

    function UI.keybind(parent, label, keyRef, order)
        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            LayoutOrder = order or 0,
        }, parent)
        new("TextLabel", {
            Size = UDim2.new(1, -90, 1, 0),
            BackgroundTransparency = 1,
            Font = Config.Font,
            TextSize = 13,
            TextColor3 = Config.Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = label,
        }, row)
        local box = new("TextButton", {
            Size = UDim2.fromOffset(80, 24),
            Position = UDim2.new(1, -80, 0.5, -12),
            BackgroundColor3 = Config.Theme.Background,
            BorderSizePixel = 0,
            Font = Config.Font,
            TextSize = 12,
            TextColor3 = Config.Theme.Accent,
            Text = tostring(keyRef.value.Name or keyRef.value),
        }, row)
        corner(box, UDim.new(0, 6))
        stroke(box, Config.Theme.Border)
        local listening = false
        box.MouseButton1Click:Connect(function() listening = true; box.Text = "..." end)
        local conn = UIS.InputBegan:Connect(function(input, gp)
            if not listening then return end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                keyRef.value = input.KeyCode
                box.Text = input.KeyCode.Name
                listening = false
                Utils.saveConfig()
            end
        end)
        track(conn)
        return box
    end
end

----------------------------------------------------------------
-- NOTIFICATIONS
----------------------------------------------------------------
local function notify(text, color)
    if not UI.Gui then return end
    local frame = new("Frame", {
        Size = UDim2.fromOffset(220, 32),
        Position = UDim2.new(1, -240, 1, -60),
        BackgroundColor3 = Config.Theme.Panel,
        BorderSizePixel = 0,
    }, UI.Gui)
    corner(frame, UDim.new(0, 6))
    stroke(frame, color or Config.Theme.Border)
    new("TextLabel", {
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Font = Config.Font,
        TextSize = 12,
        TextColor3 = Config.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
    }, frame)
    TweenService:Create(frame, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
    task.delay(2.5, function()
        TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
        task.wait(0.35)
        frame:Destroy()
    end)
end
envGet("__SAE_NOTIFY", notify)
if getgenv then getgenv().__SAE_NOTIFY = notify end

----------------------------------------------------------------
-- MENU TABS
----------------------------------------------------------------
UI.build()

local function buildPlayerTab()
    local f = UI.addTab("Player", 1)
    local s = UI.section(f, "Movement")
    UI.toggle(s, "Walkspeed", function() return Config.Player.WalkEnabled end, function(v) Config.Player.WalkEnabled = v; Player.applyWalk(); Utils.saveConfig() end)
    UI.slider(s, "Walk value", 16, 250, function() return Config.Player.WalkSpeed end, function(v) Config.Player.WalkSpeed = v; Player.applyWalk(); Utils.saveConfig() end)
    UI.toggle(s, "Jump power", function() return Config.Player.JumpEnabled end, function(v) Config.Player.JumpEnabled = v; Player.applyJump(); Utils.saveConfig() end)
    UI.slider(s, "Jump value", 50, 300, function() return Config.Player.JumpPower end, function(v) Config.Player.JumpPower = v; Player.applyJump(); Utils.saveConfig() end)
    UI.toggle(s, "Infinite jump", function() return Config.Player.InfJump end, function(v) Config.Player.InfJump = v; Utils.saveConfig() end)
    UI.toggle(s, "Fly", function() return Config.Player.FlyEnabled end, function(v) Config.Player.FlyEnabled = v; if v then Player.startFly() else Player.stopFly() end; Utils.saveConfig() end)
    UI.slider(s, "Fly speed", 20, 200, function() return Config.Player.FlySpeed end, function(v) Config.Player.FlySpeed = v; Utils.saveConfig() end)
    UI.toggle(s, "Noclip", function() return Config.Player.Noclip end, function(v) Config.Player.Noclip = v; Utils.saveConfig() end)
end

local function buildEggTab()
    local f = UI.addTab("Egg", 2)
    local s = UI.section(f, "ESP")
    UI.toggle(s, "Egg ESP", function() return Config.Egg.ESPEnabled end, function(v) Config.Egg.ESPEnabled = v; Utils.saveConfig() end)
    UI.toggle(s, "Box", function() return Config.Egg.ESPBox end, function(v) Config.Egg.ESPBox = v; Utils.saveConfig() end)
    UI.toggle(s, "Name", function() return Config.Egg.ESPName end, function(v) Config.Egg.ESPName = v; Utils.saveConfig() end)
    UI.toggle(s, "Distance", function() return Config.Egg.ESPDist end, function(v) Config.Egg.ESPDist = v; Utils.saveConfig() end)
    UI.toggle(s, "Respawn timer", function() return Config.Egg.ESPRespawn end, function(v) Config.Egg.ESPRespawn = v; Utils.saveConfig() end)

    local s2 = UI.section(f, "Collection")
    UI.button(s2, "Teleport to nearest egg", function()
        if Egg.teleportNearest() then Utils.notify("Teleported", Config.Theme.Success)
        else Utils.notify("No egg found", Config.Theme.Danger) end
    end)
    UI.toggle(s2, "Auto collect", function() return Config.Egg.AutoCollect end, function(v) Config.Egg.AutoCollect = v; Utils.saveConfig() end)
    UI.slider(s2, "Collect radius", 5, 100, function() return Config.Egg.AutoCollectRadius end, function(v) Config.Egg.AutoCollectRadius = v; Utils.saveConfig() end)
    UI.toggle(s2, "Auto return to base", function() return Config.Egg.AutoReturn end, function(v) Config.Egg.AutoReturn = v; Utils.saveConfig() end)
    UI.slider(s2, "Return after N", 1, 20, function() return Config.Egg.AutoReturnCount end, function(v) Config.Egg.AutoReturnCount = v; Utils.saveConfig() end)
end

local function buildCombatTab()
    local f = UI.addTab("Combat", 3)
    local s = UI.section(f, "Player ESP")
    UI.toggle(s, "Player ESP", function() return Config.Combat.PlayerESP end, function(v) Config.Combat.PlayerESP = v; Utils.saveConfig() end)
    UI.toggle(s, "Box",     function() return Config.Combat.PlayerBox end,  function(v) Config.Combat.PlayerBox = v; Utils.saveConfig() end)
    UI.toggle(s, "Name",    function() return Config.Combat.PlayerName end, function(v) Config.Combat.PlayerName = v; Utils.saveConfig() end)
    UI.toggle(s, "Distance",function() return Config.Combat.PlayerDist end, function(v) Config.Combat.PlayerDist = v; Utils.saveConfig() end)
    UI.toggle(s, "Health",  function() return Config.Combat.PlayerHP end,   function(v) Config.Combat.PlayerHP = v; Utils.saveConfig() end)
    UI.toggle(s, "Held egg",function() return Config.Combat.PlayerEgg end,  function(v) Config.Combat.PlayerEgg = v; Utils.saveConfig() end)

    local s2 = UI.section(f, "Anti-steal")
    UI.toggle(s2, "Anti-steal", function() return Config.Combat.AntiSteal end, function(v) Config.Combat.AntiSteal = v; Utils.saveConfig() end)
    UI.slider(s2, "Detect radius", 5, 60, function() return Config.Combat.AntiStealRadius end, function(v) Config.Combat.AntiStealRadius = v; Utils.saveConfig() end)
    UI.slider(s2, "Boost", 1, 20, function() return Config.Combat.AntiStealBoost end, function(v) Config.Combat.AntiStealBoost = v; Utils.saveConfig() end)

    local s3 = UI.section(f, "Actions")
    UI.toggle(s3, "Freeze nearest", function() return Config.Combat.FreezeEnabled end, function(v) Config.Combat.FreezeEnabled = v; Utils.saveConfig() end)
    UI.slider(s3, "Freeze duration", 1, 10, function() return Config.Combat.FreezeDuration end, function(v) Config.Combat.FreezeDuration = v; Utils.saveConfig() end)
    UI.keybind(s3, "Freeze key", { value = Config.Combat.FreezeKey })
    UI.keybind(s3, "Teleport key", { value = Config.Combat.TeleportKey })
end

local function buildRoundTab()
    local f = UI.addTab("Round", 4)
    local s = UI.section(f, "Round")
    UI.toggle(s, "Auto-join next round", function() return Config.Round.AutoJoin end, function(v) Config.Round.AutoJoin = v; Utils.saveConfig() end)
    UI.button(s, "Reset round egg count", function()
        Config.Stats.EggsThisRound = 0
        Utils.notify("Reset", Config.Theme.Accent)
    end)

    local s2 = UI.section(f, "Stats")
    UI.Objects.StatsLabel = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
        Font = Config.Font,
        TextSize = 13,
        TextColor3 = Config.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Text = "collected: 0  |  lifetime: 0",
    }, f)
end

local function buildSettingsTab()
    local f = UI.addTab("Settings", 5)
    local s = UI.section(f, "Config")
    UI.button(s, "Save config", function() Utils.saveConfig(); Utils.notify("Config saved", Config.Theme.Success) end)
    UI.button(s, "Load config", function() Utils.loadConfig(); Utils.notify("Config loaded", Config.Theme.Accent) end)
    UI.button(s, "Reset to defaults", function()
        for _, k in ipairs({"Player","Egg","Combat","Round"}) do
            for kk, vv in pairs(Config[k]) do
                if type(vv) == "boolean" then Config[k][kk] = false
                elseif type(vv) == "number" then Config[k][kk] = vv end
            end
        end
        Utils.notify("Reset", Config.Theme.Accent)
    end)
    UI.keybind(s, "Toggle menu key", { value = Config.ToggleKey })

    local s2 = UI.section(f, "Script")
    UI.button(s2, "Unload", function()
        untrackAll()
        if UI.Gui then UI.Gui:Destroy() end
        if eggEspFolder then pcall(function() eggEspFolder:Destroy() end) end
        Utils.notify("Unloaded", Config.Theme.Danger)
    end)
end

buildPlayerTab()
buildEggTab()
buildCombatTab()
buildRoundTab()
buildSettingsTab()

-- activate first tab
for name, t in pairs(UI.Tabs) do
    if name == "Player" then
        t.frame.Visible = true
        t.btn.BackgroundColor3 = Config.Theme.Accent
        t.btn.TextColor3 = Color3.new(1,1,1)
    else
        t.frame.Visible = false
    end
end

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
local function bindToggleKey()
    track(UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Config.ToggleKey and UI.Main then
            UI.Main.Visible = not UI.Main.Visible
        end
        if input.KeyCode == Config.Combat.FreezeKey and Config.Combat.FreezeEnabled then
            Combat.freezeNearest()
        end
        if input.KeyCode == Config.Combat.TeleportKey then
            Combat.teleportBehind()
        end
    end))
end

local function mainLoop()
    Player.bindChar()
    Player.startInfJump()
    Player.startNoclip()
    Player.applyWalk()
    Player.applyJump()
    bindToggleKey()
    Utils.loadConfig()

    task.spawn(function()
        while UI.Gui and UI.Gui.Parent do
            pcall(Egg.renderEsp)
            pcall(Combat.renderPlayerEsp)
            pcall(Egg.autoCollect)
            pcall(Egg.returnToBase)
            pcall(Combat.antiStealTick)
            pcall(Round.autoJoinTick)
            local t = Round.readTimer()
            if UI.RoundLabel then
                UI.RoundLabel.Text = t and string.format("round: %ds", t) or "round: —"
            end
            if UI.Objects.StatsLabel then
                UI.Objects.StatsLabel.Text = string.format("collected: %d  |  lifetime: %d", Config.Stats.EggsThisRound, Config.Stats.EggsLifetime)
            end
            task.wait(0.15)
        end
    end)
end

mainLoop()
