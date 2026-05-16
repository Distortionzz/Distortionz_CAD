/* Distortionz CAD — NUI */
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'distortionz_cad';

const state = {
  boot: null,
  dispatch: { calls: [], units: [] },
  searchMode: 'citizens',
  selectedCitizen: null,
  chargeSel: [],
};

function api(name, data, raw) {
  const body = raw ? raw : { data: data };
  return fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(body),
  }).then(r => r.json()).catch(() => ({ ok: false }));
}

function debounce(fn, ms) { let t; return function (...a) { clearTimeout(t); t = setTimeout(() => fn.apply(this, a), ms); }; }
const $ = sel => document.querySelector(sel);
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
function toast(msg) {
  const t = $('#toast');
  t.textContent = msg; t.classList.remove('hidden');
  clearTimeout(t._t); t._t = setTimeout(() => t.classList.add('hidden'), 2600);
}
function when(ts) {
  if (ts == null || ts === '') return '—';
  // oxmysql can hand back raw epoch (s or ms) for TIMESTAMP columns.
  if (typeof ts === 'number' || /^\d{10,}$/.test(ts)) {
    let n = Number(ts);
    if (n < 1e12) n *= 1000;            // seconds -> ms
    const d = new Date(n);
    if (isNaN(d.getTime())) return '—';
    const p = x => String(x).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }
  return String(ts).replace('T', ' ').slice(0, 16);
}

/* ── window message ──────────────────────────────────── */
window.addEventListener('message', e => {
  const d = e.data || {};
  if (d.action === 'open') { boot(d.data); }
  else if (d.action === 'close') { $('#cad').classList.add('hidden'); }
  else if (d.action === 'dispatch' && d.data) { state.dispatch = d.data; if (curTab === 'dispatch') renderDispatch(); renderUnitsOnly(); }
});

document.addEventListener('keydown', e => { if (e.key === 'Escape') doClose(); });

function doClose() { api('close', null, {}); $('#cad').classList.add('hidden'); }
$('#cad-close').addEventListener('click', doClose);

/* ── bootstrap ───────────────────────────────────────── */
function boot(b) {
  if (!b || !b.ok) return;
  state.boot = b;
  state.dispatch = b.dispatch || { calls: [], units: [] };

  $('#cad-version').textContent = 'v' + (b.version || '1.0.0');
  $('#off-name').textContent = b.officer.name;
  $('#off-callsign').textContent = b.officer.callsign;

  const ss = $('#off-status');
  ss.innerHTML = b.config.statusCodes.map(s =>
    `<option value="${esc(s.code)}">${esc(s.code)} · ${esc(s.label)}</option>`).join('');
  ss.value = b.officer.status;
  ss.onchange = () => api('setStatus', ss.value).then(() => toast('Status: ' + ss.value));

  $('#cs-set').onclick = () => {
    const v = $('#cs-input').value.trim();
    if (!v) return toast('Enter a callsign');
    api('setCallsign', { callsign: v }).then(r => {
      if (r.ok) { $('#off-callsign').textContent = r.callsign; $('#cs-input').value = ''; toast('Callsign set: ' + r.callsign); }
      else toast(r.reason || 'Failed');
    });
  };
  $('#op-backup').onclick = () => api('backup').then(r => toast(r.ok ? 'Backup requested' : 'Failed'));
  $('#op-panic').onclick = () => api('panic').then(r => toast(r.ok ? 'PANIC sent — units alerted' : 'Failed'));

  $('#cad').classList.remove('hidden');
  switchTab('dispatch');
}

/* ── tabs ────────────────────────────────────────────── */
let curTab = 'dispatch';
document.querySelectorAll('.tab').forEach(t =>
  t.addEventListener('click', () => switchTab(t.dataset.tab)));

