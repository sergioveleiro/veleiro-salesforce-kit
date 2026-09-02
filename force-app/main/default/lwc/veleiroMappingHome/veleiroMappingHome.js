import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import VELEIRO_LOGO from '@salesforce/resourceUrl/VeleiroLogo';
import VELEIRO_MASCOT from '@salesforce/resourceUrl/VeleiroMascot';
import getObjects from '@salesforce/apex/VeleiroMappingController.getObjects';
import getFields from '@salesforce/apex/VeleiroMappingController.getFields';
import getMappingsFor from '@salesforce/apex/VeleiroMappingController.getMappingsFor';
import defaultTemplate from '@salesforce/apex/VeleiroMappingController.defaultTemplate';
import getMappings from '@salesforce/apex/VeleiroMappingController.getMappings';
import saveMappings from '@salesforce/apex/VeleiroMappingController.saveMappings';

const ENTITY_OPTIONS = [
    { label: 'Client', value: 'client' },
    { label: 'Project', value: 'project' }
];
const TYPE_OPTIONS = [
    { label: 'Standard', value: 'Standard' },
    { label: 'Additional Field', value: 'Additional Field' }
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
    @track rows = [];
    deletedIds = [];
    hint;
    saving = false;

    @track summary = [];
    _seq = 0;

    connectedCallback() {
        getObjects().then((r) => { this.objectOptions = r; }).catch(() => {});
        this.loadSummary();
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

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.fieldOptions = [];
        getFields({ sobjectName: this.selectedObject })
            .then((r) => { this.fieldOptions = r; })
            .catch(() => {});
        this.maybeLoadPair();
    }

    handleEntityChange(event) {
        this.selectedEntity = event.detail.value;
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
