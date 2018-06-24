local mp = require 'mp'

function on_width_change(name,value)
	height = mp.get_property("osd-height")
	if (value > 0 and tonumber(height) > 0) then
		file = io.open("video_size", "w")
		file:write(string.format("%d\n%d\n",value,height))
		file:close()
	end
	os.remove("list_coords")
	os.remove("info_coords")
	os.remove("numero_coords")
	os.execute("./info")
end

mp.observe_property("osd-width","number",on_width_change)

