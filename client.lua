local points = {}
local isSelecting = false
local cam = nil
local targetPoint = nil

local config = {
    controls = {
        lookUp = 32,       -- W
        lookDown = 33,     -- S

        rollLeft = 45,     -- R
        rollRight = 23,    -- F

        zoomIn = 15,       -- Mouse wheel up
        zoomOut = 14,      -- Mouse wheel down

        moveForward = 32,  -- W
        moveBack = 33,     -- S
        moveLeft = 34,     -- A
        moveRight = 35,    -- D
        moveUp = 44,       -- Q
        moveDown = 38,     -- E

        speedUp = 21,      -- Left Shift
        slowDown = 19,     -- Left Alt

        placeMarker = 22,  -- Space
        finishZone = 73,   -- X
        cancelZone = 200,  -- ESC
    },

    speeds = {
        slow = 0.1,
        normal = 0.5,
        fast = 2.0
    },

    sensitivity = {
        mouse = 8.0,
        keyboard = 3.0
    }
}

local cameraData = {
    position = vector3(0, 0, 0),
    rotation = vector3(0, 0, 0),
    fov = 45.0,
    currentSpeed = config.speeds.normal
}

function CancelSelection()
    lib.notify({ title = 'Cancelado', description = 'Creación de zona cancelada', type = 'error' })
    CleanupResources()
end

function CleanupResources()
    if cam then
        SetCamActive(cam, false)
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, true)
        cam = nil
    end

    SetPlayerControl(PlayerId(), true, 0)
    lib.hideTextUI()
    isSelecting = false
    points = {}
    targetPoint = nil
end

RegisterCommand('createzone', function()
    if not isSelecting then
        StartPointSelection()
    else
        StopPointSelection()
    end
end)

function StartPointSelection()
    CleanupResources()

    isSelecting = true
    points = {}

    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)

    cameraData.position = coords + vector3(0, 0, 2.0)
    cameraData.rotation = vector3(0, 0, heading)

    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)

    SetPlayerControl(PlayerId(), false, 0)

    lib.showTextUI(
        "[W/S] Avanzar/Retroceder  \n" ..
        "[Q/E] Subir/Bajar  \n" ..
        "[Mouse] Rotar cámara  \n" ..
        "[Shift] Aumentar velocidad  \n" ..
        "[Alt] Reducir velocidad  \n" ..
        "[ESPACIO] Marcar punto  \n" ..
        "[X] Finalizar  \n" ..
        "[ESC] Cancelar",
    { icon = 'location-dot' })


    CreateThread(function()
        while isSelecting do
            Wait(0)
            HandleCamera()
            HandleInput()
            DrawPoints()
            DrawTargetPoint()
        end
    end)
end

function RotationToDirection(rotation)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local num = math.abs(math.cos(x))

    return vector3(
        -math.sin(z) * num,
        math.cos(z) * num,
        math.sin(x)
    )
end

function GetGroundPoint(startPos, direction, maxDistance)
    local endPos = startPos + (direction * maxDistance)

    local ray = StartExpensiveSynchronousShapeTestLosProbe(startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z, 1, 0, 4)

    local retval, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(ray)

    if hit == 1 then
        return endCoords
    end

    return nil
end

function HandleCamera()
    if not cam then return end

    if IsDisabledControlPressed(0, config.controls.speedUp) then
        cameraData.currentSpeed = config.speeds.fast
    elseif IsDisabledControlPressed(0, config.controls.slowDown) then
        cameraData.currentSpeed = config.speeds.slow
    else
        cameraData.currentSpeed = config.speeds.normal
    end

    local mouseX = GetDisabledControlNormal(0, 1) * config.sensitivity.mouse
    local mouseY = GetDisabledControlNormal(0, 2) * config.sensitivity.mouse

    if mouseX ~= 0.0 or mouseY ~= 0.0 then
        cameraData.rotation = vector3(
            math.clamp(cameraData.rotation.x - mouseY, -89.0, 89.0),
            0.0,
            cameraData.rotation.z - mouseX
        )
    end

    local forward = RotationToDirection(cameraData.rotation)
    local right = vector3(
        math.cos(math.rad(cameraData.rotation.z - 90.0)),
        math.sin(math.rad(cameraData.rotation.z - 90.0)),
        0.0
    )
    local up = vector3(0.0, 0.0, 1.0)

    if IsDisabledControlPressed(0, config.controls.moveForward) then
        cameraData.position = cameraData.position + forward * cameraData.currentSpeed
    end
    if IsDisabledControlPressed(0, config.controls.moveBack) then
        cameraData.position = cameraData.position - forward * cameraData.currentSpeed
    end
    if IsDisabledControlPressed(0, config.controls.moveLeft) then
        cameraData.position = cameraData.position - right * cameraData.currentSpeed
    end
    if IsDisabledControlPressed(0, config.controls.moveRight) then
        cameraData.position = cameraData.position + right * cameraData.currentSpeed
    end
    if IsDisabledControlPressed(0, config.controls.moveUp) then
        cameraData.position = cameraData.position + up * cameraData.currentSpeed
    end
    if IsDisabledControlPressed(0, config.controls.moveDown) then
        cameraData.position = cameraData.position - up * cameraData.currentSpeed
    end

    SetCamCoord(cam, cameraData.position.x, cameraData.position.y, cameraData.position.z)
    SetCamRot(cam, cameraData.rotation.x, cameraData.rotation.y, cameraData.rotation.z, 2)

    local groundPoint = GetGroundPoint(cameraData.position, forward, 1000.0)
    if groundPoint then
        targetPoint = groundPoint
    end
