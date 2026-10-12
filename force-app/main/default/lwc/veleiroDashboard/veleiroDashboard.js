import { LightningElement } from 'lwc';
import { MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getOverview from '@salesforce/apex/VeleiroDashboardController.getOverview';

// Cuantos clients se ven antes de pedir "ver todos". Un partner con 80 clients no deberia
// tener que hacer scroll por toda la pagina para llegar a lo que sigue.
const FIRST_PAGE = 8;
const MAX_PROJECTS_SHOWN = 5;

export default class VeleiroDashboard extends LightningElement {
    mascotUrl = VELEIRO_MASCOT;
    overview;
    loading = true;
    error;

    search = '';
    sortBy = 'projects';
    showAll = false;
    _all = [];
    _expanded = new Set();

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            const ov = await getOverview();
            this.overview = ov;
            this._all = ov.clients || [];
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : 'Could not load Veleiro data';
        } finally {
            this.loading = false;
        }
    }

    // Filtra, ordena y recorta en el cliente: getOverview ya trajo todo, no hay otro callout.
    get clients() {
        const term = this.search.trim().toLowerCase();
        let rows = term ? this._all.filter((c) => (c.name || '').toLowerCase().includes(term)) : [...this._all];
        rows.sort(this.comparator());
        if (!this.showAll) rows = rows.slice(0, FIRST_PAGE);
        return rows.map((c) => this.decorate(c));
    }

    comparator() {
        if (this.sortBy === 'name') {
            return (a, b) => (a.name || '').localeCompare(b.name || '');
        }
        if (this.sortBy === 'progress') {
            return (a, b) => a.avgProgress - b.avgProgress;      // lo más atrasado primero
        }
        return (a, b) => b.projectCount - a.projectCount || (a.name || '').localeCompare(b.name || '');
    }

    decorate(c) {
        const open = this._expanded.has(c.id);
        const projects = c.projects || [];
        return {
            ...c,
            open,
            projects: projects.slice(0, MAX_PROJECTS_SHOWN).map((p) => ({
                ...p,
                progressLabel: `${p.progress}%`,
                barVariant: p.progress >= 100 ? 'base-autocomplete' : 'base',
                barClass: p.progress >= 100 ? 'veleiro-bar veleiro-bar-done' : 'veleiro-bar'
            })),
            hiddenProjects: Math.max(projects.length - MAX_PROJECTS_SHOWN, 0),
            hasHiddenProjects: projects.length > MAX_PROJECTS_SHOWN,
            countLabel: projects.length === 1 ? '1 project' : `${projects.length} projects`,
            iconName: open ? 'utility:chevrondown' : 'utility:chevronright',
            bodyClass: open ? 'veleiro-projects' : 'veleiro-projects veleiro-collapsed',
            cardClass: open ? 'veleiro-client veleiro-client-open' : 'veleiro-client',
            trackClass: c.avgProgress >= 100 ? 'veleiro-mini veleiro-mini-done' : 'veleiro-mini'
        };
    }

    // El ancho de cada barra compacta se asigna aqui para no meter estilos en el template.
    renderedCallback() {
        this.template.querySelectorAll('.veleiro-mini-fill').forEach((el) => {
            el.style.width = `${Math.min(Number(el.dataset.pct) || 0, 100)}%`;
        });
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (this._expanded.has(id)) {
            this._expanded.delete(id);
        } else {
            this._expanded.add(id);
        }
        this._all = [...this._all];     // fuerza el recalculo del getter
    }

    handleSearch(event) {
        this.search = event.target.value || '';
        this.showAll = this.search.trim().length > 0 ? true : this.showAll;
    }

    handleSort(event) {
        this.sortBy = event.detail.value;
    }

    handleShowAll() {
        this.showAll = !this.showAll;
    }

    handleRefresh() {
        this.load();
    }

    get sortOptions() {
        return [
            { label: 'Most projects', value: 'projects' },
            { label: 'Name (A–Z)', value: 'name' },
            { label: 'Least progress', value: 'progress' }
        ];
    }

    get matchCount() {
        const term = this.search.trim().toLowerCase();
        return term ? this._all.filter((c) => (c.name || '').toLowerCase().includes(term)).length : this._all.length;
    }

    get countLabel() {
        const n = this.matchCount;
        const noun = n === 1 ? 'client' : 'clients';
        return this.search.trim() ? `${n} ${noun} found` : `${n} ${noun}`;
    }

    get hasMore() {
        return !this.showAll && this.matchCount > FIRST_PAGE;
    }

    get showAllLabel() {
        return this.showAll ? 'Show fewer' : `Show all ${this.matchCount}`;
    }

    get canCollapse() {
        return this.showAll && this.matchCount > FIRST_PAGE;
    }

    // Con la lista completa abierta, el scroll vive en la lista y no en la página entera.
    get listClass() {
        return this.showAll && this.matchCount > FIRST_PAGE ? 'veleiro-list veleiro-list-scroll' : 'veleiro-list';
    }

    get hasClients() {
        return !this.loading && this._all.length > 0;
    }

    get noMatches() {
        return this.hasClients && this.matchCount === 0;
    }

    get isEmpty() {
        return !this.loading && !this.error && this._all.length === 0;
    }
}
