local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local abilityPredict = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AbilityPredict")

local S = {
	COOLDOWN = 30,
	PAVEMENT_NAME = "Pavement",
	SLICE_TAG = "Crushable",

	FORWARD_DIST = 60,
	TARGET_Y_OFFSET = 0,
	TARGET_RAY_HEIGHT = 200,

	ENTRY_HEIGHT = 200,
	APPROACH_BACK = 35,
	APPROACH_SIDE = 200,

	SPEED = 80,
	LIFE = 12,

	BURY_TIME = 0,
	BURY_EXTRA_DOWN = 20,
	HIDE_ON_BURY = true,
	UNDERGROUND_LINGER = 1,
	AUTO_DESTROY = true,

	-- DEBUG
	DEBUG = true,
	DEBUG_DAMAGE = true,
	DEBUG_DAMAGE_VERBOSE = false,
	DEBUG_GROUND_CUBES = false,
	DEBUG_SHARDS = false,

	-- shrapnel filtering
	SHARDS_SKIP_TRUSS = true,

	-- DAMAGE
	METEOR_HIT_DAMAGE = 100,
	BLAST_DAMAGE = 55,
	OUTER_DAMAGE = 35,
	EXPLOSION_DAMAGE_HZ = 30,
	BLAST_RADIUS_MULT = 1.0,
	OUTER_RADIUS_MULT = 1.0,
	BLAST_RADIUS_MIN = 8,
	OUTER_RADIUS_MIN = 10,
	
	BLAST_RADIUS_FIXED = 45,  -- middle ring reach
	OUTER_RADIUS_FIXED = 70,  -- outer ring reach

	-- shrapnel
	AREA_MULT = 0.35,
	HIT_REPEAT_COOLDOWN = 0.08,
	HIT_REPEAT_MULT = 0.35,

	SHARDS_PER_SECOND = 50,
	MAX_SHARDS_PER_FRAME = 8,
	MAX_SHARDS_TOTAL = 350,

	SHARD_SIZE_MIN = 2,
	SHARD_SIZE_MAX = 3.5,

	SHARD_OUT_SPEED_MIN = 200,
	SHARD_OUT_SPEED_MAX = 200,
	SHARD_UP_SPEED = 25,
	SHARD_TANGENT_SPREAD = 16,
	SHARD_SPIN = 10,

	SHARD_LIFE = 6,
	SHARD_FADE_TIME = 0.35,

	-- explosion visuals
	EXPLOSION_ENABLED = true,
	EXPLOSION_PLAY_ON_BURY = true,
	EXPLOSION_DISABLE_INNER_SHOCKWAVE = true,
	EXPLOSION_FIRE_SPHERE = true,

	EXPLOSION_BLAST_NAME = "Blast",
	EXPLOSION_OUTER_NAME = "Outer",

	EXPLOSION_BLAST_START_SCALE = 0.25,
	EXPLOSION_OUTER_START_SCALE = 0.20,

	EXPLOSION_BLAST_BURST_END_SCALE = 2.6,
	EXPLOSION_BLAST_BURST_TIME = 0.16,
	EXPLOSION_OUTER_BURST_END_SCALE = 3.6,
	EXPLOSION_OUTER_BURST_TIME = 0.12,

	EXPLOSION_BLAST_DRIFT_END_SCALE = 3.15,
	EXPLOSION_BLAST_DRIFT_TIME = 0.95,
	EXPLOSION_OUTER_DRIFT_END_SCALE = 4.35,
	EXPLOSION_OUTER_DRIFT_TIME = 1.05,

	EXPLOSION_FADE_DELAY = 0.00,
	EXPLOSION_BLAST_FADE_TIME = 0.85,
	EXPLOSION_OUTER_FADE_TIME = 0.90,

	-- ground cubes
	GROUND_CUBES_ENABLED = true,
	GROUND_CUBES_COUNT = 18,
	GROUND_CUBES_RADIUS_MIN = 1.5,
	GROUND_CUBES_RADIUS_MAX = 9,
	GROUND_CUBES_SPAWN_DEPTH = 0.8,

	GROUND_CUBES_SIZE_MIN = 1.5,
	GROUND_CUBES_SIZE_MAX = 3.0,

	GROUND_CUBES_OUT_SPEED_MIN = 200,
	GROUND_CUBES_OUT_SPEED_MAX = 300,
	GROUND_CUBES_UP_SPEED_MIN = 100,
	GROUND_CUBES_UP_SPEED_MAX = 200,

	GROUND_CUBES_OUT_FORCE_MULT = 1.0,
	GROUND_CUBES_UP_FORCE_MULT = 1.0,

	GROUND_CUBES_SPIN = 10,
	GROUND_CUBES_LIFE = 3.5,
	GROUND_CUBES_FADE_TIME = 0.45,
	GROUND_CUBES_COLLIDE = true,

	-- perf
	HIT_SCAN_MAX_PARTS = 50,
	MAX_SWEEP_SAMPLES = 8,
	MAX_POINTS_PER_PART = 8,
}

local function dbg(...)
	if S.DEBUG then print("[Meteor]", ...) end
end
local function dbgDamage(...)
	if S.DEBUG and S.DEBUG_DAMAGE then print("[Meteor][DMG]", ...) end
