-----------------------------------------------------------------------------------------
-- 
-- Corona Labs
--
-- tween.lua
--
-- Code is MIT licensed; see https://www.coronalabs.com/links/code/license
--=====================================================================================--
-- Library objects ====================================================================--
--=====================================================================================--

local tweenObjectLibrary = {}
local private = {}

--=====================================================================================--
-- Constants ==========================================================================--
--=====================================================================================--

local DEBUG_STRING = "Animation Tween: "
local WARNING_STRING = "WARNING: " .. DEBUG_STRING
local ERROR_STRING = "ERROR: " .. DEBUG_STRING

--=====================================================================================--
-- Library variables ==================================================================--
--=====================================================================================--

-- What properties can you use the constantRate parameter on?
private.constantRateProperties = {

	-- Special paired properties
	position = true,
	scale = true,

	-- Individual properties
	rotation = true,
	alpha = true,
}

-- What format all the parameters for a new tween must be
private.parametersData = {

	-- Specific ranges / values
	time = { type = "number", range = ">", limit = 0 },
	delay = { type = "number", range = ">=", limit = 0 },
	speedScale = { type = "number", range = ">", limit = 0 },
	constantRate = { type = "number", range = ">", limit = 0, dependency = "constantRateProperty" },

	-- Specific type only
	reflect = "boolean",
	delta = "boolean",
	iterations = "number",
	easing = { type = { "table", "function" } }, -- This is how you specify multiple types
	easingEndIsStart = "boolean",
	constantRateProperty = { type = "string", dependency = "constantRate" }, -- If this is specified, we also need constantRate
	onStart = "function",
	onComplete = "function",
	onPause = "function",
	onResume = "function",
	onCancel = "function",
	onRepeat = "function",
	onPositionChange = "function",

	-- Simply can exist, can be any format
	id = true,
	tag = true,
}

local mMin, mMax, mFloor, mSqrt, mAbs = math.min, math.max, math.floor, math.sqrt, math.abs

--=====================================================================================--
-- Private functions ==================================================================--
--=====================================================================================--

-----------------------------------------------------------------------------------------
-- private.validateParameters( valuesToTween, tweenSettings )
-- Checks that the passed parameters are valid
-- See the private.parametersData table set up above
-- In all cases where a property is invalid for any reason, it is nil-ed
-----------------------------------------------------------------------------------------
function private.validateParameters( valuesToTween, tweenSettings )

	-- Values is easy - they must all just be numbers
	for k, v in pairs( valuesToTween ) do
		if type( v ) ~= "number" then

			-- Print warning
			print( WARNING_STRING .. "'" .. tostring( k ) .. "' property must be a number" )

			-- Turn the value to a number (in most cases will make it nil, but might help if it was a string)
			valuesToTween[ k ] = tonumber( v )
		end
	end

	-- tweenSettings need to be specific types
	local parametersData = private.parametersData
	for k, v in pairs( tweenSettings ) do

		-- Is there an entry for this key?
		local parameterData = parametersData[ k ]
		local warningText
		if parameterData then

			-- What do we want from this value?
			if type( parameterData ) == "string" then

				-- Is it the right type?
				if type( v ) ~= parameterData then warningText = "parameter must be a " .. parameterData end

			elseif "table" == type( parameterData ) then

				-- Is it the right type?
				local validType = parameterData.type
				local isValidType = false

				-- Can be one of multiple types
				if "table" == type( validType ) then
					for i = 1, #validType do
						if type( v ) == validType[ i ] then
							isValidType = true
							break
						end
					end

				-- Just a single type
				else
					isValidType = ( type( v ) == validType )
				end

				-- Invalid
				if isValidType ~= true then
					if "table" == type( validType ) then warningText = "parameter must be one of the following: " .. table.concat( validType, ", " )
					else warningText = "parameter must be a " .. validType end

				-- Was valid, now do we need to check for ranges?
				else

					-- Must be greater than the limit
					if ">" == parameterData.range then
						if parameterData.limit >= v then warningText = "parameter must be greater than " .. tonumber( parameterData.limit ) end

					-- Must be greater than or equal to the limit
					elseif ">=" == parameterData.range then
						if parameterData.limit > v then warningText = "parameter must be greater than or equal to " .. tonumber( parameterData.limit ) end
					end
				end

				-- Is there a dependency?
				if parameterData.dependency then
					if not tweenSettings[ parameterData.dependency ] then warningText = "parameter requires valid '" .. parameterData.dependency .. "'' parameter" end
				end
			end
		else

			-- Print warning
			warningText = "parameter not recognised"
		end

		-- Is a warning needed?
		if warningText then

			-- Print warning
			print( WARNING_STRING .. "'" .. tostring( k ) .. "' " .. warningText )

			-- Remove the value
			tweenSettings[ k ] = nil
		end
	end

