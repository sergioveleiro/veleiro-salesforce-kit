@isTest
private class VeleiroSyncServiceTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    private static Account newAccount(String clientId) {
        Account a = new Account(Name = 'Acme', Website = 'https://acme.com');
        if (String.isNotBlank(clientId)) {
            a.Veleiro_Client_Id__c = clientId;
            a.Veleiro_Version__c = 1;
        }
        insert a;
        return a;
    }

    private static Opportunity newOpp(Id accountId, String projectId) {
        Opportunity o = new Opportunity(
            Name = 'Acme - Implementation',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 50000,
            AccountId = accountId
        );
        if (String.isNotBlank(projectId)) {
            o.Veleiro_Project_Id__c = projectId;
            o.Veleiro_Project_Version__c = 1;
        }
        insert o;
        return o;
    }

    @isTest
    static void syncAccountCreatesClient() {
        Account a = newAccount(null);
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncService.ClientResult r = VeleiroSyncService.syncAccount(a.Id);
        Test.stopTest();

        System.assertEquals(true, r.created);
        System.assertEquals('org_test', r.clientId);
        System.assert(r.veleiroUrl.contains('/organizations/'), 'link al portal');
        Account after = [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('org_test', after.Veleiro_Client_Id__c);
    }

    @isTest
    static void syncAccountUpdatesExistingClient() {
        Account a = newAccount('org_test');
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncService.ClientResult r = VeleiroSyncService.syncAccount(a.Id);
        Test.stopTest();

        System.assertEquals(false, r.created, 'ya existia -> update');
        System.assertEquals(true, r.synced);
    }

    @isTest
    static void patchRetriesOnVersionConflict() {
        Account a = newAccount('org_test');
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.failOnceWith409 = true; // primer PATCH 409, reintenta con current_version
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSyncService.ClientResult r = VeleiroSyncService.syncAccount(a.Id);
        Test.stopTest();

        System.assertEquals(true, r.synced, 'sobrevive al 409 con retry');
    }

    @isTest
    static void getClientSummaryReadsState() {
        Account a = newAccount('org_test');
        Test.startTest();
        VeleiroSyncService.ClientResult r = VeleiroSyncService.getClientSummary(a.Id);
        Test.stopTest();
        System.assertEquals(true, r.synced);
        System.assertEquals('org_test', r.clientId);
    }

    @isTest
    static void syncOpportunityCreatesProjectForSyncedAccount() {
        Account a = newAccount('org_test');
        Opportunity o = newOpp(a.Id, null);
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncService.ProjectResult r = VeleiroSyncService.syncOpportunity(o.Id);
        Test.stopTest();

        System.assertEquals(true, r.created);
        System.assertEquals('prjct_test', r.projectId);
        Opportunity after = [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('prjct_test', after.Veleiro_Project_Id__c);
    }

    @isTest
    static void syncOpportunityCreatesClientWhenAccountUnsynced() {
        Account a = newAccount(null); // sin client -> lo crea primero
        Opportunity o = newOpp(a.Id, null);
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncService.ProjectResult r = VeleiroSyncService.syncOpportunity(o.Id);
        Test.stopTest();

        System.assertEquals(true, r.created);
        Account after = [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('org_test', after.Veleiro_Client_Id__c, 'creo el client on the fly');
    }

    @isTest
    static void getProjectSummaryAndLive() {
        Account a = newAccount('org_test');
        Opportunity o = newOpp(a.Id, 'prjct_test');
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncService.ProjectResult summary = VeleiroSyncService.getProjectSummary(o.Id);
        VeleiroSyncService.ProjectResult live = VeleiroSyncService.getProjectLive(o.Id);
        Test.stopTest();

        System.assertEquals(true, summary.synced);
        System.assertEquals('planning', live.status, 'trae el status en vivo');
    }

    private static Veleiro_Field_Mapping__c mapping(String obj, String entity, String sfField, String target, String type) {
        return new Veleiro_Field_Mapping__c(
            Name = (obj + ' ' + sfField).left(80),
            SObject__c = obj, Veleiro_Entity__c = entity,
            SF_Field__c = sfField, Veleiro_Target__c = target,
            Target_Type__c = type, Is_Standard__c = false, Active__c = true
        );
    }

    @isTest
    static void pushHonorsConfiguredMappingOnly() {
        // El partner mapea SOLO Name -> name. No mapea Website.
        insert mapping('Account', 'client', 'Name', 'name', 'Standard');
        Account a = newAccount(null); // tiene Website, pero NO esta mapeado
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSyncService.syncAccount(a.Id);
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPostBody);
        Map<String, Object> af = (Map<String, Object>) body.get('additional_fields');
        System.assertEquals('Acme', body.get('name'), 'name mapeado va top-level');
        System.assertEquals(a.Id, af.get('sf_account_id'), 'la llave de sistema siempre va');
        System.assert(!af.containsKey('sf_website'), 'Website NO fue mapeado -> no se empuja');
    }

    @isTest
    static void pushSendsMappedAdditionalField() {
        // El partner mapea un campo custom a un additional field arbitrario.
        insert mapping('Account', 'client', 'Website', 'homepage', 'Additional Field');
        Account a = newAccount(null);
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSyncService.syncAccount(a.Id);
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPostBody);
        Map<String, Object> af = (Map<String, Object>) body.get('additional_fields');
        System.assertEquals('https://acme.com', af.get('homepage'), 'el target configurado recibe el valor del campo mapeado');
    }

    @isTest
    static void pushFallsBackToDefaultsWhenNoMappings() {
        // Sin mapeos configurados -> usa el template default (Name, sf_account_id, sf_website).
        Account a = newAccount(null);
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSyncService.syncAccount(a.Id);
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPostBody);
        Map<String, Object> af = (Map<String, Object>) body.get('additional_fields');
        System.assertEquals('Acme', body.get('name'));
        System.assertEquals('https://acme.com', af.get('sf_website'), 'el default incluye Website');
    }

    @isTest
    static void invocableCreatesProject() {
        Account a = newAccount('org_test');
        Opportunity o = newOpp(a.Id, null);
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncService.syncOpportunitiesInvocable(new List<Id>{ o.Id });
        Test.stopTest();

        Opportunity after = [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('prjct_test', after.Veleiro_Project_Id__c);
    }

    @isTest
    static void invocableCreatesClient() {
        Account a = newAccount(null);
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncAccountAction.syncAccounts(new List<Id>{ a.Id });
        Test.stopTest();

        Account after = [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('org_test', after.Veleiro_Client_Id__c);
    }
}
