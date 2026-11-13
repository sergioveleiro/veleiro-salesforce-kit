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
        System.runAs(VeleiroTestAccess.user()) {
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
    }

    @isTest
    static void createSendsWebsiteUrlForResearch() {
        System.runAs(VeleiroTestAccess.user()) {
            Account a = newAccount(null); // Website = https://acme.com
            VeleiroApiMock mock = new VeleiroApiMock();
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            VeleiroSyncService.syncAccount(a.Id);
            Test.stopTest();

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPostBody);
            System.assertEquals('https://acme.com', body.get('website_url'), 'website_url dispara el analisis en Veleiro');
        }
    }

    @isTest
    static void updateDoesNotSendWebsiteUrl() {
        System.runAs(VeleiroTestAccess.user()) {
            Account a = newAccount('org_test');
            VeleiroApiMock mock = new VeleiroApiMock();
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            VeleiroSyncService.syncAccount(a.Id);
            Test.stopTest();

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.lastPatchBody);
            System.assert(!body.containsKey('website_url'), 'el PATCH no toca el perfil del client');
        }
    }

    @isTest
    static void researchWebsiteNormalizes() {
        System.runAs(VeleiroTestAccess.user()) {
            System.assertEquals('https://acme.com', VeleiroSyncService.researchWebsite('  acme.com '));
            System.assertEquals('http://acme.com/es?x=1', VeleiroSyncService.researchWebsite('http://acme.com/es?x=1'));
            System.assertEquals('HTTPS://www.acme.co:8443/', VeleiroSyncService.researchWebsite('HTTPS://www.acme.co:8443/'), 'esquema en mayusculas es valido');
            System.assertEquals(null, VeleiroSyncService.researchWebsite(null));
            System.assertEquals(null, VeleiroSyncService.researchWebsite('acme dot com'), 'con espacios Veleiro lo rechaza');
            System.assertEquals(null, VeleiroSyncService.researchWebsite('ftp://acme.com'));
            System.assertEquals(null, VeleiroSyncService.researchWebsite('https://'));
        }
    }

    @isTest
    static void syncAccountUpdatesExistingClient() {
        System.runAs(VeleiroTestAccess.user()) {
            Account a = newAccount('org_test');
            Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

            Test.startTest();
            VeleiroSyncService.ClientResult r = VeleiroSyncService.syncAccount(a.Id);
            Test.stopTest();

            System.assertEquals(false, r.created, 'ya existia -> update');
            System.assertEquals(true, r.synced);
        }
    }

    @isTest
    static void patchRetriesOnVersionConflict() {
        System.runAs(VeleiroTestAccess.user()) {
            Account a = newAccount('org_test');
            VeleiroApiMock mock = new VeleiroApiMock();
            mock.failOnceWith409 = true; // primer PATCH 409, reintenta con current_version
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            VeleiroSyncService.ClientResult r = VeleiroSyncService.syncAccount(a.Id);
            Test.stopTest();

            System.assertEquals(true, r.synced, 'sobrevive al 409 con retry');
        }
    }

    @isTest
    static void getClientSummaryReadsState() {
        System.runAs(VeleiroTestAccess.user()) {
            Account a = newAccount('org_test');
            Test.startTest();
            VeleiroSyncService.ClientResult r = VeleiroSyncService.getClientSummary(a.Id);
            Test.stopTest();
            System.assertEquals(true, r.synced);
            System.assertEquals('org_test', r.clientId);
        }
    }

    @isTest
    static void syncOpportunityCreatesProjectForSyncedAccount() {
        System.runAs(VeleiroTestAccess.user()) {
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
    }

    @isTest
    static void syncOpportunityCreatesClientWhenAccountUnsynced() {
        System.runAs(VeleiroTestAccess.user()) {
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
    }

    @isTest
    static void getProjectSummaryAndLive() {
        System.runAs(VeleiroTestAccess.user()) {
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
        System.runAs(VeleiroTestAccess.user()) {
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
    }

    @isTest
    static void pushSendsMappedAdditionalField() {
        System.runAs(VeleiroTestAccess.user()) {
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
    }

    @isTest
    static void pushFallsBackToDefaultsWhenNoMappings() {
        System.runAs(VeleiroTestAccess.user()) {
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
    }

    @isTest
    static void invocableCreatesProject() {
        System.runAs(VeleiroTestAccess.user()) {
            // El invocable es la ruta automatica: solo actua con el par en Automatic.
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true);
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

    @isTest
    static void invocableCreatesClient() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true);
            Account a = newAccount(null);
            Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

            Test.startTest();
            VeleiroSyncAccountAction.syncAccounts(new List<Id>{ a.Id });
            Test.stopTest();

            Account after = [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id];
            System.assertEquals('org_test', after.Veleiro_Client_Id__c);
        }
    }

    @isTest
    static void opportunityInvocableRespectsItsOwnSwitch() {
        System.runAs(VeleiroTestAccess.user()) {
            // Account automatico, Opportunity manual: el flow corre pero no debe sincronizar.
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, false);
            Account a = newAccount('org_test');
            Opportunity o = newOpp(a.Id, null);
            VeleiroApiMock mock = new VeleiroApiMock();
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            VeleiroSyncService.syncOpportunitiesInvocable(new List<Id>{ o.Id });
            Test.stopTest();

            System.assertEquals(null, mock.lastPostBody, 'Opportunity en manual -> no se crea el project');
            System.assertEquals(null, [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :o.Id].Veleiro_Project_Id__c);
        }
    }

    @isTest
    static void accountInvocableRespectsItsOwnSwitch() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', false, true);
            Account a = newAccount(null);
            VeleiroApiMock mock = new VeleiroApiMock();
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            VeleiroSyncAccountAction.syncAccounts(new List<Id>{ a.Id });
            Test.stopTest();

            System.assertEquals(null, mock.lastPostBody, 'Account en manual -> no se crea el client');
        }
    }

    /**
     * El caso que pide un partner que vende primero y entrega despues: la oportunidad vive su
     * ciclo en Salesforce y el project nace cuando el trato se gana, no al abrirla.
     *
     * Los dos flows de Opportunity llaman al mismo invocable, asi que el filtro tiene que estar
     * aqui: en modo 'won' la creacion pasa de largo y el paso a ganada si sincroniza.
     */
    @isTest
    static void inWonModeTheProjectIsBornWhenTheDealIsWon() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true, false,
                                   VeleiroSyncConfig.OPP_WON);
            Account a = newAccount('org_test');
            Opportunity open = newOpp(a.Id, null);
            VeleiroApiMock mock = new VeleiroApiMock();
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            VeleiroSyncService.syncOpportunitiesInvocable(new List<Id>{ open.Id });
            Test.stopTest();

            System.assertEquals(null, mock.lastPostBody, 'abierta todavia: el project no nace aqui');
            System.assertEquals(null,
                [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :open.Id].Veleiro_Project_Id__c);
        }
    }

    @isTest
    static void inWonModeAWonOpportunityDoesSync() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true, false,
                                   VeleiroSyncConfig.OPP_WON);
            Account a = newAccount('org_test');
            Opportunity won = newOpp(a.Id, null);
            won.StageName = 'Closed Won';
            update won;
            Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

            Test.startTest();
            VeleiroSyncService.syncOpportunitiesInvocable(new List<Id>{ won.Id });
            Test.stopTest();

            System.assertEquals('prjct_test',
                [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :won.Id].Veleiro_Project_Id__c,
                'ganada: aqui si nace el project');
        }
    }

    // Modo 'create': sigue sincronizando al abrir la oportunidad, como siempre.
    @isTest
    static void inCreateModeAnOpenOpportunitySyncs() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true, false,
                                   VeleiroSyncConfig.OPP_CREATE);
            Account a = newAccount('org_test');
            Opportunity open = newOpp(a.Id, null);
            Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

            Test.startTest();
            VeleiroSyncService.syncOpportunitiesInvocable(new List<Id>{ open.Id });
            Test.stopTest();

            System.assertEquals('prjct_test',
                [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :open.Id].Veleiro_Project_Id__c);
        }
    }

    // ---- lotes: todos los callouts primero y UN solo DML ----
    // Antes, syncOpportunity por registro dentro del bucle guardaba entre callouts y el segundo
    // registro del lote tronaba con "uncommitted work pending": de un flow bulkificado solo se
    // sincronizaba el primero.

    @isTest
    static void invocableSyncsEveryOpportunityOfTheBatch() {
        System.runAs(VeleiroTestAccess.user()) {
            // Account en manual: ninguna oportunidad se difiere esperando al auto-sync de su cuenta.
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', false, true);
            Account fresh = newAccount(null);            // sin client: lo crea la primera oportunidad
            Account linked = newAccount('org_existing');
            Opportunity o1 = newOpp(fresh.Id, null);
            Opportunity o2 = newOpp(fresh.Id, null);
            Opportunity o3 = newOpp(linked.Id, null);
            List<Id> ids = new List<Id>{ o1.Id, o2.Id, o3.Id };
            VeleiroApiMock mock = new VeleiroApiMock();
            mock.distinctIds = true;
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            VeleiroSyncService.syncOpportunitiesInvocable(ids);
            Test.stopTest();

            System.assertEquals(3, mock.projectPosts, 'un project por oportunidad, las tres en la misma transaccion');
            System.assertEquals(1, mock.clientPosts, 'las dos oportunidades de la cuenta nueva comparten UN client');
            System.assertEquals(3, [SELECT COUNT() FROM Opportunity WHERE Id IN :ids AND Veleiro_Project_Id__c != null]);
            System.assertEquals('org_test_1', [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :fresh.Id].Veleiro_Client_Id__c);
            System.assertEquals('org_existing', [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :linked.Id].Veleiro_Client_Id__c);
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Last_Sync_Error__c);
        }
    }

    // El client se crea para la primera oportunidad y su project falla; la segunda, de la misma
    // cuenta, reutiliza ese client. El vinculo del Account se guarda igual: el client ya existe
    // en Veleiro y sin el vinculo el siguiente sync lo crearia otra vez.
    private class FirstProjectFailsMock implements HttpCalloutMock {
        Integer projectPosts = 0;
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String url = req.getEndpoint();
            if (req.getMethod() == 'POST' && url.contains('/projects')) {
                projectPosts++;
                if (projectPosts == 1) {
                    res.setStatusCode(500);
                    res.setBody('{"error":{"code":"internal_error","message":"boom"}}');
                } else {
                    res.setStatusCode(201);
                    res.setBody('{"data":{"id":"prjct_' + projectPosts + '","name":"P","progress":0,"version":1}}');
                }
            } else if (req.getMethod() == 'POST' && url.contains('/clients')) {
                res.setStatusCode(201);
                res.setBody('{"data":{"id":"org_shared","name":"Acme","version":1}}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"data":[],"has_more":false}');
            }
            return res;
        }
    }

    @isTest
    static void batchSavesTheAccountLinkEvenWhenItsFirstProjectFails() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', false, true);
            Account fresh = newAccount(null);
            Opportunity o1 = newOpp(fresh.Id, null);
            Opportunity o2 = newOpp(fresh.Id, null);
            Test.setMock(HttpCalloutMock.class, new FirstProjectFailsMock());

            Test.startTest();
            VeleiroSyncService.syncOpportunities(new List<Id>{ o1.Id, o2.Id });
            Test.stopTest();

            System.assertEquals('org_shared',
                [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :fresh.Id].Veleiro_Client_Id__c,
                'el client creado para la primera queda vinculado aunque su project haya fallado');
            System.assertEquals(null, [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :o1.Id].Veleiro_Project_Id__c);
            System.assertEquals('prjct_2', [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :o2.Id].Veleiro_Project_Id__c,
                'la segunda reutiliza el client y sincroniza');
            String err = Veleiro_Config__c.getOrgDefaults().Last_Sync_Error__c;
            System.assert(err != null && err.contains(String.valueOf(o1.Id)), err);
        }
    }

    @isTest
    static void batchRecordsFailuresAfterTheDmlAndKeepsTheRest() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', false, true);
            Account linked = newAccount('org_existing');
            Opportunity orphan1 = newOpp(null, null);   // sin Account: falla antes del callout
            Opportunity good = newOpp(linked.Id, null);
            Opportunity orphan2 = newOpp(null, null);
            Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

            Test.startTest();
            List<Id> rest = VeleiroSyncService.syncOpportunities(new List<Id>{ orphan1.Id, good.Id, orphan2.Id });
            Test.stopTest();

            System.assert(rest.isEmpty(), 'todo cupo en la transaccion');
            System.assertEquals('prjct_test',
                [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :good.Id].Veleiro_Project_Id__c,
                'el fallo de una no frena a las demas');
            String err = Veleiro_Config__c.getOrgDefaults().Last_Sync_Error__c;
            System.assert(err != null && err.startsWith('2 failed.'), err);
            System.assert(err.contains(String.valueOf(orphan1.Id)) && err.contains(String.valueOf(orphan2.Id)), err);
        }
    }

    @isTest
    static void batchLeavesForAnotherTransactionWhatDoesNotFitTheCalloutBudget() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', false, true);
            Account linked = newAccount('org_existing');
            Opportunity o = newOpp(linked.Id, null);
            VeleiroApiMock mock = new VeleiroApiMock();
            Test.setMock(HttpCalloutMock.class, mock);
            VeleiroSyncService.calloutHeadroom = Limits.getLimitCallouts() + 1; // no cabe ni una

            Test.startTest();
            VeleiroSyncService.syncOpportunitiesInvocable(new List<Id>{ o.Id });
            Test.stopTest();

            System.assertEquals(0, mock.projectPosts, 'sin presupuesto no se hace ni un callout');
            System.assertEquals(1, [
                SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'VeleiroOppSyncQueueable'
            ], 'lo que no cupo sigue en otra transaccion');
            System.assertEquals(null,
                [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :o.Id].Veleiro_Project_Id__c);
        }
    }

    @isTest
    static void accountInvocableSyncsEveryAccountOfTheBatch() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true);
            Account a1 = newAccount(null);
            Account a2 = newAccount(null);
            VeleiroApiMock mock = new VeleiroApiMock();
            mock.distinctIds = true;
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            VeleiroSyncAccountAction.syncAccounts(new List<Id>{ a1.Id, a2.Id });
            Test.stopTest();

            System.assertEquals(2, mock.clientPosts, 'las dos cuentas en la misma transaccion');
            System.assertEquals(2, [SELECT COUNT() FROM Account WHERE Id IN :new List<Id>{ a1.Id, a2.Id }
                AND Veleiro_Client_Id__c != null]);
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Last_Sync_Error__c);
        }
    }

    @isTest
    static void accountInvocableReportsWhatDidNotFitTheCalloutBudget() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroSyncConfig.save('bidirectional', 'salesforce', 'off', 'auto', true, true);
            Account a = newAccount(null);
            VeleiroApiMock mock = new VeleiroApiMock();
            Test.setMock(HttpCalloutMock.class, mock);
            VeleiroSyncService.calloutHeadroom = Limits.getLimitCallouts() + 1;

            Test.startTest();
            VeleiroSyncAccountAction.syncAccounts(new List<Id>{ a.Id });
            Test.stopTest();

            System.assertEquals(0, mock.clientPosts);
            String err = Veleiro_Config__c.getOrgDefaults().Last_Sync_Error__c;
            System.assert(err != null && err.contains('Callout limit reached'), err);
        }
    }
}
