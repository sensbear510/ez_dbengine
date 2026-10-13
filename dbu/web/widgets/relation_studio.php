<!-- =================================================================================
 * WIDGET: relation_studio.php
 * 1:1 Aligned with build_relation_view.dart (Strictly Read-Only Live Vector Engine)
 ================================================================================= -->
<style>
@media screen and (max-width: 768px) {
    #panelRelation {
        flex-direction: column !important;
        overflow-y: auto !important;
    }
    #panelRelation > div:first-child {
        width: 100% !important; /* Left 440px wizard expands to 100% width on mobile and portrait tablets */
        max-height: 380px !important;
    }
    #panelRelation > div:last-child {
        min-height: 400px !important; /* Ensure adequate scroll space for right-hand Live DataGrid */
    }
}
</style>

<div id="panelRelation" style="display: none; width: 100%; height: 100%; gap: 16px;">
    <!-- Left 440px Relation Wizard Panel (4-Stage Wizard) -->
    <div style="width: 440px; background: #17181c; border-radius: 6px; padding: 14px; display: flex; flex-direction: column; gap: 8px; font-size: 11px; border: 1px solid var(--border-color); overflow-y: auto;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
            <span style="font-weight: 700; font-size: 13px; color: #fff;">Relation View Properties (View Builder)</span>
            <span style="cursor: pointer; color: var(--text-muted); font-size: 16px;" onclick="closeDrawer()">⌃</span>
        </div>
        
        <label style="color:var(--text-muted); margin-top: 4px;">View Name</label>
        <input type="text" id="txtRelName" value="RL_VIEW_01" style="background:#000; border:1px solid var(--border-subtle); color:#fff; padding:6px; font-family: var(--font-mono); border-radius: 4px;" />

        <!-- Stage 1: Tables & Join Mode -->
        <div style="color:var(--accent-amber); font-weight:700; margin-top:6px;">1. Select Tables & JOIN Mode</div>
        <div style="display: flex; gap: 8px;">
            <div style="flex: 1;">
                <div style="color:#777; font-size: 10px; margin-bottom: 2px;">Master EBF Table</div>
                <select id="selRelMaster" style="width: 100%; background:#000; color:#fff; border:1px solid #444; font-size:11px; padding:5px; border-radius: 4px;" onchange="onRelMasterChanged()"></select>
            </div>
            <div style="flex: 1;">
                <div style="color:#777; font-size: 10px; margin-bottom: 2px;">Child EBF Table</div>
                <select id="selRelChild" style="width: 100%; background:#000; color:#fff; border:1px solid #444; font-size:11px; padding:5px; border-radius: 4px;" onchange="onRelChildChanged()"></select>
            </div>
        </div>
        <div style="display:flex; border:1px solid var(--accent-amber); border-radius:4px; overflow:hidden; margin-top: 4px;" id="segJoinMode">
            <button class="active" style="flex:1; background:rgba(229,155,36,0.2); border:none; color:var(--accent-amber); padding:6px; font-weight:700; font-size: 11px; cursor: pointer;" onclick="setRelJoinMode(0)">✔ LEFT JOIN</button>
            <button style="flex:1; background:transparent; border:none; color:#888; padding:6px; font-size: 11px; cursor: pointer;" onclick="setRelJoinMode(1)">INNER JOIN</button>
        </div>

        <!-- Stage 2: EDX Key Pairing -->
        <div style="color:var(--accent-amber); font-weight:700; margin-top:6px;">2. Align Master & Child EDX Keys</div>
        <div style="display: flex; gap: 8px;">
            <div style="flex: 1;">
                <div style="color:#777; font-size: 10px; margin-bottom: 2px;">Master EDX Key</div>
                <select id="selRelMTag" style="width: 100%; background:#000; color:#fff; border:1px solid #444; font-size:11px; padding:5px; border-radius: 4px;" onchange="rebuildRelProjections()"></select>
            </div>
            <div style="flex: 1;">
                <div style="color:#777; font-size: 10px; margin-bottom: 2px;">Child EDX Key</div>
                <select id="selRelCTag" style="width: 100%; background:#000; color:#fff; border:1px solid #444; font-size:11px; padding:5px; border-radius: 4px;" onchange="rebuildRelProjections()"></select>
            </div>
        </div>

        <!-- Stage 3: Field Projections Checklist -->
        <div style="display: flex; justify-content: space-between; align-items: center; margin-top:6px;">
            <span style="color:var(--accent-amber); font-weight:700;">3. Field Projections & Filter Expressions</span>
            <div>
                <span style="color:var(--accent-amber); cursor:pointer; font-size:10px;" onclick="checkAllProjections(true)">Select All</span> |
                <span style="color:#888; cursor:pointer; font-size:10px;" onclick="checkAllProjections(false)">Deselect All</span>
            </div>
        </div>
        <div style="flex:1; min-height:110px; max-height: 150px; overflow-y:auto; background:#121316; border:1px solid #333; padding:6px; border-radius: 4px;" id="relProjList"></div>

        <!-- Stage 4: Execution & Persistence Actions -->
        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:6px; margin-top:auto;">
            <button onclick="executeBuildRelation()" style="background:#282a30; border:1px solid var(--accent-amber); color:var(--accent-amber); padding:7px; font-weight:700; cursor:pointer; border-radius: 4px; font-size: 11px;">⚙ 1. Build</button>
            <button onclick="executeSaveErl()" style="background:#282a30; border:1px solid var(--accent-amber); color:var(--accent-amber); padding:7px; font-weight:700; cursor:pointer; border-radius: 4px; font-size: 11px;">💾 2. Save (.ERL)</button>
            <button onclick="executeLoadErl()" style="background:#282a30; border:1px solid var(--accent-amber); color:var(--accent-amber); padding:7px; font-weight:700; cursor:pointer; border-radius: 4px; font-size: 11px;">📁 3. Load (.ERL)</button>
            <button onclick="executeActivateRelation()" style="background:var(--accent-amber); border:none; color:#17181c; padding:7px; font-weight:800; cursor:pointer; border-radius: 4px; font-size: 11px;">▶ 4. Activate</button>
        </div>
    </div>

    <!-- Right Live Relation Vector Preview Section (Strictly Read-Only Independent DataGrid Engine) -->
    <div style="flex: 1; background: #17181c; border-radius: 6px; display: flex; flex-direction: column; overflow: hidden; border: 1px solid var(--border-color);">
        <!-- Top Master Key Seek Toolbar -->
        <div style="height: 42px; background: #1f2025; display: flex; align-items: center; padding: 0 14px; gap: 10px; border-bottom: 1px solid var(--border-color);">
            <span style="font-size: 11px; font-weight: 700; color: var(--accent-amber);" id="lblRelLiveHeader">Live Relation Vector Preview (0 REC)</span>
            <div style="margin-left: auto; display: flex; align-items: center; gap: 8px;">
                <span style="font-size: 11px; font-weight: 700; color: var(--accent-amber);">🔑 Master Key Seek:</span>
                <input type="text" id="txtRelSeekInput" placeholder="Enter Master Key..." style="background:#000; border:1px solid #444; color:#fff; padding:4px 8px; font-size:11px; width:220px; border-radius: 4px; font-family: var(--font-mono);" onkeydown="if(event.key==='Enter') executeRelSeek()" />
                <button onclick="executeRelSeek()" style="background:var(--accent-amber); border:none; color:#17181c; font-weight:800; font-size:11px; padding:5px 14px; cursor:pointer; border-radius: 4px;">Seek</button>
            </div>
        </div>

        <!-- Virtualized Live Relation DataGrid Table Container -->
        <div style="flex: 1; overflow-y: scroll; overflow-x: auto; background: var(--bg-color); position: relative; outline: none;" id="relLiveGridContainer" tabindex="0" onscroll="onRelGridScroll()">
            <div id="relEmptyHint" style="height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; color: #555;">
                <span style="font-size: 36px; opacity: 0.3;">🔗</span>
                <span style="font-size: 12px;">Click "Activate" to initialize stitched relation vector stream.</span>
            </div>
            <div id="relVirtualScroller" style="position: relative; width: 100%; display: none;">
                <table style="width: 100%; border-collapse: collapse;" id="tblRelLive">
                    <thead id="tblRelLiveHeader"></thead>
                    <tbody id="tblRelLiveBody"></tbody>
                </table>
            </div>
        </div>
    </div>
