import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO } from 'c/veleiroBrand';
import getSuggestions from '@salesforce/apex/VeleiroLinkController.getSuggestions';
import linkAll from '@salesforce/apex/VeleiroLinkController.linkAll';

export default class VeleiroLinkHome extends LightningElement {
    logoUrl = VELEIRO_LOGO;
    loading = false;
    scanned = false;
    overview;
    rows = [];
    onlySuggested = false;

    matchingInfo = {
        primaryField: { fieldPath: 'Name' },
        additionalFields: [{ fieldPath: 'Website' }]
    };
    displayInfo = { additionalFields: ['Website'] };

    connectedCallback() {
        this.scan();
    }

    // Trae los clients de Veleiro sin vincular, cada uno con su cuenta sugerida.
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
        const selected = r.suggestedAccountId || null;
        return {
            ...r,
            selectedAccountId: selected,
            ...this.describe(r, selected)
        };
    }

    // Texto de ayuda y alternativas, segun lo que este elegido en esa fila.
    describe(row, selectedId) {
        const options = row.options || [];
        const chosen = options.find((o) => o.accountId === selectedId);
        const alternatives = options.filter((o) => o.accountId !== selectedId);
        let note;
        if (selectedId) {
            note = chosen ? `Suggested: ${chosen.reason}` : 'Account chosen by you';
        } else if (options.length) {
            note = 'Not sure about these — pick one if it fits';
        } else {
            note = 'No suggestion — search for the account';
        }
        return {
            chosen: !!selectedId,
            note,
            alternatives,
            hasAlternatives: alternatives.length > 0
        };
    }

    update(clientId, selectedId) {
        this.rows = this.rows.map((r) =>
            r.clientId === clientId
                ? { ...r, selectedAccountId: selectedId, ...this.describe(r, selectedId) }
                : r
        );
    }

    handlePick(event) {
        this.update(event.target.dataset.client, event.detail.recordId || null);
    }

    handleUseSuggestion(event) {
        const { client, account } = event.currentTarget.dataset;
        this.update(client, account);
    }

    handleToggleFilter(event) {
        this.onlySuggested = event.target.checked;
    }

    handleClear() {
        this.rows = this.rows.map((r) => ({ ...r, selectedAccountId: null, ...this.describe(r, null) }));
    }

    get visibleRows() {
        return this.onlySuggested ? this.rows.filter((r) => (r.options || []).length > 0) : this.rows;
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

    async handleLink() {
        const pairs = this.rows
            .filter((r) => r.selectedAccountId)
            .map((r) => ({ accountId: r.selectedAccountId, clientId: r.clientId }));
        if (!pairs.length) return;

        this.loading = true;
        try {
            const res = await linkAll({ pairsJson: JSON.stringify(pairs) });
            const skipped = res.skipped
                ? ` ${res.skipped} skipped: already linked.`
                : '';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: `${res.linked} account${res.linked === 1 ? '' : 's'} linked to Veleiro`,
                    message: `Sync them when you want Veleiro to carry the Salesforce id too.${skipped}`,
                    variant: res.linked ? 'success' : 'warning'
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
