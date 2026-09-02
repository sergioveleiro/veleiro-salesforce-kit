import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import VELEIRO_LOGO from '@salesforce/resourceUrl/VeleiroLogo';
import VELEIRO_MASCOT from '@salesforce/resourceUrl/VeleiroMascot';
import getClientSummary from '@salesforce/apex/VeleiroSyncService.getClientSummary';
import syncAccount from '@salesforce/apex/VeleiroSyncService.syncAccount';

export default class VeleiroPanel extends LightningElement {
    @api recordId;
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;
    summary;
    loading = false;
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

    async handleSync() {
        this.loading = true;
        try {
            const res = await syncAccount({ accountId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: res.created ? 'Client created in Veleiro' : 'Client updated in Veleiro',
                    message: `${res.name} (v${res.version})`,
                    variant: 'success'
                })
            );
            await refreshApex(this._wired);
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