</div>

<script>
// =============================================================================
// Relation Studio Private State & Virtualized Chunk Buffer (Fully isolated from Main View)
// =============================================================================
const kRelRowHeight = 32.0;       // Aligned with build_relation_view.dart (32px)
const kRelChunkSize = 200;        // 200-record on-demand chunk
const kRelMaxCacheChunks = 10;

let relMapCache = new Map();
let relLoadingChunks = new Set();
let relTotalRecords = 0;
let relSelectedRowIdx = 0;

let relMasterFields = [];
let relChildFields = [];
let relActiveProjections = [];
let activeRelationHandle = 0;     // Native View Handle returned by C-Core

function initRelationUI() {
    const mSel = document.getElementById('selRelMaster');
    const cSel = document.getElementById('selRelChild');
    mSel.innerHTML = '';
    cSel.innerHTML = '';

    openedTabs.forEach(t => {
        const fname = t.split(/[\/\\]/).pop();
        mSel.innerHTML += `<option value="${t}">${fname}</option>`;
        cSel.innerHTML += `<option value="${t}">${fname}</option>`;
    });

    if (currentPath) mSel.value = currentPath;
    if (openedTabs.length > 1) {
        cSel.value = openedTabs.find(p => p !== currentPath) || openedTabs[0];
    } else {
        cSel.value = openedTabs[0] || '';
    }

    onRelMasterChanged();
    onRelChildChanged();
}

