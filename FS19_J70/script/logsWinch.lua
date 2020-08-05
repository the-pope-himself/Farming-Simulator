--
-- Speciaziation class for logging winch
-- V2.0
-- @author 50keda
-- @date 20/12/2018
-- Copyright (C) 50keda, All Rights Reserved.


LogsWinch = {}
LogsWinch.JointMarginLimit = 0.8
LogsWinch.MinJointTransLimit = 0.35
LogsWinch.ModDirectory = g_currentModDirectory
LogsWinch.Actions = {
	LOGSWINCH_ATTACH_DETACH = { "ATTACH_DETACH", Player.INPUT_CONTEXT_NAME, false, true, false, GS_PRIO_VERY_HIGH },
	LOGSWINCH_DETACH_ALL = { "DETACH_ALL", Vehicle.INPUT_CONTEXT_NAME, false, true, false, GS_PRIO_VERY_HIGH },
	LOGSWINCH_WINCH_PLAYER = { "WINCH", Player.INPUT_CONTEXT_NAME, false, false, true, GS_PRIO_VERY_HIGH },
	LOGSWINCH_WINCH_VEHICLE = { "WINCH", Vehicle.INPUT_CONTEXT_NAME, false, false, true, GS_PRIO_VERY_HIGH },
	LOGSWINCH_WINCH_SPEEDUP_PLAYER = { "WINCH_SPEEDUP", Player.INPUT_CONTEXT_NAME, false, false, true, GS_PRIO_VERY_HIGH },
	LOGSWINCH_WINCH_SPEEDUP_VEHICLE = { "WINCH_SPEEDUP", Vehicle.INPUT_CONTEXT_NAME, false, false, true, GS_PRIO_VERY_HIGH },
	LOGSWINCH_RELEASE_PLAYER = { "RELEASE", Player.INPUT_CONTEXT_NAME, false, true, false, GS_PRIO_VERY_HIGH },
	LOGSWINCH_RELEASE_VEHICLE = { "RELEASE", Vehicle.INPUT_CONTEXT_NAME, false, true, false, GS_PRIO_VERY_HIGH },
	LOGSWINCH_SWITCH_TO_NEXT = { "SWITCH_TO_NEXT", Player.INPUT_CONTEXT_NAME, false, true, false, GS_PRIO_VERY_LOW },
	LOGSWINCH_SWITCH_TRAILER_HOOK = { "SWITCH_TRAILER_HOOK", Player.INPUT_CONTEXT_NAME, false, true, false, GS_PRIO_HIGH }
}

-- "static" variables for deteminating user active winch
LogsWinch.AvailableWinchesCount = 0
LogsWinch.AvailableWinches = {}
LogsWinch.ActiveWinchIdx = nil
LogsWinch.WinchJustSwitched = false
LogsWinch.WinchSwitchTimer = 0
LogsWinch.WinchingTimer = 0
LogsWinch.ClientWinchingTimer = 0
LogsWinch.ControlPlayer = false

function LogsWinch.updateAvailableWinchesCount()
	
	LogsWinch.AvailableWinchesCount = 0
	
	for k,v in pairs(LogsWinch.AvailableWinches) do
		if v ~= nil then
			LogsWinch.AvailableWinchesCount = LogsWinch.AvailableWinchesCount + 1
		end
	end

end

function LogsWinch.prerequisitesPresent(specializations)
	return true
end

function LogsWinch.registerEventListeners(vehicleType)
	local functionNames = {
		"onRegisterActionEvents",
		"onLoad",
		"onLoadFinished",
		"onPreDelete",
		"onPostAttach",
		"onPreDetach",
		"onTurnedOn",
		"onTurnedOff",
		"onUpdate"
	}

	for i, v in ipairs(functionNames) do
		SpecializationUtil.registerEventListener(vehicleType, v, LogsWinch)
	end

	LogsWinch.ModifierType = g_soundManager:registerModifierType("WINCHING_LOAD", LogsWinch.winchingLoadModifierValue, LogsWinch.winchingLoadModifierMin, LogsWinch.winchingLoadModifierMax)

end

function LogsWinch:winchingLoadModifierValue()
	local sample = g_soundManager.activeSamples[g_soundManager.currentSampleIndex]
	if sample ~= nil and sample.modifiers.pitch[LogsWinch.ModifierType] ~= nil then
		return sample.winchingLoad
	end

	return 0.0
end

function LogsWinch:winchingLoadModifierMin()
	return 0.0
end

function LogsWinch:winchingLoadModifierMax()
	return 2.0
end

function LogsWinch:onRegisterActionEvents(isActiveForInput)

	-- print(string.format(" Register action events: %s -> active for input: %s", LogsWinch.AvailableWinches[self.lwWinchIdx][2], isActiveForInput))

	if self.isClient then

		if self.lwActionEventIds ~= nil then
			for _, eventId in pairs(self.lwActionEventIds) do
				g_inputBinding:removeActionEvent(eventId)
			end
		end

		self.lwActionEventIds = {}
		self.lwTriggeredActions = {}

		-- do not register events if winch is not active
		if LogsWinch.ActiveWinchIdx ~= self.lwWinchIdx then
			return
		end

		for actionName, actionDetails in pairs(LogsWinch.Actions) do
			local internalActionName = actionDetails[1]
			local contextName = actionDetails[2]
			local triggerUp = actionDetails[3]
			local triggerDown = actionDetails[4]
			local triggerAlways = actionDetails[5]
			local priority = actionDetails[6]

			local isPlayerActionRegisterable = (not isActiveForInput and contextName == Player.INPUT_CONTEXT_NAME)
			local isVehicleActionRegisterable = (isActiveForInput and contextName == Vehicle.INPUT_CONTEXT_NAME)
			if isVehicleActionRegisterable or isPlayerActionRegisterable then
				-- print(string.format(" Registering action: %s ...", actionName))
				g_inputBinding:beginActionEventsModification(contextName)

				local colliding = false
				_, colliding, _ = g_inputBinding:checkEventCollision(actionName)
				if colliding then
					print(string.format("Error: LogsWinch got a colliding action: %s", actionName))
				end

				local actionEventId = ""
				_, actionEventId = g_inputBinding:registerActionEvent(actionName, self, LogsWinch.actionEventCallback, triggerUp, triggerDown, triggerAlways, false)
				g_inputBinding:setActionEventText(actionEventId, g_i18n:getText(string.format("action_%s", actionName)))
				g_inputBinding:setActionEventTextPriority(actionEventId, priority)
				g_inputBinding:setActionEventTextVisibility(actionEventId, true)

				self.lwActionEventIds[actionName] = actionEventId
				self.lwTriggeredActions[internalActionName] = false

				g_inputBinding:endActionEventsModification()
			end
		end

	end
end

function LogsWinch.actionEventCallback(self, actionName, inputValue, callbackState)

	-- print(" LogsWinch action callback: ", actionName, inputValue, callbackState)

	local isTriggered = (inputValue > 0)
	self.lwTriggeredActions[LogsWinch.Actions[actionName][1]] = isTriggered
end