end
local function dbgCubes(...)
	if S.DEBUG and S.DEBUG_GROUND_CUBES then print("[Meteor][CUBES]", ...) end
end
local function dbgShards(...)
	if S.DEBUG and S.DEBUG_SHARDS then print("[Meteor][SHARDS]", ...) end
end

local METEOR_TEMPLATE = ReplicatedStorage:WaitForChild("Projectiles"):WaitForChild("Meteor")
local readyAt: {[Player]: number} = {}


local function canUse(player: Player): boolean
	local now = os.clock()
	local t = readyAt[player] or 0
	if now < t then return false end
	readyAt[player] = now + S.COOLDOWN
	return true
end

local function getAlive(player: Player): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then return nil, nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return nil, nil, nil end
	return char, hum, hrp
end

local function flatForward(hrp: BasePart): Vector3
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then return Vector3.new(0, 0, -1) end
	return flat.Unit
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

local function getHumanoidRoot(h: Humanoid): BasePart?
	local m = h.Parent
	if not m or not m:IsA("Model") then return nil end
	return (m:FindFirstChild("HumanoidRootPart") :: BasePart?)
		or (m:FindFirstChild("Torso") :: BasePart?)
		or (m:FindFirstChild("UpperTorso") :: BasePart?)
end

local function ensurePrimaryPart(m: Model): BasePart?
	if m.PrimaryPart then return m.PrimaryPart end
	local pp = m:FindFirstChildWhichIsA("BasePart", true)
	if pp then m.PrimaryPart = pp end
	return m.PrimaryPart
end

local function pickHitbox(m: Model): BasePart?
	local hb = m:FindFirstChild("Hitbox", true)
	if hb and hb:IsA("BasePart") then return hb end
	local outer = m:FindFirstChild("Outer", true)
	if outer and outer:IsA("BasePart") then return outer end
	local pp = ensurePrimaryPart(m)
	if pp then return pp end
	return m:FindFirstChildWhichIsA("BasePart", true)
end

local function setMeteorParts(m: Model, hitbox: BasePart)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
			inst.Massless = true
		end
	end
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = false
end

local function hideMeteor(m: Model)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Transparency = 1
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			inst.Transparency = 1
		elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
			pcall(function() inst.Enabled = false end)
		end
	end
end

local function isCrushable(p: BasePart): boolean
	if CollectionService:HasTag(p, S.SLICE_TAG) then return true end
	local m = p:FindFirstAncestorOfClass("Model")
	return (m ~= nil) and CollectionService:HasTag(m, S.SLICE_TAG)
end

local function findPavement(): Instance?
	return workspace:FindFirstChild(S.PAVEMENT_NAME, true)
end

local function getTargetOnPavement(pavement: Instance?, basePos: Vector3): Vector3
	if not pavement then
		return basePos + Vector3.new(0, S.TARGET_Y_OFFSET, 0)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { pavement }
	params.IgnoreWater = true

	local rayStart = basePos + Vector3.new(0, S.TARGET_RAY_HEIGHT, 0)
	local rayDir = Vector3.new(0, -S.TARGET_RAY_HEIGHT * 2, 0)

	local r = workspace:Raycast(rayStart, rayDir, params)
	if r then
		return r.Position + Vector3.new(0, S.TARGET_Y_OFFSET, 0)
	end

	return basePos + Vector3.new(0, S.TARGET_Y_OFFSET, 0)
end

local function cfWithDown(pos: Vector3, downDir: Vector3, refForward: Vector3): CFrame
	local down = (downDir.Magnitude > 0.01) and downDir.Unit or Vector3.new(0, -1, 0)
	local up = -down

	local f = (refForward.Magnitude > 0.01) and refForward.Unit or Vector3.new(0, 0, -1)
	local proj = f - up * f:Dot(up)
	if proj.Magnitude < 0.01 then
		local alt = Vector3.new(1, 0, 0)
		proj = alt - up * alt:Dot(up)
		if proj.Magnitude < 0.01 then
			proj = Vector3.new(0, 0, -1) - up * Vector3.new(0, 0, -1):Dot(up)
		end
	end

	local look = proj.Unit
	local right = look:Cross(up).Unit
	local back = right:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, up, back)
end

local function projectedAreaFromSize(size: Vector3, dirLocal: Vector3): number
	local dl = (dirLocal.Magnitude > 0.01) and dirLocal.Unit or Vector3.new(0, 0, -1)
	local ax, ay, az = math.abs(dl.X), math.abs(dl.Y), math.abs(dl.Z)
	return ax * (size.Y * size.Z) + ay * (size.X * size.Z) + az * (size.X * size.Y)
end

local function closestPointOnOBB(part: BasePart, worldPoint: Vector3): Vector3
	local lp = part.CFrame:PointToObjectSpace(worldPoint)
	local hs = part.Size * 0.5
	local cx = math.clamp(lp.X, -hs.X, hs.X)
	local cy = math.clamp(lp.Y, -hs.Y, hs.Y)
	local cz = math.clamp(lp.Z, -hs.Z, hs.Z)
	return part.CFrame:PointToWorldSpace(Vector3.new(cx, cy, cz))
end

