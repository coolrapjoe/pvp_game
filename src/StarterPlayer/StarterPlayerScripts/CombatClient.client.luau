-- StarterPlayerScripts/CombatClient
-- Brick: prediction for EVERYONE via Remotes.AbilityPredict + seamless swap + guaranteed predicted cleanup
-- Fireball: minimal owner prediction kept local
-- Meteor: no prediction (slow/big)

local GameState = require(script.Parent:WaitForChild("GameState"))
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local useAbility = Remotes:WaitForChild("UseAbility")
local abilityPredict = Remotes:WaitForChild("AbilityPredict")

local brickTemplate = ReplicatedStorage:WaitForChild("Projectiles"):WaitForChild("Brick")
local fireballTemplate = ReplicatedStorage:WaitForChild("Projectiles"):WaitForChild("Fireball")

local MAX_DIST = 600

local FIREBALL_ANIM_ID = "rbxassetid://97769563564365"

local activeAnimTracks: {[string]: boolean} = {}

local function playCharacterAnim(char: Model, animId: string, speed: number?, slowSpeed: number?)
	if activeAnimTracks[animId] then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track = animator:LoadAnimation(anim)
	track.Looped = false
	track.Priority = Enum.AnimationPriority.Action4
	pcall(function() track.RootMotionWeight = 0 end)
	activeAnimTracks[animId] = true
	local origSpeed = humanoid.WalkSpeed
	if slowSpeed then humanoid.WalkSpeed = slowSpeed end
	track:Play()
	track:AdjustSpeed(speed or 1)
	task.spawn(function()
		track.Stopped:Wait()
		track:Destroy()
		activeAnimTracks[animId] = nil
		if slowSpeed and humanoid and humanoid.Parent then
			humanoid.WalkSpeed = origSpeed
		end
		task.wait()
		if humanoid and humanoid.Parent then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	end)
end

local brickUltSound = Instance.new("Sound")
brickUltSound.SoundId = "rbxassetid://119310967434859"
brickUltSound.Volume = 10
brickUltSound.Parent = workspace.Terrain

local ClientLoadouts = {
	Wizard = { Primary = "Fireball", Special = "Meteor" },
	Boxer = { Primary = "BoxPunch", Special = "BoxPunch" },
	Brick = { Primary = "BrickThrow", Special = "BrickUltimate" },
	Knight = { Primary = "SwordSlash", Special = "SwordSlash" },
}

local function getHrpPos(): Vector3?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or nil
end

local function getHrpCFrame(): CFrame?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.CFrame or nil
end

local function getAimPosFromOrigin(_originPos: Vector3, maxDist: number): Vector3
	-- Raycast from the camera centre outward so the aim point reflects exactly
	-- where the crosshair is pointing, including vertical angle.
	local rayStart = camera.CFrame.Position
	local dir = camera.CFrame.LookVector * maxDist

	local char = player.Character
	if not char then
		return rayStart + dir
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true

	local r = workspace:Raycast(rayStart, dir, params)
	return r and r.Position or (rayStart + dir)
end

local function yawDir(dir: Vector3): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then return Vector3.new(0, 0, -1) end
	return flat.Unit
end

local function hideModelLocal(m: Model, hide: boolean)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = hide and 1 or 0
			inst.CastShadow = not hide
		end
	end
end

-- ============================================================
-- Brick prediction (everyone)
-- ============================================================

local BRICK_FORWARD_SPEED = 70
local BRICK_UPWARD_SPEED = 45
local BRICK_LIFE = 5.25
local BRICK_PREDICT_CD = 0.5
local nextBrickPredictAt = 0

local predictedBrickByKey: {[string]: BasePart} = {}

local function makeKey(ownerUserId: number, shotId: string): string
	return tostring(ownerUserId) .. ":" .. shotId
end

local function cleanupPredicted(key: string)
	local b = predictedBrickByKey[key]
	if b and b.Parent then
		b.LocalTransparencyModifier = 1
		b.Transparency = 1
		Debris:AddItem(b, 0.05)
	end
	predictedBrickByKey[key] = nil
end

