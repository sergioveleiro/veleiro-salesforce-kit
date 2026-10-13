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
            System.assert(e.getMessage().toLowerCase().contains('token'), 'debe pedir el token');
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

    @isTest
    static void baseUrlFallsBackToDefault() {
        // Con token pero sin Base_Url -> usa el default (callout via Named Credential).
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        c.Base_Url__c = null;
        update c;
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());
        Test.startTest();
        Map<String, Object> body = VeleiroApiClient.doGet('/clients', null);
        Test.stopTest();
        System.assert(body.containsKey('data'), 'funciona con Base_Url por default');
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

    /**
     * Dentro del paquete administrado la Named Credential se llama veleiro__Veleiro_API. Un
     * 'callout:Veleiro_API' pelado truena con "the named credential might not exist", y eso le
     * paso a un cliente con el paquete instalado: el kit nunca pudo llamar a Veleiro.
     *
     * Sin namespace el prefijo sale vacio y el bug es invisible, por eso se simula.
     */
    @isTest
    static void theCalloutCarriesTheNamespaceOfTheManagedPackage() {
        VeleiroSyncConfig.namespaceOverride = '';
        System.assertEquals('callout:Veleiro_API', VeleiroApiClient.calloutTo('Veleiro_API'),
            'desplegado del codigo fuente no lleva prefijo');
        System.assertEquals('callout:Veleiro_API/api/v1', VeleiroApiClient.defaultBase());

        VeleiroSyncConfig.namespaceOverride = 'veleiro__';
        System.assertEquals('callout:veleiro__Veleiro_API', VeleiroApiClient.calloutTo('Veleiro_API'),
            'dentro del paquete, con prefijo o no resuelve');
        System.assertEquals('callout:veleiro__Veleiro_API/api/v1', VeleiroApiClient.defaultBase());
        System.assertEquals('callout:veleiro__Veleiro_API_Beta',
            VeleiroApiClient.calloutTo(VeleiroApiClient.CRED_BETA));
    }

    // Hay orgs que ya tienen guardada la base sin prefijo: se repara al vuelo, sin pedirles nada.
    @isTest
    static void anOldBaseUrlWithoutTheNamespaceIsHealedOnTheFly() {
        VeleiroSyncConfig.namespaceOverride = 'veleiro__';
        System.assertEquals('callout:veleiro__Veleiro_API/api/v1',
            VeleiroApiClient.withNamespace('callout:Veleiro_API/api/v1'));
        System.assertEquals('callout:veleiro__Veleiro_API/api/v1',
            VeleiroApiClient.withNamespace('callout:veleiro__Veleiro_API/api/v1'),
            'si ya lo trae, no se le pone dos veces');
        System.assertEquals('https://app.veleiro.ai/api/v1',
            VeleiroApiClient.withNamespace('https://app.veleiro.ai/api/v1'),
            'una URL cruda no se toca');

        VeleiroSyncConfig.namespaceOverride = '';
        System.assertEquals('callout:Veleiro_API/api/v1',
            VeleiroApiClient.withNamespace('callout:Veleiro_API/api/v1'),
            'sin namespace se queda igual');
    }
}
