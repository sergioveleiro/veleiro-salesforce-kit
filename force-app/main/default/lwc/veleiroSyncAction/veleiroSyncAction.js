import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import syncAccount from '@salesforce/apex/VeleiroSyncService.syncAccount';

export default class VeleiroSyncAction extends LightningElement {
    @api recordId;

    @api async invoke() {
        try {
            const res = await syncAccount({ accountId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: res.created ? 'Client created in Veleiro' : 'Client updated in Veleiro',
                    message: `${res.name} (v${res.version})`,
                    variant: 'success'
                })
            );
            getRecordNotifyChange([{ recordId: this.recordId }]);
        } catch (e) {
            const msg = e && e.body && e.body.message ? e.body.message : 'Sync failed';
            this.dispatchEvent(new ShowToastEvent({ title: 'Veleiro sync error', message: msg, variant: 'error' }));
        }
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
