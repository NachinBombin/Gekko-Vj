AddCSLuaFile()

ENT.Base                  = "npc_vj_creature_base"
ENT.Type                  = "ai"
ENT.PrintName             = "Gekko"
ENT.Author                = "BombinBase"
ENT.Category              = "VJ Base"
ENT.Spawnable             = true
ENT.AdminSpawnable        = true
ENT.AutomaticFrameAdvance = true
ENT.IsVJBaseSNPC          = true

ENT.Model                 = {"models/metal_gear_solid_4/enemies/gekko.mdl"}

ENT.VJ_NPC_Class          = {"CLASS_COMBINE"}
ENT.HullType              = HULL_HUMAN
ENT.StartHealth           = 1250

ENT.MovementType          = VJ_MOVETYPE_GROUND
ENT.DisableWandering      = false
ENT.IdleAlwaysWander      = true

ENT.HasSounds             = true
ENT.SoundTbl_Death        = {
    "mechassault_2/mechs/mech_explode1.ogg",
    "mechassault_2/mechs/mech_explode2.ogg",
}
ENT.SoundTbl_Alert        = {"mgs4/gekko/se_stage_mg_shadowmoses_gek_alert.wav"}
ENT.SoundTbl_Idle         = false

ENT.HasMeleeAttack                        = false
ENT.HasRangeAttack                        = true
ENT.RangeAttackProjectiles                = "obj_vj_rocket"
ENT.RangeAttackMinDistance                = 0
ENT.RangeAttackMaxDistance                = 2000
ENT.AnimTbl_RangeAttack                   = false
ENT.TimeUntilRangeAttackProjectileRelease = 0
ENT.NextRangeAttackTime                   = 2

ENT.Bleeds                = false
ENT.BloodColor            = BLOOD_COLOR_MECH