end

-----------------------------------------------------------------------------------------
-- copyStartParameters( propertiesToUse, sourceObject )
-- Creates a table of just the required start values by copying all the properties
-- specified in propertiesToUse from sourceObject to a new table it returns
-----------------------------------------------------------------------------------------
function private.copyStartParameters( propertiesToUse, sourceObject )

	-- Temporary copy table
	local copyTable = {}

	-- Copy all of sourceObject's properties into the new table
	for k, _ in pairs( propertiesToUse ) do
		copyTable[ k ] = sourceObject[ k ]
	end

	return copyTable

end

-----------------------------------------------------------------------------------------
-- copyEndParameters( sourceTable, targetObject, withDelta )
-- Creates a table of just the required end values by copying all the keys / values of
-- sourceTable to a new table
-- Copies all the keys / values of sourceTable to a new table it returns
-- If withDelta == true then it also adds the value of these keys from targetObject
-----------------------------------------------------------------------------------------
function private.copyEndParameters( sourceTable, targetObject, withDelta )

	-- Temporary copy table
	local copyTable = {}

	-- Copy all the source object's properties directly
	for k, v in pairs( sourceTable ) do
		copyTable[ k ] = sourceTable[ k ]
	end

	-- if delta was passed in, we add the targetObject value to the temporary copy table respective values
	if true == withDelta then
		for k, v in pairs( copyTable ) do
			copyTable[ k ] = copyTable[ k ] + ( targetObject[ k ] or 0 )
		end
	end

	return copyTable

end

-----------------------------------------------------------------------------------------
-- _setPosition( [whatToSetPosition,] parentPosition )
-- Moves the playback head to the given parentPosition
-- Position is a time in milliseconds
-- This does not work on nested tweens (which are controlled by the overall parent)
-- whatToSetPosition can be a tag or a display object
-- This IS called when the parent timeline has its position changed
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_setPosition( whatToSetPosition, parentPosition )

	-- If this object has been removed, do nothing
	if self._removed then return end

	-- Allow for missed parameter
	if not parentPosition then
		parentPosition = whatToSetPosition
		whatToSetPosition = nil
	end
	
	-- Check a valid parameter was passed
	if not parentPosition or "number" ~= type( parentPosition ) then
		error( ERROR_STRING .. " you must pass a number to a tween:setPosition() call" )
	end

	-- If in the default timeline this needs matching before we should process it
	if self._parent._isDefaultTimeline then
		if whatToSetPosition and whatToSetPosition ~= self.tag and whatToSetPosition ~= self.target and whatToSetPosition ~= self then return end
	end

	-- Update paused time if necessary
	if self._lastPausedTime then

		-- Factor in for how long it has been paused
		local pausedTime = system.getTimer() - self._lastPausedTime

		-- Change oth current offset and paused offset by this amount
		self._offsetTime = self._offsetTime + pausedTime
		self._lastPausedTime = self._lastPausedTime + pausedTime
	end

	-- If this is within the default timeline, we need to change the offset time
	if self._parent._isDefaultTimeline then
		local offsetChange = ( parentPosition - self._startTime ) - self._position
		self._offsetTime = self._offsetTime - offsetChange
	end

	-- Set the actual position (needed to ensure that when the callback is triggered, the position is in the right place)
	local position = parentPosition - self._startTime

	-- Clear the previous values as we don't care about where you came from
	-- and indeed need them to be blank so update() knows to treat this as a jump
	self._position = nil
	self.iteration = nil

	-- If we haven't yet initialised the data, then we need to use the predicted values
	if 0 <= position and self._initialisationData then self._usePredictedStartValues = true end

	-- Are we past the start?
	if 0 < position then self._hasStarted = true
	else self._hasStarted = nil end

	-- Are we past the end?
	local duration = self:getDuration()
	if duration and position > duration then self._hasCompleted = true
	else self._hasCompleted = nil end

	-- Force an update of this tween if needed
	if self._parent._isDefaultTimeline then

		-- We use the parent's position here instead of the parentPosition property so that it factors in
		-- _offsetTime properly (for children of the default time line)
		self:_update( self._parent._position, true )
	else

		-- For children there's no such need, we can just set the position directly
		self:_update( parentPosition, true )
	end

	-- Handle callback for changes
	if self.onPositionChange then self.onPositionChange( self ) end

