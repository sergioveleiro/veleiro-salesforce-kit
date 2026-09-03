import { LightningElement } from 'lwc';
import { MASCOT as VELEIRO_MASCOT } from 'c/veleiroBrand';
import getBriefing from '@salesforce/apex/VeleiroInsightService.getBriefing';

const COLUMNS = [
    { key: 'expand', title: 'Expand now', icon: '🚀', field: 'expand' },
    { key: 'risk', title: 'At risk', icon: '⚠️', field: 'risk' },
    { key: 'attention', title: 'Needs attention', icon: '🧭', field: 'attention' }
];

export default class VeleiroBriefing extends LightningElement {
    mascotUrl = VELEIRO_MASCOT;
    briefing;
    columns = [];
    loading = true;
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            const b = await getBriefing();
            this.briefing = b;
            this.columns = COLUMNS.map((col) => ({
                ...col,
                items: (b[col.field] || []).map((ci) => ({
                    ...ci,
                    scoreClass: this.scoreClass(ci.score)
                })),
                count: (b[col.field] || []).length
            }));
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : 'Velly could not read Veleiro right now.';
        } finally {
            this.loading = false;
        }
    }

    scoreClass(score) {
        if (score >= 70) return 'veleiro-score veleiro-score-good';
        if (score >= 45) return 'veleiro-score veleiro-score-mid';
        return 'veleiro-score veleiro-score-bad';
    }

    handleRefresh() {
        this.load();
    }
}
