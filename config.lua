Config = {}

Config.Debug = false

Config.ResourceName   = 'distortionz_cad'
Config.CurrentVersion = '1.6.1'

-- ─── Version checker ────────────────────────────────────────────────
Config.VersionCheck = {
    enabled      = true,
    url          = 'https://raw.githubusercontent.com/Distortionzz/Distortionz_CAD/main/version.json',
    checkOnStart = true,
}

-- ─── Notify integration ─────────────────────────────────────────────
Config.Notify = {
    title                 = 'CAD',
    useDistortionzNotify  = true,
}

-- ─── Access ─────────────────────────────────────────────────────────
-- Police-only. Any qbx job whose TYPE is in jobTypes (recommended), OR
-- whose NAME is in jobNames, can open the CAD. type 'leo' covers
-- police/sheriff/sast/fib if their qbx job is typed 'leo'.
Config.Access = {
    jobTypes = { 'leo' },
    jobNames = { 'police', 'sheriff', 'fib' },
    command  = 'cad',
    -- Optional usable item (ox_inventory). nil = command only.
    item     = nil,                 -- e.g. 'police_tablet'
    keybind  = '',                  -- optional RegisterKeyMapping default, '' = none

    -- Minimum qbx job grade LEVEL allowed to delete call-log entries.
    -- Enforced server-side; the delete button only shows for those grades.
    callLogDeleteGrade = 3,
}

-- ─── Dispatch ───────────────────────────────────────────────────────
Config.Dispatch = {
    -- Live calls are in-memory (ephemeral by design). Records persist.
    maxActiveCalls   = 60,
    callExpireMins   = 30,           -- auto-close untouched calls after N mins
    blipSprite       = 60,
    blipColour       = 1,
    blipScale        = 0.9,
    autoBlink        = true,

    -- How often the server pushes on-duty unit positions (ms). Lower =
    -- more live. Client interpolates between pushes so it stays smooth.
    unitRefreshMs    = 1500,

    -- 10-codes available for unit status (key = code, label shown in UI).
    statusCodes = {
        { code = '10-8',  label = 'In Service' },
        { code = '10-6',  label = 'Busy' },
        { code = '10-7',  label = 'Out of Service' },
        { code = '10-23', label = 'On Scene' },
        { code = '10-97', label = 'En Route' },
        { code = '10-15', label = 'Prisoner in Custody' },
        { code = 'Code 4', label = 'No Further Assistance' },
    },
    defaultStatus = '10-8',

    -- Priority styling (1 = highest). Used by the UI accent.
    priorities = { [1] = 'CRITICAL', [2] = 'PRIORITY', [3] = 'ROUTINE' },
    defaultPriority = 2,
}

-- ─── Records ────────────────────────────────────────────────────────
Config.Records = {
    -- Preset chargeable offences (UI quick-pick). months = jail, fine = $.
    charges = {
        { label = 'Speeding',                  fine = 350,   months = 0 },
        { label = 'Reckless Driving',          fine = 750,   months = 0 },
        { label = 'Evading Police',            fine = 2500,  months = 8 },
        { label = 'Possession (Class A)',      fine = 1500,  months = 6 },
        { label = 'Trafficking',               fine = 6000,  months = 25 },
        { label = 'Armed Robbery',             fine = 5000,  months = 30 },
        { label = 'Grand Theft Auto',          fine = 3000,  months = 15 },
        { label = 'Assault',                   fine = 2000,  months = 10 },
        { label = 'Assault on an Officer',     fine = 4000,  months = 20 },
        { label = 'Murder',                    fine = 10000, months = 60 },
        { label = 'Kidnapping',                fine = 7000,  months = 35 },
        { label = 'Weapons Trafficking',       fine = 8000,  months = 40 },
    },
    boloTypes = { 'Person', 'Vehicle', 'Other' },
    reportTypes = { 'Incident', 'Arrest', 'Use of Force', 'Patrol', 'Investigation' },

    -- When charges are logged, also enforce on the suspect IF they are
    -- online (resolved by CID). Records are always written regardless.
    enforce = {
        fine           = true,        -- RemoveMoney from bank (then cash)
        jail           = true,        -- send to jail via xt-prison
        fineAccount    = 'bank',
        fineFallback   = 'cash',
        -- xt-prison's enterJail takes a raw time value; charge presets are
        -- in "months". Multiply months by this to get the jail time unit
        -- your prison expects (tune in-game without code changes).
        jailMultiplier = 1,
        jailFallbackEvent = 'police:client:SendToJail',
    },

    -- Licenses shown / togg: keys map to qbx metadata.licences entries.
    licenses = { 'driver', 'weapon', 'pilot' },
}
