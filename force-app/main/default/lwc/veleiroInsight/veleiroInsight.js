import { LightningElement, api } from 'lwc';
import { MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getInsightForAccount from '@salesforce/apex/VeleiroInsightService.getInsightForAccount';

export default class VeleiroInsight extends LightningElement {
    _recordId;
    mascotUrl = VELEIRO_MASCOT;
    insight;
    loading = true;
    error;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.load();
        }
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            // Imperativo: getInsightForAccount hace callouts (no puede ser cacheable, por eso no va con @wire).
            this.insight = await getInsightForAccount({ accountId: this._recordId });
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : 'Velly could not read Veleiro.';
        } finally {
            this.loading = false;
        }
    }

    get hasInsight() {
        return this.insight && this.insight.synced && this.insight.score !== undefined && this.insight.score !== null;
    }

    get notSynced() {
        return !this.loading && this.insight && !this.insight.synced;
    }

    get scoreClass() {
        const s = this.insight ? this.insight.score : 0;
        if (s >= 70) return 'velly-score velly-score-good';
        if (s >= 45) return 'velly-score velly-score-mid';
        return 'velly-score velly-score-bad';
    }
}