local function spawnPredictedBrick(ownerUserId: number, shotId: string, originPos: Vector3, aimPos: Vector3): BasePart?
	local key = makeKey(ownerUserId, shotId)
	local existing = predictedBrickByKey[key]
	if existing and existing.Parent then
		return existing
	end

	local d3 = (aimPos - originPos)
	if d3.Magnitude < 0.01 then
		d3 = camera.CFrame.LookVector
	end

	local flat = Vector3.new(d3.X, 0, d3.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	end

	local dir = (flat.Magnitude < 0.01) and Vector3.new(0, 0, -1) or flat.Unit
	local face = yawDir(dir)
	local spawnPos = originPos + Vector3.new(0, 2.8, 0) + dir * 3

	local b = brickTemplate:Clone()
	b.Name = "PredictedBrick"
	b:SetAttribute("OwnerUserId", ownerUserId)
	b:SetAttribute("ShotId", shotId)
	b:SetAttribute("Landed", false)

	b.Anchored = false
	b.CanCollide = false
	b.CanTouch = false
	b.CanQuery = true
	b.Massless = true
	b.CFrame = CFrame.new(spawnPos, spawnPos + face)
	b.Parent = workspace

	b.AssemblyLinearVelocity = (dir * BRICK_FORWARD_SPEED) + Vector3.new(0, BRICK_UPWARD_SPEED, 0)

	predictedBrickByKey[key] = b
	Debris:AddItem(b, BRICK_LIFE)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { b }
	params.IgnoreWater = true

	local lastPos = b.Position
	local hbConn
	hbConn = RunService.Heartbeat:Connect(function()
		if not b.Parent then
			if hbConn then hbConn:Disconnect() end
			return
		end
		if b:GetAttribute("Landed") == true then
			if hbConn then hbConn:Disconnect() end
			return
		end

		local curPos = b.Position
		local delta = curPos - lastPos
		if delta.Magnitude > 0.001 then
			local r = workspace:Raycast(lastPos, delta, params)
			if r and r.Instance and r.Instance.Parent then
				b:SetAttribute("Landed", true)
				b.AssemblyLinearVelocity = Vector3.zero
				b.AssemblyAngularVelocity = Vector3.zero
				b.Anchored = true
				b.CanCollide = true

				task.delay(1.0, function()
					if predictedBrickByKey[key] == b and b and b.Parent then
						cleanupPredicted(key)
					end
				end)

				if hbConn then hbConn:Disconnect() end
				return
			end
		end
		lastPos = curPos
	end)

	task.delay(2.5, function()
		if predictedBrickByKey[key] == b and b and b.Parent then
			cleanupPredicted(key)
		end
	end)

	return b
end

abilityPredict.OnClientEvent:Connect(function(abilityName, ownerUserId, shotId, originPos, aimPos)
	if abilityName == "BrickUltSound" then
		brickUltSound:Play()
		return
	end
	if abilityName == "BrickUltAnim" then
		local animId = ownerUserId  -- repurposed arg carries the registered anim ID
		local char = player.Character
		if not char then return end
		local animator = char:FindFirstChildOfClass("Humanoid")
			and char:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
		if not animator then return end
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		local track = animator:LoadAnimation(anim)
		track:Play()
		return
	end
	if abilityName ~= "BrickThrow" then return end
	if typeof(ownerUserId) ~= "number" then return end
	if typeof(shotId) ~= "string" then return end
	if typeof(originPos) ~= "Vector3" then return end
	if typeof(aimPos) ~= "Vector3" then return end
	-- Skip our own shots. The local player's predictions are spawned in InputBegan before
	-- the server call is even sent, so this broadcast is always redundant for us. Worse,
	-- if our predicted brick already hit something and cleaned up, this would spawn a
	-- second phantom brick.
	if ownerUserId == player.UserId then return end
	spawnPredictedBrick(ownerUserId, shotId, originPos, aimPos)
end)

-- ============================================================
-- Fireball prediction (owner only) — moves and collides like the server
-- ============================================================

local FIREBALL_CD = 1.5  -- must match server COOLDOWN in Fireball.luau

local ABILITY_COST = {
	Fireball = 1,
	Meteor = 1,
	BrickThrow = 1,
	BrickUltimate = 0,
	BoxPunch = 0,
	SwordSlash = 0,
}
local nextFireballAt = 0

local PRED_START_SPEED = 120
local PRED_ACCEL      = 600
local PRED_LIFETIME   = 1.75
local PRED_BRAKE_TIME = 0.20
local PRED_BRAKE_DIST = 5

local predictedFireballById: {[string]: Model} = {}

local function setProjectilePartSettingsLocal(m: Model)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
		end
	end
end

local function ensurePrimaryPart(m: Model)
	if m.PrimaryPart then return m.PrimaryPart end
	local pp = m:FindFirstChildWhichIsA("BasePart", true)
	if pp then m.PrimaryPart = pp end
	return m.PrimaryPart
end

local function spawnPredictedFireball(shotId: string, originPos: Vector3, aimPos: Vector3): Model?
	-- Full 3D direction from the character origin toward the camera aim point.
	local d = aimPos - originPos
	if d.Magnitude < 0.01 then
		d = camera.CFrame.LookVector
	end
	local dir = d.Unit

	local startPos = originPos + Vector3.new(0, 2, 0) + dir * 4
	local ball = fireballTemplate:Clone()
	ball.Name = "PredictedFireball"
	ball:SetAttribute("ShotId", shotId)
	ball.Parent = workspace

	setProjectilePartSettingsLocal(ball)

	local primary = ensurePrimaryPart(ball)
	local hitbox = ball:FindFirstChild("Hitbox", true)
	if not primary or not (hitbox and hitbox:IsA("BasePart")) then
		ball:Destroy()
		return nil
	end

	local pivotCF = CFrame.new(startPos, startPos + dir)
	ball:PivotTo(pivotCF)

	predictedFireballById[shotId] = ball

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { player.Character, ball }
	castParams.IgnoreWater = true

	local hitboxOffset = ball:GetPivot():ToObjectSpace(hitbox.CFrame)
	local lastHitboxCF  = ball:GetPivot() * hitboxOffset

	local speed    = PRED_START_SPEED
	local elapsed  = 0
	local alive    = true
	local braking  = false
	local brakeT   = 0
	local brakeStartSpeed = 0
	local brakeTraveled   = 0

	local function diePredicted()
		predictedFireballById[shotId] = nil
		ball:Destroy()
	end

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		if not ball.Parent then
			alive = false
			conn:Disconnect()
			return
		end

		elapsed += dt

		if not braking and elapsed >= PRED_LIFETIME then
			braking       = true
			brakeT        = 0
			brakeStartSpeed = speed
			brakeTraveled = 0
		end

		local step = 0
		if not braking then
			speed += PRED_ACCEL * dt
			step = speed * dt
		else
			brakeT += dt
			local a     = math.clamp(brakeT / PRED_BRAKE_TIME, 0, 1)
			local eased = 1 - a
			speed = brakeStartSpeed * (eased * eased)
			step  = speed * dt

			local remaining = PRED_BRAKE_DIST - brakeTraveled
			if remaining <= 0 then
				step = 0
			elseif step > remaining then
				step = remaining
			end
			brakeTraveled += step

			if a >= 1 or step <= 0.0001 then
				alive = false
				conn:Disconnect()
				diePredicted()
				return
			end
		end

		local nextPos      = pivotCF.Position + dir * step
		local nextPivotCF  = CFrame.new(nextPos, nextPos + dir)
		local nextHitboxCF = nextPivotCF * hitboxOffset
		local moveVec      = nextHitboxCF.Position - lastHitboxCF.Position

		if workspace:Blockcast(lastHitboxCF, hitbox.Size, moveVec, castParams) then
			alive = false
			conn:Disconnect()
			diePredicted()
			return
		end

		pivotCF      = nextPivotCF
		lastHitboxCF = nextHitboxCF
		ball:PivotTo(pivotCF)
	end)

	return ball