end

function math.clamp(value, min, max)
    return math.min(math.max(value, min), max)
end

function HandleInput()
    if IsDisabledControlJustPressed(0, config.controls.cancelZone) then
        CancelSelection()
        return
    end

    if IsDisabledControlJustPressed(0, config.controls.placeMarker) then
        if targetPoint then
            table.insert(points, targetPoint)

            lib.notify({ title = 'Punto Marcado', description = string.format('Punto %d añadido (%.2f, %.2f, %.2f)', #points, targetPoint.x, targetPoint.y, targetPoint.z), type = 'success' })

            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
        end
    end

    if IsDisabledControlJustPressed(0, config.controls.finishZone) then
        StopPointSelection()
    end
end

function DrawTargetPoint()
    if targetPoint then
        DrawMarker(1, targetPoint.x, targetPoint.y, targetPoint.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0, 255, 0, 150, false, false, 2, false, nil, nil, false)

        local onScreen, screenX, screenY = World3dToScreen2d(targetPoint.x, targetPoint.y, targetPoint.z)
        if onScreen then
            SetTextScale(0.35, 0.35)
            SetTextFont(4)
            SetTextProportional(1)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            SetTextEntry("STRING")
            SetTextCentre(1)
            AddTextComponentString(string.format("X: %.2f\nY: %.2f\nZ: %.2f", targetPoint.x, targetPoint.y, targetPoint.z))
            DrawText(screenX, screenY)
        end
    end
end

function DrawPoints()
    for i, point in ipairs(points) do
        DrawMarker(1, point.x, point.y, point.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 255, 0, 0, 100, false, true, 2, false, nil, nil, false)

        local onScreen, screenX, screenY = World3dToScreen2d(point.x, point.y, point.z + 1.0)
        if onScreen then
            SetTextScale(0.35, 0.35)
            SetTextFont(4)
            SetTextProportional(1)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            SetTextEntry("STRING")
            SetTextCentre(1)
            AddTextComponentString(tostring(i))
            DrawText(screenX, screenY)
        end

        if i > 1 then
            local prevPoint = points[i - 1]
            DrawLine(prevPoint.x, prevPoint.y, prevPoint.z, point.x, point.y, point.z, 255, 0, 0, 255)
        end

        if i == #points and #points > 2 then
            local firstPoint = points[1]
            DrawLine(point.x, point.y, point.z, firstPoint.x, firstPoint.y, firstPoint.z, 255, 0, 0, 255)
        end
    end
end

function StopPointSelection()
    if #points < 3 then
        lib.notify({ title = 'Error', description = 'Se necesitan al menos 3 puntos para crear una zona', type = 'error' })
        return
    end

    local lowestZ = points[1].z
    for _, point in ipairs(points) do
        if point.z < lowestZ then
            lowestZ = point.z
        end
    end

    local formattedPoints = {}
    for _, point in ipairs(points) do
        table.insert(formattedPoints, vec3(point.x, point.y, lowestZ))
    end

    print('Points for ox_lib zone:')
    print('points = {')
    for _, point in ipairs(formattedPoints) do
        print(string.format('    vec3(%.2f, %.2f, %.2f),', point.x, point.y, point.z))
    end
    print('}')

    lib.notify({ title = 'Zona Completada', description = 'Los puntos han sido enviados a la consola', type = 'success' })

    CleanupResources()
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CleanupResources()
    end
end)
