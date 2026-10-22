/**
 * Las reuniones de Veleiro de un registro, como una línea de tiempo con enlaces al portal.
 *
 * Vive dentro de los paneles de Account y Opportunity, no en una página propia: el objetivo es
 * que quien está mirando la cuenta vea que en Veleiro hay conversación y cruce para allá.
 *
 * Se calla sola cuando no hay nada que mostrar. Si la API key de la org todavía no tiene el
 * scope `meeting` (las keys nacen sin él), lo dice en una línea en vez de parecer rota.
 *
 * La transcripción se pide SOLO al abrir una fila: ese endpoint tiene su propio límite de rate,
 * así que traerlas todas por si acaso sería gastárselo para nada. Lo pedido se recuerda, de modo
 * que abrir y cerrar la misma reunión no vuelve a llamar a Veleiro.
 */
import { LightningElement, api } from 'lwc';
import { T, fmt } from 'c/veleiroI18n';
import getForOpportunity from '@salesforce/apex/VeleiroMeetingService.getForOpportunity';
import getForAccount from '@salesforce/apex/VeleiroMeetingService.getForAccount';
import getTranscript from '@salesforce/apex/VeleiroMeetingService.getTranscript';

const PAGE_SIZE = 5;

export default class VeleiroMeetings extends LightningElement {
    labels = T;
    all = [];
    projects = [];
    scopeMissing = false;

    // Controles de la lista.
    newestFirst = true;
    onlyWithTranscript = false;
    projectFilter = '';
    showAll = false;

    // Acordeón: una transcripción abierta a la vez; en un panel angosto dos ya es ruido.
    openId = null;
    transcript = null;
    transcriptLoading = false;
    _cache = {};

    // 'account' | 'opportunity' — de qué lado se pregunta.
    @api scope = 'account';

    _recordId;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = this._recordId !== value;
        this._recordId = value;
        // Solo recarga si ya estamos montados (navegar de un registro a otro reusa el componente).
        // La PRIMERA carga la hace connectedCallback: las props @api se asignan antes de montar,
        // y un callout disparado ahi se pierde sin dejar rastro.
        if (this._connected && changed) this.load();
    }

    _connected = false;

    connectedCallback() {
        this._connected = true;
        this.load();
    }

    disconnectedCallback() {
        this._connected = false;
    }

    async load() {
        if (!this._recordId) return;
        try {
            const res =
                this.scope === 'opportunity'
                    ? await getForOpportunity({ opportunityId: this._recordId })
                    : await getForAccount({ accountId: this._recordId });
            this.all = res.meetings || [];
            this.projects = res.projects || [];
            this.scopeMissing = res.scopeMissing === true;
        } catch (e) {
            // Sección secundaria: si Veleiro no contesta, el panel sigue siendo útil sin ella.
            this.all = [];
            this.projects = [];
            this.scopeMissing = false;
        }
        this.projectFilter = '';
        this.openId = null;
        this.transcript = null;
        this._cache = {};
    }

    // Recarga desde el padre cuando acaba de sincronizar.
    @api
    refresh() {
        this.load();
    }

    get filtered() {
        let rows = this.projectFilter ? this.all.filter((m) => m.projectId === this.projectFilter) : [...this.all];
        if (this.onlyWithTranscript) rows = rows.filter((m) => m.hasTranscript);
        // El servicio entrega más reciente primero; invertir alcanza para el otro orden.
        return this.newestFirst ? rows : [...rows].reverse();
    }

    get rows() {
        const visible = this.showAll ? this.filtered : this.filtered.slice(0, PAGE_SIZE);
        return visible.map((m) => {
            const isOpen = m.id === this.openId;
            return {
                ...m,
                displayTitle: m.title || this.labels.meetingUntitled,
                isOpen,
                ariaExpanded: isOpen ? 'true' : 'false',
                toggleLabel: isOpen ? this.labels.meetingsHide : this.labels.meetingTranscript,
                dotClass: m.hasTranscript ? 'veleiro-tl-dot veleiro-tl-dot_full' : 'veleiro-tl-dot',
                transcript: isOpen ? this.transcript : null,
                loadingTranscript: isOpen && this.transcriptLoading
            };
        });
    }

    get showSection() {
        return this.all.length > 0 || this.scopeMissing;
    }

    get hasControls() {
        return this.all.length > 1;
    }

    // En la Account se ofrece en cuanto hay un project: aunque hoy sea uno, el usuario ve que
    // la lista se puede acotar, y mañana son tres. En la Opportunity no hay nada que elegir,
    // asi que el servicio no manda projects y el picklist no aparece.
    get hasProjectFilter() {
        return this.projects.length >= 1;
    }

    get projectOptions() {
        return [
            { value: '', label: this.labels.meetingsAllProjects, selected: this.projectFilter === '' },
            ...this.projects.map((p) => ({
                value: p.id,
                label: p.name,
                selected: this.projectFilter === p.id
            }))
        ];
    }

    handleProject(event) {
        this.projectFilter = event.target.value;
        this.showAll = false;
        this.openId = null;
    }

    get orderLabel() {
        return this.newestFirst ? this.labels.meetingsNewestFirst : this.labels.meetingsOldestFirst;
    }

    get orderClass() {
        return 'veleiro-chip';
    }

    get filterClass() {
        return this.onlyWithTranscript ? 'veleiro-chip veleiro-chip_on' : 'veleiro-chip';
    }

    get emptyAfterFilter() {
        return this.all.length > 0 && this.filtered.length === 0;
    }

    get moreLabel() {
        const hidden = this.filtered.length - PAGE_SIZE;
        if (this.showAll) return this.filtered.length > PAGE_SIZE ? this.labels.meetingsShowLess : null;
        return hidden > 0 ? fmt(this.labels.meetingsShowAll, [this.filtered.length]) : null;
    }

    handleOrder() {
        this.newestFirst = !this.newestFirst;
    }

    handleFilter() {
        this.onlyWithTranscript = !this.onlyWithTranscript;
    }

    handleMore() {
        this.showAll = !this.showAll;
    }

    async handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (this.openId === id) {
            this.openId = null;
            this.transcript = null;
            return;
        }
        this.openId = id;
        if (this._cache[id]) {
            this.transcript = this._cache[id];
            return;
        }
        this.transcriptLoading = true;
        this.transcript = null;
        try {
            const raw = await getTranscript({ meetingId: id });
            const t = { ...raw };
            t.hasText = !!(t.text && t.text.trim());
            // Dos personas pueden llamarse igual: la key del for:each lleva el índice.
            t.participants = (raw.participants || []).map((p, i) => ({ ...p, key: `${id}-${i}` }));
            t.hasParticipants = t.participants.length > 0;
            this._cache[id] = t;
            // Si el usuario cerró o cambió de fila mientras llegaba, no la pisamos.
            if (this.openId === id) this.transcript = t;
        } catch (e) {
            if (this.openId === id) this.transcript = { hasText: false, reachable: false };
        } finally {
            this.transcriptLoading = false;
        }
    }
}
