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
--  CRITICAL: Hull must match collision bounds.
--  Vector(-24,-24,0) to Vector(24,24,72) = HULL_HUMAN dimensions.
--  Tall bounds (256) blocked every nav node traversal.
-- ============================================================
function ENT:Init()
    -- Match HULL_HUMAN exactly so nav mesh traversal succeeds
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

    print("[GekkoNPC] Spine4 bone idx:   ", self.GekkoSpineBone)
    print("[GekkoNPC] L_gunrack bone idx:", self.GekkoLGunBone)
    print("[GekkoNPC] R_gunrack bone idx:", self.GekkoRGunBone)
    print("[GekkoNPC] walk seq:          ", self:LookupSequence("walk"))
    print("[GekkoNPC] run seq:           ", self:LookupSequence("run"))
    print("[GekkoNPC] idle seq:          ", self:LookupSequence("idle"))
end

-- ============================================================
--  AIM BONE — pitch only
-- ============================================================
function ENT:GekkoUpdateAimAngle()
    local bone = self.GekkoSpineBone
    if not bone or bone < 0 then return end
    local enemy = self:GetEnemy()
    if not IsValid(enemy) then
        self:ManipulateBoneAngles(bone, Angle(0, 0, 0))
        return
    end
    local matrix = self:GetBoneMatrix(bone)
    if not matrix then return end
    local worldAng = (enemy:GetPos() + Vector(0, 0, 40) - matrix:GetTranslation()):Angle()
    self:ManipulateBoneAngles(bone, Angle(worldAng.p, 0, 0))
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
--  THINK — sequence driven by PlaySequence after vel change
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

    -- Drive sequence via PlaySequence (sets ACT_DO_NOT_DISTURB so engine won't override)
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
        self.GekkoLastSeq = -1  -- Let VJ handle idle normally
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
