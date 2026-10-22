/**
 * Cubre VeleiroPulseService: el tiempo invertido y el trabajo abierto/trabado que se pintan
 * arriba de los paneles.
 */
@isTest
private class VeleiroPulseServiceTest {

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
    }

    private static Account newAccount(String clientId) {
        Account a = new Account(Name = 'Acme');
        if (String.isNotBlank(clientId)) a.Veleiro_Client_Id__c = clientId;
        insert a;
        return a;
    }

    private static Opportunity newOpp(Id accountId, String projectId) {
        Opportunity o = new Opportunity(
            Name = 'Acme - Implementation', StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30), AccountId = accountId);
        if (String.isNotBlank(projectId)) o.Veleiro_Project_Id__c = projectId;
        insert o;
        return o;
    }

    // initial / blocked / done, que es lo que separa "abierto" de "cerrado".
    private static String states() {
        return '{"data":[{"id":"tckt_st_1","state_type":"initial"},' +
               '{"id":"tckt_st_2","state_type":"blocked"},' +
               '{"id":"tckt_st_3","state_type":"done"}]}';
    }

    // 45 + 15 + 120 = 180 minutos; 2 abiertas (una trabada) y 1 cerrada. La archivada no cuenta.
    private static String tasks() {
        return '{"data":[' +
            '{"id":"tckt_1","title":"Setup","status_id":"tckt_st_1","logged_minutes":45,"is_archived":false},' +
            '{"id":"tckt_2","title":"Esperando datos","status_id":"tckt_st_2","logged_minutes":15,"is_archived":false},' +
            '{"id":"tckt_3","title":"Entregado","status_id":"tckt_st_3","logged_minutes":120,"is_archived":false},' +
            '{"id":"tckt_4","title":"Vieja","status_id":"tckt_st_1","logged_minutes":999,"is_archived":true}' +
            '],"has_more":false}';
    }

    private static VeleiroApiMock mockWith(String projectsBody) {
        VeleiroApiMock m = new VeleiroApiMock();
        m.statesBody = states();
        m.tasksBody = tasks();
        if (projectsBody != null) m.projectsBody = projectsBody;
        Test.setMock(HttpCalloutMock.class, m);
        return m;
    }

    @isTest
    static void anOpportunityAddsUpTheTimeAndTheOpenWork() {
        Account a = newAccount('org_test');
        Opportunity o = newOpp(a.Id, 'prjct_test');
        mockWith(null);

        Test.startTest();
        VeleiroPulseService.Pulse p = VeleiroPulseService.getForOpportunity(o.Id);
        Test.stopTest();

        System.assertEquals(180, p.loggedMinutes, 'la archivada no suma');
        System.assertEquals(3, p.totalTasks);
        System.assertEquals(2, p.openTasks, 'todo lo que no esta en done sigue vivo');
        System.assertEquals(1, p.blockedTasks);
        System.assertEquals(true, p.hasData);
        System.assertEquals(true, p.reachable);
    }

    @isTest
    static void anAccountAddsUpEveryProjectAndNamesThem() {
        Account a = newAccount('org_test');
        mockWith('{"data":[{"id":"prjct_a","name":"Alpha","is_archived":false},' +
                 '{"id":"prjct_b","name":"Beta","is_archived":false},' +
                 '{"id":"prjct_old","name":"Archivado","is_archived":true}],"has_more":false}');

        Test.startTest();
        VeleiroPulseService.Pulse p = VeleiroPulseService.getForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(2, p.projects.size(), 'el project archivado queda fuera');
        System.assertEquals('Alpha', p.projects[0].name);
        System.assertEquals(360, p.loggedMinutes, 'dos projects, 180 cada uno');
        System.assertEquals(4, p.openTasks);
        System.assertEquals(2, p.blockedTasks);
        System.assertEquals(false, p.partial);
    }

    @isTest
    static void aClientWithTooManyProjectsSaysItOnlyAddedSome() {
        VeleiroPulseService.maxProjectsPerClient = 2;
        Account a = newAccount('org_test');
        List<String> rows = new List<String>();
        for (Integer i = 0; i < 5; i++) {
            rows.add('{"id":"prjct_' + i + '","name":"P' + i + '","is_archived":false}');
        }
        mockWith('{"data":[' + String.join(rows, ',') + '],"has_more":false}');

        Test.startTest();
        VeleiroPulseService.Pulse p = VeleiroPulseService.getForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(2, p.projects.size());
        System.assertEquals(true, p.partial, 'el panel debe poder avisar que el numero va corto');
    }

    @isTest
    static void aProjectWithNoTasksStillShowsItsPulse() {
        Account a = newAccount('org_test');
        Opportunity o = newOpp(a.Id, 'prjct_test');
        VeleiroApiMock m = new VeleiroApiMock();
        m.statesBody = states();
        m.tasksBody = '{"data":[],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, m);

        Test.startTest();
        VeleiroPulseService.Pulse p = VeleiroPulseService.getForOpportunity(o.Id);
        Test.stopTest();

        System.assertEquals(true, p.hasData, 'un project recien arrancado tambien cuenta algo');
        System.assertEquals(0, p.loggedMinutes);
        System.assertEquals(0, p.openTasks);
    }

    @isTest
    static void withoutTheTaskScopeItSaysSoInsteadOfFailing() {
        Account a = newAccount('org_test');
        VeleiroApiMock m = new VeleiroApiMock();
        m.overrideStatus = 403;
        m.overrideBody = '{"error":{"code":"insufficient_scope","message":"nope"}}';
        Test.setMock(HttpCalloutMock.class, m);

        Test.startTest();
        VeleiroPulseService.Pulse p = VeleiroPulseService.getForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(true, p.scopeMissing);
        System.assertEquals(false, p.hasData);
    }

    @isTest
    static void anyOtherErrorJustHidesThePulse() {
        Account a = newAccount('org_test');
        Opportunity o = newOpp(a.Id, 'prjct_test');
        VeleiroApiMock m = new VeleiroApiMock();
        m.overrideStatus = 500;
        m.overrideBody = '{"error":{"code":"internal_error"}}';
        Test.setMock(HttpCalloutMock.class, m);

        Test.startTest();
        VeleiroPulseService.Pulse p = VeleiroPulseService.getForOpportunity(o.Id);
        Test.stopTest();

        System.assertEquals(false, p.reachable);
        System.assertEquals(false, p.hasData);
    }

    @isTest
    static void anUnlinkedRecordNeverSpendsACallout() {
        Account a = newAccount(null);
        Opportunity o = newOpp(a.Id, null);

        Test.startTest();
        VeleiroPulseService.Pulse fromAccount = VeleiroPulseService.getForAccount(a.Id);
        VeleiroPulseService.Pulse fromOpp = VeleiroPulseService.getForOpportunity(o.Id);
        VeleiroPulseService.Pulse none = VeleiroPulseService.getForAccount(null);
        Integer calls = Limits.getCallouts();
        Test.stopTest();

        System.assertEquals(0, calls);
        System.assertEquals(false, fromAccount.hasData);
        System.assertEquals(false, fromOpp.hasData);
        System.assertEquals(true, none.projects.isEmpty());
    }

    @isTest
    static void theMeetingsOfAnAccountCarryTheirProjectName() {
        Account a = newAccount('org_test');
        VeleiroApiMock m = new VeleiroApiMock();
        m.projectsBody = '{"data":[{"id":"prjct_a","name":"Alpha","is_archived":false}],"has_more":false}';
        m.meetingsBody = '{"data":[{"id":"bot_1","url":"https://app.test.veleiro.local/a/partner-portal/meetings/bot_1/",' +
            '"title":"Kickoff","status":"done","client_id":"org_test","project_id":"prjct_a",' +
            '"start_time":"2026-03-02T15:00:00+00:00","transcript_status":"none"}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, m);

        Test.startTest();
        VeleiroMeetingService.MeetingList r = VeleiroMeetingService.getForAccount(a.Id);
        Test.stopTest();

        System.assertEquals('Alpha', r.meetings[0].projectName, 'el id no le dice nada a nadie');
        System.assertEquals(1, r.projects.size(), 'alimenta el filtro por project del timeline');
        System.assertEquals('Alpha', r.projects[0].name);
    }
}
