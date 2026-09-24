@isTest
private class VeleiroRecordSyncTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    // Mapea un objeto cualquiera a una entidad de Veleiro, como lo haria el panel.
    private static void mapField(String sobjectName, String entity, String sfField, String target, String targetType) {
        insert new Veleiro_Field_Mapping__c(
            Name = sobjectName + ' ' + sfField,
            SObject__c = sobjectName,
            Veleiro_Entity__c = entity,
            SF_Field__c = sfField,
            Veleiro_Target__c = target,
            Target_Type__c = targetType,
            Active__c = true
        );
    }

    @isTest
    static void customObjectSyncsAsClientAndStoresTheLink() {
        mapField('Contact', 'client', 'LastName', 'name', 'Standard');
        mapField('Contact', 'client', 'Email', 'sf_email', 'Additional Field');
        Contact c = new Contact(LastName = 'Acme Holding', Email = 'hola@acme.com');
        insert c;
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSyncService.RecordResult r = VeleiroSyncService.syncRecord(c.Id, 'client');
        Test.stopTest();

        System.assertEquals(true, r.created);
        System.assertEquals('org_test', r.veleiroId);

        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPostBody);
        Map<String, Object> af = (Map<String, Object>) sent.get('additional_fields');
        System.assertEquals('Acme Holding', sent.get('name'), 'el nombre sale del mapeo');
        System.assertEquals('hola@acme.com', af.get('sf_email'));
        System.assertEquals(String.valueOf(c.Id), af.get('sf_record_id'));
        System.assertEquals('Contact', af.get('sf_object'));

        Veleiro_Link__c link = [SELECT Veleiro_Id__c, SObject__c, Veleiro_Entity__c, Veleiro_Version__c FROM Veleiro_Link__c];
        System.assertEquals('org_test', link.Veleiro_Id__c);
        System.assertEquals('Contact', link.SObject__c);
        System.assertEquals('client', link.Veleiro_Entity__c);
        System.assertEquals(1, link.Veleiro_Version__c);
    }

    @isTest
    static void secondSyncUpdatesInsteadOfCreating() {
        mapField('Contact', 'client', 'LastName', 'name', 'Standard');
        Contact c = new Contact(LastName = 'Acme');
        insert c;
        // Como si ya se hubiera sincronizado antes.
        insert new Veleiro_Link__c(
            Link_Key__c = String.valueOf(c.Id).left(15) + '|client',
            Record_Id__c = c.Id, SObject__c = 'Contact', Veleiro_Entity__c = 'client',
            Veleiro_Id__c = 'org_test', Veleiro_Version__c = 1
        );
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSyncService.RecordResult again = VeleiroSyncService.syncRecord(c.Id, 'client');
        Test.stopTest();

        System.assertEquals(false, again.created, 'ya estaba vinculado -> update');
        System.assertNotEquals(null, mock.lastPatchBody);
        System.assertEquals(null, mock.lastPostBody, 'no crea otro client');
        System.assertEquals(1, [SELECT COUNT() FROM Veleiro_Link__c], 'un solo vinculo por registro y entidad');
    }

    @isTest
    static void projectTakesTheClientFromItsAccount() {
        mapField('Case', 'project', 'Subject', 'name', 'Standard');
        Account a = new Account(Name = 'Acme', Veleiro_Client_Id__c = 'org_from_account');
        insert a;
        Case k = new Case(Subject = 'Implementacion', AccountId = a.Id);
        insert k;
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSyncService.RecordResult r = VeleiroSyncService.syncRecord(k.Id, 'project');
        Test.stopTest();

        System.assertEquals('prjct_test', r.veleiroId);
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPostBody);
        System.assertEquals('org_from_account', sent.get('client_id'), 'el project cuelga del client del Account');
        System.assertEquals('Implementacion', sent.get('name'));
    }

    @isTest
    static void projectCreatesTheClientWhenTheAccountIsNotSyncedYet() {
        mapField('Case', 'project', 'Subject', 'name', 'Standard');
        Account a = new Account(Name = 'Sin client', Website = 'https://acme.com');
        insert a;
        Case k = new Case(Subject = 'Arranque', AccountId = a.Id);
        insert k;
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncService.syncRecord(k.Id, 'project');
        Test.stopTest();

        System.assertEquals('org_test', [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id].Veleiro_Client_Id__c,
            'se creo el client y quedo guardado en el Account');
    }

    @isTest
    static void projectWithoutAClientIsRefused() {
        mapField('Contact', 'project', 'LastName', 'name', 'Standard');
        Contact c = new Contact(LastName = 'Suelto'); // sin Account
        insert c;
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        String msg;
        Test.startTest();
        try { VeleiroSyncService.syncRecord(c.Id, 'project'); }
        catch (Exception e) { msg = e.getMessage(); }
        Test.stopTest();

        System.assert(msg != null && msg.contains('client_id'), 'dice como resolverlo: ' + msg);
    }

    @isTest
    static void withoutMappingsItRefusesInsteadOfGuessing() {
        Contact c = new Contact(LastName = 'Sin mapeo');
        insert c;
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        String msg;
        Test.startTest();
        try { VeleiroSyncService.syncRecord(c.Id, 'client'); }
        catch (Exception e) { msg = e.getMessage(); }
        Test.stopTest();

        System.assert(msg != null && msg.contains('Veleiro Mappings'), 'manda a configurar el mapeo: ' + msg);
        System.assertEquals(0, [SELECT COUNT() FROM Veleiro_Link__c]);
    }

    @isTest
    static void nativePairsKeepTheirOwnFields() {
        Account a = new Account(Name = 'Acme');
        insert a;
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncService.RecordResult r = VeleiroSyncService.syncRecord(a.Id, 'client');
        Test.stopTest();

        System.assertEquals('org_test', [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id].Veleiro_Client_Id__c);
        System.assertEquals(0, [SELECT COUNT() FROM Veleiro_Link__c], 'Account no usa el objeto de vinculos');
        System.assertEquals('client', r.entity);
    }

    @isTest
    static void invocableSyncsWhateverTheFlowSends() {
        mapField('Contact', 'client', 'LastName', 'name', 'Standard');
        Contact c = new Contact(LastName = 'Desde flow');
        insert c;
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        VeleiroSyncRecordAction.Request req = new VeleiroSyncRecordAction.Request();
        req.recordId = c.Id;
        req.entity = 'client';

        Test.startTest();
        VeleiroSyncRecordAction.syncRecords(new List<VeleiroSyncRecordAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Veleiro_Link__c]);
    }

    @isTest
    static void unknownEntityIsRefused() {
        Contact c = new Contact(LastName = 'X');
        insert c;
        Boolean threw = false;
        try { VeleiroSyncService.syncRecord(c.Id, 'invoice'); } catch (Exception e) { threw = true; }
        System.assertEquals(true, threw);
    }
}
