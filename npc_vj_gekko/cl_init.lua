include("shared.lua")

function ENT:Draw()
    self:SetupBones()
    self:DrawModel()
end
