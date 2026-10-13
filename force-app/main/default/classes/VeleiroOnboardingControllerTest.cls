@isTest
private class VeleiroOnboardingControllerTest {

    private static VeleiroOnboardingController.Step step(VeleiroOnboardingController.State s, String key) {
        for (VeleiroOnboardingController.Step st : s.steps) {
            if (st.key == key) return st;
        }
        return null;
    }

    // Org recien instalada: nada configurado, nada cumplido, y el aviso dice "0 de N".
    @isTest
    static void freshOrgHasNothingDone() {
        Test.startTest();
        VeleiroOnboardingController.State s = VeleiroOnboardingController.getState(false);
        Test.stopTest();

        System.assertEquals(0, s.done, 'sin token ni config no hay nada cumplido');
        System.assertEquals(false, s.complete);
        System.assertEquals(false, s.connected, 'sin token no hay conexion');
        System.assertEquals(VeleiroOnboardingController.TODO, step(s, 'connection').state);
        System.assertEquals(VeleiroOnboardingController.TODO, step(s, 'config').state);
        System.assertEquals(VeleiroOnboardingController.TODO, step(s, 'mapping').state);
        System.assertEquals(0, s.mappingCount);
    }

    // El token solo se da por bueno si un GET real responde.
    @isTest
    static void connectionNeedsALiveCallout() {
        VeleiroApiMock.seedConfig();
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 401;
        mock.overrideBody = '{"error":{"code":"invalid_token"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroOnboardingController.State bad = VeleiroOnboardingController.getState(true);
        Test.stopTest();

        System.assertEquals(false, bad.connected, 'un token invalido no cuenta como conectado');
        System.assertEquals(VeleiroOnboardingController.TODO, step(bad, 'connection').state);
        System.assert(String.isNotBlank(step(bad, 'connection').evidence), 'y dice por que');
    }

    @isTest
    static void connectionPassesWithAWorkingToken() {
        VeleiroApiMock.seedConfig();
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroOnboardingController.State s = VeleiroOnboardingController.getState(true);
        Test.stopTest();

        System.assertEquals(true, s.connected);
        System.assertEquals(VeleiroOnboardingController.DONE, step(s, 'connection').state);
    }

    // Sin callout (el aviso del Home) basta con que el token exista: no inventa una conexion viva.
    @isTest
    static void withoutPingTheTokenIsEnough() {
        VeleiroApiMock.seedConfig();
        Test.startTest();
        VeleiroOnboardingController.State s = VeleiroOnboardingController.getState(false);
        Test.stopTest();
        System.assertEquals(true, s.connected);
        System.assertEquals(0, Limits.getCallouts(), 'el aviso del Home no debe gastar un callout');
    }

    // Sync_Trigger__c nace en blanco: se llena solo cuando alguien guarda la configuracion.
    @isTest
    static void configCountsOnlyAfterAnExplicitSave() {
        VeleiroApiMock.seedConfig();
        System.assertEquals(VeleiroOnboardingController.TODO,
            step(VeleiroOnboardingController.getState(false), 'config').state,
            'el token por si solo no configura la integracion');

        Test.startTest();
        VeleiroSyncConfig.save('sf_to_veleiro', 'salesforce', 'off', 'manual');
        Test.stopTest();

        VeleiroOnboardingController.State s = VeleiroOnboardingController.getState(false);
        System.assertEquals(VeleiroOnboardingController.DONE, step(s, 'config').state);
        System.assert(step(s, 'config').evidence.contains('manual'), 'resume lo elegido: ' + step(s, 'config').evidence);
    }

    @isTest
    static void oneActiveMappingCompletesTheMappingStep() {
        VeleiroApiMock.seedConfig();
        insert new Veleiro_Field_Mapping__c(
            SObject__c = 'Account', Veleiro_Entity__c = 'client',
            SF_Field__c = 'Name', Veleiro_Target__c = 'name',
            Target_Type__c = 'Standard', Active__c = true
        );

        VeleiroOnboardingController.State s = VeleiroOnboardingController.getState(false);
        System.assertEquals(VeleiroOnboardingController.DONE, step(s, 'mapping').state);
        System.assertEquals(1, s.mappingCount);
        System.assert(step(s, 'mapping').actionTab.endsWith('Veleiro_Mappings'), 'lleva a la pestana de mapeo');
    }

