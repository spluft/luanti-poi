"""Regenerate test_layers.lua: harness + fresh fork layers + tests T1-T12."""
src = open("/opt/git/spluft/luantiPoiPerplayer/init.lua").read()
start = src.index("local o_openlist = poi.openlist")
end = src.index('poi.openlist() -- Initalize the List on Start')
layer = src[start:end]

harness = r'''
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
'''

tests = r'''
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
'''

open("/opt/data/tmp_mods/test_layers.lua","w").write(harness + layer + "\n" + tests)
print("regenerated")
