@isTest
private class VeleiroConnectionTest {
    @testSetup
    static void setup() { VeleiroApiMock.seedConfig(); }

    @isTest
    static void statusConnected() {
        System.runAs(VeleiroTestAccess.user()) {
            Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());
            Test.startTest();
            Map<String, String> s = VeleiroMappingController.getStatus();
            Test.stopTest();
            System.assertEquals('true', s.get('tokenSet'));
            System.assertEquals('true', s.get('connected'), 'mock 200 -> conectado');
            System.assertEquals(true, VeleiroApiClient.hasToken());
        }
    }

    @isTest
    static void statusNotConnectedOnError() {
        System.runAs(VeleiroTestAccess.user()) {
            VeleiroApiMock mock = new VeleiroApiMock();
            mock.overrideStatus = 401;
            mock.overrideBody = '{"error":{"code":"invalid_token"}}';
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            Map<String, String> s = VeleiroMappingController.getStatus();
            Test.stopTest();
            System.assertEquals('false', s.get('connected'), 'error -> no conectado');
        }
    }

    @isTest
    static void saveTokenPersists() {
        System.runAs(VeleiroTestAccess.admin()) {
            Test.startTest();
            VeleiroMappingController.saveToken('vlr_abc123');
            Test.stopTest();
            System.assertEquals(true, VeleiroApiClient.hasToken());
        }
    }

    @isTest
    static void statusNoToken() {
        System.runAs(VeleiroTestAccess.user()) {
            delete [SELECT Id FROM Veleiro_Config__c];
            Test.startTest();
            Map<String, String> s = VeleiroMappingController.getStatus();
            Test.stopTest();
            System.assertEquals('false', s.get('tokenSet'));
            System.assertEquals('false', s.get('connected'));
        }
    }
}
