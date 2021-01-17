--[[!
if true then return end --]]

--[[!
https://github.com/dr-dba/far-lua-nav-multi-panel/
based on @JD:
https://forum.farmanager.com/viewtopic.php?f=15&t=8759
https://gist.github.com/johnd0e/3a8637378eb3415ea28b82f51cbf9f8a
]]

local Info = Info or package.loaded.regscript or function(...) return ... end --! luacheck: ignore 113/Info
local nfo = Info {
	_filename or ...,
	name = "MultiPanel",
	description = "Store and switch between multiple file panels",
	version = "0.5", -- http://semver.org/lang/ru/
	version_mod = "0.3",
	author = "jd",
	author_mod = "Xer0X",
	url = "http://forum.farmanager.com/viewtopic.php?f=15&t=8759",
	id = "75950345-29C3-49DB-804D-8AA96345C1B2",
	minfarversion = { 3, 0, 0, 4151, 0 }, --! local profile
	help = function(nfo)
		far.Message("\nSee Bottom title for hotkeys\n\n[...]\n", nfo.name.." v"..nfo.version, nil, "kl")
	end,
--	disabled    = false;
	options = {
		macroKey = "`", --! Ctrl~ / CtrlShift~
		popupDelayLong = 1000,
		popupDelay = 300,
		sett_save_in =
		--	"far"	--! FAR settings storage
			"file"	--! file storage in DAT as serialized Lua table
	}
}
if not nfo or nfo.disabled then return end
local O = nfo.options
local F = far.Flags
local DefPanel = {
	Directory = {
		Name = win.GetEnv("SystemDrive").."\\",
		File = "",
		Param = "",
		PluginId = win.Uuid("00000000-0000-0000-0000-000000000000")
	},
	Info = { --! http://api.farmanager.com/ru/defs/sortmetods.html
		SortMode = F.SM_EXT,
		Flags = F.PFLAGS_NONE, --! F.PFLAGS_REVERSESORTORDER,
		ViewMode = 4
	}
}
local MP_MENU_ID = "4EAC7327-6C97-444B-AC6A-2FCCCBAA7210"
local notRealHostFile = {
	[win.Uuid("42E4AEB1-A230-44F4-B33C-F195BB654931")] = "NetBox"
}
local openFromMenu = {
	[win.Uuid("1E26A927-5135-48C6-88B2-845FB8945484")] = "Process list",
	[win.Uuid("B77C964B-E31E-4D4C-8FE5-D6B0C6853E7C")] = "Temporary panel"
}
local pnl_extr, pnl_prev
local dmp_srlz
pcall(function() dmp_srlz = require("dmp-tbl-alt-x") end)
local fnc_file_whoami, dat_file_path 
if Xer0X and Xer0X.fnc_file_whoami then
	fnc_file_whoami = Xer0X.fnc_file_whoami
	local is_mdl, tbl_args, own_file_path, own_file_fold, own_file_name, own_file_extn = fnc_file_whoami({ ... })
	dat_file_path = own_file_path..".dat"
end

-------------------------------------------------------------
--- some general definitions

local function AKey() return mf.akey(1, 1) end

local function LockState(xLock, State)
	-- set State: 0|1|2=toggle
	-- get State: nil|-1
	local Lock = { Num = 0, Caps = 1, Scroll = 2 }
	local modeIsOn = 1
	local keyIsPressed = 0xff80
	local key_rec = mf.flock(assert(Lock[xLock]), State or -1)
	return	modeIsOn ==	band(key_rec, modeIsOn),
		keyIsPressed == band(key_rec, keyIsPressed)
end

--[[
NumLock	=	0x20
ScrollLock =	0x40
CapsLock =	0x80
]]
local anyCtrl = bor(F.RIGHT_CTRL_PRESSED, F.LEFT_CTRL_PRESSED)

-- State after last mf.waitkey!!
local function ModState(Mod) return band(Mouse.LastCtrlState, Mod) end