end

-----------------------------------------------------------------------------------------
-- _setSpeedScale( [whatToSetSpeed,] speedScale )
-- Sets the speed multiplier of this tween
-- It must be a number value of >0. 1 = normal playback speed. >1 = faster, <1 = slower.
-- Care must be taken in case the tween is paused, IE affect ._lastPausedTime
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_setSpeedScale( whatToSetSpeed, speedScale )

	-- If this object has been removed, do nothing
	if self._removed then return end

	-- Allow for missed parameter
	if not speedScale then
		speedScale = whatToSetSpeed
		whatToSetSpeed = nil
	end

	-- Check a valid parameter was passed
	if not speedScale or "number" ~= type( speedScale ) or 0 >= speedScale then
		error( ERROR_STRING .. " you must pass a positive number to a setSpeedScale() call, not " .. tostring( speedScale ) )
	end

	-- If in the default timeline this needs matching before we should process it
	if self._parent._isDefaultTimeline then
		if whatToSetSpeed and whatToSetSpeed ~= self.tag and whatToSetSpeed ~= self.target and whatToSetSpeed ~= self then return end

	-- If in a custom timeline, this can't be called directly
	else
		return
	end

	-- Alter the offset to cater for the new speed. Note that it is based on the old speed too
	local currentTime = system.getTimer()
	self._offsetTime = currentTime + ( self._offsetTime - currentTime) * self._speedScale / speedScale

	-- Alter the paused time if there is one
	if self._lastPausedTime then
		self._lastPausedTime = currentTime + ( self._lastPausedTime - currentTime) * self._speedScale / speedScale
	end

	-- Update the position
	self._position = self._position * self._speedScale / speedScale

	-- Set the speed
	self._speedScale = speedScale

end

-----------------------------------------------------------------------------------------
-- _pause( whatToPause, parentPausedTime )
-- Pauses the tween if not paused
-- parentPausedTime exists so tweens can share the same pause time for accuracy
-- This is only true of tweens whose parent is the default timeline
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_pause( whatToPause, parentPausedTime )

	-- If this object has been removed or is already paused, do nothing
	if self._removed or self._isPaused then return end

	-- If in the default timeline this needs matching
	-- For a custom timeline the only relevant factor is whether the parent was paused or not
	if self._parent._isDefaultTimeline then

		-- Should this be paused? Matches against tag and target
		if whatToPause and self.tag ~= whatToPause and self.target ~= whatToPause then return end

		-- Store when this was paused (uses parent time to maintain as much accuracy as possible)
		self._lastPausedTime = parentPausedTime or system.getTimer()
	end

	-- Mark as paused directly
	self._isPaused = true

	-- If there is a pause callback set, use it
	if self.onPause then self.onPause( self ) end

end

-----------------------------------------------------------------------------------------
-- resume( whatToResume )
-- Resumes the tween if paused
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_resume( whatToResume )

	-- If this object has been removed or isn't paused, do nothing
	if self._removed or not self._isPaused then return end

	-- If in the default timeline this needs matching
	-- For a custom timeline this must be a child so it will always resume
	if self._parent._isDefaultTimeline then

		-- Should this be resumed? Matches against tag and target
		if whatToResume and self.tag ~= whatToResume and self.target ~= whatToResume then return end

		-- Continue exactly from where you left off
		self._offsetTime = self._offsetTime + ( system.getTimer() - self._lastPausedTime )

		-- Clear paused time
		self._lastPausedTime = nil
	end

	-- Mark as not paused
	self._isPaused = nil

	-- If there is a resume callback set, use it
	if self.onResume then self.onResume( self ) end

end

