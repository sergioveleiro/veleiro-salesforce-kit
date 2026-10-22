/**
 * Veleiro Link a escala de org real.
 *
 * Un cliente reporto "Apex CPU time limit exceeded" al abrir la pestana. No era el SOQL: era el
 * emparejado, que recorria TODOS los registros de Salesforce por CADA recurso de Veleiro, y en
 * ese recorrido volvia a normalizar cada nombre (21 regex por nombre). Con unos miles de cuentas
 * y unas decenas de clientes, eso son millones de operaciones de texto en una sola transaccion.
 *
 * Este test existe para que no vuelva a pasar sin que nadie se entere: mide el CPU de verdad.
 * No afirma que sea rapido, afirma que CABE: el limite sincrono son 10.000 ms y aqui el techo es
 * mucho mas bajo, porque en la org del cliente ademas corre todo lo suyo.
 */
@isTest
private class VeleiroLinkScaleTest {

    private static final Integer ACCOUNTS = 1500;
    private static final Integer CLIENTS = 150;
    // Presupuesto: si el escaneo pasa de aqui, en una org mas grande truena.
    private static final Integer CPU_BUDGET_MS = 5000;

    @testSetup
    static void setup() {
        VeleiroApiMock.seedConfig();
        insert new Veleiro_Field_Mapping__c(
            Name = 'Account Name', SObject__c = 'Account', Veleiro_Entity__c = 'client',
            SF_Field__c = 'Name', Veleiro_Target__c = 'name', Target_Type__c = 'Standard', Active__c = true
        );
        insert new Veleiro_Field_Mapping__c(
            Name = 'Account Website', SObject__c = 'Account', Veleiro_Entity__c = 'client',
            SF_Field__c = 'Website', Veleiro_Target__c = 'sf_website', Target_Type__c = 'Additional', Active__c = true
        );

        // Nombres como los de una org real: repetidos, con sufijos societarios y palabras comunes.
        List<String> stems = new List<String>{
            'Grupo Industrial', 'Comercializadora', 'Distribuidora Nacional', 'Servicios Integrales',
            'Constructora', 'Transportes', 'Alimentos', 'Tecnologia Aplicada', 'Consultores Asociados',
            'Inmobiliaria'
        };
        List<String> suffixes = new List<String>{ 'SA de CV', 'S.A.S.', 'Ltda', 'Inc', '' };
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < ACCOUNTS; i++) {
            String name = stems[Math.mod(i, stems.size())] + ' ' + i + ' ' + suffixes[Math.mod(i, suffixes.size())];
            accs.add(new Account(Name = name.trim(), Website = 'https://www.empresa' + i + '.com'));
        }
        insert accs;
    }

    private static void mockClients() {
        List<String> rows = new List<String>();
        for (Integer i = 0; i < CLIENTS; i++) {
            // La mitad se parecen a cuentas existentes; la otra mitad no, que es el caso caro:
            // sin coincidencia, el recorrido completo no se cortaba nunca.
            String name = Math.mod(i, 2) == 0
                ? 'Comercializadora ' + i + ' SA de CV'
                : 'Cliente Sin Match ' + i;
            rows.add('{"id":"org_' + i + '","name":"' + name + '","additional_fields":{}}');
        }
        VeleiroApiMock mock = new VeleiroApiMock();
        mock.clientsBody = '{"data":[' + String.join(rows, ',') + '],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);
    }

    @isTest
    static void theScanFitsInOneTransaction() {
        mockClients();

        Test.startTest();
        Integer before = Limits.getCpuTime();
        VeleiroLinkController.Overview o = VeleiroLinkController.getSuggestions('Account', 'client');
        Integer spent = Limits.getCpuTime() - before;
        Test.stopTest();

        System.debug(LoggingLevel.ERROR, 'CPU del escaneo: ' + spent + ' ms con ' +
                     ACCOUNTS + ' cuentas x ' + CLIENTS + ' clientes');
        System.assertEquals(CLIENTS, o.rows.size(), 'se listan todos los clientes sin vincular');
        System.assert(spent < CPU_BUDGET_MS,
            'el escaneo gasto ' + spent + ' ms de CPU (presupuesto ' + CPU_BUDGET_MS +
            '). En la org del cliente esto es un "Apex CPU time limit exceeded".');
    }
}