function LogsWinch:onLoad(savegame)

	self.getPtoRpm 						= Utils.overwrittenFunction(self.getPtoRpm, LogsWinch.getPtoRpm)
	self.onRegisterActionEvents			= LogsWinch.onRegisterActionEvents

	self.lwSwitchToNextWinch			= LogsWinch.lwSwitchToNextWinch
	self.lwDrawActiveWinchInfo			= LogsWinch.lwDrawActiveWinchInfo
	self.lwDrawHelpButtons				= LogsWinch.lwDrawHelpButtons
	self.lwGetAttachedShapeIdx  		= LogsWinch.lwGetAttachedShapeIdx
	
	self.lwAttachDetachObject			= LogsWinch.lwAttachDetachObject
	self.lwAttachRaycastCallback		= LogsWinch.lwAttachRaycastCallback
	self.lwDetachRaycastCallback		= LogsWinch.lwDetachRaycastCallback

	self.lwAttachObject 				= LogsWinch.lwAttachObject
	self.lwCreateChainAroundObject		= LogsWinch.lwCreateChainAroundObject
	self.lwChainInterstRaycastCallback	= LogsWinch.lwChainInterstRaycastCallback
	self.lwDetachObject 				= LogsWinch.lwDetachObject
	
	self.lwWinch 						= LogsWinch.lwWinch
	self.lwRelease 						= LogsWinch.lwRelease
	
	self.lwUpdateJointFrame 			= LogsWinch.lwUpdateJointFrame
	self.lwUpdateRope					= LogsWinch.lwUpdateRope
	self.lwUpdateChain					= LogsWinch.lwUpdateChain

	
	-- active winch indexing
	self.lwWinchIdx = #LogsWinch.AvailableWinches + 1
	
	local _, name = LogsWinch:lwGetVehicleBrandAndName(self)
	if string.len(name) > 20 then
		name = name:sub(0, 20) .. ".."
	end
	local frmtStr = g_i18n:getText("info_activeWinchDetached")
	LogsWinch.AvailableWinches[self.lwWinchIdx] = { self, string.format(frmtStr, self.lwWinchIdx, name)}
	LogsWinch.updateAvailableWinchesCount()

	if LogsWinch.ActiveWinchIdx == nil then
		LogsWinch.ActiveWinchIdx = self.lwWinchIdx
	end


	local key = "vehicle.logsWinch"

	self.lwInitialized = false
	self.lwIsWinching = false
	self.lwComponentIndex = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#componentIndex"), 1)
	self.lwJointRefNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, key .. "#jointRefNode"))
	self.lwRopeRefNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, key .. "#ropeRefNode"))
	self.lwRopeShape = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, key .. "#ropeMesh"))
	self.lwRopeEndShape = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, key .. "#ropeEndMesh"))
	self.lwRopeEndShapeLen = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#ropeEndMeshLength"), 0.0)
	self.lwChainNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, key .. "#chainMesh"))
	self.lwPulleyNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, key .. "#pulleyMesh"))
	self.lwSpeed = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#winchingSpeed"), 0.01)
	self.lwSpeedup = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#winchingSpeedup"), 2)
	self.lwWinchPtoRpm = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#winchingPtoRpm"), 340)
	self.lwSpeedupWinchPtoRpm = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#speedupWinchingPtoRpm"), 540)
	self.lwRopeLength = MathUtil.clamp(Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#ropeLength"), 50), 5, 100)
	self.lwMaxChainLength = MathUtil.clamp(Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#maxChainLength"), 5), 0.5, 20)
	self.lwMaxWinchingMass = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#maxWinchingMass"), 4)

	-- load ropes for UV scrolling
	local ropesUVScrollKey = key .. ".ropesUVScroll"

	self.lwUVScrollRopes = {}
	local i=1
	while true do
		local ropeKey = string.format(ropesUVScrollKey .. ".rope%d", i)
		
		if not hasXMLProperty(self.xmlFile, ropeKey) then
			break
		end

		local ropeNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, ropeKey .. "#index"))
		if ropeNode ~= nil then
			table.insert(self.lwUVScrollRopes, ropeNode)
		end

		i = i + 1
	end

	-- load skinned rope
	local skinnedRopeKey = key .. ".skinnedRope"

	self.lwSkinnedRopeBias = Utils.getNoNil(getXMLFloat(self.xmlFile, skinnedRopeKey .. "#ropeBias"), 0.02)
	self.lwSkinnedRopeJointsParent = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, skinnedRopeKey .. "#jointsParentNode"))
	self.lwSkinnedRopeJoints = {}
	if self.lwSkinnedRopeJointsParent ~= nil and hasXMLProperty(self.xmlFile, skinnedRopeKey .. "#jointsCount") then
		local jointsCount = getXMLInt(self.xmlFile, skinnedRopeKey .. "#jointsCount") + 1

		for i=1,jointsCount,1 do
			self.lwSkinnedRopeJoints[i] = getChildAt(self.lwSkinnedRopeJointsParent, i-1)
		end
	end

	-- load dynamic chain I3D
	local dynamicChainKey = key .. ".dynamicChain"
	
	self.lwDynamicChainFilename = getXMLString(self.xmlFile, dynamicChainKey .. "#i3dFilename")
	self.lwDynamicChainI3DRoot = nil
	self.lwDynamicChainMaterialNode = nil
	self.lwDynamicChainHook = nil
	self.lwDynamicChainHookSize = 0
	if self.lwDynamicChainFilename ~= nil then
		self.lwDynamicChainI3DRoot = g_i3DManager:loadSharedI3DFile(self.lwDynamicChainFilename, LogsWinch.ModDirectory, false, false)
		self.lwDynamicChainMaterialNode = I3DUtil.indexToObject(self.lwDynamicChainI3DRoot, getXMLString(self.xmlFile, dynamicChainKey .. "#materialHolderNode"))
		self.lwDynamicChainHook = I3DUtil.indexToObject(self.lwDynamicChainI3DRoot, getXMLString(self.xmlFile, dynamicChainKey .. "#hookNode"))
		self.lwDynamicChainWidth = Utils.getNoNil(getXMLFloat(self.xmlFile, dynamicChainKey .. "#chainWidth"), 0.05)
		if self.lwDynamicChainHook ~= nil then
			local _, _, size = getTranslation(getChildAt(self.lwDynamicChainHook, 0))
			self.lwDynamicChainHookSize = size
		end
	end
	
	-- load main sound
	local soundKey = key .. ".sounds"
	self.lwSoundSample = g_soundManager:loadSampleFromXML(self.xmlFile, soundKey, "winching", self.baseDirectory, self.components[self.lwComponentIndex].node, 1, AudioGroup.VEHICLE, nil, self)
	self.lwSoundSample.winchingLoad = 0

	-- load chain attach sound
	self.lwChainAttachSndSample = g_soundManager:loadSampleFromXML(self.xmlFile, soundKey, "chainAttach", self.baseDirectory, self.components[self.lwComponentIndex].node, 1, AudioGroup.VEHICLE, nil, self)
	
	-- load chain detach sound
	self.lwChainDetachSndSample = g_soundManager:loadSampleFromXML(self.xmlFile, soundKey, "chainDetach", self.baseDirectory, self.components[self.lwComponentIndex].node, 1, AudioGroup.VEHICLE, nil, self)
	
	-- load overriden input attacher info
	local attacherKey = key .. ".overridenInputAttacher"
	self.lwAttachJointLowerRotOffset = getXMLFloat(self.xmlFile, attacherKey .. "#lowerRotationOffset")
	self.lwAttachJointUpperRotOffset = getXMLFloat(self.xmlFile, attacherKey .. "#upperRotationOffset")
	self.lwAttachJointRotSaturation = Utils.getNoNil(getXMLFloat(self.xmlFile, attacherKey .. "#rotSaturation"), 1)

	if self.lwAttachJointLowerRotOffset ~= nil then
		self.lwAttachJointLowerRotOffset = math.rad(self.lwAttachJointLowerRotOffset)
	end
	if self.lwAttachJointUpperRotOffset ~= nil then
		self.lwAttachJointUpperRotOffset = math.rad(self.lwAttachJointUpperRotOffset)
	end

	-- load removable trailer hook
	local trailerHookKey = key .. ".removableTrailerHook"
	self.lwTrailerHookNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, trailerHookKey .. "#index"))
	self.lwTrailerHookAnim = getXMLString(self.xmlFile, trailerHookKey .. "#switchAnimation")
	self.lwTrailerHookDistance = Utils.getNoNil(getXMLFloat(self.xmlFile, trailerHookKey .. "#maxSwitchingDistance"), 1)

	-- initialize all needed variables
	-- server only
	self.lwJoints = {}						-- joints references
	self.lwCurrJointZLimit = nil			-- current main joint Z translation limit (we are simulating winch with this)
	self.lwCurrAttachedShapesMass = 0		-- mass of all currently attached shape, for fakce calculation of how much winch can winch
	self.lwCurrPtoRpm = 0
	-- shared
	self.lwAttachedShapes = {}				-- attached objects shapes
	self.lwAttachedShapesRefNodes = {}		-- reference nodes for attached shapes
	-- client only
	self.lwAttachedShapesChainNodes = {}	-- static chain shapes from joint to joint
	self.lwAttachedShapesDynamicChains = {}	-- shapes of dynamic chains wrapped around attached object
	
	self.lwActionEventIds = {}
	self.lwTriggeredActions = {}

	-- mark as initialized if mandatory things are found
	if self.lwJointRefNode ~= nil then
		self.lwInitialized = true
	else
		print("Error: LogsWinch initialization failed!")
		return
	end
	
end

function LogsWinch:onLoadFinished(savegame)

	-- reset rope mesh
	self:lwUpdateRope(0, true)

	-- reset chain mesh
	if self.lwChainNode ~= nil then
		setVisibility(self.lwChainNode, false)
	end

end

function LogsWinch:onPreDelete()

	-- first make sure everything is detached
	lwDetachAllEvent.sendEvent(self)

	-- now stop all the sounds & delete samples
	g_soundManager:stopSample(self.lwSoundSample, true)
	g_soundManager:stopSample(self.lwChainAttachSndSample)
	g_soundManager:stopSample(self.lwChainDetachSndSample)

	g_soundManager:deleteSample(self.lwChainAttachSndSample)
	g_soundManager:deleteSample(self.lwChainDetachSndSample)
	g_soundManager:deleteSample(self.lwSoundSample)

	-- remove current winch from available winches, so it won't appear in active list anymore
	LogsWinch.AvailableWinches[self.lwWinchIdx] = nil
	LogsWinch.updateAvailableWinchesCount()

	-- if this winch was current active for player, then set first available as current
	if LogsWinch.ActiveWinchIdx == self.lwWinchIdx then
		for k,v in pairs(LogsWinch.AvailableWinches) do
			if v ~= nil then
				winchSpec, _ = unpack(v)
				LogsWinch.ActiveWinchIdx = k
				winchSpec:requestActionEventUpdate()
				break
			end
		end
	end

	-- release dynamic chain i3d file
	if self.lwDynamicChainFilename ~= nil then 
		g_i3DManager:releaseSharedI3DFile(self.lwDynamicChainFilename, nil, true)
	end

