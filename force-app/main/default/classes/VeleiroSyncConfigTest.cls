@isTest
private class VeleiroSyncConfigTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    @isTest
    static void defaultsWhenUnconfigured() {
        Test.startTest();
        System.assertEquals('bidirectional', VeleiroSyncConfig.direction());
        System.assertEquals('salesforce', VeleiroSyncConfig.winner());
        System.assertEquals('off', VeleiroSyncConfig.frequency());
        System.assertEquals(true, VeleiroSyncConfig.pushEnabled());
        System.assertEquals(true, VeleiroSyncConfig.pullEnabled());
        System.assertEquals(true, VeleiroSyncConfig.salesforceWins());
        Test.stopTest();
    }

    @isTest
    static void saveReadAndSchedule() {
        // el job agendado corre en stopTest -> necesita mock para su callout
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());
        Test.startTest();
        VeleiroSyncConfig.save('veleiro_to_sf', 'veleiro', 'hourly', 'manual');
        Map<String, String> c = VeleiroMappingController.getSyncConfig();
        Test.stopTest();

        System.assertEquals('veleiro_to_sf', c.get('direction'));
        System.assertEquals('veleiro', c.get('winner'));
        System.assertEquals('hourly', c.get('frequency'));
        System.assertEquals(false, VeleiroSyncConfig.pushEnabled(), 'veleiro_to_sf -> no push');
        System.assertEquals(true, VeleiroSyncConfig.pullEnabled());
        System.assertEquals(false, VeleiroSyncConfig.salesforceWins());
        // el job quedo agendado
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :VeleiroSyncConfig.JOB_NAME]);
    }

    @isTest
    static void scheduleOffAbortsJob() {
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());
        Test.startTest();
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'daily', 'manual');
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :VeleiroSyncConfig.JOB_NAME]);
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'manual');
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :VeleiroSyncConfig.JOB_NAME], 'off aborta el job');
    }

    @isTest
    static void normalizesGarbageInput() {
        VeleiroSyncConfig.save('nonsense', 'nonsense', 'nonsense', 'manual');
        System.assertEquals('bidirectional', VeleiroSyncConfig.direction());
        System.assertEquals('salesforce', VeleiroSyncConfig.winner());
        System.assertEquals('off', VeleiroSyncConfig.frequency());
    }

    @isTest
    static void pullUpdatesAppliesNewerVersion() {
        Account a = new Account(Name = 'Old', Veleiro_Client_Id__c = 'org_x', Veleiro_Version__c = 1);
        insert a;
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[{"id":"org_x","name":"New Name","version":5,"additional_fields":{"seats":9}}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Integer n = VeleiroSync.pullUpdates();
        Test.stopTest();

        System.assertEquals(1, n, 'version 5 > 1 -> actualiza');
        Account after = [SELECT Name, Veleiro_Version__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('New Name', after.Name);
        System.assertEquals(5, after.Veleiro_Version__c);
    }

    @isTest
    static void pullSkipsWhenNotNewer_cyclePrevention() {
        Account a = new Account(Name = 'Same', Veleiro_Client_Id__c = 'org_x', Veleiro_Version__c = 5);
        insert a;
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[{"id":"org_x","name":"Should Not Apply","version":5}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Integer n = VeleiroSync.pullUpdates();
        Test.stopTest();

        System.assertEquals(0, n, 'misma version -> no re-aplica (anti-ciclo)');
        System.assertEquals('Same', [SELECT Name FROM Account WHERE Id = :a.Id].Name);
    }

    @isTest
    static void pullDisabledWhenDirectionSfOnly() {
        VeleiroSyncConfig.save('sf_to_veleiro', 'salesforce', 'off', 'manual');
        insert new Account(Name = 'X', Veleiro_Client_Id__c = 'org_x', Veleiro_Version__c = 1);
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());
        Test.startTest();
        Integer n = VeleiroSync.pullUpdates();
        Test.stopTest();
        System.assertEquals(0, n, 'sf_to_veleiro -> no jala de Veleiro');
    }

    @isTest
    static void pushBlockedWhenDirectionVeleiroOnly() {
        VeleiroSyncConfig.save('veleiro_to_sf', 'salesforce', 'off', 'manual');
        Account a = new Account(Name = 'Acme');
        insert a;
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());
        Test.startTest();
        try {
            VeleiroSyncService.syncAccount(a.Id);
            System.assert(false, 'debio bloquear el push');
        } catch (VeleiroApiClient.VeleiroApiException e) {
            System.assert(e.getMessage().contains('disabled'), 'mensaje de push deshabilitado');
        }
        Test.stopTest();
    }

    @isTest
    static void scheduledJobRuns() {
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());
        Test.startTest();
        new VeleiroPullJob().execute(null);
        Test.stopTest();
        // sin error = ok (no hay accounts, devuelve 0)
        System.assert(true);
    }

    @isTest
    static void syncTriggerAndAutoOnCreate() {
        System.assertEquals('manual', VeleiroSyncConfig.syncTrigger(), 'default es manual');

        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto');
        System.assertEquals('auto', VeleiroSyncConfig.syncTrigger());
        System.assertEquals(true, VeleiroSyncConfig.autoSyncOnCreate(), 'auto + push habilitado -> true');

        VeleiroSyncConfig.save('veleiro_to_sf', 'salesforce', 'off', 'auto');
        System.assertEquals(false, VeleiroSyncConfig.autoSyncOnCreate(), 'auto pero push deshabilitado -> false');

        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'manual');
        System.assertEquals(false, VeleiroSyncConfig.autoSyncOnCreate(), 'manual -> false');
    }
}
