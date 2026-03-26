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
    self.GekkoDebugT        = 0
    self.GekkoCurPitch      = 0
    -- Gun alternation: fire left then right on alternate attacks
    self.GekkoGunToggle     = false

    print("[GekkoNPC] Spine4 bone idx:   ", self.GekkoSpineBone)
    print("[GekkoNPC] L_gunrack bone idx:", self.GekkoLGunBone)
    print("[GekkoNPC] R_gunrack bone idx:", self.GekkoRGunBone)
    print("[GekkoNPC] walk seq:          ", self:LookupSequence("walk"))
    print("[GekkoNPC] run seq:           ", self:LookupSequence("run"))
    print("[GekkoNPC] idle seq:          ", self:LookupSequence("idle"))
end

-- ============================================================
--  AIM BONE — local-space pitch delta only, yaw locked to 0
--
--  ManipulateBoneAngles expects a LOCAL offset from the bone rest
--  pose. Injecting a raw world-space angle here (as the first
--  version did) puts the delta in the wrong frame the moment the
--  NPC body yaw diverges from the enemy — causing the spin-fight.
--
--  Fix: subtract the bone's own world angle from the desired world
--  angle to get a true local delta, then apply only the pitch
--  component (yaw=0 so the spine never fights the body-turn system).
-- ============================================================
function ENT:GekkoUpdateAimAngle()
    local bone = self.GekkoSpineBone
    if not bone or bone < 0 then return end

    local enemy = self:GetEnemy()
    if not IsValid(enemy) then
        self.GekkoCurPitch = self.GekkoCurPitch * 0.85
        if math.abs(self.GekkoCurPitch) < 0.1 then self.GekkoCurPitch = 0 end
        self:ManipulateBoneAngles(bone, Angle(self.GekkoCurPitch, 0, 0))
        return
    end

    local matrix = self:GetBoneMatrix(bone)
    if not matrix then return end

    local bonePos    = matrix:GetTranslation()
    local targetPos  = enemy:GetPos() + Vector(0, 0, 40)
    local desiredAng = (targetPos - bonePos):GetNormalized():Angle()
    local boneAng    = matrix:GetAngles()

    local pitchDelta = desiredAng.p - boneAng.p
    pitchDelta = ((pitchDelta + 180) % 360) - 180
    pitchDelta = math.Clamp(pitchDelta, -40, 40)

    local alpha = FrameTime() * 6
    self.GekkoCurPitch = self.GekkoCurPitch + (pitchDelta - self.GekkoCurPitch) * math.Clamp(alpha, 0, 1)

    self:ManipulateBoneAngles(bone, Angle(self.GekkoCurPitch, 0, 0))
end

-- ============================================================
--  Helper: get world position + forward direction from a bone
-- ============================================================
local function GetMuzzleData(ent, boneIdx, offset)
    if not boneIdx or boneIdx < 0 then return nil, nil end
    local matrix = ent:GetBoneMatrix(boneIdx)
    if not matrix then return nil, nil end
    local fwd = matrix:GetForward()
    local pos = matrix:GetTranslation() + fwd * offset
    return pos, fwd
end

-- ============================================================
--  THINK
--
--  PlaySequence was removed here.  It calls ResetSequence
--  internally which snaps model cycle to 0 every frame it fires,
--  creating the afterimage/convulsion effect when velocity
--  repeatedly crossed the threshold.  VJ Base drives sequences
--  correctly through TranslateActivity + AnimationTranslations
--  — let it do its job.  OnThink only handles aim + step SFX.
-- ============================================================
function ENT:OnThink()
    self:GekkoUpdateAimAngle()

    local vel = self:GetVelocity():Length()

    if CurTime() > self.GekkoDebugT then
        print(string.format(
            "[GekkoDBG] vel=%.1f seq=%d act=%d idealAct=%d moving=%s",
            vel,
            self:GetSequence(),
            self:GetActivity(),
            self:GetIdealActivity(),
            tostring(self:IsMoving())
        ))
        self.GekkoDebugT = CurTime() + 0.5
    end

    if vel > 10 and CurTime() > (self.GekkoLastStepSound or 0) + 0.38 then
        self:EmitSound("physics/metal/metal_box_impact_hard1.wav", 85, math.random(60, 75))
        self.GekkoLastStepSound = CurTime()
    end
end

-- ============================================================
--  RANGE ATTACK
--
--  Restored from original vehicle weapon_machinegun_mgs4.lua:
--  - Fires one projectile entity (ma1_proj_machinegun_lvl1) per
--    burst from the exact gun bone muzzle position + forward
--  - Alternates left/right gun per attack call (like the vehicle)
--  - Particle muzzle flash attached at bone origin
--  - Falls back to center-mass only if both bones are invalid
-- ============================================================
function ENT:OnRangeAttackExecute(status, enemy, projectile)
    if status ~= "Init" then return end
    if not SERVER then return end
    if not IsValid(enemy) then return end

    local offset = self.GekkoBarrelOffset or 28

    -- Alternate guns each attack exactly like the vehicle does
    self.GekkoGunToggle = not self.GekkoGunToggle
    local boneIdx = self.GekkoGunToggle and self.GekkoLGunBone or self.GekkoRGunBone

    local muzzlePos, muzzleFwd = GetMuzzleData(self, boneIdx, offset)

    -- Fallback: fire from chest height if bone lookup failed
    if not muzzlePos then
        muzzlePos = self:GetPos() + Vector(0, 0, 180)
        muzzleFwd = (enemy:GetPos() + Vector(0, 0, 40) - muzzlePos):GetNormalized()
    end

    -- Direction: lead toward enemy (simple direct aim for NPC)
    local aimDir = (enemy:GetPos() + Vector(0, 0, 40) - muzzlePos):GetNormalized()

    -- Spawn the same projectile the vehicle uses
    local proj = ents.Create("ma1_proj_machinegun_lvl1")
    if IsValid(proj) then
        proj:SetPos(muzzlePos)
        proj:SetAngles(aimDir:Angle())
        proj:SetOwner(self)
        proj.Player = self   -- ma2_proj uses .Player for attacker
        proj:Spawn()
        proj:Activate()
    end

    -- Muzzle flash particle at bone origin (no offset, looks right)
    local flashPos, _ = GetMuzzleData(self, boneIdx, 0)
    if flashPos then
        local eff = EffectData()
        eff:SetOrigin(flashPos)
        eff:SetNormal(muzzleFwd or aimDir)
        util.Effect("MuzzleFlash", eff)
    end

    self:EmitSound("MA1_Weapon.Machinegun1", 80, math.random(95, 105))
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