end

function LogsWinch:onPostAttach(attacherVehicle, jointDescIndex)
	
	local _, name = LogsWinch:lwGetVehicleBrandAndName(self)
	local brand1, name1 = LogsWinch:lwGetVehicleBrandAndName(attacherVehicle)

	if string.len(name) > 10 then
		name = name:sub(0, 10) .. ".."
	end

	local attacherStr = string.format("%s %s", brand1, name1)
	if string.len(attacherStr) > 25 then
		attacherStr = attacherStr:sub(0, 25) .. ".."
	end

	local frmtStr = g_i18n:getText("info_activeWinchAttached")
	LogsWinch.AvailableWinches[self.lwWinchIdx] = {self, string.format(frmtStr, self.lwWinchIdx, name, attacherStr)}

end

function LogsWinch:onPreDetach(attacherVehicle, jointDescIndex)
	
	local _, name = LogsWinch:lwGetVehicleBrandAndName(self)
	
	if string.len(name) > 20 then
		name = name:sub(0, 20) .. ".."
	end

	local frmtStr = g_i18n:getText("info_activeWinchDetached")
	LogsWinch.AvailableWinches[self.lwWinchIdx] = {self, string.format(frmtStr, self.lwWinchIdx, name)}

end

function LogsWinch:onTurnedOn(noEventSend)
end

function LogsWinch:onTurnedOff(noEventSend)
	-- make sure to stop sound when switched off
	g_soundManager:stopSample(self.lwSoundSample, true)
end

function LogsWinch:getPtoRpm(superFunc)
	if self:getDoConsumePtoPower() then
		return self.lwCurrPtoRpm
	end

	return 0
end

function LogsWinch:onUpdate(dt)

	if not self.lwInitialized then
		return
	end

	local availableRopeOrChain = 0
	if #self.lwAttachedShapesRefNodes <= 0 then
		availableRopeOrChain = math.max(0, self.lwRopeLength - LogsWinch:lwGetPlayerDistanceTo(self.rootNode))
	else
		if self.lwAttachedShapesRefNodes[1] ~= nil and entityExists(self.lwAttachedShapesRefNodes[1]) then
			availableRopeOrChain = math.max(0, self.lwMaxChainLength - LogsWinch:lwGetPlayerDistanceTo(self.lwAttachedShapesRefNodes[1]))
		end
	end

	local isActiveForInput = self:getIsActiveForInput(true)
	local canOperateWinch = LogsWinch:lwGetPlayerDistanceTo(self.rootNode) < self.lwRopeLength or isActiveForInput

	-- update winch switching timer
	LogsWinch.WinchSwitchTimer = math.max(LogsWinch.WinchSwitchTimer - dt, 0)
	LogsWinch.WinchingTimer = math.max(LogsWinch.WinchingTimer - dt, 0)
	LogsWinch.ClientWinchingTimer = math.max(LogsWinch.ClientWinchingTimer - dt, 0)
	
	-- update winching sound samples
	if self:getIsTurnedOn() then

		-- if turned on not active on input motor rpm won't be updated!
		-- That's why force it by calling update on motor rpm
		--[[
		if self.attacherVehicle ~= nil and self.attacherVehicle.motor ~= nil then
			if not isActiveForInput or self.attacherVehicle:getLastSpeed() < 2 then
				self.attacherVehicle.motor:update(dt)
			end
		end
		]]
		
		-- if not winching anymore put pto back to normal
		if LogsWinch.ClientWinchingTimer <= 0 then
			self.lwCurrPtoRpm = self.spec_powerConsumer.ptoRpm
		end

		-- update sound modifiers depending on current pto rpm
		self.lwSoundSample.winchingLoad = (self:getPtoRpm() - self.spec_powerConsumer.ptoRpm) / (self.lwSpeedupWinchPtoRpm - self.spec_powerConsumer.ptoRpm)

		if not g_soundManager:getIsSamplePlaying(self.lwSoundSample) then
			g_soundManager:playSample(self.lwSoundSample, 0)
		end
	end

	-- update joint frames, ropes, chains and possible object detaching if entity vanishes for some reason
	if #self.lwAttachedShapesRefNodes > 0 then

		for i=1, #self.lwAttachedShapesRefNodes, 1 do

			if self.lwAttachedShapesRefNodes[i] ~= nil then

				if entityExists(self.lwAttachedShapesRefNodes[i]) then

					local jointRefNode = self.lwJointRefNode
					if i ~= 1 then
						jointRefNode = self.lwAttachedShapesRefNodes[1]
					end

					-- update rotations of joint
					local asX, asY, asZ = getWorldTranslation(self.lwAttachedShapesRefNodes[i])
					local jrX, jrY, jrZ = getWorldTranslation(jointRefNode)
					
					self:lwUpdateJointFrame(self.lwJoints[i], jointRefNode, {jrX, jrY, jrZ}, {asX, asY, asZ}, i == 1)

					if not (g_currentMission.connectedToDedicatedServer and self.isServer) then

						-- update rope only on main joint, otherwise update chain
						if i == 1 then
							jrX, jrY, jrZ = getWorldTranslation(self.lwSkinnedRopeJointsParent)
							self:lwUpdateRope(MathUtil.vector3Length(asX - jrX, asY - jrY, asZ - jrZ))
						else
							self:lwUpdateChain(i)
						end

					end

				else

					self:lwDetachObject(self.lwAttachedShapes[i])
				
				end

			end
		end
	end

	-- make sure to switch to current winch if player enters vehicle
	if isActiveForInput and LogsWinch.ActiveWinchIdx ~= self.lwWinchIdx then
		LogsWinch.ActiveWinchIdx = self.lwWinchIdx
		-- register actions in case user was on foot before where vehicle actions were not registered
		self:onRegisterActionEvents(isActiveForInput)
	end

	local isThisActiveWinch = (self.lwWinchIdx == LogsWinch.ActiveWinchIdx)

	-- keep currently active whinch alive all the time, 
	-- otherwise inputs for it will be unregistered and player won't be able to operate it anymore
	if isThisActiveWinch and not self:getRootVehicle():getIsActive() then
		self:raiseActive()

		-- everytime player controlling state changes make sure to register action events,
		-- otherwise player will loose input binding when entering vehicle without a winch.
		if g_currentMission.controlPlayer ~= LogsWinch.ControlPlayer then
			self:onRegisterActionEvents(isActiveForInput)
			LogsWinch.ControlPlayer = g_currentMission.controlPlayer
		end
	end

	-- ignore ALL input if this is not active winch or player is frozen or GUI is visible
	if (not isThisActiveWinch) or g_currentMission.isPlayerFrozen or g_gui:getIsGuiVisible() then

		-- check out end of the onUpdate for more informations on triggered actions
		self.lwTriggeredActions = {}
		return
	end

	-- active winch actions only
	if isThisActiveWinch then

		-- handle winch switching
		if self.lwTriggeredActions["SWITCH_TO_NEXT"] then
			self:lwSwitchToNextWinch(isActiveForInput)
		end

		-- draw button for switching between winches
		self:lwDrawActiveWinchInfo()
	end

	-- handle trailer hook switching
	if LogsWinch:lwGetPlayerDistanceTo(self.lwTrailerHookNode) <= self.lwTrailerHookDistance and self.lwTriggeredActions["SWITCH_TRAILER_HOOK"] then
		if self.lwTrailerHookAnim ~= nil then
			
			-- when moving hook make sure to detach all implements before that
			while #self:getAttachedImplements() > 0 do
				self:detachImplement(#self:getAttachedImplements())
			end

			local animTime = self:getAnimationTime(self.lwTrailerHookAnim)
			if animTime == 1 then
				self:playAnimation(self.lwTrailerHookAnim, -1, animTime)
			else
				self:playAnimation(self.lwTrailerHookAnim, 1, animTime)
			end
		end
	end

	-- handle all operational inputs
	if canOperateWinch then

		-- handle winching
		if self:getIsTurnedOn() then
			
			-- handle winching
			if self.lwTriggeredActions["WINCH_SPEEDUP"] then
				lwWinchEvent.sendEvent(self, true, g_currentMission.playerUserId)
			elseif self.lwTriggeredActions["WINCH"] then
				lwWinchEvent.sendEvent(self, false, g_currentMission.playerUserId)
			end

		else

			if self.lwTriggeredActions["WINCH_SPEEDUP"] or self.lwTriggeredActions["WINCH"] then
				g_currentMission:showBlinkingWarning(g_i18n:getText("warning_turnOnLoggingWinch"), 2000)
			end

		end

		-- handle release of the winch
		if self.lwTriggeredActions["RELEASE"] then
			lwReleaseEvent.sendEvent(self)
		end

		-- handle detaching/attaching
		if g_currentMission.player.isObjectInRange then
		
			if self.lwTriggeredActions["ATTACH_DETACH"] and availableRopeOrChain > 0 then
				lwAttachDetachEvent.sendEvent(self, g_currentMission.player)
			end

		end

		-- handle detaching all if inside tractor and operating winch
		if isActiveForInput and self.lwTriggeredActions["DETACH_ALL"] then
			lwDetachAllEvent.sendEvent(self)
		end

		-- as last draw helping buttons, if player can operate winch
		self:lwDrawHelpButtons(isActiveForInput, availableRopeOrChain)
	end

	-- each update reset triggered actions, 
	-- if triggered again they will be set via input action event callback
	self.lwTriggeredActions = {}
end

function LogsWinch:lwGetVehicleBrandAndName(vehicle)

	if vehicle.isDeleted or not vehicle.isVehicleSaved or vehicle.nonTabbable then
        return "-", "-"
    end
    
    local name = "-"
    local brand = "-"
    local storeItem = g_storeManager.xmlFilenameToItem[vehicle.configFileName:lower()]
    
    if storeItem ~= nil then
        if storeItem.name ~= nil then
            name = tostring(storeItem.name)
        end
        if storeItem.brandIndex ~= nil then
        	local brandItem = g_brandManager:getBrandByIndex(storeItem.brandIndex)
        	if brandItem ~= nil then
            	brand = tostring(brandItem.name)
        	end
        end
	end

	return brand, name
end

function LogsWinch:lwSwitchToNextWinch(isActiveForInput)

	--print(string.format("Switched from: %s", LogsWinch.AvailableWinches[LogsWinch.ActiveWinchIdx][2]))

	-- abort multiple switcing at once
	if LogsWinch.WinchSwitchTimer > 0 then
		return
	end

	LogsWinch.WinchSwitchTimer = 500

	if isActiveForInput then
		return
	end

	local currentFound = false
	local firstKey = nil
	local newKey = nil
	for k,_ in pairs(LogsWinch.AvailableWinches) do
		if firstKey == nil then
			firstKey = k
		end

		if currentFound then
			newKey = k
			break
		end

		if k == LogsWinch.ActiveWinchIdx then
			currentFound = true
		end
	end

	if newKey == nil then
		newKey = firstKey
	end

	LogsWinch.ActiveWinchIdx = newKey
	LogsWinch.WinchJustSwitched = true

	local winchSpec, winchInfo = unpack(LogsWinch.AvailableWinches[LogsWinch.ActiveWinchIdx])
	local message = string.format(g_i18n:getText("info_activeWinchNotification"), winchInfo)
	g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, message)

	self:onRegisterActionEvents()
	
	winchSpec:raiseActive()
	winchSpec:onRegisterActionEvents()

	--print(string.format("Switched to: %s", winchInfo))
