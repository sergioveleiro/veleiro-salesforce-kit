@isTest
private class VeleiroClientMatcherTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    private static VeleiroApiMock mockWith(String clientsJson) {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = clientsJson;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    private static Account newAccount(String name, String website) {
        Account a = new Account(Name = name, Website = website);
        insert a;
        return a;
    }

    @isTest
    static void matchesBySfAccountId() {
        Account a = newAccount('Totally Different Name', null);
        mockWith('{"data":[{"id":"org_linked","name":"Acme","additional_fields":{"sf_account_id":"' + a.Id + '"}}],"has_more":false}');

        Test.startTest();
        VeleiroClientMatcher.MatchResult r = VeleiroClientMatcher.forAccount(a.Id);
        Test.stopTest();

        System.assertEquals(1, r.candidates.size());
        System.assertEquals('org_linked', r.candidates[0].clientId);
        System.assertEquals(VeleiroClientMatcher.HIGH, r.candidates[0].confidence);
        System.assertNotEquals(null, VeleiroClientMatcher.autoLinkable(r), 'coincidencia fuerte -> vincula sola');
    }

    @isTest
    static void matchesByWebsiteDomain() {
        Account a = newAccount('Acme Colombia', 'https://www.acme.com/es');
        mockWith('{"data":[{"id":"org_dom","name":"Otra Razon Social","additional_fields":{"sf_website":"http://acme.com"}}],"has_more":false}');

        Test.startTest();
        VeleiroClientMatcher.MatchResult r = VeleiroClientMatcher.forAccount(a.Id);
        Test.stopTest();

        System.assertEquals(1, r.candidates.size());
        System.assertEquals(VeleiroClientMatcher.HIGH, r.candidates[0].confidence);
        System.assert(r.candidates[0].reason.contains('acme.com'));
    }

    @isTest
    static void matchesByNameOnlyAsMedium() {
        Account a = newAccount('Acme S.A.', null);
        mockWith('{"data":[{"id":"org_name","name":"ACME SAS","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroClientMatcher.MatchResult r = VeleiroClientMatcher.forAccount(a.Id);
        Test.stopTest();

        System.assertEquals(1, r.candidates.size());
        System.assertEquals(VeleiroClientMatcher.MEDIUM, r.candidates[0].confidence, 'solo el nombre -> se pregunta');
        System.assertEquals(null, VeleiroClientMatcher.autoLinkable(r), 'por nombre nunca vincula sola');
    }

    @isTest
    static void ignoresArchivedAndUnrelated() {
        Account a = newAccount('Acme', 'acme.com');
        mockWith('{"data":[' +
            '{"id":"org_arch","name":"Acme","is_archived":true,"additional_fields":{}},' +
            '{"id":"org_other","name":"Globex","additional_fields":{"sf_website":"globex.com"}}' +
            '],"has_more":false}');

        Test.startTest();
        VeleiroClientMatcher.MatchResult r = VeleiroClientMatcher.forAccount(a.Id);
        Test.stopTest();

        System.assert(r.candidates.isEmpty(), 'ni archivados ni ajenos');
    }

    @isTest
    static void flagsClientTakenByAnotherAccount() {
        Account taken = new Account(Name = 'Otro', Veleiro_Client_Id__c = 'org_taken');
        insert taken;
        Account a = newAccount('Acme', null);
        mockWith('{"data":[{"id":"org_taken","name":"Acme","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroClientMatcher.MatchResult r = VeleiroClientMatcher.forAccount(a.Id);
        Test.stopTest();

        System.assertEquals(true, r.candidates[0].linkedToOtherAccount, 'se muestra pero avisando');
        System.assertEquals(null, VeleiroClientMatcher.autoLinkable(r), 'no se roba el client de otra cuenta');
    }

    @isTest
    static void tooManyClientsSkipsMatching() {
        VeleiroClientMatcher.maxClients = 0; // simula un catalogo enorme
        Account a = newAccount('Acme', null);
        mockWith('{"data":[{"id":"org_x","name":"Acme","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroClientMatcher.MatchResult r = VeleiroClientMatcher.forAccount(a.Id);
        Test.stopTest();

        System.assertEquals(true, r.truncated);
        System.assert(r.candidates.isEmpty(), 'sin confianza no se sugiere nada');
        System.assertEquals(null, VeleiroClientMatcher.autoLinkable(r));
    }

    @isTest
    static void syncAccountLinksInsteadOfCreating() {
        Account a = newAccount('Acme', 'acme.com');
        VeleiroApiMock mock = mockWith('{"data":[{"id":"org_existing","name":"Acme","version":3,"additional_fields":{"sf_website":"acme.com"}}],"has_more":false}');
        mock.singleClientBody = '{"data":{"id":"org_existing","name":"Acme","version":3,"additional_fields":{"sf_website":"acme.com"}}}';

        Test.startTest();
        VeleiroSyncService.ClientResult r = VeleiroSyncService.syncAccount(a.Id);
        Test.stopTest();

        System.assertEquals(false, r.created, 'vincula y actualiza, no crea');
        System.assertEquals('org_existing', [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id].Veleiro_Client_Id__c);
        System.assertEquals(null, mock.lastPostBody, 'ningun POST /clients');
    }

    @isTest
    static void createClientForAccountIgnoresCandidates() {
        Account a = newAccount('Acme', 'acme.com');
        VeleiroApiMock mock = mockWith('{"data":[{"id":"org_existing","name":"Acme","additional_fields":{"sf_website":"acme.com"}}],"has_more":false}');

        Test.startTest();
        VeleiroSyncService.ClientResult r = VeleiroSyncService.createClientForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(true, r.created, 'el usuario pidio crear uno nuevo igual');
        System.assertNotEquals(null, mock.lastPostBody);
    }

    @isTest
    static void linkAccountToClientUpdatesExisting() {
        Account a = newAccount('Acme', null);

        Test.startTest();
        mockWith('{"data":[],"has_more":false}');
        VeleiroSyncService.ClientResult r = VeleiroSyncService.linkAccountToClient(a.Id, 'org_test');
        Test.stopTest();

        System.assertEquals(false, r.created);
        System.assertEquals('org_test', [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id].Veleiro_Client_Id__c);
    }

    @isTest
    static void linkRequiresClientId() {
        Account a = newAccount('Acme', null);
        Boolean threw = false;
        try {
            VeleiroSyncService.linkAccountToClient(a.Id, '   ');
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void findClientCandidatesIsExposedToTheLwc() {
        Account a = newAccount('Acme', null);
        mockWith('{"data":[{"id":"org_name","name":"Acme","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroClientMatcher.MatchResult r = VeleiroSyncService.findClientCandidates(a.Id);
        Test.stopTest();

        System.assertEquals(1, r.candidates.size());
    }
}
