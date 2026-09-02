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
}
