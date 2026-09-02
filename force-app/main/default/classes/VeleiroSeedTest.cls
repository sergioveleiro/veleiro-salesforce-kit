@isTest
private class VeleiroSeedTest {

    @isTest
    static void seedInsertsDefaultMappings() {
        Test.startTest();
        Integer n = VeleiroSeed.seed();
        Test.stopTest();

        System.assertEquals(6, n);
        System.assertEquals(6, [SELECT COUNT() FROM Veleiro_Field_Mapping__c]);
        System.assertEquals(3, [SELECT COUNT() FROM Veleiro_Field_Mapping__c WHERE SObject__c = 'Account']);
        System.assertEquals(3, [SELECT COUNT() FROM Veleiro_Field_Mapping__c WHERE SObject__c = 'Opportunity']);
    }

    @isTest
    static void seedIsIdempotent() {
        VeleiroSeed.seed();
        Test.startTest();
        VeleiroSeed.seed(); // corre 2 veces -> borra e inserta, no acumula
        Test.stopTest();
        System.assertEquals(6, [SELECT COUNT() FROM Veleiro_Field_Mapping__c], 'no duplica');
    }
}