function switchTab(name) {
  curTab = name;
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === name));
  document.querySelectorAll('.tabview').forEach(v => v.classList.remove('active'));
  $('#tab-' + name).classList.add('active');
  if (name === 'dispatch') renderDispatch();
  if (name === 'search') renderSearch();
  if (name === 'records') loadRecords();
  if (name === 'bolo') loadBolos();
  if (name === 'reports') loadReports();
}

/* ── DISPATCH ────────────────────────────────────────── */
function callCard(c) {
  return `<div class="callitem p${c.priority}">
    <div class="top"><span class="code">[${esc(c.code)}]</span>
      <span class="badge b${c.priority}">${esc((state.boot.config.priorities[c.priority]) || 'P' + c.priority)}</span></div>
    <div class="lbl">${esc(c.label)}</div>
    <div class="meta">${esc(c.location)} · units: ${c.units.length} · #${c.id}</div>
    <div class="actions">
      <button class="btn sm" data-act="attach" data-id="${c.id}">Attach</button>
      <button class="btn sm ghost" data-act="detach">Detach</button>
      ${c.coords ? `<button class="btn sm ghost" data-act="wp" data-id="${c.id}">Waypoint</button>` : ''}
      <button class="btn sm ghost" data-act="resolve" data-id="${c.id}">Resolve</button>
      <button class="btn sm ghost" data-act="dismiss" data-id="${c.id}">Dismiss</button>
    </div></div>`;
}
function unitsTable() {
  const u = state.dispatch.units || [];
  if (!u.length) return '<div class="empty">No units on duty.</div>';
  return `<table><tr><th>Callsign</th><th>Officer</th><th>Status</th><th>Call</th></tr>
    ${u.map(x => `<tr><td>${esc(x.callsign)}</td><td>${esc(x.name)}</td>
      <td><span class="pill on">${esc(x.status)}</span></td>
      <td>${x.callId ? '#' + x.callId : '—'}</td></tr>`).join('')}</table>`;
}
function renderUnitsOnly() { const el = $('#units-box'); if (el) el.innerHTML = unitsTable(); }

function renderDispatch() {
  const calls = state.dispatch.calls || [];
  $('#tab-dispatch').innerHTML = `
    <div class="grid2">
      <div>
        <h3 class="section">Active Calls (${calls.length})</h3>
        <div id="calls-box">${calls.length ? calls.map(callCard).join('') : '<div class="empty">No active calls.</div>'}</div>
      </div>
      <div>
        <h3 class="section">Units</h3>
        <div class="card" id="units-box">${unitsTable()}</div>
        <h3 class="section">New Call</h3>
        <div class="card">
          <div class="field"><span class="label">Code</span><input id="nc-code" class="full" placeholder="10-90" /></div>
          <div class="field"><span class="label">Title</span><input id="nc-title" class="full" placeholder="Disturbance at..." /></div>
          <div class="field"><span class="label">Location</span><input id="nc-loc" class="full" placeholder="Legion Sq" /></div>
          <div class="field"><span class="label">Priority</span>
            <select id="nc-prio" class="full"><option value="1">1 · Critical</option><option value="2" selected>2 · Priority</option><option value="3">3 · Routine</option></select></div>
          <button class="btn" id="nc-go">Create Call</button>
        </div>
      </div>
    </div>
    <h3 class="section" style="margin-top:24px">Call Log</h3>
    <div id="calllog" class="card"><div class="empty">Loading…</div></div>`;

  $('#tab-dispatch').querySelectorAll('[data-act]').forEach(b => b.onclick = () => {
    const a = b.dataset.act, id = b.dataset.id;
    if (a === 'attach') api('attachCall', Number(id)).then(r => { if (r.ok) { toast('Attached to #' + id); if (r.call && r.call.coords) api('waypoint', null, { coords: r.call.coords }); } });
    else if (a === 'detach') api('detachCall').then(() => toast('Detached'));
    else if (a === 'resolve' || a === 'dismiss') api('resolveCall', { id: Number(id), outcome: a === 'dismiss' ? 'dismissed' : 'resolved' })
      .then(r => { toast(r.ok ? ('Call ' + r.outcome) : (r.reason || 'Cannot clear call')); if (r.ok) loadCallLog(); });
    else if (a === 'wp') { const c = (state.dispatch.calls || []).find(x => x.id == id); if (c && c.coords) api('waypoint', null, { coords: c.coords }).then(() => toast('Waypoint set')); }
  });
  $('#nc-go').onclick = () => {
    const d = { code: $('#nc-code').value, title: $('#nc-title').value, location: $('#nc-loc').value, priority: Number($('#nc-prio').value) };
    if (!d.title) return toast('Title required');
    api('createCall', d).then(r => { if (r.ok) toast('Call created'); });
  };

  loadCallLog();
}

