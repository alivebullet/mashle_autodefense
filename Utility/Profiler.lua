return LPH_NO_VIRTUALIZE(function()
	-- Profile code time.
	-- Determine what parts of our script are lagging us through the microprofiler.
	local Profiler = {}

	-- Microprofiler scopes in Roblox close at thread yields. Many of our wrapped
	-- functions yield (signal handlers that fire remotes, deflect() using task.wait,
	-- etc.), which caused a warning flood from debug.profileend(). We keep the
	-- label-based entry points as passthroughs so call sites stay unchanged.

	---Runs a function with a specified profiler label.
	---@param label string
	---@param functionToProfile function
	function Profiler.run(label, functionToProfile, ...)
		return functionToProfile(...)
	end

	---Wrap function in a profiler statement with label.
	---@param label string
	---@param functionToProfile function
	---@return function
	function Profiler.wrap(label, functionToProfile)
		return functionToProfile
	end

	-- Return profiler module.
	return Profiler
end)()