function onRelMasterChanged() {
    const mPath = document.getElementById('selRelMaster').value;
    if (!mPath) return;
    postApi('open', { path: mPath }, function(res) {
        if (res.status === 'success') {
            relMasterFields = res.fields;
            const mTagSel = document.getElementById('selRelMTag');
            mTagSel.innerHTML = '<option value="">(None)</option>';
            res.tags.forEach(t => {
                mTagSel.innerHTML += `<option value="${t.name}">${t.name} (${t.expression})</option>`;
            });
            rebuildRelProjections();
        } else {
            alert('Master EBF 開啟失敗: ' + (res.message || '未知錯誤'));
        }
    });
}

function onRelChildChanged() {
    const cPath = document.getElementById('selRelChild').value;
    if (!cPath) return;
    postApi('open', { path: cPath }, function(res) {
        if (res.status === 'success') {
            relChildFields = res.fields;
            const cTagSel = document.getElementById('selRelCTag');
            cTagSel.innerHTML = '<option value="">(None)</option>';
            res.tags.forEach(t => {
                cTagSel.innerHTML += `<option value="${t.name}">${t.name} (${t.expression})</option>`;
            });
            rebuildRelProjections();
        } else {
            alert('Child EBF 開啟失敗: ' + (res.message || '未知錯誤'));
        }
    });
}

function setRelJoinMode(mode) {
    relJoinMode = mode;
    const btns = document.querySelectorAll('#segJoinMode button');
    btns[0].classList.toggle('active', mode === 0);
    btns[0].style.background = mode === 0 ? 'rgba(229,155,36,0.2)' : 'transparent';
    btns[0].style.color = mode === 0 ? 'var(--accent-amber)' : '#888';
    btns[1].classList.toggle('active', mode === 1);
    btns[1].style.background = mode === 1 ? 'rgba(229,155,36,0.2)' : 'transparent';
    btns[1].style.color = mode === 1 ? 'var(--accent-amber)' : '#888';
}

function rebuildRelProjections() {
    const list = document.getElementById('relProjList');
    list.innerHTML = '';

    const mTag = document.getElementById('selRelMTag').value;
    const cTag = document.getElementById('selRelCTag').value;

    relMasterFields.forEach(f => {
        const isKey = mTag && mTag.includes(f.name);
        const marker = isKey ? ' (M)' : '';
        list.innerHTML += `
            <div style="display:flex; align-items:center; gap:6px; padding:3px 0; font-size:11px;">
                <input type="checkbox" checked class="rel-proj-cb" data-src="master" data-field="${f.name}" data-len="${f.len}" data-type="${f.type}" data-alias="${f.name}${marker}" />
                <span style="font-family:var(--font-mono); font-weight:bold;">${f.name}${marker}</span>
                <span style="margin-left:auto; color:#666; font-size:10px;">${f.type}, ${f.len}B</span>
            </div>
        `;
    });

    const cName = (document.getElementById('selRelChild').value.split(/[\/\\]/).pop() || 'child').replace(/\.ebf$/i, '');
    relChildFields.forEach(f => {
        const isKey = cTag && cTag.includes(f.name);
        const marker = isKey ? ' (C)' : '';
        const alias = `${cName}_${f.name}${marker}`;
        list.innerHTML += `
            <div style="display:flex; align-items:center; gap:6px; padding:3px 0; font-size:11px;">
                <input type="checkbox" checked class="rel-proj-cb" data-src="child" data-field="${f.name}" data-len="${f.len}" data-type="${f.type}" data-alias="${alias}" />
                <span style="font-family:var(--font-mono);">${alias}</span>
                <span style="margin-left:auto; color:#666; font-size:10px;">${f.type}, ${f.len}B</span>
            </div>
        `;
    });
}