local function MessagePopup(msg, title, flags, delay)
	if	flags
	and	flags:find("w")
	then	mf.beep()
		delay = delay or O.popupDelayLong
	end
	local s = far.SaveScreen()
	far.Message(msg, title or nfo.name, "", flags)
	far.Text()
	win.Sleep(delay or O.popupDelay);
	far.RestoreScreen(s)
end

--[[
-- simple compare tables
local function fnc_tbl_equal(a, b)
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	return true
end
--]]

--------------------------------------------------------
-- MultiPanel panel api logic

local PNL_ACT	= F.PANEL_ACTIVE
local PNL_PAS	= F.PANEL_PASSIVE

local function getSelection(p, pInfo)
	if	pInfo.SelectedItemsNumber == 1
	then	local item = panel.GetSelectedPanelItem(p, nil, 1)
		return band(item.Flags, F.PPIF_SELECTED) ~= 0 and { item.FileName }
	elseif	pInfo.SelectedItemsNumber > 0
	then	local Sel = { }
		for i = 1, pInfo.SelectedItemsNumber
		do Sel[i] = panel.GetSelectedPanelItem(p, nil, i).FileName
		end
		return Sel
	end
end

local function setSelection(p, Sel)
	if not Sel then return end
	local idx = {}
	for i = 1, panel.GetPanelInfo(p).ItemsNumber
	do	local FileName = panel.GetPanelItem(p, nil, i).FileName
		for j = 1, #Sel do if Sel[j] == FileName then idx[#idx + 1] = i end end
	end
	panel.BeginSelection(p)
	-- https://bugs.farmanager.com/view.php?id=3766
	panel.SetSelection(p, nil, idx, true)
	panel.EndSelection(p)
--	panel.RedrawPanel(p)
end

--------------------------------------------------------
-- MultiPanel helpers

local stack = { currentHK = false }

function stack:_makeHK()
	local used = {
		--[[ this is from original code,
		but, it is unclear to me why needed:
		[self.currentHK or ""] = true --]]
	}
	for i = 1, #self do used[self[i].HK or ""] = true end
	local X = mf.xlat
	for hk in ("123456789ABCDEFGHIJKLMOPQRSTUVWXYZ"):gmatch(".")
	do	if not (used[hk]	or
			used[hk:lower()]or
			used[X(hk)]	or
			used[X(hk:lower())]
				)
		then return hk
		end
	end
end

function stack:_get(p, HK)
	local	pInfo = panel.GetPanelInfo(p)
	local	pnl = { }
	if	band(pInfo.Flags, F.PFLAGS_PLUGIN) == F.PFLAGS_PLUGIN
	then
		pnl = { isPlugin = true,
			Format = panel.GetPanelFormat(p),
			Prefix = panel.GetPanelPrefix(p)
		}
		if	band(pInfo.Flags, F.PFLAGS_SHORTCUT) ~= F.PFLAGS_SHORTCUT
		then
			pnl.openFromMenu = openFromMenu[pInfo.OwnerGuid]
			pnl.notSupported = not pnl.openFromMenu
		end
	end
	pnl.Info = pInfo
	pnl.Sel = getSelection(p, pInfo)
	pnl.Directory = panel.GetPanelDirectory(p)
	pnl.HK = HK or self:_makeHK()
	return pnl
end

function stack:_set(p, idx, pnl)
	pnl = pnl
		or type(idx) == "number" and idx > 0 and idx < #self and self[idx]
		or type(idx) == "table" and idx.Directory and idx
--	if not pnl then return end -- debug
	if	pnl.openFromMenu
	then	Plugin.Menu(win.Uuid(pnl.Info.OwnerGuid))
	elseif
	not	pnl.Directory or
	not	panel.SetPanelDirectory(p, nil, pnl.Directory)
	then	-- todo: blacklist NetBox: Stored sessions
		MessagePopup("oops", nil, "w")
		return false, pnl
	end
