@isTest
private class VeleiroSyncTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    @isTest
    static void syncClientsUpsertsAccounts() {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[' +
            '{"id":"org_a","name":"Alpha","slug":"alpha","version":2,"additional_fields":{"seats":10}},' +
            '{"id":"org_b","name":"Bravo","slug":"bravo","version":1}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Integer n = VeleiroSync.syncClients();
        Test.stopTest();

        System.assertEquals(2, n);
        Map<String, Account> byClient = new Map<String, Account>();
        for (Account a : [SELECT Name, Veleiro_Client_Id__c, Veleiro_Slug__c, Veleiro_Version__c,
                                 Veleiro_Additional_Fields__c FROM Account WHERE Veleiro_Client_Id__c != null]) {
            byClient.put(a.Veleiro_Client_Id__c, a);
        }
        System.assertEquals(2, byClient.size());
        System.assertEquals('Alpha', byClient.get('org_a').Name);
        System.assertEquals(2, byClient.get('org_a').Veleiro_Version__c);
        System.assert(byClient.get('org_a').Veleiro_Additional_Fields__c != null, 'guarda additional_fields');
    }

    @isTest
    static void syncClientsIsIdempotentByExternalId() {
        // Account preexistente con el mismo external id -> upsert lo actualiza, no duplica.
        insert new Account(Name = 'Old', Veleiro_Client_Id__c = 'org_a');
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[{"id":"org_a","name":"Alpha New","version":3}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSync.syncClients();
        Test.stopTest();

        List<Account> accts = [SELECT Name FROM Account WHERE Veleiro_Client_Id__c = 'org_a'];
        System.assertEquals(1, accts.size(), 'no duplica por external id');
        System.assertEquals('Alpha New', accts[0].Name);
    }
}
