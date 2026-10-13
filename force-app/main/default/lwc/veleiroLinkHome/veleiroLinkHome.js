import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO, MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getSuggestions from '@salesforce/apex/VeleiroLinkController.getSuggestions';
import linkAll from '@salesforce/apex/VeleiroLinkController.linkAll';
import linkAndSync from '@salesforce/apex/VeleiroLinkController.linkAndSync';
import searchRecords from '@salesforce/apex/VeleiroLinkController.searchRecords';
import sendToVeleiro from '@salesforce/apex/VeleiroLinkController.sendToVeleiro';
import getSendProgress from '@salesforce/apex/VeleiroLinkController.getSendProgress';

const POLL_MS = 2500;
const SEARCH_DEBOUNCE_MS = 300;

export default class VeleiroLinkHome extends NavigationMixin(LightningElement) {
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;

    loading = false;
    scanned = false;
    overview;
    pairValue;                 // objeto|entidad, de lo configurado en Veleiro Mappings
    mode;                      // 'send' | 'match' — se elige solo según dónde hay trabajo

    // --- modo Enviar a Veleiro ---
    selected = new Set();      // ids elegidos, sobrevive al buscador
    useMatch = new Set();      // ids que se vincularán al parecido en vez de crear uno nuevo
    sentIds = new Set();       // ya confirmados por el avance
    sendTerm = '';
    searchHits;                // resultados del buscador (null = mostrando la lista base)
    sending = false;
    progress;
    _watching = [];
    _pollId;
    _searchId;

    // --- modo Emparejar ---
    rows = [];
    onlySuggested = false;

    connectedCallback() {
        this.scan();
    }

    disconnectedCallback() {
        this.stopPolling();
        clearTimeout(this._searchId);
    }

    renderedCallback() {
        const fill = this.template.querySelector('.vl-fill');
        if (fill) fill.style.width = `${this.progressPercent}%`;
    }

