local categories, slots, active = 4, 5, 1
local configPath, statePath = "", ""
local values = {}
local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function decode(data)
 data=(data or ""):gsub('[^'..chars..'=]','')
 local raw=data:gsub('.',function(c) if c=='=' then return '' end local v=chars:find(c,1,true)-1 local bits='' for i=6,1,-1 do bits=bits..(v%2^i-v%2^(i-1)>0 and '1' or '0') end return bits end)
 raw=raw:sub(1,math.floor(#raw/8)*8)
 return (raw:gsub('%d%d%d%d%d%d%d%d',function(b) local v=0 for i=1,8 do v=v+(b:sub(i,i)=='1' and 2^(8-i) or 0) end return string.char(v) end))
end
local function readConfig()
 values={} local f=io.open(configPath,'rb') if not f then return end local d=f:read('*all') or '' f:close()
 if d:sub(1,3)==string.char(239,187,191) then d=d:sub(4) end
 for line in d:gmatch('[^\r\n]+') do local k,v=line:match('^([^=]+)=(.*)$') if k then values[k]=v end end
end
local function exists(p) if p:match('^https?://') or p:match('^mailto:') then return true end local f=io.open(p,'rb') if f then f:close() return true end return false end
local function setSlot(i)
 local k='Slot'..active..'_'..i local name=decode(values[k..'Name']) local command=decode(values[k..'Command']) local icon=decode(values[k..'Icon'])
 local configured=name~='' and command~='' local available=configured and exists(command) local configure='[!CommandMeasure MeasureLaunchers "ConfigureSlot('..active..','..i..')"]'
 local action=configure if available then action='["'..command:gsub('"','\\"')..'"]' end
 SKIN:Bang('!SetOption','MeterSlotLabel'..i,'Text',name~='' and name or '+')
 SKIN:Bang('!SetOption','MeterSlotLabel'..i,'FontColor',available and '#TextMuted#' or (configured and '#DisabledColor#' or '#TextFaint#'))
 SKIN:Bang('!SetOption','MeterSlotLabel'..i,'LeftMouseUpAction',action) SKIN:Bang('!SetOption','MeterSlotLabel'..i,'RightMouseUpAction',configure)
 SKIN:Bang('!SetOption','MeterSlotIcon'..i,'ImageName',icon~='' and icon or '#IconAssets#notes-neutral.png') SKIN:Bang('!SetOption','MeterSlotIcon'..i,'ImageAlpha',available and '220' or (configured and '60' or '0'))
 SKIN:Bang('!SetOption','MeterSlotIcon'..i,'LeftMouseUpAction',action) SKIN:Bang('!SetOption','MeterSlotIcon'..i,'RightMouseUpAction',configure)
 local tip=available and command or (configured and 'Missing: '..command or 'Configure shortcut') SKIN:Bang('!SetOption','MeterSlotIcon'..i,'ToolTipText',tip) SKIN:Bang('!SetOption','MeterSlotLabel'..i,'ToolTipText',tip)
end
local function refresh()
 readConfig()
 for i=1,categories do local name=decode(values['Category'..i..'Name']) SKIN:Bang('!SetOption','MeterCategory'..i,'Text',name~='' and name or ('Category '..i)) SKIN:Bang('!SetOption','MeterCategory'..i,'FontColor',i==active and '#TextColor#' or '#TextFaint#') end
 SKIN:Bang('!SetOption','MeterCategorySelection','X',tostring(15+(active-1)*61))
 for i=1,slots do
  local ok = pcall(setSlot,i)
  if not ok then SKIN:Bang('!SetOption','MeterSlotLabel'..i,'Text','!') end
 end
 SKIN:Bang('!UpdateMeterGroup','LauncherDynamic') SKIN:Bang('!Redraw')
end
function Initialize() configPath=SKIN:GetVariable('LauncherConfigFile') statePath=SKIN:GetVariable('LauncherStateFile') active=math.max(1,math.min(categories,tonumber(SKIN:GetVariable('ActiveLauncherCategory','1')) or 1)) refresh() end
function SelectCategory(i) active=math.max(1,math.min(categories,tonumber(i) or active)) SKIN:Bang('!WriteKeyValue','Variables','ActiveLauncherCategory',tostring(active),statePath) refresh() end
local function settings(mode,c,s) local p='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "#@#Scripts\\ShowLauncherSettings.ps1" -Mode '..mode..' -Category '..c..' -Slot '..s..' -ConfigPath "#LauncherConfigFile#" -ResultPath "#LauncherSettingsResultFile#" -IconDirectory "#LauncherIconDirectory#"' SKIN:Bang('!SetOption','MeasureLauncherSettings','Parameter',p) SKIN:Bang('!CommandMeasure','MeasureLauncherSettings','Run') end
function ConfigureSlot(c,s) settings('slot',c,s) end
function ConfigureCategory(c) settings('category',c,0) end
function SettingsFinished() refresh() end
function Update() return 0 end
