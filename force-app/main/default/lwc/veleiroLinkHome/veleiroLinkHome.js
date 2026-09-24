import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO } from 'c/veleiroBrand';
import getSuggestions from '@salesforce/apex/VeleiroLinkController.getSuggestions';
import searchAccounts from '@salesforce/apex/VeleiroLinkController.searchAccounts';
import linkAll from '@salesforce/apex/VeleiroLinkController.linkAll';

const NONE = '';

export default class VeleiroLinkHome extends LightningElement {
    logoUrl = VELEIRO_LOGO;
    loading = false;
    scanned = false;
    overview;
    rows = [];
    onlySuggested = false;

    connectedCallback() {
        this.scan();
    }

    // Trae los clients de Veleiro sin vincular, cada uno con sus Accounts candidatos.
    async scan() {
        this.loading = true;
        try {
            const data = await getSuggestions();
            this.overview = data;
            this.rows = (data.rows || []).map((r) => this.toRow(r));
            this.scanned = true;
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    toRow(r) {
        const options = (r.options || []).map((o) => ({
            label: o.website ? `${o.name} — ${o.website}` : o.name,
            value: o.accountId,
            reason: o.reason
        }));
        return {
            ...r,
            options: [{ label: '— none —', value: NONE }, ...options],
            selectedAccountId: r.suggestedAccountId || NONE,
            hasOptions: options.length > 0,
            searchTerm: '',
            note: r.suggestedReason || 'No match found — search for an account'
        };
    }

    get visibleRows() {
        return this.onlySuggested ? this.rows.filter((r) => r.hasOptions) : this.rows;
    }

    get hasRows() {
        return this.visibleRows.length > 0;
    }

    get selectedCount() {
        return this.rows.filter((r) => r.selectedAccountId).length;
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
            return 'This org has too many accounts to match here. Link them with Data Loader instead.';
        }
        if (this.overview.clientsUnlinked === 0) {
            return 'Every Veleiro client is already linked to an account.';
        }
        return 'No Veleiro clients to show.';
    }

    handleSelect(event) {
        const clientId = event.target.dataset.client;
        const value = event.detail.value;
        this.rows = this.rows.map((r) => (r.clientId === clientId ? { ...r, selectedAccountId: value } : r));
    }

    handleToggleFilter(event) {
        this.onlySuggested = event.target.checked;
    }

    // Busca Accounts por nombre para el client de esa fila y los agrega al selector.
    async handleSearch(event) {
        const clientId = event.target.dataset.client;
        const term = event.target.value;
        if (!term || term.length < 2) return;
        try {
            const found = await searchAccounts({ term });
            this.rows = this.rows.map((r) => {
                if (r.clientId !== clientId) return r;
                const extra = found.map((o) => ({
                    label: o.website ? `${o.name} — ${o.website}` : o.name,
                    value: o.accountId,
                    reason: o.reason
                }));
                const seen = new Set(r.options.map((o) => o.value));
                const merged = [...r.options, ...extra.filter((o) => !seen.has(o.value))];
                return {
                    ...r,
                    options: merged,
                    hasOptions: merged.length > 1,
                    note: extra.length ? `${extra.length} account(s) found` : 'No account matches that search'
                };
            });
        } catch (e) {
            this.toastError(e);
        }
    }

    handleClear() {
        this.rows = this.rows.map((r) => ({ ...r, selectedAccountId: NONE }));
    }

    async handleLink() {
        const pairs = this.rows
            .filter((r) => r.selectedAccountId)
            .map((r) => ({ accountId: r.selectedAccountId, clientId: r.clientId }));
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