function checkAllProjections(chk) {
    document.querySelectorAll('.rel-proj-cb').forEach(c => c.checked = chk);
}

function getSelectedProjections() {
    const list = [];
    document.querySelectorAll('.rel-proj-cb:checked').forEach(cb => {
        list.push({
            src: cb.getAttribute('data-src'),
            name: cb.getAttribute('data-field'),
            len: parseInt(cb.getAttribute('data-len') || '10'),
            type: cb.getAttribute('data-type') || 'C',
            alias: cb.getAttribute('data-alias')
        });
    });
    return list;
}

// 1. Action: Build Relation View (1:1 Aligned with build_relation_view.dart)
function executeBuildRelation(cbSuccess) {
    const mPath = document.getElementById('selRelMaster').value;
    const cPath = document.getElementById('selRelChild').value;
    const cTag = document.getElementById('selRelCTag').value || '';
    const vname = document.getElementById('txtRelName').value.trim() || 'RL_VIEW_01';

    if (!mPath) return alert('請先選取 Master 表格');
    const projs = getSelectedProjections();
    if (projs.length === 0) return alert('至少需勾選一個投影欄位！');

    postApi('rl_build_view', {
        view_name: vname,
        master_path: mPath,
        child_path: cPath,
        child_tag: cTag,
        join_mode: relJoinMode,
        projections: JSON.stringify(projs)
    }, function(res) {
        if (res.status === 'success') {
            activeRelationHandle = res.h_relation;
            if (typeof cbSuccess === 'function') {
                cbSuccess(res.h_relation);
            } else {
                alert(`⚡ [C-Core] View [${res.view_name}] Built! Handle: #0x${Number(res.h_relation).toString(16).toUpperCase()}`);
            }
        } else {
            alert('構建 Relation 失敗: ' + (res.message || '未知錯誤'));
        }
    });
}

// 2. Action: Save .ERL File
function executeSaveErl() {
    const mPath = document.getElementById('selRelMaster').value;
    const cPath = document.getElementById('selRelChild').value;
    const cTag = document.getElementById('selRelCTag').value || '';
    const vname = document.getElementById('txtRelName').value.trim() || 'RL_VIEW_01';

    const projs = getSelectedProjections();
    if (projs.length === 0) return alert('至少需勾選一個投影欄位！');

    // Generate standard filename according to build_relation_view.dart naming rules
    const mName = mPath.split(/[\/\\]/).pop().replace(/\.ebf$/i, '');
    const mTag = document.getElementById('selRelMTag').value || 'NONE';
    const cTagName = cTag || 'NONE';
    const defFileName = `${mName}_${mTag}+_+${cTagName}.erl`;

    postApi('rl_save_erl', {
        view_name: vname,
        master_path: mPath,
        child_path: cPath,
        child_tag: cTag,
        join_mode: relJoinMode,
        file_name: defFileName,
        projections: JSON.stringify(projs)
    }, function(res) {
        if (res.status === 'success') {
            alert('💾 [C-Core] Saved Relation File (.ERL): ' + res.path);
        } else {
            alert('儲存 .ERL 失敗: ' + (res.message || '未知錯誤'));
        }
    });
}

// 3. Action: Load .ERL File
function executeLoadErl() {
    openFileExplorer('', (erlPath) => {
        const mPath = document.getElementById('selRelMaster').value;
        const cPath = document.getElementById('selRelChild').value;

        postApi('rl_load_erl', {
            erl_path: erlPath,
            master_path: mPath,
            child_path: cPath
        }, function(res) {
            if (res.status === 'success') {
                activeRelationHandle = res.h_relation;
                alert(`📁 [C-Core] Loaded .ERL! Handle: #0x${Number(res.h_relation).toString(16).toUpperCase()}`);
            } else {
                alert('載入 .ERL 失敗: ' + (res.message || '未知錯誤'));
            }
        });
    });
}

