/**
 * Trae los clients de la plataforma Veleiro y los refleja como Accounts
 * en el CRM del partner (upsert por Veleiro_Client_Id__c).
 * Read-only contra Veleiro; solo escribe en el CRM local.
 */
public with sharing class VeleiroSync {

    // Sincroniza clients de Veleiro -> Accounts. Devuelve cuantos proceso.
    public static Integer syncClients() {
        List<Object> clients = VeleiroApiClient.listAll('/clients', new Map<String, String>());
        List<Account> toUpsert = new List<Account>();

        for (Object o : clients) {
            Map<String, Object> c = (Map<String, Object>) o;
            Account a = new Account();
            a.Name = (String) c.get('name');
            a.Veleiro_Client_Id__c = (String) c.get('id');
            a.Veleiro_Slug__c = (String) c.get('slug');
            if (c.get('version') != null) {
                a.Veleiro_Version__c = Decimal.valueOf(String.valueOf(c.get('version')));
            }
            Object af = c.get('additional_fields');
            a.Veleiro_Additional_Fields__c = (af != null) ? JSON.serializePretty(af) : null;
            toUpsert.add(a);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert Veleiro_Client_Id__c; // upsert por external id
        }
        System.debug('VeleiroSync.syncClients -> ' + toUpsert.size() + ' clients');
        return toUpsert.size();
    }

    /**
     * PULL Veleiro -> Salesforce para el job programado (direccion bidirectional o veleiro_to_sf).
     * Solo actualiza un Account cuando Veleiro tiene una VERSION MAS NUEVA que la guardada
     * en SF -> esto previene ciclos (no re-aplica lo que ya teniamos ni re-dispara un push).
     * Devuelve cuantos Accounts actualizo.
     */
    // Tope por corrida: una org grande no puede procesarse de un solo golpe sin pasarse de
    // los limites de Salesforce (50k registros por consulta, 10k por DML). Lo que sobra
    // entra en la corrida siguiente.
    @TestVisible private static Integer maxPerRun = 2000;

    public static Integer pullUpdates() {
        if (!VeleiroSyncConfig.pullEnabled()) return 0; // direccion sf_to_veleiro -> no jala

        Map<String, Map<String, Object>> byId = new Map<String, Map<String, Object>>();
        for (Object o : VeleiroApiClient.listAll('/clients', new Map<String, String>())) {
            Map<String, Object> c = (Map<String, Object>) o;
            byId.put((String) c.get('id'), c);
        }

        Boolean writesName = VeleiroSyncConfig.pullWritesName();
        List<Account> toUpdate = new List<Account>();
        for (Account a : [
            SELECT Id, Name, Veleiro_Client_Id__c, Veleiro_Version__c, Veleiro_Additional_Fields__c
            FROM Account WHERE Veleiro_Client_Id__c != null
            ORDER BY LastModifiedDate ASC
            LIMIT 5000
        ]) {
            Map<String, Object> c = byId.get(a.Veleiro_Client_Id__c);
            if (c == null) continue;
            Integer vVer = (c.get('version') != null) ? Integer.valueOf(String.valueOf(c.get('version'))) : null;
            Integer sfVer = (a.Veleiro_Version__c != null) ? Integer.valueOf(a.Veleiro_Version__c) : null;

            // anti-ciclo: solo si Veleiro esta MAS adelantado que lo que ya tenemos
            if (vVer != null && (sfVer == null || vVer > sfVer)) {
                // El nombre de la cuenta es del cliente: solo se pisa si lo autorizo.
                if (writesName) a.Name = (String) c.get('name');
                Object af = c.get('additional_fields');
                a.Veleiro_Additional_Fields__c = (af != null) ? JSON.serializePretty(af) : null;
                a.Veleiro_Version__c = vVer;
                toUpdate.add(a);
            }
            if (toUpdate.size() >= maxPerRun) break; // el resto, en la proxima corrida
        }

        Integer updated = 0;
        if (!toUpdate.isEmpty()) {
            // Parcial a proposito: una regla de validacion del cliente sobre UNA cuenta no
            // debe tumbar el lote completo.
            List<Database.SaveResult> results = Database.update(toUpdate, false);
            String firstError;
            Integer failed = 0;
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) { updated++; continue; }
                failed++;
                if (firstError == null && !sr.getErrors().isEmpty()) firstError = sr.getErrors()[0].getMessage();
            }
            if (failed > 0) {
                VeleiroSyncConfig.recordError('Pull: ' + failed + ' account(s) rejected by Salesforce. First: ' + firstError);
            }
        }
        System.debug('VeleiroSync.pullUpdates -> ' + updated + ' accounts actualizados');
        return updated;
    }
}
