public with sharing class VeleiroSeed {
    public static Integer seed() {
        delete [SELECT Id FROM Veleiro_Field_Mapping__c];
        List<Veleiro_Field_Mapping__c> ms = new List<Veleiro_Field_Mapping__c>();
        ms.add(new Veleiro_Field_Mapping__c(Name='Account Name',       SObject__c='Account',     SF_Field__c='Name',      Veleiro_Target__c='name',          Target_Type__c='Standard',         Is_Standard__c=true,  Active__c=true));
        ms.add(new Veleiro_Field_Mapping__c(Name='Account Id',         SObject__c='Account',     SF_Field__c='Id',        Veleiro_Target__c='sf_account_id', Target_Type__c='Additional Field', Is_Standard__c=true,  Active__c=true));
        ms.add(new Veleiro_Field_Mapping__c(Name='Account Website',    SObject__c='Account',     SF_Field__c='Website',   Veleiro_Target__c='sf_website',    Target_Type__c='Additional Field', Is_Standard__c=false, Active__c=true));
        ms.add(new Veleiro_Field_Mapping__c(Name='Opportunity Name',   SObject__c='Opportunity', SF_Field__c='Name',      Veleiro_Target__c='name',          Target_Type__c='Standard',         Is_Standard__c=true,  Active__c=true));
        ms.add(new Veleiro_Field_Mapping__c(Name='Opportunity Amount', SObject__c='Opportunity', SF_Field__c='Amount',    Veleiro_Target__c='sf_amount',     Target_Type__c='Additional Field', Is_Standard__c=false, Active__c=true));
        ms.add(new Veleiro_Field_Mapping__c(Name='Opportunity Close',  SObject__c='Opportunity', SF_Field__c='CloseDate', Veleiro_Target__c='sf_close_date', Target_Type__c='Additional Field', Is_Standard__c=false, Active__c=true));
        insert ms;
        return ms.size();
    }
}
