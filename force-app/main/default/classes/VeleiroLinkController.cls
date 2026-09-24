/**
 * Vinculacion masiva al instalar el kit en una org con historia: cuentas en Salesforce y
 * clients en Veleiro creados antes, sin ninguna relacion entre si.
 *
 * Trae los clients de Veleiro (un solo callout) y los cruza contra los Accounts sin vincular.
 * El usuario revisa y aplica; vincular solo escribe Veleiro_Client_Id__c (sin callouts, asi
 * que cientos de registros se resuelven en una transaccion). El sf_account_id del lado de
 * Veleiro se escribe en el siguiente sync de cada cuenta.
 */
public with sharing class VeleiroLinkController {

    public class Suggestion {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountWebsite;
        @AuraEnabled public String clientId;
        @AuraEnabled public String clientName;
        @AuraEnabled public String reason;
        @AuraEnabled public String confidence;      // high | medium
        @AuraEnabled public Boolean linkedToOtherAccount;
        @AuraEnabled public String veleiroUrl;
        // Clave de fila para el datatable del LWC.
        @AuraEnabled public String key;
    }

    public class Overview {
        @AuraEnabled public List<Suggestion> suggestions = new List<Suggestion>();
        @AuraEnabled public Integer accountsUnlinked = 0;
        @AuraEnabled public Integer clientsTotal = 0;
        @AuraEnabled public Integer clientsUnlinked = 0;   // clients sin Account en Salesforce
        @AuraEnabled public Integer accountsLinked = 0;
        @AuraEnabled public Boolean truncated = false;     // se corto el listado de Accounts
    }

    // Tope de Accounts revisados por corrida (el cruce es en memoria).
    @TestVisible private static Integer maxAccounts = 2000;

    @AuraEnabled
    public static Overview getSuggestions() {
        Overview o = new Overview();
        List<Object> clients = VeleiroApiClient.listAll('/clients', null);
        o.clientsTotal = clients.size();

        Set<String> linkedClientIds = new Set<String>();
        for (Account a : [SELECT Veleiro_Client_Id__c FROM Account WHERE Veleiro_Client_Id__c != null]) {
            linkedClientIds.add(a.Veleiro_Client_Id__c);
        }
        o.accountsLinked = linkedClientIds.size();
        o.clientsUnlinked = 0;
        for (Object c : clients) {
            Map<String, Object> m = (Map<String, Object>) c;
            if (m.get('is_archived') != true && !linkedClientIds.contains(String.valueOf(m.get('id')))) {
                o.clientsUnlinked++;
            }
        }

        List<Account> unlinked = [
            SELECT Id, Name, Website FROM Account
            WHERE Veleiro_Client_Id__c = null
            ORDER BY Name
            LIMIT 2001
        ];
        if (unlinked.size() > maxAccounts) {
            o.truncated = true;
            unlinked = new List<Account>(); // sin cruce parcial: seria confuso
        }
        o.accountsUnlinked = unlinked.size();

        // Un client no puede sugerirse a dos Accounts a la vez: gana el de mayor confianza.
        Map<String, Suggestion> bestByClient = new Map<String, Suggestion>();
        for (Account a : unlinked) {
            for (Object c : clients) {
                VeleiroClientMatcher.Candidate cand =
                    VeleiroClientMatcher.evaluate(a, (Map<String, Object>) c, linkedClientIds);
                if (cand == null || cand.linkedToOtherAccount) continue;

                Suggestion s = new Suggestion();
                s.accountId = a.Id;
                s.accountName = a.Name;
                s.accountWebsite = a.Website;
                s.clientId = cand.clientId;
                s.clientName = cand.name;
                s.reason = cand.reason;
                s.confidence = cand.confidence;
                s.linkedToOtherAccount = false;
                s.veleiroUrl = cand.veleiroUrl;
                s.key = a.Id + '|' + cand.clientId;

                Suggestion current = bestByClient.get(s.clientId);
                if (current == null || (current.confidence == VeleiroClientMatcher.MEDIUM
                                        && s.confidence == VeleiroClientMatcher.HIGH)) {
                    bestByClient.put(s.clientId, s);
                }
            }
        }

        // Fuertes primero: son las que conviene aplicar en bloque.
        for (Suggestion s : bestByClient.values()) {
            if (s.confidence == VeleiroClientMatcher.HIGH) o.suggestions.add(s);
        }
        for (Suggestion s : bestByClient.values()) {
            if (s.confidence != VeleiroClientMatcher.HIGH) o.suggestions.add(s);
        }
        return o;
    }

    // Aplica las vinculaciones elegidas. pairsJson: [{"accountId":"001...","clientId":"org_..."}]
    // Sin callouts: solo escribe el id en el Account (el sync posterior completa Veleiro).
    @AuraEnabled
    public static Integer linkAll(String pairsJson) {
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(pairsJson);
        Map<Id, Account> toUpdate = new Map<Id, Account>();
        Set<String> alreadyUsed = new Set<String>();
        for (Account a : [SELECT Veleiro_Client_Id__c FROM Account WHERE Veleiro_Client_Id__c != null]) {
            alreadyUsed.add(a.Veleiro_Client_Id__c);
        }

        for (Object o : rows) {
            Map<String, Object> row = (Map<String, Object>) o;
            String accountId = String.valueOf(row.get('accountId'));
            String clientId = String.valueOf(row.get('clientId'));
            if (String.isBlank(accountId) || String.isBlank(clientId)) continue;
            // Nunca dos Accounts sobre el mismo client.
            if (alreadyUsed.contains(clientId)) continue;
            alreadyUsed.add(clientId);
            toUpdate.put(accountId, new Account(Id = accountId, Veleiro_Client_Id__c = clientId, Veleiro_Version__c = null));
        }
        if (!toUpdate.isEmpty()) update toUpdate.values();
        return toUpdate.size();
    }
}
