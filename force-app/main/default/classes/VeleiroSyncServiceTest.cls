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
}
