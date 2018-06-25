local mp = require 'mp'

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
		file:close()
		if exists then
			return
		end
		os.remove("info_coords")
		os.execute("./info")
	end
end

mp.observe_property("osd-width","number",on_width_change)

mp.add_hook("on_unload", 10, function ()
	pos = mp.get_property_number("percent-pos")
	socket = require"socket"
	socket.unix = require"socket.unix"
	c = assert(socket.unix())
	assert(c:connect("sock_list"))
	if (pos < 90) then
		-- gestion basique des bookmarks :
		-- on ne semble pas pouvoir modifier directement le fichier
		-- en lua, donc on transmet la commande à list.pl
		pos = mp.get_property("time-pos")
		c:send("bookmark " .. pos .. "\n")
	else
		c:send("bookmark del\n")
	end
	c:close()
end)