-----------------------------------------------------------------------------------------
-- cancel( whatToCancel )
-- Cancels the tween object
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_cancel( whatToCancel )

	-- If this object has been removed already, do nothing
	if self._removed then return end

	-- Are we trying to match?
	if whatToCancel then

		-- Tweens in the default timeline respond to tags and display objects
		if self._parent._isDefaultTimeline then
			if self.target ~= whatToCancel and self.tag ~= whatToCancel then return end

		-- Tweens in timelines respond only to display objects
		else
			if self.target ~= whatToCancel then return end
		end
	end

	-- Mark as removed
	self._removed = true

	-- If there is a cancel callback set, use it
	if self.onCancel then self.onCancel( self ) end

	-- Destroy the object neatly
	self:_destroy()

end

-----------------------------------------------------------------------------------------
-- _new( targetObject, valuesToTween, tweenSettings, invertParameters )
-- Creates a new tween object
-- invertParameters is set when a tween is created using .from() instead of .to()
-----------------------------------------------------------------------------------------
function tweenObjectLibrary._new( targetObject, valuesToTween, tweenSettings, invertParameters )

    -- Swap parameters and object, if we want to invert them
	if true == invertParameters then

		-- Swap start / end values, factoring in the delta property if needed
		local withDelta = tweenSettings.delta
		for k, v in pairs( valuesToTween ) do
			valuesToTween[ k ] = targetObject[ k ]
			if withDelta then targetObject[ k ] = targetObject[ k ] + v
			else targetObject[ k ] = v end
		end

		-- Clear the delta settings for inverted tweens, as the delta has just been baked in
		tweenSettings.delta = nil
	end

	-- Error checking
	private.validateParameters( valuesToTween, tweenSettings )

	-- Should probably have a long list of checks for valid settings :/
	-- Create tween object - copied out the long way for better property control
	local tweenObject = {

		-- Private properties
		_isTween = true,
		_isPaused = nil,
		_parent = nil,
		_isDisplayObject = type( targetObject._class ) == "table",

		-- General tween properties
		_duration = tweenSettings.time or 500, -- If the time is to be calculated by 'speed', this is done later
		_easing = tweenSettings.easing or easing.linear,
		_easingEndIsStart = tweenSettings.easingEndIsStart,
		_startTime = tweenSettings.delay or 0,
		_delta = tweenSettings.delta,
		_reflect = tweenSettings.reflect,

		-- Storage for the start / end values
		_initialisationData = valuesToTween, -- This is nil-ed once actual start and end values are stored
		_startValues = nil, -- Not actually calculated and stored until first needed
		_endValues = nil, -- Not actually calculated and stored until first needed

		_predictedStartValues = {}, -- This is nil-ed once actual start and end values are stored
		_usePredictedStartValues = nil, -- This is set only when needed

		-- Private working properties
		_position = 0,
		_speedScale = tweenSettings.speedScale or 1, -- Multiplier for playback speed

		-- Public properties (likely should be private, but to maintain backwards compatibility)
		target = targetObject,
		id = tweenSettings.id,
		tag = tweenSettings.tag,
		iterations = tweenSettings.iterations or 1,

		-- Callbacks
		onStart = tweenSettings.onStart,
		onComplete = tweenSettings.onComplete,
		onPause = tweenSettings.onPause,
		onResume = tweenSettings.onResume,
		onCancel = tweenSettings.onCancel,
		onRepeat = tweenSettings.onRepeat,	
		onPositionChange = tweenSettings.onPositionChange, -- When the position is set directly
	}

	-- Assign functions
	for k, v in pairs( tweenObjectLibrary ) do
		if k ~= "_new" then tweenObject[ k ] = v end
	end

	-- Additional properties of new object as needed
	tweenObject._position = -tweenObject._startTime

	-- If this tween was set up with a constant rate, calculate it here
	if tweenSettings.constantRateProperty then
		tweenObject:_calculateConstantRateDuration( valuesToTween, tweenSettings )
	end
	
	-- Return tween object
	return tweenObject

end

-----------------------------------------------------------------------------------------
-- _wasLastIterationReflected()
-- Interal function to find out if the last iteration was reflected or not
-- Returns true or false
-- if no .iteration is set then it also returns false
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_wasLastIterationReflected()

	-- No iteration set so no concept of previous direction
	-- or just not using reflect
	if not self.iteration or true ~= self._reflect then return false end

	-- Return what it was based on the current iteration
	return self.iteration % 2 == 1

