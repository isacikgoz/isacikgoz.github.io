local _, ns = ...

-- What your character does, felt by the liquids (0.5.441, the player's: "when camera moves more
-- than it's usual speed ... make all liquid effects warp in way how actual fluid would warp"; then
-- "we can bound it to the character, we can also include falling and moving data too"). No camera
-- angle API exists in Forever (its CameraDocumentation has only the UI's model cameras), and
-- GetCursorDelta reads 0 while the cursor is hidden for a camera drag (seen in game, 0.5.441), so
-- it is read from:
--   * your facing (GetPlayerFacing): turning by key or with the right mouse button held
--   * your position (UnitPosition, each frame: forward and sideways speed; GetUnitSpeed, forward
--     only, where it says nothing)
--   * the air (IsFalling) and a jump's push-off (a hook on the jump key's JumpOrAscendStart)
-- The slosh below turns them into each liquid's motion; Sphere.lua draws it. `/spheres motion`
-- opens a live panel of the raw readings (SetFormattedText formats in the client: no garbage), and
-- /spheres debug keeps its peaks.

local M = {}
ns.Motion = M
local A = ns.Art

local WINDOW = 0.1 -- seconds per reading: a frame's own numbers jump about too much to read
local TWO_PI = 2 * math.pi

local panel
local lines = {}
local seen = false -- sampled since login
local opened, closed = 0, 0 -- GetTime() when the panel last opened and closed
-- this window's sums, the last reading, and the peaks since the panel opened
local win = { t = 0, turn = 0, delta = 0, cursor = 0, dragDelta = 0, dragT = 0 }
local now = { turn = 0, delta = 0, cursor = 0, speed = 0 }
local peak = { turn = 0, delta = 0, dragDelta = 0, dragCursor = 0, dragFrames = 0, frames = 0 }
local lastFacing, lastX, lastY
local facingOK, deltaOK = false, false

local function plain(v) return v ~= nil and not A.secret(v) and type(v) == "number" end
local function smooth(v, target, dt, tau) return v + (target - v) * (1 - math.exp(-dt / tau)) end
local function down(button) return IsMouseButtonDown ~= nil and IsMouseButtonDown(button) and true or false end
local function cursorHidden() return IsCursorVisible ~= nil and not IsCursorVisible() end
local function yesNo(v) return v and "yes" or "no" end
local function upDown(v) return v and "DOWN" or "up" end

-- one frame: the turn since the last (radians, wrapped to -pi..pi), the mouse's and cursor's moves
local function sample(elapsed)
    if not (elapsed and elapsed > 0) then return end
    peak.frames = peak.frames + 1
    local facing = GetPlayerFacing and GetPlayerFacing()
    facingOK = plain(facing)
    if facingOK then
        if lastFacing then win.turn = win.turn + math.abs((facing - lastFacing + math.pi) % TWO_PI - math.pi) end
        lastFacing = facing
    else
        lastFacing = nil
    end
    local dx, dy
    if GetCursorDelta then dx, dy = GetCursorDelta() end
    deltaOK = plain(dx) and plain(dy)
    local moved = deltaOK and math.sqrt(dx * dx + dy * dy) or 0
    win.delta = win.delta + moved
    local x, y = GetCursorPosition()
    local cursorMoved = 0
    if plain(x) and plain(y) then
        if lastX then cursorMoved = math.sqrt((x - lastX) ^ 2 + (y - lastY) ^ 2) end
        lastX, lastY = x, y
    end
    win.cursor = win.cursor + cursorMoved
    -- a camera drag: a mouse button held, the cursor hidden
    if (down("LeftButton") or down("RightButton")) and cursorHidden() then
        win.dragDelta, win.dragT = win.dragDelta + moved, win.dragT + elapsed
        if moved > 0 then peak.dragFrames = peak.dragFrames + 1 end
        if cursorMoved > 0 then peak.dragCursor = math.max(peak.dragCursor, cursorMoved / elapsed) end
    end
    win.t = win.t + elapsed
    if win.t < WINDOW then return false end
    now.turn = math.deg(win.turn) / win.t
    now.delta = win.delta / win.t
    now.cursor = win.cursor / win.t
    local speed = GetUnitSpeed and GetUnitSpeed("player")
    now.speed = plain(speed) and speed or 0
    peak.turn = math.max(peak.turn, now.turn)
    peak.delta = math.max(peak.delta, now.delta)
    if win.dragT > 0 then peak.dragDelta = math.max(peak.dragDelta, win.dragDelta / win.dragT) end
    win.t, win.turn, win.delta, win.cursor, win.dragDelta, win.dragT = 0, 0, 0, 0, 0, 0
    return true
end

