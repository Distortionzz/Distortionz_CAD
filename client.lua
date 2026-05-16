-- =====================================================================
--  Distortionz CAD - Client
--  Opens the MDT NUI (police only), proxies NUI <-> server callbacks,
--  draws dispatch call blips, sets waypoints on attach.
-- =====================================================================

local cadOpen   = false
local callBlips = {}

local function DebugPrint(message)
    if Config.Debug then
        print(('[%s:client] %s'):format(Config.ResourceName, message))
    end
end

-- ─── Notify wrapper ─────────────────────────────────────────────────

local function Notify(message, status, duration)
    status   = status or 'info'
    duration = duration or 5000

    if Config.Notify.useDistortionzNotify and GetResourceState('distortionz_notify') == 'started' then
        local ok = pcall(function()
            exports['distortionz_notify']:Notify(message, status, duration)
        end)
        if ok then return end
        ok = pcall(function()
            exports['distortionz_notify']:Send(message, status, duration)
        end)
        if ok then return end
        ok = pcall(function()
            TriggerEvent('distortionz_notify:client:notify', message, status, duration)
        end)
        if ok then return end
    end

    lib.notify({
        title       = Config.Notify.title,
        description = message,
        type        = status,
        duration    = duration,
    })
end

RegisterNetEvent('distortionz_cad:client:notify', function(message, status, duration)
    Notify(message, status, duration)
end)

-- ─── Call blips ─────────────────────────────────────────────────────

local function clearCallBlips()
    for _, b in pairs(callBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    callBlips = {}
end

local function refreshCallBlips(callList)
    clearCallBlips()
    if not callList then return end
    for _, c in ipairs(callList) do
        if c.coords and c.coords.x then
            local b = AddBlipForCoord(c.coords.x, c.coords.y, c.coords.z)
            SetBlipSprite(b, Config.Dispatch.blipSprite)
            SetBlipColour(b, Config.Dispatch.blipColour)
            SetBlipScale(b, Config.Dispatch.blipScale)
            SetBlipAsShortRange(b, false)
            if Config.Dispatch.autoBlink and c.priority == 1 then
                SetBlipFlashes(b, true)
            end
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(('[%s] %s'):format(c.code, c.label))
            EndTextCommandSetBlipName(b)
            callBlips[#callBlips + 1] = b
        end
    end
end

RegisterNetEvent('distortionz_cad:client:dispatch', function(snapshot)
    refreshCallBlips(snapshot and snapshot.calls)
    if cadOpen then
        SendNUIMessage({ action = 'dispatch', data = snapshot })
    end
end)

-- ─── Open / close ───────────────────────────────────────────────────

local function OpenCad()
    if cadOpen then return end
    local boot = lib.callback.await('distortionz_cad:server:bootstrap', false)
    if not boot or not boot.ok then
        Notify('Access denied — law enforcement only.', 'error', 4000)
        return
    end
    cadOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = boot })
end

local function CloseCad()
    if not cadOpen then return end
    cadOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterCommand(Config.Access.command, OpenCad, false)

if Config.Access.keybind and Config.Access.keybind ~= '' then
    RegisterKeyMapping(Config.Access.command, 'Open CAD / MDT', 'keyboard', Config.Access.keybind)
end

if Config.Access.item then
    RegisterNetEvent('distortionz_cad:client:openItem', OpenCad)
end

-- ─── NUI callbacks (proxy to server) ────────────────────────────────

local function proxy(name, serverCb)
    RegisterNUICallback(name, function(payload, cb)
        local res = lib.callback.await(serverCb, false, payload and payload.data)
        cb(res or { ok = false })
    end)
end

RegisterNUICallback('close', function(_, cb)
    CloseCad()
    cb({ ok = true })
end)

RegisterNUICallback('waypoint', function(payload, cb)
    local c = payload and payload.coords
    if c and c.x then
        SetNewWaypoint(c.x + 0.0, c.y + 0.0)
        Notify('Waypoint set.', 'success', 2500)
    end
    cb({ ok = true })
end)

