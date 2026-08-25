local launchers = {
    { variable = "BrowserCommand", icon = "MeterBrowserIcon", label = "MeterBrowser" },
    { variable = "UnityCommand", icon = "MeterUnityIcon", label = "MeterUnity" },
    { variable = "VSCodeCommand", icon = "MeterCodeIcon", label = "MeterCode" },
    { variable = "ExplorerCommand", icon = "MeterExplorerIcon", label = "MeterExplorer" },
    { variable = "NotesCommand", icon = "MeterNotesIcon", label = "MeterNotes" }
}

local function exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

function Initialize()
    local missingFormat = SKIN:GetVariable("LaunchMissingFormat", "Missing: %s")
    for _, launcher in ipairs(launchers) do
        local path = SKIN:GetVariable(launcher.variable, "")
        if not exists(path) then
            local hint = string.gsub(missingFormat, "%%s", path)
            SKIN:Bang("!SetOption", launcher.icon, "LeftMouseUpAction", "[]")
            SKIN:Bang("!SetOption", launcher.icon, "ImageAlpha", "55")
            SKIN:Bang("!SetOption", launcher.icon, "ToolTipText", hint)
            SKIN:Bang("!SetOption", launcher.label, "LeftMouseUpAction", "[]")
            SKIN:Bang("!SetOption", launcher.label, "FontColor", "#DisabledColor#")
            SKIN:Bang("!SetOption", launcher.label, "ToolTipText", hint)
        end
    end
    SKIN:Bang("!Update")
    SKIN:Bang("!Redraw")
end

function Update()
    return 0
end
