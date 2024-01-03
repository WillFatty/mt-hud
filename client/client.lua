local vehicleHUDActive = false
local playerHUDActive = false
local hunger = 100
local thirst = 100
local stress = 0
local seatbeltOn = false
local showSeatbelt = false
local speedMultiplier = Config.UseMPH and 2.23694 or 3.6
local vehicle = nil
local numgears = nil
local topspeedGTA = nil
local topspeedms = nil
local acc = nil
local hash = nil
local selectedgear = 0 
local hbrake = nil
local manualon = false
local incar = false
local currspeedlimit = nil
local ready = false
local realistic = false
local nos = 0
local nitroLevel = 0
local nitroActive = 0

RegisterNetEvent("QBCore:Client:OnPlayerLoaded", function()
    Wait(500)
    startHUD()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Wait(500)
    startHUD()
end)

function startHUD()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped) then DisplayRadar(false) else DisplayRadar(true) SendNUIMessage({ action = 'showVehicleHUD' }) end
    TriggerEvent('hud:client:LoadMap')
    SendNUIMessage({ action = 'showPlayerHUD' })
    playerHUDActive = true
    loadPlayerNeeds()
end

local lastCrossroadUpdate = 0
local lastCrossroadCheck = {}

function getCrossroads(vehicle)
    local updateTick = GetGameTimer()
    if updateTick - lastCrossroadUpdate > 1500 then
        local pos = GetEntityCoords(vehicle)
        local street1, street2 = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
        lastCrossroadUpdate = updateTick
        lastCrossroadCheck = { GetStreetNameFromHashKey(street1), GetStreetNameFromHashKey(street2) }
    end
    return lastCrossroadCheck
end

CreateThread(function()
    while true do
        local stamina = 0
        local playerId = PlayerId()
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if not IsPauseMenuActive() then
            if not playerHUDActive then SendNUIMessage({ action = 'showPlayerHUD' }) end
            if not IsEntityInWater(player) then stamina = (100 - GetPlayerSprintStaminaRemaining(playerId)) end
            if IsEntityInWater(player) then stamina = (GetPlayerUnderwaterTimeRemaining(playerId) * 10) end
            SendNUIMessage({
                action = 'updatePlayerHUD',
                health = (GetEntityHealth(ped) - 100),
                armor = GetPedArmour(ped),
                thirst = thirst,
                hunger = hunger,
                stamina = stamina,
                dynamicStress = stress,
                stress = stress,
                voice = LocalPlayer.state['proximity'].distance,
                talking = NetworkIsPlayerTalking(PlayerId()),
            })
            if IsPedInAnyVehicle(ped) then
                if not vehicleHUDActive then
                    vehicleHUDActive = true
                    DisplayRadar(true)
                    TriggerEvent('hud:client:LoadMap')
                    SendNUIMessage({ action = 'showVehicleHUD' })
                end
                local crossroads = getCrossroads(vehicle)
                SendNUIMessage({
                    action = 'updateVehicleHUD',
                    speed = math.ceil(GetEntitySpeed(vehicle) * Config.speedMultiplier),
                    fuel = math.ceil(GetVehicleFuelLevel(vehicle)),
                    gear = GetVehicleCurrentGear(vehicle),
                    street1 = crossroads[1],
                    street2 = crossroads[2],
                    direction = GetDirectionText(GetEntityHeading(vehicle)),
                    seatbeltOn = seatbeltOn,
                    showSeatbelt = showSeatbelt,
                    nos = nitroLevel
                })
            else if vehicleHUDActive then vehicleHUDActive = false DisplayRadar(false) SendNUIMessage({ action = 'hideVehicleHUD' }) end end
        else
            vehicleHUDActive = false
            DisplayRadar(false)
            SendNUIMessage({ action = 'hideVehicleHUD' })
            SendNUIMessage({ action = 'hidePlayerHUD' })
            playerHUDActive = false
        end
        SetBigmapActive(false, false)
        SetRadarZoom(1000)
        Wait(Config.updateDelay)
    end
end)

function GetDirectionText(heading)
    if ((heading >= 0 and heading < 45) or (heading >= 315 and heading < 360)) then
        return "N"
    elseif (heading >= 45 and heading < 135) then
        return "W"
    elseif (heading >=135 and heading < 225) then
        return "S"
    elseif (heading >= 225 and heading < 315) then
        return "E"
    end
end

RegisterNetEvent('hud:client:UpdateNeeds', function(newHunger, newThirst)
    thirst = newThirst
    hunger = newHunger
end)

