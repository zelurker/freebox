local mp = require 'mp'
socket = require "socket"
socket.unix = require"socket.unix"

function on_width_change(name,value)
	local file = io.open("video_size","r")
	local exists = false
	if file then
		io.close(file)
		exists = true
	end
	height = mp.get_property("osd-height")
	if (value > 0 and tonumber(height) > 0) then
		file = io.open("video_size", "w")
		file:write(string.format("%d\n%d\n",value,height))
		par = mp.get_property("osd-par")
		print("on_width_change : " .. value .. " " .. height .. " par " .. par)
		file:close()
		if exists then
			return
		end
		os.remove("info_coords")
		-- on insère l'appel dans une pause de 1s parce que la video se
		-- configure 2 fois très rapidement quand lancé en plein écran !
		mp.add_timeout(0.2,function ()
			os.execute("./info short")
		end)
	end
end

function metadata(name,value)
	for i,v in pairs(value) do
		local c = assert(socket.unix())
		if (c:connect("sock_info")) then
			c:send("metadata " .. i .. " " .. v)
			c:close()
		else
			print(i,v)
		end
	end
end

function on_abitrate(name,value)
	local vcodec = mp.get_property("video-codec")
	if not value then
		return
	end
	if not vcodec then
		local acodec = mp.get_property("audio-codec-name")
		if not acodec then
			return
		end
		local c = assert(socket.unix())
		if (c:connect("sock_info")) then
			c:send("codec " .. acodec .. " " .. (value/1000) .. "k")
			c:close()
		else
			print("acodec " .. acodec .. " bitrate " .. (value/1000) .. "k")
		end
	end
end

mp.observe_property("osd-width","number",on_width_change)
mp.observe_property("audio-bitrate","number",on_abitrate)
mp.observe_property("metadata","native",metadata)

mp.add_hook("on_unload", 10, function ()
	local c = assert(socket.unix())
	if (c:connect("sock_info")) then
		c:send("unload")
		c:close()
	end
	pos = mp.get_property_number("percent-pos")
	if not pos then
		-- si on lit une url, on aura pas de pos ici
		return
	end
	c = assert(socket.unix())
	if (c:connect("sock_list")) then
		name = mp.get_property("path")
		local duration = mp.get_property_number("duration")
		if (pos < 90 or pos > 100) and duration > 300 then
			-- gestion basique des bookmarks :
			-- on ne semble pas pouvoir modifier directement le fichier
			-- en lua, donc on transmet la commande à list.pl
			pos = mp.get_property("time-pos")
			c:send("bookmark " .. name .. " " .. pos .. "\n")
		else
			c:send("bookmark " .. name .. " del\n")
		end
		c:close()
	end
end)

