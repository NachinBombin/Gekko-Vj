include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

-- ============================================================
--  ANIMATION TRANSLATIONS
-- ============================================================
function ENT:SetAnimationTranslations(wepHoldType)
    local walkSeq = self:LookupSequence("walk")
    local runSeq  = self:LookupSequence("run")
    local idleSeq = self:LookupSequence("idle")

    self.AnimationTranslations[ACT_IDLE]     = idleSeq
    self.AnimationTranslations[ACT_WALK]     = walkSeq
    self.AnimationTranslations[ACT_RUN]      = runSeq
    self.AnimationTranslations[ACT_WALK_AIM] = walkSeq
    self.AnimationTranslations[ACT_RUN_AIM]  = runSeq

    self.GekkoSeq_Walk = walkSeq
    self.GekkoSeq_Run  = runSeq
    self.GekkoSeq_Idle = idleSeq

    print("[GekkoNPC] AnimTrans walk->", walkSeq, "run->", runSeq, "idle->", idleSeq)
end

-- ============================================================
--  TRANSLATE ACTIVITY
-- ============================================================
function ENT:TranslateActivity(act)
    if act == ACT_WALK or act == ACT_WALK_AIM then
        return self.GekkoSeq_Walk or act
    elseif act == ACT_RUN or act == ACT_RUN_AIM then
        return self.GekkoSeq_Run or act
    elseif act == ACT_IDLE then
        return self.GekkoSeq_Idle or act
    end
    return self.BaseClass.TranslateActivity(self, act)
end

-- ============================================================
--  INIT
-- ============================================================
function ENT:Init()
    self:SetCollisionBounds(Vector(-24, -24, 0), Vector(24, 24, 72))
    self:SetSkin(1)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetSolid(SOLID_BBOX)
    self:SetGravity(1)

    self:CapabilitiesAdd(bit.bor(CAP_MOVE_GROUND, CAP_TURN_HEAD, CAP_ANIMATEDFACE))
    self:CapabilitiesRemove(CAP_MOVE_FLY)

    self.GekkoSpineBone     = self:LookupBone("b_spine4")
    self.GekkoLGunBone      = self:LookupBone("b_l_gunrack")
    self.GekkoRGunBone      = self:LookupBone("b_r_gunrack")
    self.GekkoBarrelOffset  = 28
    self.GekkoLastStepSound = 0
    self.GekkoLastSeq       = -1
    self.GekkoDebugT        = 0
    -- Smoothed local pitch stored between frames (degrees)
    self.GekkoCurPitch      = 0

    print("[GekkoNPC] Spine4 bone idx:   ", self.GekkoSpineBone)
    print("[GekkoNPC] L_gunrack bone idx:", self.GekkoLGunBone)
    print("[GekkoNPC] R_gunrack bone idx:", self.GekkoRGunBone)
    print("[GekkoNPC] walk seq:          ", self:LookupSequence("walk"))
    print("[GekkoNPC] run seq:           ", self:LookupSequence("run"))
    print("[GekkoNPC] idle seq:          ", self:LookupSequence("idle"))
end