local function scheduleFadeDestroy(p: BasePart, life: number, fadeTime: number)
	local startFade = math.max(0, life - fadeTime)
	task.delay(startFade, function()
		if not (p and p.Parent) then return end
		local t = TweenService:Create(p, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
		t:Play()
		t.Completed:Once(function()
			if p and p.Parent then p:Destroy() end
		end)
	end)
	Debris:AddItem(p, life + 0.2)
end

local function makeShardFromSource(src: BasePart): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Block
	return p
end

local function spawnShard(src: BasePart, pos: Vector3, outDir: Vector3, sizeWanted: number)
	if S.SHARDS_SKIP_TRUSS and src:IsA("TrussPart") then
		dbgShards("skip truss shard from", src:GetFullName())
		return
	end

	local shard = makeShardFromSource(src)
	shard.Name = "MeteorShard"
	shard.Size = Vector3.new(sizeWanted, sizeWanted, sizeWanted)
	shard.CFrame = CFrame.new(pos - outDir * (sizeWanted * 0.55))
	shard.Anchored = false
	shard.CanCollide = true
	shard.CanTouch = false
	shard.CanQuery = false
	shard.Massless = false
	shard:SetAttribute("MeteorShard", true)

	shard.Color = src.Color
	shard.Material = src.Material
	shard.Reflectance = src.Reflectance
	shard.Transparency = 0
	if src.MaterialVariant and src.MaterialVariant ~= "" then
		shard.MaterialVariant = src.MaterialVariant
	end

	shard.Parent = workspace

	local outSpeed = S.SHARD_OUT_SPEED_MIN + math.random() * (S.SHARD_OUT_SPEED_MAX - S.SHARD_OUT_SPEED_MIN)

	local up = Vector3.new(0, 1, 0)
	local t1 = outDir:Cross(up)
	if t1.Magnitude < 0.01 then t1 = Vector3.new(1, 0, 0) end
	t1 = t1.Unit
	local t2 = t1:Cross(outDir).Unit

	local spread = (t1 * (math.random() - 0.5) + t2 * (math.random() - 0.5)) * 2
	local vel =
		outDir * outSpeed
		+ spread * S.SHARD_TANGENT_SPREAD
		+ Vector3.new(0, S.SHARD_UP_SPEED, 0)

	shard.AssemblyLinearVelocity = vel
	shard.AssemblyAngularVelocity = Vector3.new(
		(math.random() - 0.5) * S.SHARD_SPIN,
		(math.random() - 0.5) * S.SHARD_SPIN,
		(math.random() - 0.5) * S.SHARD_SPIN
	)

	scheduleFadeDestroy(shard, S.SHARD_LIFE, S.SHARD_FADE_TIME)
end

local function tweenAllTransparency(root: Instance, target: number, time: number)
	local function apply(d: Instance)
		if d:IsA("BasePart") then
			if time <= 0 then d.Transparency = target
			else TweenService:Create(d, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = target}):Play() end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			if time <= 0 then d.Transparency = target
			else TweenService:Create(d, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = target}):Play() end
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			pcall(function()
				if time <= 0 then d.Brightness = 0
				else TweenService:Create(d, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Brightness = 0}):Play() end
			end)
		end
	end
	apply(root)
	for _, d in ipairs(root:GetDescendants()) do
		apply(d)
	end
end

local function setAllAnchored(root: Instance, anchored: boolean)
	local function setOne(d: Instance)
		if d:IsA("BasePart") then
			d.Anchored = anchored
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	setOne(root)
	for _, d in ipairs(root:GetDescendants()) do
		setOne(d)
	end
end

local function cloneToImpact(meteor: Model, inst: Instance, impactPivot: CFrame): Instance?
	if not inst or not inst.Parent then return nil end

	local mp = meteor:GetPivot()
	local offset: CFrame
	if inst:IsA("Model") then
		offset = mp:ToObjectSpace(inst:GetPivot())
	else
		local bp = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
		if not bp then return nil end
		offset = mp:ToObjectSpace(bp.CFrame)
	end

	local c = inst:Clone()
	c.Parent = workspace

	if c:IsA("Model") then
		c:PivotTo(impactPivot * offset)
	else
		local bp = c:IsA("BasePart") and c or c:FindFirstChildWhichIsA("BasePart", true)
		if not bp then c:Destroy() return nil end
		bp.CFrame = impactPivot * offset
	end

	setAllAnchored(c, true)
	return c
end

local function fxBaseSize(fx: Instance): Vector3
	if fx:IsA("Model") then
		return fx:GetExtentsSize()
	end
	local bp = fx:IsA("BasePart") and fx or fx:FindFirstChildWhichIsA("BasePart", true)
	return bp and bp.Size or Vector3.new(4, 4, 4)
end

local function setScale(inst: Instance, scale: number)
	if inst:IsA("Model") then
		pcall(function() inst:ScaleTo(scale) end)
	else
		local bp = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
		if not bp then return end
		local base = bp:GetAttribute("__BaseSize")
		if typeof(base) ~= "Vector3" then
			bp:SetAttribute("__BaseSize", bp.Size)
			base = bp.Size
		end
		bp.Size = (base :: Vector3) * scale
	end
end

local function easeOutQuad(t: number): number
	t = math.clamp(t, 0, 1)
	local u = 1 - t
	return 1 - (u * u)