end

function LogsWinch:lwGetPlayerDistanceTo(node)
	
	local x, y, z = getWorldTranslation(g_currentMission.player.pickUpKinematicHelperNode)
	local x1, y1, z1 = getWorldTranslation(node)

	return MathUtil.vector3Length(x - x1, y - y1, z - z1)

end

function LogsWinch:lwDrawHelpButtons(isActiveForInput, availableRopeOrChain)

	if self.isClient then
	
		local canAttachDetach = (g_currentMission.player.isObjectInRange and availableRopeOrChain > 0)
		if canAttachDetach then
			g_inputBinding:setActionEventText(self.lwActionEventIds["LOGSWINCH_ATTACH_DETACH"], g_i18n:getText(string.format("action_%s", "LOGSWINCH_ATTACH_DETACH")))
		end
		g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_ATTACH_DETACH"], canAttachDetach)
		
		if not isActiveForInput then
			if #self.lwAttachedShapesRefNodes <= 0 then
				g_currentMission:addExtraPrintText(string.format(g_i18n:getText("info_availableWinchRope"), availableRopeOrChain))
			else
				g_currentMission:addExtraPrintText(string.format(g_i18n:getText("info_availableWinchChain"), availableRopeOrChain))			
			end
		end
		g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_DETACH_ALL"], isActiveForInput)

		local isAnyShapeAttached = (#self.lwAttachedShapes > 0)
		g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_WINCH_PLAYER"], isAnyShapeAttached)
		g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_WINCH_VEHICLE"], isAnyShapeAttached)
		g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_WINCH_SPEEDUP_PLAYER"], isAnyShapeAttached)
		g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_WINCH_SPEEDUP_VEHICLE"], isAnyShapeAttached)
		g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_RELEASE_PLAYER"], isAnyShapeAttached)
		g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_RELEASE_VEHICLE"], isAnyShapeAttached)

		local canSwitchTrailerHook = (self.lwTrailerHookNode ~= nil and LogsWinch:lwGetPlayerDistanceTo(self.lwTrailerHookNode) <= self.lwTrailerHookDistance)
		g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_SWITCH_TRAILER_HOOK"], canSwitchTrailerHook)

	end

end

function LogsWinch:lwDrawActiveWinchInfo()

	if self.isClient then
		local canSetActive = (LogsWinch.AvailableWinchesCount > 1)
		if canSetActive then			
			g_currentMission:addExtraPrintText(string.format(g_i18n:getText("info_activeWinch"), LogsWinch.AvailableWinches[LogsWinch.ActiveWinchIdx][2]))
		end
		if self.lwActionEventIds ~= nil then
			g_inputBinding:setActionEventActive(self.lwActionEventIds["LOGSWINCH_SWITCH_TO_NEXT"], canSetActive)
		end
	end
end

function LogsWinch:lwGetAttachedShapeIdx(shape)

	local idx = -1

	-- search for given shape in allready attached shapes	
	for k, v in pairs(self.lwAttachedShapes) do
		if v == shape then
			idx = k
			break
		end
	end

	return idx
end

function LogsWinch:lwAttachDetachObject(x, y, z, x1, y1, z1, isDetach)

	if x == nil or y == nil or z == nil or x1 == nil or y1 == nil or z1 == nil then
		print("LOGSWINCH: Error: Invalid input paramters one of them is nil")
		return
	end

	local dx = x - x1
	local dy = y - y1
	local dz = z - z1
	local length = MathUtil.vector3Length(dx, dy, dz)

	-- depedning on input argument decide which callback we have to use for raycasting
	local callback = "lwAttachRaycastCallback"
	local requiredDiff = 1
	if isDetach then
		callback = "lwDetachRaycastCallback"
		requiredDiff = -1
	end

	local allreadyAttachedCount = #self.lwAttachedShapes

	raycastClosest(x1, y1, z1, dx / length, dy / length, dz / length, callback, 4, self, 0x1000000)
	
	-- in case raycast from camera node did not succed just send another one from kinematic helpr
	if #self.lwAttachedShapes - allreadyAttachedCount ~= requiredDiff then
		raycastClosest(x, y, z, dx / length, dy / length, dz / length, callback, 3, self, 0x1000000)
	end

	--[[
	if #self.lwAttachedShapes - allreadyAttachedCount ~= requiredDiff then
		if isDetach then
			print("LOGSWINCH: Detach raycasting did not find any objects!")
		else
			print("LOGSWINCH: Attach raycasting did not find any objects!")
		end
	end
	]]
		
	if isDetach and #self.lwAttachedShapes < allreadyAttachedCount then
		return true
	elseif not isDetach and #self.lwAttachedShapes > allreadyAttachedCount then
		return true
	end

	return false

end

function LogsWinch:lwAttachRaycastCallback(shape, x, y, z, distance)
	-- print(string.format("LOGSWINCH: Attach raycast callback (current mass): %s", getMass(shape)))
	if getMass(shape) > 0 then
		self:lwAttachObject(shape, x, y, z, distance)
	end
end

function LogsWinch:lwDetachRaycastCallback(shape, x, y, z, distance)
	-- print(string.format("LOGSWINCH: Detach raycast callback (current mass): %s", getMass(shape)))
	if getMass(shape) > 0 then
		self:lwDetachObject(shape)
	end
end

function LogsWinch:lwAttachObject(shape, apX, apY, apZ, distance)

	-- initial check
	if shape == nil or shape == 0 then
		return
	end

	-- ignore attaching if already attached
	if self:lwGetAttachedShapeIdx(shape) ~= -1 then
		return
	end

	-- TODO: test it! and properly implement it
	--setAngularDamping(shape, 0.75)

	local idx = #self.lwAttachedShapes + 1
	self.lwAttachedShapes[idx] = shape
	self.lwCurrAttachedShapesMass = self.lwCurrAttachedShapesMass + getMass(shape)

	-- create reference node on split shape
	local attachedShapeRefNode = createTransformGroup("lwAttachRef")
	self.lwAttachedShapesRefNodes[idx] = attachedShapeRefNode
	link(shape, attachedShapeRefNode)
	local aplX, aplY, aplZ = worldToLocal(attachedShapeRefNode, apX, apY, apZ)
	setTranslation(attachedShapeRefNode, aplX, aplY, aplZ)

	if self.isServer then

		-- create joint for winching
		local constr = JointConstructor:new()
		if idx == 1 then

			constr:setActors(self.components[self.lwComponentIndex].node, shape)
			constr:setJointTransforms(self.lwJointRefNode, attachedShapeRefNode)

			local jrX, jrY, jrZ = getWorldTranslation(self.lwJointRefNode)
			self.lwCurrJointZLimit = MathUtil.vector3Length(apX - jrX, apY - jrY, apZ - jrZ) + 0.001
			constr:setTranslationLimit(0, true, -LogsWinch.JointMarginLimit, LogsWinch.JointMarginLimit)
			constr:setTranslationLimit(1, true, -LogsWinch.JointMarginLimit, LogsWinch.JointMarginLimit)
			constr:setTranslationLimit(2, true, -self.lwCurrJointZLimit, LogsWinch.JointMarginLimit)
			
			constr:setTranslationLimitSpring(0, 5, 0, 5, 0, 5)
			constr:setEnableCollision(true)

			self.lwJoints[idx] = constr:finalize()

			self:lwUpdateJointFrame(self.lwJoints[idx], self.lwJointRefNode, {jrX, jrY, jrZ}, {apX, apY, apZ}, true)
			
		else

			constr:setActors(self.lwAttachedShapes[1], shape)
			constr:setJointTransforms(self.lwAttachedShapesRefNodes[1], attachedShapeRefNode)

			local jrX, jrY, jrZ = getWorldTranslation(self.lwAttachedShapesRefNodes[1])
			local zLimit = MathUtil.vector3Length(apX - jrX, apY - jrY, apZ - jrZ) + 0.0015
			constr:setTranslationLimit(0, true, -0.1, 0.1)
			constr:setTranslationLimit(1, true, -0.1, 0.1)
			constr:setTranslationLimit(2, true, -zLimit, 0.0015)
			
			constr:setTranslationLimitSpring(0, 5, 0, 5, 0, 5)
			constr:setEnableCollision(true)

			self.lwJoints[idx] = constr:finalize()

			self:lwUpdateJointFrame(self.lwJoints[idx], self.lwAttachedShapesRefNodes[1], {jrX, jrY, jrZ}, {apX, apY, apZ}, false)
		
		end

	end

	if not self.isServer or not g_currentMission.connectedToDedicatedServer then
		
		-- create chain around attached object
		self:lwCreateChainAroundObject(idx, distance)

		if idx == 1 then

			-- if first mesh, then just update main rope
			self:lwUpdateRope()

		else

			-- otherwise create chain mesh
			if self.lwChainNode ~= nil then
				self.lwAttachedShapesChainNodes[idx] = clone(self.lwChainNode, false, false, false)
				link(self.lwAttachedShapesRefNodes[idx], self.lwAttachedShapesChainNodes[idx])

				setVisibility(self.lwAttachedShapesChainNodes[idx], true)

				self:lwUpdateChain(idx)
			end

		end

	end
end

function LogsWinch:lwCreateChainAroundObject(idx, distance)

	local shape = self.lwAttachedShapes[idx]
	local shapeRefNode = self.lwAttachedShapesRefNodes[idx]

	local beltData = g_tensionBeltManager:getBeltData("basic")
	local edgeLength = 0.1
	local geometryBias = 0.005

	-- get chain material
	local materialId = getMaterial(self.lwDynamicChainMaterialNode, 0)
	if materialId == nil or materialId <= 0 then
		materialId = beltData.dummyMaterial.materialId
	end

	local tensionBelt = TensionBeltGeometryConstructor:new()
	tensionBelt:setWidth(self.lwDynamicChainWidth)
	tensionBelt:setMaxEdgeLength(edgeLength)
	tensionBelt:setMaterial(materialId)
	tensionBelt:setUVscale(beltData.dummyMaterial.uvScale)

	-- add hook on the begining of the chain
	if self.lwDynamicChainHook ~= nil then
		tensionBelt:addAttachment(0, 0, self.lwDynamicChainHookSize * self.lwDynamicChainWidth)
	end

	-- create origin node and belt start and end nodes
	local originNode = createTransformGroup("lwChainLinkNode")
	link(shape, originNode)
	
	local startNode = createTransformGroup("lwChainStartNode")
	local endNode = createTransformGroup("lwChainEndNode")
	link(originNode, startNode)
	link(originNode, endNode)

	local x,y,z = getWorldTranslation(shapeRefNode)
	local dxCamera, dyCamera, dzCamera = localDirectionToWorld(g_currentMission.player.cameraNode, 0, 1, 0)
	local dxShape, dyShape, dzShape = localDirectionToWorld(shape, 0, 1, 0)

	-- move origin node a bit closer to camera ( this should help for belt wrapping around object)
	local closeupDiff = 0.05
	local lx, ly, lz = worldToLocal(g_currentMission.player.cameraNode, x, y, z)
	local lx1, ly1, lz1 = localToLocal(g_currentMission.player.cameraNode, shape, lx, ly, lz + closeupDiff)
	setTranslation(originNode, lx1, ly1, lz1)

	-- crazy hack to better visualize chains and not appearing under hooks
	setTranslation(shapeRefNode, lx1, ly1, lz1)

	-- calculate Y-plane direction vector to object center
	local dx = lx1
	local dy = 0
	local dz = lz1
	local length = MathUtil.vector3Length(dx, dy, dz)
	dx = dx / length
	dz = dz / length
	
	-- put it into tangent direction
	setDirection(originNode, dx, dy, dz, 0, 1, 0)
	
	-- properly rotate start and end nodes
	rotateAboutLocalAxis(startNode, 1.57, 0, 1, 0)
	rotateAboutLocalAxis(endNode, 1.57, 0, 1, 0)
	rotateAboutLocalAxis(startNode, -1.57, 0, 0, 1)
	rotateAboutLocalAxis(endNode, -1.57, 0, 0, 1)

	-- offset both for 1cm on each side, so belt will be generated at all
 	setTranslation(startNode, 0.01, 0, 0)
 	setTranslation(endNode, -0.01, 0, 0)
	
	-- finally set fixed points!
	tensionBelt:setFixedPoints(endNode, startNode)
	tensionBelt:setGeometryBias(geometryBias)
	tensionBelt:setLinkNode(shape)
	
	-- initialize temporary data to which callback can write
	self.lwTempIntersectionPoints = {}
	self.lwTempShape = shape

	-- do raycasting around joint to collect all intersection points
	-- (we could use tensionBelt:addShape but it didn't work properly on spruce)
	-- Algorithm simply rotates origin node and raycasts towards itself from different angles
	-- each time it does a rotation on local axis for cca 2.8° up to 90° and then raycasts
	local i = -32
	while i <= 32 do

		i = i + 1

		rotateAboutLocalAxis(originNode, -0.05 * i, 0, 1, 0)

		x, y, z = localToWorld(originNode, 0, 0, -2)
		dirX, dirY, dirZ = localDirectionToWorld(originNode, 0, 0, 1)
		raycastAll(x, y, z, dirX, dirY, dirZ, "lwChainInterstRaycastCallback", 2, self, 0x1000)

		rotateAboutLocalAxis(originNode, 0.05 * i , 0, 1, 0)

	end

	-- after all points are collected finally add intersection points
	dirX, dirY, dirZ = localDirectionToWorld(startNode, 1, 0, 0)
	for k,v in pairs(self.lwTempIntersectionPoints) do
		x, y, z = unpack(v)
		tensionBelt:addIntersectionPoint(x, y, z, dirX, dirY, dirZ)
	end

	-- clear termporary data from raycasting
	for k,v in pairs(self.lwTempIntersectionPoints) do self.lwTempIntersectionPoints[k] = nil end
	self.lwTempIntersectionPoints = nil
	self.lwTempShape = nil

    -- tadaaa create shape!!!
	local beltShape, _, beltLength = tensionBelt:finalize()
	
	-- now finaly add hook mesh
	if self.lwDynamicChainHook ~= nil then
		local hook = clone(self.lwDynamicChainHook, false, false, false)
		link(getChildAt(beltShape, 0), hook)
		setScale(hook, self.lwDynamicChainWidth, self.lwDynamicChainWidth, self.lwDynamicChainWidth)
		
		-- should be on 0 0 0
		setRotation(hook, 0.0, 0, 0)  

		setShaderParameter(beltShape, "beltClipOffsets", 0, self.lwDynamicChainHookSize * self.lwDynamicChainWidth, 1, 0, false)

		-- copy over RDT factors from winch
		local x,y,z,w = getShaderParameter(self.lwRopeShape, "RDT")
		setShaderParameter(hook, "RDT", x, y, z, w)
	end

	-- all creted helper transform groups can now be relased, as geometry of belt is created
	unlink(startNode)
	unlink(endNode)
	unlink(originNode)

	-- print("LOGSWINCH: Belt for chain creted, length: " .. beltLength)
	
	self.lwAttachedShapesDynamicChains[idx] = beltShape

end

function LogsWinch:lwChainInterstRaycastCallback(shape, x, y, z, distance)
	if shape == self.lwTempShape then
		table.insert(self.lwTempIntersectionPoints, {x,y,z})
		return false
	end
	return true
end

function LogsWinch:lwDetachObject(shape)

	local foundShapeIdx = nil
	if shape == nil then
		foundShapeIdx = #self.lwAttachedShapes
	else
		foundShapeIdx = self:lwGetAttachedShapeIdx(shape)
	end

	-- if shape is found finally remove it
	if foundShapeIdx > 0 then

		-- reset mass first
		self.lwCurrAttachedShapesMass = 0

		if foundShapeIdx == 1 then -- if root shape then we have to collapse everything

			for i=#self.lwAttachedShapes,1,-1 do

				if self.isServer then
				
					removeJoint(self.lwJoints[i])
					table.remove(self.lwJoints, i)

				end
				
				if self.lwAttachedShapesRefNodes[i] ~= nil and entityExists(self.lwAttachedShapesRefNodes[i]) then
					unlink(self.lwAttachedShapesRefNodes[i])
				end

				table.remove(self.lwAttachedShapes, i)
				table.remove(self.lwAttachedShapesRefNodes, i)
				
				if not self.isServer or not g_currentMission.connectedToDedicatedServer then
					
					if entityExists(self.lwAttachedShapesDynamicChains[i]) then
						unlink(self.lwAttachedShapesDynamicChains[i])
					end

					table.remove(self.lwAttachedShapesChainNodes, i)
					table.remove(self.lwAttachedShapesDynamicChains, i)
				end

			end

		else -- otherwise just found shape has to be removed

			if self.isServer then
				
				-- first recalculate mass
				for idx,k in pairs(self.lwAttachedShapes) do
					
					-- again check entity, because if detach is invoked directly from update,
					-- this means that entities are disappearing (sold most probably).
					-- So in that case 2 entities can disappear at same time,
					-- but when first entity is detached (this function is called) and
					-- second is also already missing, getMass would spit out errors in log
					if entityExists(k) and idx ~= foundShapeIdx then
						self.lwCurrAttachedShapesMass = self.lwCurrAttachedShapesMass + getMass(k)
					end

				end

				removeJoint(self.lwJoints[foundShapeIdx])
				table.remove(self.lwJoints, foundShapeIdx)

			end
			
			if self.lwAttachedShapesRefNodes[foundShapeIdx] ~= nil and entityExists(self.lwAttachedShapesRefNodes[foundShapeIdx]) then
				unlink(self.lwAttachedShapesRefNodes[foundShapeIdx])
			end

			table.remove(self.lwAttachedShapes, foundShapeIdx)
			table.remove(self.lwAttachedShapesRefNodes, foundShapeIdx)
			
			if not self.isServer or not g_currentMission.connectedToDedicatedServer then
				
				if entityExists(self.lwAttachedShapesDynamicChains[foundShapeIdx]) then
					unlink(self.lwAttachedShapesDynamicChains[foundShapeIdx])
				end

				table.remove(self.lwAttachedShapesChainNodes, foundShapeIdx)
				table.remove(self.lwAttachedShapesDynamicChains, foundShapeIdx)
			end
			
		end

		if not self.isServer or not g_currentMission.connectedToDedicatedServer then
			-- if everything was removed reset joint reference node
			if #self.lwAttachedShapes <= 0 then

				self:lwUpdateRope(0, true)

			end
		end

		return true
	end

	return false
end

function LogsWinch:lwWinch(speedup, userId)

	if LogsWinch.WinchingTimer > 0 then
		return
	end

	-- really small timeout, just to make sure multiple sended events 
	-- are not triggering double speedup of winching
	LogsWinch.WinchingTimer = 10  

	if not self:getIsTurnedOn() or #self.lwAttachedShapesRefNodes <= 0 then
		return
	end

	-- calulate current joint distance and set is as current joint limit just to make sure
	-- that during winching rope is always in uptight state, actual winching is done below
	local asX, asY, asZ = getWorldTranslation(self.lwAttachedShapesRefNodes[1])	
	local jrX, jrY, jrZ = getWorldTranslation(self.lwJointRefNode)
	local currentJointDistance = MathUtil.vector3Length(asX - jrX, asY - jrY, asZ - jrZ)
	if self.lwCurrJointZLimit == nil or self.lwCurrJointZLimit > currentJointDistance + 0.01 then
		self.lwCurrJointZLimit = currentJointDistance + 0.01
	end

	-- "start winching" if mass of attached shapes is small enough
	local isToHeavy = false
	if self.lwCurrAttachedShapesMass < self.lwMaxWinchingMass then
		local diff =  self.lwSpeed
		if speedup ~= nil and speedup == true then
			diff = diff * self.lwSpeedup
		end
		self.lwCurrJointZLimit = MathUtil.clamp(self.lwCurrJointZLimit - diff, LogsWinch.MinJointTransLimit, self.lwCurrJointZLimit)
	else
		isToHeavy = true
	end

	-- only update translation limit if closest possible limit not reached yet
	local isWinching = false
	if self.lwCurrJointZLimit > LogsWinch.MinJointTransLimit then
		setJointTranslationLimit(self.lwJoints[1], 2, true, -self.lwCurrJointZLimit, LogsWinch.JointMarginLimit)
		isWinching = true
	end

	-- post feedback of winching
	lwWinchFeedbackEvent.sendEvent(self, isToHeavy, isWinching, speedup, userId)
end

function LogsWinch:lwRelease()

	if #self.lwJoints > 0 then
		setJointTranslationLimit(self.lwJoints[1], 2, true, -self.lwRopeLength, LogsWinch.JointMarginLimit)
		self.lwCurrJointZLimit = nil
	end

end

function LogsWinch:lwUpdateJointFrame(joint, refNode, jointRefPos, attachPointPos, updatePulleyAndRopeRefNode)

	local jrX, jrY, jrZ = unpack(jointRefPos)
	local apX, apY, apZ = unpack(attachPointPos)

	local dX = jrX - apX
	local dY = jrY - apY
	local dZ = jrZ - apZ
	
	local dlX, dlY, dlZ = worldDirectionToLocal(getParent(refNode), dX, dY, dZ)
	local upX, upY, upZ = worldDirectionToLocal(getParent(refNode), 0, 1, 0)

	setDirection(refNode, dlX, dlY, dlZ, upX, upY, upZ)

	if updatePulleyAndRopeRefNode ~= nil and updatePulleyAndRopeRefNode == true then
		
		if self.lwPulleyNode ~= nil then
			setDirection(self.lwPulleyNode, dlX, 0, dlZ, 0, 1, 0)
		end
		
		-- if rope reference node is given then update it's rotation too so rope will be properly directed
		-- NOTE: this should be the case when user uses pulley & wants to offset rope mesh from joint ref point
		if self.lwRopeRefNode ~= nil then
		
			jrX, jrY, jrZ = getWorldTranslation(self.lwRopeRefNode)

			dX = jrX - apX
			dY = jrY - apY
			dZ = jrZ - apZ
			
			dlX, dlY, dlZ = worldDirectionToLocal(getParent(self.lwRopeRefNode), dX, dY, dZ)
			setDirection(self.lwRopeRefNode, dlX, dlY, dlZ, 0, 1, 0)

		end

	end

	if joint ~= nil then
		setJointFrame(joint, 0, refNode)
	end

end

function LogsWinch:lwUpdateRope(scale, resetRotation)
	
	local jointsCount = #self.lwSkinnedRopeJoints

	if self.lwRopeShape == nil and jointsCount <= 0 then
		return
	end

	-- if no scale is given calculate it
	if scale == nil then

		local x, y, z = getWorldTranslation(self.lwAttachedShapesRefNodes[1])
		local x1, y1, z1 = getWorldTranslation(self.lwJointRefNode)

		scale = MathUtil.vector3Length(x1 - x, y1 - y, z1 - z)

	end

	-- as we got the scale now subtract the size of rope end mesh
	scale = math.max(0.05, scale - self.lwRopeEndShapeLen)

	if jointsCount > 0 then
		
		local transZPerJoint = scale / (jointsCount - 1)
		local wantedYs = {}
		local wantedYsIndices = {}
		
		-- collect world Y positions for all joints
		local anyJointUnderGround = false
		for i=1,jointsCount,1 do

			-- first make sure to reset transfromations so any calculations can be done properly!
			setRotation(self.lwSkinnedRopeJoints[i], 0, 0, 0)
			setTranslation(self.lwSkinnedRopeJoints[i], 0, 0, (i - 1) * transZPerJoint)

			local x,y,z = localToWorld(self.lwSkinnedRopeJoints[1], 0, 0, (i - 1) * transZPerJoint)
			local terrainY = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, y, z)

			if terrainY + self.lwSkinnedRopeBias >= y then
				-- get terrain once again, for better approximation of terrain height for this joint
				terrainY = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, terrainY, z)
				_,y,_ = worldToLocal(self.lwSkinnedRopeJoints[1], x, terrainY + self.lwSkinnedRopeBias, z)

				wantedYs[i] = y
				anyJointUnderGround = true
			else
				wantedYs[i] = 0
			end

			wantedYsIndices[i] = i
		end

		-- remove ones that would give effect of "pulling down" of the rope, 
		-- by naive comparison of middle point between selected two points and
		-- removing it if it's lower that would be straight line from next and prev point
		if anyJointUnderGround then
			local anyPointRemoved = true
			while anyPointRemoved do
				
				anyPointRemoved = false

				-- until any points are removed we have run algorithm again
				local i = 3
				while i <= #wantedYs do
					local prevY = wantedYs[i-2]
					local prevIdx = wantedYsIndices[i-2]
					local nextY = wantedYs[i]
					local nextIdx = wantedYsIndices[i]
					local currY = wantedYs[i-1]
					local currIdx = wantedYsIndices[i-1]

					-- if predicted height for current point is lower then it would be,
					-- on straight line from previous to next point, then remove current point
					-- otherwise move to next point
					if prevY + (nextY - prevY) * ((currIdx - prevIdx) / (nextIdx - prevIdx)) > currY then
						table.remove(wantedYs, i-1)
						table.remove(wantedYsIndices, i-1)
						anyPointRemoved = true
					else
						i = i + 1
					end
				end
			end
		end

		-- set new translations to all joints
		local prevHighestIdx = wantedYsIndices[1]
		table.remove(wantedYsIndices, 1)
		local nextHighestIdx = wantedYsIndices[1]
		table.remove(wantedYsIndices, 1)
		for i=1,jointsCount,1 do

			local currY = 0
			if i == prevHighestIdx then
				currY = wantedYs[1]
			elseif i < nextHighestIdx then
				currY = (wantedYs[2] - wantedYs[1]) * ((i - prevHighestIdx) / (nextHighestIdx - prevHighestIdx)) + wantedYs[1]
			elseif i == jointsCount then
				currY = 0  -- last joint has to be on zero always, to be sticked to shape reference node even if underground
			else
				currY = wantedYs[2]
				
				prevHighestIdx = nextHighestIdx
				nextHighestIdx = wantedYsIndices[1]
				table.remove(wantedYsIndices, 1)
				table.remove(wantedYs, 1)
			end

			local currZ = (i - 1) * transZPerJoint
			setTranslation(self.lwSkinnedRopeJoints[i], 0, currY, currZ)
		end

		-- interpolate angles to new curvature only if one of joints was under ground
		if anyJointUnderGround then
			for i=2,jointsCount-1,1 do

				local prevX, prevY, prevZ = getTranslation(self.lwSkinnedRopeJoints[i - 1])
				local currX, currY, currZ = getTranslation(self.lwSkinnedRopeJoints[i])
				local nextX, nextY, nextZ = getTranslation(self.lwSkinnedRopeJoints[i + 1])

				local angle = -math.atan2((currY - prevY), (currZ - prevZ))
				local angle2 = -math.atan2((nextY - currY), (nextZ - currZ))
				
				setRotation(self.lwSkinnedRopeJoints[i], (angle + angle2) / 2, 0, 0)

				if i == 2 then
					setRotation(self.lwSkinnedRopeJoints[i-1], angle, 0, 0)
				elseif i == jointsCount - 1 then
					
					-- now compensate height for end rope mesh, 
					-- which will be after applying the rotation displaced
					local diffY = math.tan(angle2) * self.lwRopeEndShapeLen
					setTranslation(self.lwSkinnedRopeJoints[i + 1], nextX, nextY + diffY, nextZ)
					setRotation(self.lwSkinnedRopeJoints[i + 1], angle2, 0, 0)
					
					-- propagate change down the joints until there is any joint that's higher than last one
					local ii = i
					local x, y, z = getTranslation(self.lwSkinnedRopeJoints[ii])
					local currDiffY = diffY * (ii / jointsCount)  -- slowly fade out the difference
					while y > nextY + currDiffY and ii > 1 do
						setTranslation(self.lwSkinnedRopeJoints[ii], x, y + currDiffY, z)
						ii = ii - 1
						currDiffY = diffY * (ii / jointsCount)
						x, y, z = getTranslation(self.lwSkinnedRopeJoints[ii])
					end
				end
			end
		end
	end

	if self.lwRopeShape ~= nil then

		if jointsCount <= 0 then

			local sX, sY, _ = getScale(self.lwRopeShape)
			setScale(self.lwRopeShape, sX, sY, scale)

			if resetRotation ~= nil and resetRotation == true then
				setRotation(self.lwRopeShape, 0, 0, 0)
			end

		end

		local x,_,z,w = getShaderParameter(self.lwRopeShape, "uvScale")
		setShaderParameter(self.lwRopeShape, "uvScale", x, scale, z, w, false)

		for i=1,#self.lwUVScrollRopes,1 do

			x,_,z,w = getShaderParameter(self.lwUVScrollRopes[i], "offsetUV")
			setShaderParameter(self.lwUVScrollRopes[i], "offsetUV", x, (scale * 4) % 1, z, w, false)

		end

	end

	if resetRotation ~= nil and resetRotation == true and self.lwRopeRefNode then

		local jrX, jrY, jrZ = getTranslation(self.lwRopeRefNode)

		local dlX = jrX + 0
		local dlY = jrY + 0.6
		local dlZ = jrZ + 0.4
		
		setDirection(self.lwRopeRefNode, dlX, dlY, dlZ, 0, 1, 0)

	end
