--[[Switch-Case Simulation in Lua
 
DOCUMENTATION
 
SWITCH MODULE
 
    local Switch = require(script.Switch) --returns a callable function for constructing Switch objects
 
Switch Object
 
    __call(variable) - Checks a specified variable amongst case statements. Uses :default if no value is found. If :default is not declared, this will error
 
    self :case(value, callback) - Sets a case value to callback, returns the object so that it can be chained
    self :default(callback) - Sets the default callback
 
 
EXAMPLE
 
local Switch = require(script.Switch)
 
local SpeedCase = Switch()
    :case(16, function()
        print("Hello Sixteen")
    end)
 
    :case(30, function()
        print("Hello Thirty")
    end)
 
    :default(function()
        print("Unrecognised")
    end)
 
SpeedCase(script.Parent.Humanoid.WalkSpeed)
 
]]--
 
local switchObjectMethods = {}
switchObjectMethods.__index = switchObjectMethods
 
switchObjectMethods.__call = function(self, variable)
    local c = self._callbacks[variable] or self._default
    if c then
        c()
    end
end
 
function switchObjectMethods:case(v, f)
    self._callbacks[v] = f
    return self
end
 
function switchObjectMethods:default(f)
    self._default = f
    return self
end

return function()
    local o = setmetatable({}, switchObjectMethods) 
    o._callbacks = {}   
    return o
end