end

local function explosionScaleAt(e: number, startScale: number, burstScale: number, burstTime: number, driftScale: number, driftTime: number): number
	if burstTime > 0 and e <= burstTime then
		return startScale + (burstScale - startScale) * easeOutQuad(e / burstTime)
	end
	if driftTime <= 0 then
		return driftScale
	end
	local e2 = e - math.max(0, burstTime)
	local a2 = math.clamp(e2 / driftTime, 0, 1)
	return burstScale + (driftScale - burstScale) * easeOutQuad(a2)
end

local function anyBasePart(inst: Instance?): BasePart?
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function buildHumanoidCandidatesAll(attackerHum: Humanoid): {[Humanoid]: BasePart}
	local candidates: {[Humanoid]: BasePart} = {}

	-- NPCs in workspace
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Humanoid") then
			local h = inst
			if h ~= attackerHum and h.Health > 0 then
				local root = getHumanoidRoot(h)
				if root then
					candidates[h] = root
				end
			end
		end
	end

	-- Players (extra-safe)
	for _, plr in ipairs(Players:GetPlayers()) do
		local _, h, hrp = getAlive(plr)
		if h and hrp and h ~= attackerHum and h.Health > 0 then
			candidates[h] = hrp
		end
	end

	return candidates
end


local function applyRingDamageToCandidates(
	center: Vector3,
	blastR: number,
	outerR: number,
	attackerHum: Humanoid,
	hitMap: {[Humanoid]: boolean},
	candidates: {[Humanoid]: BasePart}
)
	local hits = 0
	local candCount = 0

	for h, root in pairs(candidates) do
		candCount += 1
		if h.Health > 0 and h ~= attackerHum and not hitMap[h] then
			local d = (root.Position - center).Magnitude
			local dmg = 0
			if blastR > 0 and d <= blastR then
				dmg = S.BLAST_DAMAGE
			elseif outerR > 0 and d <= outerR then
				dmg = S.OUTER_DAMAGE
			end

			if dmg > 0 then
				hitMap[h] = true
				h:TakeDamage(dmg)
				hits += 1
				dbgDamage("hit", h.Parent and h.Parent.Name or tostring(h), "d=", math.floor(d*10)/10, "dmg=", dmg, "blastR=", math.floor(blastR*10)/10, "outerR=", math.floor(outerR*10)/10)
			end
		end
	end

	if S.DEBUG and S.DEBUG_DAMAGE and S.DEBUG_DAMAGE_VERBOSE and hits == 0 then
		dbgDamage("tick no hits; candidates=", candCount, "blastR=", math.floor(blastR*10)/10, "outerR=", math.floor(outerR*10)/10)
	end
end

local function disableInnerFX(meteor: Model)
	if S.EXPLOSION_DISABLE_INNER_SHOCKWAVE then
		local shock = meteor:FindFirstChild("Shockwave", true)
		if shock and shock:IsA("ParticleEmitter") then shock.Enabled = false end
	end
	if S.EXPLOSION_FIRE_SPHERE then
		local fire = meteor:FindFirstChild("Fire", true)
		if fire and fire:IsA("ParticleEmitter") then
			pcall(function() fire.Shape = Enum.ParticleEmitterShape.Sphere end)
		end
	end
end

local function prepImpactExplosion(meteor: Model, impactPos: Vector3): (Instance?, Instance?)
	if not S.EXPLOSION_ENABLED then return nil, nil end

	disableInnerFX(meteor)

	local mp = meteor:GetPivot()
	local rotOnly = mp - mp.Position
	local impactPivot = rotOnly + impactPos

	local blastSrc = meteor:FindFirstChild(S.EXPLOSION_BLAST_NAME, true)
	local outerSrc = meteor:FindFirstChild(S.EXPLOSION_OUTER_NAME, true)

	local blastFx = blastSrc and cloneToImpact(meteor, blastSrc, impactPivot) or nil
	local outerFx = outerSrc and cloneToImpact(meteor, outerSrc, impactPivot) or nil

	if blastFx then
		setScale(blastFx, S.EXPLOSION_BLAST_START_SCALE)
		tweenAllTransparency(blastFx, 1, 0)
	end
	if outerFx then
		setScale(outerFx, S.EXPLOSION_OUTER_START_SCALE)
		tweenAllTransparency(outerFx, 1, 0)
	end

	return blastFx, outerFx
end