end

-----------------------------------------------------------------------------------------
-- _destroy()
-- Destroys the tween
-- Called at the end of _update() when the _cancel property is set
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_destroy()

	-- Remove itself neatly from a parent timeline if it has one
	if self._parent then self._parent:_removeTween( self ) end

	-- Make sure target is freed
	self.target = nil

	-- Remaining marker to ensure it gets handled as removed
	-- in case something is still referencing it
	self._removed = true

end

-----------------------------------------------------------------------------------------
-- _update()
-- Where this tween is updated, and also where it is destroyed if necessary
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_update( parentPosition, forceUpdate )

	-- Should this tween be ignored for any reason?
	--if self._removed or ( ( self._isPaused or self._hasCompleted ) and true ~= forceUpdate ) then return false end
	if self._removed or ( self._isPaused and true ~= forceUpdate ) then return false end

	-- Get previous update's values
	local oldPosition = self._position
	local oldIteration = self.iteration

	-- Work out position calculations
	-- Position is <0 up to total duration+ (duration * iterations)
	local duration = self._duration / self._speedScale
	local position = parentPosition - self._offsetTime

	-- Are we at or past the start position?
	local beyondTweenStart = ( position >= 0 )
	if beyondTweenStart then

		-- Trigger the start function if we've passed the start time
		if not self._hasStarted then
			self._hasStarted = true
			if self.onStart then self.onStart( self ) end
		end

		-- Have we grabbed the start values yet? If not grab them
		if self._initialisationData then self:_initialiseTween() end
	end

	-- Are we past the end position?
	local tweenDuration = self:getDuration()
	local beyondTweenEnd = tweenDuration and position > tweenDuration 

	-- Were we past the end position in the previous frame?
	local oldBeyondTweenEnd = tweenDuration and oldPosition and oldPosition > tweenDuration

	-- Store position so future updates can access it
	self._position = position

	-- Bail out if we aren't within the tween
	-- Exceptions are we are forcing an update, or we are past the end of the tween
	-- but in the previous update we were within it (IE to force the proper end state)
	if not forceUpdate and
		( false == beyondTweenStart or true == beyondTweenEnd and true == oldBeyondTweenEnd ) then return false end

	-- If there are iterations calculate the new maximum duration and in which iteration you are in
	-- If it is set to loop forever, we use duration * 2 in case it is set to reflect
	local maxDuration
	local iterations = self.iterations
	local limitedIterations = ( 0 < iterations )
	if limitedIterations then maxDuration = duration * iterations
	else maxDuration = duration * 2 end

	-- Find the clipped position
	local clippedPosition = mMax( position, 0 )
	if limitedIterations then clippedPosition = mMin( clippedPosition, maxDuration ) end

	-- Find the iteration
	local iteration = mFloor( clippedPosition / duration ) + 1
	if limitedIterations then iteration = mMin( iteration, iterations ) end

	-- Store iteration so future updates can access it
	self.iteration = iteration

	-- Calculated position is 0-duration (factoring in reflect)
	local calculatedPosition, reflected
	if self._reflect then
		if math.floor( clippedPosition / duration ) % 2 == 0 then
			calculatedPosition = clippedPosition % duration
		else
			reflected = true
			calculatedPosition = duration - ( clippedPosition % duration )
		end
	else
		calculatedPosition = clippedPosition % duration
	end

	-- If _initialisationData exists, it means we haven't yet set up the tween to process values
	if self._initialisationData then return false end

	-- If no longer a valid target, end the update and force remove the tween
	if self:_isInvalidTarget() then return true, true end

	-- Calculate the ratio
	local ratio = calculatedPosition / duration

	-- Get shortcut to the start and end values to tween between
	local startValues = self._startValues -- Start values are simply to extract the relevant properties
	local endValues = self._endValues

	-- Have we reached any important states?
	local didChangeIteration = oldIteration and oldIteration < iteration and iteration > 1
	local didReachEnd = 0 < iterations and maxDuration and clippedPosition == maxDuration

	-- Interpolate (or set directly) the values

	-- Are we at the end of the tween as a whole or an iteration?
	if true == didReachEnd or true == didChangeIteration then

		-- easing.continuousLoop or true == self._easingEndIsStart always uses start values
		if self._easing == easing.continuousLoop or true == self._easingEndIsStart then
			endValues = startValues
		else

			-- End of tween values are start values under certain circumstances
			if true == didReachEnd then 

				-- Are we reflecting? Requires reflect property set and every other iteration
				if true == self._reflect and 0 == iterations % 2 then endValues = startValues end

			-- End of an iteration values are start values under certain circumstances
			else

				-- Are we at the end of a reflected iteration?
				if true == self._reflect and 1 == iteration % 2 then endValues = startValues end
			end
		end

		-- Set the target object's properties to their correct end values directly (no interpolation)
		local targetObject = self.target
		for k, _ in pairs( startValues ) do
			targetObject[ k ] = endValues[ k ]
		end

		-- Process repeats here
		if didChangeIteration then
		
			-- Repeat it for each iteration passed (so if you have a really short iteration it captures everything)
			for i = oldIteration + 1, iteration do

				-- Set the iteration property to be correct *just* for this callback
				self.iteration = i

				-- Call the onRepeat handler
				if self.onRepeat then self.onRepeat( self ) end
			end
		end

	-- We are in the tween, or forceUpdate was set
	-- This ensures we only update if within the tween, unless something really needs the values
	-- to be updated regardless
	else

		-- Interpolate between start and end values (end values either from a fixed table or a target object)
		local targetObject = self.target
		local easing = self._easing

		-- Set the target object's properties to their correct values using interpolation
		local targetObject = self.target
		for k, v in pairs( startValues ) do
			targetObject[ k ] = easing( ratio, 1, v, ( endValues[ k ] or 0 ) - v )
		end
	end

	-- Have we completed the tween (for the first time, in case it was forceUpdated)?
	if true == didReachEnd and not self._hasCompleted then

		-- Mark as completed
		self._hasCompleted = true

		-- Alert with the onComplete callback if exists
		if self.onComplete then self.onComplete( self ) end

		-- Return that this tween was completed
		return true
	end

	-- Tween has not completed yet
	return false

