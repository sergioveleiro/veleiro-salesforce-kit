/**
 * Vinculacion masiva al instalar el kit en una org con historia: cuentas en Salesforce y
 * clients en Veleiro creados antes, sin relacion entre si.
 *
 * La lista arranca por los CLIENTS de Veleiro sin vincular (decenas), no por los Accounts
 * (pueden ser miles): para cada client se sugieren los Accounts que se le parecen y el
 * usuario elige, o busca otro a mano. Vincular solo escribe Veleiro_Client_Id__c: sin
 * callouts, asi que cientos de filas caben en una transaccion. El sf_account_id del lado
 * de Veleiro se escribe en el siguiente sync de esa cuenta.
 */
public with sharing class VeleiroLinkController {

    public class AccountOption {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String website;
        @AuraEnabled public String reason;       // por que se sugiere
        @AuraEnabled public String confidence;   // high | medium | weak
    }

    public class ClientRow {
        @AuraEnabled public String clientId;
        @AuraEnabled public String clientName;
        @AuraEnabled public String clientWebsite;
        @AuraEnabled public String veleiroUrl;
        @AuraEnabled public List<AccountOption> options = new List<AccountOption>();
        // Mejor sugerencia (la que el LWC preselecciona); null si no hay ninguna.
        @AuraEnabled public Id suggestedAccountId;
        @AuraEnabled public String suggestedReason;
        @AuraEnabled public String confidence;
    }

    public class Overview {
        @AuraEnabled public List<ClientRow> rows = new List<ClientRow>();
        @AuraEnabled public Integer clientsTotal = 0;
        @AuraEnabled public Integer clientsUnlinked = 0;
        @AuraEnabled public Integer accountsUnlinked = 0;
        @AuraEnabled public Integer accountsLinked = 0;
        @AuraEnabled public Boolean truncated = false; // demasiados Accounts para cruzar
    }

    @TestVisible private static Integer maxAccounts = 20000;
    private static final Integer MAX_OPTIONS = 5;

    // Todos los clients de Veleiro sin vincular, cada uno con sus Accounts candidatos.
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

        List<Account> unlinked = [
            SELECT Id, Name, Website FROM Account
            WHERE Veleiro_Client_Id__c = null
            ORDER BY Name
            LIMIT 20001
        ];
        o.accountsUnlinked = unlinked.size();
        if (unlinked.size() > maxAccounts) {
            o.truncated = true;
            unlinked = new List<Account>();
        }

        // Indices para no recorrer todas las cuentas por cada client.
        Map<String, List<Account>> byDomain = new Map<String, List<Account>>();
        Map<String, List<Account>> byName = new Map<String, List<Account>>();
        Map<String, List<Account>> byFirstWord = new Map<String, List<Account>>();
        for (Account a : unlinked) {
            addTo(byDomain, VeleiroClientMatcher.domainOf(a.Website), a);
            String n = VeleiroClientMatcher.normalizeName(a.Name);
            addTo(byName, n, a);
            if (String.isNotBlank(n)) addTo(byFirstWord, n.split(' ')[0], a);
        }

        for (Object obj : clients) {
            Map<String, Object> c = (Map<String, Object>) obj;
            if (c.get('is_archived') == true) continue;
            String clientId = String.valueOf(c.get('id'));
            if (linkedClientIds.contains(clientId)) continue;
            o.clientsUnlinked++;

            Map<String, Object> af = (c.get('additional_fields') instanceof Map<String, Object>)
                ? (Map<String, Object>) c.get('additional_fields') : new Map<String, Object>();

            ClientRow row = new ClientRow();
            row.clientId = clientId;
            row.clientName = String.valueOf(c.get('name'));
            row.clientWebsite = str(af.get('sf_website'));
            row.veleiroUrl = VeleiroApiClient.appBaseUrl() + '/a/partner-portal/organizations/' + clientId;

            Map<Id, AccountOption> found = new Map<Id, AccountOption>();
            // 1. El client ya trae un id de Salesforce.
            String sfId = str(af.get('sf_account_id'));
            if (String.isNotBlank(sfId)) {
                for (Account a : unlinked) {
                    if (String.valueOf(a.Id).substring(0, 15) == sfId.left(15)) {
                        put(found, a, 'Carries this Salesforce Account id', VeleiroClientMatcher.HIGH);
                    }
                }
            }
            // 2. Mismo dominio.
            String clientDomain = VeleiroClientMatcher.domainOf(row.clientWebsite);
            if (String.isNotBlank(clientDomain)) {
                for (Account a : get(byDomain, clientDomain)) {
                    put(found, a, 'Same website domain (' + clientDomain + ')', VeleiroClientMatcher.HIGH);
                }
            }
            // 3. Mismo nombre normalizado.
            String clientName = VeleiroClientMatcher.normalizeName(row.clientName);
            for (Account a : get(byName, clientName)) {
                put(found, a, 'Same name', VeleiroClientMatcher.MEDIUM);
            }
            // 4. Parecidos: misma primera palabra o un nombre contiene al otro.
            if (String.isNotBlank(clientName)) {
                for (Account a : get(byFirstWord, clientName.split(' ')[0])) {
                    put(found, a, 'Similar name', VeleiroClientMatcher.WEAK);
                }
                for (Account a : unlinked) {
                    if (found.size() >= MAX_OPTIONS * 3) break;
                    String an = VeleiroClientMatcher.normalizeName(a.Name);
                    if (String.isNotBlank(an) && an != clientName
                        && (an.contains(clientName) || clientName.contains(an))) {
                        put(found, a, 'Similar name', VeleiroClientMatcher.WEAK);
                    }
                }
            }

            row.options = rank(found.values());
            if (!row.options.isEmpty()) {
                AccountOption best = row.options[0];
                // Solo se preselecciona lo fuerte; lo demas el usuario lo elige.
                if (best.confidence != VeleiroClientMatcher.WEAK) {
                    row.suggestedAccountId = best.accountId;
                }
                row.suggestedReason = best.reason;
                row.confidence = best.confidence;
            }
            o.rows.add(row);
        }

        // Los que tienen sugerencia fuerte primero; los que no tienen ninguna, al final.
        List<ClientRow> sorted = new List<ClientRow>();
        for (ClientRow r : o.rows) if (r.confidence == VeleiroClientMatcher.HIGH) sorted.add(r);
        for (ClientRow r : o.rows) if (r.confidence == VeleiroClientMatcher.MEDIUM) sorted.add(r);
        for (ClientRow r : o.rows) if (r.confidence == VeleiroClientMatcher.WEAK) sorted.add(r);
        for (ClientRow r : o.rows) if (r.confidence == null) sorted.add(r);
        o.rows = sorted;
        return o;
    }

    // Busqueda manual de Accounts sin vincular (para cuando ninguna sugerencia sirve).
    @AuraEnabled(cacheable=true)
    public static List<AccountOption> searchAccounts(String term) {
        List<AccountOption> out = new List<AccountOption>();
        if (String.isBlank(term) || term.trim().length() < 2) return out;
        String pattern = '%' + String.escapeSingleQuotes(term.trim()) + '%';
        for (Account a : [
            SELECT Id, Name, Website FROM Account
            WHERE Veleiro_Client_Id__c = null AND Name LIKE :pattern
            ORDER BY Name LIMIT 20
        ]) {
            AccountOption op = new AccountOption();
            op.accountId = a.Id;
            op.name = a.Name;
            op.website = a.Website;
            op.reason = 'Found by search';
            op.confidence = VeleiroClientMatcher.WEAK;
            out.add(op);
        }
        return out;
    }

    // Aplica las vinculaciones elegidas. pairsJson: [{"accountId":"001...","clientId":"org_..."}]
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
            if (String.isBlank(accountId) || String.isBlank(clientId)
                || accountId == 'null' || clientId == 'null') continue;
            if (alreadyUsed.contains(clientId)) continue; // un client, un Account
            alreadyUsed.add(clientId);
            toUpdate.put(accountId, new Account(Id = accountId, Veleiro_Client_Id__c = clientId, Veleiro_Version__c = null));
        }
        if (!toUpdate.isEmpty()) update toUpdate.values();
        return toUpdate.size();
    }

    // ---- helpers ----

    private static void addTo(Map<String, List<Account>> idx, String key, Account a) {
        if (String.isBlank(key)) return;
        if (!idx.containsKey(key)) idx.put(key, new List<Account>());
        idx.get(key).add(a);
    }

    private static List<Account> get(Map<String, List<Account>> idx, String key) {
        if (String.isBlank(key) || !idx.containsKey(key)) return new List<Account>();
        return idx.get(key);
    }

    // Guarda la mejor razon por Account (no pisa una coincidencia fuerte con una debil).
    private static void put(Map<Id, AccountOption> found, Account a, String reason, String confidence) {
        AccountOption existing = found.get(a.Id);
        if (existing != null && rank(existing.confidence) <= rank(confidence)) return;
        AccountOption op = new AccountOption();
        op.accountId = a.Id;
        op.name = a.Name;
        op.website = a.Website;
        op.reason = reason;
        op.confidence = confidence;
        found.put(a.Id, op);
    }

    private static Integer rank(String confidence) {
        if (confidence == VeleiroClientMatcher.HIGH) return 0;
        if (confidence == VeleiroClientMatcher.MEDIUM) return 1;
        return 2;
    }

    private static List<AccountOption> rank(List<AccountOption> options) {
        List<AccountOption> out = new List<AccountOption>();
        for (Integer level = 0; level <= 2; level++) {
            for (AccountOption op : options) {
                if (rank(op.confidence) == level && out.size() < MAX_OPTIONS) out.add(op);
            }
        }
        return out;
    }

    private static String str(Object o) { return (o == null) ? null : String.valueOf(o); }
}