function loadCallLog() {
  const box = $('#calllog');
  if (!box) return;
  const canDel = state.boot && state.boot.officer
    && (state.boot.officer.grade || 0) >= ((state.boot.config && state.boot.config.deleteGrade) || 3);
  api('listCallLog').then(r => {
    const log = (r && r.log) || [];
    box.innerHTML = log.length ? `<table>
      <tr><th>#</th><th>Code</th><th>Call</th><th>Outcome</th><th>Cleared by</th><th>When</th>${canDel ? '<th></th>' : ''}</tr>
      ${log.map(x => `<tr><td>${x.id}</td><td>${esc(x.code)}</td><td>${esc(x.title)}</td>
        <td><span class="badge ${x.outcome === 'dismissed' ? 'b2' : 'b3'}">${esc(x.outcome)}</span></td>
        <td>${esc(x.officer || '—')}</td><td>${when(x.created_at)}</td>
        ${canDel ? `<td><button class="btn sm ghost" data-del="${x.id}">Delete</button></td>` : ''}</tr>`).join('')}</table>`
      : '<div class="empty">No logged calls yet.</div>';
    if (canDel) box.querySelectorAll('[data-del]').forEach(b => b.onclick = () =>
      api('deleteCallLog', Number(b.dataset.del)).then(res => {
        toast(res.ok ? 'Log entry deleted' : (res.reason || 'Cannot delete'));
        if (res.ok) loadCallLog();
      }));
  });
}