end

function LogsWinch:lwUpdateChain(idx)

	if self.lwAttachedShapesChainNodes[idx] == nil then
		return
	end

	local jrX, jrY, jrZ = getWorldTranslation(self.lwAttachedShapesRefNodes[1])
	local asX, asY, asZ = getWorldTranslation(self.lwAttachedShapesChainNodes[idx])

	local dX = jrX - asX
	local dY = jrY - asY
	local dZ = jrZ - asZ
	local scale = MathUtil.vector3Length(dX, dY, dZ)

	local dlX, dlY, dlZ = worldDirectionToLocal(getParent(self.lwAttachedShapesChainNodes[idx]), dX, dY, dZ)
	local upX, upY, upZ = worldDirectionToLocal(getParent(self.lwAttachedShapesChainNodes[idx]), 0, 1, 0)

	setDirection(self.lwAttachedShapesChainNodes[idx], dlX, dlY, dlZ, upX, upY, upZ)

	local sX, sY, _ = getScale(self.lwAttachedShapesChainNodes[idx])
	setScale(self.lwAttachedShapesChainNodes[idx], sX, sY, scale)

	local x,_,z,w = getShaderParameter(self.lwAttachedShapesChainNodes[idx], "uvScale")
	setShaderParameter(self.lwAttachedShapesChainNodes[idx], "uvScale", x, scale, z, w, false)

