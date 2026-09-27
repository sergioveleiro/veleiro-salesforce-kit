@isTest
private class VeleiroAutoSyncGuardTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    private static List<Id> fakeIds(Integer howMany) {
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < howMany; i++) {
            ids.add(Id.valueOf('00100000000' + String.valueOf(1000 + i) + 'AAA')); // 18 chars
        }
        return ids;
    }

    @isTest
    static void normalBatchesGoThrough() {
        System.assertEquals(false, VeleiroAutoSyncGuard.tooManyForAutoSync(fakeIds(10), 'accounts'));
        System.assertEquals(false, VeleiroAutoSyncGuard.tooManyForAutoSync(null, 'accounts'));
        System.assertEquals(null, VeleiroSyncConfig.lastError(), 'nada que reportar');
    }

    @isTest
    static void bulkLoadsAreSkippedAndLeftOnRecord() {
        VeleiroAutoSyncGuard.maxAutoBatch = 5;

        Test.startTest();
        Boolean skipped = VeleiroAutoSyncGuard.tooManyForAutoSync(fakeIds(20), 'accounts');
        Test.stopTest();

        System.assertEquals(true, skipped, 'una carga masiva no dispara miles de callouts');
        String err = VeleiroSyncConfig.lastError();
        System.assert(err != null && err.contains('20'), 'queda anotado cuantos se saltaron: ' + err);
        System.assertNotEquals(null, VeleiroSyncConfig.lastErrorAt());
    }

    @isTest
    static void failuresAreVisibleInsteadOfSilent() {
        Account a = new Account(Name = 'Acme');
        insert a;

        Test.startTest();
        VeleiroAutoSyncGuard.recordFailure(a.Id, new VeleiroApiClient.VeleiroApiException('invalid_token: el token vencio'));
        Test.stopTest();

        String err = VeleiroSyncConfig.lastError();
        System.assert(err.contains('invalid_token'), 'el panel puede mostrarlo: ' + err);
    }

    @isTest
    static void longMessagesAreTrimmedToFitTheField() {
        Test.startTest();
        VeleiroSyncConfig.recordError('x'.repeat(400));
        Test.stopTest();
        System.assertEquals(255, VeleiroSyncConfig.lastError().length());
    }

    @isTest
    static void autoSyncSkipsBulkLoadsEndToEnd() {
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true);
        VeleiroAutoSyncGuard.maxAutoBatch = 2;
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Uno'), new Account(Name = 'Dos'), new Account(Name = 'Tres')
        };
        insert accounts;
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSyncAccountAction.syncAccounts(new List<Id>(new Map<Id, Account>(accounts).keySet()));
        Test.stopTest();

        System.assertEquals(null, mock.lastPostBody, 'no se llamo a Veleiro por la carga masiva');
    }

    @isTest
    static void oneBadRecordDoesNotStopTheRestAndLeavesTheError() {
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true);
        Account a = new Account(Name = 'Acme');
        insert a;
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 401;
        mock.overrideBody = '{"error":{"code":"invalid_token","message":"token invalido"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroSyncAccountAction.syncAccounts(new List<Id>{ a.Id }); // no relanza
        Test.stopTest();

        String err = VeleiroSyncConfig.lastError();
        System.assert(err != null && err.contains('invalid_token'), 'el fallo queda visible: ' + err);
        System.assertEquals(null, [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id].Veleiro_Client_Id__c);
    }
}
