/**
 * Busca en Veleiro un client que ya represente a un Account, para vincular en vez de duplicar.
 *
 * Caso real: el partner ya tenia clientes en Veleiro y cuentas en Salesforce antes de instalar
 * el kit. Sin esto, el primer sync crea un client nuevo y quedan dos en Veleiro.
 *
 * La API no busca por nombre ni por dominio (solo filtra por fecha), asi que se lista y se
 * compara aca. El listado tampoco devuelve website_url: el dominio solo se puede comparar
 * cuando el client trae sf_website en additional_fields (lo escribe el mapeo por defecto).
 *
 * Confianza:
 *   HIGH   - additional_fields.sf_account_id es este Account, o mismo dominio -> vincular solo.
 *   MEDIUM - mismo nombre normalizado -> siempre preguntarle al usuario.
 */
public with sharing class VeleiroClientMatcher {

    public static final String HIGH = 'high';
    public static final String MEDIUM = 'medium';
    // Tope de clients revisados: mas alla de esto la busqueda no es confiable y se avisa.
    @TestVisible private static Integer maxClients = 2000;

    public class Candidate {
        @AuraEnabled public String clientId;
        @AuraEnabled public String name;
        @AuraEnabled public String reason;      // texto para el usuario
        @AuraEnabled public String confidence;  // high | medium
        @AuraEnabled public String veleiroUrl;
        @AuraEnabled public Boolean linkedToOtherAccount;
    }

    public class MatchResult {
        @AuraEnabled public List<Candidate> candidates = new List<Candidate>();
        @AuraEnabled public Boolean truncated = false; // se corto el listado -> puede faltar alguno
    }

    // Candidatos para un Account que todavia no esta vinculado (callout).
    public static MatchResult forAccount(Id accountId) {
        Account a = [SELECT Id, Name, Website, Veleiro_Client_Id__c FROM Account WHERE Id = :accountId LIMIT 1];
        MatchResult r = new MatchResult();

        List<Object> clients = VeleiroApiClient.listAll('/clients', null);
        if (clients.size() > maxClients) {
            r.truncated = true;
            return r; // demasiados para comparar con confianza: mejor no sugerir nada
        }

        // Ids de clients ya usados por otras cuentas: se muestran, pero avisando.
        Set<String> takenElsewhere = new Set<String>();
        for (Account other : [
            SELECT Veleiro_Client_Id__c FROM Account
            WHERE Veleiro_Client_Id__c != null AND Id != :a.Id
        ]) {
            takenElsewhere.add(other.Veleiro_Client_Id__c);
        }

        for (Object o : clients) {
            Candidate cand = evaluate(a, (Map<String, Object>) o, takenElsewhere);
            if (cand != null) r.candidates.add(cand);
        }
        // Primero las coincidencias fuertes y sin dueño.
        List<Candidate> sorted = new List<Candidate>();
        for (Candidate c : r.candidates) if (c.confidence == HIGH && !c.linkedToOtherAccount) sorted.add(c);
        for (Candidate c : r.candidates) if (!(c.confidence == HIGH && !c.linkedToOtherAccount)) sorted.add(c);
        r.candidates = sorted;
        return r;
    }

    // Un client contra un Account: devuelve el candidato o null si no se parecen.
    public static Candidate evaluate(Account a, Map<String, Object> c, Set<String> takenElsewhere) {
        if (c.get('is_archived') == true) return null;
        Map<String, Object> af = (c.get('additional_fields') instanceof Map<String, Object>)
            ? (Map<String, Object>) c.get('additional_fields') : new Map<String, Object>();

        String accountDomain = domainOf(a.Website);
        String accountName = normalizeName(a.Name);
        String accountId15 = String.valueOf(a.Id).substring(0, 15);
        String linkedSfId = str(af.get('sf_account_id'));
        String clientDomain = domainOf(str(af.get('sf_website')));

        String reason;
        String confidence;
        if (String.isNotBlank(linkedSfId) && linkedSfId.length() >= 15
            && linkedSfId.substring(0, 15) == accountId15) {
            reason = 'Already carries this Salesforce Account id';
            confidence = HIGH;
        } else if (String.isNotBlank(accountDomain) && accountDomain == clientDomain) {
            reason = 'Same website domain (' + accountDomain + ')';
            confidence = HIGH;
        } else if (String.isNotBlank(accountName) && accountName == normalizeName(str(c.get('name')))) {
            reason = 'Same name';
            confidence = MEDIUM;
        } else {
            return null;
        }

        Candidate cand = new Candidate();
        cand.clientId = str(c.get('id'));
        cand.name = str(c.get('name'));
        cand.reason = reason;
        cand.confidence = confidence;
        cand.linkedToOtherAccount = takenElsewhere != null && takenElsewhere.contains(cand.clientId);
        cand.veleiroUrl = VeleiroApiClient.appBaseUrl() + '/a/partner-portal/organizations/' + cand.clientId;
        return cand;
    }

    // Coincidencia lo bastante fuerte para vincular sin preguntar (flows y auto-sync).
    public static Candidate autoLinkable(MatchResult r) {
        if (r == null || r.truncated) return null;
        for (Candidate c : r.candidates) {
            if (c.confidence == HIGH && !c.linkedToOtherAccount) return c;
        }
        return null;
    }

    // 'https://www.Acme.com/es' -> 'acme.com'. Null si no hay dominio utilizable.
    @TestVisible
    private static String domainOf(String url) {
        if (String.isBlank(url)) return null;
        String s = url.trim().toLowerCase();
        s = s.replaceFirst('^https?://', '');
        s = s.split('/')[0].split('\\?')[0];
        if (s.startsWith('www.')) s = s.substring(4);
        s = s.split(':')[0];
        return s.contains('.') ? s : null;
    }

    // 'Acme S.A. de C.V.' -> 'acme'. Quita sufijos societarios y puntuacion.
    @TestVisible
    private static String normalizeName(String raw) {
        if (String.isBlank(raw)) return null;
        String s = raw.trim().toLowerCase();
        s = s.replaceAll('[^a-z0-9 ]', ' ');
        for (String suffix : new List<String>{
            'sa de cv', 's a de c v', 'sas', 's a s', 'sa', 's a', 'ltda', 'limitada',
            'inc', 'llc', 'ltd', 'corp', 'corporation', 'company', 'co', 'gmbh', 'bv', 'srl', 'spa'
        }) {
            s = s.replaceAll('(^| )' + suffix + '( |$)', ' ');
        }
        s = s.replaceAll(' +', ' ').trim();
        return String.isBlank(s) ? null : s;
    }

    private static String str(Object o) { return (o == null) ? null : String.valueOf(o); }
}