end


--
-- MP ready
--

lwAttachDetachEvent = {}
lwAttachDetachEvent_mt = Class(lwAttachDetachEvent, Event)

InitEventClass(lwAttachDetachEvent, "lwAttachDetachEvent")

function lwAttachDetachEvent:emptyNew()
    local self = Event:new(lwAttachDetachEvent_mt)
    return self
end

function lwAttachDetachEvent:new(object, x, y, z, x1, y1, z1, isDetach)
    local self = lwAttachDetachEvent:emptyNew()
    self.object = object
	self.x = x
	self.y = y
	self.z = z
	self.x1 = x1
	self.y1 = y1
	self.z1 = z1
	self.isDetach = isDetach
    return self
end

function lwAttachDetachEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
	self.x = streamReadFloat32(streamId)
	self.y = streamReadFloat32(streamId)
	self.z = streamReadFloat32(streamId)
	self.x1 = streamReadFloat32(streamId)
	self.y1 = streamReadFloat32(streamId)
	self.z1 = streamReadFloat32(streamId)
	self.isDetach = streamReadBool(streamId)
	self:run(connection)
end

function lwAttachDetachEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.object)
	streamWriteFloat32(streamId, self.x)
	streamWriteFloat32(streamId, self.y)
	streamWriteFloat32(streamId, self.z)
	streamWriteFloat32(streamId, self.x1)
	streamWriteFloat32(streamId, self.y1)
	streamWriteFloat32(streamId, self.z1)
	streamWriteBool(streamId, self.isDetach)
