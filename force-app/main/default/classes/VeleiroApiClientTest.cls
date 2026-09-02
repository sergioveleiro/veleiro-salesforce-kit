@isTest
private class VeleiroApiClientTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    @isTest
    static void doGetReturnsEnvelope() {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[{"id":"org_1","name":"Uno"}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> body = VeleiroApiClient.doGet('/clients', null);
        Test.stopTest();

        System.assert(body.containsKey('data'), 'debe traer el envelope data');
    }

    @isTest
    static void listAllFollowsCursor() {
        Test.setMock(HttpCalloutMock.class, new TwoPageMock());
        Test.startTest();
        List<Object> all = VeleiroApiClient.listAll('/clients', null);
        Test.stopTest();
        System.assertEquals(2, all.size(), 'debe unir las dos paginas');
    }

    @isTest
    static void doPostReturnsData() {
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());
        Test.startTest();
        Map<String, Object> data = VeleiroApiClient.doPost('/clients',
            new Map<String, Object>{ 'name' => 'X' });
        Test.stopTest();
        System.assertEquals('org_test', data.get('id'));
    }

    @isTest
    static void doPatchReturnsData() {
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Map<String, Object> data = VeleiroApiClient.doPatch('/clients/org_test',
            new Map<String, Object>{ 'name' => 'Y' }, 1);
        Test.stopTest();
        System.assertEquals('org_test', data.get('id'));
    }

    @isTest
    static void notFoundThrowsWithCode() {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 404;
        mock.overrideBody = '{"error":{"code":"not_found","message":"nope"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            VeleiroApiClient.doGet('/clients/org_x', null);
            System.assert(false, 'debio lanzar');
        } catch (VeleiroApiClient.VeleiroApiException e) {
            System.assertEquals('not_found', e.code, 'ramifica por code, no por message');
        }
        Test.stopTest();
    }

    @isTest
    static void missingConfigThrows() {
        delete [SELECT Id FROM Veleiro_Config__c];
        Test.startTest();
        try {
            VeleiroApiClient.doGet('/clients', null);
            System.assert(false, 'debio lanzar por config faltante');
        } catch (VeleiroApiClient.VeleiroApiException e) {
            System.assert(e.getMessage().contains('Veleiro_Config__c'));
        }
        Test.stopTest();
    }

    @isTest
    static void appBaseFallsBackToDefault() {
        // Sin App_Base_Url__c configurada -> default beta.
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        c.App_Base_Url__c = null;
        update c;
        System.assert(VeleiroApiClient.appBaseUrl().startsWith('https://'), 'devuelve un default valido');
    }

    // Mock de dos paginas para ejercitar la paginacion por cursor.
    private class TwoPageMock implements HttpCalloutMock {
        Integer calls = 0;
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            if (calls == 0) {
                calls++;
                res.setBody('{"data":[{"id":"org_1"}],"has_more":true,"next_cursor":"abc"}');
            } else {
                res.setBody('{"data":[{"id":"org_2"}],"has_more":false}');
            }
            return res;
        }
    }
}
