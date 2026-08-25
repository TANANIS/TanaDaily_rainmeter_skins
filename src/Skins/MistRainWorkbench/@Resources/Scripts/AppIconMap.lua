local icons = {
    ["Browser"] = "browser.png",
    ["VS Code"] = "vscode.png",
    ["Unity"] = "unity.png",
    ["Explorer"] = "explorer.png",
    ["Notes"] = "notes.png",
    ["Discord"] = "discord.png",
    ["Steam"] = "steam.png",
    ["Rainmeter"] = "rainmeter.png",
    ["Windows Apps"] = "windows-apps.png",
    ["League of Legends"] = "league.png",
    ["Riot Client"] = "riot.png",
    ["ChatGPT"] = "chatgpt.png"
}

local last = ""

local function apply()
    local signature = ""
    for i = 1, 5 do
        local name = SKIN:GetVariable("App" .. i .. "Name", "")
        signature = signature .. "|" .. name
        local image = icons[name] or "generic.png"
        SKIN:Bang("!SetOption", "MeterApp" .. i .. "Icon", "ImageName", "#IconAssets#" .. image)
    end
    if signature ~= last then
        last = signature
        for i = 1, 5 do
            SKIN:Bang("!UpdateMeter", "MeterApp" .. i .. "Icon")
        end
        SKIN:Bang("!Redraw")
    end
end

function Initialize()
    apply()
end

function Update()
    apply()
    return 0
end
