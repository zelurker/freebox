local mp = require 'mp'

-- un script lua pour extraire la toc du dvd, c'est quand même lourd de
-- devoir faire ça !

mp.add_hook("on_unload", 10, function ()
	dvd = mp.get_property_native("disc-title-list")
	for i,v in pairs(dvd) do
		print("hook " .. i )
		for i2,v2 in pairs(v) do
			print(i2 .. " " .. v2)
		end
	end
end)

