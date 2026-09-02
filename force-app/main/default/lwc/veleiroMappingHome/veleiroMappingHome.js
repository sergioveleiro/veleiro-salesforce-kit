import { LightningElement, wire } from 'lwc';
import VELEIRO_LOGO from '@salesforce/resourceUrl/VeleiroLogo';
import VELEIRO_MASCOT from '@salesforce/resourceUrl/VeleiroMascot';
import getMappings from '@salesforce/apex/VeleiroMappingController.getMappings';

const ICONS = {
    Account: 'standard:account',
    Opportunity: 'standard:opportunity',
    Contact: 'standard:contact'
};

export default class VeleiroMappingHome extends LightningElement {
    logoUrl = VELEIRO_LOGO;
    mascotUrl = VELEIRO_MASCOT;
    groups = [];
    total = 0;
    error;

    @wire(getMappings)
    wired({ data, error }) {
        if (data) {
            this.total = data.length;
            const byObj = {};
            data.forEach((m) => {
                const obj = m.SObject__c || 'Other';
                if (!byObj[obj]) byObj[obj] = [];
                byObj[obj].push({
                    id: `${obj}-${m.SF_Field__c}`,
                    sfField: m.SF_Field__c,
                    target: m.Veleiro_Target__c,
                    type: m.Target_Type__c,
                    isStandard: m.Is_Standard__c,
                    typeClass: m.Target_Type__c === 'Standard'
                        ? 'veleiro-pill veleiro-pill-standard'
                        : 'veleiro-pill veleiro-pill-custom'
                });
            });
            this.groups = Object.keys(byObj)
                .sort()
                .map((obj) => ({
                    object: obj,
                    icon: ICONS[obj] || 'standard:record',
                    count: byObj[obj].length,
                    rows: byObj[obj]
                }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
        }
    }
}
