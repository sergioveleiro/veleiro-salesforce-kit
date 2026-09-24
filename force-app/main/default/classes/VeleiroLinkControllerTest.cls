@isTest
private class VeleiroLinkControllerTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    private static void mockClients(String json) {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = json;
        Test.setMock(HttpCalloutMock.class, mock);
    }

    private static VeleiroLinkController.ClientRow rowFor(VeleiroLinkController.Overview o, String clientId) {
        for (VeleiroLinkController.ClientRow r : o.rows) {
            if (r.clientId == clientId) return r;
        }
        return null;
    }

    @isTest
    static void listsEveryUnlinkedClientEvenWithoutMatches() {
        Account domainMatch = new Account(Name = 'Razon Social Distinta', Website = 'https://acme.com');
        Account nameMatch = new Account(Name = 'Globex S.A.');
        insert new List<Account>{ domainMatch, nameMatch };

        mockClients('{"data":[' +
            '{"id":"org_acme","name":"Acme","additional_fields":{"sf_website":"http://www.acme.com/x"}},' +
            '{"id":"org_globex","name":"GLOBEX SAS","additional_fields":{}},' +
            '{"id":"org_alone","name":"Nadie Se Le Parece","additional_fields":{}}' +
            '],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions();
        Test.stopTest();

        System.assertEquals(3, o.rows.size(), 'todos los clients sin vincular, con o sin candidato');
        System.assertEquals(3, o.clientsUnlinked);
        System.assertEquals(2, o.accountsUnlinked);

        System.assertEquals('org_acme', o.rows[0].clientId, 'la coincidencia fuerte va primero');
        System.assertEquals(domainMatch.Id, o.rows[0].suggestedAccountId);
        System.assertEquals('high', o.rows[0].confidence);

        VeleiroLinkController.ClientRow globex = rowFor(o, 'org_globex');
        System.assertEquals(nameMatch.Id, globex.suggestedAccountId);
        System.assertEquals('medium', globex.confidence);

        VeleiroLinkController.ClientRow alone = rowFor(o, 'org_alone');
        System.assert(alone.options.isEmpty(), 'sin candidatos, pero la fila existe');
        System.assertEquals(null, alone.suggestedAccountId);
    }

    @isTest
    static void offersSimilarNamesWithoutPreselecting() {
        Account similar = new Account(Name = 'Codeart Solutions');
        insert similar;
        mockClients('{"data":[{"id":"org_code","name":"Codeart","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions();
        Test.stopTest();

        VeleiroLinkController.ClientRow r = o.rows[0];
        System.assertEquals(1, r.options.size(), 'lo ofrece como parecido');
        System.assertEquals(similar.Id, r.options[0].accountId);
        System.assertEquals('weak', r.confidence);
        System.assertEquals(null, r.suggestedAccountId, 'un parecido nunca viene preseleccionado');
    }

    @isTest
    static void skipsClientsAlreadyLinked() {
        insert new Account(Name = 'Ya vinculada', Veleiro_Client_Id__c = 'org_taken');
        insert new Account(Name = 'Acme');
        mockClients('{"data":[' +
            '{"id":"org_taken","name":"Acme","additional_fields":{}},' +
            '{"id":"org_arch","name":"Acme","is_archived":true,"additional_fields":{}}' +
            '],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions();
        Test.stopTest();

        System.assert(o.rows.isEmpty(), 'ni el ya vinculado ni el archivado');
        System.assertEquals(1, o.accountsLinked);
        System.assertEquals(0, o.clientsUnlinked);
    }

    @isTest
    static void strongCandidateBeatsWeakOneForTheSameClient() {
        Account byName = new Account(Name = 'Acme');
        Account byDomain = new Account(Name = 'Acme Holdings', Website = 'acme.com');
        insert new List<Account>{ byName, byDomain };
        mockClients('{"data":[{"id":"org_acme","name":"Acme","additional_fields":{"sf_website":"acme.com"}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions();
        Test.stopTest();

        VeleiroLinkController.ClientRow r = o.rows[0];
        System.assertEquals(byDomain.Id, r.suggestedAccountId, 'el dominio gana al nombre');
        System.assert(r.options.size() >= 2, 'el otro sigue disponible en el selector');
    }

    @isTest
    static void matchesTheSalesforceIdTheClientAlreadyCarries() {
        Account a = new Account(Name = 'Nombre Distinto');
        insert a;
        mockClients('{"data":[{"id":"org_id","name":"Otro","additional_fields":{"sf_account_id":"' + a.Id + '"}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions();
        Test.stopTest();

        System.assertEquals(a.Id, o.rows[0].suggestedAccountId);
        System.assertEquals('high', o.rows[0].confidence);
    }

    @isTest
    static void searchAccountsFindsUnlinkedOnesByName() {
        insert new Account(Name = 'Buscable Uno');
        insert new Account(Name = 'Buscable Dos', Veleiro_Client_Id__c = 'org_x');

        List<VeleiroLinkController.AccountOption> found = VeleiroLinkController.searchAccounts('buscable');
        System.assertEquals(1, found.size(), 'solo las que faltan por vincular');
        System.assertEquals('Buscable Uno', found[0].name);
        System.assert(VeleiroLinkController.searchAccounts('a').isEmpty(), 'busqueda muy corta');
        System.assert(VeleiroLinkController.searchAccounts(null).isEmpty());
    }

    @isTest
    static void linkAllWritesTheIds() {
        Account a = new Account(Name = 'Acme');
        insert a;

        Test.startTest();
        Integer linked = VeleiroLinkController.linkAll(JSON.serialize(new List<Map<String, String>>{
            new Map<String, String>{ 'accountId' => a.Id, 'clientId' => 'org_acme' }
        }));
        Test.stopTest();

        System.assertEquals(1, linked);
        System.assertEquals('org_acme', [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :a.Id].Veleiro_Client_Id__c);
    }

    @isTest
    static void linkAllNeverReusesAClient() {
        Account taken = new Account(Name = 'Primera', Veleiro_Client_Id__c = 'org_acme');
        Account other = new Account(Name = 'Segunda');
        insert new List<Account>{ taken, other };

        Test.startTest();
        Integer linked = VeleiroLinkController.linkAll(JSON.serialize(new List<Map<String, String>>{
            new Map<String, String>{ 'accountId' => other.Id, 'clientId' => 'org_acme' },
            new Map<String, String>{ 'accountId' => other.Id, 'clientId' => '' }
        }));
        Test.stopTest();

        System.assertEquals(0, linked, 'ni roba el client ni acepta filas vacias');
        System.assertEquals(null, [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :other.Id].Veleiro_Client_Id__c);
    }

    @isTest
    static void tooManyAccountsStopsMatching() {
        VeleiroLinkController.maxAccounts = 0;
        insert new Account(Name = 'Acme');
        mockClients('{"data":[{"id":"org_acme","name":"Acme","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions();
        Test.stopTest();

        System.assertEquals(true, o.truncated);
        System.assertEquals(1, o.rows.size(), 'los clients se listan igual, sin candidatos');
        System.assert(o.rows[0].options.isEmpty());
    }
}