/* ── SEARCH ──────────────────────────────────────────── */
function renderSearch() {
  $('#tab-search').innerHTML = `
    <div class="row" style="margin-bottom:16px">
      <button class="btn ${state.searchMode === 'citizens' ? '' : 'ghost'}" id="sm-cit">Citizens</button>
      <button class="btn ${state.searchMode === 'vehicles' ? '' : 'ghost'}" id="sm-veh">Vehicles</button>
      <input id="sq" class="grow" autocomplete="off" placeholder="${state.searchMode === 'citizens' ? 'Type a name or CID — results auto-fill…' : 'Type a plate — results auto-fill…'}" />
      <button class="btn" id="sgo">Search</button>
    </div>
    <div class="grid2">
      <div><h3 class="section">Results</h3><div id="sres" class="card"><div class="empty">Run a search.</div></div></div>
      <div><h3 class="section">Profile</h3><div id="sprof" class="card"><div class="empty">Select a result.</div></div></div>
    </div>`;
  $('#sm-cit').onclick = () => { state.searchMode = 'citizens'; renderSearch(); };
  $('#sm-veh').onclick = () => { state.searchMode = 'vehicles'; renderSearch(); };
  const run = () => doSearch($('#sq').value);
  $('#sgo').onclick = run;
  const liveRun = debounce(() => {
    const v = $('#sq').value.trim();
    if (v.length < 2) { $('#sres').innerHTML = '<div class="empty">Keep typing…</div>'; return; }
    doSearch(v);
  }, 220);
  $('#sq').addEventListener('input', liveRun);
  $('#sq').addEventListener('keydown', e => { if (e.key === 'Enter') run(); });
  $('#sq').focus();
}
function doSearch(q) {
  if (state.searchMode === 'citizens') {
    api('searchCitizens', q).then(r => {
      const rows = (r.results || []);
      $('#sres').innerHTML = rows.length ? `<table><tr><th>Name</th><th>CID</th><th>DOB</th><th>Phone</th></tr>
        ${rows.map(x => `<tr class="click" data-cid="${esc(x.citizenid)}"><td>${esc(x.name)}</td><td>${esc(x.citizenid)}</td><td>${esc(x.dob)}</td><td>${esc(x.phone)}</td></tr>`).join('')}</table>`
        : '<div class="empty">No matches.</div>';
      $('#sres').querySelectorAll('[data-cid]').forEach(tr => tr.onclick = () => openCitizen(tr.dataset.cid));
    });
  } else {
    api('searchVehicles', q).then(r => {
      const rows = (r.results || []);
      $('#sres').innerHTML = rows.length ? `<table><tr><th>Plate</th><th>Model</th><th>Owner</th></tr>
        ${rows.map(x => `<tr class="click" data-cid="${esc(x.citizenid)}"><td>${esc(x.plate)}${x.fakeplate ? ' <span class="pill">FAKE</span>' : ''}</td><td>${esc(x.model)}</td><td>${esc(x.owner || '—')}</td></tr>`).join('')}</table>`
        : '<div class="empty">No matches.</div>';
      $('#sres').querySelectorAll('[data-cid]').forEach(tr => tr.onclick = () => tr.dataset.cid && openCitizen(tr.dataset.cid));
    });
  }
}
function openCitizen(cid) {
  api('getCitizen', cid).then(r => {
    if (!r.ok) return toast(r.reason || 'Not found');
    state.selectedCitizen = r;
    const p = r.profile;
    $('#sprof').innerHTML = `
      <div class="kv">
        <span class="label">Name</span><span>${esc(p.name)}</span>
        <span class="label">CID</span><span>${esc(p.citizenid)}</span>
        <span class="label">DOB</span><span>${esc(p.dob)}</span>
        <span class="label">Sex</span><span>${esc(p.gender)}</span>
        <span class="label">Phone</span><span>${esc(p.phone)}</span>
      </div>
      <h3 class="section" style="margin-top:18px">Active Warrants (${r.warrants.filter(w => w.status === 'active').length})</h3>
      ${r.warrants.length ? `<table><tr><th>Reason</th><th>Status</th><th>Officer</th></tr>
        ${r.warrants.map(w => `<tr><td>${esc(w.reason)}</td><td><span class="badge ${w.status === 'active' ? 'b1' : 'b3'}">${esc(w.status)}</span></td><td>${esc(w.officer)}</td></tr>`).join('')}</table>` : '<div class="empty">None.</div>'}
      <h3 class="section" style="margin-top:18px">Active BOLOs (${(r.bolos || []).length})</h3>
      ${(r.bolos && r.bolos.length) ? r.bolos.map(b => `<div class="callitem p1" style="margin:0 0 10px">
        <div class="row"><span class="badge b1">${esc(b.type)}</span><strong>${esc(b.title)}</strong></div>
        ${b.details ? `<div class="muted" style="margin-top:6px">${esc(b.details)}</div>` : ''}
        <div class="muted" style="margin-top:4px">${esc(b.officer || '—')} · ${when(b.created_at)}</div></div>`).join('')
        : '<div class="empty">None.</div>'}
      <h3 class="section" style="margin-top:18px">Charge History</h3>
      ${r.charges.length ? r.charges.map(c => `<div class="card" style="margin:0 0 10px">
        <div class="meta muted">${when(c.created_at)} · ${esc(c.officer)} · fine $${c.total_fine} · ${c.total_jail}mo</div>
        <div>${(c.charges || []).map(x => `<span class="pill">${esc(x.label)}</span>`).join('')}</div>
        ${c.notes ? `<div class="muted" style="margin-top:6px">${esc(c.notes)}</div>` : ''}</div>`).join('') : '<div class="empty">Clean.</div>'}
      <h3 class="section" style="margin-top:18px">Licenses</h3>
      <div class="row">${(r.licenses || []).map(l =>
        `<button class="btn sm ${l.held ? '' : 'ghost'}" data-lic="${esc(l.key)}" data-held="${l.held ? 1 : 0}">
          ${esc(l.key.toUpperCase())} · ${l.held ? 'HELD' : 'NONE'}</button>`).join('') || '<span class="empty">No license types configured.</span>'}</div>
      <h3 class="section" style="margin-top:18px">Vehicles</h3>
      ${r.vehicles.length ? `<table><tr><th>Plate</th><th>Model</th></tr>
        ${r.vehicles.map(v => `<tr><td>${esc(v.plate)}</td><td>${esc(v.vehicle)}</td></tr>`).join('')}</table>` : '<div class="empty">None registered.</div>'}`;

    $('#sprof').querySelectorAll('[data-lic]').forEach(btn => btn.onclick = () => {
      const grant = btn.dataset.held !== '1';
      api('setLicense', { citizenid: p.citizenid, key: btn.dataset.lic, grant }).then(res => {
        toast(res.ok ? (btn.dataset.lic.toUpperCase() + (grant ? ' granted' : ' revoked')) : (res.reason || 'Failed'));
        if (res.ok) openCitizen(p.citizenid);
      });
    });
  });
}

