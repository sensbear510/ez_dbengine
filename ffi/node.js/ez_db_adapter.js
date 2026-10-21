/* =================================================================================
 * ez_db_adapter.js - Shared Pool Data Mapper for Node.js Services
 * ================================================================================= */

const { EzDbEngine } = require('./ez_dbengine');
const path = require('path');

class EzDbAdapter {
    static #instance = null;

    constructor() {
        this.engine = EzDbEngine.getInstance();
        this.handles = new Map();
    }

    static getInstance() {
        if (!EzDbAdapter.#instance) {
            EzDbAdapter.#instance = new EzDbAdapter();
        }
        return EzDbAdapter.#instance;
    }

    getHandle(tableName) {
        const filePath = path.join('data', `${tableName}.ebf`);
        if (!this.handles.has(filePath)) {
            const h = this.engine.use(filePath);
            this.handles.set(filePath, h);
        }
        return this.handles.get(filePath);
    }

    insert(tableName, data) {
        const h = this.getHandle(tableName);
        const fields = this.engine.getFdt(h);

        const values = fields.map(f => (data[f.name] !== undefined ? data[f.name] : ''));
        const csvPayload = values.join(',');

        const status = this.engine.append(h, csvPayload, 1, ',');
        if (status !== 0) {
            throw new Error(`Atomic append failed on table ${tableName} | ${this.engine.getDetailedError(status)}`);
        }

        this.engine.commit(h);
        return this.engine.getRecordCount(h);
    }
}

module.exports = EzDbAdapter;