    // Vincular escribe el id y deja la version en null; sincronizar trae la version de la API.
    // Es la unica forma de distinguir los dos pasos sin agregar campos.
    @isTest
    static void linkAndSyncAreToldApartByTheVersion() {
        VeleiroApiMock.seedConfig();
        Account linked = new Account(Name = 'Solo vinculada', Veleiro_Client_Id__c = 'org_linked');
        insert linked;

        VeleiroOnboardingController.State afterLink = VeleiroOnboardingController.getState(false);
        System.assertEquals(1, afterLink.linkedCount);
        System.assertEquals(0, afterLink.syncedCount, 'vincular no es sincronizar');
        System.assertEquals(VeleiroOnboardingController.DONE, step(afterLink, 'link').state);
        System.assertEquals(VeleiroOnboardingController.TODO, step(afterLink, 'sync').state);

        linked.Veleiro_Version__c = 3;   // lo que deja un sync real
        update linked;

        VeleiroOnboardingController.State afterSync = VeleiroOnboardingController.getState(false);
        System.assertEquals(1, afterSync.syncedCount);
        System.assertEquals(VeleiroOnboardingController.DONE, step(afterSync, 'sync').state);
        System.assertEquals('Account', step(afterSync, 'sync').actionObject);
    }

    // Cualquier objeto mapeado cuenta: el vinculo generico vive en Veleiro_Link__c.
    @isTest
    static void aGenericLinkAlsoCounts() {
        VeleiroApiMock.seedConfig();
        Account a = new Account(Name = 'Cualquiera');
        insert a;
        insert new Veleiro_Link__c(
            Link_Key__c = a.Id + '|client', Record_Id__c = a.Id,
            SObject__c = 'Account', Veleiro_Entity__c = 'client',
            Veleiro_Id__c = 'org_generic', Veleiro_Version__c = 2
        );

        VeleiroOnboardingController.State s = VeleiroOnboardingController.getState(false);
        System.assertEquals(1, s.linkedCount);
        System.assertEquals(1, s.syncedCount);
    }

