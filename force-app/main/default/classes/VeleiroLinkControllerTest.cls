@isTest
private class VeleiroLinkControllerTest {
    // Con namespace el objeto se llama veleiro__Veleiro_Field_Mapping__c: se lee del describe.
    private static final String KIT_OBJECT = String.valueOf(Veleiro_Field_Mapping__c.SObjectType);


    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    // Mapeo minimo: la pantalla de Link solo ofrece lo que este configurado.
    // Registro de prueba sobre un objeto del propio kit: inmune a las reglas del cliente.
    private static Veleiro_Field_Mapping__c anyRecord(String name) {
        Veleiro_Field_Mapping__c r = new Veleiro_Field_Mapping__c(
            Name = name, SObject__c = 'ZZ_TEST_RECORD', Veleiro_Entity__c = 'client',
            SF_Field__c = 'Name', Veleiro_Target__c = 'name', Target_Type__c = 'Standard',
            Active__c = false
        );
        insert r;
        return r;
    }

    private static void mapField(String sobjectName, String entity, String sfField, String target, String targetType) {
        insert new Veleiro_Field_Mapping__c(
            Name = sobjectName + ' ' + sfField, SObject__c = sobjectName, Veleiro_Entity__c = entity,
            SF_Field__c = sfField, Veleiro_Target__c = target, Target_Type__c = targetType, Active__c = true
        );
    }

    private static void mockClients(String json) {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = json;
        Test.setMock(HttpCalloutMock.class, mock);
    }

    private static VeleiroLinkController.VeleiroRow rowFor(VeleiroLinkController.Overview o, String veleiroId) {
        for (VeleiroLinkController.VeleiroRow r : o.rows) if (r.veleiroId == veleiroId) return r;
        return null;
    }

    @isTest
    static void withoutMappingsThereIsNothingToLink() {
        insert new Account(Name = 'Acme');
        mockClients('{"data":[{"id":"org_acme","name":"Acme","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions(null, null);
        Test.stopTest();

        System.assert(o.pairs.isEmpty(), 'sin mapeos no hay pares');
        System.assert(o.rows.isEmpty(), 'y no se sugiere nada');
    }

    @isTest
    static void pairsComeFromTheConfiguredMappings() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        mapField(KIT_OBJECT, 'client', 'Name', 'name', 'Standard');
        mapField('Opportunity', 'project', 'Name', 'name', 'Standard');

        List<VeleiroLinkController.Pair> pairs = VeleiroLinkController.getPairs();
        Set<String> values = new Set<String>();
        for (VeleiroLinkController.Pair p : pairs) values.add(p.value);
        System.assertEquals(new Set<String>{ 'Account|client', KIT_OBJECT + '|client', 'Opportunity|project' }, values);
    }

    @isTest
    static void listsUnlinkedClientsWithCandidatesForTheChosenObject() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        mapField('Account', 'client', 'Website', 'sf_website', 'Additional Field');
        Account domainMatch = new Account(Name = 'Razon Social Distinta', Website = 'https://acme.com');
        Account nameMatch = new Account(Name = 'Globex S.A.');
        insert new List<Account>{ domainMatch, nameMatch };

        mockClients('{"data":[' +
            '{"id":"org_acme","name":"Acme","additional_fields":{"sf_website":"http://www.acme.com/x"}},' +
            '{"id":"org_globex","name":"GLOBEX SAS","additional_fields":{}},' +
            '{"id":"org_alone","name":"Nadie Se Le Parece","additional_fields":{}}' +
            '],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions('Account', 'client');
        Test.stopTest();

        System.assertEquals('Account', o.sobjectName);
        System.assertEquals(3, o.rows.size(), 'todos los clients sin vincular, con o sin candidato');
        System.assertEquals(3, o.veleiroUnlinked);
        System.assertEquals(2, o.recordsUnlinked);
        System.assertEquals('org_acme', o.rows[0].veleiroId, 'la coincidencia fuerte va primero');
        System.assertEquals(domainMatch.Id, o.rows[0].suggestedRecordId);
        System.assertEquals('high', o.rows[0].confidence);
        System.assertEquals(nameMatch.Id, rowFor(o, 'org_globex').suggestedRecordId);
        System.assert(rowFor(o, 'org_alone').options.isEmpty());
    }