local function paint()
    if facingOK then
        lines[1]:SetFormattedText("turn: %.0f°/s   (peak %.0f)", now.turn, peak.turn)
    else
        lines[1]:SetFormattedText("turn: no facing here (%s)", "GetPlayerFacing gave nothing")
    end
    if deltaOK then
        lines[2]:SetFormattedText("mouse: %.0f /s   (peak %.0f)", now.delta, peak.delta)
    else
        lines[2]:SetFormattedText("mouse: %s", GetCursorDelta and "GetCursorDelta gave nothing" or "no GetCursorDelta")
    end
    lines[3]:SetFormattedText("camera drag seen: %s   (peak %.0f /s, %d frames moved)",
        peak.dragFrames > 0 and "YES" or "not yet", peak.dragDelta, peak.dragFrames)
    lines[4]:SetFormattedText("cursor position moved: %.0f /s", now.cursor)
    lines[5]:SetFormattedText("left %s   right %s   mouselook %s   cursor hidden %s", upDown(down("LeftButton")),
        upDown(down("RightButton")), yesNo(IsMouselooking and IsMouselooking()), yesNo(cursorHidden()))
    lines[6]:SetFormattedText("moving: %.1f yd/s   falling %s", now.speed, yesNo(IsFalling and IsFalling()))
end

local function build()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(420, 150)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.85)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText("Spheres motion")
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
    f.hint:SetText("drag the camera, turn, run; /spheres motion closes")
    for i = 1, 6 do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 12, -14 - 18 * i)
        fs:SetJustifyH("LEFT")
        lines[i] = fs
    end
    f:SetScript("OnUpdate", A.Timed("motion probe", function(_, elapsed) if sample(elapsed) then paint() end end))
    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- The slosh (0.5.442): the player's values from the Sphere Slosh mockup ("Spheres slosh: threshold