    // Los pasos opcionales se pueden marcar como "no aplica" y volver atras.
    @isTest
    static void optionalStepsCanBeSkippedAndRestored() {
        VeleiroApiMock.seedConfig();
        System.assertEquals(VeleiroOnboardingController.TODO,
            step(VeleiroOnboardingController.getState(false), 'link').state);

        Test.startTest();
        VeleiroOnboardingController.skipStep('link', true);
        Test.stopTest();

        System.assertEquals(VeleiroOnboardingController.SKIPPED,
            step(VeleiroOnboardingController.getState(false), 'link').state);

        VeleiroOnboardingController.skipStep('link', false);
        System.assertEquals(VeleiroOnboardingController.TODO,
            step(VeleiroOnboardingController.getState(false), 'link').state);

        VeleiroOnboardingController.skipStep(null, true);   // no truena ni guarda basura
        System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Onboarding_Skipped__c);
    }

    // Un paso saltado no puede bloquear el 100%, y uno opcional tampoco cuenta para el total.
    @isTest
    static void optionalStepsDoNotBlockCompletion() {
        VeleiroApiMock.seedConfig();
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'manual');
        insert new Veleiro_Field_Mapping__c(
            SObject__c = 'Account', Veleiro_Entity__c = 'client',
            SF_Field__c = 'Name', Veleiro_Target__c = 'name',
            Target_Type__c = 'Standard', Active__c = true
        );
        insert new Account(Name = 'Sincronizada', Veleiro_Client_Id__c = 'org_done', Veleiro_Version__c = 1);
        VeleiroOnboardingController.assignedToMe = 1;      // con acceso propio, el paso es opcional
        VeleiroOnboardingController.assignedToOthers = 0;

        Test.startTest();
        VeleiroOnboardingController.State s = VeleiroOnboardingController.getState(true);
        Test.stopTest();

        System.assertEquals(4, s.total, 'conexion, config, mapeo y sync son los obligatorios');
        System.assertEquals(4, s.done);
        System.assertEquals(true, s.complete, 'los opcionales no cuentan para el total');
    }

    // Los flows solo son un paso cuando el trigger es automatico: en manual no hacen falta.
    @isTest
    static void flowsOnlyMatterOnAutomatic() {
        VeleiroApiMock.seedConfig();
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'manual');
        System.assertEquals(null, step(VeleiroOnboardingController.getState(false), 'flows'),
            'en manual no se pide activar flows');

        Test.startTest();
        VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto');
        Test.stopTest();

        VeleiroOnboardingController.Step flows = step(VeleiroOnboardingController.getState(false), 'flows');
        System.assertNotEquals(null, flows, 'en automatico si');
        System.assert(String.isNotBlank(flows.evidence), 'y dice como esta: ' + flows.evidence);
    }

    // Las asignaciones reales de la org donde corren los tests no deben decidir el resultado.
    private static VeleiroOnboardingController.Step teamStep(Integer mine, Integer others) {
        VeleiroI18n.languageOverride = 'es';   // el idioma del usuario no decide si el test pasa
        VeleiroOnboardingController.assignedToMe = mine;
        VeleiroOnboardingController.assignedToOthers = others;
        return step(VeleiroOnboardingController.getState(false), 'team');
    }

    /**
     * Sin el permission set no se ven los campos de Veleiro ni los paneles: el kit se ve roto.
     * Si le falta a quien esta configurando, el paso NO es opcional.
     */
    @isTest
    static void accessIsRequiredWhenTheAdminIsMissingItToo() {
        VeleiroApiMock.seedConfig();
        VeleiroOnboardingController.Step team = teamStep(0, 0);
        System.assertEquals(VeleiroOnboardingController.TODO, team.state);
        System.assertEquals(false, team.optional, 'nada del kit funciona sin esto');
        System.assert(team.evidence.contains('Ni tú'), team.evidence);
        System.assertEquals('Asignar el permission set', team.actionLabel);
    }

    // Con acceso propio pero sin equipo, es un consejo: funciona, y se puede saltar.
    @isTest
    static void accessIsAdviceOnceTheAdminHasIt() {
        VeleiroApiMock.seedConfig();
        VeleiroOnboardingController.Step team = teamStep(1, 0);
        System.assertEquals(VeleiroOnboardingController.TODO, team.state);
        System.assertEquals(true, team.optional);
        System.assert(team.evidence.contains('Solo tú'), team.evidence);

        VeleiroOnboardingController.skipStep('team', true);
        System.assertEquals(VeleiroOnboardingController.SKIPPED, teamStep(1, 0).state);
    }

    @isTest
    static void accessIsDoneWhenSomeoneElseHasItToo() {
        VeleiroApiMock.seedConfig();
        VeleiroOnboardingController.Step team = teamStep(1, 2);
        System.assertEquals(VeleiroOnboardingController.DONE, team.state);
        System.assert(team.evidence.contains('2'), team.evidence);
        System.assertEquals(null, team.actionLabel, 'ya no hay nada que hacer');
    }

    // Sin namespace no hay prefijo; dentro del paquete administrado, las pestanas lo llevan.
    @isTest
    static void tabNamesCarryTheNamespaceWhenThereIsOne() {
        String expected = String.valueOf(Veleiro_Field_Mapping__c.SObjectType).split('__').size() >= 3
            ? 'veleiro__Veleiro_Mappings' : 'Veleiro_Mappings';
        VeleiroApiMock.seedConfig();
        System.assertEquals(expected, step(VeleiroOnboardingController.getState(false), 'mapping').actionTab);
    }
}
