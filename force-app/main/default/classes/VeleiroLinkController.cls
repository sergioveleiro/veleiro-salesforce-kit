/**
 * Vinculacion masiva al instalar el kit en una org con historia: registros en Salesforce y
 * clients/projects en Veleiro creados antes, sin relacion entre si.
 *
 * Lo que manda es el panel de Veleiro Mappings: esta pantalla solo ofrece los pares
 * (objeto -> client|project) que el partner haya mapeado. Sin mapeo no hay nada que vincular.
 *
 * La lista arranca por los recursos de VELEIRO sin vincular (decenas), no por los registros de
 * Salesforce (pueden ser miles): para cada uno se sugieren los registros que se le parecen y el
 * usuario elige, o busca otro con el buscador estandar. Vincular escribe el vinculo (campo
 * propio en Account/Opportunity, Veleiro_Link__c en cualquier otro objeto) sin callouts;
 * "Link and sync" ademas empuja los campos mapeados en segundo plano.
 */
public with sharing class VeleiroLinkController {

    public class Pair {
        @AuraEnabled public String sobjectName;
        @AuraEnabled public String sobjectLabel;
        @AuraEnabled public String entity;       // client | project
        @AuraEnabled public String label;        // 'Account - client'
        @AuraEnabled public String value;        // 'Account|client'
    }

    public class RecordOption {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String website;
        @AuraEnabled public String reason;
        @AuraEnabled public String confidence;   // high | medium | weak
    }

    public class VeleiroRow {
        @AuraEnabled public String veleiroId;
        @AuraEnabled public String veleiroName;
        @AuraEnabled public String veleiroWebsite;
        @AuraEnabled public String veleiroUrl;
        @AuraEnabled public List<RecordOption> options = new List<RecordOption>();
        @AuraEnabled public Id suggestedRecordId;
        @AuraEnabled public String suggestedReason;
        @AuraEnabled public String confidence;
    }

    public class Overview {
        @AuraEnabled public List<Pair> pairs = new List<Pair>();
        @AuraEnabled public String sobjectName;
        @AuraEnabled public String sobjectLabel;
        @AuraEnabled public String entity;
        @AuraEnabled public List<VeleiroRow> rows = new List<VeleiroRow>();
        @AuraEnabled public Integer veleiroUnlinked = 0;
        @AuraEnabled public Integer recordsUnlinked = 0;
        @AuraEnabled public Integer alreadyLinked = 0;
        @AuraEnabled public Boolean truncated = false;
    }

    @TestVisible private static Integer maxRecords = 20000;
    private static final Integer MAX_OPTIONS = 5;

    // Pares configurados en Veleiro Mappings: es lo unico que esta pantalla puede vincular.
    @AuraEnabled(cacheable=true)
    public static List<Pair> getPairs() {
        Map<String, Pair> pairs = new Map<String, Pair>();
        for (AggregateResult ar : [
            SELECT SObject__c so, Veleiro_Entity__c ent
            FROM Veleiro_Field_Mapping__c
            WHERE Active__c = true AND SObject__c != null AND Veleiro_Entity__c != null
            GROUP BY SObject__c, Veleiro_Entity__c
        ]) {
            String so = (String) ar.get('so');
            String ent = (String) ar.get('ent');
            Schema.SObjectType type = Schema.getGlobalDescribe().get(so);
            if (type == null) continue; // el objeto ya no existe en la org

            Pair p = new Pair();
            p.sobjectName = so;
            p.sobjectLabel = type.getDescribe().getLabel();
            p.entity = ent;
            p.label = p.sobjectLabel + ' -> ' + ent;
            p.value = so + '|' + ent;
            pairs.put(p.value, p);
        }
        return pairs.values();
    }

    // Recursos de Veleiro sin vincular para ese par, cada uno con sus registros candidatos.
    @AuraEnabled
    public static Overview getSuggestions(String sobjectName, String entity) {
        Overview o = new Overview();
        o.pairs = getPairs();
        if (o.pairs.isEmpty()) return o; // sin mapeos no hay nada que hacer

        String so = String.isNotBlank(sobjectName) ? sobjectName : o.pairs[0].sobjectName;
        String ent = String.isNotBlank(entity) ? entity : o.pairs[0].entity;
        o.sobjectName = so;
        o.entity = ent;
        Schema.SObjectType type = Schema.getGlobalDescribe().get(so);
        if (type == null || !VeleiroSyncService.hasMappings(so, ent)) return o;
        o.sobjectLabel = type.getDescribe().getLabel();

        List<Object> resources = VeleiroApiClient.listAll(ent == 'client' ? '/clients' : '/projects', null);
        Set<String> linkedVeleiroIds = VeleiroLinkStore.linkedIds(so, ent);
        Set<Id> linkedRecordIds = VeleiroLinkStore.linkedRecords(so, ent);
        o.alreadyLinked = linkedVeleiroIds.size();

        // Campos con los que comparar: el mapeado a 'name' (o Name) y el del sitio web.
        String nameField = mappedField(so, ent, new Set<String>{ 'name' });
        String siteField = mappedField(so, ent, new Set<String>{ 'website_url', 'sf_website', 'website' });
        if (String.isBlank(nameField) && hasField(so, 'Name')) nameField = 'Name';
        if (String.isBlank(siteField) && hasField(so, 'Website')) siteField = 'Website';

        List<SObject> unlinked = new List<SObject>();
        if (String.isNotBlank(nameField)) {
            Set<String> cols = new Set<String>{ 'Id', nameField };
            if (String.isNotBlank(siteField)) cols.add(siteField);
            String soql = 'SELECT ' + String.join(new List<String>(cols), ', ') +
                          ' FROM ' + String.escapeSingleQuotes(so) +
                          ' WHERE Id NOT IN :linkedRecordIds' +
                          ' ORDER BY ' + nameField + ' LIMIT 20001';
            unlinked = Database.query(soql);
        }
        o.recordsUnlinked = unlinked.size();
        if (unlinked.size() > maxRecords) {
            o.truncated = true;
            unlinked = new List<SObject>();
        }

        // Indices para no recorrer todos los registros por cada recurso de Veleiro.
        Map<String, List<SObject>> byDomain = new Map<String, List<SObject>>();
        Map<String, List<SObject>> byName = new Map<String, List<SObject>>();
        Map<String, List<SObject>> byFirstWord = new Map<String, List<SObject>>();
        for (SObject r : unlinked) {
            if (String.isNotBlank(siteField)) addTo(byDomain, VeleiroClientMatcher.domainOf(str(r.get(siteField))), r);
            String n = VeleiroClientMatcher.normalizeName(str(r.get(nameField)));
            addTo(byName, n, r);
            if (String.isNotBlank(n)) addTo(byFirstWord, n.split(' ')[0], r);
        }

        for (Object obj : resources) {
            Map<String, Object> c = (Map<String, Object>) obj;
            if (c.get('is_archived') == true) continue;
            String veleiroId = str(c.get('id'));
            if (linkedVeleiroIds.contains(veleiroId)) continue;
            o.veleiroUnlinked++;

            Map<String, Object> af = (c.get('additional_fields') instanceof Map<String, Object>)
                ? (Map<String, Object>) c.get('additional_fields') : new Map<String, Object>();

            VeleiroRow row = new VeleiroRow();
            row.veleiroId = veleiroId;
            row.veleiroName = str(c.get('name'));
            row.veleiroWebsite = str(af.get('sf_website'));
            row.veleiroUrl = VeleiroApiClient.appBaseUrl()
                + (ent == 'client' ? '/a/partner-portal/organizations/' : '/a/partner-portal/projects/')
                + veleiroId;

            Map<Id, RecordOption> found = new Map<Id, RecordOption>();
            // 1. El recurso ya trae el id del registro de Salesforce.
            String sfId = str(af.get('sf_record_id'));
            if (String.isBlank(sfId)) sfId = str(af.get(ent == 'client' ? 'sf_account_id' : 'sf_opportunity_id'));
            if (String.isNotBlank(sfId) && sfId.length() >= 15) {
                for (SObject r : unlinked) {
                    if (String.valueOf(r.Id).left(15) == sfId.left(15)) {
                        put(found, r, nameField, siteField, 'Carries this Salesforce record id', VeleiroClientMatcher.HIGH);
                    }
                }
            }
            // 2. Mismo dominio del sitio web.
            String domain = VeleiroClientMatcher.domainOf(row.veleiroWebsite);
            if (String.isNotBlank(domain)) {
                for (SObject r : get(byDomain, domain)) {
                    put(found, r, nameField, siteField, 'Same website domain (' + domain + ')', VeleiroClientMatcher.HIGH);
                }
            }
            // 3. Mismo nombre normalizado, y 4. parecidos.
            String vName = VeleiroClientMatcher.normalizeName(row.veleiroName);
            for (SObject r : get(byName, vName)) {
                put(found, r, nameField, siteField, 'Same name', VeleiroClientMatcher.MEDIUM);
            }
            if (String.isNotBlank(vName)) {
                for (SObject r : get(byFirstWord, vName.split(' ')[0])) {
                    put(found, r, nameField, siteField, 'Similar name', VeleiroClientMatcher.WEAK);
                }
                for (SObject r : unlinked) {
                    if (found.size() >= MAX_OPTIONS * 3) break;
                    String rn = VeleiroClientMatcher.normalizeName(str(r.get(nameField)));
                    if (String.isNotBlank(rn) && rn != vName && (rn.contains(vName) || vName.contains(rn))) {
                        put(found, r, nameField, siteField, 'Similar name', VeleiroClientMatcher.WEAK);
                    }
                }
            }

            row.options = rank(found.values());
            if (!row.options.isEmpty()) {
                RecordOption best = row.options[0];
                if (best.confidence != VeleiroClientMatcher.WEAK) row.suggestedRecordId = best.recordId;
                row.suggestedReason = best.reason;
                row.confidence = best.confidence;
            }
            o.rows.add(row);
        }

        // Sugerencias fuertes primero; los que no tienen ninguna, al final.
        List<VeleiroRow> sorted = new List<VeleiroRow>();
        for (String level : new List<String>{ VeleiroClientMatcher.HIGH, VeleiroClientMatcher.MEDIUM, VeleiroClientMatcher.WEAK }) {
            for (VeleiroRow r : o.rows) if (r.confidence == level) sorted.add(r);
        }
        for (VeleiroRow r : o.rows) if (r.confidence == null) sorted.add(r);
        o.rows = sorted;
        return o;
    }

    // Buscador propio: el picker estandar depende de configuracion de la org y puede no cargar.
    // Devuelve registros sin vincular de ese objeto cuyo nombre contenga el texto.
    @AuraEnabled(cacheable=true)
    public static List<RecordOption> searchRecords(String sobjectName, String entity, String term) {
        List<RecordOption> out = new List<RecordOption>();
        if (String.isBlank(sobjectName) || String.isBlank(term) || term.trim().length() < 2) return out;
        Schema.SObjectType type = Schema.getGlobalDescribe().get(sobjectName);
        if (type == null) return out;

        String nameField = mappedField(sobjectName, entity, new Set<String>{ 'name' });
        if (String.isBlank(nameField) && hasField(sobjectName, 'Name')) nameField = 'Name';
        if (String.isBlank(nameField)) return out;
        String siteField = mappedField(sobjectName, entity, new Set<String>{ 'website_url', 'sf_website', 'website' });
        if (String.isBlank(siteField) && hasField(sobjectName, 'Website')) siteField = 'Website';

        Set<Id> linked = VeleiroLinkStore.linkedRecords(sobjectName, entity);
        Set<String> cols = new Set<String>{ 'Id', nameField };
        if (String.isNotBlank(siteField)) cols.add(siteField);
        String pattern = '%' + String.escapeSingleQuotes(term.trim()) + '%';
        String soql = 'SELECT ' + String.join(new List<String>(cols), ', ') +
                      ' FROM ' + String.escapeSingleQuotes(sobjectName) +
                      ' WHERE ' + nameField + ' LIKE :pattern AND Id NOT IN :linked' +
                      ' ORDER BY ' + nameField + ' LIMIT 20';
        for (SObject r : Database.query(soql)) {
            RecordOption op = new RecordOption();
            op.recordId = r.Id;
            op.name = str(r.get(nameField));
            op.website = String.isNotBlank(siteField) ? str(r.get(siteField)) : null;
            op.reason = 'Found by search';
            op.confidence = VeleiroClientMatcher.WEAK;
            out.add(op);
        }
        return out;
    }

    public class LinkResult {
        @AuraEnabled public Integer linked = 0;
        @AuraEnabled public Integer skipped = 0;     // ya vinculados de un lado o del otro
        @AuraEnabled public Boolean syncing = false; // se encolo el push de los campos mapeados
    }

    // Vincula y ademas empuja a Veleiro los campos mapeados de cada registro (en segundo plano).
    @AuraEnabled
    public static LinkResult linkAndSync(String sobjectName, String entity, String pairsJson) {
        return link(sobjectName, entity, pairsJson, true);
    }

    @AuraEnabled
    public static LinkResult linkAll(String sobjectName, String entity, String pairsJson) {
        return link(sobjectName, entity, pairsJson, false);
    }

    // pairsJson: [{"recordId":"001...","veleiroId":"org_..."}]
    private static LinkResult link(String so, String ent, String pairsJson, Boolean pushAfter) {
        LinkResult result = new LinkResult();
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(pairsJson);
        Set<String> usedVeleiroIds = VeleiroLinkStore.linkedIds(so, ent);
        Set<Id> usedRecordIds = VeleiroLinkStore.linkedRecords(so, ent);

        Map<Id, SObject> nativeUpdates = new Map<Id, SObject>();
        List<Veleiro_Link__c> linkRows = new List<Veleiro_Link__c>();
        List<Id> toPush = new List<Id>();

        for (Object o : rows) {
            Map<String, Object> row = (Map<String, Object>) o;
            String recordId = str(row.get('recordId'));
            String veleiroId = str(row.get('veleiroId'));
            if (String.isBlank(recordId) || String.isBlank(veleiroId)
                || recordId == 'null' || veleiroId == 'null') continue;
            // Un recurso, un registro (y viceversa): lo ya vinculado no se toca.
            if (usedVeleiroIds.contains(veleiroId) || usedRecordIds.contains((Id) recordId)) {
                result.skipped++;
                continue;
            }
            usedVeleiroIds.add(veleiroId);
            usedRecordIds.add((Id) recordId);
            toPush.add((Id) recordId);

            SObject record = Schema.getGlobalDescribe().get(so).newSObject((Id) recordId);
            SObject applied = VeleiroLinkStore.apply(record, so, ent, veleiroId, null);
            if (applied instanceof Veleiro_Link__c) linkRows.add((Veleiro_Link__c) applied);
            else nativeUpdates.put(record.Id, applied);
        }

        if (!nativeUpdates.isEmpty()) update nativeUpdates.values();
        if (!linkRows.isEmpty()) upsert linkRows Link_Key__c;
        result.linked = toPush.size();

        // El push va aparte: hace callouts, y aqui acabamos de hacer DML.
        if (pushAfter && !toPush.isEmpty() && VeleiroSyncConfig.pushEnabled()) {
            System.enqueueJob(new VeleiroLinkSyncQueueable(toPush, ent));
            result.syncing = true;
        }
        return result;
    }

    // ---- helpers ----

    // Campo de Salesforce mapeado a alguno de esos targets de Veleiro.
    private static String mappedField(String so, String ent, Set<String> targets) {
        for (Veleiro_Field_Mapping__c m : [
            SELECT SF_Field__c, Veleiro_Target__c FROM Veleiro_Field_Mapping__c
            WHERE SObject__c = :so AND Veleiro_Entity__c = :ent AND Active__c = true
        ]) {
            if (targets.contains(m.Veleiro_Target__c) && hasField(so, m.SF_Field__c)) return m.SF_Field__c;
        }
        return null;
    }

    private static Boolean hasField(String so, String field) {
        if (String.isBlank(field)) return false;
        Schema.SObjectType type = Schema.getGlobalDescribe().get(so);
        return type != null && type.getDescribe().fields.getMap().containsKey(field.toLowerCase());
    }

    private static void addTo(Map<String, List<SObject>> idx, String key, SObject r) {
        if (String.isBlank(key)) return;
        if (!idx.containsKey(key)) idx.put(key, new List<SObject>());
        idx.get(key).add(r);
    }

    private static List<SObject> get(Map<String, List<SObject>> idx, String key) {
        if (String.isBlank(key) || !idx.containsKey(key)) return new List<SObject>();
        return idx.get(key);
    }

    // Guarda la mejor razon por registro (no pisa una coincidencia fuerte con una debil).
    private static void put(Map<Id, RecordOption> found, SObject r, String nameField, String siteField,
                            String reason, String confidence) {
        RecordOption existing = found.get(r.Id);
        if (existing != null && rank(existing.confidence) <= rank(confidence)) return;
        RecordOption op = new RecordOption();
        op.recordId = r.Id;
        op.name = str(r.get(nameField));
        op.website = String.isNotBlank(siteField) ? str(r.get(siteField)) : null;
        op.reason = reason;
        op.confidence = confidence;
        found.put(r.Id, op);
    }

    private static Integer rank(String confidence) {
        if (confidence == VeleiroClientMatcher.HIGH) return 0;
        if (confidence == VeleiroClientMatcher.MEDIUM) return 1;
        return 2;
    }

    private static List<RecordOption> rank(List<RecordOption> options) {
        List<RecordOption> out = new List<RecordOption>();
        for (Integer level = 0; level <= 2; level++) {
            for (RecordOption op : options) {
                if (rank(op.confidence) == level && out.size() < MAX_OPTIONS) out.add(op);
            }
        }
        return out;
    }

    private static String str(Object o) { return (o == null) ? null : String.valueOf(o); }
}
