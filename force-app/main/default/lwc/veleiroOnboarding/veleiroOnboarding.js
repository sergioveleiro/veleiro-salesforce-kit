import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LOGO as VELEIRO_LOGO, MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import { T, fmt } from 'c/veleiroI18n';
import getState from '@salesforce/apex/VeleiroOnboardingController.getState';
import skipStep from '@salesforce/apex/VeleiroOnboardingController.skipStep';
import saveToken from '@salesforce/apex/VeleiroMappingController.saveToken';
import saveEnvironment from '@salesforce/apex/VeleiroMappingController.saveEnvironment';
import getSyncConfig from '@salesforce/apex/VeleiroMappingController.getSyncConfig';
import saveSyncConfig from '@salesforce/apex/VeleiroMappingController.saveSyncConfig';

// Paginas de Setup a las que mandamos al usuario cuando el paso no vive en nuestra app.
const SETUP_PAGES = {
    flows: '/lightning/setup/Flows/home',
    team: '/lightning/setup/PermSets/home'
};

export default class VeleiroOnboarding extends NavigationMixin(LightningElement) {
    labels = T;
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;

    state;
    steps = [];
    loading = true;
    error;
    saving = false;
    showStepsAnyway = false;      // en modo "completo", para volver a ver la lista

    // inline del paso 1
    tokenInput = '';
    environment = 'Production';
    // inline del paso 2
    direction = 'bidirectional';
    syncTrigger = 'manual';
    _config = {};