end

-- ============================================================
-- Server brick swap + fireball swap
-- ============================================================

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("BasePart") and inst.Name == "ThrownBrick" then
		local ownerUserId = inst:GetAttribute("OwnerUserId")
		local shotId = inst:GetAttribute("ShotId")
		if typeof(ownerUserId) ~= "number" or typeof(shotId) ~= "string" then return end

		local key = makeKey(ownerUserId, shotId)
		local predicted = predictedBrickByKey[key]

		inst.LocalTransparencyModifier = 1
		inst.CastShadow = false

		task.defer(function()
			if not (inst and inst.Parent) then return end

			if predicted and predicted.Parent then
				if predicted:GetAttribute("Landed") ~= true then
					inst.CFrame = predicted.CFrame
					inst.AssemblyLinearVelocity = predicted.AssemblyLinearVelocity
					inst.AssemblyAngularVelocity = predicted.AssemblyAngularVelocity
					inst.CanCollide = false
				end
				predicted:Destroy()
				predictedBrickByKey[key] = nil
			end

			inst.LocalTransparencyModifier = 0
			inst.Transparency = 0
			inst.CastShadow = true
		end)
		return
	end

	if inst:IsA("Model") and inst.Name == "FireballShot" and inst:GetAttribute("OwnerUserId") == player.UserId then
		local shotId = inst:GetAttribute("ShotId")
		if typeof(shotId) ~= "string" then return end

		-- Hide any children that replicate in after the initial hide call.
		-- DescendantAdded fires for the Model before its children have arrived,
		-- so GetDescendants() may be empty at that point.
		local lateHideConn = inst.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
				d.CastShadow = false
			end
		end)

		local predicted = predictedFireballById[shotId]
		if predicted and predicted.Parent then
			-- Predicted still alive: swap server ball to its position
			hideModelLocal(inst, true)
			task.defer(function()
				lateHideConn:Disconnect()
				if not (inst and inst.Parent) then return end
				if not (predicted and predicted.Parent) then
					hideModelLocal(inst, false)
					return
				end
				pcall(function()
					inst:PivotTo(predicted:GetPivot())
				end)
				predicted:Destroy()
				predictedFireballById[shotId] = nil
				hideModelLocal(inst, false)
			end)
		else
			-- No predicted (server fired a shot the client didn't predict, or predicted
			-- already died). Suppress the server ball visually; lateHideConn stays active
			-- to catch late-replicating children.
			hideModelLocal(inst, true)
		end
	end