// 4. Action: Activate View (Aligned with _executeActivateView in build_relation_view.dart)
function executeActivateRelation() {
    const mPath = document.getElementById('selRelMaster').value;
    if (!mPath) return alert('請先選取 Master 表格');

    relActiveProjections = getSelectedProjections();
    if (relActiveProjections.length === 0) return alert('至少需勾選一個投影欄位！');

    // Trigger Build first if Handle is 0
    if (activeRelationHandle === 0) {
        executeBuildRelation((hRel) => {
            _activateRelationViewInternal();
        });
    } else {
        _activateRelationViewInternal();
    }
}

function _activateRelationViewInternal() {
    relMapCache.clear();
    relLoadingChunks.clear();
    relSelectedRowIdx = 0;

    const thead = document.getElementById('tblRelLiveHeader');
    let thHtml = '<tr><th style="width:50px; text-align:center; height:34px; background:#1f2025; color:var(--accent-amber); border-bottom:1px solid var(--border-color); border-right:1px solid var(--border-color); position:sticky; top:0; z-index:10;">#</th>';
    relActiveProjections.forEach(p => {
        thHtml += `<th style="width:140px; min-width:140px; height:34px; background:#1f2025; color:var(--accent-amber); border-bottom:1px solid var(--border-color); border-right:1px solid var(--border-color); position:sticky; top:0; z-index:10; padding:0 10px;">${p.alias}</th>`;
    });
    thHtml += '</tr>';
    thead.innerHTML = thHtml;

    // Fetch initial chunk batch
    ensureRelRowBuffered(0);
}

function onRelGridScroll() {
    renderRelVisibleWindow();
}

function renderRelVisibleWindow() {
    if (relTotalRecords <= 0) return;

    const container = document.getElementById('relLiveGridContainer');
    const scrollTop = container.scrollTop;
    const viewportHeight = container.clientHeight || 400;

    let startIdx = Math.floor(scrollTop / kRelRowHeight) - 5;
    let endIdx = Math.ceil((scrollTop + viewportHeight) / kRelRowHeight) + 5;

    startIdx = Math.max(0, startIdx);
    endIdx = Math.min(relTotalRecords - 1, endIdx);

    ensureRelRowBuffered(startIdx);
    ensureRelRowBuffered(endIdx);

    const tbody = document.getElementById('tblRelLiveBody');
    tbody.innerHTML = '';

    const topSpacer = startIdx * kRelRowHeight;
    if (topSpacer > 0) {
        const trTop = document.createElement('tr');
        trTop.style.height = `${topSpacer}px`;
        tbody.appendChild(trTop);
    }

    for (let i = startIdx; i <= endIdx; i++) {
        const rData = relMapCache.get(i);
        const tr = document.createElement('tr');
        tr.style.height = `${kRelRowHeight}px`;
        tr.style.background = (i % 2 === 0) ? '#1c1d22' : '#17181c';

        if (i === relSelectedRowIdx) {
            tr.style.background = 'rgba(52, 152, 219, 0.25)';
        }

        if (rData) {
            let rowHtml = `<td style="text-align:center; color:var(--accent-amber); font-weight:700; border-right:1px solid rgba(255,255,255,0.03);">${rData.recno}</td>`;
            relActiveProjections.forEach(p => {
                const val = rData.data[p.alias] || '';
                rowHtml += `<td style="width:140px; padding:0 10px; border-right:1px solid rgba(255,255,255,0.03); font-family:var(--font-mono); white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${val}</td>`;
            });
            tr.innerHTML = rowHtml;
        } else {
            tr.innerHTML = `<td style="text-align:center;">${i + 1}</td><td colspan="${relActiveProjections.length}" style="color:#555;">Loading relation chunk...</td>`;
        }

        tr.onclick = () => selectRelRowIndex(i);
        tbody.appendChild(tr);
    }

    const bottomSpacer = (relTotalRecords - 1 - endIdx) * kRelRowHeight;
    if (bottomSpacer > 0) {
        const trBottom = document.createElement('tr');
        trBottom.style.height = `${bottomSpacer}px`;
        tbody.appendChild(trBottom);
    }
}