RegisterNetEvent("hud:client:LoadMap", function()
    Wait(100)
    local defaultAspectRatio = 1920/1080
    local resolutionX, resolutionY = GetActiveScreenResolution()
    local safezone = GetSafeZoneSize()
    local aspectRatio = (resolutionX-(safezone/2))/(resolutionY-(safezone/2))
    local minimapOffset = 0
    if aspectRatio > defaultAspectRatio then minimapOffset = ((defaultAspectRatio-aspectRatio)/3.6)-0.019 end
    RequestStreamedTextureDict("squaremap", false)
    if not HasStreamedTextureDictLoaded("squaremap") then Wait(150) end
    SetMinimapClipType(0)
    AddReplaceTexture("platform:/textures/graphics", "radarmasksm", "squaremap", "radarmasksm")
    AddReplaceTexture("platform:/textures/graphics", "radarmask1g", "squaremap", "radarmasksm")
    SetMinimapComponentPosition('minimap', 'L', 'B', 0.0 + minimapOffset, -0.047, 0.1638, 0.183)
    SetMinimapComponentPosition("minimap_mask", "L", "B", 0.0 + minimapOffset, 0.0, 0.128, 0.20)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.00 + minimapOffset, 0.065, 0.252, 0.338)
    SetBlipAlpha(GetNorthRadarBlip(), 0)
    SetMinimapClipType(0)
    SetRadarBigmapEnabled(true, false)
    Wait(50)
    SetRadarBigmapEnabled(false, false)
end)

RegisterNetEvent('hud:client:UpdateStress', function(newStress) -- Add this event with adding stress elsewhere
    stress = newStress
end)

CreateThread(function() -- Speeding
    while true do
        if LocalPlayer.state.isLoggedIn then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                local vehClass = GetVehicleClass(veh)
                local speed = GetEntitySpeed(veh) * speedMultiplier
                local vehHash = GetEntityModel(veh)
                if Config.VehClassStress[tostring(vehClass)] and not Config.WhitelistedVehicles[vehHash] then
                    local stressSpeed
                    if vehClass == 8 then -- Motorcycle exception for seatbelt
                        stressSpeed = Config.MinimumSpeed
                    else
                        stressSpeed = seatbeltOn and Config.MinimumSpeed or Config.MinimumSpeedUnbuckled
                    end
                    if speed >= stressSpeed then
                        TriggerServerEvent('hud:server:GainStress', math.random(1, 3))
                    end
                end
            end
        end
        Wait(10000)
    end
end)

-- Stress Screen Effects

local function GetBlurIntensity(stresslevel)
    for _, v in pairs(Config.Intensity['blur']) do
        if stresslevel >= v.min and stresslevel <= v.max then
            return v.intensity
        end
    end
    return 1500
end

local function GetEffectInterval(stresslevel)
    for _, v in pairs(Config.EffectInterval) do
        if stresslevel >= v.min and stresslevel <= v.max then
            return v.timeout
        end
    end
    return 60000
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local effectInterval = GetEffectInterval(stress)
        if stress >= 100 then
            local BlurIntensity = GetBlurIntensity(stress)
            local FallRepeat = math.random(2, 4)
            local RagdollTimeout = FallRepeat * 1750
            TriggerScreenblurFadeIn(1000.0)
            Wait(BlurIntensity)
            TriggerScreenblurFadeOut(1000.0)

            if not IsPedRagdoll(ped) and IsPedOnFoot(ped) and not IsPedSwimming(ped) then
                SetPedToRagdollWithFall(ped, RagdollTimeout, RagdollTimeout, 1, GetEntityForwardVector(ped), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
            end

            Wait(1000)
            for _ = 1, FallRepeat, 1 do
                Wait(750)
                DoScreenFadeOut(200)
                Wait(1000)
                DoScreenFadeIn(200)
                TriggerScreenblurFadeIn(1000.0)
                Wait(BlurIntensity)
                TriggerScreenblurFadeOut(1000.0)
            end
        elseif stress >= Config.MinimumStress then
            local BlurIntensity = GetBlurIntensity(stress)
            TriggerScreenblurFadeIn(1000.0)
            Wait(BlurIntensity)
            TriggerScreenblurFadeOut(1000.0)
        end
        Wait(effectInterval)
    end
end)

-- seatbelt

RegisterNetEvent('hud:client:ToggleShowSeatbelt', function()
    showSeatbelt = not showSeatbelt
end)

RegisterNetEvent('seatbelt:client:ToggleSeatbelt', function() -- Triggered in smallresources
    seatbeltOn = not seatbeltOn
end)