    _openKey;                     // paso abierto a mano (null = el primero pendiente)

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        // El ancho de la barra se pone aqui y no en el template: nada de estilos dinamicos.
        const fill = this.template.querySelector('.vo-track-fill');
        if (fill) fill.style.width = this.percent + '%';
    }

    async load(verify = true) {
        this.loading = true;
        this.error = undefined;
        try {
            const [state, config] = await Promise.all([getState({ verifyConnection: verify }), getSyncConfig()]);
            this.state = state;
            this._config = config || {};
            this.direction = this._config.direction || 'bidirectional';
            this.syncTrigger = this._config.trigger || 'manual';
            this.environment = (state.environment || '').includes('beta') ? 'Beta' : 'Production';
            this.decorate();
        } catch (e) {
            this.error = this.messageOf(e, T.setupReadError);
        } finally {
            this.loading = false;
        }
    }

    decorate() {
        const steps = this.state.steps || [];
        // El paso activo es el primero que falta, salvo que el usuario abra otro a proposito.
        const pending = steps.find((s) => s.state === 'todo' || s.state === 'unknown');
        const openKey = this._openKey || (pending ? pending.key : null);

        this.steps = steps.map((s, i) => {
            const done = s.state === 'done';
            const skipped = s.state === 'skipped';
            const open = s.key === openKey;
            return {
                ...s,
                number: i + 1,
                isDone: done,
                isToken: s.inline === 'token',
                isConfig: s.inline === 'config',
                canSkip: s.optional && !done,
                skipLabel: skipped ? T.unskipStep : T.skipStep,
                skipNext: !skipped,
                pillLabel: this.pillLabel(s.state),
                pillClass: `vo-pill vo-pill-${s.state}`,
                badgeClass: done ? 'vo-badge vo-badge-done'
                    : skipped ? 'vo-badge vo-badge-skipped'
                    : open ? 'vo-badge vo-badge-active' : 'vo-badge',
                cardClass: `vo-step${done ? ' vo-step-done' : ''}${open ? ' vo-step-open' : ''}`,
                bodyClass: open ? 'vo-step-body' : 'vo-step-body vo-hidden',
                chevron: open ? 'utility:chevronup' : 'utility:chevrondown',
                actionVariant: done ? 'neutral' : 'brand'
            };
        });
    }

    pillLabel(state) {
        if (state === 'done') return T.pillDone;
        if (state === 'skipped') return T.pillSkipped;
        if (state === 'unknown') return T.pillUnknown;
        return T.pillTodo;
    }

    // ---- interaccion ----

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        this._openKey = this._openKey === key ? 'none' : key;
        this.decorate();
    }

    handleAction(event) {
        const key = event.currentTarget.dataset.key;
        const step = (this.state.steps || []).find((s) => s.key === key);
        if (!step) return;
        if (step.actionTab) {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: step.actionTab }
            });
        } else if (step.actionObject) {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: step.actionObject, actionName: 'list' },
                state: { filterName: 'Recent' }
            });
        } else if (SETUP_PAGES[key]) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: { url: SETUP_PAGES[key] }
            });
        }
    }

    async handleSkip(event) {
        const key = event.currentTarget.dataset.key;
        const step = this.steps.find((s) => s.key === key);
        try {
            await skipStep({ key, skip: step ? step.skipNext : true });
            this._openKey = undefined;
            await this.load(false);
        } catch (e) {
            this.toast(T.couldNotSave, this.messageOf(e, T.tryAgain), 'error');
        }
    }

    handleTokenChange(event) { this.tokenInput = event.detail.value; }
    handleEnvChange(event) { this.environment = event.detail.value; }
    handleDirectionChange(event) { this.direction = event.detail.value; }
    handleTriggerChange(event) { this.syncTrigger = event.detail.value; }

    async handleSaveToken() {
        if (!this.tokenInput) {
            this.toast(T.tokenMissing, T.tokenMissingMsg, 'warning');
            return;
        }
        this.saving = true;
        try {
            await saveEnvironment({ environment: this.environment });
            await saveToken({ token: this.tokenInput });
            this.tokenInput = '';
            await this.load(true);                     // verifica de verdad contra la API
            const conn = (this.state.steps || []).find((s) => s.key === 'connection');
            if (conn && conn.state === 'done') {
                this.toast(T.connected, T.connectedMsg, 'success');
            } else {
                this.toast(T.tokenNoConnection, conn ? conn.evidence : '', 'warning');
            }
        } catch (e) {
            this.toast(T.couldNotSaveToken, this.messageOf(e, ''), 'error');
        } finally {
            this.saving = false;
        }
    }

    async handleSaveConfig() {
        this.saving = true;
        try {
            await saveSyncConfig({
                direction: this.direction,
                winner: this._config.winner || 'salesforce',
                frequency: this._config.frequency || 'off',
                triggerMode: this.syncTrigger,
                autoAccount: this._config.autoAccount !== 'false',
                autoOpportunity: this._config.autoOpportunity !== 'false',
                pullWritesName: this._config.pullWritesName === 'true',
                opportunityMode: this._config.opportunityMode || 'create'
            });
            this._openKey = undefined;
            await this.load(false);
            this.toast(T.configSaved, T.configSavedMsg, 'success');
        } catch (e) {
            this.toast(T.couldNotSave, this.messageOf(e, ''), 'error');
        } finally {
            this.saving = false;
        }
    }

    handleRecheck() {
        this._openKey = undefined;
        this.load(true);
    }

    handleShowSteps() { this.showStepsAnyway = !this.showStepsAnyway; }

    // ---- getters de presentacion ----

    get percent() {
        if (!this.state || !this.state.total) return 0;
        return Math.round((this.state.done / this.state.total) * 100);
    }

    get progressLabel() {
        if (!this.state) return '';
        return fmt(T.stepsOf, [this.state.done, this.state.total]);
    }

    get complete() { return !!(this.state && this.state.complete); }
    get showHealth() { return this.complete && !this.loading; }
    get showSteps() { return !this.loading && !this.error && (!this.complete || this.showStepsAnyway); }
    get stepsToggleLabel() { return this.showStepsAnyway ? T.hideSteps : T.showSteps; }

    get heroTitle() { return this.complete ? T.setupTitleDone : T.setupTitle; }

    get heroSub() { return this.complete ? T.setupSubDone : T.setupSub; }

    get vellyLine() {
        if (!this.state) return T.vellyStart;
        const left = this.state.total - this.state.done;
        if (left === 0) return T.vellyDone;
        if (left === 1) return T.vellyAlmost;
        return this.state.done === 0 ? T.vellyStart : T.vellyGoing;
    }

    get connectionClass() {
        return this.state && this.state.connected ? 'vo-dot vo-dot-ok' : 'vo-dot vo-dot-bad';
    }

    get environmentLabel() {
        if (!this.state || !this.state.environment) return '';
        return this.state.environment.includes('beta') ? T.beta : T.production;
    }

    get hasLastError() { return !!(this.state && this.state.lastError); }

    get lastErrorLine() {
        if (!this.hasLastError) return '';
        return this.state.lastErrorAt ? `${this.state.lastError} (${this.state.lastErrorAt})` : this.state.lastError;
    }

    get environmentOptions() {
        return [
            { label: T.envProduction, value: 'Production' },
            { label: T.envBeta, value: 'Beta' }
        ];
    }

    get directionOptions() {
        return [
            { label: T.dirBoth, value: 'bidirectional' },
            { label: T.dirSfToVeleiro, value: 'sf_to_veleiro' },
            { label: T.dirVeleiroToSf, value: 'veleiro_to_sf' }
        ];
    }

    get triggerOptions() {
        return [
            { label: T.trigManual, value: 'manual' },
            { label: T.trigAuto, value: 'auto' }
        ];
    }

    messageOf(e, fallback) {
        return (e && e.body && e.body.message) || (e && e.message) || fallback;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
