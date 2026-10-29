
-- minimal harness: poi fork layers (perplayer + poi_global) against stubs
FAKE_DB = {}
local storage = {
	get_string=function(self,k) return FAKE_DB[k] end,
	set_string=function(self,k,v) FAKE_DB[k]=v end,
	to_table=function(self) local t={} for k,v in pairs(FAKE_DB) do t[k]=v end return {version=1,fields=t} end,
	from_table=function(self,tbl) if type(tbl)~="table" or type(tbl.fields)~="table" then error("BAD from_table arg",2) end FAKE_DB={} for k,v in pairs(tbl.fields) do FAKE_DB[k]=v end end,
}
local S = function(s) return s end
local green, red = '#0F0', '#F00'
local chat = {}
minetest = {
	settings={get=function(_,k)
		if k=="poi.perplayer_global" then return "init_spawn" end
		if k=="poi.perplayer_default_owner" then return "spluft" end end},
	register_chatcommand=function(name,def) CHATCMDS=CHATCMDS or {}; CHATCMDS[name]=def end,
	log=function(_,m) print("LOG: "..m) end,
	chat_send_player=function(n,m) chat[#chat+1]=n..": "..m end,
	check_player_privs=function(n,privs) return false end,
}
-- stub originals (pre-layer semantics of stock poi)
poi = {points={}, spairs=function(t,f) local k={} for x in pairs(t) do k[#k+1]=x end table.sort(k,f)
	local i=0 return function() i=i+1 return k[i],t[k[i]] end end,
	print=function(n,m,c) chat[#chat+1]=n..": "..m end,
}
function poi.openlist() for k in pairs(poi.points) do poi.points[k]=nil end end
function poi.set(name,key) if poi.points[key] then return false end
	poi.points[key]="(1,1,1), (0,0){1}"; poi.save(); return true end
function poi.delete(name,key) if not poi.points[key] then return false end
	poi.points[key]=nil; poi.save(); return true end
function poi.rename(name,opts) local old=opts:match("^(.-),") or opts; local new=opts:match(",%s*(.+)$")
	if not poi.points[old] or poi.points[new] then return false end
	poi.points[new]=poi.points[old]; poi.points[old]=nil; poi.save(); return true end
function poi.move(name,key) if not poi.points[key] then return false end
	poi.points[key]="(5,5,5), (0,0){1}"; poi.save(); return true end
function poi.jump(name,key) return poi.points[key] ~= nil end
function poi.gui() end
local o_openlist = poi.openlist
local o_save = poi.save
local o_list = poi.list
local o_set = poi.set
local o_delete = poi.delete
local o_jump = poi.jump
local o_move = poi.move
local o_rename = poi.rename
local o_gui = poi.gui

PPL = {
	current = nil,         -- player whose view is currently active in poi.points
	storage_snapshot = {}, -- full storage fields {key=raw_value}
	shadowed = {},         -- global keys shadowed by own POI in current view
	global_vals = {},      -- raw values of those globals (restored on save)
}

PPL.global_names = {}
PPL.settings_globals = {} -- declared via poi.perplayer_global: removable only via config
do
	local raw = minetest.settings:get("poi.perplayer_global") or "init_spawn"
	for item in raw:gmatch("[^,]+") do
		local n = item:match("^%s*(.-)%s*$")
		if n ~= "" then
			PPL.global_names[n] = true
			PPL.settings_globals[n] = true
		end
	end
end
PPL.default_owner = minetest.settings:get("poi.perplayer_default_owner") or "spluft"

PPL.promoted = {} -- runtime-promoted globals: [name] = promoter

function PPL.promoted_list_string()
	local keys = {}
	for k in pairs(PPL.promoted) do keys[#keys + 1] = k end
	table.sort(keys)
	local out = {}
	for i, k in ipairs(keys) do out[i] = k .. "=" .. PPL.promoted[k] end
	return table.concat(out, ",")
end

function PPL.is_global(key)
	return PPL.global_names[key] == true
end

function PPL.is_owned_by(key, name)
	local suffix = "@" .. name
	return string.sub(key, -#suffix) == suffix
end

-- one-time in-memory migration: legacy unprefixed keys -> default_owner
function PPL.migrate()
	local changed = false
	for k in pairs(PPL.storage_snapshot) do
		if not PPL.is_global(k) and not string.find(k, "@", 1, true)
				and string.sub(k, 1, 1) ~= "_" then
			PPL.storage_snapshot[k .. "@" .. PPL.default_owner] =
				PPL.storage_snapshot[k]
			PPL.storage_snapshot[k] = nil
			changed = true
		end
	end
	if changed then
		storage:from_table({fields = PPL.storage_snapshot})
		minetest.log("action", "[POI] perplayer migration done, owner=" .. PPL.default_owner)
	end
end

function poi.openlist()
	o_openlist() -- keep original behavior for poi.reload()
	local t = storage:to_table()
	PPL.storage_snapshot = t.fields or {}
	PPL.current = nil
	-- restore runtime-promoted globals before migration claims their bare keys
	local raw = PPL.storage_snapshot["_pp_globals"]
	if type(raw) == "string" then
		for item in raw:gmatch("[^,]+") do
			local n, owner = item:match("^%s*([^=@]+)%s*=%s*([^,%s]+)")
			n = n and n:match("^%s*(.-)%s*$")
			if n and n ~= "" and owner and not PPL.is_global(n) then
				PPL.global_names[n] = true
				PPL.promoted[n] = owner
			end
		end
	end
	PPL.migrate()
	poi.points = {} -- empty view until a player context is set
end

-- read-modify-write flush: rebuild full table from storage,
-- drop current player's slice, rewrite it from the bare-key view
function poi.save()
	local full = (storage:to_table()).fields or {}
	for k, v in pairs(PPL.storage_snapshot) do full[k] = v end
	if PPL.current then
		for k in pairs(full) do
			if PPL.is_owned_by(k, PPL.current) then full[k] = nil end
		end
		for k, v in pairs(poi.points) do
			if PPL.is_global(k) then
				if PPL.shadowed[k] then
					-- own POI shadows this global: keep global value intact,
					-- store own value under owned key
					full[k] = PPL.global_vals[k]
					full[k .. "@" .. PPL.current] = v
				else
					full[k] = v -- genuine write (e.g. right after promote)
				end
			elseif string.find(k, "@", 1, true) then
				full[k] = v -- explicit owned key
			else
				full[k .. "@" .. PPL.current] = v
			end
		end
		full["_pp_globals"] = PPL.promoted_list_string()
	end
	storage:from_table({fields = full})
	PPL.storage_snapshot = full
end

-- switch poi.points to the view of `name`: globals first, own keys shadow them
function PPL.view(name)
	if PPL.current == name then return end
	local view, shadowed, gvals = {}, {}, {}
	for k, v in pairs(PPL.storage_snapshot) do
		if PPL.is_global(k) then
			view[k] = v
			gvals[k] = v
		end
	end
	for k, v in pairs(PPL.storage_snapshot) do
		local at = string.find(k, "@", 1, true)
		if at then
			local base = string.sub(k, 1, at - 1)
			local owner = string.sub(k, at + 1)
			if owner == name then
				if PPL.global_names[base] then
					shadowed[base] = true
					gvals[base] = gvals[base] or view[base]
				end
				view[base] = v
			end
		end
	end
	poi.points = view
	PPL.shadowed = shadowed
	PPL.global_vals = gvals
	PPL.current = name
end

function poi.exist(poi_name)
	if poi_name == nil or poi_name == "" then return false end
	return poi.points[poi_name] ~= nil
end

function poi.list(name, option)
	PPL.view(name)
	option = string.lower(option or "")
	local count = 0
	for key, value in poi.spairs(poi.points) do
		count = count + 1
		if string.find(option, "-a", 1, true) ~= nil then
			local pos = poi.split_pos_cat(value)
			poi.print(name, key .. ": " .. pos .. " " ..
				poi.get_categoriename(poi.get_categorie(key)), green)
		end
	end
	poi.print(name, count .. S(" Points in your list (yours + shared)."), green)
end

function poi.set(name, poi_name)
	PPL.view(name)
	return o_set(name, poi_name) -- o_set -> poi.save() (patched) maps bare -> owned
end

function poi.delete(name, poi_name)
	PPL.view(name)
	if poi_name ~= nil and poi_name ~= "" and PPL.is_global(poi_name) then
		poi.print(name, "Shared POIs are read-only for players.", red)
		return false
	end
	return o_delete(name, poi_name)
end

function poi.jump(name, poi_name)
	PPL.view(name)
	return o_jump(name, poi_name)
end

function poi.move(name, poi_name)
	PPL.view(name)
	if poi_name ~= nil and poi_name ~= "" and PPL.is_global(poi_name) then
		poi.print(name, "Shared POIs are read-only for players.", red)
		return false
	end
	return o_move(name, poi_name)
end

function poi.rename(name, poi_name)
	PPL.view(name)
	local oldname = poi_name
	if string.find(poi_name, ",", 1, true) ~= nil then
		oldname = string.sub(poi_name, 1, string.find(poi_name, ",", 1, true) - 1)
		oldname = oldname:match("^%s*(.-)%s*$")
	end
	if oldname ~= nil and PPL.is_global(oldname) then
		poi.print(name, "Shared POIs are read-only for players.", red)
		return false
	end
	return o_rename(name, poi_name)
end

function poi.gui(player_name, showup, main)
	PPL.view(player_name)
	return o_gui(player_name, showup, main)
end

--[[
	/poi_global          - list shared POIs
	/poi_global <name>   - promote own POI to shared (read-only for players);
	                       run again to un-share (promoter or server-priv only)
--]]
minetest.register_chatcommand("poi_global", {
	params = S("[Name]"),
	description = S("Share your own POI with everyone (read-only for players)."
		.. " Without argument: list shared POIs."),
	privs = {poi = true},
	func = function(name, param)
		param = (param or ""):match("^%s*(.-)%s*$")
		if param == "" then
			local cfg, promo = {}, {}
			for k in pairs(PPL.global_names) do
				if PPL.settings_globals[k] then cfg[#cfg + 1] = k
				else promo[#promo + 1] = k end
			end
			table.sort(cfg); table.sort(promo)
			poi.print(name, S("Shared POIs:"), green)
			for _, k in ipairs(cfg) do
				poi.print(name, "  " .. k .. " (config: poi.perplayer_global)", '#FFCC00')
			end
			for _, k in ipairs(promo) do
				poi.print(name, "  " .. k .. " (shared by " .. tostring(PPL.promoted[k])
					.. ", /poi_global " .. k .. " to un-share)", '#FFCC00')
			end
			if #cfg == 0 and #promo == 0 then
				poi.print(name, S("  none yet"), '#FFCC00')
			end
			return true
		end
		PPL.view(name)
		if not PPL.is_global(param) then
			if not poi.exist(param) then
				poi.print(name, S("Unknown POI: ") .. param, red)
				return false
			end
			if PPL.shadowed[param] then
				poi.print(name, S("A shared POI named '") .. param
					.. S("' already exists - rename yours first."), red)
				return false
			end
			-- promote own POI: view keeps bare key (now global), save() maps it
			PPL.global_names[param] = true
			PPL.promoted[param] = name
			poi.save()
			minetest.log("action", "[POI] " .. name .. " shared POI '" .. param .. "' globally")
			poi.print(name, S("POI '") .. param
				.. S("' is now shared with everyone (read-only)."), green)
			poi.print(name, "Run the same command again to un-share it.", '#FFCC00')
			return true
		end
		-- un-share path
		if PPL.settings_globals[param] then
			poi.print(name, S("Managed by poi.perplayer_global config: remove it there instead."), red)
			return false
		end
		local promoter = PPL.promoted[param]
		if promoter ~= name and not minetest.check_player_privs(name, {server = true}) then
			poi.print(name, S("Only ") .. tostring(promoter) .. S(" or a server admin can un-share it."), red)
			return false
		end
		local raw = PPL.global_vals[param]
		if raw == nil then
			local t = storage:to_table().fields or {}
			raw = t[param] or poi.points[param]
		end
		if raw == nil then
			poi.print(name, S("Internal: shared key not found: ") .. param, red)
			return false
		end
		local full = storage:to_table().fields or {}
		full[param] = nil
		full[param .. "@" .. name] = raw
		PPL.global_names[param] = nil
		PPL.promoted[param] = nil
		PPL.current = nil -- save() without player slice: persist demotion as-is
		full["_pp_globals"] = PPL.promoted_list_string()
		storage:from_table({fields = full})
		PPL.storage_snapshot = full
		PPL.view(name) -- rebuild view: caller now owns the POI
		minetest.log("action", "[POI] " .. name .. " un-shared POI '" .. param .. "'")
		poi.print(name, S("POI '") .. param .. S("' is yours again (private)."), green)
		return true
	end,
})

do
	local n = 0
	for _ in pairs(PPL.global_names) do n = n + 1 end
	print("[MOD] poi_perplayer layer loaded: " .. n .. " shared global POI(s), legacy owner = " .. PPL.default_owner)
end

--[[
	********************************************
	***           Start of the Mod                     ***
	********************************************
--]]



FAKE_DB = {
	["init_spawn"]="(173,0,-27), (0,0){1}",
	["pillagers@spluft"]="(-246,16,-1808), (0,0){1}",
	["village@spluft"]="(-193,0,-2044), (0,0){1}",
}
poi.openlist()
assert(FAKE_DB["pillagers@spluft"] and FAKE_DB["init_spawn"], "T0 no false migration")

-- T1/T2 views
PPL.view("matway"); assert(poi.points["init_spawn"] and not poi.points["village"], "T1")
PPL.view("spluft"); assert(poi.points["village"] and poi.points["pillagers"], "T2")

-- T3 set own -> name@owner key, others intact
assert(poi.set("spluft","base"), "T3set")
assert(FAKE_DB["base@spluft"] and FAKE_DB["village@spluft"] and FAKE_DB["init_spawn"], "T3")

-- T4 other player same name -> separate key (distinct value to track ownership)
PPL.view("matway"); poi.points["base"]="(99,99,99), (0,0){1}"; poi.save()
assert(FAKE_DB["base@matway"] and FAKE_DB["base@spluft"], "T4")

-- T5 /poi_global promotes (the feature asked about)
local cmd = CHATCMDS["poi_global"]; assert(cmd, "T5 cmd registered")
local ok = cmd.func("spluft","base")
assert(ok and FAKE_DB["base"] and PPL.global_names["base"], "T5 promote")
assert(FAKE_DB["_pp_globals"]:find("base"), "T5b persisted")
PPL.view("matway")
assert(poi.points["init_spawn"], "T5c matway sees spawn")

-- T6 guards on shared POIs
assert(poi.delete("matway","init_spawn")==false, "T6a")
assert(poi.move("matway","base")==false, "T6b")
assert(poi.rename("matway","init_spawn,hax")==false, "T6c")

-- T7 restart reload restores promoted globals
poi.openlist()
assert(PPL.global_names["base"] and PPL.global_names["init_spawn"], "T7")

-- T8 own shadow must not clobber promoted global on save
PPL.view("matway"); poi.points["home"]="(7,7,7), (0,0){1}"; poi.save()
assert(FAKE_DB["home@matway"] and FAKE_DB["base"]=="(1,1,1), (0,0){1}", "T8")

-- T9 listing cmd mentions both config and promoted globals
chat={}; cmd.func("spluft","")
local joined=table.concat(chat,"|")
assert(joined:find("base") and joined:find("init_spawn"), "T9")

-- T10 toggle-off un-shares promoted global back to caller
local ok10 = cmd.func("spluft","base")
assert(ok10 and not PPL.global_names["base"] and FAKE_DB["base@spluft"] and not FAKE_DB["base"], "T10 demote")
assert(not (FAKE_DB["_pp_globals"] or ""):find("base"), "T10b list cleaned")

-- T11 config-managed global cannot be un-shared via command
assert(cmd.func("spluft","init_spawn")==false, "T11 config global protected")

-- T12 after demote matway keeps only his own shadow
PPL.view("matway")
assert(poi.points["base"]=="(99,99,99), (0,0){1}", "T12")

-- T13 re-promote then collision: spluft shares base again, matway must be rejected
assert(cmd.func("spluft","base"), "T13a re-promote")
PPL.view("matway")
assert(poi.points["base"]=="(99,99,99), (0,0){1}", "T13b matway sees own shadow")
assert(cmd.func("matway","base")==false, "T13c collision rejected")
assert(FAKE_DB["base"]=="(1,1,1), (0,0){1}", "T13d global value intact")
-- matway saves while shadowing: global must survive, own stays keyed
poi.points["farm"]="(8,8,8), (0,0){1}"; poi.save()
assert(FAKE_DB["base"]=="(1,1,1), (0,0){1}" and FAKE_DB["base@matway"]=="(99,99,99), (0,0){1}",
	"T13e shadow-safe save keeps both")

print("ALL 13 TESTS PASS")