end

-----------------------------------------------------------------------------------------
-- _isInvalidTarget()
-- Checks if target is still valid, or if it has been cleaned up unexpectedly.
-- For example if a display object is :removeSelf()-ed without first cancelling any
-- tweens it is in, or :removeSelf()-ing the display object whose effect / path is
-- being tweened, again without canceling properly.
-- For these purposes a display object stops being a display object when its _class
-- property stops being a table (a display object is a table with extra features)
-- Effects / paths etc. are userdata objects - these are treated as cleaned up when
-- the first property being tweened returns nil
-- Returns whether the target is invalid (true) or not (false)
function tweenObjectLibrary:_isInvalidTarget()

	-- Check that target is still valid

	-- A table might be a pure table or a display object
	-- If a pure table and passes this test, it is still valid
	local targetObject = self.target
	local targetType = type( targetObject )
	if "table" == targetType then

		-- Display object table is no longer a display object if it has lost it's _class table
		if self._isDisplayObject then
			return "table" ~= type( targetObject._class )
		else
			return false
		end

	-- userdata comes from things like paths or effects
	elseif "userdata" == targetType then

		-- If any tweened property of userdata is nil, it is because the parent object has died a death
		local key = next( self._startValues )
		return targetObject[ key ] == nil

	-- If it isn't any of the above, it is definitely not a valid object now!
	else
		return true
	end

end

-----------------------------------------------------------------------------------------
-- _initialiseTween(  )
-- Sets the start and end values of the tween
-- Called the first time they are needed, which is either:
--		The first time the playback head passes the start point or
--		The first time the playback head is manually set beyond the start point
-- Start and end values are only set once, AFTER the onStart callback (called in _update)
-- This allows us to capture any changes made in the callback (eg setting alpha etc)
-- This is now true for .from() tweens too
--
-- Note that for tweens created with the constantRate property, the duration can only be
-- calculated once we have the start and end values
-- The solution for now is that these tweens do immediately grab the values for
-- calculation purposes
--
-- Tweens may have predicted start values when part of a timeline
-- These are the end value of the closest previous tween that shares the same target and
-- property
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_initialiseTween()

	-- Get start values
	local startValues = private.copyStartParameters( self._initialisationData, self.target )

	-- Overwrite with predicted values if needed
	if self._usePredictedStartValues then
		for k, v in pairs( self._predictedStartValues ) do
			startValues[ k ] = v
		end
	end

	-- End values are always constant
	local endValues = private.copyEndParameters( self._initialisationData, self.target, self._delta )

	-- Store the values
	self._startValues = startValues
	self._endValues = endValues

	-- Remove our initial storage value
	self._initialisationData = nil
	self._predictedStartValues = nil
	self._usePredictedStartValues = nil

