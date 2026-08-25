local lastKey = ""
local monthOffset = 0

local function daysInMonth(year, month)
    return os.date("*t", os.time({ year = year, month = month + 1, day = 0, hour = 12 })).day
end

local function populate()
    local now = os.date("*t")
    local target = os.date("*t", os.time({ year = now.year, month = now.month + monthOffset, day = 1, hour = 12 }))
    local key = string.format("%04d-%02d-%02d-%d", now.year, now.month, now.day, monthOffset)
    if key == lastKey then return end
    lastKey = key

    local monthName = SKIN:GetVariable(string.format("Month%02d", target.month), tostring(target.month))
    SKIN:Bang("!SetOption", "MeterMonth", "Text", monthName .. "  " .. target.year)

    local first = os.date("*t", os.time({ year = target.year, month = target.month, day = 1, hour = 12 }))
    local offset = (first.wday + 5) % 7
    local total = daysInMonth(target.year, target.month)
    local previousYear = target.year
    local previousMonth = target.month - 1
    if previousMonth == 0 then
        previousMonth = 12
        previousYear = previousYear - 1
    end
    local previousTotal = daysInMonth(previousYear, previousMonth)

    for i = 1, 42 do
        local day = i - offset
        local meter = string.format("MeterDay%02d", i)
        if day < 1 then
            SKIN:Bang("!SetOption", meter, "Text", tostring(previousTotal + day))
            SKIN:Bang("!SetOption", meter, "FontColor", "#TextFaint#")
        elseif day > total then
            SKIN:Bang("!SetOption", meter, "Text", tostring(day - total))
            SKIN:Bang("!SetOption", meter, "FontColor", "#TextFaint#")
        else
            SKIN:Bang("!SetOption", meter, "Text", tostring(day))
            if monthOffset == 0 and day == now.day then
                SKIN:Bang("!SetOption", meter, "FontColor", "#TextColor#")
                SKIN:Bang("!SetOption", "MeterToday", "Hidden", "0")
                SKIN:Bang("!SetOption", "MeterToday", "X", tostring(15 + ((i - 1) % 7) * 42))
                SKIN:Bang("!SetOption", "MeterToday", "Y", tostring(82 + math.floor((i - 1) / 7) * 29))
            else
                SKIN:Bang("!SetOption", meter, "FontColor", "#TextMuted#")
            end
        end
    end
    SKIN:Bang("!UpdateMeter", "MeterMonth")
    SKIN:Bang("!UpdateMeter", "MeterToday")
    SKIN:Bang("!UpdateMeterGroup", "CalendarDays")
    SKIN:Bang("!Redraw")
end

function Initialize()
    populate()
end

function Update()
    populate()
    return 0
end

function Navigate(delta)
    monthOffset = monthOffset + (tonumber(delta) or 0)
    lastKey = ""
    SKIN:Bang("!SetOption", "MeterToday", "Hidden", "1")
    populate()
end

function ResetMonth()
    monthOffset = 0
    lastKey = ""
    populate()
end