--	if not eq(panel.GetPanelDirectory(p), pnl.Directory) then le({ panel.GetPanelDirectory(p), pnl.Directory }) end
--	assert(eq(panel.GetPanelDirectory(p), pnl.Directory)) -- debug APPs ~= Apps
	self.currentHK = pnl.HK
	local pInfo = pnl.Info
	panel.SetSortMode(p, nil, pInfo.SortMode)
	local Flags = pInfo.Flags
	panel.SetSortOrder(p, nil, band(Flags, F.PFLAGS_REVERSESORTORDER) ~= 0)
	panel.SetViewMode(p, nil, pInfo.ViewMode)
	setSelection(p, pnl.Sel)
	panel.RedrawPanel(p, nil, pInfo)
	return true, pnl
end

--------------------------------------------------------
-- MultiPanel stack logic

function stack:Push(p, pnl, new)
	pnl = pnl or self:_get(p)
	if pnl.notSupported then return false, pnl, "This panel kind is not supported" end
	local idx_exists
	local tbl_used_hk = { }
	for ii_key, ii_val in pairs(self)
	do	if	type(ii_key) == "number"
		then	if	ii_val.Directory.Name == pnl.Directory.Name
			and not idx_exists
			then	idx_exists = ii_key
			else	tbl_used_hk[ii_val.HK] = true
			end
		end
	end
	if	idx_exists
	and	idx_exists > 0
	then	pnl.HK = self[idx_exists].HK
		pnl.HK = (tbl_used_hk[pnl.HK] or pnl.HK == "0") and self:_makeHK() or pnl.HK
		self[idx_exists] = pnl
	else	if	new
		then	pnl.HK = self:_makeHK()
		end
		table.insert(self, 1, pnl)
	end
	if	pnl_extr
	and	pnl_extr.Directory.Name == pnl.Directory.Name
	then	pnl_extr = nil
	end
	return idx_exists == -1, pnl
end

function stack:Clone(idx)
	local	pnl
	if	idx == PNL_ACT
	then	pnl = self:_get(PNL_ACT)
		idx = 1
	elseif	type(idx) == "number"
	and	idx > 0
	then	pnl = self[idx]
	elseif	type(idx) == "table"
	and	idx.Directory
	then	pnl = idx
	end
	local copy = { }
	for k, v in pairs(pnl) do copy[k] = v end
	copy.HK = self:_makeHK()
	table.insert(self, idx, copy)
	return idx
end

function stack:Pop(idx, p)
	if	self:_set(p, idx)
	then	return table.remove(self, idx)
	end
end

-- push p/pnl and switch to i
function stack:Switch(idx_targ, p, pnl_curr)
	local idx_curr, pnl_save, pnl_push, set_targ_ok, pnl_targ
	pnl_targ = type(idx_targ) == "table"	and idx_targ
	idx_targ = type(idx_targ) == "number"	and idx_targ
	for	ii_key, ii_val in pairs(self)
	do	if	type(ii_key) == "number"
		and	type(ii_val) == "table"
		and	ii_key > 0
		then	if not	pnl_save
			and	pnl_curr.Directory.Name == ii_val.Directory.Name
			and	pnl_curr.HK == ii_val.HK
			then	idx_curr = ii_key
				pnl_save = ii_val
			end
			if	idx_targ
			and not pnl_targ
			and	ii_key == idx_targ
			then	pnl_targ = ii_val
			end
			if 	pnl_targ
			and not idx_targ
			and	pnl_targ.Directory.Name == ii_val.Directory.Name
			then	idx_targ = ii_key
			end
		end
	end
	if	pnl_save
	then    pnl_save = self:_get(p, pnl_curr.HK)
		table.remove(self, idx_curr)
		table.insert(self, 1, pnl_save)
		if	idx_targ
		and	idx_targ < idx_curr
		then	idx_targ = idx_targ + 1
		end
	end
	if	pnl_targ
	then	set_targ_ok, pnl_targ = self:_set(p, idx_targ, pnl_targ)
		if	idx_targ
		then	table.remove(self, idx_targ)
			table.insert(self, 1, pnl_targ)
		end
		if	pnl_targ.Directory.Name ~= pnl_curr.Directory.Name
		or	pnl_targ.HK ~= pnl_curr.HK
		then	pnl_prev = pnl_curr
			if not	pnl_save
			then	pnl_extr = pnl_curr
			end
		end
	end