end)

-- ============================================================
-- Input -> server
-- ============================================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if GameState.isSelecting() then return end

	local isPrimary = (input.UserInputType == Enum.UserInputType.MouseButton1)
	local isSpecial = (input.KeyCode == Enum.KeyCode.E)
	if not isPrimary and not isSpecial then return end

	local slot = isPrimary and "Primary" or "Special"

	local originPos = getHrpPos()
	if not originPos then return end

	local aimPos = getAimPosFromOrigin(originPos, MAX_DIST)
	local originCF = getHrpCFrame()

	local shotId = HttpService:GenerateGUID(false)

	local charType = player:GetAttribute("CharacterType") or "Wizard"
	local moveName = (ClientLoadouts[charType] and ClientLoadouts[charType][slot]) or nil
	if not moveName then return end

	local ammo = player:FindFirstChild("Ammo")
	local maxAmmo = player:FindFirstChild("MaxAmmo")
	local useAmmo = player:FindFirstChild("UseAmmo")

	local cost = ABILITY_COST[moveName] or 0
	if cost > 0 and ammo and maxAmmo and useAmmo then
		if useAmmo.Value == false then
			if ammo.Value ~= maxAmmo.Value then
				ammo.Value = maxAmmo.Value
			end
		else
			if ammo.Value < cost then
				return
			end
		end
	end

	if moveName == "BrickThrow" then
		local now = os.clock()
		if now >= nextBrickPredictAt then
			nextBrickPredictAt = now + BRICK_PREDICT_CD
			spawnPredictedBrick(player.UserId, shotId, originPos, aimPos)
		end
	elseif moveName == "Fireball" then
		local now = os.clock()
		if now >= nextFireballAt then
			nextFireballAt = now + FIREBALL_CD
			local char = player.Character
			if char then playCharacterAnim(char, FIREBALL_ANIM_ID, 1.1) end
			task.delay(0.4, function()
				spawnPredictedFireball(shotId, originPos, aimPos)
				useAbility:FireServer(slot, shotId, originPos, aimPos, originCF)
			end)
		end
		return
	end

	useAbility:FireServer(slot, shotId, originPos, aimPos, originCF)
end)