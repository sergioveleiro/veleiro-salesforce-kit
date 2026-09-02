public with sharing class VeleiroMappingController {
    @AuraEnabled(cacheable=true)
    public static List<Veleiro_Field_Mapping__c> getMappings() {
        return [
            SELECT Name, SObject__c, SF_Field__c, Veleiro_Target__c, Target_Type__c, Is_Standard__c, Active__c
            FROM Veleiro_Field_Mapping__c
            WHERE Active__c = true
            ORDER BY SObject__c, Is_Standard__c DESC, SF_Field__c
        ];
    }
}