proxy('searchCitizens',  'distortionz_cad:server:searchCitizens')
proxy('searchVehicles',  'distortionz_cad:server:searchVehicles')
proxy('getCitizen',      'distortionz_cad:server:getCitizen')
proxy('listRecords',     'distortionz_cad:server:listRecords')
proxy('createWarrant',   'distortionz_cad:server:createWarrant')
proxy('resolveWarrant',  'distortionz_cad:server:resolveWarrant')
proxy('createBolo',      'distortionz_cad:server:createBolo')
proxy('resolveBolo',     'distortionz_cad:server:resolveBolo')
proxy('createCharge',    'distortionz_cad:server:createCharge')
proxy('createReport',    'distortionz_cad:server:createReport')
proxy('listReports',     'distortionz_cad:server:listReports')
proxy('getDispatch',     'distortionz_cad:server:getDispatch')
proxy('attachCall',      'distortionz_cad:server:attachCall')
proxy('detachCall',      'distortionz_cad:server:detachCall')
proxy('resolveCall',     'distortionz_cad:server:resolveCall')
proxy('listCallLog',     'distortionz_cad:server:listCallLog')
proxy('deleteCallLog',   'distortionz_cad:server:deleteCallLog')
proxy('createCall',      'distortionz_cad:server:createCall')
proxy('setStatus',       'distortionz_cad:server:setStatus')
proxy('panic',           'distortionz_cad:server:panic')
proxy('backup',          'distortionz_cad:server:backup')
proxy('setLicense',      'distortionz_cad:server:setLicense')
proxy('setCallsign',     'distortionz_cad:server:setCallsign')

-- Panic also available without the MDT open.
RegisterCommand('panic', function()
    lib.callback.await('distortionz_cad:server:panic', false)
    Notify('PANIC sent — units alerted.', 'error', 4000)
end, false)

-- ─── Live unit blips ────────────────────────────────────────────────
-- Persistent per-unit blips that glide toward their latest reported
-- position every frame, so movement is continuous instead of teleporting
-- on each server push.

local units = {}   -- [cid] = { blip, cur = {x,y,z}, tgt = {x,y,z} }

local function clearUnitBlips()
    for _, u in pairs(units) do
        if u.blip and DoesBlipExist(u.blip) then RemoveBlip(u.blip) end
    end
    units = {}
end

RegisterNetEvent('distortionz_cad:client:unitPositions', function(list)
    if not list then return end
    local seen = {}
    for _, u in ipairs(list) do
        local cid = u.cid
        if cid and u.coords then
            seen[cid] = true
            local rec = units[cid]
            if not rec then
                local b = AddBlipForCoord(u.coords.x, u.coords.y, u.coords.z)
                SetBlipSprite(b, 1)
                SetBlipColour(b, 38)        -- light blue = unit
                SetBlipScale(b, 0.8)
                SetBlipAsShortRange(b, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(('%s (%s)'):format(u.name or 'Unit', u.callsign or '—'))
                EndTextCommandSetBlipName(b)
                rec = { blip = b,
                        cur = { x = u.coords.x, y = u.coords.y, z = u.coords.z } }
                units[cid] = rec
            end
            rec.tgt = { x = u.coords.x, y = u.coords.y, z = u.coords.z }
        end
    end
    -- Drop units that went off duty / left.
    for cid, rec in pairs(units) do
        if not seen[cid] then
            if rec.blip and DoesBlipExist(rec.blip) then RemoveBlip(rec.blip) end
            units[cid] = nil
        end
    end
end)

-- Per-frame interpolation toward each unit's latest reported position.
CreateThread(function()
    while true do
        local any = false
        for _, rec in pairs(units) do
            any = true
            if rec.tgt and rec.blip and DoesBlipExist(rec.blip) then
                local c, t = rec.cur, rec.tgt
                c.x = c.x + (t.x - c.x) * 0.18
                c.y = c.y + (t.y - c.y) * 0.18
                c.z = c.z + (t.z - c.z) * 0.18
                SetBlipCoords(rec.blip, c.x, c.y, c.z)
            end
        end
        Wait(any and 0 or 500)
    end
end)

-- ─── Cleanup ────────────────────────────────────────────────────────

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearCallBlips()
    clearUnitBlips()
    if cadOpen then
        SetNuiFocus(false, false)
    end
end)
