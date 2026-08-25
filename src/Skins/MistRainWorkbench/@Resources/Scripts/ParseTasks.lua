local maxTasks = 6
local sourcePath = ""
local cachePath = ""
local requestPath = ""
local resultPath = ""
local lastSource = false
local building = false
local pendingBuild = false
local writing = false
local adding = false
local postBuildMessage = ""
local currentItems = {}
local sourceHash = ""
local inputResultPath = ""

local function readBinary(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local data = file:read("*all") or ""
    file:close()
    if data:sub(1, 3) == string.char(239, 187, 191) then data = data:sub(4) end
    return data
end

local function writeAscii(path, content)
    local file = io.open(path, "wb")
    if not file then return false end
    file:write(content)
    file:close()
    return true
end

local base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
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

local function setStatus(text, color)
    SKIN:Bang("!SetOption", "MeterStatus", "Text", text or "")
    SKIN:Bang("!SetOption", "MeterStatus", "FontColor", color or "#TextFaint#")
end

local function clearRows()
    currentItems = {}
    for i = 1, maxTasks do
        SKIN:Bang("!SetOption", "MeterTaskBullet" .. i, "Text", "")
        SKIN:Bang("!SetOption", "MeterTaskText" .. i, "Text", "")
        SKIN:Bang("!SetOption", "MeterTaskText" .. i, "ToolTipText", "")
        SKIN:Bang("!SetOption", "MeterTaskBullet" .. i, "LeftMouseUpAction", "[]")
        SKIN:Bang("!SetOption", "MeterTaskBullet" .. i, "Hidden", "1")
        SKIN:Bang("!SetOption", "MeterTaskText" .. i, "Hidden", "1")
    end
end

local function showEmpty(visible)
    local value = visible and "0" or "1"
    SKIN:Bang("!SetOption", "MeterEmptyTitle", "Hidden", value)
    SKIN:Bang("!SetOption", "MeterEmptyHint", "Hidden", value)
end

local function parseCache(content)
    local version = tonumber(content:match("^Version=(%d+)")) or 0
    local status = content:match("\nStatus=([^\r\n]+)") or "bridge_error"
    local hash = content:match("\nSourceHash=([A-Fa-f0-9]+)") or ""
    local items = {}
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do
        local done, sourceLine, text = line:match("^Item%d+=(%d)|(%d+)|(.*)$")
        if done and sourceLine and text then
            items[#items + 1] = { done = done == "1", line = tonumber(sourceLine), text = text }
            if #items >= maxTasks then break end
        end
    end
    return version, status, hash, items
end

local function renderCache()
    local content = readBinary(cachePath)
    clearRows()
    showEmpty(false)
    if not content then
        setStatus(SKIN:GetVariable("TodoStatusBridgeError"), "#ErrorColor#")
        return
    end
    local version, status, hash, items = parseCache(content)
    if version ~= 2 then
        setStatus(SKIN:GetVariable("TodoStatusBridgeError"), "#ErrorColor#")
        return
    end
    sourceHash = hash
    if status == "missing" then
        setStatus(SKIN:GetVariable("TodoStatusMissing"), "#ErrorColor#")
        return
    elseif status == "empty" then
        setStatus("", "#TextFaint#")
        showEmpty(true)
        return
    elseif status == "parse_error" then
        setStatus(SKIN:GetVariable("TodoStatusParseError"), "#WarningColor#")
        return
    elseif status ~= "ok" and status ~= "partial" then
        setStatus(SKIN:GetVariable("TodoStatusBridgeError"), "#ErrorColor#")
        return
    end
    setStatus(status == "partial" and SKIN:GetVariable("TodoStatusParseError") or "", "#WarningColor#")
    currentItems = items
    for i, item in ipairs(items) do
        local bulletColor = item.done and "#AccentDim#" or "#TextMuted#"
        local textColor = item.done and "#TextFaint#" or "#TextColor#"
        local style = item.done and "Italic" or "Normal"
        SKIN:Bang("!SetOption", "MeterTaskBullet" .. i, "Text", item.done and SKIN:GetVariable("TodoBulletDone") or SKIN:GetVariable("TodoBulletOpen"))
        SKIN:Bang("!SetOption", "MeterTaskBullet" .. i, "FontColor", bulletColor)
        SKIN:Bang("!SetOption", "MeterTaskBullet" .. i, "LeftMouseUpAction", '[!CommandMeasure MeasureTasks "Toggle(' .. i .. ')"]')
        SKIN:Bang("!SetOption", "MeterTaskText" .. i, "FontColor", textColor)
        SKIN:Bang("!SetOption", "MeterTaskText" .. i, "StringStyle", style)
        SKIN:Bang("!SetOption", "MeterTaskBullet" .. i, "Hidden", "0")
        SKIN:Bang("!SetOption", "MeterTaskText" .. i, "Hidden", "0")
    end
end

local function requestBuild()
    if building then pendingBuild = true return end
    building = true
    setStatus(SKIN:GetVariable("TodoStatusLoading"), "#TextFaint#")
    SKIN:Bang("!UpdateMeter", "MeterStatus")
    SKIN:Bang("!Redraw")
    SKIN:Bang("!CommandMeasure", "MeasureTaskBridge", "Run")
end

function Initialize()
    sourcePath = SKIN:GetVariable("TasksFile")
    cachePath = SKIN:GetVariable("TasksCacheFile")
    requestPath = SKIN:GetVariable("TasksRequestFile")
    resultPath = SKIN:GetVariable("TasksResultFile")
    inputResultPath = SKIN:GetVariable("TasksInputResultFile")
    lastSource = readBinary(sourcePath)
    renderCache()
    requestBuild()
end

function Reload()
    building = false
    renderCache()
    SKIN:Bang("!CommandMeasure", "MeasureTaskRender", "Update")
    if postBuildMessage ~= "" then
        setStatus(postBuildMessage, "#TextFaint#")
        postBuildMessage = ""
    end
    SKIN:Bang("!UpdateMeterGroup", "TaskRows")
    SKIN:Bang("!UpdateMeter", "MeterEmptyTitle")
    SKIN:Bang("!UpdateMeter", "MeterEmptyHint")
    SKIN:Bang("!UpdateMeter", "MeterStatus")
    SKIN:Bang("!Redraw")
    if pendingBuild then pendingBuild = false requestBuild() end
end

function OpenAdd()
    if writing or building then return end
    local pending = table.concat({ "Version=1", "Status=pending", "TitleBase64=", "Detail=", "" }, "\r\n")
    if not writeAscii(inputResultPath, pending) then
        setStatus(SKIN:GetVariable("TodoStatusWriteError"), "#ErrorColor#")
        SKIN:Bang("!UpdateMeter", "MeterStatus")
        SKIN:Bang("!Redraw")
        return
    end
    adding = true
    setStatus(SKIN:GetVariable("TodoStatusInput"), "#TextFaint#")
    SKIN:Bang("!UpdateMeter", "MeterStatus")
    SKIN:Bang("!Redraw")
    SKIN:Bang("!CommandMeasure", "MeasureTaskInput", "Run")
end

function InputFinished()
    if not adding or writing or building or sourceHash == "" then return end
    adding = false
    local result = readBinary(inputResultPath) or ""
    local status = result:match("\nStatus=([^\r\n]+)") or result:match("^Status=([^\r\n]+)") or "error"
    if status == "cancel" then
        setStatus("", "#TextFaint#")
        SKIN:Bang("!UpdateMeter", "MeterStatus")
        SKIN:Bang("!Redraw")
        return
    end
    local titleBase64 = result:match("\nTitleBase64=([^\r\n]+)") or ""
    if status ~= "ok" or titleBase64 == "" then
        setStatus(status == "invalid_input" and SKIN:GetVariable("TodoStatusInvalidInput") or SKIN:GetVariable("TodoStatusWriteError"), status == "invalid_input" and "#WarningColor#" or "#ErrorColor#")
        SKIN:Bang("!UpdateMeter", "MeterStatus")
        SKIN:Bang("!Redraw")
        return
    end
    local payload = table.concat({
        "Version=1",
        "Action=Add",
        "ExpectedHash=" .. sourceHash,
        "TitleBase64=" .. titleBase64,
        ""
    }, "\r\n")
    if not writeAscii(requestPath, payload) then
        adding = false
        setStatus(SKIN:GetVariable("TodoStatusWriteError"), "#ErrorColor#")
        SKIN:Bang("!UpdateMeter", "MeterStatus")
        SKIN:Bang("!Redraw")
        return
    end
    adding = false
    writing = true
    setStatus(SKIN:GetVariable("TodoStatusWriting"), "#TextFaint#")
    SKIN:Bang("!UpdateMeter", "MeterStatus")
    SKIN:Bang("!Redraw")
    SKIN:Bang("!CommandMeasure", "MeasureTaskWriter", "Run")
end

function Toggle(index)
    index = tonumber(index)
    if writing or building or not index or not currentItems[index] or sourceHash == "" then return end
    local item = currentItems[index]
    local payload = table.concat({
        "Version=1",
        "Action=Toggle",
        "LineNumber=" .. tostring(item.line),
        "ExpectedHash=" .. sourceHash,
        ""
    }, "\r\n")
    if not writeAscii(requestPath, payload) then
        setStatus(SKIN:GetVariable("TodoStatusWriteError"), "#ErrorColor#")
        SKIN:Bang("!UpdateMeter", "MeterStatus")
        SKIN:Bang("!Redraw")
        return
    end
    writing = true
    setStatus(SKIN:GetVariable("TodoStatusWriting"), "#TextFaint#")
    SKIN:Bang("!UpdateMeter", "MeterStatus")
    SKIN:Bang("!Redraw")
    SKIN:Bang("!CommandMeasure", "MeasureTaskWriter", "Run")
end

function WriteFinished()
    writing = false
    local result = readBinary(resultPath) or ""
    local status = result:match("\nStatus=([^\r\n]+)") or result:match("^Status=([^\r\n]+)") or "write_error"
    local action = result:match("\nAction=([^\r\n]+)") or ""
    if status == "ok" then
        postBuildMessage = action == "Add" and SKIN:GetVariable("TodoStatusAdded") or SKIN:GetVariable("TodoStatusUpdated")
        requestBuild()
    elseif status == "conflict" then
        setStatus(SKIN:GetVariable("TodoStatusConflict"), "#WarningColor#")
        requestBuild()
    elseif status == "encoding_error" then
        setStatus(SKIN:GetVariable("TodoStatusEncodingError"), "#ErrorColor#")
    elseif status == "invalid_input" then
        setStatus(SKIN:GetVariable("TodoStatusInvalidInput"), "#WarningColor#")
    else
        setStatus(SKIN:GetVariable("TodoStatusWriteError"), "#ErrorColor#")
    end
    SKIN:Bang("!UpdateMeter", "MeterStatus")
    SKIN:Bang("!Redraw")
end

function Update()
    local source = readBinary(sourcePath)
    if source ~= lastSource then
        lastSource = source
        requestBuild()
    end
    return 0
end