local function runExplosionAndDamage(blastFx: Instance?, outerFx: Instance?, center: Vector3, attackerHum: Humanoid)
	local hitOnce: {[Humanoid]: boolean} = {}

	-- Always collect humanoids (don’t radius-pre-filter)
	local candidates = buildHumanoidCandidatesAll(attackerHum)
	if S.DEBUG and S.DEBUG_DAMAGE then
		local candCount = 0
		for _ in pairs(candidates) do candCount += 1 end
		dbgDamage("explosion humanoids found(total)=", candCount, "blastFx=", blastFx ~= nil, "outerFx=", outerFx ~= nil)
	end

	-- Base radii come from FX extents IF they exist, otherwise fall back to 1 (so mins still apply)
	local blastBaseR = 1
	local outerBaseR = 1
	if blastFx and blastFx.Parent then
		local base = fxBaseSize(blastFx)
		blastBaseR = math.max(1, 0.5 * math.max(base.X, base.Y, base.Z))
	end
	if outerFx and outerFx.Parent then
		local base = fxBaseSize(outerFx)
		outerBaseR = math.max(1, 0.5 * math.max(base.X, base.Y, base.Z))
	end

	-- Show visuals if they exist
	if blastFx and blastFx.Parent then tweenAllTransparency(blastFx, 0, 0) end
	if outerFx and outerFx.Parent then tweenAllTransparency(outerFx, 0, 0) end

	local blastDuration = math.max(0, S.EXPLOSION_BLAST_BURST_TIME + S.EXPLOSION_BLAST_DRIFT_TIME + 0.10)
	local outerDuration = math.max(0, S.EXPLOSION_OUTER_BURST_TIME + S.EXPLOSION_OUTER_DRIFT_TIME + 0.10)
	local totalDuration = math.max(blastDuration, outerDuration)

	local t0 = os.clock()
	local acc = 0.0
	local step = (S.EXPLOSION_DAMAGE_HZ > 0) and (1 / S.EXPLOSION_DAMAGE_HZ) or 0

	local printedClosest = false

	local con: RBXScriptConnection?
	con = RunService.Heartbeat:Connect(function(dt)
		local e = os.clock() - t0
		if e >= totalDuration then
			if con then con:Disconnect() end
			return
		end

		-- Compute scales (even if visuals are nil)
		local blastScale = 0
		local outerScale = 0

		if e <= blastDuration then
			blastScale = explosionScaleAt(
				e,
				S.EXPLOSION_BLAST_START_SCALE,
				S.EXPLOSION_BLAST_BURST_END_SCALE,
				S.EXPLOSION_BLAST_BURST_TIME,
				S.EXPLOSION_BLAST_DRIFT_END_SCALE,
				S.EXPLOSION_BLAST_DRIFT_TIME
			)
			if blastFx and blastFx.Parent then
				setScale(blastFx, blastScale)
			end
		end

		if e <= outerDuration then
			outerScale = explosionScaleAt(
				e,
				S.EXPLOSION_OUTER_START_SCALE,
				S.EXPLOSION_OUTER_BURST_END_SCALE,
				S.EXPLOSION_OUTER_BURST_TIME,
				S.EXPLOSION_OUTER_DRIFT_END_SCALE,
				S.EXPLOSION_OUTER_DRIFT_TIME
			)
			if outerFx and outerFx.Parent then
				setScale(outerFx, outerScale)
			end
		end

		-- Radii ALWAYS exist via mins (this is the key)
		local blastR = 0
		local outerR = 0

		-- Use FIXED radii (not FX size)
		if e <= blastDuration then
			blastR = math.max(S.BLAST_RADIUS_MIN, S.BLAST_RADIUS_FIXED * S.BLAST_RADIUS_MULT)
		end
		if e <= outerDuration then
			outerR = math.max(S.OUTER_RADIUS_MIN, S.OUTER_RADIUS_FIXED * S.OUTER_RADIUS_MULT)
		end
		
		-- One-time debug: closest target distance vs radii
		if S.DEBUG and S.DEBUG_DAMAGE and (not printedClosest) then
			printedClosest = true
			local bestName, bestD = "none", math.huge
			for h, root in pairs(candidates) do
				local d = (root.Position - center).Magnitude
				if d < bestD then
					bestD = d
					bestName = h.Parent and h.Parent.Name or tostring(h)
				end
			end
			dbgDamage("closest=", bestName, "d=", math.floor(bestD*10)/10, "blastR(min/cur)=", S.BLAST_RADIUS_MIN, math.floor(blastR*10)/10, "outerR(min/cur)=", S.OUTER_RADIUS_MIN, math.floor(outerR*10)/10)
		end

		-- Apply ring damage by distance (no collision involved)
		if (S.BLAST_DAMAGE > 0 or S.OUTER_DAMAGE > 0) and (blastR > 0 or outerR > 0) then
			if step <= 0 then
				applyRingDamageToCandidates(center, blastR, outerR, attackerHum, hitOnce, candidates)
			else
				acc += dt
				if acc >= step then
					acc = 0
					applyRingDamageToCandidates(center, blastR, outerR, attackerHum, hitOnce, candidates)
				end
			end
		end
	end)

	-- Fade visuals if they exist
	if blastFx and blastFx.Parent then
		local fadeAt = S.EXPLOSION_BLAST_BURST_TIME + S.EXPLOSION_FADE_DELAY
		task.delay(math.max(0, fadeAt), function()
			if blastFx and blastFx.Parent then
				tweenAllTransparency(blastFx, 1, S.EXPLOSION_BLAST_FADE_TIME)
			end
		end)
		local life = math.max(S.EXPLOSION_BLAST_BURST_TIME + S.EXPLOSION_BLAST_DRIFT_TIME, fadeAt + S.EXPLOSION_BLAST_FADE_TIME) + 0.2
		Debris:AddItem(blastFx, life)
	end

	if outerFx and outerFx.Parent then
		local fadeAt = S.EXPLOSION_OUTER_BURST_TIME + S.EXPLOSION_FADE_DELAY
		task.delay(math.max(0, fadeAt), function()
			if outerFx and outerFx.Parent then
				tweenAllTransparency(outerFx, 1, S.EXPLOSION_OUTER_FADE_TIME)
			end
		end)
		local life = math.max(S.EXPLOSION_OUTER_BURST_TIME + S.EXPLOSION_OUTER_DRIFT_TIME, fadeAt + S.EXPLOSION_OUTER_FADE_TIME) + 0.2
		Debris:AddItem(outerFx, life)
	end
