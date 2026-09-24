@isTest
private class VeleiroLinkControllerTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    // Mapeo minimo: la pantalla de Link solo ofrece lo que este configurado.
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
        mapField('Contact', 'client', 'LastName', 'name', 'Standard');
        mapField('Opportunity', 'project', 'Name', 'name', 'Standard');

        List<VeleiroLinkController.Pair> pairs = VeleiroLinkController.getPairs();
        Set<String> values = new Set<String>();
        for (VeleiroLinkController.Pair p : pairs) values.add(p.value);
        System.assertEquals(new Set<String>{ 'Account|client', 'Contact|client', 'Opportunity|project' }, values);
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
        mapField('Contact', 'client', 'LastName', 'name', 'Standard');
        Contact c = new Contact(LastName = 'Acme');
        insert c;
        mockClients('{"data":[{"id":"org_acme","name":"ACME","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions('Contact', 'client');
        Test.stopTest();

        System.assertEquals('Contact', o.sobjectName);
        System.assertEquals(c.Id, o.rows[0].suggestedRecordId, 'empareja por el campo mapeado a name');
    }

    @isTest
    static void linkStoresTheLinkOnTheCustomObject() {
        mapField('Contact', 'client', 'LastName', 'name', 'Standard');
        Contact c = new Contact(LastName = 'Acme');
        insert c;

        Test.startTest();
        VeleiroLinkController.LinkResult r = VeleiroLinkController.linkAll('Contact', 'client', JSON.serialize(
            new List<Map<String, String>>{ new Map<String, String>{ 'recordId' => c.Id, 'veleiroId' => 'org_acme' } }));
        Test.stopTest();

        System.assertEquals(1, r.linked);
        System.assertEquals(false, r.syncing);
        Veleiro_Link__c link = [SELECT Veleiro_Id__c, SObject__c FROM Veleiro_Link__c];
        System.assertEquals('org_acme', link.Veleiro_Id__c);
        System.assertEquals('Contact', link.SObject__c);
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
}
