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

<div id="panelSchema" style="display: none; width: 100%; height: 100%; gap: 16px;">
    <!-- Left 380px Instruction and Path Configuration Panel -->
    <div style="width: 380px; background: #17181c; border-radius: 6px; padding: 14px; display: flex; flex-direction: column; gap: 10px; font-size: 11px; border: 1px solid var(--border-color);">
        <div style="font-weight: 700; font-size: 13px; color: #fff;" id="lblSchemaTitle">Modify Existing EBF Schema (ez_dbalter)</div>
        
        <label style="color:var(--text-muted); margin-top: 4px;">Database File Path / Name (.ebf)</label>
        <div style="display: flex; gap: 6px;">
            <input type="text" id="txtSchemaEbfPath" style="flex:1; background:#000; border:1px solid var(--border-subtle); color:#fff; padding:6px; font-size:11px; border-radius: 4px; font-family: var(--font-mono);" />
            <button onclick="openFileExplorer('', (p) => loadSchemaFromFile(p))" style="padding:4px 10px; background:var(--card-color); border:1px solid #555; color:#fff; font-size:11px; cursor:pointer; border-radius: 4px;">📁 Load EBF</button>
        </div>

        <div style="color:var(--accent-amber); font-weight:700; margin-top:8px;">🛠️ Workbench Instructions</div>
        <div style="color:var(--text-muted); font-size:10px; line-height:1.5;">
            Define table columns (EZ_FIELD_NODE) and specify EDX index tags below. Click "Save EBF" to initialize the physical database via C-Core engine.
        </div>

        <div style="color:var(--accent-amber); font-weight:700; margin-top:8px;">📄 Field Type Reference</div>
        <div style="color:var(--text-muted); font-size:10px; line-height:1.6; font-family: var(--font-mono);">
            C : Character (Text)<br>
            N : Numeric (Float)<br>
            I : Integer (4-Byte)<br>
            D : Date (YYYYMMDD)<br>
            L : Logical (Boolean T/F)<br>
            B : Binary / BLOB (>=24B)
        </div>

        <div style="color:#777; font-size:10px; line-height:1.4; margin-top: 6px;">
            Combined Key: Use plus (+) to concatenate multiple fields (e.g., date + code). All fields processed as strings.
        </div>

        <button onclick="executeSaveSchema()" style="margin-top:auto; height:40px; background:var(--accent-amber); border:none; font-weight:800; color:#17181c; cursor:pointer; border-radius:4px; font-size: 12px; display: flex; align-items: center; justify-content: center; gap: 6px;">
            <span>💾</span> <span id="btnSaveSchemaText">Save EBF</span>
        </button>
    </div>

    <!-- Right Dual-Track Definition Workspace (Flex 3 : Flex 2) -->
    <div style="flex: 1; display: flex; flex-direction: column; gap: 12px; overflow: hidden;">
        <!-- 1. EZ_FIELD_NODE Columns Definition (Flex 3) -->
        <div style="flex: 3; background: #17181c; border-radius: 6px; padding: 12px; border: 1px solid var(--border-color); display: flex; flex-direction: column; overflow: hidden;">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                <span style="font-size: 12px; font-weight: 700; color: var(--accent-amber);">1. EZ_FIELD_NODE Columns Definition</span>
                <button onclick="addSchemaFieldRow()" style="background:none; border:1px solid var(--accent-amber); color:var(--accent-amber); font-size:10px; padding:4px 10px; border-radius: 4px; cursor:pointer; font-weight: 700;">+ Add Field</button>
            </div>
            <div style="flex: 1; overflow-y: auto;">
                <table style="width: 100%; font-size: 11px;" id="tblSchemaFields">
                    <thead>
                        <tr>
                            <th style="width:36px;">#</th>
                            <th>Field Name</th>
                            <th style="width:140px;">Type</th>
                            <th style="width:100px;">Length</th>
                            <th style="width:40px; text-align: center;"></th>
                        </tr>
                    </thead>
                    <tbody></tbody>
                </table>
            </div>
        </div>

        <!-- 2. EDX Index Tags Builder (Flex 2) -->
        <div style="flex: 2; background: #17181c; border-radius: 6px; padding: 12px; border: 1px solid var(--border-color); display: flex; flex-direction: column; overflow: hidden;">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                <span style="font-size: 12px; font-weight: 700; color: var(--accent-amber);">2. EDX Index Tags Builder</span>
                <button onclick="addSchemaIndexRow()" style="background:none; border:1px solid var(--accent-amber); color:var(--accent-amber); font-size:10px; padding:4px 10px; border-radius: 4px; cursor:pointer; font-weight: 700;">+ Add Index</button>
            </div>
            <div style="flex: 1; overflow-y: auto;">
                <table style="width: 100%; font-size: 11px;" id="tblSchemaIndexes">
                    <thead>
                        <tr>
                            <th style="width:80px;">Tag#</th>
                            <th style="width:200px;">Tag Name</th>
                            <th>Index Expression (Fields)</th>
                            <th style="width:40px; text-align: center;"></th>
                        </tr>
                    </thead>
                    <tbody></tbody>
                </table>
            </div>
        </div>
    </div>
</div>