end

local function spawnGroundCubes(center: Vector3, pavement: Instance?)
	if not S.GROUND_CUBES_ENABLED then return end
	if S.GROUND_CUBES_COUNT <= 0 then return end

	local ref = anyBasePart(pavement)
	local color = ref and ref.Color or Color3.fromRGB(120, 120, 120)
	local material = ref and ref.Material or Enum.Material.Concrete
	local refl = ref and ref.Reflectance or 0
	local variant = (ref and ref.MaterialVariant) or ""

	for i = 1, S.GROUND_CUBES_COUNT do
		local size = S.GROUND_CUBES_SIZE_MIN + math.random() * (S.GROUND_CUBES_SIZE_MAX - S.GROUND_CUBES_SIZE_MIN)

		local ang = math.random() * math.pi * 2
		local r = S.GROUND_CUBES_RADIUS_MIN + math.random() * (S.GROUND_CUBES_RADIUS_MAX - S.GROUND_CUBES_RADIUS_MIN)

		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		dir = (dir + Vector3.new((math.random() - 0.5) * 0.50, 0, (math.random() - 0.5) * 0.50))
		if dir.Magnitude < 0.001 then dir = Vector3.new(1, 0, 0) end
		dir = dir.Unit

		local spawnPos = center + dir * r + Vector3.new(0, -S.GROUND_CUBES_SPAWN_DEPTH, 0)

		local p = Instance.new("Part")
		p.Name = "MeteorCube"
		p.Size = Vector3.new(size, size, size)
		p.CFrame = CFrame.new(spawnPos) * CFrame.Angles(math.random() * math.pi * 2, math.random() * math.pi * 2, math.random() * math.pi * 2)
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = false

		p.Color = color
		p.Material = material
		p.Reflectance = refl
		if variant ~= "" then p.MaterialVariant = variant end

		p.Parent = workspace

		local outSpeed = (S.GROUND_CUBES_OUT_SPEED_MIN + math.random() * (S.GROUND_CUBES_OUT_SPEED_MAX - S.GROUND_CUBES_OUT_SPEED_MIN)) * S.GROUND_CUBES_OUT_FORCE_MULT
		local upSpeed = (S.GROUND_CUBES_UP_SPEED_MIN + math.random() * (S.GROUND_CUBES_UP_SPEED_MAX - S.GROUND_CUBES_UP_SPEED_MIN)) * S.GROUND_CUBES_UP_FORCE_MULT

		local tangent = Vector3.new(-dir.Z, 0, dir.X)
		local tangKick = (math.random() - 0.5) * 60
		local desiredVel = (dir * outSpeed) + (tangent * tangKick) + Vector3.new(0, upSpeed, 0)

		p.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * S.GROUND_CUBES_SPIN,
			(math.random() - 0.5) * S.GROUND_CUBES_SPIN,
			(math.random() - 0.5) * S.GROUND_CUBES_SPIN
		)

		p.AssemblyLinearVelocity = desiredVel
		task.defer(function()
			if p and p.Parent then
				p.AssemblyLinearVelocity = desiredVel
				p:ApplyImpulse(desiredVel * p.AssemblyMass)
			end
		end)

		task.delay(0.06, function()
			if p and p.Parent then
				p.CanCollide = S.GROUND_CUBES_COLLIDE
			end
		end)

		dbgCubes("cube", i, "vel", math.floor(desiredVel.Magnitude))

		scheduleFadeDestroy(p, S.GROUND_CUBES_LIFE, S.GROUND_CUBES_FADE_TIME)
	end
end