/* ── RECORDS ─────────────────────────────────────────── */
function loadRecords() {
  api('listRecords').then(r => {
    const w = r.warrants || [], b = r.bolos || [];
    const cfg = state.boot.config;
    $('#tab-records').innerHTML = `
      <div class="grid2">
        <div>
          <h3 class="section">Active Warrants (${w.length})</h3>
          <div class="card">${w.length ? `<table><tr><th>Name/CID</th><th>Reason</th><th></th></tr>
            ${w.map(x => `<tr><td>${esc(x.name || x.citizenid)}</td><td>${esc(x.reason)}</td>
              <td><button class="btn sm" data-serve="${x.id}">Serve</button></td></tr>`).join('')}</table>` : '<div class="empty">No active warrants.</div>'}</div>
        </div>
        <div>
          <h3 class="section">Add Charges</h3>
          <div class="card">
            <div class="field"><span class="label">Citizen ID</span><input id="ch-cid" class="full" placeholder="CID" /></div>
            <div class="field"><span class="label">Name</span><input id="ch-name" class="full" placeholder="Suspect name" /></div>
            <div class="field"><span class="label">Offences</span>
              <div class="checks">${cfg.charges.map((c, i) => `<div class="check" data-ci="${i}">${esc(c.label)} · $${c.fine}/${c.months}mo</div>`).join('')}</div></div>
            <div class="field"><span class="label">Notes</span><textarea id="ch-notes" class="full"></textarea></div>
            <div class="row"><span id="ch-tot" class="muted"></span><button class="btn" id="ch-go" style="margin-left:auto">Log Charges</button></div>
          </div>
          <h3 class="section">New Warrant</h3>
          <div class="card">
            <div class="field"><span class="label">Citizen ID</span><input id="wr-cid" class="full" /></div>
            <div class="field"><span class="label">Name</span><input id="wr-name" class="full" /></div>
            <div class="field"><span class="label">Reason</span><textarea id="wr-reason" class="full"></textarea></div>
            <button class="btn" id="wr-go">Issue Warrant</button>
          </div>
        </div>
      </div>`;

    $('#tab-records').querySelectorAll('[data-serve]').forEach(btn => btn.onclick = () =>
      api('resolveWarrant', Number(btn.dataset.serve)).then(() => { toast('Warrant served'); loadRecords(); }));

    state.chargeSel = [];
    const tot = () => {
      let f = 0, j = 0;
      state.chargeSel.forEach(i => { f += cfg.charges[i].fine; j += cfg.charges[i].months; });
      $('#ch-tot').textContent = `Total: $${f} · ${j} mo`;
    };
    $('#tab-records').querySelectorAll('[data-ci]').forEach(el => el.onclick = () => {
      const i = Number(el.dataset.ci), k = state.chargeSel.indexOf(i);
      if (k >= 0) { state.chargeSel.splice(k, 1); el.classList.remove('sel'); }
      else { state.chargeSel.push(i); el.classList.add('sel'); }
      tot();
    });
    tot();

    $('#ch-go').onclick = () => {
      if (!$('#ch-cid').value || !state.chargeSel.length) return toast('CID + offences required');
      const charges = state.chargeSel.map(i => cfg.charges[i]);
      api('createCharge', { citizenid: $('#ch-cid').value, name: $('#ch-name').value, charges, notes: $('#ch-notes').value })
        .then(r => {
          if (!r.ok) return toast(r.reason || 'Failed');
          const a = r.applied || {};
          let msg = `Logged · $${r.fine} · ${r.jail}mo`;
          msg += a.online ? ` — ${a.fined ? 'fined' : ''}${a.fined && a.jailed ? ' + ' : ''}${a.jailed ? 'jailed' : ''}`.trimEnd()
                          : ' — suspect offline (record only)';
          toast(msg);
          loadRecords();
        });
    };
    $('#wr-go').onclick = () => api('createWarrant', { citizenid: $('#wr-cid').value, name: $('#wr-name').value, reason: $('#wr-reason').value })
      .then(r => { if (r.ok) { toast('Warrant issued'); loadRecords(); } else toast(r.reason || 'Failed'); });

    // Live citizen autofill — type a name or CID, pick a suggestion.
    attachCitizenAutocomplete($('#ch-cid'), p => { $('#ch-cid').value = p.citizenid; if (!$('#ch-name').value) $('#ch-name').value = p.name; });
    attachCitizenAutocomplete($('#wr-cid'), p => { $('#wr-cid').value = p.citizenid; if (!$('#wr-name').value) $('#wr-name').value = p.name; });
  });
}