end

function stack:Close(p, pnl)
	pnl = pnl or self:_get(p)
	if	pnl.isPlugin
	then	panel.ClosePanel(p)
	--	panel.RedrawPanel(p) -- ??
	else    self:_set(p, nil, DefPanel)
	end
end

function stack:Restore(p, pnl)
	if	#self > 0
	then	self:Pop(1, p)
	else    self:Close(p, pnl)
	end
end

--[[ from the original code, but we use direct access:
setmetatable(stack, { __index = function(_, k) error("out of bounds index: "..k) end }) --]]

local mtPanelsStack = { __index = stack }
-- load/save
local Panels
local _KEY =	nfo.author:upper()
local _NAME =	nfo.name

local function delSettings()
	mf.mdelete(_KEY, _NAME, "local")
end

local function saveSettings()
	mf.msave(_KEY, _NAME, { Panels = Panels }, "local")
	if dmp_srlz and dat_file_path
	then	local res_val, file_hnd = dmp_srlz.fnc_file_save(Panels, { file_path = dat_file_path, file_init = true, file_close = true })
	end
end

local function loadSettings()
	local	file_obj, file_err
	if	O.sett_save_in == "file"
	and	dat_file_path
	then	file_obj, file_err = loadfile(dat_file_path)
		if	file_obj
		then	Panels = file_obj()
		else
		--!	far.Message(file_err, "Load settings error")
		end
	end
	if	O.sett_save_in == "far"
	or not	file_obj
	or not	Panels
	then	local S = mf.mload(_KEY, _NAME, "local") or { }
	        Panels = S.Panels
	end
	Panels = Panels or { currentHK = 0 }
	setmetatable(Panels, mtPanelsStack)
end

loadSettings()

Event { description = "[MultiPanel] Save settings (on exit)",
	group = "ExitFAR",
	action = saveSettings
}

local function isMultiPanelMenu() return Menu.Id == MP_MENU_ID end

local closeOnRelease

Event { description = "[MultiPanel] (close on release)",
	group = "DialogEvent",
	condition = function(Event, Param)
		return closeOnRelease
		and	Event ==	F.DE_DLGPROCINIT
		and	Param.Msg ==	F.DN_ENTERIDLE
		and	isMultiPanelMenu()
		and	ModState(anyCtrl) == 0
	end,
	action = function()
		mf.postmacro(Keys, "Enter")
	--	mf.postmacro(Keys, "CtrlEsc")
	end
}

------------------------------------------------
-- MultiPanel-menu macros

Macro { description = "[MultiPanel] Prev/Next",
	area = "Menu",
	key = "/^[LR]Ctrl(Shift)?(CapsLock|Tab|`)$/",
	condition = isMultiPanelMenu,
	action = function() Keys(AKey():find "Shift" and "Up" or "Down") end
}

Macro { description = "[MultiPanel] Prev/Next (additional)",
	area = "Menu",
	key = "/^[LR]Ctrl(Up|Down|PgUp|PgDn|Num9|Num3)$/",
	condition = isMultiPanelMenu,
	action = function() Keys(AKey():match("^R?Ctrl(.+)$")) end
}

Macro { description = "[MultiPanel] Scroll long titles",
	area = "Menu",
	key = "CtrlRight CtrlLeft",
	condition = isMultiPanelMenu,
	action = function() Keys("Alt"..AKey():match("Ctrl(.+)")) end
}