local function spawnMeteor(player: Player, shotId: any): boolean
	local char, hum, hrp = getAlive(player)
	if not char or not hum or not hrp then return false end
	if not canUse(player) then return false end
	if not (METEOR_TEMPLATE and METEOR_TEMPLATE:IsA("Model")) then return false end

	local pavement = findPavement()

	local fwd = flatForward(hrp)
	local right = Vector3.new(fwd.Z, 0, -fwd.X)

	local basePos = hrp.Position + fwd * S.FORWARD_DIST
	local targetPos = getTargetOnPavement(pavement, basePos)

	local startPos = targetPos
		+ Vector3.new(0, S.ENTRY_HEIGHT, 0)
	- fwd * S.APPROACH_BACK
		+ right * S.APPROACH_SIDE

	local travel = targetPos - startPos
	if travel.Magnitude < 0.01 then return false end
	local travelDir = travel.Unit
	local totalDist = travel.Magnitude
	local traveled = 0.0

	local meteor = METEOR_TEMPLATE:Clone()
	meteor.Name = "MeteorShot"
	meteor:SetAttribute("OwnerUserId", player.UserId)
	if typeof(shotId) == "string" then meteor:SetAttribute("ShotId", shotId) end
	meteor.Parent = workspace

	abilityPredict:FireAllClients("MeteorCast")

	local hitbox = pickHitbox(meteor)
	if not hitbox then
		meteor:Destroy()
		return false
	end

	ensurePrimaryPart(meteor)
	setMeteorParts(meteor, hitbox)

	local rotCF = cfWithDown(Vector3.zero, travelDir, fwd)
	local pivot = rotCF + startPos
	meteor:PivotTo(pivot)

	local hitboxOffset = meteor:GetPivot():ToObjectSpace(hitbox.CFrame)
	local lastHitboxCF = meteor:GetPivot() * hitboxOffset

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = pavement and { meteor, pavement } or { meteor }
	pcall(function() overlap.MaxParts = S.HIT_SCAN_MAX_PARTS end)

	Debris:AddItem(meteor, S.LIFE)

	local impacted = false
	local buryStopAt = 0.0
	local impactPosSaved: Vector3? = nil
	local preppedBlastFx: Instance? = nil
	local preppedOuterFx: Instance? = nil
	local played = false

	local meteorHit: {[Humanoid]: boolean} = {}

	type Emitter = {src: BasePart, area: number, pts: {Vector3}, dirs: {Vector3}, idx: number}
	local emitByPart: {[BasePart]: Emitter} = {}
	local emitList: {Emitter} = {}
	local emitRR = 0

	local lastAreaAt: {[BasePart]: number} = {}
	local spawnAcc = 0.0
	local shardsTotal = 0

	local function addEmitterPoint(p: BasePart, hitCF: CFrame)
		local hx = hitbox.Size.X * 0.5
		local hy = hitbox.Size.Y * 0.5
		local hz = hitbox.Size.Z * 0.5

		local rp =
			hitCF.Position
			+ hitCF.RightVector * ((math.random() - 0.5) * 2 * hx)
			+ hitCF.UpVector * ((math.random() - 0.5) * 2 * hy)
			+ hitCF.LookVector * ((math.random() - 0.5) * 2 * hz)

		local cp = closestPointOnOBB(p, rp)

		local v = (cp - hitCF.Position)
		if v.Magnitude < 0.05 then
			local a = math.random() * math.pi * 2
			v = Vector3.new(math.cos(a), 0, math.sin(a))
		end
		local outDir = v.Unit

		local e = emitByPart[p]
		if not e then
			e = {src = p, area = 0, pts = {}, dirs = {}, idx = 1}
			emitByPart[p] = e
			emitList[#emitList + 1] = e
		end

		local pts = e.pts
		local dirs = e.dirs
		if #pts >= S.MAX_POINTS_PER_PART then
			table.remove(pts, 1)
			table.remove(dirs, 1)
			if e.idx > 1 then e.idx -= 1 end
		end
		pts[#pts + 1] = cp
		dirs[#dirs + 1] = outDir

		local aHit = projectedAreaFromSize(hitbox.Size, hitCF:VectorToObjectSpace(travelDir))
		local add = aHit * S.AREA_MULT

		local now = os.clock()
		local last = lastAreaAt[p] or 0
		if (now - last) < S.HIT_REPEAT_COOLDOWN then
			add *= S.HIT_REPEAT_MULT
		else
			lastAreaAt[p] = now
		end

		e.area += add
	end

	local function scanAt(hitCF: CFrame)
		if S.MAX_SHARDS_TOTAL > 0 and shardsTotal >= S.MAX_SHARDS_TOTAL then return end

		local parts = workspace:GetPartBoundsInBox(hitCF, hitbox.Size, overlap)
		for _, p in ipairs(parts) do
			if not p or not p.Parent then continue end
			if not p:IsA("BasePart") then continue end
			if p.Name == S.PAVEMENT_NAME then continue end

			local h = findHumanoidFromHit(p)
			if h and h ~= hum and h.Health > 0 then
				if not meteorHit[h] then
					meteorHit[h] = true
					h:TakeDamage(S.METEOR_HIT_DAMAGE)
					dbgDamage("meteor direct hit", h.Parent and h.Parent.Name or tostring(h), "dmg=", S.METEOR_HIT_DAMAGE)
				end
				continue
			end

			if S.SHARDS_SKIP_TRUSS and p:IsA("TrussPart") then
				dbgShards("skip truss emitter", p:GetFullName())
				continue
			end

			if not isCrushable(p) then continue end
			addEmitterPoint(p, hitCF)
		end
	end

	local function pruneEmitters()
		local i = 1
		while i <= #emitList do
			local e = emitList[i]
			if (not e.src) or (not e.src.Parent) or (#e.pts == 0) or (e.area <= (S.SHARD_SIZE_MIN * S.SHARD_SIZE_MIN * 0.5)) then
				if e.src then emitByPart[e.src] = nil end
				table.remove(emitList, i)
				if emitRR > #emitList then emitRR = 0 end
			else
				i += 1
			end
		end
	end

	local function spawnFromEmitters(dt: number)
		if #emitList == 0 then return end
		if S.MAX_SHARDS_TOTAL > 0 and shardsTotal >= S.MAX_SHARDS_TOTAL then return end

		spawnAcc += dt * S.SHARDS_PER_SECOND

		local spawnedThisFrame = 0
		local minCost = S.SHARD_SIZE_MIN * S.SHARD_SIZE_MIN

		while spawnAcc >= 1.0 do
			if spawnedThisFrame >= S.MAX_SHARDS_PER_FRAME then break end
			if S.MAX_SHARDS_TOTAL > 0 and shardsTotal >= S.MAX_SHARDS_TOTAL then break end
			if #emitList == 0 then break end

			emitRR += 1
			if emitRR > #emitList then emitRR = 1 end
			local e = emitList[emitRR]
			if not e or not e.src or not e.src.Parent then
				pruneEmitters()
				spawnAcc -= 1.0
				continue
			end

			if e.area < minCost or #e.pts == 0 then
				pruneEmitters()
				spawnAcc -= 1.0
				continue
			end

			local sizeWanted = S.SHARD_SIZE_MIN + (math.random() * (S.SHARD_SIZE_MAX - S.SHARD_SIZE_MIN))
			local cost = sizeWanted * sizeWanted

			if cost > e.area then
				local fit = math.sqrt(e.area)
				fit = math.clamp(fit, S.SHARD_SIZE_MIN, S.SHARD_SIZE_MAX)
				sizeWanted = fit
				cost = sizeWanted * sizeWanted
				if cost > e.area then
					e.area = 0
					pruneEmitters()
					spawnAcc -= 1.0
					continue
				end
			end

			if e.idx > #e.pts then e.idx = 1 end
			local pos = e.pts[e.idx]
			local outDir = e.dirs[e.idx]
			e.idx += 1

			spawnShard(e.src, pos, outDir, sizeWanted)
			e.area -= cost
			shardsTotal += 1

			spawnAcc -= 1.0
			spawnedThisFrame += 1
		end

		if spawnedThisFrame > 0 then
			pruneEmitters()
		end
	end

	local alive = true
	local conn: RBXScriptConnection?

	local function doBuryNow()
		if not alive then return end
		alive = false
		if conn then conn:Disconnect() end

		if S.BURY_EXTRA_DOWN ~= 0 then
			local p = pivot.Position + Vector3.new(0, -S.BURY_EXTRA_DOWN, 0)
			pivot = (rotCF + p)
			meteor:PivotTo(pivot)
		end

		meteor:SetAttribute("Buried", true)

		if S.EXPLOSION_PLAY_ON_BURY and not played and impactPosSaved then
			played = true
			runExplosionAndDamage(preppedBlastFx, preppedOuterFx, impactPosSaved, hum)
			spawnGroundCubes(impactPosSaved, pavement)
		end

		if S.HIDE_ON_BURY then
			hideMeteor(meteor)
		end

		if S.AUTO_DESTROY and S.UNDERGROUND_LINGER >= 0 then
			task.delay(S.UNDERGROUND_LINGER, function()
				if meteor and meteor.Parent then
					meteor:Destroy()
				end
			end)
		end
	end

	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		if not meteor.Parent then
			alive = false
			if conn then conn:Disconnect() end
			return
		end

		if impacted then
			spawnFromEmitters(dt)
			if os.clock() >= buryStopAt then
				doBuryNow()
			end
			return
		end

		local step = S.SPEED * dt
		local remaining = totalDist - traveled
		local reach = (step >= remaining)

		local nextPos: Vector3
		if reach then
			nextPos = targetPos
			step = remaining
			traveled = totalDist
		else
			traveled += step
			nextPos = pivot.Position + travelDir * step
		end

		local nextPivot = (rotCF + nextPos)
		local nextHitboxCF = nextPivot * hitboxOffset
		local moveVec = nextHitboxCF.Position - lastHitboxCF.Position

		local minDim = math.max(1, math.min(hitbox.Size.X, hitbox.Size.Y, hitbox.Size.Z))
		local samples = math.max(1, math.ceil(moveVec.Magnitude / (minDim * 0.6)))
		if samples > S.MAX_SWEEP_SAMPLES then samples = S.MAX_SWEEP_SAMPLES end

		for i = 1, samples do
			local a = i / samples
			local cf = lastHitboxCF:Lerp(nextHitboxCF, a)
			scanAt(cf)
		end

		spawnFromEmitters(dt)

		pivot = nextPivot
		meteor:PivotTo(pivot)
		lastHitboxCF = nextHitboxCF

		if reach then
			impacted = true
			impactPosSaved = targetPos
			buryStopAt = os.clock() + S.BURY_TIME

			abilityPredict:FireAllClients("MeteorImpact")

			if S.EXPLOSION_ENABLED then
				preppedBlastFx, preppedOuterFx = prepImpactExplosion(meteor, impactPosSaved)
				if not S.EXPLOSION_PLAY_ON_BURY then
					runExplosionAndDamage(preppedBlastFx, preppedOuterFx, impactPosSaved, hum)
					spawnGroundCubes(impactPosSaved, pavement)
				end
			end

			if S.BURY_TIME <= 0 then
				doBuryNow()
			end
		end
	end)

	return true
end

local Meteor = {}

function Meteor.Cast(player: Player, shotId: any, originPos: any, aimPos: any, originCF: any)
	return spawnMeteor(player, shotId)
end

return Meteor