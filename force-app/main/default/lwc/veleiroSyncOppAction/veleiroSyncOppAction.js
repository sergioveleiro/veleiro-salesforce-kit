import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import syncOpportunity from '@salesforce/apex/VeleiroSyncService.syncOpportunity';

export default class VeleiroSyncOppAction extends LightningElement {
    @api recordId;
    @api async invoke() {
        try {
            const r = await syncOpportunity({ opportunityId: this.recordId });
            this.dispatchEvent(new ShowToastEvent({
                title: r.created ? 'Project created in Veleiro' : 'Project updated in Veleiro',
                message: `${r.name}${r.progress != null ? ' — ' + r.progress + '% complete' : ''}`,
                variant: 'success'
            }));
            getRecordNotifyChange([{ recordId: this.recordId }]);
        } catch (e) {
            const msg = e && e.body && e.body.message ? e.body.message : 'Sync failed';
            this.dispatchEvent(new ShowToastEvent({ title: 'Veleiro sync error', message: msg, variant: 'error' }));
        }
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
