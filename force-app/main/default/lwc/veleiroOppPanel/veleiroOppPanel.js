import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import VELEIRO_LOGO from '@salesforce/resourceUrl/VeleiroLogo';
import VELEIRO_MASCOT from '@salesforce/resourceUrl/VeleiroMascot';
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

    @wire(getProjectSummary, { opportunityId: '$recordId' })
    wired(result) {
        this._wired = result;
        if (result.data) {
            this.summary = result.data;
            if (result.data.synced) {
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