end

-----------------------------------------------------------------------------------------
-- _calculateConstantRateDuration( valuesToTween, tweenSettings )
-- This calculates the duration of a tween based on how big the changes are between the
-- chosen constantRateProperty
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_calculateConstantRateDuration( valuesToTween, tweenSettings )

	-- We can only continue if constantRateProperty is one of the allowed values
	local constantRateProperty = tweenSettings.constantRateProperty
	if not private.constantRateProperties[ constantRateProperty ] then
		print( WARNING_STRING .. "'" .. tostring( constantRateProperty ) .. "' parameter invalid when using 'constantRate'" )
		return
	end

	-- Grab values if needed
	if self._initialisationData then self:_initialiseTween() end

	-- You also supplied a time property, stop being silly!
	if tweenSettings.time then print( WARNING_STRING .. "'time' parameter invalid when using 'constantRate'" ) end

	-- The amount the values change by to calculate the duration
	local valueChange

	-- Position (x and y)
	if "position" == constantRateProperty then

		-- For X and Y calculate the distance
		local dX, dY
		if valuesToTween.x then dX = self._endValues.x - self._startValues.x end
		if valuesToTween.y then dY = self._endValues.y - self._startValues.y end

		-- Were valid values found for at least one of the axes?
		if not dX and not dY then
			print( WARNING_STRING .. "'constantRateProperty' is 'position' but neither x nor y end values have been specified" )
		else

			-- Calculate the distance (using defaults if needed)
			dX, dY = dX or 0, dY or 0
			valueChange = mSqrt( dX * dX + dY * dY )
		end

	-- Scale (xScale and yScale)
	elseif "scale" == constantRateProperty then

		-- For X and Y calculate the scale 'distance'
		local dXScale, dYScale
		if valuesToTween.xScale then dXScale = self._endValues.xScale - self._startValues.xScale end
		if valuesToTween.yScale then dYScale = self._endValues.yScale - self._startValues.yScale end

		-- Were valid values found for at least one of the scale axes?
		if not dXScale and not dYScale then
			print( WARNING_STRING .. "'constantRateProperty' is 'scale' but neither xScale nor yScale end values have been specified" )
		else

			-- Calculate the 'distance' (our valueChange)
			dXScale, dYScale = dXScale or 0, dYScale or 0
			valueChange = mSqrt( dXScale * dXScale + dYScale * dYScale )
		end

	-- The other options just use the property as-is
	else

		-- Does this property exist to be changed?
		-- This means, did we supply an end value for 
		if not self._startValues[ constantRateProperty ] then
			print( WARNING_STRING .. "constantRateProperty is '" .. constantRateProperty .. "' but no end value has been specified" )
		else
			valueChange = self._endValues[ constantRateProperty ] - self._startValues[ constantRateProperty ]
		end
	end
	
	-- If there's no valueChange it is because the properties weren't set to change
	if valueChange then

		-- Alert them if they are passing a negative value

		-- Calculate how long it would take to change the value by this speed (speed is given in per seconds, but we need result in per milliseconds)
		self._duration = mAbs( valueChange ) * 1000 / mAbs( tweenSettings.constantRate )
	end

end

-----------------------------------------------------------------------------------------
-- _getTotalDuration()
-- Returns the duration of all parts of the tween object active or otherwise, in
-- milliseconds. In other words, the duration plus the specified delay / time offset
-- before-hand if set
-- If there are infinite repetitions, it returns nil
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:_getTotalDuration()

	-- If this object has been removed already, do nothing
	if self._removed then return end

	if 0 < self.iterations then return self:getDuration() + self._startTime
	else return end

end

--=====================================================================================--
-- Public functions ===================================================================--
--=====================================================================================--

