// ==UserScript==
// @name         Onshape -> Bambu Studio
// @namespace    https://github.com/gordoa40/onshape-bambu
// @version      0.1.0
// @description  Send selected parts from the current Onshape Part Studio to Bambu Studio.
// @match        https://cad.onshape.com/documents/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  const BRIDGE = 'http://127.0.0.1:7777';

  // ---------- URL parsing ----------
  // /documents/{did}/w/{wid}/e/{eid}
  function parseIds() {
    const m = location.pathname.match(/\/documents\/([^\/]+)\/w\/([^\/]+)\/e\/([^\/?#]+)/);
    if (!m) return null;
    return { documentId: m[1], workspaceId: m[2], elementId: m[3] };
  }

  function currentNames() {
    // Best-effort. The document title contains both doc + element names.
    const title = document.title.replace(/ – Onshape.*$/, '');
    // Doc names show as "Document Name - Element Name" in tab title.
    const dash = title.lastIndexOf(' - ');
    if (dash > 0) {
      return { documentName: title.slice(0, dash).trim(), elementName: title.slice(dash + 3).trim() };
    }
    return { documentName: title.trim(), elementName: '' };
  }

  // ---------- UI ----------
  const css = `
  #osb-btn {
    position: fixed; right: 18px; bottom: 18px; z-index: 999999;
    background: #00b386; color: #fff; border: none; border-radius: 999px;
    padding: 10px 16px; font: 600 13px system-ui, sans-serif;
    box-shadow: 0 4px 14px rgba(0,0,0,.25); cursor: pointer;
  }
  #osb-btn:hover { background: #009973; }
  #osb-modal-bg {
    position: fixed; inset: 0; background: rgba(0,0,0,.55); z-index: 999998;
    display: flex; align-items: center; justify-content: center;
  }
  #osb-modal {
    background: #1f2226; color: #eee; width: 420px; max-height: 70vh;
    border-radius: 10px; padding: 18px; font: 13px system-ui, sans-serif;
    display: flex; flex-direction: column; gap: 10px;
    box-shadow: 0 12px 40px rgba(0,0,0,.5);
  }
  #osb-modal h3 { margin: 0; font-size: 15px; }
  #osb-list {
    overflow-y: auto; border: 1px solid #333; border-radius: 6px;
    padding: 8px; background: #14171a; flex: 1; min-height: 80px;
  }
  #osb-list label { display: flex; gap: 8px; padding: 4px 2px; cursor: pointer; }
  #osb-list label:hover { background: #232830; }
  .osb-actions { display: flex; gap: 8px; justify-content: flex-end; }
  .osb-actions button {
    border: none; border-radius: 6px; padding: 8px 14px; font-weight: 600; cursor: pointer;
  }
  .osb-btn-primary { background: #00b386; color: #fff; }
  .osb-btn-secondary { background: #353a40; color: #eee; }
  #osb-status { font-size: 12px; color: #9aa; min-height: 16px; }
  .osb-row-tools { display: flex; gap: 10px; font-size: 12px; }
  .osb-row-tools a { color: #6cf; cursor: pointer; text-decoration: underline; }
  `;
  const style = document.createElement('style');
  style.textContent = css;
  document.head.appendChild(style);

  function makeButton() {
    if (document.getElementById('osb-btn')) return;
    const btn = document.createElement('button');
    btn.id = 'osb-btn';
    btn.textContent = 'Send to Bambu';
    btn.onclick = openModal;
    document.body.appendChild(btn);
  }

  function closeModal() {
    const bg = document.getElementById('osb-modal-bg');
    if (bg) bg.remove();
  }

  async function openModal() {
    const ids = parseIds();
    if (!ids) {
      alert('Could not detect document/element from URL. Open a Part Studio first.');
      return;
    }

    closeModal();
    const bg = document.createElement('div');
    bg.id = 'osb-modal-bg';
    bg.innerHTML = `
      <div id="osb-modal">
        <h3>Send to Bambu Studio</h3>
        <div class="osb-row-tools">
          <a id="osb-all">All</a><a id="osb-none">None</a>
        </div>
        <div id="osb-list">Loading parts…</div>
        <div id="osb-status"></div>
        <div class="osb-actions">
          <button class="osb-btn-secondary" id="osb-cancel">Cancel</button>
          <button class="osb-btn-primary" id="osb-send">Export &amp; Open</button>
        </div>
      </div>`;
    bg.addEventListener('click', (e) => { if (e.target === bg) closeModal(); });
    document.body.appendChild(bg);

    document.getElementById('osb-cancel').onclick = closeModal;

    let parts = [];
    const listEl = document.getElementById('osb-list');
    try {
      const url = `${BRIDGE}/parts?documentId=${ids.documentId}&workspaceId=${ids.workspaceId}&elementId=${ids.elementId}`;
      const r = await fetch(url);
      if (!r.ok) throw new Error(`bridge ${r.status}: ${await r.text()}`);
      parts = (await r.json()).parts;
    } catch (e) {
      listEl.innerHTML = `<div style="color:#f77">Could not reach bridge at ${BRIDGE}.<br>Is the helper running?<br><br><code>${escapeHtml(String(e))}</code></div>`;
      return;
    }

    if (!parts.length) {
      listEl.innerHTML = '<div style="color:#bbb">No parts found in this element.</div>';
      return;
    }
    listEl.innerHTML = parts.map(p => `
      <label><input type="checkbox" value="${p.partId}" data-name="${escapeAttr(p.name)}" checked> ${escapeHtml(p.name)}</label>
    `).join('');

    document.getElementById('osb-all').onclick = () =>
      listEl.querySelectorAll('input[type=checkbox]').forEach(c => c.checked = true);
    document.getElementById('osb-none').onclick = () =>
      listEl.querySelectorAll('input[type=checkbox]').forEach(c => c.checked = false);

    document.getElementById('osb-send').onclick = async () => {
      const checked = [...listEl.querySelectorAll('input[type=checkbox]:checked')];
      if (!checked.length) { setStatus('Select at least one part.'); return; }
      const partIds = checked.map(c => c.value);
      const partNames = Object.fromEntries(checked.map(c => [c.value, c.dataset.name]));
      const names = currentNames();
      setStatus(`Exporting ${partIds.length} part(s)…`);

      try {
        const r = await fetch(`${BRIDGE}/export`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ...ids, partIds, partNames, ...names, openInBambu: true }),
        });
        if (!r.ok) throw new Error(`bridge ${r.status}: ${await r.text()}`);
        const j = await r.json();
        setStatus(`Sent ${j.files.length} file(s) to Bambu Studio.`);
        setTimeout(closeModal, 900);
      } catch (e) {
        setStatus(`Error: ${e}`);
      }
    };
  }

  function setStatus(s) {
    const el = document.getElementById('osb-status');
    if (el) el.textContent = s;
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  }
  function escapeAttr(s) { return escapeHtml(s); }

  // Onshape is a SPA — re-attach the button on navigation.
  const obs = new MutationObserver(() => makeButton());
  obs.observe(document.body, { childList: true, subtree: true });
  makeButton();
})();
