import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO } from 'c/veleiroBrand';
import { MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getObjects from '@salesforce/apex/VeleiroMappingController.getObjects';
import getFields from '@salesforce/apex/VeleiroMappingController.getFields';
import getMappingsFor from '@salesforce/apex/VeleiroMappingController.getMappingsFor';
import defaultTemplate from '@salesforce/apex/VeleiroMappingController.defaultTemplate';
import getMappings from '@salesforce/apex/VeleiroMappingController.getMappings';
import saveMappings from '@salesforce/apex/VeleiroMappingController.saveMappings';
import getSyncConfig from '@salesforce/apex/VeleiroMappingController.getSyncConfig';
import saveSyncConfig from '@salesforce/apex/VeleiroMappingController.saveSyncConfig';

const ENTITY_OPTIONS = [
    { label: 'Client', value: 'client' },
    { label: 'Project', value: 'project' }
];
const TYPE_OPTIONS = [
    { label: 'Standard', value: 'Standard' },
    { label: 'Additional Field', value: 'Additional Field' }
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

export default class VeleiroMappingHome extends LightningElement {
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;
    entityOptions = ENTITY_OPTIONS;
    typeOptions = TYPE_OPTIONS;

    objectOptions = [];
    fieldOptions = [];
    selectedObject;
    selectedEntity;
    entityLocked = false; // true cuando el objeto ya tiene una entidad mapeada (uno-a-uno)
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
    syncDirection = 'bidirectional';
    syncWinner = 'salesforce';
    syncFrequency = 'off';
    savingConfig = false;

    connectedCallback() {
        getObjects().then((r) => { this.objectOptions = r; }).catch(() => {});
        this.loadSummary();
        this.loadConfig();
    }

    loadConfig() {
        getSyncConfig()
            .then((c) => {
                if (c) {
                    this.syncDirection = c.direction || 'bidirectional';
                    this.syncWinner = c.winner || 'salesforce';
                    this.syncFrequency = c.frequency || 'off';
                }
            })
            .catch(() => {});
    }

    handleDirectionChange(event) { this.syncDirection = event.detail.value; }
    handleWinnerChange(event) { this.syncWinner = event.detail.value; }
    handleFrequencyChange(event) { this.syncFrequency = event.detail.value; }

    handleSaveConfig() {
        this.savingConfig = true;
        saveSyncConfig({
            direction: this.syncDirection,
            winner: this.syncWinner,
            frequency: this.syncFrequency
        })
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

    loadSummary() {
        getMappings()
            .then((data) => {
                const byPair = {};
                (data || []).forEach((m) => {
                    const key = m.SObject__c + '|' + (m.Veleiro_Entity__c || '');
                    if (!byPair[key]) {
                        byPair[key] = {
                            key,
                            object: m.SObject__c,
                            entity: m.Veleiro_Entity__c || '—',
                            rows: []
                        };
                    }
                    byPair[key].rows.push({
                        key: key + '|' + m.SF_Field__c,
                        sfField: m.SF_Field__c,
                        target: m.Veleiro_Target__c,
                        type: m.Target_Type__c
                    });
                });
                this.summary = Object.values(byPair);
            })
            .catch(() => {});
    }

    get canEdit() {
        return this.selectedObject && this.selectedEntity;
    }
    get saveDisabled() {
        return this.saving || !this.canEdit;
    }
    get hasSummary() {
        return this.summary && this.summary.length > 0;
    }

    // Devuelve la entidad ya mapeada para un objeto (uno-a-uno), o null si no existe.
    existingEntityFor(object) {
        const g = (this.summary || []).find((s) => s.object === object && s.entity !== '—');
        return g ? g.entity : null;
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.fieldOptions = [];
        getFields({ sobjectName: this.selectedObject })
            .then((r) => { this.fieldOptions = r; })
            .catch(() => {});
        // uno-a-uno: si el objeto ya esta mapeado, fija su entidad y no deja elegir otra
        const existing = this.existingEntityFor(this.selectedObject);
        if (existing) {
            this.selectedEntity = existing;
            this.entityLocked = true;
        } else {
            this.selectedEntity = undefined;
            this.entityLocked = false;
            this.rows = [];
            this.hint = undefined;
        }
        this.maybeLoadPair();
    }

    handleEntityChange(event) {
        if (this.entityLocked) return; // objeto ya mapeado -> entidad fija
        this.selectedEntity = event.detail.value;
        this.maybeLoadPair();
    }

    // Click en una tarjeta de "Configured mappings" -> cargar arriba para editar.
    editMapping(event) {
        const obj = event.currentTarget.dataset.object;
        const ent = event.currentTarget.dataset.entity;
        this.selectedObject = obj;
        this.fieldOptions = [];
        getFields({ sobjectName: obj })
            .then((r) => { this.fieldOptions = r; })
            .catch(() => {});
        this.selectedEntity = ent;
        this.entityLocked = true;
        this.maybeLoadPair();
    }

    maybeLoadPair() {
        if (!this.canEdit) return;
        this.hint = undefined;
        getMappingsFor({ sobjectName: this.selectedObject, entity: this.selectedEntity })
            .then((existing) => {
                if (existing && existing.length) {
                    this.rows = existing.map((m) => this.toRow(m.Id, m.SF_Field__c, m.Veleiro_Target__c, m.Target_Type__c));
                    return null;
                }
                // sin mapeos guardados -> intenta autopopular defaults conocidos
                return defaultTemplate({ sobjectName: this.selectedObject, entity: this.selectedEntity });
            })
            .then((tpl) => {
                if (tpl === null) return; // ya habia guardados
                if (tpl && tpl.length) {
                    this.rows = tpl.map((m) => this.toRow(null, m.SF_Field__c, m.Veleiro_Target__c, m.Target_Type__c));
                    this.hint = 'Default mapping auto-filled for ' + this.selectedObject +
                        ' → ' + this.selectedEntity + '. Review and Save.';
                } else {
                    this.rows = [this.toRow(null, '', '', 'Additional Field')];
                    this.hint = 'No default for this combination — define the fields manually, then Save.';
                }
            })
            .catch(() => {});
        this.deletedIds = [];
    }

    toRow(id, sfField, target, type) {
        this._seq += 1;
        return { key: 'r' + this._seq, id, sfField, target, type: type || 'Additional Field' };
    }

    handleFieldChange(event) {
        this.updateRow(event.currentTarget.dataset.key, 'sfField', event.detail.value);
    }
    handleTargetChange(event) {
        this.updateRow(event.currentTarget.dataset.key, 'target', event.detail.value);
    }
    handleTypeChange(event) {
        this.updateRow(event.currentTarget.dataset.key, 'type', event.detail.value);
    }
    updateRow(key, prop, value) {
        this.rows = this.rows.map((r) => (r.key === key ? { ...r, [prop]: value } : r));
    }

    addRow() {
        this.rows = [...this.rows, this.toRow(null, '', '', 'Additional Field')];
    }
    removeRow(event) {
        const key = event.currentTarget.dataset.key;
        const row = this.rows.find((r) => r.key === key);
        if (row && row.id) this.deletedIds = [...this.deletedIds, row.id];
        this.rows = this.rows.filter((r) => r.key !== key);
    }

    handleSave() {
        this.saving = true;
        const payload = this.rows.map((r) => ({
            id: r.id,
            sfField: r.sfField,
            target: r.target,
            type: r.type
        }));
        saveMappings({
            sobjectName: this.selectedObject,
            entity: this.selectedEntity,
            rows: payload,
            deletedIds: this.deletedIds
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Mapping saved',
                    message: this.selectedObject + ' → ' + this.selectedEntity,
                    variant: 'success'
                }));
                this.deletedIds = [];
                this.loadSummary();
                this.maybeLoadPair();
            })
            .catch((e) => {
                const msg = e && e.body && e.body.message ? e.body.message : 'Could not save mapping';
                this.dispatchEvent(new ShowToastEvent({ title: 'Save failed', message: msg, variant: 'error' }));
            })
            .finally(() => { this.saving = false; });
    }
}