Macro { description = "[MultiPanel] Goto [0-9A-Z]",
	area = "Menu",
	key = "/^[RL]Ctrl\\w$/",
	condition = isMultiPanelMenu,
	action = function() Keys(AKey():sub(-1)) end
}

local TypeW = 10

local function fnc_menu_item_prep(pnl, new_hot_key)
	local Dir = pnl.Directory or { };
	Dir.File = Dir.File or "";
	-- protect from bad data:
	Dir.Name = Dir.Name or ""
	local file = Dir.File:match("[^\\]+$")
	local Name = Dir.Name:match(".+" or "[Root]")
	local path, Type, is_dir, dir_path, dir_name
	if	pnl.isPlugin
	then
		Type = pnl.Prefix:match("^[^:]*")
		Name = (file and file or pnl.Format)..":"..Name or Name
		if Dir.File ~= "" and not notRealHostFile[Dir.PluginId] then path = Dir.File end
	else	is_dir = true
		Type = "Panel"
		path = Dir.Name
		dir_name = string.match(path, "([^\\^/]+)$")
		dir_path = dir_name and string.sub(path, 1, -string.len(dir_name) - 1) or path
		Name = dir_name and dir_name.." &| "..dir_path or dir_path
	end
	Type = Type..(" "):rep(TypeW - Type:len())
	local notfound = path and not win.GetFileAttr(path)
	local Mark = notfound and "!" or pnl.Sel and "*"
	if	new_hot_key
	and	pnl.HK == "0"
	then	pnl.HK = stack:_makeHK()
	end
	local hk = pnl.HK and "&"..pnl.HK or ""
	local text = ("%2s %-$s %s %s"):gsub("%$", TypeW):format(hk, Type, Mark or " ", Name) -- Sel
	local menu_item = {
		pnl = pnl,
		text = text,
		checked = not pnl.isPlugin and "≡", -- =≡■
		grayed = pnl.notSupported or notfound
	--	disable
	--	hidden
	}
	return menu_item
end

local function fnc_menu_prep()
	local menu_has_curr, menu_idx_curr, menu_has_extr, menu_add_extr
	local menu_items = { }
	local pnl_act = Panels:_get(PNL_ACT)
	pnl_act.HK = "0"
	for ii = 1, #Panels
	do
		local	ii_pnl = Panels[ii]
		if	ii_pnl
		then	if	ii_pnl.Directory.Name == pnl_act.Directory.Name
			and not menu_idx_curr
			then	menu_idx_curr = #menu_items + 1
				menu_has_curr = true
			end
			if	pnl_extr
			and	pnl_extr.Directory.Name ~= pnl_act.Directory.Name
			and	pnl_extr.Directory.Name == ii_pnl.Directory.Name
			then	menu_has_extr = true
			end
			table.insert(menu_items, fnc_menu_item_prep(ii_pnl, true))
		end
	end
	if not	menu_has_curr
	then	table.insert(menu_items, 1, fnc_menu_item_prep(pnl_act))
		menu_idx_curr = 1
		menu_has_curr = false
	elseif	pnl_extr
	and not menu_has_extr
	then	table.insert(menu_items, 1, fnc_menu_item_prep(pnl_extr))
		menu_add_extr = true
		if	menu_idx_curr
		and	menu_idx_curr > 0
		then	menu_idx_curr = menu_idx_curr + 1
		end
	end
	return menu_items, menu_has_curr, menu_idx_curr, menu_add_extr
end -- fnc_menu_prep

--[[ from the original code,
but we will try to live without this "global" variable:
local Items --]]

local function expandBreakKeys(BreakKeysArr)
	local newBreakKeysArr = { }
	for ii, item in ipairs(BreakKeysArr)
	do	for key in item.BreakKey:gmatch("%S+")
		do
			local newitem = {}
			for k, v in pairs(item) do newitem[k] = v end
			newitem.BreakKey = key
			table.insert(newBreakKeysArr, newitem)
		end
	end
	return newBreakKeysArr
