import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO } from 'c/veleiroBrand';
import { MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getSuggestions from '@salesforce/apex/VeleiroLinkController.getSuggestions';
import linkAll from '@salesforce/apex/VeleiroLinkController.linkAll';

export default class VeleiroLinkHome extends LightningElement {
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;
    loading = false;
    scanned = false;
    overview;
    rows = [];

    connectedCallback() {
        this.scan();
    }

    // Trae los clients de Veleiro y los cruza con los Accounts sin vincular.
    async scan() {
        this.loading = true;
        try {
            const data = await getSuggestions();
            this.overview = data;
            // Las coincidencias fuertes vienen marcadas: son las que conviene aplicar en bloque.
            this.rows = (data.suggestions || []).map((s) => ({
                ...s,
                selected: s.confidence === 'high',
                strong: s.confidence === 'high'
            }));
            this.scanned = true;
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get selectedCount() {
        return this.rows.filter((r) => r.selected).length;
    }

    get linkLabel() {
        return `Link ${this.selectedCount} selected`;
    }

    get nothingToLink() {
        return this.selectedCount === 0;
    }

    get emptyMessage() {
        if (!this.overview) return '';
        if (this.overview.truncated) {
            return 'This org has too many unlinked accounts to match safely. Link them with Data Loader instead.';
        }
        if (this.overview.accountsUnlinked === 0) {
            return 'Every account is already linked to Veleiro.';
        }
        return 'No matches found. These accounts will create new clients when you sync them.';
    }

    handleToggle(event) {
        const key = event.target.dataset.key;
        this.rows = this.rows.map((r) => (r.key === key ? { ...r, selected: event.target.checked } : r));
    }

    handleSelectStrong() {
        this.rows = this.rows.map((r) => ({ ...r, selected: r.strong }));
    }

    handleClear() {
        this.rows = this.rows.map((r) => ({ ...r, selected: false }));
    }

    async handleLink() {
        const pairs = this.rows
            .filter((r) => r.selected)
            .map((r) => ({ accountId: r.accountId, clientId: r.clientId }));
        if (!pairs.length) return;

        this.loading = true;
        try {
            const count = await linkAll({ pairsJson: JSON.stringify(pairs) });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: `${count} account${count === 1 ? '' : 's'} linked to Veleiro`,
                    message: 'Sync them when you want Veleiro to carry the Salesforce id too.',
                    variant: 'success'
                })
            );
            await this.scan();
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    toastError(e) {
        const msg = e && e.body && e.body.message ? e.body.message : 'Could not reach Veleiro';
        this.dispatchEvent(new ShowToastEvent({ title: 'Veleiro error', message: msg, variant: 'error' }));
    }
}
