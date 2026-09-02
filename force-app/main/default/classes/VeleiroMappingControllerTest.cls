@isTest
private class VeleiroMappingControllerTest {

    @isTest
    static void getMappingsReturnsActiveSeeded() {
        Integer seeded = VeleiroSeed.seed(); // inserta los 6 mapeos default
        System.assertEquals(6, seeded);

        Test.startTest();
        List<Veleiro_Field_Mapping__c> ms = VeleiroMappingController.getMappings();
        Test.stopTest();

        System.assertEquals(6, ms.size(), 'trae los 6 activos');
        // agrupa por objeto: deben venir Account y Opportunity
        Set<String> objs = new Set<String>();
        for (Veleiro_Field_Mapping__c m : ms) objs.add(m.SObject__c);
        System.assert(objs.contains('Account'));
        System.assert(objs.contains('Opportunity'));
    }

    @isTest
    static void inactiveMappingsAreExcluded() {
        VeleiroSeed.seed();
        Veleiro_Field_Mapping__c m = [SELECT Id FROM Veleiro_Field_Mapping__c LIMIT 1];
        m.Active__c = false;
        update m;

        Test.startTest();
        List<Veleiro_Field_Mapping__c> ms = VeleiroMappingController.getMappings();
        Test.stopTest();

        System.assertEquals(5, ms.size(), 'excluye el inactivo');
    }
}