end

function lwAttachDetachEvent:run(connection)
	
	if not connection:getIsServer() then
        g_server:broadcastEvent(lwAttachDetachEvent:new(self.object, self.x, self.y, self.z, self.x1, self.y1, self.z1, self.isDetach), nil, connection, self.object)
	end

	if self.object ~= nil then
		self.object:lwAttachDetachObject(self.x, self.y, self.z, self.x1, self.y1, self.z1, self.isDetach)
	end
end

function lwAttachDetachEvent.sendEvent(vehicle, player, noEventSend)

	local x,y,z = getWorldTranslation(player.pickUpKinematicHelperNode)
	local x1, y1, z1 = getWorldTranslation(player.cameraNode)

	-- first try detach, if not succesful then go for attach
	local isDetach = true
	local success = vehicle:lwAttachDetachObject(x, y, z, x1, y1, z1, isDetach)
	if not success then
		isDetach = false
		success = vehicle:lwAttachDetachObject(x, y, z, x1, y1, z1, isDetach)
	end

	-- also play sound inside origin game, other players can't really have this sound playing
	-- as we would need to position this sound on the place of attaching, but we don't know how!
	if success then
		if isDetach and vehicle.lwChainDetachSndSample ~= nil then
			g_soundManager:playSample(vehicle.lwChainDetachSndSample, 1)
		elseif not isDetach and vehicle.lwChainAttachSndSample ~= nil then
			g_soundManager:playSample(vehicle.lwChainAttachSndSample, 1)
		end
	end

	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(lwAttachDetachEvent:new(vehicle, x, y, z, x1, y1, z1, isDetach), nil, nil, vehicle)
		else
			g_client:getServerConnection():sendEvent(lwAttachDetachEvent:new(vehicle, x, y, z, x1, y1, z1, isDetach))
		end
	end
