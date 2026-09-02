@isTest
private class VeleiroInsightServiceTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    private static VeleiroApiMock mockWithData() {
        String today = String.valueOf(Date.today()); // yyyy-MM-dd (daysSince usa los 1ros 10 chars)
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.statesBody = '{"data":[' +
            '{"id":"st_block","name":"Input Required","state_type":"blocked"},' +
            '{"id":"st_prog","name":"In Progress","state_type":"in_progress"}]}';
        mock.clientsBody = '{"data":[{"id":"org_test","name":"Acme",' +
            '"additional_fields":{"sf_account_id":"001xx"}}],"has_more":false}';
        mock.projectsBody = '{"data":[{"id":"prjct_1","client_id":"org_test",' +
            '"progress":35,"status":"active","updated_at":"' + today + 'T00:00:00+00:00"}],"has_more":false}';
        mock.tasksBody = '{"data":[],"has_more":false}';
        return mock;
    }

    @isTest
    static void getBriefingBucketsClient() {
        Test.setMock(HttpCalloutMock.class, mockWithData());
        Test.startTest();
        VeleiroInsightService.Briefing b = VeleiroInsightService.getBriefing();
        Test.stopTest();

        System.assertEquals(1, b.clientCount);
        System.assert(String.isNotBlank(b.headline), 'genera headline en lenguaje natural');
        Integer inQueues = b.expand.size() + b.risk.size() + b.attention.size();
        System.assertEquals(1, inQueues, 'el client cae en exactamente una cola');
    }

    @isTest
    static void getBriefingWithBlockedTaskGoesToRisk() {
        VeleiroApiMock mock = mockWithData();
        // una task bloqueada para el client -> cola de riesgo (unblock)
        mock.tasksBody = '{"data":[{"id":"t1","client_id":"org_test","status_id":"st_block"}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroInsightService.Briefing b = VeleiroInsightService.getBriefing();
        Test.stopTest();

        System.assertEquals(1, b.risk.size(), 'task bloqueada -> riesgo');
        System.assertEquals('unblock', b.risk[0].motionKey);
    }

    @isTest
    static void getInsightForSyncedAccount() {
        Account a = new Account(Name = 'Acme', Veleiro_Client_Id__c = 'org_test');
        insert a;
        Test.setMock(HttpCalloutMock.class, mockWithData());

        Test.startTest();
        VeleiroInsightService.ClientInsight ci = VeleiroInsightService.getInsightForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(true, ci.synced);
        System.assertEquals('org_test', ci.clientId);
        System.assert(String.isNotBlank(ci.narrative), 'Velly narra');
        System.assert(String.isNotBlank(ci.nextAction), 'da un next-best-action');
        System.assert(ci.score >= 0 && ci.score <= 100, 'score en rango');
    }

    @isTest
    static void getInsightForUnsyncedAccount() {
        Account a = new Account(Name = 'NoSync');
        insert a;
        Test.startTest();
        VeleiroInsightService.ClientInsight ci = VeleiroInsightService.getInsightForAccount(a.Id);
        Test.stopTest();
        System.assertEquals(false, ci.synced, 'account sin client -> no synced');
    }

    // Construye un mock con un solo project (progress/status/dias-sin-update) para
    // ejercitar cada rama del motor de reglas.
    private static VeleiroApiMock oneProject(Integer progress, String status, Integer daysAgo) {
        String d = String.valueOf(Date.today().addDays(-daysAgo));
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.statesBody = '{"data":[]}';
        mock.clientsBody = '{"data":[{"id":"org_test","name":"Acme"}],"has_more":false}';
        mock.projectsBody = '{"data":[{"id":"prjct_1","client_id":"org_test","progress":' + progress +
            ',"status":"' + status + '","updated_at":"' + d + 'T00:00:00+00:00"}],"has_more":false}';
        mock.tasksBody = '{"data":[],"has_more":false}';
        return mock;
    }

    private static String motionFor(VeleiroApiMock mock) {
        Test.setMock(HttpCalloutMock.class, mock);
        VeleiroInsightService.Briefing b = VeleiroInsightService.getBriefing();
        List<VeleiroInsightService.ClientInsight> all = new List<VeleiroInsightService.ClientInsight>();
        all.addAll(b.expand); all.addAll(b.risk); all.addAll(b.attention);
        return all.isEmpty() ? null : all[0].motionKey;
    }

    @isTest
    static void ruleOnboardingFreshZero() {
        Test.startTest();
        System.assertEquals('onboard', motionFor(oneProject(0, 'planning', 0)));
        Test.stopTest();
    }

    @isTest
    static void ruleOffCourseStalledZero() {
        Test.startTest();
        System.assertEquals('protect', motionFor(oneProject(0, 'active', 20)));
        Test.stopTest();
    }

    @isTest
    static void ruleStalledWithProgress() {
        Test.startTest();
        System.assertEquals('protect', motionFor(oneProject(40, 'active', 30)));
        Test.stopTest();
    }

    @isTest
    static void ruleReferenceComplete() {
        Test.startTest();
        System.assertEquals('reference', motionFor(oneProject(100, 'completed', 1)));
        Test.stopTest();
    }

    @isTest
    static void ruleSteadyEarly() {
        Test.startTest();
        System.assertEquals('nurture', motionFor(oneProject(10, 'active', 2)));
        Test.stopTest();
    }

    @isTest
    static void briefingEmptyWhenNoClients() {
        VeleiroApiMock mock = new VeleiroApiMock(); // todo vacio
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        VeleiroInsightService.Briefing b = VeleiroInsightService.getBriefing();
        Test.stopTest();
        System.assertEquals(0, b.clientCount);
        System.assert(String.isNotBlank(b.headline), 'headline de estado vacio');
    }

    @isTest
    static void insightForAccountFallbackWhenClientMissing() {
        // Account apunta a un client que no vuelve en la lista -> rama de fallback.
        Account a = new Account(Name = 'Ghost', Veleiro_Client_Id__c = 'org_missing');
        insert a;
        Test.setMock(HttpCalloutMock.class, oneProject(35, 'active', 1));
        Test.startTest();
        VeleiroInsightService.ClientInsight ci = VeleiroInsightService.getInsightForAccount(a.Id);
        Test.stopTest();
        System.assertEquals(true, ci.synced);
        System.assertEquals('org_missing', ci.clientId);
    }
}
