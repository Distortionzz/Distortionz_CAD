-- =====================================================================
--  Distortionz CAD - Server
--  Police-gated MDT. Citizen/vehicle lookup (live from players /
--  player_vehicles), records (charges/warrants/BOLOs/reports), live
--  dispatch, and a central call hub other scripts feed into.
-- =====================================================================

local calls      = {}      -- [id] = call
local nextCallId = 1
local unitStatus = {}      -- [citizenid] = '10-8'

local function DebugPrint(message)
    if Config.Debug then
        print(('[%s:server] %s'):format(Config.ResourceName, message))
    end
end

-- ─── qbx helpers ────────────────────────────────────────────────────

local function GetPlayer(src)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    return ok and p or nil
end

local function IsLeo(src)
    local p = GetPlayer(src)
    if not p or not p.PlayerData or not p.PlayerData.job then return false, nil end
    local job = p.PlayerData.job
    for _, t in ipairs(Config.Access.jobTypes) do
        if job.type == t then return true, p end
    end
    for _, n in ipairs(Config.Access.jobNames) do
        if job.name == n then return true, p end
    end
    return false, p
end

local function OfficerOf(p)
    local pd = p and p.PlayerData
    if not pd then return 'Unknown', '---', nil end
    local ci   = pd.charinfo or {}
    local name = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then name = pd.citizenid or 'Unknown' end
    local callsign = (pd.metadata and pd.metadata.callsign)
        or (pd.job and pd.job.grade and pd.job.grade.name)
        or (pd.job and pd.job.name) or '---'
    return name, tostring(callsign), pd.citizenid
end

local function GradeOf(p)
    local g = p and p.PlayerData and p.PlayerData.job and p.PlayerData.job.grade
    return tonumber(g and g.level) or 0
end