    @isTest
    static void worksWithAnyMappedObjectNotJustAccount() {
        mapField(KIT_OBJECT, 'client', 'Name', 'name', 'Standard');
        Veleiro_Field_Mapping__c c = anyRecord('Acme');
        mockClients('{"data":[{"id":"org_acme","name":"ACME","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions(KIT_OBJECT, 'client');
        Test.stopTest();

        System.assertEquals(KIT_OBJECT, o.sobjectName);
        System.assertEquals(c.Id, o.rows[0].suggestedRecordId, 'empareja por el campo mapeado a name');
    }

    @isTest
    static void linkStoresTheLinkOnTheCustomObject() {
        mapField(KIT_OBJECT, 'client', 'Name', 'name', 'Standard');
        Veleiro_Field_Mapping__c c = anyRecord('Acme');

        Test.startTest();
        VeleiroLinkController.LinkResult r = VeleiroLinkController.linkAll(KIT_OBJECT, 'client', JSON.serialize(
            new List<Map<String, String>>{ new Map<String, String>{ 'recordId' => c.Id, 'veleiroId' => 'org_acme' } }));
        Test.stopTest();

        System.assertEquals(1, r.linked);
        System.assertEquals(false, r.syncing);
        Veleiro_Link__c link = [SELECT Veleiro_Id__c, SObject__c FROM Veleiro_Link__c];
        System.assertEquals('org_acme', link.Veleiro_Id__c);
        System.assertEquals(KIT_OBJECT, link.SObject__c);
    }

    @isTest
    static void linkWritesAccountsOnTheirOwnField() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        Account a = new Account(Name = 'Acme');
        insert a;

        Test.startTest();
        VeleiroLinkController.LinkResult r = VeleiroLinkController.linkAll('Account', 'client', JSON.serialize(
            new List<Map<String, String>>{ new Map<String, String>{ 'recordId' => a.Id, 'veleiroId' => 'org_acme' } }));
        Test.stopTest();

        System.assertEquals(1, r.linked);
        System.assertEquals('org_acme', [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id].Veleiro_Client_Id__c);
        System.assertEquals(0, [SELECT COUNT() FROM Veleiro_Link__c], 'Account usa su campo, no el objeto de vinculos');
    }

