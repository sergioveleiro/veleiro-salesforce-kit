import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO } from 'c/veleiroBrand';
import { MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getObjects from '@salesforce/apex/VeleiroMappingController.getObjects';
import getFields from '@salesforce/apex/VeleiroMappingController.getFields';
import getTargets from '@salesforce/apex/VeleiroMappingController.getTargets';
import getMappingsFor from '@salesforce/apex/VeleiroMappingController.getMappingsFor';
import defaultTemplate from '@salesforce/apex/VeleiroMappingController.defaultTemplate';
import getMappings from '@salesforce/apex/VeleiroMappingController.getMappings';
import saveMappings from '@salesforce/apex/VeleiroMappingController.saveMappings';
import getSyncConfig from '@salesforce/apex/VeleiroMappingController.getSyncConfig';
import saveSyncConfig from '@salesforce/apex/VeleiroMappingController.saveSyncConfig';
import getStatus from '@salesforce/apex/VeleiroMappingController.getStatus';
import saveToken from '@salesforce/apex/VeleiroMappingController.saveToken';
import saveEnvironment from '@salesforce/apex/VeleiroMappingController.saveEnvironment';

const ENTITY_OPTIONS = [
    { label: 'Client', value: 'client' },
    { label: 'Project', value: 'project' }
];
const DIRECTION_OPTIONS = [
    { label: 'Bidirectional (both ways)', value: 'bidirectional' },
    { label: 'Salesforce → Veleiro only', value: 'sf_to_veleiro' },
    { label: 'Veleiro → Salesforce only', value: 'veleiro_to_sf' }
];
const WINNER_OPTIONS = [
    { label: 'Salesforce wins', value: 'salesforce' },
    { label: 'Veleiro wins', value: 'veleiro' }
];
const FREQUENCY_OPTIONS = [
    { label: 'Off (no scheduled pull)', value: 'off' },
    { label: 'Every hour', value: 'hourly' },
    { label: 'Daily', value: 'daily' }
];
const TRIGGER_OPTIONS = [
    { label: 'Manual (only when you click Sync)', value: 'manual' },
    { label: 'Automatic on record create', value: 'auto' }
];

export default class VeleiroMappingHome extends LightningElement {
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;
    entityOptions = ENTITY_OPTIONS;

    // 'list' = ver mapeos configurados; 'editor' = crear/editar uno. Nunca los dos a la vez.
    mode = 'list';

    objectOptions = [];
    fieldOptions = [];
    @track targetOptions = [];   // targets de Veleiro (picklist) para la entidad seleccionada
    selectedObject;
    selectedEntity;
    entityLocked = false; // al editar un objeto ya mapeado, su entidad es fija (uno-a-uno)
    objectLocked = false; // al editar, no se cambia el objeto
    @track rows = [];
    deletedIds = [];
    hint;
    saving = false;

    @track summary = [];
    _seq = 0;

    // ---- integration config (global) ----
    directionOptions = DIRECTION_OPTIONS;
    winnerOptions = WINNER_OPTIONS;
    frequencyOptions = FREQUENCY_OPTIONS;
    triggerOptions = TRIGGER_OPTIONS;
    syncDirection = 'bidirectional';
    syncWinner = 'salesforce';
    syncFrequency = 'off';
    syncTrigger = 'manual';
    savingConfig = false;

    // ---- connection status ----
    connected = false;
    tokenSet = false;
    statusMessage = 'Checking connection…';
    nextRun = '';
    tokenInput = '';
    checking = true;
    editingConn = false; // muestra los campos editables (token + entorno) solo bajo demanda
    environment = '';
    appBase = '';
    selectedEnvironment = 'Production';
    savingEnv = false;
    environmentOptions = [
        { label: 'Production (app.veleiro.ai)', value: 'Production' },
        { label: 'Beta (app.beta.veleiro.dev)', value: 'Beta' }
    ];

    connectedCallback() {
        getObjects().then((r) => { this.objectOptions = r; }).catch(() => {});
        this.loadSummary(true);
        this.loadConfig();
        this.loadStatus();
    }

    // ---- connection ----
    loadStatus() {
        this.checking = true;
        return getStatus()
            .then((s) => {
                this.tokenSet = s.tokenSet === 'true';
                this.connected = s.connected === 'true';
                this.statusMessage = s.message || '';
                this.nextRun = s.nextRun || '';
                this.environment = s.environment || '';
                this.appBase = s.appBase || '';
                if (s.environment === 'Production' || s.environment === 'Beta') {
                    this.selectedEnvironment = s.environment;
                }
            })
            .catch(() => { this.connected = false; this.statusMessage = 'Could not check connection.'; })
            .finally(() => { this.checking = false; });
    }

    handleTokenChange(event) { this.tokenInput = event.detail.value; }

    handleSaveToken() {
        this.checking = true;
        const token = (this.tokenInput || '').trim();
        const step = token ? saveToken({ token }) : Promise.resolve();
        step
            .then(() => {
                this.tokenInput = '';
                return this.loadStatus();
            })
            .then(() => {
                if (this.connected) this.editingConn = false; // conectó -> colapsa a la vista resumida
                this.dispatchEvent(new ShowToastEvent({
                    title: this.connected ? 'Connected to Veleiro' : 'Not connected',
                    message: this.statusMessage,
                    variant: this.connected ? 'success' : 'warning'
                }));
            })
            .catch(() => { this.checking = false; });
    }

    // Conexión: vista resumida (conectado) vs editor (primera vez o al editar).
    get showConnSummary() { return this.connected && !this.editingConn; }
    get showConnEditor() { return !this.connected || this.editingConn; }
    startEditConn() { this.editingConn = true; }
    doneEditConn() { this.editingConn = false; this.tokenInput = ''; }

    handleEnvironmentChange(event) {
        const env = event.detail.value;
        this.selectedEnvironment = env;
        this.savingEnv = true;
        this.checking = true;
        saveEnvironment({ environment: env })
            .then(() => this.loadStatus())
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Environment set to ' + env,
                    message: this.connected ? 'Connected to ' + this.appBase : this.statusMessage,
                    variant: this.connected ? 'success' : 'warning'
                }));
            })
            .catch((e) => {
                const msg = e && e.body && e.body.message ? e.body.message : 'Could not switch environment';
                this.dispatchEvent(new ShowToastEvent({ title: 'Switch failed', message: msg, variant: 'error' }));
            })
            .finally(() => { this.savingEnv = false; });
    }

    get statusClass() {
        if (this.checking) return 'veleiro-status veleiro-status-checking';
        return this.connected ? 'veleiro-status veleiro-status-ok' : 'veleiro-status veleiro-status-bad';
    }
    get statusLabel() {
        if (this.checking) return 'Checking connection…';
        return this.connected ? 'Connected to Veleiro' : 'Not connected';
    }
    get statusDot() {
        if (this.checking) return '⚪';
        return this.connected ? '🟢' : '🔴';
    }
    get nextRunText() {
        if (!this.connected) return '';
        if (this.syncFrequency === 'off' || !this.nextRun) return 'Scheduled pull is off.';
        return 'Next pull from Veleiro: ' + this.nextRun;
    }
    get envText() {
        if (!this.environment) return '';
        const host = this.appBase ? this.appBase.replace('https://', '') : '';
        return host ? this.environment + ' · ' + host : this.environment;
    }
    get tokenPlaceholder() {
        return this.tokenSet ? 'Paste a new token to replace the current one' : 'Paste your Veleiro API token (starts with vlr_)';
    }
    get saveTokenLabel() {
        return this.tokenSet ? 'Update & re-test' : 'Save & test connection';
    }

    // ---- vista ----
    get showEditor() { return this.mode === 'editor'; }
    get showList() { return this.mode === 'list'; }
    get hasSummary() { return this.summary && this.summary.length > 0; }
    get showEmpty() { return this.mode === 'list' && !this.hasSummary; }

    // Filas con el valor calculado para el combobox de target (isCustom -> '__custom__').
    get displayRows() {
        return this.rows.map((r) => ({ ...r, comboValue: r.isCustom ? '__custom__' : r.target }));
    }

    get canSave() { return this.selectedObject && this.selectedEntity; }
    get saveDisabled() { return this.saving || !this.canSave; }
    get editorTitle() { return this.objectLocked ? 'Edit mapping' : 'New mapping'; }

    // ---- integration config ----
    loadConfig() {
        getSyncConfig()
            .then((c) => {
                if (c) {
                    this.syncDirection = c.direction || 'bidirectional';
                    this.syncWinner = c.winner || 'salesforce';
                    this.syncFrequency = c.frequency || 'off';
                    this.syncTrigger = c.trigger || 'manual';
                }
            })
            .catch(() => {});
    }
    handleDirectionChange(event) { this.syncDirection = event.detail.value; }
    handleWinnerChange(event) { this.syncWinner = event.detail.value; }
    handleFrequencyChange(event) { this.syncFrequency = event.detail.value; }
    handleTriggerChange(event) { this.syncTrigger = event.detail.value; }

    handleSaveConfig() {
        this.savingConfig = true;
        saveSyncConfig({ direction: this.syncDirection, winner: this.syncWinner, frequency: this.syncFrequency, triggerMode: this.syncTrigger })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Integration configured',
                    message: 'Direction, conflict winner and pull schedule saved.',
                    variant: 'success'
                }));
            })
            .catch((e) => {
                const msg = e && e.body && e.body.message ? e.body.message : 'Could not save the integration config';
                this.dispatchEvent(new ShowToastEvent({ title: 'Save failed', message: msg, variant: 'error' }));
            })
            .finally(() => { this.savingConfig = false; });
    }

    // ---- lista de mapeos ----
    loadSummary(setInitialMode) {
        return getMappings()
            .then((data) => {
                const byPair = {};
                (data || []).forEach((m, i) => {
                    const key = m.SObject__c + '|' + (m.Veleiro_Entity__c || '');
                    if (!byPair[key]) {
                        byPair[key] = { key, object: m.SObject__c, entity: m.Veleiro_Entity__c || '—', rows: [] };
                    }
                    byPair[key].rows.push({
                        key: key + '|' + m.SF_Field__c + '|' + i, // indice: nunca colisiona aunque haya repetidos
                        sfField: m.SF_Field__c,
                        target: m.Veleiro_Target__c,
                        type: m.Target_Type__c
                    });
                });
                this.summary = Object.values(byPair);
                if (setInitialMode) {
                    // primera vez: si no hay nada, abre el editor para crear el primero
                    if (this.summary.length) { this.mode = 'list'; }
                    else { this.startNew(); }
                }
            })
            .catch(() => {});
    }

    existingEntityFor(object) {
        const g = (this.summary || []).find((s) => s.object === object && s.entity !== '—');
        return g ? g.entity : null;
    }

    // ---- entrar al editor ----
    startNew() {
        this.mode = 'editor';
        this.objectLocked = false;
        this.entityLocked = false;
        this.selectedObject = undefined;
        this.selectedEntity = undefined;
        this.fieldOptions = [];
        this.rows = [];
        this.deletedIds = [];
        this.hint = undefined;
    }

    editMapping(event) {
        const obj = event.currentTarget.dataset.object;
        const ent = event.currentTarget.dataset.entity;
        this.mode = 'editor';
        this.objectLocked = true;   // editando: objeto fijo
        this.entityLocked = true;   // uno-a-uno: entidad fija
        this.selectedObject = obj;
        this.selectedEntity = ent;
        this.fieldOptions = [];
        getFields({ sobjectName: obj }).then((r) => { this.fieldOptions = r; }).catch(() => {});
        this.loadPair();
    }

    cancelEdit() {
        // si aun no hay mapeos, no hay lista a la que volver -> quedarse en editor vacio
        this.mode = this.hasSummary ? 'list' : 'editor';
        if (this.mode === 'editor') this.startNew();
    }

    // ---- editor: pickers ----
    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.fieldOptions = [];
        getFields({ sobjectName: this.selectedObject }).then((r) => { this.fieldOptions = r; }).catch(() => {});
        const existing = this.existingEntityFor(this.selectedObject);
        if (existing) {
            // ya existe -> uno-a-uno: fija entidad y carga para editar
            this.selectedEntity = existing;
            this.entityLocked = true;
        } else {
            this.selectedEntity = undefined;
            this.entityLocked = false;
            this.rows = [];
            this.hint = undefined;
        }
        this.loadPair();
    }

    handleEntityChange(event) {
        if (this.entityLocked) return;
        this.selectedEntity = event.detail.value;
        this.loadPair();
    }

    loadPair() {
        if (!this.canSave) return;
        this.hint = undefined;
        this.deletedIds = [];

        // 1) FILAS primero — rápido, SIN callout. Aparecen de inmediato (evita la carrera
        //    donde se guardaba vacío si el usuario daba Save antes de que resolviera getTargets).
        getMappingsFor({ sobjectName: this.selectedObject, entity: this.selectedEntity })
            .then((existing) => {
                if (existing && existing.length) {
                    this.rows = existing.map((m) => this.toRow(m.Id, m.SF_Field__c, m.Veleiro_Target__c));
                    return null;
                }
                return defaultTemplate({ sobjectName: this.selectedObject, entity: this.selectedEntity });
            })
            .then((tpl) => {
                if (tpl === null) return;
                if (tpl && tpl.length) {
                    this.rows = tpl.map((m) => this.toRow(null, m.SF_Field__c, m.Veleiro_Target__c));
                    this.hint = 'Default mapping auto-filled — review and Save.';
                } else {
                    this.rows = [this.toRow(null, '', '')];
                    this.hint = 'No default for this combination — pick fields and Save.';
                }
            })
            .catch(() => {});

        // 2) TARGETS (picklist) en paralelo — hace callout, NO bloquea las filas. Al llegar,
        //    recalcula isCustom para que los defaults se vean como selección y no como texto libre.
        getTargets({ entity: this.selectedEntity })
            .then((opts) => {
                this.targetOptions = opts || [];
                this.rows = this.rows.map((r) => ({ ...r, isCustom: !!r.target && !this.targetValues.has(r.target) }));
            })
            .catch(() => { this.targetOptions = []; });
    }

    get targetValues() {
        return new Set((this.targetOptions || []).map((o) => o.value));
    }

    // Sugerencia canonica desde el campo SF (espejo de VeleiroTargets.suggest en Apex).
    suggestTarget(sfField) {
        if (!sfField) return '';
        let base = sfField;
        if (/__c$/i.test(base)) base = base.slice(0, -3);
        if (base.includes('__')) base = base.split('__').pop();
        const norm = base.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '');
        if (norm === 'name') return 'name';
        return 'sf_' + norm;
    }

    // Fila del editor. isCustom = el target no esta en el catalogo (se edita a mano).
    toRow(id, sfField, target) {
        this._seq += 1;
        const isCustom = !!target && !this.targetValues.has(target);
        return { key: 'r' + this._seq, id, sfField, target: target || '', isCustom };
    }

    // Al elegir el campo SF, autosugiere el target si aun esta vacio (homologa nombres).
    handleFieldChange(event) {
        const key = event.currentTarget.dataset.key;
        const sfField = event.detail.value;
        this.rows = this.rows.map((r) => {
            if (r.key !== key) return r;
            const next = { ...r, sfField };
            if (!r.target) {
                const sug = this.suggestTarget(sfField);
                next.target = sug;
                next.isCustom = !this.targetValues.has(sug);
            }
            return next;
        });
    }

    // Combobox de target: '__custom__' abre el input libre; cualquier otro fija el valor.
    handleTargetSelect(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.detail.value;
        this.rows = this.rows.map((r) => {
            if (r.key !== key) return r;
            if (value === '__custom__') return { ...r, isCustom: true };
            return { ...r, isCustom: false, target: value };
        });
    }

    handleCustomTargetChange(event) {
        this.updateRow(event.currentTarget.dataset.key, 'target', event.detail.value);
    }

    updateRow(key, prop, value) {
        this.rows = this.rows.map((r) => (r.key === key ? { ...r, [prop]: value } : r));
    }
    addRow() { this.rows = [...this.rows, this.toRow(null, '', '')]; }
    removeRow(event) {
        const key = event.currentTarget.dataset.key;
        const row = this.rows.find((r) => r.key === key);
        if (row && row.id) this.deletedIds = [...this.deletedIds, row.id];
        this.rows = this.rows.filter((r) => r.key !== key);
    }

    handleSave() {
        // Solo filas completas (campo SF + target). Evita guardar vacío en silencio.
        const payload = this.rows
            .map((r) => ({ id: r.id, sfField: r.sfField, target: r.target }))
            .filter((r) => r.sfField && r.target);
        if (payload.length === 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Nothing to save yet',
                message: 'Add at least one row with a Salesforce field and a Veleiro target before saving.',
                variant: 'warning'
            }));
            return;
        }
        this.saving = true;
        saveMappings({
            sobjectName: this.selectedObject,
            entity: this.selectedEntity,
            rows: payload,
            deletedIds: this.deletedIds,
            rowsJson: JSON.stringify(payload) // el string round-trips; el array tipado llega null (gotcha LWC->Apex)
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Mapping saved',
                    message: this.selectedObject + ' → ' + this.selectedEntity,
                    variant: 'success'
                }));
                this.deletedIds = [];
                return this.loadSummary(false);
            })
            .then(() => { this.mode = 'list'; })  // volver a la lista (una sola superficie)
            .catch((e) => {
                const msg = e && e.body && e.body.message ? e.body.message : 'Could not save mapping';
                this.dispatchEvent(new ShowToastEvent({ title: 'Save failed', message: msg, variant: 'error' }));
            })
            .finally(() => { this.saving = false; });
    }
}
