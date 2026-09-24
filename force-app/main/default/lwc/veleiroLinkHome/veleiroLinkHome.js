import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO } from 'c/veleiroBrand';
import getSuggestions from '@salesforce/apex/VeleiroLinkController.getSuggestions';
import linkAll from '@salesforce/apex/VeleiroLinkController.linkAll';
import linkAndSync from '@salesforce/apex/VeleiroLinkController.linkAndSync';

export default class VeleiroLinkHome extends LightningElement {
    logoUrl = VELEIRO_LOGO;
    loading = false;
    scanned = false;
    overview;
    rows = [];
    onlySuggested = false;
    // Par elegido (objeto|entidad). Sale de lo configurado en Veleiro Mappings.
    pairValue;

    matchingInfo = { primaryField: { fieldPath: 'Name' } };
    displayInfo = { additionalFields: [] };

    connectedCallback() {
        this.scan();
    }

    async scan() {
        this.loading = true;
        try {
            const [sobjectName, entity] = (this.pairValue || '|').split('|');
            const data = await getSuggestions({ sobjectName, entity });
            this.overview = data;
            this.pairValue = data.sobjectName ? `${data.sobjectName}|${data.entity}` : undefined;
            this.rows = (data.rows || []).map((r) => this.toRow(r));
            this.scanned = true;
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    toRow(r) {
        const selected = r.suggestedRecordId || null;
        return { ...r, selectedRecordId: selected, ...this.describe(r, selected) };
    }

    // Texto de ayuda y alternativas, segun lo elegido en esa fila.
    describe(row, selectedId) {
        const options = row.options || [];
        const chosen = options.find((o) => o.recordId === selectedId);
        const alternatives = options.filter((o) => o.recordId !== selectedId);
        let note;
        if (selectedId) {
            note = chosen ? `Suggested: ${chosen.reason}` : 'Chosen by you';
        } else if (options.length) {
            note = 'Not sure about these — pick one if it fits';
        } else {
            note = 'No suggestion — search for the record';
        }
        return { chosen: !!selectedId, note, alternatives, hasAlternatives: alternatives.length > 0 };
    }

    update(veleiroId, selectedId) {
        this.rows = this.rows.map((r) =>
            r.veleiroId === veleiroId
                ? { ...r, selectedRecordId: selectedId, ...this.describe(r, selectedId) }
                : r
        );
    }

    handlePick(event) {
        this.update(event.target.dataset.veleiro, event.detail.recordId || null);
    }

    handleUseSuggestion(event) {
        const { veleiro, record } = event.currentTarget.dataset;
        this.update(veleiro, record);
    }

    handlePairChange(event) {
        this.pairValue = event.detail.value;
        this.scan();
    }

    handleToggleFilter(event) {
        this.onlySuggested = event.target.checked;
    }

    handleClear() {
        this.rows = this.rows.map((r) => ({ ...r, selectedRecordId: null, ...this.describe(r, null) }));
    }

    get pairOptions() {
        return ((this.overview && this.overview.pairs) || []).map((p) => ({ label: p.label, value: p.value }));
    }

    get hasPairs() {
        return this.pairOptions.length > 0;
    }

    get objectApiName() {
        return this.overview ? this.overview.sobjectName : null;
    }

    get visibleRows() {
        return this.onlySuggested ? this.rows.filter((r) => (r.options || []).length > 0) : this.rows;
    }

    get hasRows() {
        return this.visibleRows.length > 0;
    }

    get recordColumnLabel() {
        return this.overview && this.overview.sobjectLabel ? this.overview.sobjectLabel : 'Salesforce record';
    }

    get veleiroColumnLabel() {
        return this.overview && this.overview.entity === 'project' ? 'Veleiro project' : 'Veleiro client';
    }

    get selectedCount() {
        return this.rows.filter((r) => r.selectedRecordId).length;
    }

    get linkLabel() {
        return `Link ${this.selectedCount} selected`;
    }

    get linkAndSyncLabel() {
        return `Link and sync ${this.selectedCount}`;
    }

    get nothingToLink() {
        return this.selectedCount === 0;
    }

    get emptyMessage() {
        if (!this.overview) return '';
        if (!this.hasPairs) {
            return 'Nothing is mapped yet. Configure a mapping in the Veleiro Mappings tab first — this screen follows whatever you map there.';
        }
        if (this.overview.truncated) {
            return 'This org has too many records to match here. Link them with Data Loader instead.';
        }
        if (this.overview.veleiroUnlinked === 0) {
            return 'Everything on the Veleiro side is already linked for this pair.';
        }
        return 'Nothing to show for this pair.';
    }

    handleLink() {
        return this.apply(false);
    }

    handleLinkAndSync() {
        return this.apply(true);
    }

    // push=true tambien manda a Veleiro los campos mapeados de cada registro vinculado.
    async apply(push) {
        const pairs = this.rows
            .filter((r) => r.selectedRecordId)
            .map((r) => ({ recordId: r.selectedRecordId, veleiroId: r.veleiroId }));
        if (!pairs.length) return;

        this.loading = true;
        try {
            const [sobjectName, entity] = this.pairValue.split('|');
            const args = { sobjectName, entity, pairsJson: JSON.stringify(pairs) };
            const res = push ? await linkAndSync(args) : await linkAll(args);
            const skipped = res.skipped ? ` ${res.skipped} skipped: already linked.` : '';
            const message = res.syncing
                ? `Their mapped fields are being sent to Veleiro in the background.${skipped}`
                : `Sync them when you want Veleiro to carry the mapped fields too.${skipped}`;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: `${res.linked} record${res.linked === 1 ? '' : 's'} linked to Veleiro`,
                    message,
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
