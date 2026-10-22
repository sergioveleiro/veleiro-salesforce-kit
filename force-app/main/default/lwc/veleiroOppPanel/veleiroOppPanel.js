import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO } from 'c/veleiroBrand';
import { MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getProjectSummary from '@salesforce/apex/VeleiroSyncService.getProjectSummary';
import getProjectLive from '@salesforce/apex/VeleiroSyncService.getProjectLive';
import syncOpportunity from '@salesforce/apex/VeleiroSyncService.syncOpportunity';

export default class VeleiroOppPanel extends LightningElement {
    @api recordId;
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;
    summary;
    live;
    loading = false;
    _wired;

    _connected = false;

    connectedCallback() {
        this._connected = true;
        // El wire puede haber resuelto antes de que el componente estuviera montado.
        if (this.synced && !this.live) this.loadLive();
    }

    disconnectedCallback() {
        this._connected = false;
    }

    @wire(getProjectSummary, { opportunityId: '$recordId' })
    wired(result) {
        this._wired = result;
        if (result.data) {
            this.summary = result.data;
            if (result.data.synced && this._connected) {
                this.loadLive();
            }
        }
    }

    async loadLive() {
        try {
            this.live = await getProjectLive({ opportunityId: this.recordId });
        } catch (e) {
            // La barra es secundaria: si el callout falla, dejamos la vista de linkage.
            this.live = undefined;
        }
    }

    get synced() {
        return this.summary && this.summary.synced;
    }

    // Recien sincronizado: el project puede tener reuniones que antes no se podian pedir.
    refreshMeetings() {
        const meetings = this.template.querySelector('c-veleiro-meetings');
        if (meetings) meetings.refresh();
        const pulse = this.template.querySelector('c-veleiro-pulse');
        if (pulse) pulse.refresh();
    }

    get hasProgress() {
        return this.live && this.live.progress !== null && this.live.progress !== undefined;
    }

    get progressValue() {
        return this.hasProgress ? this.live.progress : 0;
    }

    get statusLabel() {
        return this.live && this.live.status ? this.live.status : null;
    }

    async handleSync() {
        this.loading = true;
        try {
            const res = await syncOpportunity({ opportunityId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: res.created ? 'Project created in Veleiro' : 'Project updated in Veleiro',
                    message: `${res.name} (v${res.version})`,
                    variant: 'success'
                })
            );
            await refreshApex(this._wired);
            await this.loadLive();
            this.refreshMeetings();
        } catch (e) {
            const msg = e && e.body && e.body.message ? e.body.message : 'Sync failed';
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Veleiro sync error', message: msg, variant: 'error' })
            );
        } finally {
            this.loading = false;
        }
    }
}