// On-demand vector buffer loader (invoking C-Core ez_rl_get_record_vector)
function ensureRelRowBuffered(targetIndex) {
    if (targetIndex < 0 || (relTotalRecords > 0 && targetIndex >= relTotalRecords)) return;
    if (relMapCache.has(targetIndex)) return;

    const chunkId = Math.floor(targetIndex / kRelChunkSize);
    if (relLoadingChunks.has(chunkId)) return;
    relLoadingChunks.add(chunkId);

    const offset = chunkId * kRelChunkSize;
    const mPath = document.getElementById('selRelMaster').value;
    const mTag = document.getElementById('selRelMTag').value || '';

    postApi('rl_fetch_vector', {
        master_path: mPath,
        h_relation: activeRelationHandle,
        offset: offset,
        limit: kRelChunkSize,
        master_tag: mTag,
        projections: JSON.stringify(relActiveProjections)
    }, function(res) {
        relLoadingChunks.delete(chunkId);
        if (res.status === 'success') {
            relTotalRecords = res.total;
            document.getElementById('lblRelLiveHeader').innerText = `Live Relation Vector Preview (${relTotalRecords} REC)`;

            document.getElementById('relEmptyHint').style.display = 'none';
            const scroller = document.getElementById('relVirtualScroller');
            scroller.style.display = 'block';
            scroller.style.height = `${Math.max(relTotalRecords * kRelRowHeight, 100)}px`;

            if (relMapCache.size > kRelChunkSize * kRelMaxCacheChunks) {
                relMapCache.clear();
            }

            res.rows.forEach((r, idx) => {
                relMapCache.set(offset + idx, r);
            });

            renderRelVisibleWindow();
            document.getElementById('relLiveGridContainer').focus();
        } else {
            alert('讀取關聯向量資料失敗: ' + (res.message || '未知錯誤'));
        }
    });
}

function selectRelRowIndex(index) {
    if (index < 0 || index >= relTotalRecords) return;
    relSelectedRowIdx = index;
    renderRelVisibleWindow();

    // Synchronize Master EBF cursor (1-based)
    const mPath = document.getElementById('selRelMaster').value;
    const mTag = document.getElementById('selRelMTag').value || '';
    postApi('seek_locate', {
        path: mPath,
        mode: 'locate',
        start_rec: index + 1
    }, function() {});
}

function ensureRelRowVisible(index) {
    const container = document.getElementById('relLiveGridContainer');
    const targetY = index * kRelRowHeight;
    const currentY = container.scrollTop;
    const viewportHeight = container.clientHeight;

    if (targetY < currentY) {
        container.scrollTop = targetY;
    } else if (targetY + kRelRowHeight > currentY + viewportHeight) {
        container.scrollTop = targetY + kRelRowHeight - viewportHeight;
    }
}

// Master Key Seek (Aligned with build_relation_view.dart)
function executeRelSeek() {
    const key = document.getElementById('txtRelSeekInput').value.trim();
    if (!key) return;

    const mPath = document.getElementById('selRelMaster').value;
    const mTag = document.getElementById('selRelMTag').value || 'idx_code';

    postApi('seek_locate', {
        path: mPath,
        mode: 'seek',
        tag_name: mTag,
        key: key
    }, function(res) {
        if (res.status === 'success' && res.found) {
            const targetIdx = res.recno - 1;
            selectRelRowIndex(targetIdx);
            ensureRelRowVisible(targetIdx);
        } else {
            alert(`Master Key Seek Not Found: [${key}] (Tag: ${mTag})`);
        }
    });
}

document.getElementById('relLiveGridContainer').addEventListener('keydown', (e) => {
    if (relTotalRecords <= 0) return;

    if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (relSelectedRowIdx < relTotalRecords - 1) {
            selectRelRowIndex(relSelectedRowIdx + 1);
            ensureRelRowVisible(relSelectedRowIdx);
        }
    } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        if (relSelectedRowIdx > 0) {
            selectRelRowIndex(relSelectedRowIdx - 1);
            ensureRelRowVisible(relSelectedRowIdx);
        }
    } else if (e.key === 'Home') {
        e.preventDefault();
        selectRelRowIndex(0);
        ensureRelRowVisible(0);
    } else if (e.key === 'End') {
        e.preventDefault();
        selectRelRowIndex(relTotalRecords - 1);
        ensureRelRowVisible(relTotalRecords - 1);
    }
});
</script>