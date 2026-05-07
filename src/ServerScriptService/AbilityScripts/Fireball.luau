-- ServerScriptService/AbilityScripts/Fireball
-- Standard signature: Cast(player, shotId, originPos, aimPos)
-- Fireball direction is FLAT (yaw only), so looking up/down doesn't change travel direction.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DEBUG = false
local function sfb(...)
	if DEBUG then
		local parts = { "[Fireball]" }
		for _, v in ipairs({ ... }) do
			parts[#parts + 1] = tostring(v)
		end
		warn(table.concat(parts, " "))
	end
end

-- Config
local COOLDOWN = 0.8
local START_SPEED = 120
local ACCEL = 600
local LIFETIME = 1.75
local DAMAGE = 22.5

local CAST_SOUNDS = {
	"rbxassetid://101485035067883",
	"rbxassetid://85998279500440",
	"rbxassetid://108864000747313",
}
local soundIndex: {[Player]: number} = {}

local BRAKE_TIME = 0.20
local BRAKE_DISTANCE = 5

local HIT_FLASH_TIME = 0.12
local HIT_FADE_TIME = 0.25
local HIT_LIGHT_BRIGHTNESS = 8

local HIT_BURST_COUNT = 30
local HIT_BURST_SCALE = 2
local HIT_BURST_TIME = 0.14

local FIRE_SLOW_TIME = 0.25
local FIRE_SLOW_MULT = 0.5

-- Wall-hit smoke poof
local SMOKE_EMIT_COUNT = 20   -- particles burst on env hit

local MAX_AIM_DIST = 600

local FIREBALL_TEMPLATE = ReplicatedStorage:WaitForChild("Projectiles"):WaitForChild("Fireball")

-- cooldowns[player]["Fireball"] = readyTime
local cooldowns: {[Player]: {[string]: number}} = {}

local function getAliveCharacter(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return end
	return char, hum, hrp
end

local function clampAim(origin: Vector3, aim: Vector3): Vector3
	local d = aim - origin
	local m = d.Magnitude
	if m > MAX_AIM_DIST then
		return origin + d.Unit * MAX_AIM_DIST
	end
	return aim
end

local function dirFromAim(origin: Vector3, aim: Vector3, fallbackLook: Vector3): Vector3
	local d = aim - origin
	if d.Magnitude < 0.01 then
		return (fallbackLook.Magnitude > 0.01) and fallbackLook.Unit or Vector3.new(0, 0, -1)
	end
	return d.Unit
end

local function findHumanoidFromHit(hitInst: Instance): Humanoid?
	local cur: Instance? = hitInst
	while cur do
		if cur:IsA("Model") then
			local h = cur:FindFirstChildOfClass("Humanoid")
			if h then return h end
		end
		cur = cur.Parent
	end
	return nil
end

local function ensurePrimaryPart(m: Model)
	if m.PrimaryPart then return m.PrimaryPart end
	local pp = m:FindFirstChildWhichIsA("BasePart", true)
	if pp then m.PrimaryPart = pp end
	return m.PrimaryPart
end

local function setProjectilePartSettings(m: Model)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
		end
	end
end

local function hideVisualParts(m: Model)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Transparency = 1
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("Decal") or d:IsA("Texture") then
					d.Transparency = 1
				end
			end
		end
	end
end

local function disableParticleEmitters(m: Model)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("ParticleEmitter") then
			if inst.Name == "Particles2" then
				inst:Destroy()
			else
				inst.Enabled = false
			end
		end
	end
end

local function scaledNumberSequence(ns: NumberSequence, mult: number): NumberSequence
	local kps = ns.Keypoints
	local newKps = table.create(#kps)
	for i, kp in ipairs(kps) do
		newKps[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * mult, kp.Envelope * mult)
	end
	return NumberSequence.new(newKps)
end

local function hitWoosh(m: Model)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("ParticleEmitter") and inst.Name ~= "Smoke" then
			local pe = inst :: ParticleEmitter
			local oldSize = pe.Size
			local oldSpeed = pe.Speed
			local oldRot = pe.RotSpeed

			pe.Size = scaledNumberSequence(oldSize, HIT_BURST_SCALE)
			pe.Speed = NumberRange.new(oldSpeed.Min * 1.1, oldSpeed.Max * 1.1)
			pe.RotSpeed = NumberRange.new(oldRot.Min * 1.1, oldRot.Max * 1.1)

			pcall(function() pe:Emit(HIT_BURST_COUNT) end)

			task.delay(HIT_BURST_TIME, function()
				if pe and pe.Parent then
					pe.Size = oldSize
					pe.Speed = oldSpeed
					pe.RotSpeed = oldRot
				end
			end)
		end
	end

	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
			local light = inst :: any
			local startB = light.Brightness
			local flash = TweenService:Create(light, TweenInfo.new(HIT_FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Brightness = startB + HIT_LIGHT_BRIGHTNESS
			})
			local fade = TweenService:Create(light, TweenInfo.new(HIT_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Brightness = 0
			})
			flash:Play()
			flash.Completed:Connect(function() fade:Play() end)
		end
	end

	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			local p = inst
			local startT = p.Transparency
			local flashT = math.clamp(startT - 0.15, 0, 1)
			local flash = TweenService:Create(p, TweenInfo.new(HIT_FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = flashT
			})
			local fade = TweenService:Create(p, TweenInfo.new(HIT_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1
			})
			flash:Play()
			flash.Completed:Connect(function() fade:Play() end)
		end
	end
end

-- firing slow (stacks)
local slowUntil: {[Humanoid]: number} = {}

local function applyFireSlow(hum: Humanoid)
	local now = os.clock()
	local untilT = now + FIRE_SLOW_TIME
	if (slowUntil[hum] or 0) < untilT then slowUntil[hum] = untilT end

	if hum:GetAttribute("Fireball_OrigSpeed") == nil then
		hum:SetAttribute("Fireball_OrigSpeed", hum.WalkSpeed)
	end

	local orig = hum:GetAttribute("Fireball_OrigSpeed")
	if type(orig) ~= "number" then orig = hum.WalkSpeed end

	hum.WalkSpeed = math.max(6, orig * FIRE_SLOW_MULT)

	task.delay(FIRE_SLOW_TIME + 0.1, function()
		if not hum.Parent then return end
		if (slowUntil[hum] or 0) > os.clock() then return end
		local o = hum:GetAttribute("Fireball_OrigSpeed")
		if type(o) == "number" then hum.WalkSpeed = o end
		hum:SetAttribute("Fireball_OrigSpeed", nil)
		slowUntil[hum] = nil
	end)
end

local function spawnFireball(player: Player, shotId: any, originPos: any, aimPos: any)
	local char, hum, hrp = getAliveCharacter(player)
	if not char then return end

	applyFireSlow(hum)

	-- Validate origin (anti-cheese like bricks)
	local serverPos = hrp.Position
	local clientPos = (typeof(originPos) == "Vector3") and originPos or serverPos
	if (clientPos - serverPos).Magnitude > 10 then
		clientPos = serverPos
	end

	-- Full 3D direction toward the camera aim point (preserves vertical angle)
	local fallbackLook = hrp.CFrame.LookVector
	local aim = (typeof(aimPos) == "Vector3") and clampAim(clientPos, aimPos) or (clientPos + fallbackLook * 30)
	local dir = dirFromAim(clientPos, aim, fallbackLook)

	local flatFace = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if flatFace.Magnitude > 0.01 then flatFace = flatFace.Unit else flatFace = Vector3.new(dir.X, 0, dir.Z).Unit end
	local startPos = clientPos + Vector3.new(0, 2, 0) + flatFace * 3

	local ball = FIREBALL_TEMPLATE:Clone()
	ball.Name = "FireballShot"
	ball:SetAttribute("OwnerUserId", player.UserId)
	if typeof(shotId) == "string" then
		ball:SetAttribute("ShotId", shotId)
	end
	ball.Parent = workspace

	setProjectilePartSettings(ball)

	local primary = ensurePrimaryPart(ball)
	local hitbox = ball:FindFirstChild("Hitbox", true)
	if not primary then
		warn("[Fireball] Model has no BasePart/PrimaryPart.")
		ball:Destroy()
		return
	end
	if not hitbox or not hitbox:IsA("BasePart") then
		warn("[Fireball] Missing Hitbox part in model.")
		ball:Destroy()
		return
	end

	-- Cast sound is handled client-side for the shooter (always audible).
	-- Increment index server-side so it stays in sync if server sounds are added later.
	soundIndex[player] = ((soundIndex[player] or 0) % #CAST_SOUNDS) + 1
	game:GetService("Debris"):AddItem(castSound, 5)

	local pivotCF = CFrame.new(startPos, startPos + dir)
	ball:PivotTo(pivotCF)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, ball }
	params.IgnoreWater = true

	local hitboxOffset  = ball:GetPivot():ToObjectSpace(hitbox.CFrame)
	local primaryOffset = ball:GetPivot():ToObjectSpace(primary.CFrame)

	local speed = START_SPEED
	local alive = true
	local elapsed = 0
	local lastHitboxCF  = ball:GetPivot() * hitboxOffset
	local lastPrimaryCF = ball:GetPivot() * primaryOffset

	local braking = false
	local brakeT = 0
	local brakeStartSpeed = 0
	local brakeTraveled = 0

	local function dieWithParticlesAndDestroy()
		hideVisualParts(ball)
		disableParticleEmitters(ball)
		task.delay(3, function()
			if ball and ball.Parent then ball:Destroy() end
		end)
	end

	sfb("spawn", "shotId=", shotId, "pos=", startPos, "dir=", dir)

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		if not ball.Parent then
			alive = false
			if conn then conn:Disconnect() end
			return
		end

		elapsed += dt

		if (not braking) and elapsed >= LIFETIME then
			braking = true
			brakeT = 0
			brakeStartSpeed = speed
			brakeTraveled = 0
		end

		local step = 0
		if not braking then
			speed += ACCEL * dt
			step = speed * dt
		else
			brakeT += dt
			local a = math.clamp(brakeT / BRAKE_TIME, 0, 1)
			local eased = (1 - a)
			speed = brakeStartSpeed * (eased * eased)
			step = speed * dt

			local remaining = BRAKE_DISTANCE - brakeTraveled
			if remaining <= 0 then
				step = 0
			elseif step > remaining then
				step = remaining
			end
			brakeTraveled += step

			if a >= 1 or step <= 0.0001 then
				alive = false
				if conn then conn:Disconnect() end
				sfb("expire", "shotId=", shotId)
				dieWithParticlesAndDestroy()
				return
			end
		end

		local nextPos       = pivotCF.Position + dir * step
		local nextPivotCF   = CFrame.new(nextPos, nextPos + dir)
		local nextHitboxCF  = nextPivotCF * hitboxOffset
		local nextPrimaryCF = nextPivotCF * primaryOffset

		-- Hitbox cast: only used to detect player hits (enlarged area for leniency).
		local hitboxMove = nextHitboxCF.Position - lastHitboxCF.Position
		local hitboxResult = workspace:Blockcast(lastHitboxCF, hitbox.Size * 2, hitboxMove, params)

		local playerHit: Humanoid? = nil
		if hitboxResult then
			local targetHum = findHumanoidFromHit(hitboxResult.Instance)
			if targetHum and targetHum ~= hum and targetHum.Health > 0 then
				playerHit = targetHum
			end
		end

		-- Primary-part cast: used to detect environment/wall hits.
		-- The hitbox is intentionally larger than the visual fireball, so we only
		-- destroy on geometry if the actual fireball part would have hit it too.
		local envHit = false
		local envHitPos: Vector3? = nil
		if not playerHit then
			local primaryMove = nextPrimaryCF.Position - lastPrimaryCF.Position
			local primaryResult = workspace:Blockcast(lastPrimaryCF, primary.Size, primaryMove, params)
			if primaryResult then
				local targetHum = findHumanoidFromHit(primaryResult.Instance)
				if targetHum and targetHum ~= hum and targetHum.Health > 0 then
					-- Primary part hit a player (hitbox must have grazed geometry first).
					playerHit = targetHum
				else
					envHit = true
					envHitPos = primaryResult.Position
				end
			end
		end

		if playerHit or envHit then
			alive = false
			if conn then conn:Disconnect() end

			if playerHit then
				sfb("hit player", "shotId=", shotId, "hum=", playerHit:GetFullName())
				playerHit:TakeDamage(DAMAGE)
				hitWoosh(ball)
				task.delay(HIT_FLASH_TIME, function()
					if ball and ball.Parent then dieWithParticlesAndDestroy() end
				end)
			else
				sfb("hit env", "shotId=", shotId)
				-- Clone the smoke object onto a stationary host at the hit point so
				-- the poof stays in place while the fireball fades out.
				local smokeObj = ball:FindFirstChild("Smoke", true)
				if smokeObj and envHitPos then
					local host = Instance.new("Part")
					host.Anchored     = true
					host.CanCollide   = false
					host.CanTouch     = false
					host.CanQuery     = false
					host.Transparency = 1
					host.Size         = Vector3.new(1, 1, 1)
					-- Identity CFrame keeps the part Y-up so Top = upward
					host.CFrame       = CFrame.new(envHitPos)
					host.Parent       = workspace

					local maxLife = 0
					local sources = smokeObj:IsA("ParticleEmitter") and { smokeObj } or smokeObj:GetDescendants()
					for _, pe in ipairs(sources) do
						if pe:IsA("ParticleEmitter") then
							local cloned = pe:Clone()
							-- Disabled = no continuous stream; Emit() fires a clean one-shot
							-- burst so particles fade out naturally and the host can be
							-- destroyed without cutting anything off mid-life.
							cloned.Enabled          = false
							cloned.EmissionDirection = Enum.NormalId.Top
							cloned.Parent = host
							cloned.Size = NumberSequence.new(6,8)
							cloned.Speed = NumberRange.new(10)
							cloned.SpreadAngle = Vector2.new(-25,25)
							cloned.Transparency = NumberSequence.new(0.9,1)
							cloned:Emit(SMOKE_EMIT_COUNT)
							if cloned.Lifetime.Max > maxLife then maxLife = cloned.Lifetime.Max end
						end
					end

					task.delay(maxLife + 0.5, function()
						if host and host.Parent then host:Destroy() end
					end)
				end
				dieWithParticlesAndDestroy()
			end
			return
		end

		pivotCF     = nextPivotCF
		ball:PivotTo(pivotCF)
		lastHitboxCF  = nextHitboxCF
		lastPrimaryCF = nextPrimaryCF
	end)
end

Players.PlayerRemoving:Connect(function(player: Player)
	cooldowns[player] = nil
	soundIndex[player] = nil
end)

local Fireball = {}

function Fireball.Cast(player: Player, shotId: any, originPos: any, aimPos: any)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		sfb("BLOCKED dead/no-char", player.Name)
		return false
	end

	-- Single authoritative cooldown check and set. Never reset after this.
	cooldowns[player] = cooldowns[player] or {}
	local now = os.clock()
	local readyAt = cooldowns[player]["Fireball"] or 0
	if now < readyAt then
		sfb("BLOCKED cooldown", player.Name, "remaining=" .. string.format("%.2f", readyAt - now) .. "s")
		return false
	end
	cooldowns[player]["Fireball"] = now + COOLDOWN
	sfb("FIRE allowed", player.Name, "nextReadyAt=" .. string.format("%.3f", now + COOLDOWN))

	spawnFireball(player, shotId, originPos, aimPos)
	return true
end

return Fireball