/* ── BOLOs ───────────────────────────────────────────── */
function loadBolos() {
  api('listRecords').then(r => {
    const b = (r && r.bolos) || [], cfg = state.boot.config;
    $('#tab-bolo').innerHTML = `
      <div class="grid2">
        <div>
          <h3 class="section">Active BOLOs (${b.length})</h3>
          ${b.length ? b.map(x => `<div class="card">
            <div class="row"><span class="badge b2">${esc(x.type)}</span><strong>${esc(x.title)}</strong>
              <button class="btn sm ghost" data-clear="${x.id}" style="margin-left:auto">Clear</button></div>
            <div class="muted" style="margin-top:6px">${esc(x.details)}${x.reference ? ' · ref ' + esc(x.reference) : ''}</div>
            <div class="muted" style="margin-top:4px">${esc(x.officer || '—')} · ${when(x.created_at)}</div></div>`).join('')
            : '<div class="empty">No active BOLOs.</div>'}
        </div>
        <div>
          <h3 class="section">New BOLO</h3>
          <div class="card">
            <div class="field"><span class="label">Type</span><select id="bo-type" class="full">${cfg.boloTypes.map(t => `<option>${esc(t)}</option>`).join('')}</select></div>
            <div class="field"><span class="label">Title</span><input id="bo-title" class="full" placeholder="Suspect / vehicle summary" /></div>
            <div class="field"><span class="label">Reference (plate/CID)</span><input id="bo-ref" class="full" autocomplete="off" /></div>
            <div class="field"><span class="label">Details</span><textarea id="bo-det" class="full"></textarea></div>
            <button class="btn" id="bo-go">Post BOLO</button>
          </div>
        </div>
      </div>`;

    $('#tab-bolo').querySelectorAll('[data-clear]').forEach(btn => btn.onclick = () =>
      api('resolveBolo', Number(btn.dataset.clear)).then(() => { toast('BOLO cleared'); loadBolos(); }));

    $('#bo-go').onclick = () => api('createBolo', { type: $('#bo-type').value, title: $('#bo-title').value, reference: $('#bo-ref').value, details: $('#bo-det').value })
      .then(res => { if (res.ok) { toast('BOLO posted'); loadBolos(); } else toast(res.reason || 'Failed'); });

    attachCitizenAutocomplete($('#bo-ref'), p => { $('#bo-ref').value = p.citizenid; });
  });
}