-- ============================================================
--  AIM BONE — local-space pitch only, smoothed, yaw locked to 0
--
--  THE BUG THAT WAS HERE:
--    worldAng.p was fed directly into ManipulateBoneAngles.
--    ManipulateBoneAngles expects a LOCAL delta from the bone's
--    rest pose, not a world-space angle.  In combat the NPC body
--    yaw diverges from the enemy, so the injected world pitch
--    is in the wrong frame → the bone fights the body-turn system
--    and spins hard to the left.
--
--  FIX:
--    1. Get bone world angle from its matrix.
--    2. Compute the world-space angle we WANT the bone to face.
--    3. Subtract current bone world angle to get a LOCAL delta.
--    4. Apply ONLY the pitch component of that delta (lock yaw=0, roll=0).
--    5. Clamp and smooth so it can't snap or spiral.
-- ============================================================
function ENT:GekkoUpdateAimAngle()
    local bone = self.GekkoSpineBone
    if not bone or bone < 0 then return end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) then
        -- Decay back to rest smoothly
        self.GekkoCurPitch = self.GekkoCurPitch * 0.85
        if math.abs(self.GekkoCurPitch) < 0.1 then self.GekkoCurPitch = 0 end
        self:ManipulateBoneAngles(bone, Angle(self.GekkoCurPitch, 0, 0))
        return
    end

    local matrix = self:GetBoneMatrix(bone)
    if not matrix then return end

    -- World direction from bone to enemy eye level
    local bonePos    = matrix:GetTranslation()
    local targetPos  = enemy:GetPos() + Vector(0, 0, 40)
    local toEnemy    = (targetPos - bonePos):GetNormalized()
    local desiredAng = toEnemy:Angle()          -- world-space desired

    -- Current bone world angle
    local boneAng = matrix:GetAngles()          -- world-space current

    -- Delta in world space → extract only pitch
    local pitchDelta = desiredAng.p - boneAng.p

    -- Normalise to [-180, 180]
    pitchDelta = ((pitchDelta + 180) % 360) - 180

    -- Clamp to a sane arc (spine can't bend infinitely)
    pitchDelta = math.Clamp(pitchDelta, -40, 40)

    -- Smooth (lerp toward target at ~10°/frame equivalent)
    local alpha = FrameTime() * 6   -- tune speed here
    self.GekkoCurPitch = self.GekkoCurPitch + (pitchDelta - self.GekkoCurPitch) * math.Clamp(alpha, 0, 1)

    -- Yaw=0, Roll=0 — only pitch, no fighting the body-turn system
    self:ManipulateBoneAngles(bone, Angle(self.GekkoCurPitch, 0, 0))
end

-- ============================================================
--  Helper: barrel world position
-- ============================================================
local function GetBarrelPos(ent, boneIdx, offset)
    if not boneIdx or boneIdx < 0 then return nil end
    local matrix = ent:GetBoneMatrix(boneIdx)
    if not matrix then return nil end
    return matrix:GetTranslation() + matrix:GetForward() * offset
end

-- ============================================================
--  THINK
-- ============================================================
function ENT:OnThink()
    self:GekkoUpdateAimAngle()

    local vel    = self:GetVelocity():Length()
    local curSeq = self:GetSequence()

    if CurTime() > self.GekkoDebugT then
        print(string.format(
            "[GekkoDBG] vel=%.1f curSeq=%d curAct=%d idealAct=%d IsGoalActive=%s IsMoving=%s",
            vel, curSeq,
            self:GetActivity(),
            self:GetIdealActivity(),
            tostring(self:IsGoalActive()),
            tostring(self:IsMoving())
        ))
        self.GekkoDebugT = CurTime() + 0.5
    end

    local targetSeq
    if vel > 160 then
        targetSeq = self.GekkoSeq_Run
    elseif vel > 10 then
        targetSeq = self.GekkoSeq_Walk
    end

    if targetSeq and targetSeq ~= self.GekkoLastSeq then
        self:PlaySequence(targetSeq)
        self.GekkoLastSeq = targetSeq
        print("[GekkoDBG] PlaySequence ->", targetSeq)
    elseif not targetSeq and self.GekkoLastSeq ~= -1 and vel == 0 then
        self.GekkoLastSeq = -1
    end

    if vel > 10 and CurTime() > (self.GekkoLastStepSound or 0) + 0.38 then
        self:EmitSound("physics/metal/metal_box_impact_hard1.wav", 85, math.random(60, 75))
        self.GekkoLastStepSound = CurTime()
    end
end

-- ============================================================
--  RANGE ATTACK EXECUTE
-- ============================================================
function ENT:OnRangeAttackExecute(status, enemy, projectile)
    if status ~= "Init" then return end
    local offset = self.GekkoBarrelOffset or 28

    local function FireBurst(src)
        if not IsValid(enemy) then return end
        local dir = (enemy:GetPos() + Vector(0, 0, 40) - src):GetNormalized()
        self:FireBullets({
            Attacker   = self,
            Damage     = 8,
            Dir        = dir,
            Src        = src,
            AmmoType   = "AR2",
            TracerName = "Tracer",
            Num        = 3,
            Spread     = Vector(0.05, 0.05, 0),
        })
        local eff = EffectData()
        eff:SetOrigin(src)
        eff:SetNormal(dir)
        util.Effect("MuzzleFlash", eff)
    end

    local fired = false
    for _, boneIdx in ipairs({self.GekkoLGunBone, self.GekkoRGunBone}) do
        local pos = GetBarrelPos(self, boneIdx, offset)
        if pos then FireBurst(pos) fired = true end
    end
    if not fired then FireBurst(self:GetPos() + Vector(0, 0, 200)) end

    self:EmitSound("weapons/ar2/fire1.wav", 80, math.random(90, 110))
    return true
end

-- ============================================================
--  DEATH
-- ============================================================
function ENT:OnDeath(dmginfo, hitgroup, status)
    if status ~= "Finish" then return end
    local attacker = IsValid(dmginfo:GetAttacker()) and dmginfo:GetAttacker() or self
    local pos      = self:GetPos()
    timer.Simple(0.8, function()
        if not IsValid(self) then return end
        ParticleEffect("astw2_nightfire_explosion_generic", pos, angle_zero)
        self:EmitSound(table.Random({
            "weapons/mgs3/explosion_01.wav",
            "weapons/mgs3/explosion_02.wav",
        }), 511, 100, 2)
        util.BlastDamage(self, attacker, pos, 512, 256)
    end)
end