end

-- http://msdn.microsoft.com/library/dd375731
local menu_brkys = expandBreakKeys {
	{       BreakKey = "RETURN",
		action = function(list_targ_idx, menu_item_curr)
			Panels:Switch(list_targ_idx, PNL_ACT, menu_item_curr.pnl)
			return "break"
		end
	},
	{       BreakKey = "C+RETURN",
		action = function(pos)
			if	pos > 1
			then	Panels:Switch(pos - 1, PNL_PAS, nil)
			else    Keys("CtrlU Tab")
			end
			return "break"
		end
	},
	{       BreakKey = "C+CONTROL",
		breaking = true
	},
	{       BreakKey = "C+ESCAPE ESCAPE",
		breaking = true
	},
	{	BreakKey = "C+F3 F3",
		action = function(pos) return false, Panels:Clone(pos) end
	},
	{	BreakKey = "C+F4 F4",
		action = function(pos)
			if	type(pos) == "number"
			and	pos > 0
			then	--! should be regular remove of existing (saved) Panle
				table.remove(Panels, pos)
			elseif	type(pos) == "table"
			and	pos.Directory
			then	--[[! should be got here by deleting (current or "extra") unsaved Panel,
				so do nothing]]
			end
		end
	},
	{	BreakKey = "CS+F9 S+F9",
		action = saveSettings
	},
	{       BreakKey = "C+F9 F9",
		action = function()
			if	far.Message("Reload settings?", nfo.name, ";OkCancel")
			then	loadSettings()
			end
		end
	},
	{	BreakKey = "C+F8 F8",
		action = function()
			if	far.Message("Delete saved settings?", nfo.name, ";OkCancel")
			then	delSettings()
				Panels = nil
				loadSettings()
			end
		end
	},
	{	BreakKey = "C+F1 F1",
		action = function()
			nfo:help()
			return closeOnRelease and ModState(anyCtrl) == 0
		end
	}
}

local menu_props = { Title = "MultiPanel", Id = win.Uuid(MP_MENU_ID), Flags = F.FMENU_WRAPMODE }
local menu_low = "F3:Clone, F4:Close, Release:Switch, Ctrl-Enter:..on passive"

