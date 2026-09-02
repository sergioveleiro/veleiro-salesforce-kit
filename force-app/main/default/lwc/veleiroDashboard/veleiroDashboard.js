import { LightningElement } from 'lwc';
import VELEIRO_LOGO from '@salesforce/resourceUrl/VeleiroLogo';
import VELEIRO_MASCOT from '@salesforce/resourceUrl/VeleiroMascot';
import getOverview from '@salesforce/apex/VeleiroDashboardController.getOverview';

export default class VeleiroDashboard extends LightningElement {
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;
    overview;
    clients = [];
    loading = true;
    error;
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
            this.decorate(ov.clients || []);
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : 'Could not load Veleiro data';
        } finally {
            this.loading = false;
        }
    }

    decorate(rawClients) {
        this.clients = rawClients.map((c) => {
            const open = this._expanded.has(c.id);
            return {
                ...c,
                open,
                projects: (c.projects || []).map((p) => ({
                    ...p,
                    progressLabel: `${p.progress}%`,
                    barVariant: p.progress >= 100 ? 'base-autocomplete' : 'base',
                    barClass: p.progress >= 100 ? 'veleiro-bar veleiro-bar-done' : 'veleiro-bar'
                })),
                iconName: open ? 'utility:chevrondown' : 'utility:chevronright',
                bodyClass: open ? 'veleiro-projects' : 'veleiro-projects veleiro-collapsed',
                cardClass: open ? 'veleiro-client veleiro-client-open' : 'veleiro-client'
            };
        });
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (this._expanded.has(id)) {
            this._expanded.delete(id);
        } else {
            this._expanded.add(id);
        }
        this.decorate(this.overview.clients || []);
    }

    handleRefresh() {
        this.load();
    }

    get hasClients() {
        return !this.loading && this.clients && this.clients.length > 0;
    }

    get isEmpty() {
        return !this.loading && !this.error && (!this.clients || this.clients.length === 0);
    }
}
