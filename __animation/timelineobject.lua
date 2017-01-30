--=====================================================================================--
-- To do:
-- 		- error checking parameters	
--=====================================================================================--

--=====================================================================================--

local tweenObjectLibrary = require( "__animation.tweenobject" )

--=====================================================================================--
-- Library objects ====================================================================--
--=====================================================================================--

local timelineObjectLibrary = {}
local private = {}

--=====================================================================================--
-- Constants ==========================================================================--
--=====================================================================================--

local DEBUG_STRING = "Animation Timeline: "
local WARNING_STRING = "WARNING: " .. DEBUG_STRING
local ERROR_STRING = "ERROR: " .. DEBUG_STRING

--=====================================================================================--
-- Library variables ==================================================================--
--=====================================================================================--

-- What format all the parameters for a new tween must be
private.parametersData = {

	-- Base timeline parameters
	timeline = {

		-- Specific ranges / values
		autoPlay = "boolean",
		autoCancel = "boolean",
		time = { type = "number", range = ">", limit = 0 },
		delay = { type = "number", range = ">=", limit = 0 },
		speedScale = { type = "number", range = ">", limit = 0 },

		-- Specific type only
		markers = "table",
		tweens = "table",
		onStart = "function",
		onComplete = "function",
		onPause = "function",
		onResume = "function",
		onCancel = "function",
		onPositionChange = "function",
		onMarkerPass = "function",

		-- Simply must exist, can be any format
		id = true,
		tag = true,

		-- Special, internal only value
		_isDefaultTimeline = true,
	},

	-- Parameters for individual tweens
	tweens = {
		startTime = { type = "number", range = ">=", limit = 0 },
		tween = "table", -- Checked individually in the tween's _new() function
		useFrom = "boolean",
	},
}

local mMin, mMax = math.min, math.max

--=====================================================================================--
-- Private functions ==================================================================--
--=====================================================================================--

-----------------------------------------------------------------------------------------
-- private.sortMarkersByTime( markerA, markerB )
-- Used when creating a new marker to insert it into a table in the right order
-- Are there any benefits to having it here or can I just place it into the table.sort()
-- function directly?
-----------------------------------------------------------------------------------------
function private.sortMarkersByTime( markerA, markerB )

	-- Return which marker is earlier than the other
	return markerA.time < markerB.time

end

-----------------------------------------------------------------------------------------
-- private.validateParameters( params )
-- Checks that the passed parameters to the timeline creation function are valid
-- See the private.parametersData table set up above
-- Note we don't check the markers table (other than it exists) because later on it gets
-- its own special checks within addMarker()
-----------------------------------------------------------------------------------------
function private.validateParameters( params )

	-- Do main parameters
	private.validateSetOfParameters( params, private.parametersData.timeline )

	-- Do tweens
	local tweens = params.tweens
	if tweens and type( tweens ) == "table" then
		for i = 1, #tweens do
			local tween = tweens[ i ]
			if type( tween ) ~= "table" then print( WARNING_STRING .. " tween parameter must be a table: " .. tostring( tween ) )
			else private.validateSetOfParameters( tween, private.parametersData.tweens, " in tween" ) end
		end
	end

end

-----------------------------------------------------------------------------------------
-- private.validateSetOfParameters( paramsm parametersData )
-- Checks the passed parameters against the supplied parametersData are valid
-- See private.validateParameters() and the private.parametersData table set up above
-- In all cases where a property is invalid for any reason, it is nil-ed
-----------------------------------------------------------------------------------------
function private.validateSetOfParameters( params, parametersData, appendString )

	-- In case we didn't want an identifier
	appendString = appendString or ""

	-- params need to be specific types
	for k, v in pairs( params ) do

		-- Is there an entry for this key?
		local parameterData = parametersData[ k ]
		local warningText
		if parameterData then

			-- What do we want from this value?
			if type( parameterData ) == "string" then

				-- Is it the right type?
				if type( v ) ~= parameterData then warningText = "parameter must be a " .. parameterData end

			elseif type( parameterData ) == "table" then

				-- Is it the right type?
				local validType = parameterData.type
				local isValidType = false

				-- Can be one of multiple types
				if type( validType ) == "table" then
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
					if type( validType ) == "table" then warningText = "parameter must be one of the following: " .. table.concat( validType, ", " )
					else warningText = "parameter must be a " .. validType end

				-- Was valid, now do we need to check for ranges?
				else

					-- Must be greater than the limit
					if parameterData.range == ">" then
						if parameterData.limit >= v then warningText = "parameter must be greater than " .. tonumber( parameterData.limit ) end

					-- Must be greater than or equal to the limit
					elseif parameterData.range == ">=" then
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
			print( WARNING_STRING .. "'" .. tostring( k ) .. "' " .. warningText .. appendString )

			-- Remove the value
			params[ k ] = nil
		end
	end


