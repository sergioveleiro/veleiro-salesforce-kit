@isTest
private class VeleiroDashboardControllerTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    @isTest
    static void getOverviewAggregatesByClient() {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[' +
            '{"id":"org_a","name":"Alpha"},' +
            '{"id":"org_b","name":"Bravo"}],"has_more":false}';
        mock.projectsBody = '{"data":[' +
            '{"id":"prjct_1","client_id":"org_a","progress":50,"status":"active"},' +
            '{"id":"prjct_2","client_id":"org_a","progress":100,"status":"completed"},' +
            '{"id":"prjct_3","client_id":"org_b","progress":0,"status":"planning"}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroDashboardController.Overview ov = VeleiroDashboardController.getOverview();
        Test.stopTest();

        System.assertEquals(2, ov.clientCount);
        System.assertEquals(3, ov.projectCount);
        System.assertEquals(1, ov.completedProjectCount, 'uno al 100%');
        System.assertEquals(2, ov.openProjectCount);
        System.assert(ov.avgProgress >= 0 && ov.avgProgress <= 100);
        System.assertEquals(2, ov.clients.size());
    }

    @isTest
    static void getOverviewHandlesOrphanProject() {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[],"has_more":false}';
        mock.projectsBody = '{"data":[{"id":"prjct_x","client_id":"org_ghost","progress":10}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroDashboardController.Overview ov = VeleiroDashboardController.getOverview();
        Test.stopTest();

        System.assertEquals(1, ov.projectCount, 'el project huerfano se cuenta bajo Unassigned');
    }
}
