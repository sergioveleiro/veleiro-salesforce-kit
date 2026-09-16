@isTest
private class VeleiroOppSyncQueueableTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    // Los registros se crean en modo manual (los flows de auto-sync no corren) y luego se
    // enciende 'auto' para simular la conversion de Lead.
    private static Opportunity newOpp(String clientId) {
        Account a = new Account(Name = 'Lead Co', Veleiro_Client_Id__c = clientId);
        insert a;
        Opportunity o = new Opportunity(
            Name = 'Lead Co - Deal', StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30), AccountId = a.Id
        );
        insert o;
        return o;
    }

    private static void setTrigger(String mode) {
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        c.Sync_Trigger__c = mode;
        update c;
    }

    @isTest
    static void freshUnsyncedAccountWaits() {
        Opportunity o = newOpp(null);
        setTrigger('auto');
        System.assertEquals(new Set<Id>{ o.Id },
            VeleiroOppSyncQueueable.waitingForAccountSync(new List<Id>{ o.Id }));
    }

    @isTest
    static void manualModeNeverWaits() {
        Opportunity o = newOpp(null);
        setTrigger('manual');
        System.assert(VeleiroOppSyncQueueable.waitingForAccountSync(new List<Id>{ o.Id }).isEmpty());
    }

    @isTest
    static void syncedAccountNeverWaits() {
        Opportunity o = newOpp('org_existing');
        setTrigger('auto');
        System.assert(VeleiroOppSyncQueueable.waitingForAccountSync(new List<Id>{ o.Id }).isEmpty());
    }

    @isTest
    static void invocableDefersThenSyncs() {
        Opportunity o = newOpp(null);
        setTrigger('auto');
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroSyncService.syncOpportunitiesInvocable(new List<Id>{ o.Id });
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'VeleiroOppSyncQueueable'
        ], 'la Opportunity se difiere en vez de crear el client en paralelo');
        Opportunity after = [SELECT Veleiro_Project_Id__c, Account.Veleiro_Client_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('prjct_test', after.Veleiro_Project_Id__c, 'en el ultimo intento sincroniza igual');
        System.assertEquals('org_test', after.Account.Veleiro_Client_Id__c);
    }

    @isTest
    static void usesClientCreatedByAccountSync() {
        // El auto-sync del Account ya termino cuando corre el Queueable: no se crea otro client.
        Opportunity o = newOpp('org_from_account');
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new VeleiroOppSyncQueueable(new List<Id>{ o.Id }, 1).execute(null);
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPostBody);
        System.assertEquals('org_from_account', body.get('client_id'), 'el unico POST es el project, con el client existente');
        Opportunity after = [SELECT Veleiro_Project_Id__c, Account.Veleiro_Client_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('prjct_test', after.Veleiro_Project_Id__c);
        System.assertEquals('org_from_account', after.Account.Veleiro_Client_Id__c);
    }
}