    @isTest
    static void linkAndSyncPushesTheMappedFields() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        mapField('Account', 'client', 'Website', 'sf_website', 'Additional Field');
        Account a = new Account(Name = 'Acme', Website = 'https://acme.com');
        insert a;
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.singleClientBody = '{"data":{"id":"org_acme","name":"Acme","version":3,"additional_fields":{"otro":"no se pisa"}}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroLinkController.LinkResult r = VeleiroLinkController.linkAndSync('Account', 'client', JSON.serialize(
            new List<Map<String, String>>{ new Map<String, String>{ 'recordId' => a.Id, 'veleiroId' => 'org_acme' } }));
        Test.stopTest(); // el Queueable corre aqui

        System.assertEquals(1, r.linked);
        System.assertEquals(true, r.syncing);
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPatchBody);
        Map<String, Object> af = (Map<String, Object>) sent.get('additional_fields');
        System.assertEquals('https://acme.com', af.get('sf_website'), 'los campos mapeados viajan a Veleiro');
        System.assertEquals(String.valueOf(a.Id), af.get('sf_account_id'));
        System.assertEquals('no se pisa', af.get('otro'), 'lo que ya tenia Veleiro se conserva');
    }

    @isTest
    static void neverReusesARecordOrAResource() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        Account taken = new Account(Name = 'Primera', Veleiro_Client_Id__c = 'org_acme');
        Account other = new Account(Name = 'Segunda');
        insert new List<Account>{ taken, other };

        Test.startTest();
        VeleiroLinkController.LinkResult r = VeleiroLinkController.linkAll('Account', 'client', JSON.serialize(
            new List<Map<String, String>>{
                new Map<String, String>{ 'recordId' => other.Id, 'veleiroId' => 'org_acme' }, // client ocupado
                new Map<String, String>{ 'recordId' => taken.Id, 'veleiroId' => 'org_otro' }, // cuenta ocupada
                new Map<String, String>{ 'recordId' => other.Id, 'veleiroId' => '' }          // fila vacia
            }));
        Test.stopTest();

        System.assertEquals(0, r.linked);
        System.assertEquals(2, r.skipped);
        System.assertEquals(null, [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :other.Id].Veleiro_Client_Id__c);
    }

    @isTest
    static void tooManyRecordsStopsMatching() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        VeleiroLinkController.maxRecords = 0;
        insert new Account(Name = 'Acme');
        mockClients('{"data":[{"id":"org_acme","name":"Acme","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions('Account', 'client');
        Test.stopTest();

        System.assertEquals(true, o.truncated);
        System.assertEquals(1, o.rows.size(), 'los clients se listan igual, sin candidatos');
        System.assert(o.rows[0].options.isEmpty());
    }

    @isTest
    static void linkSyncQueueableSkipsWhatFailsAndKeepsGoing() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        Account a = new Account(Name = 'Acme', Veleiro_Client_Id__c = 'org_acme');
        insert a;
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 404;
        mock.overrideBody = '{"error":{"code":"not_found"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new VeleiroLinkSyncQueueable(new List<Id>{ a.Id }, 'client'));
        Test.stopTest();

        System.assertEquals('org_acme', [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id].Veleiro_Client_Id__c,
            'el error de Veleiro no rompe el lote ni borra el vinculo');
    }

    @isTest
    static void searchRecordsFindsUnlinkedOnesByName() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        insert new Account(Name = 'Buscable Uno');
        insert new Account(Name = 'Buscable Dos', Veleiro_Client_Id__c = 'org_x');

        List<VeleiroLinkController.RecordOption> found =
            VeleiroLinkController.searchRecords('Account', 'client', 'buscable');

        System.assertEquals(1, found.size(), 'solo los que faltan por vincular');
        System.assertEquals('Buscable Uno', found[0].name);
        System.assert(VeleiroLinkController.searchRecords('Account', 'client', 'a').isEmpty(), 'busqueda muy corta');
        System.assert(VeleiroLinkController.searchRecords('Account', 'client', null).isEmpty());
        System.assert(VeleiroLinkController.searchRecords('NoExiste__c', 'client', 'algo').isEmpty());
    }

    @isTest
    static void searchRecordsUsesTheMappedNameFieldOfAnyObject() {
        mapField(KIT_OBJECT, 'client', 'Name', 'name', 'Standard');
        anyRecord('Buscable Registro');

        List<VeleiroLinkController.RecordOption> found =
            VeleiroLinkController.searchRecords(KIT_OBJECT, 'client', 'buscable');
        System.assertEquals(1, found.size());
        System.assertEquals('Buscable Registro', found[0].name);
    }

    // ================= Enviar a Veleiro =================

    // El escaneo trae, del MISMO listado, lo que falta por enviar y lo que falta por emparejar.
    @isTest
    static void theScanAlsoListsWhatIsNotInVeleiroYet() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        insert new List<Account>{ new Account(Name = 'Alfa'), new Account(Name = 'Beta') };
        mockClients('{"data":[],"has_more":false}');   // Veleiro vacio: cliente nuevo

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions('Account', 'client');
        Test.stopTest();

        System.assertEquals(2, o.candidates.size(), 'las dos cuentas estan listas para enviarse');
        System.assertEquals(0, o.veleiroUnlinked, 'y no hay nada que emparejar');
        System.assertEquals(true, o.pushEnabled);
        System.assert(o.maxPerBatch > 0, 'el UI necesita el tope por tanda');
        System.assert(o.mappingsTab.endsWith('Veleiro_Mappings'));
        for (VeleiroLinkController.SendCandidate c : o.candidates) {
            System.assertEquals(null, c.matchVeleiroId, 'nada se le parece: no hay duplicado posible');
        }
    }

    // Lo que ya existe en Veleiro queda avisado en el candidato, para no crear un duplicado.
    @isTest
    static void aCandidateWarnsWhenSomethingLikeItIsAlreadyInVeleiro() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        insert new Account(Name = 'Globex');
        mockClients('{"data":[{"id":"org_globex","name":"Globex","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions('Account', 'client');
        Test.stopTest();

        System.assertEquals(1, o.candidates.size());
        VeleiroLinkController.SendCandidate c = o.candidates[0];
        System.assertEquals('org_globex', c.matchVeleiroId, 'se avisa cual podria ser');
        System.assertEquals('Globex', c.matchName);
        System.assert(String.isNotBlank(c.matchReason), 'y por que: ' + c.matchReason);
    }

    @isTest
    static void sendingQueuesTheRecordsAndSkipsTheLinkedOnes() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        Account fresh = new Account(Name = 'Sin vinculo');
        Account linked = new Account(Name = 'Ya vinculada', Veleiro_Client_Id__c = 'org_done');
        insert new List<Account>{ fresh, linked };

        Test.startTest();
        VeleiroLinkController.SendResult res = VeleiroLinkController.sendToVeleiro('Account', 'client',
            JSON.serialize(new List<Object>{
                new Map<String, Object>{ 'recordId' => fresh.Id },
                new Map<String, Object>{ 'recordId' => linked.Id },
                new Map<String, Object>{ 'recordId' => fresh.Id },      // repetido
                new Map<String, Object>{ 'recordId' => 'no-es-un-id' }
            }));
        Test.stopTest();

        System.assertEquals(1, res.queued, 'solo la que no tiene vinculo, una vez');
        System.assertEquals(1, res.skipped, 'la vinculada se avisa, no se reenvia');
    }

    @isTest
    static void sendingRefusesWhenTheDirectionForbidsIt() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        Account a = new Account(Name = 'No deberia salir');
        insert a;
        VeleiroSyncConfig.save('veleiro_to_sf', 'veleiro', 'off', 'manual');

        Boolean threw = false;
        try {
            VeleiroLinkController.sendToVeleiro('Account', 'client',
                JSON.serialize(new List<Object>{ new Map<String, Object>{ 'recordId' => a.Id } }));
        } catch (Exception e) {
            threw = true;
            System.assert(e.getMessage().contains('Veleiro'), 'explica por que: ' + e.getMessage());
        }
        System.assertEquals(true, threw, 'con direccion Veleiro -> Salesforce no se envia nada');
        // El UI lo sabe antes de que el usuario lo intente: getSuggestions publica este mismo
        // valor en Overview.pushEnabled (probado en el escaneo, que ahi si puede hacer callout:
        // guardar la config es DML, y despues de un DML no se puede llamar a Veleiro).
        System.assertEquals(false, VeleiroSyncConfig.pushEnabled());
    }

    @isTest
    static void sendingRefusesABatchOverTheLimit() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        List<Account> many = new List<Account>();
        for (Integer i = 0; i < 5; i++) many.add(new Account(Name = 'Cuenta ' + i));
        insert many;
        VeleiroLinkController.maxPerBatch = 3;

        List<Object> rows = new List<Object>();
        for (Account a : many) rows.add(new Map<String, Object>{ 'recordId' => a.Id });

        Boolean threw = false;
        try {
            VeleiroLinkController.sendToVeleiro('Account', 'client', JSON.serialize(rows));
        } catch (Exception e) {
            threw = true;
            System.assert(e.getMessage().contains('3'), 'dice el tope: ' + e.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void sendingNeedsAMapping() {
        Account a = new Account(Name = 'Sin mapeo');
        insert a;
        Boolean threw = false;
        try {
            VeleiroLinkController.sendToVeleiro('Account', 'client',
                JSON.serialize(new List<Object>{ new Map<String, Object>{ 'recordId' => a.Id } }));
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'sin mapeo no hay payload que mandar');
        System.assertEquals(0, VeleiroLinkController.sendToVeleiro(null, null, '[]').queued);
    }

    // El avance se mide por el vinculo guardado, que es la prueba de que Veleiro respondio.
    @isTest
    static void progressCountsTheRecordsThatAlreadyHaveTheirLink()  {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        Account done = new Account(Name = 'Llego', Veleiro_Client_Id__c = 'org_llego');
        Account pending = new Account(Name = 'No llego');
        insert new List<Account>{ done, pending };
        String ids = JSON.serialize(new List<Id>{ done.Id, pending.Id });

        Test.startTest();
        VeleiroLinkController.SendProgress p = VeleiroLinkController.getSendProgress('Account', 'client', ids);
        Test.stopTest();

        System.assertEquals(2, p.total);
        System.assertEquals(1, p.sent);
        System.assertEquals(new List<Id>{ done.Id }, p.doneIds, 'el UI marca solo el que ya esta');
        System.assertEquals(false, p.running, 'no hay jobs encolados en este test');
        System.assertEquals(0, VeleiroLinkController.getSendProgress('Account', 'client', null).total);
    }

    // Sin token (o con Veleiro caido) la pantalla no truena: dice que hay que conectar.
    @isTest
    static void aBrokenConnectionBecomesGuidanceNotAnError() {
        mapField('Account', 'client', 'Name', 'name', 'Standard');
        insert new Account(Name = 'Alguien');
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 401;
        mock.overrideBody = '{"error":{"code":"invalid_token"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions('Account', 'client');
        Test.stopTest();

        System.assert(String.isNotBlank(o.connectionError), 'el UI sabe por que no puede trabajar');
        System.assert(o.rows.isEmpty());
        System.assert(o.candidates.isEmpty());
        System.assert(o.setupTab.endsWith('Veleiro_Setup'), 'y a donde mandar al usuario');
    }
}