end

-----------------------------------------------------------------------------------------
-- _match( tagOrDisplayObject )
-- Returns this timeline if it matches the tag, and any chil tweens if they match on the
-- tag or display object
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_match( tagOrDisplayObject )

	-- Are we looking at a tag match for this timeline?
	if "string" == type( tagOrDisplayObject ) and not self._isDefaultTimeline then
		if self.tag == tagOrDisplayObject then return { self } end
	end

	-- Find any children that match this
	-- Returns all matches regardless of whether this is the default timeline or not
	local matches = {}
	for i = 1, #self._children do
		local tweenObject = self._children[ i ]

		-- String passed so match against the tag
		if "string" == type( tagOrDisplayObject ) then
			if tweenObject.tag == tagOrDisplayObject then matches[ #matches + 1 ] = tweenObject end

		-- Otherwise match against the target display object
		elseif tweenObject.target == tagOrDisplayObject then
			matches[ #matches + 1 ] = tweenObject
		end
	end

	-- Return the matches
	return matches

end

-----------------------------------------------------------------------------------------
-- _calculateAndSetTotalDuration( newDuration )
-- Calculates and sets the _duration property of the timeline object
-- If newDuration is set, then this means we just added a time, so we only need to
-- compare the current duration to the new time and store whichever is longer
-- If newTime is nil, this means we need to calculate the duration the long way (likely
-- as a result of deleting something). In this case we find the end of the last child,
-- then compare that to the last marker if any exists
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_calculateAndSetTotalDuration( newDuration )

	-- If this new duration is shorter than the timeline's current duration, re-calculate the timeline's duration
	if newDuration and self._duration and newDuration < self._duration then

		-- Need to recalculate the duration the old fashioned way (longest remaining tween or latest marker)
		newDuration = 0
		for i = 1, #self._children do

			-- Get the child duration
			local childTotalDuration = self._children[ i ]:getTotalDuration()

			-- The child has a valid duration (IE isn't infinite), so store which is longer
			if childTotalDuration then
				newDuration = mMax( newDuration, childTotalDuration )

			-- This marks it as having an infinite duration
			else
				break
			end
		end
                                                                        
		-- Compare the duration against the last marker if any exist
		if newDuration and #self._markersInOrder > 0 then
			newDuration = mMax( newDuration, self._markersInOrder[ #self._markersInOrder ].time )
		end
	end

	-- Store the duration in the timeline object if it is different to the current one
	-- but only if the overall duration isn't infinite
	if self._duration and newDuration ~= self._duration then
		self._duration = newDuration

		-- Let the parent know if relevant
		if self._parent and not self._parent._isDefaultTimeline then
			self._parent:_calculateAndSetTotalDuration( newDuration )
		end
	end

end

-----------------------------------------------------------------------------------------
-- _createTween( tweenObject, tweenStartTime, invertParameters )
-- Adds a tween to the timeline
-- The tweenObject can be an actual tween or timeline object already created,
-- or a normal set of values for creating tweens directly
-- invertParameters creates the tween as if it were created using .from() instead of
-- .to()
-- NOTE invertParameters only works if the tweenObject is actually just raw data
-- (ie target, propertyChanges, tweenSettings) and is created here. If you pass an
-- actual tween object, it isn't affected by this parameter
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_createTween( targetObject, valuesToTween, tweenSettings, tweenStartTime, invertParameters )

	-- If this isn't an actual tween object, then create it
	local tweenObject = tweenObjectLibrary._new( targetObject, valuesToTween, tweenSettings, invertParameters )

	-- If the creation didn't work for any reason, stop
	if not tweenObject then return end

	-- Set the start time definitively (as the passed parameter over-writes whatever was already in the object)
	-- Note that if supplied, it is because the tween was created within a newTimeline() call, and start time is
	-- actually the startTime parameter combined with the tween's delay
	if tweenStartTime then tweenObject._startTime = tweenStartTime end

	-- Reset the offset as needed
	if self._isDefaultTimeline then

		-- Anything added into the default timeline has its offset based upon the system time
		tweenObject._offsetTime = system.getTimer() + tweenObject._startTime
	else

		-- Anything nested is set relative to the start time of this timeline (IE not based upon system.time() )
		tweenObject._offsetTime = tweenObject._startTime

		-- Anything nested is matched to the parent (this!)
		tweenObject._isPaused = self._isPaused
		tweenObject._lastPausedTime = nil
	end

	-- Set the default position
	tweenObject._position = -tweenObject._startTime * tweenObject._speedScale

	-- Insert this tween into this timeline
	self._children[ #self._children + 1 ] = tweenObject
	tweenObject._parent = self

	-- Calculate the new duration for the timeline
	self:_calculateAndSetTotalDuration( tweenObject:getTotalDuration() )

	-- Return the tween object
	return tweenObject

end

-----------------------------------------------------------------------------------------
-- _removeTween( tweenObject )
-- Removes a tween or timeline from the timeline
-- This does not destroy the tween object, it merely removes it from its parent
-- This is called only from the tween's _destroy() function
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_removeTween( tweenObject )

	-- Find the tween in this object and break reference
	for i = #self._children, 1, -1 do
		if tweenObject == self._children[ i ] then
			tweenObject._parent = nil
			table.remove( self._children, i )
			break
		end
	end

	-- Calculate the new duration for the timeline
	self:_calculateAndSetTotalDuration()

end

-----------------------------------------------------------------------------------------
-- _new( params )
-- Creates a new timeline object.
-- _isDefaultTimeline = true 	- hidden parameter (to create the only default timeline)
-----------------------------------------------------------------------------------------
function timelineObjectLibrary._new( params )

	-- Allow for nil parameters without causing problems later on
	params = params or {}

	-- Error checking
	private.validateParameters( params )

	-- Create timeline object
	local timelineObject = {

		-- Private properties
		_isTimeline = true, 
		_isDefaultTimeline = params._isDefaultTimeline, -- If it is default, certain actions are prohibited
		_parent = nil,
		_children = {}, 
		_isPaused = true,
		_autoCancel = params.autoCancel, -- If set, will cancel itself upon completion

		_markers = {}, -- Markers stored by name
		_markersInOrder = {}, -- Markers are stored in order by time (grouped together if sharing time)
		_duration = 0, -- Duration is the maximum duration of all children
		_startTime = params.delay or 0,
		_offsetTime = 0, -- Is set later on
		_position = nil, -- Is set later on
		_includeOldPositionInChecks = true, -- If this is true, then marker checks include start position, otherwise > start position 

		_speedScale = params.speedScale or 1, -- Multiplier for playback speed

		-- Public properties (likely should be private, but to maintain backwards compatibility)
		id = params.id,
		tag = params.tag,

		-- Callbacks
		onStart = params.onStart,
		onComplete = params.onComplete,
		onPause = params.onPause,
		onResume = params.onResume,
		onCancel = params.onCancel,
		onPositionChange = params.onPositionChange, -- When the position is set directly
		onMarkerPass = params.onMarkerPass, -- Callback for when you pass a marker
	}

	-- Assign functions to it
	for k, v in pairs( timelineObjectLibrary ) do
		timelineObject[ k ] = v
	end

	-- Create any specified tween objects and move them into the timeline
	if params and params.tweens then
		for i = 1, #params.tweens do
			local tweenToInsert = params.tweens[ i ]

			if type( tweenToInsert ) ~= "table" then
				print( WARNING_STRING .. "Tried to insert nil into this timeline" )
			else
				local tweenData = tweenToInsert.tween

				--- Check that the 
				-- Check that the tween value is now no longer an actual tween or timeline object (saaad!)
				if not tweenData then print( WARNING_STRING .. "Tried to insert nil into new timeline" )
				elseif tweenData._isTimeline then print( WARNING_STRING .. "Tried to insert a timeline object into new timeline" )
				elseif tweenData._isTween then print( WARNING_STRING .. "Tried to insert a tween object into new timeline" )
				else

					-- Check for the right number of parameters, creating defaults if needed
					local targetObject, valuesToTween, tweenSettings = tweenData[ 1 ], tweenData[ 2 ], tweenData[ 3 ]
					
					-- Checks for valid parameters
					if not targetObject or type( targetObject ) ~= "table" then error( ERROR_STRING .. " you must pass a table or display object for tweens in a new timeline" ) end
					if not valuesToTween or type( valuesToTween ) ~= "table" then error( ERROR_STRING .. " you must pass a properties table for tweens in a new timeline" ) end
					if not tweenSettings or type( tweenSettings ) ~= "table" then error( ERROR_STRING .. " you must pass a params table for tweens in a new timeline" ) end

					-- The delay is now a combination of start time and delay
					-- We do this to over-write the internal delay parameter
					local startTime = ( tweenToInsert.startTime or 0 ) + ( tweenToInsert.tween[ 3 ].delay or 0 )

					-- Send the tween data and add it to this timeline 
					timelineObject:_createTween( tweenToInsert.tween[ 1 ], tweenToInsert.tween[ 2 ], tweenToInsert.tween[ 3 ], startTime, tweenToInsert.useFrom )
				end
			end
		end
	end

	-- Add in any markers
	if params.markers then
		for i = 1, #params.markers do
			local marker = params.markers[ i ]
			timelineObject:addMarker( marker.name, marker.time )
		end
	end

	-- Additional properties of new object as needed
	local systemTimer = system.getTimer()
	if params._isDefaultTimeline then
		timelineObject._isPaused = false
		timelineObject._offsetTime = timelineObject._startTime
		timelineObject._lastPausedTime = systemTimer
	else
		timelineObject._offsetTime = systemTimer + timelineObject._startTime
		timelineObject._lastPausedTime = systemTimer
	end
	timelineObject._position = -timelineObject._startTime

	-- Automatically start the timeline and children if asked to do so
	-- Done manually to avoid generating onResume callbacks
	if true == params.autoPlay then

		-- Force the children to not be paused
		for i = 1, #timelineObject._children do
			local tweenObject = timelineObject._children[ i ]
			tweenObject._isPaused = nil
			tweenObject._lastPausedTime = nil
		end

		-- Start this timeline immediately
		timelineObject._isPaused = nil
		timelineObject._lastPausedTime = nil
	end

	-- Return the timeline object
	return timelineObject

end

-----------------------------------------------------------------------------------------
-- _destroy()
-- Cleans up after itself
-- Note tweens clean themselves up, so by the time this gets called all children will
-- already be taken care of
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_destroy()

--[[
	-- Remove all references
	for k, v in pairs( self ) do self[ k ] = nil end

	-- Remaining marker to ensure it gets handled as removed
	self._removed = true
--]]

end

-----------------------------------------------------------------------------------------
-- _update()
-- Where all the children are updated, and also where they are destroyed if necessary
-- from 'natural' causes (eg they completed and are ready for removal)
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_update( parentPosition, forceUpdate )

	-- Should this timeline be ignored for any reason?
	if ( self._removed or self._isPaused ) and true ~= forceUpdate then return false, true end

	-- Get previous update's values
	local oldPosition = self._position
	local oldHasCompleted = self._hasCompleted

	-- Calculate position
	local duration
	if self._duration then duration = self._duration / self._speedScale end
	local position = parentPosition - self._offsetTime

	-- Store the position
	self._position = position

	-- Useful
	if not self._hasCompleted then

		-- Check for passing markers and deal with them
		self:_processMarkers( position, oldPosition, duration )

		-- Clear the need to include the old position (it is only needed for the first update after a set position change)
		self._includeOldPositionInChecks = nil

		-- Create a duplicate of the objects to process to work on
		local activeTweenObjects = {}
		local currentTweenObjects = {}
		for i = 1, #self._children do
			activeTweenObjects[ i ] = self._children[ i ]
			currentTweenObjects[ self._children[ i ] ] = true
		end
		local tweenObjectsToRemove = {}
		local allTweensPaused = true

		-- Loop through all tween objects
		for i = 1, #activeTweenObjects do

			-- Update the tween
			local tweenObject = activeTweenObjects[ i ]
			local tweenCompleted, forceRemove = tweenObject:_update( position * self._speedScale )

			-- Mark tween for removal if it completed in the default timeline
			if tweenCompleted and self._isDefaultTimeline then
				tweenObjectsToRemove[ #tweenObjectsToRemove + 1 ] = i
			end
		end

		-- Delete tween objects no longer in use
		for i = #tweenObjectsToRemove, 1, -1 do
			local tweenObjectToRemove = activeTweenObjects[ tweenObjectsToRemove[ i ] ]
			tweenObjectToRemove:_destroy()
			table.remove( activeTweenObjects, tweenObjectsToRemove[ i ] )
		end

		-- Merge in any new tween objects created while we processed the ones that existed before
		local tempTweenObjects = self._children or {}
		for i = 1, #tempTweenObjects do
			local tweenObject = tempTweenObjects[ i ]

			-- Did this object exist previously? If not, add it to the active list
			if not currentTweenObjects[ tweenObject ] then
				activeTweenObjects[ #activeTweenObjects + 1 ] = tweenObject
				if not tweenObject._isPaused then allPaused = false end
			end
		end

		-- Remove any ._removed objects from external factors
		-- Now, given how this works, could I actually simplify the entire loop above and take out the 'working copies' etc?
		for i = #activeTweenObjects, 1, -1 do
			if activeTweenObjects[ i ]._removed then table.remove( activeTweenObjects, i ) end
		end

		-- We only call the timeline's onComplete listener after everything else has been processed
		if oldHasCompleted ~= self._hasCompleted and true == self._hasCompleted then

			-- Alert with the onComplete callback if exists
			if self.onComplete then self.onComplete( self ) end

			-- If this wants to automatically cancel itself upon completion, do so
			if true == self._autoCancel then self:cancel() end
		end

		-- Store the valid active timelines
		self._children = activeTweenObjects
	end

	-- Return that this timeline was not removed, and if active or not
	return false, allTweensPaused

end

-----------------------------------------------------------------------------------------
-- _processMarkers()
-- Where we find if we have passed any markers and if so, call the callback
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_processMarkers( position, oldPosition, duration )

	-- For non-default timelines check for start and completion
	-- The default timeline basically always runs
	if not self._isDefaultTimeline then

		-- Trigger the start function if we've passed the start time
		if not self._hasStarted and 0 <= position and not self._hasCompleted then
			self._hasStarted = true
			if self.onStart then self.onStart( self ) end
		end

		-- Have we completed this timeline?
		if duration and position >= duration then
			position = duration

			-- Mark as completed
			self._hasCompleted = true
		end

		-- Process markers for callbacks
		-- Note that if _includeOldPositionInChecks == true, we check from start
		-- position (inclusive) to end position (inclusive)
		-- Otherwise we check from > start position to end position (inclusive)
		-- NOTE This could be sped up by storing what the last marker checked was
		-- (and we reset it whenever there's a position change)
		local markers = self._markersInOrder
		if #markers > 0 then
			local speedScale = self._speedScale
			local includeOldPositionInChecks = self._includeOldPositionInChecks
			for i = 1, #markers do
				local marker = markers[ i ]

				-- Is this marker after (or at the same time as, depending on _includeOldPositionInChecks) the start position?
				local includeMarker
				if true == includeOldPositionInChecks then includeMarker = ( oldPosition <= ( marker.time / speedScale ) )
				else includeMarker = ( oldPosition < ( marker.time / speedScale ) ) end

				-- Have we found the first marker after our current start position?
				if includeMarker then

					-- Now find all the markers (including the first one found) that are before or equal to the end position
					for j = i, #markers do
						local marker = markers[ j ]
						if ( marker.time / speedScale ) <= position then

							-- If the timeline has an onMarkerPass callback, call it
							if self.onMarkerPass then self.onMarkerPass{ name = marker.name, time = marker.time, timeline = self } end
						else

							-- Outside, so we stop
							break
						end
					end

					-- No more checking needed, we already found the range (whether empty or not)
					break
				end
			end
		end
	end

end

-----------------------------------------------------------------------------------------
-- _setPosition( [whatToSetPosition,] parentPosition )
-- Moves the playback head to the given parentPosition
-- Position can be a time in milliseconds
-- It can also be a marker name
-- This does not work on nested timelines (which are controlled by the overall parent)
-- whatToSetPosition can be a tag or display object
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_setPosition( whatToSetPosition, parentPosition )

	-- If this object has been removed, do nothing
	if self._removed then return end

	-- Allow for missed parameters
	if not parentPosition then
		parentPosition = whatToSetPosition
		whatToSetPosition = nil
	end

	-- Check a valid parameter was passed
	if not parentPosition or ( "number" ~= type( parentPosition ) and "string" ~= type( parentPosition ) ) then
		error( DEBUG_STRING .. " you must pass a number or marker name to a timelineObject:setPosition() call." )
	end

	-- Is this a marker? If so convert to a time position
	-- If no marker exists, stop trying to set the position
	if "string" == type( parentPosition ) then
		marker = self._markers[ parentPosition ]
		if not parentPosition then return
		else parentPosition = marker.time end
	end

	-- Special case for default timeline, it doesn't set its own position, it sets its children directly
	if self._isDefaultTimeline then
		for i = 1, #self._children do
			if whatToSetPosition then self._children[ i ]:_setPosition( whatToSetPosition, parentPosition )
			else self._children[ i ]:_setPosition( parentPosition ) end
		end

		-- Stop processing
		return
	end

	-- Is this a valid timeline object to affect?
	if whatToSetPosition and whatToSetPosition ~= self.tag then return end

	-- What is the change in position?
	local positionChange = ( self._position - parentPosition ) -- / self._speedScale

	-- Set the offset based upon this
	self._offsetTime = self._offsetTime + positionChange

	-- Update paused time if necessary
	if self._lastPausedTime then

		-- Factor in for how long it has been paused
		local pausedTime = system.getTimer() - self._lastPausedTime

		-- Change both current offset and paused offset by this amount
		self._offsetTime = self._offsetTime + pausedTime
		self._lastPausedTime = self._lastPausedTime + pausedTime
	end

	-- Set the actual position property (needed to ensure that when the callback is triggered, the position is in the right place)
	local position = parentPosition
	self._position = position

	-- For the next update, include the old position in marker checks
	-- Normally markers are processed in the range > start time to == end time
	-- In this case we want == start time to == end time
	self._includeOldPositionInChecks = true

	-- Handle callback for changes
	if self.onPositionChange then self.onPositionChange( self ) end

	-- If this timeline was complete but now it would be played again, remove the completed flag
	-- Note the extra check in case there's no duration (infinite repeats)
	-- In theory you shouldn't be able to complete a timeline of infinite duration, but...
	local duration = self:getDuration()
	if self._hasCompleted and ( not duration or position <= self:getDuration() ) then
		self._hasCompleted = nil
	end

	-- If this tween had started but now it would be set to before it started, remove the started flag
	if self._hasStarted and 0 >= position then self._hasStarted = nil end

	-- Cascade down any change events if required
	for i = 1, #self._children do
		self._children[ i ]:_setPosition( position * self._speedScale )
	end

end

-----------------------------------------------------------------------------------------
-- _setSpeedScale( [whatToSetSpeed,] speedScale )
-- Sets the speed multiplier of this timeline
-- It must be a number value of >0
-- Care must be taken in case the timeline is paused, IE affect ._lastPausedTime
-- Also, parents need to know about this change in case it extends the total duration
-- of the timeline
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_setSpeedScale( whatToSetSpeed, speedScale )

	-- If this object has been removed, do nothing
	if self._removed then return end

	-- Allow for missed parameter
	-- This happens when you call this via timelineObject:setSpeedScale( speedScale )
	if not speedScale then
		speedScale = whatToSetSpeed
		whatToSetSpeed = nil
	end

	-- Check a valid parameter was passed
	if not speedScale or "number" ~= type( speedScale ) or 0 >= speedScale then
		error( DEBUG_STRING .. " you must pass a positive number to a setSpeedScale() call, not " .. tostring( speedScale ) )
	end

	-- Special case for default timeline, it doesn't set its own speedscale, it sets its children directly
	if self._isDefaultTimeline then
		for i = 1, #self._children do
			self._children[ i ]:_setSpeedScale( whatToSetSpeed, speedScale )
		end

		-- Stop processing
		return
	end

	-- Don't need to set the speed if this object isn't what we are after
	-- Matches are just by tag or object reference
	if whatToSetSpeed and ( whatToSetSpeed ~= self.tag and whatToSetSpeed ~= self ) then return end

	-- Alter the offset to cater for the new speed. Note that it is based on the old speed too
	-- This ensures we only change the speed, not the position
	local currentTime = system.getTimer()
	local scalar = self._speedScale / speedScale
	self._offsetTime = currentTime + ( self._offsetTime - currentTime ) * scalar

	-- Alter the paused time if there is one
	if self._lastPausedTime then
		self._lastPausedTime = currentTime + ( self._lastPausedTime - currentTime ) * scalar
	end

	-- Update the position
	self._position = self._position * scalar

	-- Set the speed
	self._speedScale = speedScale

	-- Alert the parent that it needs to recalculate
	if self._parent and not self._parent._isDefaultTimeline then
		self._parent:_calculateAndSetTotalDuration( self:getTotalDuration() )
	end

end

-----------------------------------------------------------------------------------------
-- _pause(  whatToPause )
-- Pauses the timeline and all children
-- This recurses, generating callbacks from itself and all children that have them
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_pause( whatToPause )

	-- If this object has been removed, do nothing
	if self._removed then return end

	-- This and all children share a paused time
	local pausedTime = system.getTimer()

	-- Special case for default timeline, it doesn't pause itself, it pauses its children directly
	if self._isDefaultTimeline then

		-- Pause all children with this paused time
		for i = 1, #self._children do
			self._children[ i ]:_pause( whatToPause, pausedTime )
		end

		-- Stop processing
		return
	end

	-- Already paused, so stop processing
	if self._isPaused then return end

	-- Should this be paused? Matches against tag (no target for timelines)
	if whatToPause and self.tag ~= whatToPause then return end

	-- Mark as paused directly
	self._isPaused = true

	-- Store when this was paused
	self._lastPausedTime = pausedTime

	-- Recurse through the children pausing them all
	for i = 1, #self._children do
		self._children[ i ]:_pause()
	end

	-- If there is a pause callback set, use it
	if self.onPause then self.onPause( self ) end

end

-----------------------------------------------------------------------------------------
-- _resume( whatToResume )
-- Resumes the timeline
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_resume( whatToResume )

	-- If this object has been removed, do nothing
	if self._removed then return end

	-- Special case for default timeline, it doesn't resume itself, it resumes its children directly
	if self._isDefaultTimeline then
		for i = 1, #self._children do
			self._children[ i ]:_resume( whatToResume )
		end

		-- Stop processing
		return
	end

	-- Not paused, so stop processing
	if not self._isPaused then return end

	-- Should this be resumed? Matches against tag (no target for timelines)
	if whatToResume and self.tag ~= whatToResume then return end

	-- Mark as not paused directly
	self._isPaused = nil

	-- Only continue exactly from where you left off
	self._offsetTime = self._offsetTime + ( system.getTimer() - self._lastPausedTime )

	-- Clear paused time
	self._lastPausedTime = nil

	-- Recurse through the children resuming them all
	for i = 1, #self._children do
		self._children[ i ]:_resume()
	end

	-- If there is a resume callback set, use it
	if self.onResume then self.onResume( self ) end

end

-----------------------------------------------------------------------------------------
-- _cancel()
-- cancels the timeline and everything in it (or rather marks it all for cancelling)
-- This works differently to pause / resume etc, as it *can* recurse and locate specific
-- items in children
-- The logic behind this is if you call cancel with a display object etc. you really
-- would expect it to be removed (particularly if you are then going to removeSelf() it)
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:_cancel( whatToCancel )

	-- Ignore if already completed
	if self._removed then return end

	-- Determine if this object should be cancelled
	local cancelThis = true
	if whatToCancel then

		-- If this timeline has a tag, does it match the passed string?
		if "string" == type( whatToCancel ) then cancelThis = ( whatToCancel == self.tag )

		-- Is this the right target?
		elseif "table" == type( whatToCancel ) then cancelThis = ( whatToCancel == self.target ) end	
	end

	-- Cancel this object if needed
	if true == cancelThis then self._removed = true end

	-- Recurse through the children (they remove themselves from self's _children table as needed)
	for i = #self._children, 1, -1 do
		self._children[ i ]:_cancel( whatToCancel )
	end

	-- Destroy this object if necessary
	if true == cancelThis then

		-- If there is a cancel callback set, use it
		if self.onCancel then self.onCancel( self ) end

		-- Destroy the object
		self:_destroy()

		-- Return that this was cancelled
		return true
	end

end

--=====================================================================================--
-- Public functions ===================================================================--
--=====================================================================================--

-----------------------------------------------------------------------------------------
-- addMarker( markerName, time )
-- Creates a marker in the timeline at the specified time
-- Markernames must be unique (returns 'false' if one already exists with this name)
-- If a natural movement of the playback head crosses more than one marker with callbacks,
-- all callbacks are called in the correct order
-- If several markers share the same time, their order of callback is unspecified
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:addMarker( markerName, time )

	-- Ignore if already completed
	if self._removed then return end

	-- Check a valid parameter was passed
	if not markerName or "string" ~= type( markerName ) then
		error( ERROR_STRING .. " you must pass a string as the markerName parameter to a timeline:addMarker() call." )
	end

	-- Check a valid parameter was passed
	if not time or "number" ~= type( time ) or 0 >= time then
		error( ERROR_STRING .. " you must pass a positive number as the time parameter to a timeline:addMarker() call." )
	end

	-- Check this marker name is unique. If it already exists return false
	if self._markers[ markerName ] then return false end

	-- Create a marker table containing all relevant data
	local marker = {
		name = markerName,
		time = time,
	}

	-- Store marker by name
	self._markers[ markerName ] = marker

	-- Store marker by time and sort the table to ensure the correct order
	local markersInOrder = self._markersInOrder
	markersInOrder[ #markersInOrder + 1 ] = marker
	table.sort( markersInOrder, private.sortMarkersByTime )

	-- Calculate the new duration for the timeline
	self:_calculateAndSetTotalDuration( time )

	-- Return that creation was successful
	return true

end

-----------------------------------------------------------------------------------------
-- deleteMarker( markerName )
-- Deletes the marker with the supplied name
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:deleteMarker( markerName )

	-- Ignore if already completed
	if self._removed then return end

	-- Check a valid parameter was passed
	if not markerName or "string" ~= type( markerName ) or not self._markers[ markerName ] then
		print( WARNING_STRING .. " you must pass an existing marker name to a timeline:deleteMarker() call." )
		return
	end

	-- Clear the reference by name
	self._markers[ markerName ] = nil

	-- Find the marker in the ordered table and remove it
	local markersInOrder = self._markersInOrder
	for i = #markersInOrder, 1, -1 do
		if markerName == markersInOrder[ i ].name then
			table.remove( markersInOrder, i )
			break
		end
	end

end

-----------------------------------------------------------------------------------------
-- getMarkers()
-- Returns a copy of all the markers that exist
-- Keys are marker names, value is the time
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:getMarkers()

	-- Ignore if already completed
	if self._removed then return end

	-- Create a new table containing the marker data (prevents users editing the data)
	local copyMarkers = {}
	for k, v in pairs( self._markers ) do
		copyMarkers[ k ] = v.time
	end

	-- Return the data
	return copyMarkers

end

-----------------------------------------------------------------------------------------
-- getDuration()
-- Returns the duration of all active parts of the timeline object in milliseconds
-- If a child has infinite repetitions, it returns nil
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:getDuration()

	-- Ignore if already completed
	if self._removed then return end

	if self._duration then return self._duration / self._speedScale
	else return end

end

-----------------------------------------------------------------------------------------
-- getTotalDuration()
-- Returns the duration of all parts of the timeline object active or otherwise, in
-- milliseconds
-- If a child has infinite repetitions, it returns nil
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:getTotalDuration()

	-- Ignore if already completed
	if self._removed then return end

	if self._duration then return self:getDuration() + ( self._startTime or 0 )
	else return end

end

-----------------------------------------------------------------------------------------
-- setPosition( position )
-- Moves the playback head to the given position
-- Position can be a time in milliseconds
-- It can also be a marker name
-- This can only be called directly - it prevents problems with parameters
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:setPosition( position )

	-- Relay the message to the internal function
	return self:_setPosition( position )

end

-----------------------------------------------------------------------------------------
-- getPosition( getClipped )
-- Returns the position of the playback head
-- Value can be negative (before the start of the timeline) or greater than the duration
-- of the timeline (has finished)
-- If getClipped = true, the returned value is clipped to the lifespan of the timeline
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:getPosition( getClipped )

	-- Ignore if already completed
	if self._removed then return end

	if true == getClipped then
		if self._duration then return mMin( mMax( self._position or 0, 0 ), self:getDuration() )
		else return mMax( self._position ) end
	else
		return self._position
	end

end

-----------------------------------------------------------------------------------------
-- setSpeedScale( speedScale )
-- Sets the speed multiplier of this timeline
-- It must be a number value of >0
-- Care must be taken in case the timeline is paused, IE affect ._lastPausedTime
-- Also, parents need to know about this change in case it extends the total duration
-- of the timeline
-- This can only be called directly - it prevents problems with parameters
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:setSpeedScale( speedScale )

	-- Relay the message to the internal function
	return self:_setSpeedScale( speedScale )

end

-----------------------------------------------------------------------------------------
-- getSpeedScale()
-- Returns the current speed multiplier of this tween
----------------------------------------------------------------------------------------
function timelineObjectLibrary:getSpeedScale()

	-- Ignore if already completed
	if self._removed then return end

	return self._speedScale

end

-----------------------------------------------------------------------------------------
-- pause()
-- Pauses the timeline and all children
-- This can only be called directly - it prevents problems with parameters
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:pause()

	-- Relay the message to the internal function
	return self:_pause()

end

-----------------------------------------------------------------------------------------
-- resume( whatToResume )
-- Resumes the timeline
-- This can only be called directly - it prevents problems with parameters
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:resume()

	-- Relay the message to the internal function
	return self:_resume()

end

-----------------------------------------------------------------------------------------
-- cancel( whatToResume )
-- Cancels the timeline
-- This can only be called directly - it prevents problems with parameters
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:cancel()

	-- Relay the message to the internal function
	return self:_cancel()

end

-----------------------------------------------------------------------------------------
-- getIsPaused()
-- Returns whether the timeline is paused or not for whatever reason
-----------------------------------------------------------------------------------------
function timelineObjectLibrary:getIsPaused()

	-- Ignore if already completed
	if self._removed then return end

	-- Return whether this is paused or not (by any means)
	return true == self._isPaused

end

--=====================================================================================--

-- Returns the timeline object library
return timelineObjectLibrary