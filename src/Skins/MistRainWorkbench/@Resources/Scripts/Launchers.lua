local categoryCount, slotCount = 4, 5
local active = 1
local configPath, statePath, resultPath, launchResultPath = "", "", "", ""
local values = {}
local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function decode(data)
    data = (data or ""):gsub('[^' .. chars .. '=]', '')
    if data == "" then return "" end
    local raw = data:gsub('.', function(char)
        if char == '=' then return '' end
        local found = chars:find(char, 1, true)
        if not found then return '' end
        local value = found - 1
        local bits = ''
        for i = 6, 1, -1 do bits = bits .. (value % 2 ^ i - value % 2 ^ (i - 1) > 0 and '1' or '0') end
        return bits
    end)
    raw = raw:sub(1, math.floor(#raw / 8) * 8)
    return (raw:gsub('%d%d%d%d%d%d%d%d', function(byte)
        local value = 0
        for i = 1, 8 do value = value + (byte:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
        return string.char(value)
    end))
end

local function readBinary(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local data = file:read('*all') or ''
    file:close()
    if data:sub(1, 3) == string.char(239, 187, 191) then data = data:sub(4) end
    return data
end

local function writePending()
    local file = io.open(resultPath, 'wb')
    if not file then return false end
    file:write("Version=1\r\nStatus=pending\r\nMode=\r\nCategory=0\r\nSlot=0\r\nDetail=\r\n")
    file:close()
    return true
end

local function writeLaunchPending()
    local file = io.open(launchResultPath, 'wb')
    if not file then return false end
    file:write("Version=1\r\nStatus=pending\r\nDetail=\r\n")
    file:close()
    return true
end
local function parseKeys(data)
    local map = {}
    for line in (data or ''):gmatch('[^\r\n]+') do
        local key, value = line:match('^([^=]+)=(.*)$')
        if key then map[key] = value end
    end
    return map
end

local function setStatus(text, color)
    SKIN:Bang('!SetOption', 'MeterLauncherStatus', 'Text', text or '')
    SKIN:Bang('!SetOption', 'MeterLauncherStatus', 'FontColor', color or '#TextFaint#')
    SKIN:Bang('!UpdateMeter', 'MeterLauncherStatus')
end

local function readConfig()
    values = parseKeys(readBinary(configPath) or '')
    return values.Version == '1'
end

local function setSlot(index)
    local key = 'Slot' .. active .. '_' .. index
    local name = decode(values[key .. 'Name'])
    local command = decode(values[key .. 'Command'])
    local icon = decode(values[key .. 'Icon'])
    local configured = name ~= '' and command ~= ''
    -- Lua 5.1 file APIs are ANSI-only on Windows. The Unicode bridge
    -- validates and starts the configured command without round-tripping it here.
    local available = configured
    local configure = '[!CommandMeasure MeasureLaunchers "ConfigureSlot(' .. active .. ',' .. index .. ')"]'
    local action = configure
    if available then action = '[!CommandMeasure MeasureLaunchers "Launch(' .. active .. ',' .. index .. ')"]' end

    SKIN:Bang('!SetOption', 'MeterSlotLabel' .. index, 'Text', name ~= '' and name or '+')
    SKIN:Bang('!SetOption', 'MeterSlotLabel' .. index, 'FontColor', available and '#TextMuted#' or (configured and '#DisabledColor#' or '#TextFaint#'))
    SKIN:Bang('!SetOption', 'MeterSlotLabel' .. index, 'LeftMouseUpAction', action)
    SKIN:Bang('!SetOption', 'MeterSlotLabel' .. index, 'RightMouseUpAction', configure)
    SKIN:Bang('!SetOption', 'MeterSlotIcon' .. index, 'ImageName', icon ~= '' and icon or '#IconAssets#notes-neutral.png')
    SKIN:Bang('!SetOption', 'MeterSlotIcon' .. index, 'ImageAlpha', available and '220' or (configured and '60' or '0'))
    SKIN:Bang('!SetOption', 'MeterSlotIcon' .. index, 'LeftMouseUpAction', action)
    SKIN:Bang('!SetOption', 'MeterSlotIcon' .. index, 'RightMouseUpAction', configure)
    local tip = configured and SKIN:GetVariable('LauncherOpenHint', 'Open shortcut') or 'Configure shortcut'
    SKIN:Bang('!SetOption', 'MeterSlotIcon' .. index, 'ToolTipText', tip)
    SKIN:Bang('!SetOption', 'MeterSlotLabel' .. index, 'ToolTipText', tip)
end

local function refresh()
    if not readConfig() then
        setStatus(SKIN:GetVariable('LauncherStatusError', 'Unable to read launcher config'), '#ErrorColor#')
        SKIN:Bang('!Redraw')
        return
    end
    for index = 1, categoryCount do
        local name = decode(values['Category' .. index .. 'Name'])
        SKIN:Bang('!SetOption', 'MeterCategory' .. index, 'Text', name ~= '' and name or ('Category ' .. index))
        SKIN:Bang('!SetOption', 'MeterCategory' .. index, 'FontColor', index == active and '#TextColor#' or '#TextFaint#')
    end
    SKIN:Bang('!SetOption', 'MeterCategorySelection', 'X', tostring(15 + (active - 1) * 61))
    for index = 1, slotCount do
        local ok = pcall(setSlot, index)
        if not ok then
            SKIN:Bang('!SetOption', 'MeterSlotLabel' .. index, 'Text', '!')
            SKIN:Bang('!SetOption', 'MeterSlotLabel' .. index, 'LeftMouseUpAction', '[!CommandMeasure MeasureLaunchers "ConfigureSlot(' .. active .. ',' .. index .. ')"]')
        end
    end
    SKIN:Bang('!UpdateMeterGroup', 'LauncherDynamic')
    SKIN:Bang('!Redraw')
end

function Initialize()
    configPath = SKIN:GetVariable('LauncherConfigFile')
    statePath = SKIN:GetVariable('LauncherStateFile')
    resultPath = SKIN:GetVariable('LauncherSettingsResultFile')
    launchResultPath = SKIN:GetVariable('LauncherLaunchResultFile')
    active = math.max(1, math.min(categoryCount, tonumber(SKIN:GetVariable('ActiveLauncherCategory', '1')) or 1))
    setStatus('', '#TextFaint#')
    refresh()
end

function SelectCategory(index)
    active = math.max(1, math.min(categoryCount, tonumber(index) or active))
    SKIN:Bang('!WriteKeyValue', 'Variables', 'ActiveLauncherCategory', tostring(active), statePath)
    setStatus('', '#TextFaint#')
    refresh()
end

local function settings(mode, category, slot)
    if not writePending() then
        setStatus(SKIN:GetVariable('LauncherStatusError'), '#ErrorColor#')
        SKIN:Bang('!Redraw')
        return
    end
    setStatus(SKIN:GetVariable('LauncherStatusOpening'), '#TextFaint#')
    SKIN:Bang('!Redraw')
    local parameter = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "#@#Scripts\\ShowLauncherSettings.ps1" -Mode ' .. mode .. ' -Category ' .. category .. ' -Slot ' .. slot .. ' -ConfigPath "#LauncherConfigFile#" -ResultPath "#LauncherSettingsResultFile#" -IconDirectory "#LauncherIconDirectory#"'
    SKIN:Bang('!SetOption', 'MeasureLauncherSettings', 'Parameter', parameter)
    SKIN:Bang('!CommandMeasure', 'MeasureLauncherSettings', 'Run')
end

function ConfigureSlot(category, slot) settings('slot', category, slot) end
function ConfigureCategory(category) settings('category', category, 0) end

function Launch(category, slot)
    category = math.max(1, math.min(categoryCount, tonumber(category) or active))
    slot = math.max(1, math.min(slotCount, tonumber(slot) or 1))
    if not writeLaunchPending() then
        setStatus(SKIN:GetVariable('LauncherStatusLaunchError'), '#ErrorColor#')
        SKIN:Bang('!Redraw')
        return
    end
    setStatus(SKIN:GetVariable('LauncherStatusLaunching'), '#TextFaint#')
    SKIN:Bang('!Redraw')
    local parameter = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "#@#Scripts\LaunchShortcut.ps1" -Category ' .. category .. ' -Slot ' .. slot .. ' -ConfigPath "#LauncherConfigFile#" -ResultPath "#LauncherLaunchResultFile#"'
    SKIN:Bang('!SetOption', 'MeasureLauncherRun', 'Parameter', parameter)
    SKIN:Bang('!CommandMeasure', 'MeasureLauncherRun', 'Run')
end

function LaunchFinished()
    local result = parseKeys(readBinary(launchResultPath) or '')
    local status = result.Status or 'error'
    if status == 'ok' then
        setStatus(SKIN:GetVariable('LauncherStatusLaunched'), '#TextFaint#')
    elseif status == 'missing' then
        setStatus(SKIN:GetVariable('LauncherStatusLaunchMissing'), '#WarningColor#')
    else
        setStatus(SKIN:GetVariable('LauncherStatusLaunchError'), '#ErrorColor#')
    end
    SKIN:Bang('!Redraw')
end
function SettingsFinished()
    local result = parseKeys(readBinary(resultPath) or '')
    local status = result.Status or 'error'
    if status == 'ok' then
        local text = result.Mode == 'category' and SKIN:GetVariable('LauncherStatusCategoryUpdated') or SKIN:GetVariable('LauncherStatusUpdated')
        setStatus(text, '#TextFaint#')
    elseif status == 'cancel' then
        setStatus('', '#TextFaint#')
    elseif status == 'invalid_input' then
        setStatus(SKIN:GetVariable('LauncherStatusInvalid'), '#WarningColor#')
    elseif status == 'missing_file' then
        setStatus(SKIN:GetVariable('LauncherStatusMissing'), '#WarningColor#')
    else
        setStatus(SKIN:GetVariable('LauncherStatusError'), '#ErrorColor#')
    end
    refresh()
end

function Update() return 0 end