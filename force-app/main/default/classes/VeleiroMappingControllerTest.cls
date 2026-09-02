@isTest
private class VeleiroMappingControllerTest {

    @isTest
    static void seedAndGetMappings() {
        Integer seeded = VeleiroSeed.seed();
        System.assertEquals(6, seeded);

        Test.startTest();
        List<Veleiro_Field_Mapping__c> ms = VeleiroMappingController.getMappings();
        Test.stopTest();

        System.assertEquals(6, ms.size());
        Set<String> objs = new Set<String>();
        for (Veleiro_Field_Mapping__c m : ms) objs.add(m.SObject__c);
        System.assert(objs.contains('Account'));
        System.assert(objs.contains('Opportunity'));
    }

    @isTest
    static void objectsAndFields() {
        Test.startTest();
        List<VeleiroMappingController.Option> objs = VeleiroMappingController.getObjects();
        List<VeleiroMappingController.Option> fields = VeleiroMappingController.getFields('Account');
        List<VeleiroMappingController.Option> none = VeleiroMappingController.getFields(null);
        Test.stopTest();

        System.assert(!objs.isEmpty(), 'debe listar objetos');
        Boolean hasAccount = false;
        for (VeleiroMappingController.Option o : objs) if (o.value == 'Account') hasAccount = true;
        System.assert(hasAccount, 'Account entre los objetos');

        System.assert(!fields.isEmpty(), 'debe listar campos de Account');
        System.assertEquals(0, none.size(), 'objeto nulo -> sin campos');
    }

    @isTest
    static void defaultTemplateForKnownPairs() {
        Test.startTest();
        List<Veleiro_Field_Mapping__c> acc = VeleiroMappingController.defaultTemplate('Account', 'client');
        List<Veleiro_Field_Mapping__c> opp = VeleiroMappingController.defaultTemplate('Opportunity', 'project');
        List<Veleiro_Field_Mapping__c> unknown = VeleiroMappingController.defaultTemplate('Case', 'client');
        Test.stopTest();

        System.assertEquals(3, acc.size(), 'Account->client tiene 3 defaults');
        System.assertEquals(3, opp.size(), 'Opportunity->project tiene 3 defaults');
        System.assertEquals(0, unknown.size(), 'par desconocido -> manual');
    }

    @isTest
    static void saveThenReadThenDelete() {
        VeleiroMappingController.MappingRow r1 = new VeleiroMappingController.MappingRow();
        r1.sfField = 'Subject'; r1.target = 'name'; r1.type = 'Standard';
        VeleiroMappingController.MappingRow r2 = new VeleiroMappingController.MappingRow();
        r2.sfField = 'Priority'; r2.target = 'sf_priority'; r2.type = 'Additional Field';
        VeleiroMappingController.MappingRow blank = new VeleiroMappingController.MappingRow(); // se ignora

        Test.startTest();
        VeleiroMappingController.saveMappings('Case', 'project',
            new List<VeleiroMappingController.MappingRow>{ r1, r2, blank }, null);
        List<Veleiro_Field_Mapping__c> saved = VeleiroMappingController.getMappingsFor('Case', 'project');
        Test.stopTest();

        System.assertEquals(2, saved.size(), 'guarda 2 (ignora la fila vacia)');

        // borra una
        VeleiroMappingController.saveMappings('Case', 'project',
            new List<VeleiroMappingController.MappingRow>(), new List<Id>{ saved[0].Id });
        System.assertEquals(1, VeleiroMappingController.getMappingsFor('Case', 'project').size(), 'quedo 1');
    }

    @isTest
    static void saveUpdatesExistingRow() {
        VeleiroMappingController.MappingRow r = new VeleiroMappingController.MappingRow();
        r.sfField = 'Name'; r.target = 'name'; r.type = 'Standard';
        VeleiroMappingController.saveMappings('Account', 'client',
            new List<VeleiroMappingController.MappingRow>{ r }, null);
        Veleiro_Field_Mapping__c existing = VeleiroMappingController.getMappingsFor('Account', 'client')[0];

        VeleiroMappingController.MappingRow upd = new VeleiroMappingController.MappingRow();
        upd.id = existing.Id; upd.sfField = 'Name'; upd.target = 'display_name'; upd.type = 'Standard';

        Test.startTest();
        VeleiroMappingController.saveMappings('Account', 'client',
            new List<VeleiroMappingController.MappingRow>{ upd }, null);
        Test.stopTest();

        List<Veleiro_Field_Mapping__c> after = VeleiroMappingController.getMappingsFor('Account', 'client');
        System.assertEquals(1, after.size(), 'no duplica, actualiza');
        System.assertEquals('display_name', after[0].Veleiro_Target__c);
    }
}
