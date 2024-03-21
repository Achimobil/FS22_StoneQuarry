PlaceableSimpleHeapSpawner = {
	SPEC_NAME = g_currentModName .. ".simpleHeapSpawner"
}
PlaceableSimpleHeapSpawner.SPEC = "spec_" .. PlaceableSimpleHeapSpawner.SPEC_NAME

function PlaceableSimpleHeapSpawner.prerequisitesPresent(specializations)
	return true
end

function PlaceableSimpleHeapSpawner.registerEventListeners(placeableType)
	SpecializationUtil.registerEventListener(placeableType, "onLoad", PlaceableSimpleHeapSpawner)
	SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", PlaceableSimpleHeapSpawner)
	SpecializationUtil.registerEventListener(placeableType, "onUpdateTick", PlaceableSimpleHeapSpawner)
	SpecializationUtil.registerEventListener(placeableType, "onDelete", PlaceableSimpleHeapSpawner)
end

function PlaceableSimpleHeapSpawner.registerXMLPaths(schema, basePath)
	schema:setXMLSpecializationType("PlaceableSimpleHeapSpawner")
	schema:register(XMLValueType.NODE_INDEX, basePath .. ".simpleHeapSpawner.spawnArea(?).area#startNode", "")
	schema:register(XMLValueType.NODE_INDEX, basePath .. ".simpleHeapSpawner.spawnArea(?).area#widthNode", "")
	schema:register(XMLValueType.NODE_INDEX, basePath .. ".simpleHeapSpawner.spawnArea(?).area#heightNode", "")
	schema:register(XMLValueType.STRING, basePath .. ".simpleHeapSpawner.spawnArea(?)#fillType", "Spawn fill type")
	schema:register(XMLValueType.FLOAT, basePath .. ".simpleHeapSpawner.spawnArea(?)#litersPerHour", "Spawn liters per ingame hour")
	EffectManager.registerEffectXMLPaths(schema, basePath .. ".simpleHeapSpawner.spawnArea(?).effectNodes")
	schema:setXMLSpecializationType()
end

function PlaceableSimpleHeapSpawner:onLoad(savegame)
	local spec = self[PlaceableSimpleHeapSpawner.SPEC]
	local key = "placeable.simpleHeapSpawner"
	spec.spawnAreas = {}

	self.xmlFile:iterate(key .. ".spawnArea", function (_, areaKey)
		local startNode = self.xmlFile:getValue(areaKey .. ".area#startNode", nil, self.components, self.i3dMappings)

		if startNode == nil then
			Logging.xmlError(self.xmlFile, "Missing startNode for spawnArea '%s'", areaKey)

			return
		end

		local widthNode = self.xmlFile:getValue(areaKey .. ".area#widthNode", nil, self.components, self.i3dMappings)

		if widthNode == nil then
			Logging.xmlError(self.xmlFile, "Missing widthNode for spawnArea '%s'", areaKey)

			return
		end

		local heightNode = self.xmlFile:getValue(areaKey .. ".area#heightNode", nil, self.components, self.i3dMappings)

		if heightNode == nil then
			Logging.xmlError(self.xmlFile, "Missing heightNode for spawnArea '%s'", areaKey)

			return
		end

		local fillTypeName = self.xmlFile:getValue(areaKey .. "#fillType", "")
		local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)

		if fillTypeIndex == nil then
			Logging.xmlError(self.xmlFile, "Missing or invalid fillType (%s) for spawnArea '%s'", fillTypeName, areaKey)

			return
		end

		local litersPerHour = self.xmlFile:getValue(areaKey .. "#litersPerHour", 150)

		if litersPerHour <= 0 then
			Logging.xmlError(self.xmlFile, "litersPerHour may not be 0 or negative for spawnArea '%s'", areaKey)

			return
		end

		local spawnArea = {
			amountToTip = 0,
			lineOffset = 0,
			start = startNode,
			width = widthNode,
			height = heightNode,
			fillTypeIndex = fillTypeIndex,
			litersPerMs = litersPerHour / 3600000
		}

		if self.isClient then
			spawnArea.effects = g_effectManager:loadEffect(self.xmlFile, areaKey .. ".effectNodes", self.components, self, self.i3dMappings)

			g_effectManager:setFillType(spawnArea.effects, fillTypeIndex)
			g_effectManager:startEffects(spawnArea.effects)
		end

		table.insert(spec.spawnAreas, spawnArea)
	end)
end

function PlaceableSimpleHeapSpawner:onFinalizePlacement(savegame)
	if self.isServer then
		self:raiseActive()
	end
end

function PlaceableSimpleHeapSpawner:onDelete()
	local spec = self[PlaceableSimpleHeapSpawner.SPEC]

	if spec.spawnAreas ~= nil then
		for _, spawnArea in ipairs(spec.spawnAreas) do
			g_effectManager:deleteEffects(spawnArea.effects)
		end
	end
end

function PlaceableSimpleHeapSpawner:onUpdateTick(dt)
	if self.isServer then
		local spec = self[PlaceableSimpleHeapSpawner.SPEC]
		local scaledDt = dt * g_currentMission:getEffectiveTimeScale()

		for _, spawnArea in ipairs(spec.spawnAreas) do
			local amountToTip = scaledDt * spawnArea.litersPerMs
			spawnArea.amountToTip = spawnArea.amountToTip + amountToTip

			if g_densityMapHeightManager:getMinValidLiterValue(spawnArea.fillTypeIndex) < spawnArea.amountToTip then
				local lsx, lsy, lsz, lex, ley, lez, radius = DensityMapHeightUtil.getLineByArea(spawnArea.start, spawnArea.width, spawnArea.height, false)
				local _, lineOffset = DensityMapHeightUtil.tipToGroundAroundLine(nil, spawnArea.amountToTip, spawnArea.fillTypeIndex, lsx, lsy, lsz, lex, ley, lez, radius, radius, spawnArea.lineOffset, nil, nil, nil)
				spawnArea.lineOffset = lineOffset
				spawnArea.amountToTip = 0
			end
		end

		self:raiseActive()
	end
end