-- 360°/s, strength 1.30, lean 0.10, weight 0.45 s, moving 0.70, float 0.20, landing 0.20, wobble
-- 0.75 Hz, settling 0.20, climb 8, swirl drift 0.60, churn 0.35, tilt full"; full tilt didn't
-- draw in game, see Sphere.lua SLOSH_EDGE: the liquid climbs, the low side stays). Turning past
-- `threshold` sloshes sideways, the more the faster it starts or stops (`lean`: a little tilt for
-- as long as it lasts); strafing sloshes sideways too, starting and stopping a run bobs it
-- (`move`); in the air the liquid gets lighter (`float`), landing slams it down (`landing`),
-- harder after a longer fall, and a jump's push-off presses it down. Every push goes through the
-- liquid's `weight` (seconds for a push to take hold; one the other way cancels the motion
-- gradually instead of flipping it: "opposite directions should cancel out slowly"), then two
-- springs per liquid: its sideways slosh (`wobble` Hz for the health piece, a narrower vessel
-- faster; `settle` of critical damping) and its bob (K.bob Hz). Drawn (M.Shape): the surface `climb`
-- units up the wall it sloshes to, its swirls carried (`drift`) and churning faster (`churn`).
-- The liquid simulator (`make sim`, Spheres/tools/sim_bridge.lua) runs this file as it is.
-------------------------------------------------------------------------------
-- `wobble`: 0.45 since 0.5.445 (the player's: "slow down slosh animation speed like 40% for
-- horizontal movements"; the bob keeps its own frequency, K.bob).
local SLOSH = { threshold = 360, strength = 1.30, lean = 0.10, weight = 0.45, move = 0.70, float = 0.20,
    landing = 0.20, wobble = 0.45, settle = 0.20, climb = 8, drift = 0.60, churn = 0.35 }
M.SLOSH = SLOSH
-- The model's own numbers, not tuned by the player: how readings are smoothed (seconds), how much a
-- change of turn (degrees a second, per `turnPush`), of sideways speed (yards a second, per
-- `strafePush`) and of forward speed (per `runPush`) pushes, the bob, the landing and the shape.
local K = {
    turnSmooth = 0.05, alphaSmooth = 0.03, speedSmooth = 0.06, maxStep = 0.1,
    maxTurn = 1500,      -- degrees a second past which the facing jumped (a loading screen, a port)
    maxSpeed = 100,      -- yards a second, likewise for your position
    turnPush = 500, strafePush = 12, runPush = 24, leanTurn = 600,
    bob = 1.6, bobSettleMin = 0.12, -- the bob's frequency (Hz, the health piece) and least damping
    slam = 1.1, slamBase = 0.6, slamFall = 0.9, fallFull = 1.5, jumpKick = 0.45,
    floatIn = 0.35, floatOut = 0.08,
    steps = 240, energyMax = 1.5, energySmooth = 0.3, churnGain = 1.5,
    bobUnits = 5, shiftUnits = 9, liftUnits = 3, ampBob = 0.6, swirl = 0.3, swirlMax = 0.4,
    carryBottom = 0.25,  -- the carry at a piece's bottom, of its top's (Sphere.lua moveLayer)
    room = 10,           -- units past the climb the surface strips reach (M.ROOM)
}
M.K = K
M.ROOM = SLOSH.climb + K.room -- units over and under the level the surface strips reach: the climb and the bob
local sense = { omega = 0, eff = 0, effPrev = 0, alpha = 0, vf = 0, vl = 0, fwd = 0, lat = 0, fwdPrev = 0,
    latPrev = 0, pushLat = 0, pushVert = 0, float = 0, air = false, airStart = 0, kick = 0, frameSlam = 0,
    frameKick = 0, clock = 0, via = "nothing yet", landings = 0, jumps = 0 }

if hooksecurefunc and JumpOrAscendStart then
    hooksecurefunc("JumpOrAscendStart", function() -- after the game's own: the push-off of a jump from the ground
        if not (IsFalling and IsFalling()) and not (IsSwimming and IsSwimming()) then
            sense.kick, sense.jumps = 1, sense.jumps + 1
        end
    end)
end

-- Once a frame, before the liquids: what your character did, as the pushes the liquids feel.
function M.Sample(elapsed)
    if not (elapsed and elapsed > 0) then return end
    local S, dt = sense, math.min(elapsed, K.maxStep)
    S.clock = S.clock + elapsed
    -- turning, degrees a second, + to the right (the facing turns counter-clockwise)
    local facing = GetPlayerFacing and GetPlayerFacing()
    local turn = 0
    if plain(facing) then
        if S.facing then
            turn = -math.deg((facing - S.facing + math.pi) % TWO_PI - math.pi) / elapsed
            if turn > K.maxTurn or turn < -K.maxTurn then turn = S.omega end
        end
        S.facing = facing
    else
        S.facing = nil
    end
    S.omega = smooth(S.omega, turn, dt, K.turnSmooth)
    local over = math.abs(S.omega) - SLOSH.threshold
    local eff = over > 0 and (S.omega > 0 and over or -over) or 0
    S.alpha = smooth(S.alpha, (eff - S.effPrev) / dt, dt, K.alphaSmooth)
    S.eff, S.effPrev = eff, eff
    -- moving: forward and sideways (+ right), yards a second
    local north, west
    if UnitPosition then north, west = UnitPosition("player") end
    local fwd, lat = S.vf, S.vl -- held through a jump in your position
    if plain(north) and plain(west) and plain(facing) then
        if S.north then
            local vn, vw = (north - S.north) / elapsed, (west - S.west) / elapsed
            if vn * vn + vw * vw < K.maxSpeed * K.maxSpeed then
                local c, s = math.cos(facing), math.sin(facing)
                fwd, lat = vn * c + vw * s, vn * s - vw * c
            end
        end
        S.north, S.west, S.via = north, west, "your position"
    else
        S.north, S.west = nil, nil
        local speed = GetUnitSpeed and GetUnitSpeed("player")
        fwd, lat, S.via = plain(speed) and speed or 0, 0, "your speed"
    end
    S.vf, S.vl = fwd, lat
    S.fwd, S.lat = smooth(S.fwd, fwd, dt, K.speedSmooth), smooth(S.lat, lat, dt, K.speedSmooth)
    local aFwd, aLat = (S.fwd - S.fwdPrev) / dt, (S.lat - S.latPrev) / dt
    S.fwdPrev, S.latPrev = S.fwd, S.lat
    -- the air: lighter while in it; a slam on landing, harder the longer the fall
    local falling = IsFalling and IsFalling() and true or false
    S.frameSlam, S.frameKick, S.kick = 0, S.kick, 0
    if falling and not S.air then
        S.air, S.airStart = true, S.clock
    elseif S.air and not falling then
        S.air, S.landings = false, S.landings + 1
        S.frameSlam = SLOSH.landing * (K.slamBase + K.slamFall * math.min(1, (S.clock - S.airStart) / K.fallFull))
    end
    S.float = smooth(S.float, S.air and SLOSH.float or 0, dt, S.air and K.floatIn or K.floatOut)
    -- the pushes through the liquid's weight (+ sideways: the body pushed right, the liquid lags left)
    S.pushLat = smooth(S.pushLat, S.alpha / K.turnPush + SLOSH.move * aLat / K.strafePush, dt, SLOSH.weight)
    S.pushVert = smooth(S.pushVert, SLOSH.move * aFwd / K.runPush, dt, SLOSH.weight) -- starting dips it, stopping lifts it
end

function M.Reset(bar)
    bar.sloshS, bar.sloshSV, bar.sloshB, bar.sloshBV, bar.sloshEnergy, bar.sloshW0 = 0, 0, 0, 0, 0, 1
end

-- One liquid's springs over `elapsed`; returns how far its clock moves (faster while it churns).
-- `bar.sloshRate`: a narrower vessel rocks faster (Sphere.lua, the root of the health piece's width
-- over its own).
function M.Step(bar, elapsed)
    local S, dt = sense, math.min(elapsed or 0, K.maxStep)
    if dt <= 0 then return 0 end
    if not bar.sloshS then M.Reset(bar) end
    local rate = bar.sloshRate or 1
    local w0 = TWO_PI * SLOSH.wobble * rate
    local k, c = w0 * w0, 2 * SLOSH.settle * w0
    local wb = TWO_PI * K.bob * rate
    local kb, cb = wb * wb, 2 * math.max(K.bobSettleMin, SLOSH.settle) * wb
    local s, sv, b, bv = bar.sloshS, bar.sloshSV, bar.sloshB, bar.sloshBV
    bv = bv - (S.frameSlam * K.slam + S.frameKick * K.jumpKick * SLOSH.strength) * wb
    local lean = -SLOSH.lean * S.eff / K.leanTurn
    local driveS, driveB = SLOSH.strength * w0 * S.pushLat, SLOSH.strength * wb * S.pushVert
    local n = math.ceil(dt * K.steps)
    local h = dt / n
    for _ = 1, n do
        sv = sv + (-k * (s - lean) - c * sv - driveS) * h
        s = s + sv * h
        bv = bv + (-kb * (b - S.float) - cb * bv - driveB) * h
        b = b + bv * h
    end
    bar.sloshS, bar.sloshSV, bar.sloshB, bar.sloshBV, bar.sloshW0 = s, sv, b, bv, w0
    local energy = math.min(K.energyMax, math.abs(s) + math.abs(sv) / w0 + 0.5 * math.abs(b) + 0.5 * math.abs(bv) / wb)
    bar.sloshEnergy = smooth(bar.sloshEnergy, energy, dt, K.energySmooth)
    return elapsed * (1 + SLOSH.churn * bar.sloshEnergy * K.churnGain)
end

-- How a liquid looks this frame: its surface's line `hL` and `hR` units over the level at its
-- walls (only up: the low side stays level, Sphere.lua SLOSH_EDGE), its waves stretched `amp`
-- times, its swirls carried `shift` units sideways at its top (K.carryBottom of it at its bottom)
-- and `lift` up, turned `swirl` radians. In its own units (`bar.unit`: the pet's ball is smaller).
function M.Shape(bar)
    local unit = bar.unit or 1
    local t = math.tanh(bar.sloshS or 0)
    local b = bar.sloshB or 0
    local climb, hc = t * SLOSH.climb * unit, b * K.bobUnits * unit
    local hL, hR = hc - climb, hc + climb
    if hL < 0 then hL = 0 end
    if hR < 0 then hR = 0 end
    local swirl = K.swirl * (bar.sloshSV or 0) / (bar.sloshW0 or 1) * SLOSH.drift
    if swirl > K.swirlMax then swirl = K.swirlMax elseif swirl < -K.swirlMax then swirl = -K.swirlMax end
    return hL, hR, 1 + K.ampBob * math.min(1, math.abs(b)), t * K.shiftUnits * SLOSH.drift * unit,
        b * K.liftUnits * SLOSH.drift * unit, swirl
end

function M.SloshDebug()
    local S = sense
    return string.format("turning %.0f°/s (%.0f past the threshold), moving %.1f forward and %.1f sideways yd/s (from %s), %s,"
        .. " %d jumps and %d landings seen; pushes %.2f sideways, %.2f up", S.omega, math.abs(S.eff), S.fwd, S.lat, S.via,
        S.air and "in the air" or "on the ground", S.jumps, S.landings, S.pushLat, S.pushVert)
end

function M.Toggle()
    panel = panel or build()
    if panel:IsShown() then
        panel:Hide()
        closed = GetTime()
        return false
    end
    for k in pairs(peak) do peak[k] = 0 end
    for k in pairs(win) do win[k] = 0 end
    lastFacing, lastX, lastY = nil, nil, nil
    opened, seen = GetTime(), true
    panel:Show()
    paint()
    return true
end

function M.Debug()
    if not seen then return "motion: not sampled yet (/spheres motion opens the live panel)" end
    return string.format("motion (/spheres motion, %.0f s, %d frames): turn peak %.0f°/s (facing %s), mouse peak %.0f /s"
        .. " (GetCursorDelta %s), camera drag: %s, peak %.0f /s over %d frames, cursor position moved %.0f /s at most meanwhile",
        (panel:IsShown() and GetTime() or closed) - opened, peak.frames, peak.turn, facingOK and "read" or "unread", peak.delta,
        GetCursorDelta and (deltaOK and "read" or "unread") or "missing", peak.dragFrames > 0 and "seen" or "not seen",
        peak.dragDelta, peak.dragFrames, peak.dragCursor)
end
