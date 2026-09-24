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

    @isTest
    static void suggestsStrongAndWeakMatches() {
        Account domainMatch = new Account(Name = 'Razon Social Distinta', Website = 'https://acme.com');
        Account nameMatch = new Account(Name = 'Globex S.A.');
        Account noMatch = new Account(Name = 'Sin Pareja');
        insert new List<Account>{ domainMatch, nameMatch, noMatch };

        mockClients('{"data":[' +
            '{"id":"org_acme","name":"Acme","additional_fields":{"sf_website":"http://www.acme.com/x"}},' +
            '{"id":"org_globex","name":"GLOBEX SAS","additional_fields":{}}' +
            '],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions();
        Test.stopTest();

        System.assertEquals(2, o.suggestions.size());
        System.assertEquals('high', o.suggestions[0].confidence, 'las fuertes van primero');
        System.assertEquals('org_acme', o.suggestions[0].clientId);
        System.assertEquals(domainMatch.Id, o.suggestions[0].accountId);
        System.assertEquals('medium', o.suggestions[1].confidence);
        System.assertEquals(3, o.accountsUnlinked);
        System.assertEquals(2, o.clientsTotal);
        System.assertEquals(2, o.clientsUnlinked);
        System.assertEquals(0, o.accountsLinked);
    }

    @isTest
    static void skipsClientsAlreadyLinked() {
        insert new Account(Name = 'Ya vinculada', Veleiro_Client_Id__c = 'org_taken');
        insert new Account(Name = 'Acme');
        mockClients('{"data":[{"id":"org_taken","name":"Acme","additional_fields":{}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions();
        Test.stopTest();

        System.assert(o.suggestions.isEmpty(), 'ese client ya tiene dueño');
        System.assertEquals(1, o.accountsLinked);
        System.assertEquals(0, o.clientsUnlinked);
    }

    @isTest
    static void oneClientIsSuggestedOnlyOnce() {
        // Dos Accounts se parecen al mismo client: gana la coincidencia fuerte.
        Account byName = new Account(Name = 'Acme');
        Account byDomain = new Account(Name = 'Otra', Website = 'acme.com');
        insert new List<Account>{ byName, byDomain };
        mockClients('{"data":[{"id":"org_acme","name":"Acme","additional_fields":{"sf_website":"acme.com"}}],"has_more":false}');

        Test.startTest();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions();
        Test.stopTest();

        System.assertEquals(1, o.suggestions.size(), 'un client no se ofrece a dos cuentas');
        System.assertEquals(byDomain.Id, o.suggestions[0].accountId);
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
        System.assert(o.suggestions.isEmpty());
    }
}
