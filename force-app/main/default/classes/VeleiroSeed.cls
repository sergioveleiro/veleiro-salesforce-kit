public with sharing class VeleiroSeed {
    public static Integer seed() {
        delete [SELECT Id FROM Veleiro_Field_Mapping__c];
        insert defaults();
        return 6;
    }

    // Los mapeos default que "hacen sentido": Account -> client, Opportunity -> project.
    // Se usan tanto para sembrar como para autopopular en el builder.
    public static List<Veleiro_Field_Mapping__c> defaults() {
        List<Veleiro_Field_Mapping__c> ms = new List<Veleiro_Field_Mapping__c>();
        ms.addAll(defaultsFor('Account', 'client'));
        ms.addAll(defaultsFor('Opportunity', 'project'));
        return ms;
    }

    // Devuelve las filas default para un par (objeto, entidad) conocido; lista vacia si no hay.
    public static List<Veleiro_Field_Mapping__c> defaultsFor(String sobjectName, String entity) {
        List<Veleiro_Field_Mapping__c> ms = new List<Veleiro_Field_Mapping__c>();
        if (sobjectName == 'Account' && entity == 'client') {
            ms.add(row('Account Name',    'Account', 'client', 'Name',    'name',          'Standard',         true));
            ms.add(row('Account Id',      'Account', 'client', 'Id',      'sf_account_id', 'Additional Field', true));
            ms.add(row('Account Website', 'Account', 'client', 'Website', 'sf_website',    'Additional Field', false));
        } else if (sobjectName == 'Opportunity' && entity == 'project') {
            ms.add(row('Opportunity Name',   'Opportunity', 'project', 'Name',      'name',          'Standard',         true));
            ms.add(row('Opportunity Amount', 'Opportunity', 'project', 'Amount',    'sf_amount',     'Additional Field', false));
            ms.add(row('Opportunity Close',  'Opportunity', 'project', 'CloseDate', 'sf_close_date', 'Additional Field', false));
        }
        return ms;
    }

    // TRUE si el par (objeto, entidad) tiene defaults conocidos que hace sentido autopopular.
    public static Boolean hasDefaults(String sobjectName, String entity) {
        return !defaultsFor(sobjectName, entity).isEmpty();
    }

    private static Veleiro_Field_Mapping__c row(String name, String obj, String entity,
            String sfField, String target, String type, Boolean isStd) {
        return new Veleiro_Field_Mapping__c(
            Name = name, SObject__c = obj, Veleiro_Entity__c = entity,
            SF_Field__c = sfField, Veleiro_Target__c = target,
            Target_Type__c = type, Is_Standard__c = isStd, Active__c = true
        );
    }
}
