/**
 * El pulso de la entrega, arriba del panel: tiempo invertido, trabajo abierto y trabajo trabado.
 *
 * Es la parte que un vendedor no puede ver en su CRM. El tiempo viene de las horas que el equipo
 * registró en Veleiro, así que el número es el argumento de la renovación, y el detalle de dónde
 * se fue ese tiempo solo existe allá.
 *
 * Se calla sola si no hay nada que contar: un panel con tres ceros no informa, estorba.
 */
import { LightningElement, api } from 'lwc';
import { T, fmt } from 'c/veleiroI18n';
import getForOpportunity from '@salesforce/apex/VeleiroPulseService.getForOpportunity';
import getForAccount from '@salesforce/apex/VeleiroPulseService.getForAccount';

export default class VeleiroPulse extends LightningElement {
    labels = T;
    pulse;

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
            this.pulse =
                this.scope === 'opportunity'
                    ? await getForOpportunity({ opportunityId: this._recordId })
                    : await getForAccount({ accountId: this._recordId });
        } catch (e) {
            this.pulse = undefined;
        }
    }

    @api
    refresh() {
        this.load();
    }

    get showSection() {
        return !!this.pulse && (this.pulse.hasData || this.pulse.scopeMissing);
    }

    get scopeMissing() {
        return !!this.pulse && this.pulse.scopeMissing;
    }

    get tiles() {
        if (!this.pulse || !this.pulse.hasData) return [];
        const out = [
            { key: 'time', label: this.labels.pulseTime, value: this.timeLabel, cls: 'veleiro-tile' },
            {
                key: 'open',
                label: this.labels.pulseOpen,
                value: String(this.pulse.openTasks || 0),
                cls: 'veleiro-tile'
            }
        ];
        // El trabajo trabado solo aparece cuando lo hay: si no, es un cero que no dice nada.
        if (this.pulse.blockedTasks > 0) {
            out.push({
                key: 'blocked',
                label: this.labels.pulseBlocked,
                value: String(this.pulse.blockedTasks),
                cls: 'veleiro-tile veleiro-tile_warn'
            });
        }
        return out;
    }

    // Menos de una hora se dice en minutos: "0,3 h" no lo entiende nadie.
    get timeLabel() {
        const minutes = (this.pulse && this.pulse.loggedMinutes) || 0;
        if (minutes < 60) return fmt(this.labels.pulseMinutes, [minutes]);
        const hours = minutes / 60;
        const shown = hours < 10 ? Math.round(hours * 10) / 10 : Math.round(hours);
        return fmt(this.labels.pulseHours, [shown]);
    }

    get partialLabel() {
        return this.pulse && this.pulse.partial
            ? fmt(this.labels.pulsePartial, [(this.pulse.projects || []).length])
            : null;
    }
}