-----------------------------------------------------------------------------------------
-- getDuration()
-- Returns the duration of the active part of the tween object in milliseconds
-- If there are infinite repetitions, it returns nil
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:getDuration()

	-- If this object has been removed already, do nothing
	if self._removed then return end

	if 0 < self.iterations then return ( self._duration * self.iterations ) / self._speedScale
	else return end

end

-----------------------------------------------------------------------------------------
-- setPosition( position )
-- Moves the playback head to the given position
-- Position is a time in milliseconds
-- This does not work on nested tweens (which are controlled by the overall parent)
-- Cannot be set directly on anything within a custom timeline
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:setPosition( position )

	-- This can only be called directly - IE to a tween with default timeline parent
	if not self._parent or not self._parent._isDefaultTimeline then
		print( WARNING_STRING .. " you cannot set the position directly of a tween in a timeline" )
		return
	end

	-- Check a valid parameter was passed
	if "number" == type( position ) and position < 0 then
		error( DEBUG_STRING .. " you cannot pass a negative position to a tween:setPosition() call." )
	end

	-- Call the actual setPosition function
	return self:_setPosition( position )

end

-----------------------------------------------------------------------------------------
-- getPosition( getClipped )
-- Returns the position of the playback head
-- Value can be negative (before the start of the tween) or greater than the duration
-- of the tween (has finished)
-- If getClipped = true, the returned value is clipped to the lifespan of the tween
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:getPosition( getClipped )

	-- If this object has been removed already, do nothing
	if self._removed then return end

	-- Do we want the position clipped or not?
	if true == getClipped then
		if 0 >= self.iterations then return mMax( self._position, 0 )
		else return mMin( mMax( self._position or 0, 0 ), self:getDuration() ) end
	else
		return self._position
	end

end

-----------------------------------------------------------------------------------------
-- setSpeedScale( [whatToSetSpeed,] speedScale )
-- Sets the speed multiplier of this tween
-- It must be a number value of >0. 1 = normal playback speed. >1 = faster, <1 = slower.
-- Care must be taken in case the tween is paused, IE affect ._lastPausedTime
-- This does not work on nested tweens (which are controlled by the overall parent)
-- Cannot be set directly on anything within a custom timeline
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:setSpeedScale( speedScale )

	-- This can only be called directly - IE to a tween with default timeline parent
	if not self._parent or not self._parent._isDefaultTimeline then
		print( WARNING_STRING .. " you cannot directly set the speed scale of a tween in a timeline" )
		return
	end

	-- Call the actual pause function
	return self:_setSpeedScale( speedScale )

end

-----------------------------------------------------------------------------------------
-- getSpeedScale()
-- Returns the current speed multiplier of this tween
----------------------------------------------------------------------------------------
function tweenObjectLibrary:getSpeedScale()

	return self._speedScale

end

-----------------------------------------------------------------------------------------
-- pause()
-- Pauses the tween if not paused
-- parentPausedTime exists so tweens can share the same pause time for accuracy
-- This is only true of tweens whose parent is the default timeline
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:pause()

	-- This can only be called directly - IE to a tween with default timeline parent
	if not self._parent or not self._parent._isDefaultTimeline then
		print( WARNING_STRING .. " you cannot directly pause a tween in a timeline" )
		return
	end

	-- Call the actual pause function
	return self:_pause()

end

-----------------------------------------------------------------------------------------
-- resume()
-- Resumes the tween if paused
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:resume()

	-- This can only be called directly - IE to a tween with default timeline parent
	if not self._parent or not self._parent._isDefaultTimeline then
		print( WARNING_STRING .. " you cannot directly resume a tween in a timeline" )
		return
	end

	-- Call the acutal resume function
	return self:_resume()

end

-----------------------------------------------------------------------------------------
-- cancel()
-- Cancels the tween object
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:cancel()

	-- This can only be called directly - IE to a tween with default timeline parent
	if not self._parent or not self._parent._isDefaultTimeline then return end

	-- Call the acutal resume function
	return self:_cancel()

end

-----------------------------------------------------------------------------------------
-- getIsPaused()
-- Returns whether the tween is paused or not including if parent timeline is paused
-----------------------------------------------------------------------------------------
function tweenObjectLibrary:getIsPaused()

	-- If this object has been removed already, do nothing
	if self._removed then return end

	-- Return whether this is paused or not
	return true == self._isPaused

end

--=====================================================================================--

-- Returns the tween object library
return tweenObjectLibrary