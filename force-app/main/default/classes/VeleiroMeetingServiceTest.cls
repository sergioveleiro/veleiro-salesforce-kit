/**
 * Cubre VeleiroMeetingService. Lo que de verdad importa aqui no es el camino feliz, sino que
 * una org SIN el scope `meeting` (todas las que ya tenian una API key) no vea el panel roto.
 */
@isTest
private class VeleiroMeetingServiceTest {

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
            Name = 'Acme - Implementation',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = accountId
        );
        if (String.isNotBlank(projectId)) o.Veleiro_Project_Id__c = projectId;
        insert o;
        return o;
    }

    // Dos reuniones del mismo project, la vieja primero, para que el orden del panel se note.
    private static String twoMeetings() {
        return '{"data":[' +
            '{"id":"bot_old","url":"https://app.test.veleiro.local/a/partner-portal/meetings/bot_old/",' +
            '"title":"Kickoff","status":"done","client_id":"org_test","project_id":"prjct_test",' +
            '"start_time":"2026-01-10T15:00:00+00:00","end_time":"2026-01-10T16:00:00+00:00",' +
            '"is_archived":false,"version":3,"transcript_status":"none","transcript_id":null},' +
            '{"id":"bot_new","url":"https://app.test.veleiro.local/a/partner-portal/meetings/bot_new/",' +
            '"title":"Revision semanal","status":"done","client_id":"org_test","project_id":"prjct_test",' +
            '"start_time":"2026-03-02T15:00:00+00:00","end_time":null,' +
            '"is_archived":false,"version":1,"transcript_status":"available","transcript_id":"trn_1"}' +
            '],"has_more":false}';
    }

    @isTest
    static void opportunityMeetingsComeBackNewestFirst() {
        Account a = newAccount('org_test');
        Opportunity o = newOpp(a.Id, 'prjct_test');
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.meetingsBody = twoMeetings();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroMeetingService.MeetingList r = VeleiroMeetingService.getForOpportunity(o.Id);
        Test.stopTest();

        System.assertEquals(2, r.meetings.size());
        System.assertEquals('bot_new', r.meetings[0].id, 'la mas reciente va primero');
        System.assertEquals('bot_old', r.meetings[1].id);
        System.assertEquals(true, r.meetings[0].hasTranscript, 'transcript_status available');
        System.assertEquals(false, r.meetings[1].hasTranscript);
        System.assertEquals(false, r.scopeMissing);
        System.assertEquals(true, r.reachable);
        System.assertEquals(2, r.total);
    }

    @isTest
    static void theUrlIsTheOneVeleiroSentNotOneWeBuilt() {
        Account a = newAccount('org_test');
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.meetingsBody = twoMeetings();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroMeetingService.MeetingList r = VeleiroMeetingService.getForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(
            'https://app.test.veleiro.local/a/partner-portal/meetings/bot_new/',
            r.meetings[0].url,
            'se guarda tal cual: armarla aqui se rompe cuando el portal cambie de ruta');
    }

    @isTest
    static void withoutTheMeetingScopeThePanelSaysSoInsteadOfFailing() {
        Account a = newAccount('org_test');
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 403;
        mock.overrideBody = '{"error":{"code":"insufficient_scope","message":"Insufficient scope for this operation."}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroMeetingService.MeetingList r = VeleiroMeetingService.getForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(true, r.scopeMissing, 'se ramifica por el code, no por el mensaje');
        System.assertEquals(true, r.meetings.isEmpty());
    }

    @isTest
    static void anyOtherVeleiroErrorJustHidesTheSection() {
        Account a = newAccount('org_test');
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 500;
        mock.overrideBody = '{"error":{"code":"internal_error","message":"boom"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroMeetingService.MeetingList r = VeleiroMeetingService.getForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(false, r.reachable);
        System.assertEquals(false, r.scopeMissing);
        System.assertEquals(true, r.meetings.isEmpty());
    }

    @isTest
    static void anUnlinkedRecordNeverSpendsACallout() {
        Account a = newAccount(null);
        Opportunity o = newOpp(a.Id, null);

        Test.startTest();
        VeleiroMeetingService.MeetingList fromAccount = VeleiroMeetingService.getForAccount(a.Id);
        VeleiroMeetingService.MeetingList fromOpp = VeleiroMeetingService.getForOpportunity(o.Id);
        Integer calls = Limits.getCallouts();
        Test.stopTest();

        System.assertEquals(0, calls, 'sin vinculo no hay a quien preguntarle');
        System.assertEquals(true, fromAccount.meetings.isEmpty());
        System.assertEquals(true, fromOpp.meetings.isEmpty());
        System.assertEquals(true, fromOpp.reachable, 'vacio no es inalcanzable');
    }

    @isTest
    static void nullIdsAndBrokenRowsDoNotBlowUp() {
        VeleiroApiMock mock = new VeleiroApiMock();
        // Una fila sin url (no aporta un link) y una fecha ilegible.
        mock.meetingsBody = '{"data":[' +
            '{"id":"bot_nourl","title":"Sin link","status":"done"},' +
            '{"id":"bot_baddate","url":"https://app.test.veleiro.local/a/partner-portal/meetings/bot_baddate/",' +
            '"title":"Fecha rara","status":"done","start_time":"ayer","transcript_status":"processing"}' +
            '],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);
        Account a = newAccount('org_test');

        Test.startTest();
        VeleiroMeetingService.MeetingList r = VeleiroMeetingService.getForAccount(a.Id);
        VeleiroMeetingService.MeetingList none = VeleiroMeetingService.getForOpportunity(null);
        Test.stopTest();

        System.assertEquals(1, r.meetings.size(), 'la fila sin url se descarta');
        System.assertEquals('bot_baddate', r.meetings[0].id);
        System.assertEquals(null, r.meetings[0].startTime, 'una fecha ilegible deja la reunion sin fecha');
        System.assertEquals(true, none.meetings.isEmpty());
    }

    @isTest
    static void theWholePageComesBackOrderedSoTheUiCanFilterIt() {
        List<String> rows = new List<String>();
        for (Integer i = 0; i < 6; i++) {
            rows.add('{"id":"bot_' + i + '","url":"https://app.test.veleiro.local/a/partner-portal/meetings/bot_' + i + '/",' +
                     '"title":"R' + i + '","status":"done","start_time":"2026-0' + (i + 1) + '-01T15:00:00+00:00"}');
        }
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.meetingsBody = '{"data":[' + String.join(rows, ',') + '],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);
        Account a = newAccount('org_test');

        Test.startTest();
        VeleiroMeetingService.MeetingList r = VeleiroMeetingService.getForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(6, r.meetings.size(), 'el recorte lo hace el componente, no el servicio');
        System.assertEquals(6, r.total);
        System.assertEquals('bot_5', r.meetings[0].id, 'mas reciente primero');
        System.assertEquals('bot_0', r.meetings[5].id);
    }

    @isTest
    static void theTranscriptComesBackWithItsParticipants() {
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        VeleiroMeetingService.Transcript t = VeleiroMeetingService.getTranscript('bot_new');
        Test.stopTest();

        System.assertEquals('meeting_bot', t.source);
        System.assertEquals(true, t.text.contains('Ana: Hola'));
        System.assertEquals(2, t.participants.size());
        System.assertEquals('Ana', t.participants[0].name);
        System.assertEquals(false, t.truncated);
        System.assertEquals(true, t.reachable);
    }

    @isTest
    static void aHugeTranscriptIsCutBeforeItCrossesToTheBrowser() {
        VeleiroMeetingService.maxTranscriptChars = 40;
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.transcriptBody = '{"data":{"id":"trn_1","meeting_id":"bot_new","source":"upload","text":"' +
            'x'.repeat(500) + '","participants":[]}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroMeetingService.Transcript t = VeleiroMeetingService.getTranscript('bot_new');
        Test.stopTest();

        System.assertEquals(true, t.truncated, 'el panel es un asomo, no el transcript entero');
        System.assertEquals(40, t.text.length(), 'se corta en el limite y el resto se lee en Veleiro');
    }

    @isTest
    static void aTranscriptWithoutScopeSaysSoToo() {
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 403;
        mock.overrideBody = '{"error":{"code":"insufficient_scope","message":"nope"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        VeleiroMeetingService.Transcript t = VeleiroMeetingService.getTranscript('bot_new');
        VeleiroMeetingService.Transcript empty = VeleiroMeetingService.getTranscript('  ');
        Test.stopTest();

        System.assertEquals(true, t.scopeMissing);
        System.assertEquals(null, empty.text, 'sin id no se pregunta');
    }
}
