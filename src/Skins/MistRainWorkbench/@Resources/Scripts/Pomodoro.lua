local timerCount = 4
local timers = {}
local activeTimer = 1
local stateFile = ""
local settingsResultPath = ""
local base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function formatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function encodeBase64(data)
    return ((data:gsub('.', function(char)
        local byte = char:byte()
        local bits = ''
        for i = 8, 1, -1 do bits = bits .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and '1' or '0') end
        return bits
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(chunk)
        if #chunk < 6 then return '' end
        local value = 0
        for i = 1, 6 do value = value + (chunk:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        return base64Chars:sub(value + 1, value + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function decodeBase64(data)
    data = (data or ""):gsub('[^' .. base64Chars .. '=]', '')
    local rawBits = data:gsub('.', function(char)
        if char == '=' then return '' end
        local value = base64Chars:find(char, 1, true) - 1
        local bits = ''
        for i = 6, 1, -1 do bits = bits .. (value % 2 ^ i - value % 2 ^ (i - 1) > 0 and '1' or '0') end
        return bits
    end)
    rawBits = rawBits:sub(1, math.floor(#rawBits / 8) * 8)
    return (rawBits:gsub('%d%d%d%d%d%d%d%d', function(byte)
        local value = 0
        for i = 1, 8 do value = value + (byte:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
        return string.char(value)
    end))
end

local function readBinary(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local data = file:read("*all") or ""
    file:close()
    if data:sub(1, 3) == string.char(239, 187, 191) then data = data:sub(4) end
    return data
end

local function defaultTimer(index)
    local minutes = clamp(tonumber(SKIN:GetVariable("FocusDefaultMinutes", "25")) or 25, 1, 180)
    return {
        nameBase64 = encodeBase64("Timer " .. index),
        duration = minutes * 60,
        remaining = minutes * 60,
        running = false,
        endTimestamp = 0,
        completionCount = 0
    }
end

local function serializeTimer(timer)
    return string.format("%d|%d|%d|%d|%d", timer.duration, math.max(0, math.floor(timer.remaining + 0.5)), timer.running and 1 or 0, timer.endTimestamp, timer.completionCount)
end

local function persistTimer(index)
    local timer = timers[index]
    SKIN:Bang("!WriteKeyValue", "Variables", "Timer" .. index .. "Name", timer.nameBase64, stateFile)
    SKIN:Bang("!WriteKeyValue", "Variables", "Timer" .. index .. "State", serializeTimer(timer), stateFile)
end

local function persistHeader()
    SKIN:Bang("!WriteKeyValue", "Variables", "FocusStateVersion", "2", stateFile)
    SKIN:Bang("!WriteKeyValue", "Variables", "ActiveTimer", tostring(activeTimer), stateFile)
end

local function persistAll()
    persistHeader()
    for i = 1, timerCount do persistTimer(i) end
end

local function parseTimer(raw, fallback)
    local duration, remaining, running, ending, completions = (raw or ""):match("^(%d+)|(%d+)|([01])|(%d+)|(%d+)$")
    if not duration then return fallback end
    fallback.duration = clamp(tonumber(duration) or fallback.duration, 60, 10800)
    fallback.remaining = clamp(tonumber(remaining) or fallback.duration, 0, fallback.duration)
    fallback.running = running == "1"
    fallback.endTimestamp = tonumber(ending) or 0
    fallback.completionCount = math.max(0, tonumber(completions) or 0)
    return fallback
end

local function loadState()
    stateFile = SKIN:GetVariable("PomodoroStateFile")
    settingsResultPath = SKIN:GetVariable("FocusSettingsResultFile")
    local version = tonumber(SKIN:GetVariable("FocusStateVersion", "0")) or 0
    activeTimer = clamp(tonumber(SKIN:GetVariable("ActiveTimer", "1")) or 1, 1, timerCount)
    for i = 1, timerCount do timers[i] = defaultTimer(i) end

    if version == 2 then
        for i = 1, timerCount do
            local name = SKIN:GetVariable("Timer" .. i .. "Name", timers[i].nameBase64)
            if decodeBase64(name) ~= "" then timers[i].nameBase64 = name end
            timers[i] = parseTimer(SKIN:GetVariable("Timer" .. i .. "State", ""), timers[i])
        end
    else
        timers[1] = parseTimer(SKIN:GetVariable("TimerState", ""), timers[1])
        persistAll()
    end
end

local function phase(timer)
    if timer.running then return "running" end
    if timer.remaining <= 0 then return "finished" end
    if timer.remaining >= timer.duration then return "ready" end
    return "paused"
end

local function playFinishSound()
    local sound = SKIN:GetVariable("PomodoroFinishSound", "")
    if sound == "" then return end
    local file = io.open(sound, "rb")
    if file then file:close() SKIN:Bang("!Play", sound) end
end

local function completeTimer(index, notify)
    local timer = timers[index]
    timer.remaining = 0
    timer.running = false
    timer.endTimestamp = 0
    timer.completionCount = timer.completionCount + 1
    persistTimer(index)
    if notify then playFinishSound() end
end

local function syncTimer(index, notify)
    local timer = timers[index]
    if not timer.running then return end
    timer.remaining = math.max(0, timer.endTimestamp - os.time())
    if timer.remaining <= 0 then completeTimer(index, notify) end
end

local function refreshMeters()
    local timer = timers[activeTimer]
    local current = phase(timer)
    local stateText = SKIN:GetVariable("PomodoroStateReady")
    local stateColor = "#Accent#"
    local timeColor = "#TextColor#"
    local ringColor = "#Accent#"
    local startLabel = SKIN:GetVariable("PomodoroLabelStart")
    local startColor = "#Accent#"
    local pauseColor = "#DisabledColor#"

    if current == "running" then
        stateText = SKIN:GetVariable("PomodoroStateRunning")
        startLabel = SKIN:GetVariable("PomodoroLabelRunning")
        startColor = "#DisabledColor#"
        pauseColor = "#HoverColor#"
    elseif current == "paused" then
        stateText = SKIN:GetVariable("PomodoroStatePaused")
        stateColor = "#WarningColor#"
        startLabel = SKIN:GetVariable("PomodoroLabelResume")
    elseif current == "finished" then
        stateText = SKIN:GetVariable("PomodoroStateFinished")
        stateColor = "#SuccessColor#"
        timeColor = "#SuccessColor#"
        ringColor = "#SuccessColor#"
    end

    local timerName = decodeBase64(timer.nameBase64)
    SKIN:Bang("!SetOption", "MeterMode", "Text", timerName)
    SKIN:Bang("!SetOption", "MeterMode", "ToolTipText", timerName)
    SKIN:Bang("!SetOption", "MeterTime", "Text", formatTime(timer.remaining))
    SKIN:Bang("!SetOption", "MeterTime", "FontColor", timeColor)
    SKIN:Bang("!SetOption", "MeterState", "Text", stateText)
    SKIN:Bang("!SetOption", "MeterState", "FontColor", stateColor)
    SKIN:Bang("!SetOption", "MeterRing", "LineColor", ringColor)
    SKIN:Bang("!SetOption", "MeterStart", "FontColor", startColor)
    SKIN:Bang("!SetOption", "MeterStartLabel", "FontColor", startColor)
    SKIN:Bang("!SetOption", "MeterStartLabel", "Text", startLabel)
    SKIN:Bang("!SetOption", "MeterPause", "FontColor", pauseColor)
    SKIN:Bang("!SetOption", "MeterPauseLabel", "FontColor", pauseColor)
    SKIN:Bang("!SetOption", "MeasureInputMinutes", "DefaultValue", tostring(math.floor(timer.duration / 60)))
    SKIN:Bang("!SetOption", "MeterTimerSelection", "X", tostring(90 + (activeTimer - 1) * 39))

    for i = 1, timerCount do
        local itemPhase = phase(timers[i])
        local bulletColor = "#TrackColor#"
        if i == activeTimer then bulletColor = "#Accent#"
        elseif itemPhase == "running" then bulletColor = "#SuccessColor#"
        elseif itemPhase == "paused" then bulletColor = "#WarningColor#"
        elseif itemPhase == "finished" then bulletColor = "#SuccessColor#" end
        SKIN:Bang("!SetOption", "MeterSession" .. i, "FontColor", bulletColor)
        SKIN:Bang("!SetOption", "MeterSessionNumber" .. i, "FontColor", i == activeTimer and "#TextColor#" or "#TextFaint#")
        SKIN:Bang("!SetOption", "MeterTimerHit" .. i, "ToolTipText", decodeBase64(timers[i].nameBase64))
    end
    SKIN:Bang("!UpdateMeterGroup", "PomodoroDynamic")
    SKIN:Bang("!UpdateMeter", "MeterMode")
    SKIN:Bang("!UpdateMeter", "MeterTimerSelection")
    SKIN:Bang("!Redraw")
end

function Initialize()
    loadState()
    for i = 1, timerCount do syncTimer(i, true) end
    refreshMeters()
end

function SelectTimer(index)
    index = clamp(tonumber(index) or activeTimer, 1, timerCount)
    activeTimer = index
    persistHeader()
    refreshMeters()
end

function Start()
    local timer = timers[activeTimer]
    if timer.running then return end
    if timer.remaining <= 0 then timer.remaining = timer.duration end
    timer.running = true
    timer.endTimestamp = os.time() + math.floor(timer.remaining + 0.5)
    persistTimer(activeTimer)
    refreshMeters()
end

function Pause()
    local timer = timers[activeTimer]
    if not timer.running then return end
    timer.remaining = math.max(0, timer.endTimestamp - os.time())
    timer.running = false
    timer.endTimestamp = 0
    persistTimer(activeTimer)
    refreshMeters()
end

function Reset()
    local timer = timers[activeTimer]
    timer.running = false
    timer.remaining = timer.duration
    timer.endTimestamp = 0
    persistTimer(activeTimer)
    refreshMeters()
end

function SetMinutes(value)
    local minutes = tonumber(value)
    if not minutes then return end
    minutes = clamp(math.floor(minutes + 0.5), 1, 180)
    local timer = timers[activeTimer]
    timer.running = false
    timer.duration = minutes * 60
    timer.remaining = timer.duration
    timer.endTimestamp = 0
    persistTimer(activeTimer)
    refreshMeters()
end

function AdjustMinutes(delta)
    SetMinutes((timers[activeTimer].duration / 60) + (tonumber(delta) or 0))
end

function EditTimer(index)
    SelectTimer(index)
    local timer = timers[activeTimer]
    local parameter = '-NoProfile -ExecutionPolicy Bypass -STA -File "#@#Scripts\\ShowTimerSettings.ps1" -OutputPath "#FocusSettingsResultFile#" -DefaultNameBase64 "' .. timer.nameBase64 .. '" -DefaultMinutes ' .. tostring(math.floor(timer.duration / 60))
    SKIN:Bang("!SetOption", "MeasureTimerSettings", "Parameter", parameter)
    SKIN:Bang("!CommandMeasure", "MeasureTimerSettings", "Run")
end

function SettingsFinished()
    local result = readBinary(settingsResultPath) or ""
    local status = result:match("\nStatus=([^\r\n]+)") or result:match("^Status=([^\r\n]+)") or "error"
    if status ~= "ok" then return end
    local nameBase64 = result:match("\nNameBase64=([^\r\n]+)") or ""
    local minutes = tonumber(result:match("\nMinutes=(%d+)") or "")
    if nameBase64 == "" or decodeBase64(nameBase64) == "" or not minutes then return end
    local timer = timers[activeTimer]
    timer.nameBase64 = nameBase64
    timer.duration = clamp(minutes, 1, 180) * 60
    timer.remaining = timer.duration
    timer.running = false
    timer.endTimestamp = 0
    persistTimer(activeTimer)
    refreshMeters()
end

function Update()
    for i = 1, timerCount do syncTimer(i, true) end
    refreshMeters()
    local timer = timers[activeTimer]
    if timer.duration <= 0 then return 0 end
    return (timer.remaining / timer.duration) * 100
end