function attachCitizenAutocomplete(input, onPick) {
  if (!input) return;
  let box = null;
  const close = () => { if (box) { box.remove(); box = null; } };
  const liveRun = debounce(() => {
    const v = input.value.trim();
    if (v.length < 2) { close(); return; }
    api('searchCitizens', v).then(r => {
      const rows = ((r && r.results) || []).slice(0, 8);
      close();
      if (!rows.length || document.activeElement !== input) return;
      box = document.createElement('div');
      box.className = 'ac-box';
      box.innerHTML = rows.map(x =>
        `<div class="ac-item" data-cid="${esc(x.citizenid)}" data-name="${esc(x.name)}">
          <strong>${esc(x.name || '—')}</strong> <span class="muted">${esc(x.citizenid)}</span></div>`).join('');
      input.parentNode.appendChild(box);
      box.querySelectorAll('.ac-item').forEach(it =>
        it.addEventListener('mousedown', e => {
          e.preventDefault();
          onPick({ citizenid: it.dataset.cid, name: it.dataset.name });
          close();
        }));
    });
  }, 220);
  input.addEventListener('input', liveRun);
  input.addEventListener('blur', () => setTimeout(close, 120));
}

/* ── REPORTS ─────────────────────────────────────────── */
function loadReports() {
  api('listReports').then(r => {
    const reps = r.reports || [], cfg = state.boot.config;
    $('#tab-reports').innerHTML = `
      <div class="grid2">
        <div>
          <h3 class="section">Reports (${reps.length})</h3>
          ${reps.length ? reps.map(x => `<div class="card">
            <div class="row"><span class="badge b2">${esc(x.type)}</span><strong>${esc(x.title)}</strong></div>
            <div class="muted" style="margin:6px 0">${when(x.created_at)} · ${esc(x.author)} ${x.involved && x.involved.length ? '· involved: ' + x.involved.map(esc).join(', ') : ''}</div>
            <div style="white-space:pre-wrap;font-size:13px">${esc(x.narrative)}</div></div>`).join('') : '<div class="empty">No reports filed.</div>'}
        </div>
        <div>
          <h3 class="section">File Report</h3>
          <div class="card">
            <div class="field"><span class="label">Type</span><select id="rp-type" class="full">${cfg.reportTypes.map(t => `<option>${esc(t)}</option>`).join('')}</select></div>
            <div class="field"><span class="label">Title</span><input id="rp-title" class="full" /></div>
            <div class="field"><span class="label">Involved (comma-separated)</span><input id="rp-inv" class="full" /></div>
            <div class="field"><span class="label">Narrative</span><textarea id="rp-narr" class="full" style="min-height:180px"></textarea></div>
            <button class="btn" id="rp-go">Submit Report</button>
          </div>
        </div>
      </div>`;
    $('#rp-go').onclick = () => {
      const inv = $('#rp-inv').value.split(',').map(s => s.trim()).filter(Boolean);
      api('createReport', { type: $('#rp-type').value, title: $('#rp-title').value, narrative: $('#rp-narr').value, involved: inv })
        .then(res => { if (res.ok) { toast('Report filed'); loadReports(); } else toast(res.reason || 'Failed'); });
    };
  });
}