local function LeoSources()
    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        if s and IsLeo(s) then out[#out + 1] = s end
    end
    return out
end

local function Notify(src, message, status, duration)
    TriggerClientEvent('distortionz_cad:client:notify', src,
        message, status or 'info', duration or 5000)
end

-- Broadcast a notify to every on-duty LEO (optionally skipping one src).
local function AlertUnits(message, status, exceptSrc)
    for _, s in ipairs(LeoSources()) do
        if s ~= exceptSrc then Notify(s, message, status or 'police', 9000) end
    end
end

local function PlayerByCid(cid)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    local ok, pl = pcall(function() return exports.qbx_core:GetPlayerByCitizenId(cid) end)
    return ok and pl or nil
end

local function EntityCoordsOf(src)
    local ped = src and src ~= 0 and GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

-- Guard: every callback must come from an on-duty LEO.
local function gate(src)
    local ok, p = IsLeo(src)
    if not ok then return nil end
    return p
end

-- ─── Dispatch state ─────────────────────────────────────────────────

local function activeCalls()
    local list = {}
    for _, c in pairs(calls) do list[#list + 1] = c end
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.time > b.time
    end)
    return list
end

local function unitRoster()
    local units = {}
    for _, s in ipairs(LeoSources()) do
        local p = GetPlayer(s)
        local name, callsign, cid = OfficerOf(p)
        local attached
        for _, c in pairs(calls) do
            for _, u in ipairs(c.units) do
                if u == cid then attached = c.id break end
            end
        end
        units[#units + 1] = {
            cid      = cid,
            name     = name,
            callsign = callsign,
            status   = unitStatus[cid] or Config.Dispatch.defaultStatus,
            callId   = attached,
        }
    end
    return units
end

local function pushDispatch()
    local snapshot = { calls = activeCalls(), units = unitRoster() }
    for _, s in ipairs(LeoSources()) do
        TriggerClientEvent('distortionz_cad:client:dispatch', s, snapshot)
    end
end

local function addCall(data)
    if not data then return end
    local n = 0
    for _ in pairs(calls) do n = n + 1 end
    if n >= Config.Dispatch.maxActiveCalls then return end

    local id = nextCallId
    nextCallId = nextCallId + 1
    calls[id] = {
        id        = id,
        code      = tostring(data.code or 'ALERT'),
        label     = tostring(data.title or data.label or 'Dispatch call'),
        location  = tostring(data.location or 'Unknown'),
        coords    = data.coords,
        priority  = tonumber(data.priority) or Config.Dispatch.defaultPriority,
        time      = os.time(),
        source    = data.source or 'SYSTEM',
        units     = {},
    }
    DebugPrint(('call #%d added: %s'):format(id, calls[id].label))
    pushDispatch()
    return id
end

exports('AddCall', addCall)
RegisterNetEvent('distortionz_cad:server:addCall', function(data)
    -- net event may arrive from a script (no real source filtering needed —
    -- it only creates a dispatch entry, no rewards/side effects).
    addCall(data)
end)

-- Bridge: qbx_police's own alert feeds the CAD automatically.
RegisterNetEvent('police:server:policeAlert', function(text)
    local src = source
    local coords
    local ped = src and src ~= 0 and GetPlayerPed(src)
    if ped and ped ~= 0 then
        local c = GetEntityCoords(ped)
        coords = { x = c.x, y = c.y, z = c.z }
    end
    addCall({
        code     = '10-66',
        title    = text or 'Police alert',
        location = 'See map',
        coords   = coords,
        priority = 2,
        source   = 'qbx_police',
    })
end)

-- Auto-expire stale calls.
CreateThread(function()
    while true do
        Wait(60000)
        local cutoff = os.time() - (Config.Dispatch.callExpireMins * 60)
        local changed = false
        for id, c in pairs(calls) do
            if c.time < cutoff and #c.units == 0 then
                calls[id] = nil
                changed = true
            end
        end
        if changed then pushDispatch() end
    end
end)

-- ─── Bootstrap / dispatch callbacks ─────────────────────────────────

lib.callback.register('distortionz_cad:server:bootstrap', function(source)
    local p = gate(source)
    if not p then return { ok = false } end
    local name, callsign, cid = OfficerOf(p)
    unitStatus[cid] = unitStatus[cid] or Config.Dispatch.defaultStatus
    return {
        ok       = true,
        version  = Config.CurrentVersion,
        officer  = { name = name, callsign = callsign, cid = cid,
                     status = unitStatus[cid], grade = GradeOf(p) },
        config   = {
            statusCodes  = Config.Dispatch.statusCodes,
            priorities   = Config.Dispatch.priorities,
            charges      = Config.Records.charges,
            boloTypes    = Config.Records.boloTypes,
            reportTypes  = Config.Records.reportTypes,
            deleteGrade  = Config.Access.callLogDeleteGrade,
        },
        dispatch = { calls = activeCalls(), units = unitRoster() },
    }
end)

lib.callback.register('distortionz_cad:server:getDispatch', function(source)
    if not gate(source) then return { ok = false } end
    return { ok = true, calls = activeCalls(), units = unitRoster() }
end)

lib.callback.register('distortionz_cad:server:setStatus', function(source, code)
    local p = gate(source)
    if not p then return { ok = false } end
    local _, _, cid = OfficerOf(p)
    unitStatus[cid] = tostring(code or Config.Dispatch.defaultStatus)
    pushDispatch()
    return { ok = true }
end)

lib.callback.register('distortionz_cad:server:attachCall', function(source, id)
    local p = gate(source)
    if not p then return { ok = false } end
    local call = calls[tonumber(id)]
    if not call then return { ok = false, reason = 'Call gone.' } end
    local _, _, cid = OfficerOf(p)
    for _, c in pairs(calls) do
        for i = #c.units, 1, -1 do
            if c.units[i] == cid then table.remove(c.units, i) end
        end
    end
    call.units[#call.units + 1] = cid
    pushDispatch()
    return { ok = true, call = call }
end)

lib.callback.register('distortionz_cad:server:detachCall', function(source)
    local p = gate(source)
    if not p then return { ok = false } end
    local _, _, cid = OfficerOf(p)
    for _, c in pairs(calls) do
        for i = #c.units, 1, -1 do
            if c.units[i] == cid then table.remove(c.units, i) end
        end
    end
    pushDispatch()
    return { ok = true }
end)

-- A call ends only by being Resolved (handled) or Dismissed (no action /
-- false alarm). Either way it must have no responding units — an active
-- call cannot be cleared out from under the units on it.
lib.callback.register('distortionz_cad:server:resolveCall', function(source, data)
    local p = gate(source)
    if not p then return { ok = false } end
    data = data or {}
    local call = calls[tonumber(data.id)]
    if not call then return { ok = false, reason = 'Call no longer exists.' } end
    if #call.units > 0 then
        return { ok = false, reason = ('Call is active — %d unit(s) attached. Detach first.'):format(#call.units) }
    end
    local outcome = data.outcome == 'dismissed' and 'dismissed' or 'resolved'

    -- Who actually cleared it. OfficerOf -> char name; fall back to the
    -- player's account name so it's never a generic 'Unknown'.
    local officerName = OfficerOf(p)
    if not officerName or officerName == '' or officerName == 'Unknown' then
        officerName = GetPlayerName(source) or 'Officer'
    end

    -- Permanently log the call before clearing it from the live feed.
    -- created_at = real server time (NOW()), opened_at = when it came in.
    -- json.encode(... or {}) so a coordless call can't leave a nil hole
    -- in the param array and shift the bindings.
    MySQL.insert.await([[
        INSERT INTO distortionz_cad_calls
            (code, title, location, coords, priority, source, outcome, officer, opened_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), NOW())
    ]], {
        call.code, call.label, call.location,
        json.encode(call.coords or {}),
        call.priority, call.source, outcome,
        officerName, call.time or os.time(),
    })

    calls[tonumber(data.id)] = nil
    pushDispatch()
    return { ok = true, outcome = outcome }
end)

lib.callback.register('distortionz_cad:server:listCallLog', function(source)
    if not gate(source) then return { ok = false } end
    local rows = MySQL.query.await([[
        SELECT id, code, title, location, priority, source, outcome, officer,
               DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS created_at,
               DATE_FORMAT(opened_at,  '%Y-%m-%d %H:%i') AS opened_at
        FROM distortionz_cad_calls ORDER BY id DESC LIMIT 80
    ]]) or {}
    return { ok = true, log = rows }
end)

lib.callback.register('distortionz_cad:server:deleteCallLog', function(source, id)
    local p = gate(source)
    if not p then return { ok = false } end
    if GradeOf(p) < (Config.Access.callLogDeleteGrade or 3) then
        return { ok = false, reason = 'Insufficient rank to delete call-log entries.' }
    end
    id = tonumber(id)
    if not id then return { ok = false, reason = 'Bad id.' } end
    MySQL.update.await('DELETE FROM distortionz_cad_calls WHERE id = ?', { id })
    return { ok = true }
end)

lib.callback.register('distortionz_cad:server:createCall', function(source, data)
    local p = gate(source)
    if not p then return { ok = false } end
    data = data or {}
    data.source = 'OFFICER'
    local id = addCall(data)
    return { ok = id ~= nil, id = id }
end)

lib.callback.register('distortionz_cad:server:panic', function(source)
    local p = gate(source)
    if not p then return { ok = false } end
    local name = OfficerOf(p)
    local id = addCall({
        code = '10-99', title = ('PANIC — %s needs immediate assistance'):format(name),
        location = 'Officer GPS', coords = EntityCoordsOf(source),
        priority = 1, source = 'PANIC',
    })
    AlertUnits(('🚨 PANIC — Officer %s needs immediate assistance!'):format(name), 'police')
    return { ok = id ~= nil }
end)

lib.callback.register('distortionz_cad:server:backup', function(source)
    local p = gate(source)
    if not p then return { ok = false } end
    local name = OfficerOf(p)
    local id = addCall({
        code = '10-78', title = ('Backup requested — %s'):format(name),
        location = 'Officer GPS', coords = EntityCoordsOf(source),
        priority = 2, source = 'BACKUP',
    })
    AlertUnits(('Backup requested by %s'):format(name), 'police')
    return { ok = id ~= nil }
end)

-- Live unit positions -> on-duty clients draw/update unit blips.
CreateThread(function()
    while true do
        Wait(Config.Dispatch.unitRefreshMs or 1500)
        local leo = LeoSources()
        if #leo > 0 then
            local pos = {}
            for _, s in ipairs(leo) do
                local pl = GetPlayer(s)
                local nm, cs, cid = OfficerOf(pl)
                local c = EntityCoordsOf(s)
                if c then pos[#pos + 1] = { cid = cid, name = nm, callsign = cs, coords = c } end
            end
            for _, s in ipairs(leo) do
                TriggerClientEvent('distortionz_cad:client:unitPositions', s, pos)
            end
        end
    end
end)

lib.callback.register('distortionz_cad:server:setCallsign', function(source, data)
    local p = gate(source)
    if not p then return { ok = false } end
    local cs = tostring((data and data.callsign) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if cs == '' then return { ok = false, reason = 'Callsign required.' } end
    p.Functions.SetMetaData('callsign', cs)
    pushDispatch()
    return { ok = true, callsign = cs }
end)

lib.callback.register('distortionz_cad:server:setLicense', function(source, data)
    local p = gate(source)
    if not p then return { ok = false } end
    data = data or {}
    local cid, key, grant = data.citizenid, data.key, data.grant == true
    if not cid or not key then return { ok = false, reason = 'Bad request.' } end

    local valid = false
    for _, k in ipairs(Config.Records.licenses or {}) do if k == key then valid = true break end end
    if not valid then return { ok = false, reason = 'Unknown license.' } end

    local target = PlayerByCid(cid)
    if target and target.PlayerData then
        local lic = target.PlayerData.metadata.licences or {}
        lic[key] = grant or nil
        target.Functions.SetMetaData('licences', lic)
    else
        local row = MySQL.query.await('SELECT metadata FROM players WHERE citizenid = ? LIMIT 1', { cid })
        if not row or not row[1] then return { ok = false, reason = 'Citizen not found.' } end
        local ok, meta = pcall(json.decode, row[1].metadata or '{}')
        if not ok or type(meta) ~= 'table' then meta = {} end
        meta.licences = type(meta.licences) == 'table' and meta.licences or {}
        meta.licences[key] = grant or nil
        MySQL.update.await('UPDATE players SET metadata = ? WHERE citizenid = ?',
            { json.encode(meta), cid })
    end
    return { ok = true, key = key, grant = grant }
end)

-- ─── Search ─────────────────────────────────────────────────────────

local function decodeCharinfo(raw)
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, t = pcall(json.decode, raw)
    return (ok and type(t) == 'table') and t or {}
end

lib.callback.register('distortionz_cad:server:searchCitizens', function(source, query)
    if not gate(source) then return { ok = false } end
    query = tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #query < 2 then return { ok = true, results = {} } end

    local rows = MySQL.query.await(
        'SELECT citizenid, charinfo, phone_number FROM players WHERE charinfo LIKE ? OR citizenid = ? LIMIT 25',
        { '%' .. query .. '%', query }) or {}

    local results = {}
    for _, r in ipairs(rows) do
        local ci = decodeCharinfo(r.charinfo)
        results[#results + 1] = {
            citizenid = r.citizenid,
            name      = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('^%s+', ''):gsub('%s+$', ''),
            dob       = ci.birthdate or '—',
            gender    = ci.gender == 1 and 'Female' or 'Male',
            phone     = r.phone_number or ci.phone or '—',
        }
    end
    return { ok = true, results = results }
end)

lib.callback.register('distortionz_cad:server:searchVehicles', function(source, query)
    if not gate(source) then return { ok = false } end
    query = tostring(query or ''):gsub('%s+', ''):upper()
    if #query < 2 then return { ok = true, results = {} } end

    local rows = MySQL.query.await([[
        SELECT pv.plate, pv.vehicle, pv.fakeplate, pv.citizenid, p.charinfo
        FROM player_vehicles pv
        LEFT JOIN players p ON p.citizenid = pv.citizenid
        WHERE pv.plate LIKE ? OR pv.fakeplate LIKE ? LIMIT 25
    ]], { '%' .. query .. '%', '%' .. query .. '%' }) or {}

    local results = {}
    for _, r in ipairs(rows) do
        local ci = decodeCharinfo(r.charinfo)
        local bolo = MySQL.query.await(
            "SELECT id, title FROM distortionz_cad_bolos WHERE reference = ? AND status = 'active' LIMIT 1",
            { r.plate })
        local hasBolo = bolo and bolo[1] ~= nil
        results[#results + 1] = {
            plate     = r.plate,
            fakeplate = r.fakeplate,
            model     = r.vehicle,
            citizenid = r.citizenid,
            owner     = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('^%s+', ''):gsub('%s+$', ''),
            bolo      = hasBolo and bolo[1].title or nil,
        }
        if hasBolo then
            AlertUnits(('⚠ BOLO PLATE RAN — %s: %s'):format(r.plate, bolo[1].title),
                'police', source)
        end
    end
    return { ok = true, results = results }
end)

lib.callback.register('distortionz_cad:server:getCitizen', function(source, citizenid)
    if not gate(source) then return { ok = false } end
    citizenid = tostring(citizenid or '')

    local prow = MySQL.query.await(
        'SELECT citizenid, charinfo, phone_number, job, metadata FROM players WHERE citizenid = ? LIMIT 1',
        { citizenid })
    if not prow or not prow[1] then return { ok = false, reason = 'Not found.' } end
    local ci = decodeCharinfo(prow[1].charinfo)
    local meta = decodeCharinfo(prow[1].metadata)
    local metaLic = (type(meta.licences) == 'table' and meta.licences) or {}
    local licenses = {}
    for _, k in ipairs(Config.Records.licenses or {}) do
        licenses[#licenses + 1] = { key = k, held = metaLic[k] == true }
    end

    local warrants = MySQL.query.await(
        'SELECT id, reason, status, officer, created_at FROM distortionz_cad_warrants WHERE citizenid = ? ORDER BY id DESC LIMIT 50',
        { citizenid }) or {}
    local charges = MySQL.query.await(
        'SELECT id, charges, total_fine, total_jail, notes, officer, created_at FROM distortionz_cad_charges WHERE citizenid = ? ORDER BY id DESC LIMIT 50',
        { citizenid }) or {}
    local vehicles = MySQL.query.await(
        'SELECT plate, vehicle, fakeplate FROM player_vehicles WHERE citizenid = ? LIMIT 50',
        { citizenid }) or {}
    -- Active BOLOs linked to this person via the reference field (the
    -- citizen-autocomplete on the BOLO form stores their citizenid there).
    local bolos = MySQL.query.await(
        "SELECT id, type, title, details, officer, created_at FROM distortionz_cad_bolos WHERE reference = ? AND status = 'active' ORDER BY id DESC LIMIT 25",
        { citizenid }) or {}

    for _, c in ipairs(charges) do
        local ok, parsed = pcall(json.decode, c.charges or '[]')
        c.charges = (ok and parsed) or {}
    end

    local fullName = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')

    -- BOLO / warrant auto-alert: running this person pings all units.
    local activeWarrants = 0
    for _, w in ipairs(warrants) do if w.status == 'active' then activeWarrants = activeWarrants + 1 end end
    if #bolos > 0 or activeWarrants > 0 then
        local flags = {}
        if #bolos > 0 then flags[#flags + 1] = (#bolos .. ' BOLO') end
        if activeWarrants > 0 then flags[#flags + 1] = (activeWarrants .. ' warrant') end
        AlertUnits(('⚠ FLAGGED — %s (%s): %s'):format(
            fullName ~= '' and fullName or citizenid, citizenid, table.concat(flags, ' · ')),
            'police', source)
    end

    return {
        ok = true,
        profile = {
            citizenid = citizenid,
            name      = fullName,
            dob       = ci.birthdate or '—',
            gender    = ci.gender == 1 and 'Female' or 'Male',
            phone     = prow[1].phone_number or ci.phone or '—',
            nationality = ci.nationality or '—',
        },
        warrants = warrants,
        bolos    = bolos,
        charges  = charges,
        vehicles = vehicles,
        licenses = licenses,
    }
end)

-- ─── Records: write ─────────────────────────────────────────────────

lib.callback.register('distortionz_cad:server:createCharge', function(source, data)
    local p = gate(source)
    if not p then return { ok = false } end
    data = data or {}
    if not data.citizenid or type(data.charges) ~= 'table' or #data.charges == 0 then
        return { ok = false, reason = 'Pick a citizen and at least one charge.' }
    end
    local fine, jail = 0, 0
    for _, ch in ipairs(data.charges) do
        fine = fine + (tonumber(ch.fine) or 0)
        jail = jail + (tonumber(ch.months) or 0)
    end
    local officer = OfficerOf(p)
    MySQL.insert.await([[
        INSERT INTO distortionz_cad_charges (citizenid, name, charges, total_fine, total_jail, notes, officer)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { data.citizenid, data.name or '', json.encode(data.charges), fine, jail,
          data.notes or '', officer })

    -- Enforce on the suspect if they are online. Record is already saved.
    local enf = Config.Records.enforce or {}
    local target = PlayerByCid(data.citizenid)
    local applied = { fined = false, jailed = false, online = target ~= nil }

    if target and target.PlayerData then
        local tsrc = target.PlayerData.source
        if enf.fine and fine > 0 then
            local okF = pcall(function()
                return target.Functions.RemoveMoney(enf.fineAccount or 'bank', fine, 'cad-fine')
            end)
            if not okF and enf.fineFallback then
                pcall(function() target.Functions.RemoveMoney(enf.fineFallback, fine, 'cad-fine') end)
            end
            applied.fined = true
        end
        if enf.jail and jail > 0 then
            local jt = math.floor(jail * (enf.jailMultiplier or 1))
            if GetResourceState('xt-prison'):find('start') then
                pcall(function() lib.callback.await('xt-prison:client:enterJail', tsrc, jt) end)
            else
                TriggerClientEvent(enf.jailFallbackEvent or 'police:client:SendToJail', tsrc, jt)
            end
            pcall(function()
                target.Functions.SetMetaData('criminalrecord', { hasRecord = true, date = os.date('*t') })
            end)
            applied.jailed = true
        end
        Notify(tsrc, ('You were charged: $%d fine, %d months.'):format(fine, jail), 'error', 8000)
    end

    return { ok = true, fine = fine, jail = jail, applied = applied }
end)

lib.callback.register('distortionz_cad:server:createWarrant', function(source, data)
    local p = gate(source)
    if not p then return { ok = false } end
    data = data or {}
    if not data.citizenid or not data.reason or data.reason == '' then
        return { ok = false, reason = 'Citizen and reason required.' }
    end
    local officer = OfficerOf(p)
    MySQL.insert.await([[
        INSERT INTO distortionz_cad_warrants (citizenid, name, reason, officer)
        VALUES (?, ?, ?, ?)
    ]], { data.citizenid, data.name or '', data.reason, officer })
    pushDispatch()
    return { ok = true }
end)

lib.callback.register('distortionz_cad:server:resolveWarrant', function(source, id)
    if not gate(source) then return { ok = false } end
    MySQL.update.await('UPDATE distortionz_cad_warrants SET status = ? WHERE id = ?',
        { 'served', tonumber(id) })
    return { ok = true }
end)

lib.callback.register('distortionz_cad:server:createBolo', function(source, data)
    local p = gate(source)
    if not p then return { ok = false } end
    data = data or {}
    if not data.title or data.title == '' then
        return { ok = false, reason = 'Title required.' }
    end
    local officer = OfficerOf(p)
    MySQL.insert.await([[
        INSERT INTO distortionz_cad_bolos (type, title, details, reference, officer)
        VALUES (?, ?, ?, ?, ?)
    ]], { data.type or 'Person', data.title, data.details or '',
          data.reference or '', officer })
    return { ok = true }
end)

lib.callback.register('distortionz_cad:server:resolveBolo', function(source, id)
    if not gate(source) then return { ok = false } end
    MySQL.update.await('UPDATE distortionz_cad_bolos SET status = ? WHERE id = ?',
        { 'cleared', tonumber(id) })
    return { ok = true }
end)

lib.callback.register('distortionz_cad:server:listRecords', function(source)
    if not gate(source) then return { ok = false } end
    local warrants = MySQL.query.await(
        "SELECT id, citizenid, name, reason, officer, created_at FROM distortionz_cad_warrants WHERE status = 'active' ORDER BY id DESC LIMIT 100") or {}
    local bolos = MySQL.query.await(
        "SELECT id, type, title, details, reference, officer, created_at FROM distortionz_cad_bolos WHERE status = 'active' ORDER BY id DESC LIMIT 100") or {}
    return { ok = true, warrants = warrants, bolos = bolos }
end)

lib.callback.register('distortionz_cad:server:createReport', function(source, data)
    local p = gate(source)
    if not p then return { ok = false } end
    data = data or {}
    if not data.title or data.title == '' or not data.narrative or data.narrative == '' then
        return { ok = false, reason = 'Title and narrative required.' }
    end
    local officer = OfficerOf(p)
    MySQL.insert.await([[
        INSERT INTO distortionz_cad_reports (type, title, narrative, involved, author)
        VALUES (?, ?, ?, ?, ?)
    ]], { data.type or 'Incident', data.title, data.narrative,
          json.encode(data.involved or {}), officer })
    return { ok = true }
end)

lib.callback.register('distortionz_cad:server:listReports', function(source)
    if not gate(source) then return { ok = false } end
    local rows = MySQL.query.await(
        'SELECT id, type, title, narrative, involved, author, created_at FROM distortionz_cad_reports ORDER BY id DESC LIMIT 60') or {}
    for _, r in ipairs(rows) do
        local ok, inv = pcall(json.decode, r.involved or '[]')
        r.involved = (ok and inv) or {}
    end
    return { ok = true, reports = rows }
end)

-- ─── Cleanup ────────────────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    pushDispatch()
end)
