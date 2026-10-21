<!-- =================================================================================
 * WIDGET: schema_designer.php
 * 1:1 Aligned with schema_designer_view.dart (C-Core Physical Alter/Create)
 ================================================================================= -->
<style>
@media screen and (max-width: 768px) {
    #panelSchema {
        flex-direction: column !important;
        overflow-y: auto !important;
    }
    #panelSchema > div:first-child {
        width: 100% !important; /* Left configuration panel expands to 100% width on mobile and portrait tablets */
    }
    #panelSchema > div:last-child {
        min-height: 480px !important;
    }
}
</style>

<!-- Schema Designer Panel (Aligned with schema_designer_view.dart) -->
<div id="panelSchema" style="display:flex; width:100%; height:100%; gap:12px;">
    <!-- Left Configuration Panel (360px) -->
    <div style="width: 360px; background: #1c1d22; border-right: 1px solid var(--border-color); display:flex; flex-direction:column; padding:12px; gap:10px;">
        <div style="display:flex; justify-content:space-between; align-items:center;">
            <span id="lblSchemaTitle" style="font-weight:700; color:#fff; font-size:12px;">EBF Schema Designer</span>
            <span style="cursor:pointer; font-size:11px; color:#888;" onclick="closeDrawer()">✕ Close</span>
        </div>

        <!-- Target File Path and Explorer Button -->
        <div style="display:flex; gap:6px;">
            <input type="text" id="txtSchemaEbfPath" placeholder="Physical EBF Path (e.g. data/table.ebf)" 
                   style="flex:1; height:28px; background:#121316; border:1px solid var(--border-subtle); color:#fff; padding:0 8px; font-size:11px; font-family:var(--font-mono); border-radius:4px;" />
            <button onclick="openFileExplorer('', (p) => loadSchemaFromFile(p))" 
                    style="height:28px; background:#282a30; border:1px solid var(--border-subtle); color:#aaa; font-size:11px; padding:0 10px; border-radius:4px; cursor:pointer;">
                📁 Load EBF
            </button>
        </div>

        <!-- Schema Field Reference Guide -->
        <div style="flex:1; overflow-y:auto; font-size:11px; color:#aaa; line-height:1.5; border:1px solid rgba(255,255,255,0.05); padding:8px; border-radius:4px; background:#16171a;">
            <div style="font-weight:700; color:var(--accent-amber); margin-bottom:4px;">Field Types Reference</div>
            <div><b style="color:#fff;">C</b> : Character (Text String)</div>
            <div><b style="color:#fff;">N</b> : Numeric Float (Fixed Length)</div>
            <div><b style="color:#fff;">I</b> : 4-Byte Signed Integer</div>
            <div><b style="color:#fff;">D</b> : Date (YYYYMMDD, 8 Bytes)</div>
            <div><b style="color:#fff;">L</b> : Logical Boolean (T/F, 1 Byte)</div>
            <div><b style="color:#fff;">B</b> : Binary BLOB (Length >= 24)</div>
            <div style="margin-top:8px; border-top:1px solid #333; padding-top:6px; color:#888;">
                <b>Index Rules:</b><br>
                - Use <code>+</code> to concatenate composite fields (e.g., <code>CODE+DATE</code>).<br>
                - BLOB (Type B) fields cannot be used as index keys.
            </div>
        </div>

        <!-- Save / Alter Action Button -->
        <button id="btnSaveSchema" onclick="saveSchemaWorkflow()" 
                style="height:36px; background:var(--accent-amber); border:none; color:#17181c; font-weight:800; font-size:12px; border-radius:4px; cursor:pointer;">
            ⚡ Generate & Create EBF
        </button>
    </div>

    <!-- Right Fields & Tags Workbench -->
    <div style="flex:1; display:flex; flex-direction:column; gap:12px; height:100%; overflow:hidden;">
        <!-- 1. EZ_FIELD_NODE Section (Flex: 3) -->
        <div style="flex:3; display:flex; flex-direction:column; background:#1c1d22; border:1px solid var(--border-color); border-radius:4px; padding:10px;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                <span style="font-size:12px; font-weight:700; color:var(--accent-amber);">1. EZ_FIELD_NODE Columns Definition</span>
                <button onclick="addSchemaFieldRow()" style="height:24px; background:#282a30; border:1px solid var(--accent-amber); color:var(--accent-amber); font-size:11px; font-weight:700; padding:0 8px; border-radius:3px; cursor:pointer;">
                    + Add Field
                </button>
            </div>
            <div style="flex:1; overflow-y:auto;">
                <table id="tblSchemaFields" style="width:100%;">
                    <thead>
                        <tr style="color:#888; font-size:11px; border-bottom:1px solid #333;">
                            <th style="width:40px; text-align:center;">#</th>
                            <th>Field Name</th>
                            <th style="width:100px;">Type</th>
                            <th style="width:80px;">Length</th>
                            <th style="width:50px; text-align:center;">Del</th>
                        </tr>
                    </thead>
                    <tbody style="font-family:var(--font-mono); font-size:11px;"></tbody>
                </table>
            </div>
        </div>

        <!-- 2. EDX Index Tags Section (Flex: 2) -->
        <div style="flex:2; display:flex; flex-direction:column; background:#1c1d22; border:1px solid var(--border-color); border-radius:4px; padding:10px;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                <span style="font-size:12px; font-weight:700; color:var(--accent-amber);">2. EDX Index Tags Builder</span>
                <button onclick="addSchemaIndexRow()" style="height:24px; background:#282a30; border:1px solid var(--accent-amber); color:var(--accent-amber); font-size:11px; font-weight:700; padding:0 8px; border-radius:3px; cursor:pointer;">
                    + Add Index Tag
                </button>
            </div>
            <div style="flex:1; overflow-y:auto;">
                <table id="tblSchemaIndexes" style="width:100%;">
                    <thead>
                        <tr style="color:#888; font-size:11px; border-bottom:1px solid #333;">
                            <th style="width:60px;">Slot</th>
                            <th style="width:160px;">Tag Name</th>
                            <th>Index Expression (Fields)</th>
                            <th style="width:70px; text-align:center;">Unique</th>
                            <th style="width:50px; text-align:center;">Del</th>
                        </tr>
                    </thead>
                    <tbody style="font-family:var(--font-mono); font-size:11px;"></tbody>
                </table>
            </div>
        </div>
    </div>
</div>