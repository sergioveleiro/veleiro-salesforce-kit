@isTest
private class VeleiroBulkSendQueueableTest {

    // Con namespace el objeto se llama veleiro__Veleiro_Field_Mapping__c: se lee del describe,
    // nunca del literal, o el test pasa aqui y truena al construir el paquete administrado.
    private static final String KIT_OBJECT = String.valueOf(Veleiro_Field_Mapping__c.SObjectType);

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
        insert new Veleiro_Field_Mapping__c(
            Name = 'Account Name', SObject__c = 'Account', Veleiro_Entity__c = 'client',
            SF_Field__c = 'Name', Veleiro_Target__c = 'name', Target_Type__c = 'Standard', Active__c = true
        );
    }

    // El mock de siempre devuelve el mismo id para todo POST, y Veleiro_Client_Id__c es unico:
    // para probar un lote de verdad hace falta que cada create traiga su propio id.
    private class DistinctIdsMock implements HttpCalloutMock {
        Integer created = 0;
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            created++;
            res.setStatusCode(201);
            res.setBody('{"data":{"id":"org_' + created + '","name":"C' + created + '","version":1}}');
            return res;
        }
    }

    private static List<Account> accounts(Integer howMany) {
        List<Account> out = new List<Account>();
        for (Integer i = 0; i < howMany; i++) out.add(new Account(Name = 'Cuenta ' + i));
        insert out;
        return out;
    }

    private static List<Id> idsOf(List<Account> accs) {
        List<Id> ids = new List<Id>();
        for (Account a : accs) ids.add(a.Id);
        return ids;
    }

    // Account -> client cabe por decenas en una transaccion: todos los callouts, un solo DML.
    @isTest
    static void sendsEveryAccountInOneTransaction() {
        List<Account> accs = accounts(5);
        Test.setMock(HttpCalloutMock.class, new DistinctIdsMock());

        Test.startTest();
        System.enqueueJob(new VeleiroBulkSendQueueable(idsOf(accs), 'client', null));
        Test.stopTest();

        Integer linked = [SELECT COUNT() FROM Account WHERE Veleiro_Client_Id__c != null];
        System.assertEquals(5, linked, 'las cinco quedaron creadas y vinculadas en una sola corrida');
        for (Account a : [SELECT Veleiro_Version__c FROM Account WHERE Veleiro_Client_Id__c != null]) {
            System.assertEquals(1, a.Veleiro_Version__c, 'y con la version que devolvio Veleiro');
        }
    }

    // Si el usuario eligio un client que ya existe, se vincula a ese en vez de crear otro.
    @isTest
    static void linksToTheChosenClientInsteadOfCreating() {
        List<Account> accs = accounts(1);
        VeleiroApiMock mock = new VeleiroApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new VeleiroBulkSendQueueable(
            idsOf(accs), 'client', new Map<Id, String>{ accs[0].Id => 'org_test' }));
        Test.stopTest();

        Account after = [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :accs[0].Id];
        System.assertEquals('org_test', after.Veleiro_Client_Id__c, 'se vinculo al elegido');
        System.assertEquals(null, mock.lastPostBody, 'y no se creo nada nuevo en Veleiro');
    }

    /**
     * Si Veleiro creo el client pero Salesforce no pudo guardar el id, eso NO puede quedar en
     * silencio: el error tiene que decir el id para poder rescatarlo. Aqui se provoca con el
     * mock de siempre, que devuelve el mismo id para las dos cuentas y choca con la unicidad.
     */
    @isTest
    static void aFailedSaveReportsTheClientVeleiroAlreadyCreated() {
        List<Account> accs = accounts(2);
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        System.enqueueJob(new VeleiroBulkSendQueueable(idsOf(accs), 'client', null));
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Veleiro_Client_Id__c = 'org_test'],
            'el id unico solo lo puede tener una');
        String err = Veleiro_Config__c.getOrgDefaults().Last_Sync_Error__c;
        System.assert(err != null && err.contains('org_test'),
            'el error dice que el client existe en Veleiro: ' + err);
    }

    // Cualquier otro par va por syncRecord, uno por transaccion (ahi el DML es parte del sync).
    @isTest
    static void anObjectWithoutANativePairGoesOneAtATime() {
        insert new Veleiro_Field_Mapping__c(
            Name = 'Kit Name', SObject__c = KIT_OBJECT, Veleiro_Entity__c = 'client',
            SF_Field__c = 'Name', Veleiro_Target__c = 'name', Target_Type__c = 'Standard', Active__c = true
        );
        List<Veleiro_Field_Mapping__c> records = new List<Veleiro_Field_Mapping__c>();
        for (Integer i = 0; i < 2; i++) {
            records.add(new Veleiro_Field_Mapping__c(
                Name = 'Registro ' + i, SObject__c = 'ZZ_TEST', Veleiro_Entity__c = 'client',
                SF_Field__c = 'Name', Veleiro_Target__c = 'name', Target_Type__c = 'Standard', Active__c = false
            ));
        }
        insert records;
        List<Id> ids = new List<Id>{ records[0].Id, records[1].Id };
        Test.setMock(HttpCalloutMock.class, new VeleiroApiMock());

        Test.startTest();
        System.enqueueJob(new VeleiroBulkSendQueueable(ids, 'client', null));
        Test.stopTest();   // encadenar esta apagado en tests: solo corre el primero

        System.assertEquals(1, [SELECT COUNT() FROM Veleiro_Link__c],
            'el resto sigue en la cadena, no en esta transaccion');
    }

    @isTest
    static void anEmptyBatchDoesNothing() {
        Test.startTest();
        System.enqueueJob(new VeleiroBulkSendQueueable(new List<Id>(), 'client', null));
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Veleiro_Client_Id__c != null]);
    }

    // Un registro que truena no se lleva el lote: los demas se guardan y el error queda anotado.
    @isTest
    static void oneBadRecordDoesNotCostTheBatch() {
        List<Account> accs = accounts(2);
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.overrideStatus = 403;
        mock.overrideBody = '{"error":{"code":"ip_not_allowed"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new VeleiroBulkSendQueueable(idsOf(accs), 'client', null));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Veleiro_Client_Id__c != null]);
        System.assert(String.isNotBlank(Veleiro_Config__c.getOrgDefaults().Last_Sync_Error__c),
            'el fallo queda visible en el panel');
    }
}
