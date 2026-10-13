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
        // El nombre solo se pisa si el cliente lo autoriza; aqui se prueba con permiso.
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'manual', true, true, true);
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

    @isTest
    static void eachPairCanBeAutomaticOnItsOwn() {
        // Account automatico, Opportunity manual: el caso que piden los partners.
        Test.startTest();
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, false);
        Test.stopTest();

        System.assertEquals(true, VeleiroSyncConfig.autoSyncAccount());
        System.assertEquals(false, VeleiroSyncConfig.autoSyncOpportunity());
        System.assertEquals(true, VeleiroSyncConfig.autoSyncAccountFlag());
        System.assertEquals(false, VeleiroSyncConfig.autoSyncOpportunityFlag());
    }

    @isTest
    static void manualTriggerTurnsOffBothPairs() {
        Test.startTest();
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'manual', true, true);
        Test.stopTest();

        System.assertEquals(false, VeleiroSyncConfig.autoSyncAccount(), 'el trigger global manda');
        System.assertEquals(false, VeleiroSyncConfig.autoSyncOpportunity());
        System.assertEquals(true, VeleiroSyncConfig.autoSyncAccountFlag(), 'pero el interruptor conserva su valor');
    }

    @isTest
    static void pairsDefaultToAutomaticWhenNothingIsSavedYet() {
        System.assertEquals(true, VeleiroSyncConfig.autoSyncAccountFlag());
        System.assertEquals(true, VeleiroSyncConfig.autoSyncOpportunityFlag());
    }

    /**
     * Una org que ya estaba configurada con el checkbox no tiene que reconfigurarse: el campo
     * nuevo nace vacio y el modo se deduce del checkbox. El tipo de un campo ya publicado no se
     * puede cambiar, por eso hay dos campos y no uno.
     */
    @isTest
    static void theModeFallsBackToTheOldCheckbox() {
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c == null || c.Id == null) c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        c.Sync_Trigger__c = 'auto';
        c.Sync_Direction__c = 'bidirectional';
        c.Opportunity_Sync_Mode__c = null;          // como queda una org que nunca vio el campo nuevo
        c.Auto_Sync_Opportunity__c = true;          // configurada con la version anterior
        upsert c;
        System.assertEquals(VeleiroSyncConfig.OPP_CREATE, VeleiroSyncConfig.opportunitySyncMode(),
            'checkbox encendido -> sincroniza al crear, como antes');
        System.assertEquals(true, VeleiroSyncConfig.autoSyncOpportunity());

        c.Auto_Sync_Opportunity__c = false;
        update c;
        System.assertEquals(VeleiroSyncConfig.OPP_MANUAL, VeleiroSyncConfig.opportunitySyncMode());
        System.assertEquals(false, VeleiroSyncConfig.autoSyncOpportunity());
    }

    @isTest
    static void theModeWinsOverTheCheckboxOnceItIsSet() {
        Test.startTest();
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true, false,
                               VeleiroSyncConfig.OPP_WON);
        Test.stopTest();

        System.assertEquals(VeleiroSyncConfig.OPP_WON, VeleiroSyncConfig.opportunitySyncMode());
        System.assertEquals(true, VeleiroSyncConfig.autoSyncOpportunity(), 'won sigue siendo automatico');
        // El checkbox queda en sintonia para las orgs que todavia corran la version anterior.
        System.assertEquals(true, VeleiroSyncConfig.autoSyncOpportunityFlag());

        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true, false,
                               VeleiroSyncConfig.OPP_MANUAL);
        System.assertEquals(VeleiroSyncConfig.OPP_MANUAL, VeleiroSyncConfig.opportunitySyncMode());
        System.assertEquals(false, VeleiroSyncConfig.autoSyncOpportunityFlag(), 'manual apaga el checkbox');
    }

    // Account automatico y Opportunity en cualquiera de sus tres momentos: son independientes.
    @isTest
    static void accountStaysAutomaticWhateverTheOpportunityDoes() {
        for (String mode : new List<String>{ VeleiroSyncConfig.OPP_CREATE, VeleiroSyncConfig.OPP_WON,
                                             VeleiroSyncConfig.OPP_MANUAL }) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true, false, mode);
            System.assertEquals(true, VeleiroSyncConfig.autoSyncAccount(), 'Account sigue en automatico con ' + mode);
            System.assertEquals(mode, VeleiroSyncConfig.opportunitySyncMode());
        }
    }
}
