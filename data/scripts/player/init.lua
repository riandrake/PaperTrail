if onServer() then
	player = Player()
	if player ~= nil then
		player:addScriptOnce("papertrail.lua")
	end
end