--[[! todo: check it
local function _align(pos) return pos > #Items and 1 or pos < 1 and #Items or pos end --]]

local function showMultiPanel(option)
	local	menu_break, menu_item, menu_items,
		menu_idx_curr, menu_idx_targ,
		list_idx_curr, menu_add_extr,
		list_idx_targ, list_has_curr,
		list_idx_goto
	--[[! todo: check it
	if not (menu_item.grayed or option) then menu_pos = _align(2) end --]]
	if not (option == "doNotCloseOnRelease" or ModState(anyCtrl) == 0)
	then closeOnRelease = true
	end
	repeat
		menu_items, list_has_curr, menu_idx_curr, menu_add_extr = fnc_menu_prep()
		local adj_pos = false
			or list_idx_goto and (menu_add_extr or not list_has_curr)
				and list_idx_goto + 1
			or list_idx_goto
				and list_idx_goto
			or menu_add_extr
				and (not pnl_prev and 1 or (
					pnl_prev.Directory.Name == pnl_extr.Directory.Name and 1 or
					pnl_prev.Directory.Name ~= pnl_extr.Directory.Name and 3
						)
					)
			or 2
		menu_idx_targ = math.min(adj_pos, #menu_items)
		menu_item = menu_items[menu_idx_targ]
		menu_props.Bottom = menu_low
		menu_props.SelectIndex = menu_idx_targ
		menu_item, menu_idx_targ = far.Menu(menu_props, menu_items, menu_brkys)
		if not	menu_item.BreakKey
		then	-- Enter:
			menu_item = menu_brkys[1]
		end
		list_idx_targ = --[[ SORRY, COMMENTS BELOW IS NOT EXACTLY CORRECT,
				RIGTH NOW I HAVE NO TIME TO FIX IT :( )]]
			--[[ menu items includes persistent (stored) panel,
			either there is "extra" (last-visited-not-in-list) panel,
			so the index is the same:]]
			list_has_curr and not menu_add_extr and menu_idx_targ or
			--[[ menu items do NOT include persistent (stored) panel,
			no "extra" (last-visited-not-in-list) panel,
			but chosen first item, which supposed to be the current active:]]
			list_has_curr and menu_add_extr and menu_idx_targ == 1 and pnl_extr or
			not list_has_curr and not menu_add_extr and menu_idx_targ == 1 and PNL_ACT or
			--[[ menu items do NOT includes persistent (stored) panel,
			and choosen any not first item,
			which supposed to be from the list:]]
			(not list_has_curr or menu_add_extr) and #Panels > 0 and menu_idx_targ - 1 or
			--[[no saved panels in the list: ]]
			PNL_ACT
		if	menu_item.action
		then	menu_break, list_idx_goto = menu_item.action(list_idx_targ, menu_items[menu_idx_curr])
		end
	until	menu_break or menu_item.breaking
	closeOnRelease = false
	return menu_idx_targ
end

nfo.execute = function() showMultiPanel("doNotCloseOnRelease") end;

--[[ todo
* sticky folders
* Help
* Info QView Tree
* autoswitch?
* Multi-panel plugin specific features?
--]]
--[[
local allPanels = "Shell Info QView Tree Search" --]]
local allPanels = "Shell Search"

Macro { description = "[MultiPanel] switch",
	area = allPanels,
	key = "/^LCtrl(Shift)?("..O.macroKey..")$/",
	action = function()
		showMultiPanel()
		if O.macroKey == "CapsLock" then LockState("Caps", 0) end
	end
}

NoMacro {
	description = "[MultiPanel] toggle",
	area = allPanels,
	key = "LCtrl",
	action = function() showMultiPanel("doNotCloseOnRelease") end
}

Macro { description = "[MultiPanel] goto Panels",
	area = "Editor Viewer",
	key = "/^LCtrl(Shift)?("..O.macroKey..")$/",
	action = function()
		Keys("F12 1")
		if Area.Shell then showMultiPanel("current") end
		if O.macroKey == "CapsLock" then LockState("Caps", 0) end
	end
}

local function Push(p)
	local	ok, pnl, err = Panels:Push(p, nil, p == PNL_ACT)
	if	ok
	then	MessagePopup("Storing panel...")
	elseif	err
	then	local msg = ("Unable to store this plugin panel: %s"):format(pnl.Format)
		MessagePopup(msg, err, "w")
	else	-- existing in list
	end
end

Macro { description = "[MultiPanel] store active panel",
	area = allPanels,
	key = "LCtrlF3:Hold",
	action = function() Push(PNL_ACT) end
}

Macro { description = "[MultiPanel] store passive panel",
	area = allPanels,
	key = "LCtrlShiftF3:Hold",
	action = function() Push(PNL_PAS) end
}

Macro { description = "[MultiPanel] restore prev. panel",
	area = allPanels,
	key = "LCtrlF4:Hold",
	action = function()
		Panels:Restore(PNL_ACT)
		MessagePopup("Closing panel...")
	end
}

Macro { description = "[MultiPanel] restore prev. panel as passive",
	area = allPanels,
	key = "LCtrlShiftF4:Hold",
	action = function()
		Panels:Restore(PNL_PAS)
		MessagePopup("Closing panel...")
	end
}

Macro { description = "[MultiPanel] close active panel",
	area = allPanels,
	key = "LCtrlF8:Hold",
	action = function() Panels:Close(PNL_ACT) end
}

Macro { description = "[MultiPanel] close passive panel",
	area = allPanels,
	key = "LCtrlShiftF8:Hold",
	action = function() Panels:Close(PNL_PAS) end
}
