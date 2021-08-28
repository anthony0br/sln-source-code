local module = {}

for i, v in pairs(script:GetChildren()) do
	module[v.Name] = require(v)
end

return module