    async scan() {
        this.loading = true;
        try {
            const [sobjectName, entity] = (this.pairValue || '|').split('|');
            const data = await getSuggestions({ sobjectName, entity });
            this.overview = data;
            this.pairValue = data.sobjectName ? `${data.sobjectName}|${data.entity}` : undefined;
            this.rows = (data.rows || []).map((r) => this.toRow(r));
            this.selected = new Set();
            this.useMatch = new Set();
            this.sentIds = new Set();
            this.searchHits = undefined;
            this.sendTerm = '';
            // Arranca donde está el trabajo: Veleiro vacío -> hay que enviar, no emparejar.
            if (!this.mode) this.mode = (data.veleiroUnlinked || 0) > 0 ? 'match' : 'send';
            this.scanned = true;
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    // ================= modo Enviar a Veleiro =================

    get candidates() {
        const base = this.searching ? this.searchHits || [] : (this.overview && this.overview.candidates) || [];
        return base.map((c) => {
            const picked = this.selected.has(c.recordId);
            const linking = this.useMatch.has(c.recordId);
            const sent = this.sentIds.has(c.recordId);
            return {
                ...c,
                selected: picked,
                sent,
                hasMatch: !!c.matchVeleiroId && !sent,
                linking,
                rowClass: `vl-row${picked ? ' vl-row-picked' : ''}${sent ? ' vl-row-sent' : ''}`,
                matchLine: linking
                    ? `Se vinculará a “${c.matchName}” en vez de crear uno nuevo`
                    : `Puede que ya exista en Veleiro: “${c.matchName}” — ${c.matchReason}`,
                matchBtnLabel: linking ? 'No, crear uno nuevo' : 'Vincular con ese',
                matchClass: linking ? 'vl-dup vl-dup-on' : 'vl-dup'
            };
        });
    }

    get searching() {
        return this.sendTerm.trim().length >= 2;
    }

    handleSendSearch(event) {
        this.sendTerm = event.target.value || '';
        clearTimeout(this._searchId);
        if (!this.searching) {
            this.searchHits = undefined;
            return;
        }
        const term = this.sendTerm;
        // El buscador va al servidor: la lista base son los primeros 200, y una org puede
        // tener miles de registros sin vincular.
        this._searchId = setTimeout(async () => {
            try {
                const [sobjectName, entity] = this.pairValue.split('|');
                const hits = await searchRecords({ sobjectName, entity, term });
                this.searchHits = hits.map((h) => ({
                    recordId: h.recordId,
                    name: h.name,
                    website: h.website
                }));
            } catch (e) {
                this.toastError(e);
            }
        }, SEARCH_DEBOUNCE_MS);
    }

    handlePick(event) {
        const id = event.target.dataset.id;
        const next = new Set(this.selected);
        if (event.target.checked) {
            if (next.size >= this.maxPerBatch) {
                event.target.checked = false;
                this.toast(
                    'Tope por tanda',
                    `Puedes enviar ${this.maxPerBatch} a la vez. Manda esta tanda y sigue con la siguiente.`,
                    'warning'
                );
                return;
            }
            next.add(id);
        } else {
            next.delete(id);
        }
        this.selected = next;
    }

    handleSelectAll() {
        const ids = this.candidates.filter((c) => !c.sent).map((c) => c.recordId);
        this.selected = this.allVisibleSelected ? new Set() : new Set(ids.slice(0, this.maxPerBatch));
    }

    handleUseMatch(event) {
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.useMatch);
        if (next.has(id)) {
            next.delete(id);
        } else {
            next.add(id);
            this.selected = new Set([...this.selected, id]);   // elegirlo implica mandarlo
        }
        this.useMatch = next;
    }

    async handleSend() {
        const all = [...(this.overview.candidates || []), ...(this.searchHits || [])];
        const byId = new Map(all.map((c) => [c.recordId, c]));
        const rows = [...this.selected].map((id) => ({
            recordId: id,
            veleiroId: this.useMatch.has(id) && byId.get(id) ? byId.get(id).matchVeleiroId : null
        }));
        if (!rows.length) return;

        this.loading = true;
        try {
            const [sobjectName, entity] = this.pairValue.split('|');
            const res = await sendToVeleiro({ sobjectName, entity, rowsJson: JSON.stringify(rows) });
            this._watching = rows.map((r) => r.recordId);
            this.progress = { total: res.queued, sent: 0, running: true };
            this.sending = res.queued > 0;
            if (res.skipped) {
                this.toast('Algunos ya estaban', `${res.skipped} ya tenían vínculo y no se mandaron.`, 'info');
            }
            if (this.sending) this.startPolling();
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    startPolling() {
        this.stopPolling();
        this._pollId = setInterval(() => this.poll(), POLL_MS);
        this.poll();
    }

    stopPolling() {
        if (this._pollId) clearInterval(this._pollId);
        this._pollId = undefined;
    }

    async poll() {
        try {
            const [sobjectName, entity] = this.pairValue.split('|');
            const p = await getSendProgress({
                sobjectName,
                entity,
                recordIdsJson: JSON.stringify(this._watching)
            });
            this.sentIds = new Set(p.doneIds || []);
            this.progress = { total: p.total, sent: p.sent, running: p.running, lastError: p.lastError };
            if (!p.running) this.finishSending(p);
        } catch (e) {
            this.stopPolling();
            this.sending = false;
            this.toastError(e);
        }
    }

    finishSending(p) {
        this.stopPolling();
        this.sending = false;
        const failed = p.total - p.sent;
        if (failed > 0) {
            this.toast(
                `${p.sent} de ${p.total} llegaron a Veleiro`,
                `${failed} no pudieron: ${p.lastError || 'revisa el último error en Veleiro Mappings'}`,
                'warning'
            );
        } else {
            this.toast(
                `${p.sent} ${p.sent === 1 ? 'registro' : 'registros'} en Veleiro`,
                'Ya quedaron creados y vinculados.',
                'success'
            );
        }
        this.scan();
    }

    get maxPerBatch() {
        return (this.overview && this.overview.maxPerBatch) || 200;
    }

    get selectedCount() {
        return this.selected.size;
    }

    get nothingSelected() {
        return this.selected.size === 0 || this.sending;
    }

    get sendLabel() {
        const n = this.selected.size;
        if (!n) return 'Enviar a Veleiro';
        return `Enviar ${n} a Veleiro`;
    }

    get allVisibleSelected() {
        const ids = this.candidates.filter((c) => !c.sent).map((c) => c.recordId);
        return ids.length > 0 && ids.every((id) => this.selected.has(id));
    }

    get selectAllLabel() {
        if (this.allVisibleSelected) return 'Quitar la selección';
        const n = Math.min(this.candidates.filter((c) => !c.sent).length, this.maxPerBatch);
        return `Seleccionar ${n}`;
    }

    get selectionLabel() {
        const total = (this.overview && this.overview.recordsUnlinked) || 0;
        const shown = this.candidates.length;
        const base = this.searching
            ? `${shown} ${shown === 1 ? 'resultado' : 'resultados'}`
            : `${shown} de ${total} sin enviar`;
        return this.selected.size ? `${base} · ${this.selected.size} elegidos` : base;
    }

    get moreThanShown() {
        return !this.searching && ((this.overview && this.overview.recordsUnlinked) || 0) > this.candidates.length;
    }

    get progressLabel() {
        if (!this.progress) return '';
        return `Enviando a Veleiro… ${this.progress.sent} de ${this.progress.total}`;
    }

    get progressPercent() {
        if (!this.progress || !this.progress.total) return 0;
        return Math.round((this.progress.sent / this.progress.total) * 100);
    }

    get hasCandidates() {
        return this.candidates.length > 0;
    }

    get sendEmptyMessage() {
        if (this.searching) return `Ningún ${this.recordColumnLabel} sin vincular coincide con “${this.sendTerm}”.`;
        if (this.overview && this.overview.truncated) {
            return 'Esta org tiene demasiados registros para listarlos aquí. Usa el buscador para mandarlos por tandas.';
        }
        return `Todos tus registros de ${this.recordColumnLabel} ya están en Veleiro. No queda nada por enviar.`;
    }

    // ================= modos =================

    handleMode(event) {
        this.mode = event.currentTarget.dataset.mode;
    }

    get isSend() {
        return this.mode === 'send';
    }

    get isMatch() {
        return this.mode === 'match';
    }

    get sendModeClass() {
        return this.isSend ? 'vl-mode vl-mode-on' : 'vl-mode';
    }

    get matchModeClass() {
        return this.isMatch ? 'vl-mode vl-mode-on' : 'vl-mode';
    }

    get sendModeSub() {
        const n = (this.overview && this.overview.recordsUnlinked) || 0;
        if (!n) return 'Nada pendiente';
        return `${n} ${this.recordColumnLabel} sin enviar`;
    }

    get matchModeSub() {
        const n = (this.overview && this.overview.veleiroUnlinked) || 0;
        if (!n) return 'Nada por emparejar';
        return `${n} en Veleiro por vincular`;
    }

    get subtitle() {
        return this.isSend
            ? 'Elige los registros de Salesforce que quieres crear en Veleiro. Si alguno ya existe allá, te lo advertimos antes de duplicarlo.'
            : 'Para lo que ya existía en los dos lados. Cada registro de Veleiro muestra el de Salesforce que creemos que es — confírmalo o busca otro.';
    }

    // ================= modo Emparejar (igual que antes) =================

    toRow(r) {
        const selected = r.suggestedRecordId || null;
        return { ...r, selectedRecordId: selected, term: '', results: [], ...this.describe(r, selected) };
    }

    describe(row, selectedId) {
        const options = [...(row.options || []), ...(row.results || [])];
        const chosen = options.find((o) => o.recordId === selectedId);
        const alternatives = options.filter((o) => o.recordId !== selectedId);
        let note;
        if (selectedId) {
            note = chosen ? `${chosen.name} — ${chosen.reason}` : 'Registro elegido';
        } else if (options.length) {
            note = 'No estamos seguros — elige uno si encaja';
        } else {
            note = 'Sin sugerencia — escribe un nombre para buscar';
        }
        return {
            chosen: !!selectedId,
            chosenName: chosen ? chosen.name : null,
            note,
            alternatives,
            hasAlternatives: alternatives.length > 0
        };
    }

    update(veleiroId, selectedId, extra) {
        this.rows = this.rows.map((r) => {
            if (r.veleiroId !== veleiroId) return r;
            const merged = { ...r, ...(extra || {}) };
            return { ...merged, selectedRecordId: selectedId, ...this.describe(merged, selectedId) };
        });
    }

    async handleSearch(event) {
        const veleiroId = event.target.dataset.veleiro;
        const term = event.target.value;
        if (!term || term.length < 2) {
            this.update(veleiroId, this.selectedOf(veleiroId), { term, results: [] });
            return;
        }
        try {
            const [sobjectName, entity] = this.pairValue.split('|');
            const results = await searchRecords({ sobjectName, entity, term });
            this.update(veleiroId, this.selectedOf(veleiroId), { term, results });
        } catch (e) {
            this.toastError(e);
        }
    }

    selectedOf(veleiroId) {
        const row = this.rows.find((r) => r.veleiroId === veleiroId);
        return row ? row.selectedRecordId : null;
    }

    handleUnpick(event) {
        this.update(event.currentTarget.dataset.veleiro, null);
    }

    handleUseSuggestion(event) {
        const { veleiro, record } = event.currentTarget.dataset;
        this.update(veleiro, record);
    }

    handlePairChange(event) {
        this.pairValue = event.detail.value;
        this.mode = undefined;   // el par nuevo decide de nuevo dónde está el trabajo
        this.scan();
    }

    handleToggleFilter(event) {
        this.onlySuggested = event.target.checked;
    }

    handleClear() {
        this.rows = this.rows.map((r) => ({ ...r, selectedRecordId: null, ...this.describe(r, null) }));
    }

    handleLink() {
        return this.apply(false);
    }

    handleLinkAndSync() {
        return this.apply(true);
    }

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
            const skipped = res.skipped ? ` ${res.skipped} se saltaron: ya estaban vinculados.` : '';
            const message = res.syncing
                ? `Sus campos mapeados se están enviando a Veleiro en segundo plano.${skipped}`
                : `Sincronízalos cuando quieras que Veleiro cargue también los campos mapeados.${skipped}`;
            this.toast(
                `${res.linked} ${res.linked === 1 ? 'registro' : 'registros'} vinculados`,
                message,
                res.linked ? 'success' : 'warning'
            );
            await this.scan();
        } catch (e) {
            this.toastError(e);
        } finally {
            this.loading = false;
        }
    }

    // ================= comunes =================

    get pairOptions() {
        return ((this.overview && this.overview.pairs) || []).map((p) => ({ label: p.label, value: p.value }));
    }

    get hasPairs() {
        return this.pairOptions.length > 0;
    }

    get noMappings() {
        return this.scanned && !this.loading && !this.hasPairs && !this.notConnected;
    }

    get notConnected() {
        return !!(this.overview && this.overview.connectionError);
    }

    get connectionError() {
        return this.overview ? this.overview.connectionError : '';
    }

    get ready() {
        return this.scanned && this.hasPairs && !this.notConnected;
    }

    get pushDisabled() {
        return !!this.overview && this.overview.pushEnabled === false;
    }

    get visibleRows() {
        return this.onlySuggested ? this.rows.filter((r) => (r.options || []).length > 0) : this.rows;
    }

    get hasRows() {
        return this.visibleRows.length > 0;
    }

    get recordColumnLabel() {
        return this.overview && this.overview.sobjectLabel ? this.overview.sobjectLabel : 'registro';
    }

    get veleiroColumnLabel() {
        return this.overview && this.overview.entity === 'project' ? 'Veleiro project' : 'Veleiro client';
    }

    get matchSelectedCount() {
        return this.rows.filter((r) => r.selectedRecordId).length;
    }

    get linkLabel() {
        return `Solo vincular ${this.matchSelectedCount}`;
    }

    get linkAndSyncLabel() {
        return `Vincular y sincronizar ${this.matchSelectedCount}`;
    }

    get nothingToLink() {
        return this.matchSelectedCount === 0;
    }

    get matchEmptyMessage() {
        if (!this.overview) return '';
        if (this.overview.truncated) {
            return 'Esta org tiene demasiados registros para emparejarlos aquí. Hazlo con Data Loader.';
        }
        if (this.overview.veleiroUnlinked === 0) {
            return 'Todo lo que hay en Veleiro ya está vinculado para este par. Si lo que quieres es llevar registros de Salesforce a Veleiro, usa “Enviar a Veleiro”.';
        }
        return 'Nada que mostrar para este par.';
    }

    handleOpenMappings() {
        this.openTab(this.mappingsTab);
    }

    handleOpenSetup() {
        this.openTab((this.overview && this.overview.setupTab) || 'Veleiro_Setup');
    }

    openTab(apiName) {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName } });
    }

    // Apex resuelve el nombre: la pestaña lleva prefijo dentro del paquete administrado.
    get mappingsTab() {
        return (this.overview && this.overview.mappingsTab) || 'Veleiro_Mappings';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    toastError(e) {
        const msg = e && e.body && e.body.message ? e.body.message : 'No pudimos hablar con Veleiro';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error de Veleiro', message: msg, variant: 'error' }));
    }
}
