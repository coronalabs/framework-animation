
--=====================================================================================--

--=====================================================================================--
-- Library objects ====================================================================--
--=====================================================================================--

local Library = require "CoronaLibrary"

-- Create library
local animationLibrary = Library:new{ name='animation', publisherId='com.coronalabs' }
local private = {}

local timelineObjectLibrary = require( "plugin.animation.timeline" )
local tweenObjectLibrary = require( "plugin.animation.tween" )

--=====================================================================================--
-- Constants ==========================================================================--
--=====================================================================================--

local DEBUG_STRING = "Animation: "
local WARNING_STRING = "WARNING: " .. DEBUG_STRING
local ERROR_STRING = "ERROR: " .. DEBUG_STRING

--=====================================================================================--
-- Library variables ==================================================================--
--=====================================================================================--

private.timelines = {}
private.hasRuntimeListener = false
private.defaultTimelineTag = "_default"

--=====================================================================================--
-- Private functions ==================================================================--
--=====================================================================================--

-----------------------------------------------------------------------------------------
-- enterFrame( event )
-- The frame listener for the animation library
-- It works on a copy of the original list of timelines (activeTimelines), but doesn't
-- clear the old one
-- This was because of a bug when attempting to affect timelines etc within the loop
-- could not see the current ones
-- However, users still can't directly affect the list of timelines being processed
-- The active timelines list is merged with any new timelines created during the
-- enterFrame() at the end (this is the purpose of currentTimelines, which tracks which
-- timelines were not created during the update)
-----------------------------------------------------------------------------------------
function private.enterFrame( event )

	-- Event time
	local eventTime = event.time

	-- Get variables for later use
	local allTimelinesPaused = true

	-- Create a duplicate of the timelines to process to work on
	local activeTimelines = {}
	local currentTimelines = {}
	for i = 1, #private.timelines do
		activeTimelines[ i ] = private.timelines[ i ]
		currentTimelines[ private.timelines[ i ] ] = true
	end

	-- Timelines to be destroyed
	local timelinesToRemove = {}

	-- Update all timelines in order - if default exists it should always be index 1
	-- This isn't precisely necessary, but I force it so these all get processed first,
	-- followed by custom timelines
	for i = 1, #activeTimelines do
		local activeTimeline = activeTimelines[ i ]

		-- Only process this timeline if it is not nested (has no parent or parent is default timeline)
		-- NOTE this check should not be relevant anymore, as nested timelines are removed from the timelines table
		if not activeTimeline._parent or private.defaultTimeline == activeTimeline._parent then

			-- Timeline update returns whether the timeline was removed (true) and
			-- if not, if it is active (true) or paused (false)
			local wasRemoved, isActive = activeTimeline:_update( eventTime )

			-- If this was removed, act accordingly
			if wasRemoved then
				timelinesToRemove[ #timelinesToRemove + 1 ] = i

			-- If this timeline was active, note that *something* is happening this frame
			elseif true == isActive then
				allTimelinesPaused = false
			end
		end
	end

	-- Delete timeline objects no longer in use (they destroy() themselves)
	if #timelinesToRemove > 0 then
		for i = #timelinesToRemove, 1, -1 do
			local timelineToRemove = activeTimelines[ timelinesToRemove[ i ] ]
			timelineToRemove:_destroy()
			table.remove( activeTimelines, timelinesToRemove[ i ] )
		end

		-- If the default timeline was also cancelled, clear the direct private reference to it
		--if private.defaultTimeline and private.defaultTimeline._removed then private.defaultTimeline = nil end
	end

	-- Merge in any new timelines created while we processed the ones that existed before
	local tempTimelines = private.timelines
	for i = 1, #tempTimelines do
		local timeline = tempTimelines[ i ]

		-- Did this timeline exist previously? If not, add it to the active list
		if not currentTimelines[ timeline ] then
			activeTimelines[ #activeTimelines + 1 ] = timeline
		end
	end

	-- Remove any ._removed timelines from external factors
	-- Now, given how this works, could I actually simplify the entire loop above and take out the 'working copies' etc?
	for i = #activeTimelines, 1, -1 do
		if activeTimelines[ i ]._removed then table.remove( activeTimelines, i ) end
	end

	-- Store the valid active timelines
	private.timelines = activeTimelines

	-- Clean up if there are no active tweens (either all finished, or all paused)
	--if ( 0 == #timelines or true == allTimelinesPaused ) and private.hasRuntimeListener then
	--if 0 == #timelines and private.hasRuntimeListener then
	--	Runtime:removeEventListener( "enterFrame", private.enterFrame )
	--	private.hasRuntimeListener = false
	--end

end

-----------------------------------------------------------------------------------------
-- newDefaultTimeline()
-- Creates a new time line and makes it the default
-- There can only ever be 1 default timeline, and it is invisible to the users
-----------------------------------------------------------------------------------------
function private.newDefaultTimeline()

	-- Create a new timeline object and assign the specific tag to it
	local timelineObject = animationLibrary.newTimeline( { tag = private.defaultTimelineTag, _isDefaultTimeline = true } )

	-- Default timeline starts automatically playing
	timelineObject._isPaused = nil

	-- Store the default timeline both with a private reference
	private.defaultTimeline = timelineObject

	-- Return the default timeline
	return timelineObject

end

-----------------------------------------------------------------------------------------
-- copyTable( tableToCopy )
-- Creates a copy of the table
-----------------------------------------------------------------------------------------
function private.copyTable( tableToCopy )

	-- Temporary copy table
	local copyTable = {}

	-- Copy all of tableToCopy's properties into the new table
	for k, v in pairs( tableToCopy ) do
		copyTable[ k ] = v
	end

	return copyTable

end

--=====================================================================================--
-- Public functions ===================================================================--
--=====================================================================================--

-----------------------------------------------------------------------------------------
-- pause( whatToPause )
-- Pauses the whatToPause tween object, timeline, tag or display object
-- In each case it calls the private _pause() function in the tween or timeline object
-----------------------------------------------------------------------------------------
function animationLibrary.pause( whatToPause )

	-- Pause everything
	if not whatToPause then
		for i = 1, #private.timelines do
			private.timelines[ i ]:_pause()
		end

	-- Pause default timeline
	elseif private.defaultTimelineTag == whatToPause then
		private.defaultTimeline:_pause()

	-- Pause by tag within all timelines
	elseif "string" == type( whatToPause ) then

		-- Go through each timeline, only pausing if the root timeline has this tag
		-- Unless it is the default timeline in which case it parses its first level
		for i = 1, #private.timelines do
			private.timelines[ i ]:_pause( whatToPause )
		end

	-- Could be a tween, timeline, display object or userdata reference
	elseif "table" == type( whatToPause ) or "userdata" == type( whatToPause ) then

		-- Is a timeline or tween object
		if whatToPause._isTween or whatToPause._isTimeline then
			whatToPause:_pause()

		-- A display object or userdata (requires recursive searching)
		-- This only works on the default timeline
		else
			private.defaultTimeline:_pause( whatToPause )
		end
	end

end

-----------------------------------------------------------------------------------------
-- resume( whatToResume )
-- Resumes the whatToResume tween object, display object, timeline, tag or nil for all
-- In each case it calls the private _resume() function in the tween or timeline object
-----------------------------------------------------------------------------------------
function animationLibrary.resume( whatToResume )

	-- Pause everything
	if not whatToResume then
		for i = 1, #private.timelines do
			private.timelines[ i ]:_resume()
		end

	-- Resume default timeline
	elseif private.defaultTimelineTag == whatToResume then
		private.defaultTimeline:_resume()

	-- Resume by tag within all timelines or
	elseif "string" == type( whatToResume ) then

		-- Go through each timeline (which will do recursive resuming as necessary)
		for i = 1, #private.timelines do
			private.timelines[ i ]:_resume( whatToResume )
		end

	-- Could be a tween, timeline, display object or userdata reference
	elseif "table" == type( whatToResume ) or "userdata" == type( whatToResume ) then

		-- Is a timeline or tween object
		if whatToResume._isTween or whatToResume._isTimeline then
			whatToResume:_resume()

		-- A display object or userdata (requires recursive searching)
		-- This only works on the default timeline
		else
			private.defaultTimeline:_resume( whatToResume )
		end
	end

end

-----------------------------------------------------------------------------------------
-- cancel( whatToCancel )
-- Cancels the whatToCancel tween object, display object, timeline, tag or nil for all
-- Note that unlike the pause() / resume() functions, this does go into children where
-- needed when a display object is passed as whatToCancel
-- This is because there should be nothing preventing clean-up, even under bizarre
-- circumstances - it is more important to prevent a memory leak even if it creates
-- strange behaviour
-- In each case it calls the private _cancel() function in the tween or timeline object
-----------------------------------------------------------------------------------------
function animationLibrary.cancel( whatToCancel )

	-- Cancel everything
	if not whatToCancel then
		for i = #private.timelines, 1, -1 do
			private.timelines[ i ]:_cancel()
		end

		-- Empty all timelines
		private.timelines = {}
		private.defaultTimeline = nil

	-- Cancel by tag
	elseif "string" == type( whatToCancel ) then

		-- Go through each timeline (which will do recursive cancelling as necessary)
		for i = #private.timelines, 1, -1 do

			-- If this timeline was cancelled, remove it from storage
			if private.timelines[ i ]:_cancel( whatToCancel ) then

				-- Clear the default timeline reference if it was cancelled
				if private.timelines[ i ]._isDefaultTimeline then private.defaultTimeline = nil end
				
				-- Remove the timeline from the timelines storage
				table.remove( private.timelines, i )
			end
		end

	-- Could be a tween, timeline, display object or userdata reference
	elseif "table" == type( whatToCancel ) or "userdata" == type( whatToCancel ) then

		-- Is a timeline or tween object
		if whatToCancel._isTween or whatToCancel._isTimeline then
			whatToCancel:_cancel()

		-- A display object or userdata (requires recursive searching)
		-- This the exception to the rule of not recursing into custom timelines
		else

			-- Go through each timeline / tween object (which will do recursive cancel as necessary)
			for i = 1, #private.timelines do
				private.timelines[ i ]:_cancel( whatToCancel )
			end
		end
	end

end

-----------------------------------------------------------------------------------------
-- setSpeedScale( whatToSetSpeed, speedScale )
-- sets the speed multiplier of whatToSetSpeed tween, timeline, tag or display object
-- In each case it calls the private _setSpeedScale() function in the tween or timeline
-- object
-----------------------------------------------------------------------------------------
function animationLibrary.setSpeedScale( whatToSetSpeed, speedScale )

	-- Allow for missed parameter
	-- This happens when you want to set the speed scale of everything
	-- IE tween.setSpeedScale( speedScale )
	if not speedScale then
		speedScale = whatToSetSpeed
		whatToSetSpeed = nil
	end

	-- Check a valid parameter was passed
	if not speedScale or "number" ~= type( speedScale ) or 0 >= speedScale then
		error( ERROR_STRING .. "you must pass a positive number as the speedScale parameter to a tween.setSpeedScale() call." )
	end

	-- Set speed of everything everything
	if not whatToSetSpeed then
		for i = 1, #private.timelines do
			private.timelines[ i ]:_setSpeedScale( speedScale )
		end

	-- Set speed within default timeline only
	elseif private.defaultTimelineTag == whatToSetSpeed then
		private.defaultTimeline:_setSpeedScale( speedScale )

	-- Set speed by tag within all timelines
	elseif "string" == type( whatToSetSpeed ) then

		-- Go through each timeline (which will do recursive speed setting as necessary)
		for i = 1, #private.timelines do
			private.timelines[ i ]:_setSpeedScale( whatToSetSpeed, speedScale )
		end

	-- Could be a tween, timeline, display object or userdata reference
	elseif "table" == type( whatToSetSpeed ) or "userdata" == type( whatToSetSpeed ) then

		-- Is a timeline or tween object
		if whatToSetSpeed._isTween or whatToSetSpeed._isTimeline then
			whatToSetSpeed:_setSpeedScale( speedScale )

		-- A display object or userdata (requires recursive searching)
		-- This only works on the default timeline
		else
			private.defaultTimeline:_setSpeedScale( whatToSetSpeed, speedScale )
		end
	end

end

-----------------------------------------------------------------------------------------
-- setPosition( whatToSetPosition, position )
-- sets the position of whatToSetPosition tween, timeline, tag or display object
-- In each case it calls the private _setPosition() function in the tween or timeline
-- object
-----------------------------------------------------------------------------------------
function animationLibrary.setPosition( whatToSetPosition, position )

	-- Allow for missed parameter
	if not position then
		position = whatToSetPosition
		whatToSetPosition = nil
	end

	-- Check a valid parameter was passed
	if not position or ( "number" ~= type( position ) and "string" ~= type( position ) ) then
		error( ERROR_STRING .. " you must pass a number or a marker name to an animation.setPosition() call." )
	end

	-- Check a valid parameter was passed
	if "number" == type( position ) and position < 0 then
		error( DEBUG_STRING .. " you cannot pass a negative position to an animation.setPosition() call." )
	end

	-- Set position of everything
	if not whatToSetPosition then
		for i = 1, #private.timelines do
			private.timelines[ i ]:_setPosition( position )
		end

	-- Set position within default timeline
	elseif private.defaultTimelineTag == whatToSetPosition then
		private.defaultTimeline:_setPosition( position )

	-- Position by tag within all timelines
	elseif "string" == type( whatToSetPosition ) then

		-- Go through each timeline (which will do recursive speed setting as necessary)
		for i = 1, #private.timelines do
			private.timelines[ i ]:_setPosition( whatToSetPosition, position )
		end

	-- Could be a tween, timeline, display object or userdata reference
	elseif "table" == type( whatToSetPosition ) or "userdata" == type( whatToSetPosition ) then

		-- Is a timeline or tween object
		if whatToSetPosition._isTween or whatToSetPosition._isTimeline then
			whatToSetPosition:_setPosition( position )

		-- A display object or userdata (requires recursive searching)
		-- This only works on the default timeline
		else
			private.defaultTimeline:_setPosition( whatToSetPosition, position )
		end
	end

end

-----------------------------------------------------------------------------------------
-- newTimeline( params )
-- Creates a new timeline
-- Users calling this will create a custom timeline that by default is paused
-- Is also called internally to create the default timeline as needed
-- (see private.newDefaultTimeline())
-- Whether a timeline is the default or not is a _isDefaultTimeline parameter
-----------------------------------------------------------------------------------------
function animationLibrary.newTimeline( params )

	-- Create the new timeline object
	local timelineObject = timelineObjectLibrary._new( params )

	-- Where to store the timeline object?
	if true == timelineObject._isDefaultTimeline then

		-- Default timeline object is always stored first in the timelines list
		table.insert( private.timelines, 1, timelineObject )
	else

		-- Non default timeline objects are simply appended to the timelines list
		private.timelines[ #private.timelines + 1 ] = timelineObject
	end

	-- Add enterFrame handler if we don't yet have one
	-- Note this check also happens in to() - the two entry points into the library
	if false == private.hasRuntimeListener then
		Runtime:addEventListener( "enterFrame", private.enterFrame )
		private.hasRuntimeListener = true
	end

	-- Return the new timeline object
	return timelineObject

end

-----------------------------------------------------------------------------------------
-- to( targetObject, valuesToTween, tweenSettings, invertParameters )
-- Tweens an object to the specified tweenParams
-- If invertParameters is set to true then this is the same as .from()
-----------------------------------------------------------------------------------------
function animationLibrary.to( targetObject, valuesToTween, tweenSettings, invertParameters )

	-- Checks for valid parameters
	if not targetObject or ( type( targetObject ) ~= "table" and type( targetObject ) ~= "userdata" ) then error( ERROR_STRING .. " you must pass a table, display object, .path or .fill.effect to an animation.to() call." ) end
	if not valuesToTween or type( valuesToTween ) ~= "table" then error( ERROR_STRING .. " you must pass a properties table to an animation.to() call." ) end
	if not tweenSettings or type( tweenSettings ) ~= "table" then error( ERROR_STRING .. " you must pass a params table to an animation.to() call." ) end

	-- If there's no default timeline yet, create it
	local timelineObject = private.defaultTimeline
	if nil == private.defaultTimeline then timelineObject = private.newDefaultTimeline() end

	-- Create the tween in the default timeline
	local tweenObject = timelineObject:_createTween( targetObject, valuesToTween, tweenSettings, nil, invertParameters )

	-- Return the new tween object
	return tweenObject

end

-----------------------------------------------------------------------------------------
-- from( targetObj, valuesToTween, tweenSettings )
-- Tweens an object from the specified valuesToTween to its current values
-- This just calls the .to() function, with the invertParameters property set to true
-----------------------------------------------------------------------------------------
function animationLibrary.from( targetObject, valuesToTween, tweenSettings )

	-- Checks for valid parameters
	if not targetObject or ( type( targetObject ) ~= "table" and type( targetObject ) ~= "userdata" ) then error( ERROR_STRING .. " you must pass a table, display object, .path or .fill.effect to an animation.from() call." ) end
	if not valuesToTween or type( valuesToTween ) ~= "table" then error( ERROR_STRING .. " you must pass a properties table to an animation.from() call." ) end
	if not tweenSettings or type( tweenSettings ) ~= "table" then error( ERROR_STRING .. " you must pass a params table to an animation.from() call." ) end

	-- Return the new tween object (same as .to but with the invertParameters set)
	return animationLibrary.to( targetObject, valuesToTween, tweenSettings, true )

end

-----------------------------------------------------------------------------------------
-- getAnimations( tagOrDisplayObject )
-- Returns a table of tweens and timelines that match the supplied criteria
-- If a timeline contains any tween that matches, just the timeline itself is returned
-----------------------------------------------------------------------------------------
function animationLibrary.getAnimations( tagOrDisplayObject )

	-- Create an empty results table
	local allMatches = { tweens = {}, timelines = {} }

	-- Loop through all timelines
	for i = 1, #private.timelines do
		local timelineObject = private.timelines[ i ]
		local matches = timelineObject:_match( tagOrDisplayObject )

		-- Merge matches
		if #matches > 0 then

			-- The private timeline adds individual tweens
			if true == timelineObject._isDefaultTimeline then
				allMatches.tweens = matches

			-- Custom timelines merely add themselves
			else
				allMatches.timelines[ #allMatches.timelines + 1 ] = timelineObject
			end
		end
	end

	-- Return all found matches
	return allMatches

end

--=====================================================================================--

return animationLibrary