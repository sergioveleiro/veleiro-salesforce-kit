import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO } from 'c/veleiroBrand';
import { MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getClientSummary from '@salesforce/apex/VeleiroSyncService.getClientSummary';
import syncAccount from '@salesforce/apex/VeleiroSyncService.syncAccount';
import findClientCandidates from '@salesforce/apex/VeleiroSyncService.findClientCandidates';
import linkAccountToClient from '@salesforce/apex/VeleiroSyncService.linkAccountToClient';
import createClientForAccount from '@salesforce/apex/VeleiroSyncService.createClientForAccount';

export default class VeleiroPanel extends LightningElement {
    @api recordId;
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;
    summary;
    loading = false;
    // Candidatos encontrados en Veleiro: mientras haya, se muestra el modal de confirmacion.
    candidates = [];
    _wired;

    @wire(getClientSummary, { accountId: '$recordId' })
    wired(result) {
        this._wired = result;
        if (result.data) {
            this.summary = result.data;
        }
    }

    get synced() {
        return this.summary && this.summary.synced;
    }

    get showCandidates() {
        return this.candidates.length > 0;
    }

    // Antes de crear un client nuevo, revisa si ese cliente ya existe en Veleiro.
    async handleSync() {
        if (this.synced) {
            await this.runSync();
            return;
        }
        this.loading = true;
        try {
            const match = await findClientCandidates({ accountId: this.recordId });
            if (match && match.candidates && match.candidates.length) {
                this.candidates = match.candidates;
                return; // el usuario decide: vincular o crear
            }
        } catch (e) {
            // Si la busqueda falla no bloqueamos el sync: seguimos al camino normal.
            this.candidates = [];
        } finally {
            this.loading = false;
        }
        await this.runSync();
    }

    async runSync() {
        this.loading = true;
        try {
            const res = await syncAccount({ accountId: this.recordId });
            this.toast(
                res.created ? 'Client created in Veleiro' : 'Client updated in Veleiro',
                `${res.name} (v${res.version})`,
                'success'
            );
            await refreshApex(this._wired);
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    async handleLink(event) {
        const clientId = event.target.dataset.id;
        this.candidates = [];
        this.loading = true;
        try {
            const res = await linkAccountToClient({ accountId: this.recordId, clientId });
            this.toast('Linked to the existing Veleiro client', `${res.name} (v${res.version})`, 'success');
            await refreshApex(this._wired);
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    async handleCreateAnyway() {
        this.candidates = [];
        this.loading = true;
        try {
            const res = await createClientForAccount({ accountId: this.recordId });
            this.toast('Client created in Veleiro', `${res.name} (v${res.version})`, 'success');
            await refreshApex(this._wired);
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    handleCancel() {
        this.candidates = [];
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    toastError(e) {
        const msg = e && e.body && e.body.message ? e.body.message : 'Sync failed';
        this.dispatchEvent(new ShowToastEvent({ title: 'Veleiro sync error', message: msg, variant: 'error' }));
    }
}
