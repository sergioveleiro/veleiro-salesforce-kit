/**
 * Aviso de setup en el Home: solo existe mientras el onboarding esta incompleto.
 * Pide el estado SIN verificar la conexion para no gastar un callout al abrir el Home.
 */
import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getState from '@salesforce/apex/VeleiroOnboardingController.getState';

export default class VeleiroSetupBanner extends NavigationMixin(LightningElement) {
    mascotUrl = VELEIRO_MASCOT;
    state;
    ready = false;

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        const fill = this.template.querySelector('.vsb-fill');
        if (fill) fill.style.width = this.percent + '%';
    }

    async load() {
        try {
            this.state = await getState({ verifyConnection: false });
        } catch (e) {
            this.state = undefined;   // el aviso nunca estorba: si falla, no se dibuja
        } finally {
            this.ready = true;
        }
    }

    handleOpen() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: this.state.setupTab }
        });
    }

    get show() {
        return this.ready && this.state && !this.state.complete;
    }

    get percent() {
        if (!this.state || !this.state.total) return 0;
        return Math.round((this.state.done / this.state.total) * 100);
    }

    get headline() {
        if (!this.state) return '';
        return this.state.done === 0
            ? 'Veleiro todavía no está conectado'
            : `Te faltan ${this.state.total - this.state.done} de ${this.state.total} pasos del setup`;
    }

    get nextStep() {
        if (!this.state) return '';
        const pending = (this.state.steps || []).find((s) => s.state === 'todo' || s.state === 'unknown');
        return pending ? `Sigue: ${pending.title}` : '';
    }
}
