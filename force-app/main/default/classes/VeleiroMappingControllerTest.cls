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
            new List<VeleiroMappingController.MappingRow>{ r1, r2, blank }, null, null);
        List<Veleiro_Field_Mapping__c> saved = VeleiroMappingController.getMappingsFor('Case', 'project');
        Test.stopTest();

        System.assertEquals(2, saved.size(), 'guarda 2 (ignora la fila vacia)');

        // Reemplazo por par: reenviar solo r2 deja el par con 1 (r1 se elimina).
        VeleiroMappingController.saveMappings('Case', 'project',
            new List<VeleiroMappingController.MappingRow>{ r2 }, null, null);
        List<Veleiro_Field_Mapping__c> after = VeleiroMappingController.getMappingsFor('Case', 'project');
        System.assertEquals(1, after.size(), 'quedo 1');
        System.assertEquals('Priority', after[0].SF_Field__c, 'quedo el reenviado, no el omitido');
    }

    @isTest
    static void saveIsIdempotentNoDuplicates() {
        VeleiroMappingController.MappingRow n = new VeleiroMappingController.MappingRow();
        n.sfField = 'Name'; n.target = 'name';
        VeleiroMappingController.MappingRow w = new VeleiroMappingController.MappingRow();
        w.sfField = 'Website'; w.target = 'sf_website';

        Test.startTest();
        // Guardar el MISMO par tres veces no debe acumular duplicados.
        for (Integer i = 0; i < 3; i++) {
            VeleiroMappingController.saveMappings('Account', 'client',
                new List<VeleiroMappingController.MappingRow>{ n, w }, null, null);
        }
        Test.stopTest();

        System.assertEquals(2, VeleiroMappingController.getMappingsFor('Account', 'client').size(),
            'reemplazo por par -> siempre 2, sin duplicar');
    }

    @isTest
    static void saveUpdatesExistingRow() {
        VeleiroMappingController.MappingRow r = new VeleiroMappingController.MappingRow();
        r.sfField = 'Name'; r.target = 'name'; r.type = 'Standard';
        VeleiroMappingController.saveMappings('Account', 'client',
            new List<VeleiroMappingController.MappingRow>{ r }, null, null);
        Veleiro_Field_Mapping__c existing = VeleiroMappingController.getMappingsFor('Account', 'client')[0];

        VeleiroMappingController.MappingRow upd = new VeleiroMappingController.MappingRow();
        upd.id = existing.Id; upd.sfField = 'Name'; upd.target = 'display_name'; upd.type = 'Standard';

        Test.startTest();
        VeleiroMappingController.saveMappings('Account', 'client',
            new List<VeleiroMappingController.MappingRow>{ upd }, null, null);
        Test.stopTest();

        List<Veleiro_Field_Mapping__c> after = VeleiroMappingController.getMappingsFor('Account', 'client');
        System.assertEquals(1, after.size(), 'no duplica, actualiza');
        System.assertEquals('display_name', after[0].Veleiro_Target__c);
    }

    @isTest
    static void getTargetsReturnsCatalogWithCustom() {
        // Sin token configurado -> no hay callout de descubrimiento; solo catalogo canonico.
        Test.startTest();
        List<VeleiroMappingController.Option> client = VeleiroMappingController.getTargets('client');
        List<VeleiroMappingController.Option> project = VeleiroMappingController.getTargets('project');
        Test.stopTest();

        Set<String> cv = new Set<String>();
        for (VeleiroMappingController.Option o : client) cv.add(o.value);
        System.assert(cv.contains('name'), 'incluye el top-level name');
        System.assert(cv.contains('sf_website'), 'incluye el catalogo canonico de client');
        System.assert(cv.contains('__custom__'), 'incluye el escape Custom');

        Set<String> pv = new Set<String>();
        for (VeleiroMappingController.Option o : project) pv.add(o.value);
        System.assert(pv.contains('sf_amount'), 'catalogo canonico de project');
    }

    @isTest
    static void getTargetsDiscoversInUseKeys() {
        VeleiroApiMock.seedConfig();
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[{"id":"org_1","additional_fields":{"sf_custom_extra":"x"}}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<VeleiroMappingController.Option> client = VeleiroMappingController.getTargets('client');
        Test.stopTest();

        Set<String> cv = new Set<String>();
        for (VeleiroMappingController.Option o : client) cv.add(o.value);
        System.assert(cv.contains('sf_custom_extra'), 'descubre llaves ya en uso en Veleiro');
    }

    @isTest
    static void statusTokenAndConfigRoundTrip() {
        VeleiroApiMock.seedConfig(); // base https que el mock intercepta (callout: no resuelve en test)
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroMappingController.saveToken('vlr_test');
        Map<String, String> st = VeleiroMappingController.getStatus();
        VeleiroMappingController.saveSyncConfig('bidirectional', 'salesforce', 'off');
        Map<String, String> cfg = VeleiroMappingController.getSyncConfig();
        Test.stopTest();

        System.assertEquals('true', st.get('tokenSet'), 'token guardado');
        System.assert(st.containsKey('connected'), 'getStatus evalua la conexion');
        System.assertEquals('bidirectional', cfg.get('direction'));
    }

    @isTest
    static void saveNormalizesTargetAndInfersType() {
        VeleiroMappingController.MappingRow messy = new VeleiroMappingController.MappingRow();
        messy.sfField = 'Website'; messy.target = '  Web Site '; // se normaliza
        VeleiroMappingController.MappingRow std = new VeleiroMappingController.MappingRow();
        std.sfField = 'Name'; std.target = 'Name'; // top-level -> Standard

        Test.startTest();
        VeleiroMappingController.saveMappings('Account', 'client',
            new List<VeleiroMappingController.MappingRow>{ messy, std }, null, null);
        Test.stopTest();

        Map<String, Veleiro_Field_Mapping__c> byField = new Map<String, Veleiro_Field_Mapping__c>();
        for (Veleiro_Field_Mapping__c m : VeleiroMappingController.getMappingsFor('Account', 'client')) {
            byField.put(m.SF_Field__c, m);
        }
        System.assertEquals('web_site', byField.get('Website').Veleiro_Target__c, 'target normalizado');
        System.assertEquals('Additional Field', byField.get('Website').Target_Type__c);
        System.assertEquals('name', byField.get('Name').Veleiro_Target__c);
        System.assertEquals('Standard', byField.get('Name').Target_Type__c, 'name -> top-level Standard');
    }

    @isTest
    static void saveAllInvalidRowsThrowsAndPreservesExisting() {
        // Existe un mapping valido.
        VeleiroMappingController.MappingRow good = new VeleiroMappingController.MappingRow();
        good.sfField = 'Name'; good.target = 'name';
        VeleiroMappingController.saveMappings('Account', 'client',
            new List<VeleiroMappingController.MappingRow>{ good }, null, null);
        System.assertEquals(1, VeleiroMappingController.getMappingsFor('Account', 'client').size());

        // Mando una fila con target basura ('###' pasa el filtro truthy del LWC pero normalize -> '').
        VeleiroMappingController.MappingRow garbage = new VeleiroMappingController.MappingRow();
        garbage.sfField = 'Name'; garbage.target = '###';
        Boolean threw = false;
        Test.startTest();
        try {
            VeleiroMappingController.saveMappings('Account', 'client',
                new List<VeleiroMappingController.MappingRow>{ garbage }, null, null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'todas las filas invalidas -> lanza error, no guarda en silencio');
        System.assertEquals(1, VeleiroMappingController.getMappingsFor('Account', 'client').size(),
            'el mapping previo NO se destruye');
    }
}
