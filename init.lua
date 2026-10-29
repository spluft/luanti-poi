poi_namefilter = {}
poi_categories = {}

local storage = minetest.get_mod_storage()  -- initalize storage file of this mod. This can only happen here and should be always local
poi = {

	points = {},
	filter = {},
	categories = {},
	modpath = minetest.get_modpath(minetest.get_current_modname()),
    modname = minetest.get_current_modname()
}

-- Load support for intllib.
local S

if(minetest.get_modpath("intllib")) then
    S = dofile(poi.modpath .."/intllib.lua")
    print("[MOD] " .. poi.modname .. ": translating in intllib-mode.")

else
    S = minetest.get_translator(poi.modname)
    print("[MOD] " .. poi.modname .. ": translating in minetest-mode.")

end -- if(minetest.get_modpath(

poi.get_translator = S

dofile(poi.modpath .. "/namefilter.lua")   -- avoid servercrash loop if someone decided to rename the modfolder !
dofile(poi.modpath .. "/categories.lua")

-- Options for Print_Message
local log = 0
local green = '#00FF00'
local red = '#FF0000'
local orange = '#FF6700'
local none = 99

-- Options for Categories and Gui management
-- FIX(poi-perplayer): GUI selection state is per-player. Upstream used single
-- globals shared by every player that had the form open: with two players (or one
-- player with both windows) the last click of either clobbered the other's
-- selection, so rename/set/move/delete acted on a wrong or empty POI.
local gui_state = {}   -- [player_name] = {call_list, lastchoice, selected_category, choosen_name, selected_point}
local function gstate(name)
	local st = gui_state[name]
	if not st then
		st = { call_list = {}, lastchoice = "", selected_category = 0, choosen_name = 0, selected_point = "" }
		gui_state[name] = st
	end
	return st
end
local drop_down = 0
local catlist = ""


minetest.register_privilege("poi", S("Player may set and manage Points of Interest."))


--[[
	********************************************
	***           Functions of POI                    ***
	********************************************
--]]

-- Loads the List of POI's
function poi.openlist()

	local load = storage:to_table()
	poi.points = load.fields

end -- poi.openlist()


-- Writes the List of POI's
function poi.save()

	storage:from_table({fields=poi.points})

end -- poi.save()

-- Helpfunctions for the List-Command
function poi.list_filter(name)
	local list = ""
	local index = 0

	for key, value in pairs(poi.filter) do
		list = list .. key .. ": " .. value .. "\n"
		index = index + 1

	end -- for key, value

	poi.print(name, list, orange)
	poi.print(name, index .. S(" Filter in List."), green)

end -- poi.list_filter()

function poi.list_categories(name)
	local list = ""
	local index = 0

	for key, value in pairs(poi.categories) do
		list = list .. key .. ": " .. value .. "\n"
		index = index + 1

	end -- for key,value

	poi.print(name, list, orange) -- Send List to Player
	poi.print(name, index .. S(" Categories in List."), green) -- Send List to Player

end -- poi.list_categories()

-- List the POI's with an optional Arg
function poi.list(name, option)

	local list = ""
	local all = false 	-- is option list all set?
	local pos, cat
	local idx = 0	-- a given Index with the option -i <number>

-- Check Options for the Command List

	-- Lists only Filterwords
	if string.find(string.lower(option), "-f") ~= nil then
		poi.list_filter(name)
		return true

	end

	-- Lists only the Categories
	if string.find(string.lower(option), "-c") ~= nil then
		poi.list_categories(name)
		return true
	end

	-- List the full Entries of PoI's
	if string.find(string.lower(option), "-a") ~= nil then
		all = true

	end

	if string.find(string.lower(option), "-i") ~= nil then
		idx = tonumber(string.sub(string.lower(option), string.find(string.lower(option), "-i") + 2, -1))
		if(idx == nil) then -- Option wan't a Number, then try to find out the Categorie by Name
			idx = poi.get_categorienumber(poi.trim(string.sub(string.lower(option), string.find(string.lower(option), "-i") + 2, -1)))

		end

		idx = idx or 0 -- Convert a invalid Number to 0
	end

	if (idx > 0) then
		poi.print(name, S("Points of Interest in category ") .. poi.get_categoriename(idx) .. S(" are:"), green)

	else
		poi.print(name, poi.count() .. S(" Points of Interest are:"), green)

	end -- if(idx > 0)

	for key, value in poi.spairs(poi.points) do	-- Build up the List
		pos, cat = poi.split_pos_cat(value)
		if(idx > 0) then
			if(cat == idx) then
				if all then
					list = list .. key .. ": " .. pos .. "\n"

				else
					list = list .. key .. "\n"

				end -- if all

			end -- if (key == idx)

		else -- if(idx > 0)
			if all then
				list = list .. key .. ": " .. pos .. S(" Category: ") .. poi.get_categoriename(cat) .. "\n"

			else
				list = list .. key .. "\n"

			end -- if(all)

		end -- if(key == idx)

	end -- for key,value

	poi.print(name, list, orange) -- Send List to Player
	return true

end -- poi.list()

-- Set's a POI
function poi.set(name, poi_name)

	local player = minetest.get_player_by_name(name)
	local currpos = player:getpos(name)
	local currdir = { pitch = player:get_look_vertical(), yaw = player:get_look_horizontal() }
	local categorie, p_name

	p_name, categorie = poi.split_option(poi_name)

	-- Check Categorie, if Unknown then set it to General
	if categorie == 0 then categorie = 1
	end

	if poi.exist(p_name) then -- Ups, Name exists
		if(poi.get_categorie(p_name) ~= categorie) then -- ok, we want to change the Categorie
			if(categorie == -1) then	-- Invalid Categoriename?
				poi.print(name, S("Given category doesn't exist."), red)
				return false

			end -- if(poi.get_categoriename())

			local value = poi.points[p_name]
			local pos, cat
			pos, cat, dir = poi.split_pos_cat(poi.points[p_name])
			poi.points[p_name] = poi.combine_pos_cat(pos, categorie, dir) -- Changes the Entry
			poi.print(name, name .. S(" has changed the POI: ") .. p_name .. S(" at ") .. pos .. S(" category: ") .. poi.get_categoriename(cat) .. S(" to category: ") .. poi.get_categoriename(categorie) .. "\n", log)
			poi.print(name, "POI: " .. p_name .. S(" at ") .. pos .. S(" in category: ") .. poi.get_categoriename(cat) .. S(" changed to category: ") .. poi.get_categoriename(categorie), green)
			poi.save()
			return true

		else
			poi.print(name, "PoI <" .. p_name .. S("> in category <") .. categorie .. " - " .. poi.get_categoriename(categorie) .. S("> already exists."), red)
			return false -- Name exists, leave function

		end -- if(poi.get_categorie)

	end -- if poi.exist

	if not poi.check_name(p_name) then
		poi_name = poi.convertnil(poi_name) -- convert possible NIL
		poi.print(name, S("Invalid or Forbidden Name <") .. p_name .. S("> for POI."), red)
		return false

	end -- if poi.check_name

	if(categorie == -1) then  -- Checks invalid Categoriename, then set it on new Entry to 1
		poi.print(name, S("Warning: Unkown category, setting to category 1."), red)
		categorie = 1
	end

	poi.points[p_name] = poi.combine_pos_cat(currpos, categorie, currdir)-- Insert the new Entry
	poi.save() -- and write the new List

	poi.print(name, name .. S(" has set the POI: ") .. p_name .. S(" at ") .. minetest.pos_to_string(currpos) .. S(" Categorie: ") .. "{" .. poi.get_categoriename(categorie) .. "}\n", log)
	poi.print(name, "POI: " .. p_name .. S(" at ") .. minetest.pos_to_string(currpos) .. S(" in Categorie: ") .. poi.get_categoriename(categorie) .. S(" stored."), green)
	return true

end -- poi.set()

-- Deletes a POI
function poi.delete(name, poi_name)

	if(poi_name == nil or poi_name == "") then  -- No PoI-Name given ..

		poi.print(name, S("Name of the POI needed."), red)
		return false -- can't delete a non-existing Entry, leave function

	end

	if poi.exist(poi_name) == false then

		poi_name = poi.convertnil(poi_name) -- convert possible NIL
		poi.print(name,  "PoI <" .. poi_name .. S("> unknown to delete."), red)
		return false -- can't delete a non-existing Entry, leave function

	end -- if poi.exist

	local list = ""

	list = poi_name .. ": " .. poi.points[poi_name]	-- Get the full Name of the PoI and save it in a temporary var
	poi.points[poi_name] = nil -- and delete it

	poi.print(name, name .. S(" has deleted POI-Name: ") .. list .. "\n", log)
	poi.print(name, list .. S(" deleted."), red)
	poi.save()	-- Write the new list at the server

	return true

end -- poi.delete()

-- Reload or Reset the List of PoI's and load it new
function poi.reload(name)
	poi.points = nil -- Deletes the List of PoI's
	poi.openlist() -- and Load it new

	poi.print(name, S("POI-List reloaded."), red)
	return true

end -- poi.reload()

-- Jumps to PoI
function poi.jump(name, poi_name)

	if (poi.exist(poi_name) == false) then -- Unknown or not existing Point of Interest
		poi_name = poi.convertnil(poi_name) -- convert possible NIL
		poi.print(name, S("Unknown Point of Interest: ") .. poi_name .. ".", red)
		return false -- POI not in List, leave function

	end -- if poi.exist

	local Position = poi.points[poi_name]
	local direction
	Position, _, direction = poi.split_pos_cat(Position)		-- Extract the Position

	local player = minetest.get_player_by_name(name)
	gstate(name).lastchoice = ""                     -- set lastchoice back to zero (per player)

	poi.play_soundeffect(name, "teleport") -- Play's a Sound
	player:setpos(minetest.string_to_pos(Position)) -- Move Player to Point
	if direction ~= nil then
		player:set_look_vertical(direction.pitch)
		player:set_look_horizontal(direction.yaw)
	end
	poi.print(name, S("You are moved to POI: ") .. poi_name .. ".", green)
	return true

end -- poi.jump()



-- ***********************************
-- ***********************************
-- ** The Gui section starting here **
-- ***********************************
-- ***********************************


-- shows gui with all available PoIs
function poi.gui(player_name, showup, main)
	local gs = gstate(player_name)
	gs.call_list = {}     -- rebuild fully every render; category-filtered lists shrink
	local list = ""
	local showcat =  ""
	local cat
	local count = 0
	local manageme = ""



	for key, value in poi.spairs(poi.points) do	-- Build up the List
	cat = poi.get_categorie(key)

	  if not showup then
	    drop_down = 0

	    if list == "" then

		  list = key

	    else

		  list = list .. "," .. key

	    end
	    count = count +1
	    gs.call_list[count] = key  -- makes it easier to find jump point
	  else
	    drop_down = poi.get_categorienumber(showup)
	    --showcat = "label[0.6,0.4;Category is: "..showup.."]" -- show choosen categorie in gui ##not needed anymore
	    if poi.get_categorienumber(showup) == cat then
	      if list == "" then

		  list = key

	      else

		  list = list .. "," .. key

	      end
	      count = count +1
	      gs.call_list[count] = key  -- makes it easier to find jump point
	    end
	  end

	end -- for key,value

	if minetest.get_player_privs(player_name).poi then
	    manageme = "button[5,6.5;2,1;poimanager;" .. S("Manage PoI") .. "]"
	end

	if main then
	      minetest.show_formspec(player_name,"minetest_poi:thegui",                            -- The main gui for everyone with interact
				      "size[7,8]" ..
				      "label[0.4,0;> ".. S("Double-click on destination to teleport") .. " <]"..
				      --showcat..
				      "textlist[0.4,1;3,5;name;"..list..";selected_idx;false]"..
				      "label[0.6,6;".. count .. S(" points in list") .. "]" ..
				      "label[4.3,0.5; ".. S("Categories") .. " ]" ..
				      "dropdown[4,1;2,1;dname;"..catlist..";"..drop_down.."]"..
				      "button[0.4,6.5;1,1;poitelme;".. S("Go") .. "]" ..
				      "button[1.4,6.5;2,1;poishowall;" .. S("Show all") .. "]" ..manageme..
				      "button_exit[0.4,7.4;3.4,1;poiexit;" .. S("Quit") .. "]"
				      )
	else
	      minetest.show_formspec(player_name,"minetest_poi:manager",                            -- The management gui for people with poi priv
				      "size[7,9]" ..
				      "textlist[0.4,0;3,5;maname;"..list..";"..gs.choosen_name..";false]"..
				      "textlist[4,0;2,2;madname;"..catlist..";"..gs.selected_category..";false]"..
				      "button[4,2.5;2,1;reload;" .. S("Reload") .. "]" ..
				      "button[4,3.5;2,1;validate;" .. S("Validate") .. "]"..
				      "field[0.3,5.4;7,1;managename;                                                                                      - ".. S("Enter Name").." -;"..gs.selected_point.."]"..
				      "button[0.4,6;6,1;set;" .. S("Set Point or change category") .. "]"..
				      "button[0.4,7;2,1;rename;" .. S("Rename") .. "]"..
				      "button[2.4,7;2,1;move;" .. S("Move") .. "]"..
				      "image_button[5.4,7;1,1;minetest_poi_deleteme.png;delete;]"..
				      "button_exit[0.4,8;3,1;doexit;" .. S("Quit") .. "]"..
				      "button[3.4,8;3,1;goback;" .. S("Back") .. "]"
				      )
	end
end -- poi.gui()

-- Callback for formspec
minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "minetest_poi:thegui" and player then -- The form name and player must be online
		local pname = player:get_player_name()
		local gs = gstate(pname)

		local event = minetest.explode_textlist_event(fields.name)  -- get values of what was clicked


		if fields.poiexit then
			gs.lastchoice = nil
			gs.choosen_name = 0
			gs.selected_point = ""
			return false
		end

		if fields.poishowall then
		    gs.lastchoice = nil
		    poi.gui(player:get_player_name(), nil, true)
		    return false
		end

		if fields.poimanager then
		    poi.gui(player:get_player_name(), nil, false)
		    return false
		end


		if fields.poitelme and gs.lastchoice ~= "" then                -- single click and go-Button is much easier for tablet users
		    poi.jump(player:get_player_name(), gs.lastchoice)
		    return false
		end


		if (event.type == "CHG") and event.index then              -- save the last choosen PoI by singleclick
		    gs.lastchoice = gs.call_list[event.index]
		end


		if fields.dname and fields.dname ~= "" then
			  poi.gui(player:get_player_name(), fields.dname, true)
		end


		if (event.type == "DCL") then               -- DCL =doubleclick CHG = leftclick single   by minetest definition
		   poi.jump(player:get_player_name(), gs.call_list[event.index])
		  return false
		end -- if event.type



	end -- if formname

	if formname == "minetest_poi:manager" and player then -- The form name and player must be online
		local pname = player:get_player_name()
		local gs = gstate(pname)
		local event = minetest.explode_textlist_event(fields.maname)  -- get values of what was clicked in PoI
		local catevent = minetest.explode_textlist_event(fields.madname)  -- get values of what was clicked in Categories

		if fields.goback then
			gs.selected_category = 0
			gs.choosen_name = 0
			gs.selected_point = ""
			poi.gui(player:get_player_name(), nil, true)
			return false
		end

		if fields.doexit then
			gs.selected_category = 0
			gs.choosen_name = 0
			gs.selected_point = ""
			return false
		end

		if fields.reload then
			poi.reload(player:get_player_name())
			poi.gui(player:get_player_name(), nil, false)
		end

		if fields.validate then
			poi.validate(player:get_player_name())
			poi.gui(player:get_player_name(), nil, false)
		end

		if fields.delete then
			-- FIX(poi-perplayer): upstream made the trash button admin-only ("couldn't
			-- resist :D"), which in a per-player fork means players cannot delete
			-- their OWN POIs from the GUI at all. Deletion is now delegated to
			-- poi.delete, whose per-player layer refuses shared/foreign POIs
			-- ("Shared POIs are read-only") and allows own ones for everyone.
			poi.delete(player:get_player_name(),gs.selected_point)
			gs.selected_point = ""
			gs.choosen_name = 0
			poi.gui(player:get_player_name(), nil, false)
		end

		if fields.move then
			if gs.selected_point ~= "" then
				poi.move(player:get_player_name(),gs.selected_point)
			end
			poi.gui(player:get_player_name(), nil, false)

		end

		if fields.rename then
			if gs.selected_point ~= "" and fields.managename ~= nil then
				poi.rename(player:get_player_name(),gs.selected_point..","..fields.managename)
			end
			poi.gui(player:get_player_name(), nil, false)
		end

		if fields.managename then
			gs.choosen_name = 0
			gs.selected_point = fields.managename
			poi.gui(player:get_player_name(), nil, false)
		end

		if fields.set then
			if gs.selected_point ~= "" or gs.selected_category ~= 0 then
				poi.set(player:get_player_name(), gs.selected_point..","..gs.selected_category)
				gs.selected_category = 0
				gs.choosen_name = 0
				gs.selected_point = ""
			end
			poi.gui(player:get_player_name(), nil, false)
		end

		if (event.type == "CHG") and event.index and gs.call_list[event.index] then              -- save the last choosen poi
		    gs.selected_point = gs.call_list[event.index]
		    gs.choosen_name = event.index
		    gs.selected_category = poi.get_categorie(gs.selected_point) or 0
		    poi.gui(player:get_player_name(), nil, false)
		end

		if (catevent.type == "CHG") and catevent.index then              -- save the last choosen category
		    gs.selected_category = catevent.index
		    poi.gui(player:get_player_name(), nil, false)
		end
	end

end)


-- *********************************
-- *********************************
-- ** The Gui section ending here **
-- *********************************
-- *********************************

-- Changes a POI-Position
function poi.move(name, poi_name)

	if (poi.exist(poi_name) == false) then
		poi_name = poi.convertnil(poi_name) -- convert possible NIL
		poi.print(name, S("Unknown POI <") .. poi_name .. ">.", red)
		return false

	end -- if poi.exist

	local exist = false
	local player = minetest.get_player_by_name(name)
	local currpos = player:getpos(name)
	local currdir = { pitch = player:get_look_vertical(), yaw = player:get_look_horizontal() }
	local oldpos, cat, dir = poi.split_pos_cat(poi.points[poi_name])

	poi.points[poi_name] = poi.combine_pos_cat(currpos, cat, currdir) -- Write the Position new
	poi.save() -- and write the List

	poi.print(name, name .. S(" has moved the POI: ") .. poi_name .. S(" at ") .. oldpos ..  S(" to Position: ") .. minetest.pos_to_string(currpos) .. "\n", log)
	poi.print(name, "POI: " .. poi_name .. S(" at ") .. oldpos .. S(" moved to Position: ") .. minetest.pos_to_string(currpos) .."\n", green)
	return true

end -- poi.move

-- Renames a POI
function poi.rename(name, poi_name)
	local oldname, newname

	if string.find(poi_name, ",") == nil then
		poi.print(name, S("/poi_rename: No new name for Point given.") .. "\n", red)
		return false
	end

	oldname = poi.trim(string.sub(poi_name,1, string.find(poi_name, ",")-1))

	if not poi.exist(oldname) then
		poi.print(name, S("Point to rename not found.") .. "\n", red)
		return false
	end

	newname = poi.trim(string.sub(poi_name, string.find(poi_name, ",") + 1, -1))

	if not poi.check_name(newname) then
		poi.print(name, S("New name of POI is invalid.") .. "\n", red)
		return false
	end

	if poi.exist(newname) then
		poi.print(name, S("New name of POI already exists.") .. "\n", red)
		return false
	end

	local old_position
	old_position = poi.points[oldname] -- get the Positioni
	poi.points[newname] = old_position -- and make a new entry

	poi.points[oldname] = nil -- now deletes the old one
	poi.save()			-- saves the List

	poi.print(name, name .. S(" has renamed POI-Name: ") .. oldname .. S(" to: ") .. newname .. S(" - Position: ") .. old_position .. "\n", log)
	poi.print(name, S("POI-Name: ") .. oldname .. S(" renamed to ") .. newname ..  S(" - Position: ") .. old_position .. "\n", green)

end -- poi.rename()

-- Check the PoI in the List? Return true if the Name exsists, else false
function poi.exist(poi_name)
   local exist = true

   if(poi_name == "" or poi_name == nil) then
      exist = false

   else
	  local Position = poi.points[poi_name]
	  if(Position == nil or Position == "") then
		  exist = false

	  end -- if Position == nil

  end -- if poi_name ==

   return exist

end -- poi.exist

-- Checks the List and deletes invalid Poi's
function poi.validate(name)
	local count = 0 -- Value of invalid Entries
	local invalid_cat = 0 -- Value of Entries without Categorie
	local key, value

	for key, value in pairs(poi.points) do
		if not poi.check_name(key) then -- is the Name valid?
			count = count + 1
			poi.points[key] = nil

		else
			if value == nil then -- is the Position of the PoI valid?
				count = count + 1
				poi.points[key] = nil

			else -- Yeahh, valid Entry, let us see the Categorie ...

				if( not (string.find(poi.points[key], "{")) and not (string.find(poi.points[key], "}"))) then
					-- Entry without Categorie found
					invalid_cat = invalid_cat + 1
					poi.points[key] = value .. "{1}" -- Set Categorie to 1
				end -- if(string.find)

				local pos, cat
				pos, cat, dir = poi.split_pos_cat(poi.points[key])
				if( (cat == nil) or (cat > poi.max_categories) or (cat <= 0) )then	-- Invalid Categorienumber found
					poi.points[key] = poi.combine_pos_cat(pos, 1, dir) -- Changes the Categorienumber to 1
					invalid_cat = invalid_cat + 1

				end -- if(cat ==)

			end -- if value

		end -- if check_name

	end -- for key,value

	if (count > 0) or (invalid_cat > 0) then
		poi.print(name, name .. " has deleted with validate " .. count .. " PoI's.\n", log)
		poi.print(name, name .. " has found " .. invalid_cat .. " Entries with an invalid Categorie.\n", log)
		poi.print(name, count .. S(" invalid POIs found and deleted."), red)
		poi.print(name, invalid_cat .. S(" POIs with an invalid category found and set to 1."), red)
		poi.save()

	else
		poi.print(name, S("No invalid POI found.") .. "\n", green)

	end

end -- poi.validate

--[[
	********************************************
	***           Helpfunctions                        ***
	********************************************
--]]

-- Trims a String
function poi.trim(myString)
	return (string.gsub(myString, "^%s*(.-)%s*$", "%1"))

end -- poi.trim()


-- builds the list of Categories for drop down menu in the gui
function poi.build_cat_list()
      for key, value in pairs(poi_categories) do      -- build the dropdown menu

	  if catlist == "" then

	   catlist = value

	  else

	    catlist = catlist .. "," .. value

	  end
      end
end


-- Checks the valid of the name
function poi.check_name(name)
	if (name == "") or (name == nil) then
		return false

	end -- if name

	local valid = true

	for key, value in ipairs(poi.filter) do
		if string.find(string.lower(name), string.lower(value)) ~= nil then
			valid = false
		end -- if string.find

	end -- for key,value

	return valid -- Name was in Filter?

end -- poi.check_name()

-- Count's the amount of Entries
function poi.count()
	local count = 0
	for _,key in pairs(poi.points) do
		count = count + 1

	end -- for _,key

	return count
end -- poi.count

-- Returns a sorted Table
function poi.spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do
	keys[#keys+1] = k
    end -- for k

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end -- if order

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end -- if keys

    end -- function()

end -- poi.spairs

-- Writes a Message in a specific color or Logs it
function poi.print(name, message, color)

	error = error or none	-- No Error given, set it to 99 (none)

	-- Logs a Message
	if(color == log) then
		minetest.log("action","[POI] "..name .. " : " .. message)
		return

	else
		if(color ~= none) then
			minetest.chat_send_player(name, core.colorize(color, message))
			return

		else
			minetest.chat_send_player(name,  message)
			return

		end -- if(error ~=none)

	end -- if(error == log)

end -- print_message()

-- Returns the Entryname and the Categorieindex from an given Option
function poi.split_option(poi_name)
	local categorie, p_name

	categorie = 1	-- Set's categorie to 1 per default

	if(string.find(poi_name, ",") ~= nil) then
		p_name = poi.trim(string.sub(poi_name,1, string.find(poi_name, ",")-1))					-- Extract only the Name
		categorie = tonumber(poi.trim(string.sub(poi_name,string.find(poi_name, ",")+1,-1)))		-- Extract the Number of Categorie

		if(categorie == nil) then -- Categorie was not a Number, then check the name
			categorie = poi.trim(string.sub(poi_name,string.find(poi_name, ",")+1,-1))
			categorie = poi.get_categorienumber(categorie)	-- Find the Categorienumber
			if(categorie == nil) then	-- Puuhhh, unknown Categorie
				categorie = -1		-- ok, set it to 1

			end -- if(categorie == nil) -- unknown Name

		end -- if(categorie == nil)

	else
		p_name = poi_name	-- No Categorie found, only a Name was given

	end

	return p_name, categorie

end -- poi.split_option()

-- Returns Coordinates, Categorieindex and direction from an Entry
-- direction may be nil, as earlier POIs didn't save this
function poi.split_pos_cat(position)
	local pos, cat, dir

	if( (string.find(position,"{")) and (string.find(position, "}"))) then
		local posAndDir = string.sub(position, 1, string.find(position, "{") - 1)   -- Extract the pos coords and direction angles
		pos, dir = string.match(posAndDir, "(%([%d, .-]+%))[, ]*([%p%s%d]*)")       -- split "(x,y,z), (p,y)" into "(x,y,z)" and "(p,y)". The pattern is a bit awkward because Lua doesn't support optional captures.
		dir = poi.string_to_direction(dir)	                                        -- convert "(p,y)" to either nil or a table with pitch and yaw
		cat = tonumber(string.sub(position, string.find(position, "{") + 1, string.find(position, "}") - 1)) -- Extract the Categorie
		cat = cat or 1 -- Convert it in an invalid case to 1

	else

		-- No Categorie found
		pos = position
		cat = 1			-- Categorie general
		dir = nil       -- No direction specified

	end -- if(string.find(position)

	return pos, cat, dir

end -- poi.split_pos_cat()


function poi.combine_pos_cat(position, category, dir)

	local dirStr = ""
	if dir ~= nil and dir.pitch ~= nil and dir.yaw ~= nil then
		dirStr = ", (" .. tonumber(dir.pitch) .. "," .. tonumber(dir.yaw) .. ")"
	end

	if type(position) == "table" then
		position = minetest.pos_to_string(position)
	end

	return position .. dirStr .. "{" .. tonumber(category) .. "}"
end -- poi.combine_pos_cat()


-- return nil, or a table with pitch and yaw
function poi.string_to_direction(value)
	if value == nil then
		return nil
	end

	p = {}
	p.pitch, p.yaw = string.match(value, "^%( *([%d.-]+)[, ] *([%d.-]+) *%)$")
	if p.pitch and p.yaw then
		p.pitch = tonumber(p.pitch)
		p.yaw   = tonumber(p.yaw)
		return p
	end
	return nil
end -- poi.string_to_direction()


-- Get's a Categoriename by Index
function poi.get_categoriename(cat)

	local categorie = "Unknown"

	for key, value in pairs(poi.categories) do
		if(key == cat) then
			categorie = value
			break

		end -- if(key == cat)

	end -- for key,value

	return categorie

end -- get_categoriename()

-- Gets a Categorienumber by Name
function poi.get_categorienumber(name)

	local categorie = nil

	if(name == "" or name == nil) then
		return categorie

	end -- if(name)

	name = string.lower(name)

	for key, value in pairs(poi.categories) do
		if(string.lower(value) == name) then
			categorie = key
			break

		end -- if(string.lower)

	end -- for key,value

	return categorie

end -- poi.get_categorienumber()


-- Gets a Categorie of an Entry
function poi.get_categorie(poi_name)
	local value, cat, pos

	value = poi.points[poi_name]
	pos, cat = poi.split_pos_cat(value)

	return cat

end -- get_categorie()

function poi.count_categories()
	local cat = 0

	for key,value in pairs(poi.categories) do
		cat = cat + 1

	end -- for key,value

	return cat

end -- count_categories()

function poi.play_soundeffect(name, soundname)

	if(soundname == nil or soundname == "") then
		soundname = "teleport"

	end -- if(soundname)

	minetest.sound_play("minetest_poi_" .. soundname, {
		to_player = name,
		loop = false,
	})

	--poi.print(name, name .. " has played the Sound: " .. poi.modpath .. "/sounds/minetest_poi_" .. soundname .. ".ogg.", log)

end -- poi.play_soundeffect()

function poi.convertnil(poi_name)

	if(poi_name == nil) then
		poi_name = " "

	end

	return poi_name

end -- poi.convertnil()

--[[
	********************************************
	***         Commands to Register             ***
	********************************************
--]]

minetest.register_chatcommand("poi_set", {
	params = S("<poi_name, category[number]>"),
	description = S("Sets a Point of Interest or changes the category of an existing point."),
	privs = {poi = true},
	func = function(name, poi_name)

		poi.set(name, poi_name)

	end,
})

minetest.register_chatcommand("poi_gui", {
	params = "",
	description = S("Shows POIs in a GUI."),
	privs = {interact = true},
	func = function(name)

      poi.gui(name,nil,true)

	end,
})
minetest.register_chatcommand("poi_list", {
	params = S("<-a> <-c> <-f> <-i [Categorie[Number]]>"),
	description = S("Shows Points of Interest.\nOption -a shows Points of Interest with Coordinates.\nOption -c shows you Categories.\nOption -f shows you the Namefilter\nOption -i <Categorie[number]> shows only the Entries of the given Categorienumber or Name"),
	privs = {interact = true},
	func = function(name, arg)

		poi.list(name, arg)

	end,
})

minetest.register_chatcommand("poi_delete", {
	params = S("<POI-Name>"),
	description = S("Deletes a Point of Interest."),
	privs = {poi = true},
	func = function(name, poi_name)

		poi.delete(name, poi_name)

	end,
})

minetest.register_chatcommand("poi_reload", {
	params = "",
	description = S("Reloads the list of POIs."),
	privs = {poi = true},
	func = function(name)

		poi.reload(name)

	end,
})


minetest.register_chatcommand("poi_jump", {
	params = S("<POI-Name>"),
	description = S("Jumps to the Position of the Point of Interest."),
	privs = {interact = true},
	func = function(name, poi_name)

		poi.jump(name, poi_name)

	end,
})

minetest.register_chatcommand("poi_move", {
	params = S("<POI-Name>"),
	description = S("Changes the Position of the Point of Interest."),
	privs = {poi = true},
	func = function(name, poi_name)

		poi.move(name, poi_name)

	end,
})

minetest.register_chatcommand("poi_rename", {
	params = S("<POI Old Name>,<POI New Name>"),
	description = S("Changes the Name of the Point of Interest."),
	privs = {poi = true},
	func = function(name, poi_name)

		poi.rename(name, poi_name)

	end,
})

minetest.register_chatcommand("poi_validate", {
	params = "",
	description = S("Validates the List of POIs."),
	privs = {poi = true},
	func = function(name)

		poi.validate(name)

	end,
})


-- add button to unified_inventory
if (minetest.get_modpath("unified_inventory")) then
	unified_inventory.register_button("minetest_poi", {
		type = "image",
		image = "minetest_poi_button_32x32.png",
		tooltip = S("Show Points of Interest"),
		hide_lite=true,
		action = function(player)
			local player_name = player:get_player_name()
			if not player_name then return end
			if minetest.check_player_privs(player_name, {interact=true}) then
			  poi.gui(player_name,nil,true)
			else
			  minetest.chat_send_player(player_name,core.colorize(red, S("You need the"))..core.colorize(green, S(" interact"))..core.colorize(red,S(" priv, please type"))..core.colorize(green,S(" /rules"))..core.colorize(red,S(" and search for the keyword")))
			end
		end,
	})
end


--[[
	********************************************
	***   poi_perplayer layer (fork patch)    ***
	***   Each player owns their own POIs.    ***
	***   Storage keys: "name@owner". Bare    ***
	***   keys listed in poi.perplayer_global ***
	***   are shared, read-only for everyone. ***
	***   View = bare keys (globals + own);   ***
	***   owner-mapping happens in save().    ***
	********************************************
--]]

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
		-- FIX(poi-perplayer): admins manage shared POIs (the GUI trash is their
		-- management surface now); players keep read-only. POIs declared in
		-- poi.perplayer_global config stay removable only via config — even by
		-- admins — so config and storage never disagree.
		if PPL.settings_globals[poi_name] then
			poi.print(name, "This POI is shared via config; remove it from poi.perplayer_global to delete it.", red)
			return false
		end
		if not minetest.get_player_privs(name).server then
			poi.print(name, "Shared POIs are read-only for players. Ask an admin (or /poi_global to list shared).", red)
			return false
		end
		-- admin deleting a promoted POI: drop the promotion, then delete for real
		PPL.global_names[poi_name] = nil
		PPL.promoted[poi_name] = nil
		local ok = o_delete(name, poi_name)
		if ok then
			local full = (storage:to_table()).fields or {}
			full[poi_name] = nil -- drop the bare key: save() cannot remove bare globals
			full["_pp_globals"] = PPL.promoted_list_string()
			storage:from_table({fields = full})
			PPL.storage_snapshot = full
		end
		return ok
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
	/poi_global          - list shared POIs            (admin only: privs.server)
	/poi_global <name>   - promote POI to shared (read-only for players);
	                       run again to un-share. Personal POI commands keep
	                       the stock poi priv - sharing is an admin decision.
--]]
minetest.register_chatcommand("poi_global", {
	params = S("[Name]"),
	description = S("Admin only. Share a POI with everyone (read-only for players)."
		.. " Without argument: list shared POIs."),
	privs = {server = true},
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
					.. ", un-share: /poi_global " .. k .. ")", '#FFCC00')
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
				.. S("' is now shared with everyone (read-only for players)."), green)
			poi.print(name, "Run the same command again to un-share it.", '#FFCC00')
			return true
		end
		-- un-share path
		if PPL.settings_globals[param] then
			poi.print(name, S("Managed by poi.perplayer_global config: remove it there instead."), red)
			return false
		end
		-- caller necessarily has server priv (enforced by command privs).
		-- the POI returns to whoever promoted it, not the admin caller.
		local promoter = PPL.promoted[param] or name
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
		full[param .. "@" .. promoter] = raw
		PPL.global_names[param] = nil
		PPL.promoted[param] = nil
		PPL.current = nil -- save() without player slice: persist demotion as-is
		full["_pp_globals"] = PPL.promoted_list_string()
		storage:from_table({fields = full})
		PPL.storage_snapshot = full
		PPL.view(name) -- rebuild view: caller now owns the POI
		minetest.log("action", "[POI] " .. name .. " un-shared POI '" .. param
			.. "' (returned to " .. promoter .. ")")
		if promoter == name then
			poi.print(name, S("POI '") .. param .. S("' is yours again (private)."), green)
		else
			poi.print(name, S("POI '") .. param .. S("' returned to ") .. promoter
				.. S("'s private list."), green)
		end
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

minetest.register_on_leaveplayer(function(player)
	gui_state[player:get_player_name()] = nil
end)

poi.openlist() -- Initalize the List on Start
poi.filter = poi_namefilter
poi.categories = poi_categories
poi.max_categories = poi.count_categories()
poi.build_cat_list()

print("[MOD] " .. minetest.get_current_modname() .. " loaded.")