end


lwDetachAllEvent = {}
lwDetachAllEvent_mt = Class(lwDetachAllEvent, Event)

InitEventClass(lwDetachAllEvent, "lwDetachAllEvent")

function lwDetachAllEvent:emptyNew()
    local self = Event:new(lwDetachAllEvent_mt)
    return self
end

function lwDetachAllEvent:new(object)
    local self = lwDetachAllEvent:emptyNew()
    self.object = object
    return self
end

function lwDetachAllEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
	self:run(connection)
end

function lwDetachAllEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.object)
end

function lwDetachAllEvent:run(connection)
	
	if not connection:getIsServer() then
        g_server:broadcastEvent(lwDetachAllEvent:new(self.object), nil, connection, self.object)
	end

	if self.object ~= nil then
		self.object:lwDetachObject(self.object.lwAttachedShapes[1])
	end
end

function lwDetachAllEvent.sendEvent(vehicle, noEventSend)

	if vehicle:lwDetachObject(vehicle.lwAttachedShapes[1]) then
		if vehicle.lwChainDetachSndSample ~= nil then
			g_soundManager:playSample(vehicle.lwChainDetachSndSample, 1)
		end
	end

	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(lwDetachAllEvent:new(vehicle), nil, nil, vehicle)
		else
			g_client:getServerConnection():sendEvent(lwDetachAllEvent:new(vehicle))
		end
	end
end


lwWinchEvent = {}
lwWinchEvent_mt = Class(lwWinchEvent, Event)

InitEventClass(lwWinchEvent, "lwWinchEvent")

function lwWinchEvent:emptyNew()
    local self = Event:new(lwWinchEvent_mt)
    return self
end

function lwWinchEvent:new(object, isSpeedup, userId)
    local self = lwWinchEvent:emptyNew()
    self.object = object
	self.isSpeedup = isSpeedup
	self.userId = userId
    return self
end

function lwWinchEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
	self.isSpeedup = streamReadBool(streamId)
	self.userId = NetworkUtil.readNodeObjectId(streamId)	
	self:run(connection)
end

function lwWinchEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.object)
	streamWriteBool(streamId, self.isSpeedup)
	NetworkUtil.writeNodeObjectId(streamId, self.userId)
end

function lwWinchEvent:run(connection)
	if self.object ~= nil then
    	self.object:lwWinch(self.isSpeedup, self.userId)
	end
end

function lwWinchEvent.sendEvent(vehicle, isSpeedup, userId, noEventSend)

	if vehicle.isServer then
		vehicle:lwWinch(isSpeedup, userId)
	else
		if noEventSend == nil or noEventSend == false then
			g_client:getServerConnection():sendEvent(lwWinchEvent:new(vehicle, isSpeedup, userId))
		end
	end
end


lwWinchFeedbackEvent = {}
lwWinchFeedbackEvent_mt = Class(lwWinchFeedbackEvent, Event)

InitEventClass(lwWinchFeedbackEvent, "lwWinchFeedbackEvent")

function lwWinchFeedbackEvent:emptyNew()
    local self = Event:new(lwWinchFeedbackEvent_mt)
    return self
end

function lwWinchFeedbackEvent:new(object, isToHeavy, isWinching, isSpeedup, userId)
    local self = lwWinchFeedbackEvent:emptyNew()
    self.object = object
    self.isToHeavy = isToHeavy
    self.isWinching = isWinching
    self.isSpeedup = isSpeedup
    self.userId = userId
    return self
end

function lwWinchFeedbackEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
    self.isToHeavy = streamReadBool(streamId)
    self.isWinching = streamReadBool(streamId)
    self.isSpeedup = streamReadBool(streamId)
    self.userId = NetworkUtil.readNodeObjectId(streamId)
	self:run(connection)
end

function lwWinchFeedbackEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.object)
	streamWriteBool(streamId, self.isToHeavy)
	streamWriteBool(streamId, self.isWinching)
	streamWriteBool(streamId, self.isSpeedup)
	NetworkUtil.writeNodeObjectId(streamId, self.userId)
end

function lwWinchFeedbackEvent:run(connection)
	if self.object ~= nil then
		if self.isToHeavy then
			if g_currentMission.playerUserId == self.userId then
				g_currentMission:showBlinkingWarning(g_i18n:getText("warning_attachedObjectsToHeavy"), 2000)
			end
		end

		if self.object.lwSoundSample ~= nil then
			if self.isWinching then
				if self.isSpeedup then
					self.object.lwCurrPtoRpm = self.object.lwSpeedupWinchPtoRpm
				else
					self.object.lwCurrPtoRpm = self.object.lwWinchPtoRpm
				end

				-- we can use this variable to tell client update function that winch is winching,
				-- so sounds can be properly updated once timer is up
				LogsWinch.ClientWinchingTimer = 200
			end
		end
	end
end

function lwWinchFeedbackEvent.sendEvent(vehicle, isToHeavy, isWinching, isSpeedup, userId, noEventSend)

	--if not g_currentMission.connectedToDedicatedServer then

	if not g_currentMission.connectedToDedicatedServer and g_server ~= nil and isToHeavy then
		if g_currentMission.playerUserId == userId then
			g_currentMission:showBlinkingWarning(g_i18n:getText("warning_attachedObjectsToHeavy"), 2000)
		end
	end

	if vehicle.lwSoundSample ~= nil then
		if isWinching then
			if isSpeedup then
				vehicle.lwCurrPtoRpm = vehicle.lwSpeedupWinchPtoRpm
			else
				vehicle.lwCurrPtoRpm = vehicle.lwWinchPtoRpm
			end

			-- we can use this variable to tell client update function that winch is winching,
			-- so sounds can be properly updated once timer is up
			LogsWinch.ClientWinchingTimer = 200
		end
	end

	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(lwWinchFeedbackEvent:new(vehicle, isToHeavy, isWinching, isSpeedup, userId), nil, nil, vehicle)
		else
			g_client:getServerConnection():sendEvent(lwWinchFeedbackEvent:new(vehicle, isToHeavy, isWinching, isSpeedup, userId))
		end
	end
end


lwReleaseEvent = {}
lwReleaseEvent_mt = Class(lwReleaseEvent, Event)

InitEventClass(lwReleaseEvent, "lwReleaseEvent")

function lwReleaseEvent:emptyNew()
    local self = Event:new(lwReleaseEvent_mt)
    return self
end

function lwReleaseEvent:new(object)
    local self = lwReleaseEvent:emptyNew()
    self.object = object
    return self
end

function lwReleaseEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
	self:run(connection)
end

function lwReleaseEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.object)
end

function lwReleaseEvent:run(connection)
	if self.object ~= nil then
    	self.object:lwRelease()
	end
end

function lwReleaseEvent.sendEvent(vehicle, noEventSend)

	if vehicle.isServer then
		vehicle:lwRelease()
	else
		if noEventSend == nil or noEventSend == false then
			g_client:getServerConnection():sendEvent(lwReleaseEvent:new(vehicle))
		end
	end
end
