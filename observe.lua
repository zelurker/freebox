local mp = require 'mp'

function on_width_change(name,value)
	height = mp.get_property("osd-height")
	file = io.open("video_size", "w")
	file:write(string.format("%d\n%d\n",value,height))
	file:close()
end

mp.observe_property("osd-width","number",on_width_change)

