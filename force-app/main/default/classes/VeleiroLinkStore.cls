/**
 * Donde vive el vinculo entre un registro de Salesforce y su client/project de Veleiro.
 *
 * Account y Opportunity siguen usando sus campos propios (Veleiro_Client_Id__c /
 * Veleiro_Project_Id__c): lo que ya esta instalado y sincronizado no se toca. Cualquier
 * otro objeto guarda su vinculo en Veleiro_Link__c, asi el kit funciona con objetos
 * personalizados sin pedirle al partner que cree campos.
 */
public with sharing class VeleiroLinkStore {

    public class Link {
        public String veleiroId;
        public Integer version;
    }

    // Campos nativos por objeto+entidad; el resto va al objeto Veleiro_Link__c.
    private static final Map<String, List<String>> NATIVE_FIELDS = new Map<String, List<String>>{
        'account|client'     => new List<String>{ 'Veleiro_Client_Id__c', 'Veleiro_Version__c' },
        'opportunity|project' => new List<String>{ 'Veleiro_Project_Id__c', 'Veleiro_Project_Version__c' }
    };

    public static Boolean isNative(String sobjectName, String entity) {
        return NATIVE_FIELDS.containsKey(key(sobjectName, entity));
    }

    private static List<String> nativeFields(String sobjectName, String entity) {
        return NATIVE_FIELDS.get(key(sobjectName, entity));
    }

    public static String key(String sobjectName, String entity) {
        return (sobjectName + '|' + entity).toLowerCase();
    }

    // Lee el vinculo del registro (null si aun no esta vinculado).
    public static Link read(SObject record, String sobjectName, String entity) {
        Link l = new Link();
        if (isNative(sobjectName, entity)) {
            List<String> f = nativeFields(sobjectName, entity);
            l.veleiroId = (String) record.get(f[0]);
            Object v = record.get(f[1]);
            l.version = (v == null) ? null : Integer.valueOf(String.valueOf(v));
        } else {
            for (Veleiro_Link__c row : [
                SELECT Veleiro_Id__c, Veleiro_Version__c FROM Veleiro_Link__c
                WHERE Link_Key__c = :linkKey(record.Id, entity) LIMIT 1
            ]) {
                l.veleiroId = row.Veleiro_Id__c;
                l.version = (row.Veleiro_Version__c == null) ? null : Integer.valueOf(row.Veleiro_Version__c);
            }
        }
        return l;
    }

    // Deja el vinculo sobre el registro EN MEMORIA (nativo) o devuelve la fila a guardar.
    // Quien llama hace el DML: nunca entre callouts.
    public static SObject apply(SObject record, String sobjectName, String entity, String veleiroId, Integer version) {
        if (isNative(sobjectName, entity)) {
            List<String> f = nativeFields(sobjectName, entity);
            record.put(f[0], veleiroId);
            record.put(f[1], version);
            return record;
        }
        Veleiro_Link__c row = new Veleiro_Link__c(
            Link_Key__c = linkKey(record.Id, entity),
            Record_Id__c = String.valueOf(record.Id),
            SObject__c = sobjectName,
            Veleiro_Entity__c = entity,
            Veleiro_Id__c = veleiroId,
            Veleiro_Version__c = version
        );
        return row;
    }

    // Ids de Veleiro ya vinculados para ese par objeto+entidad (para no ofrecerlos dos veces).
    public static Set<String> linkedIds(String sobjectName, String entity) {
        Set<String> ids = new Set<String>();
        if (isNative(sobjectName, entity)) {
            String field = nativeFields(sobjectName, entity)[0];
            String soql = 'SELECT ' + field + ' FROM ' + String.escapeSingleQuotes(sobjectName) +
                          ' WHERE ' + field + ' != null';
            for (SObject r : Database.query(soql)) ids.add((String) r.get(field));
        } else {
            for (Veleiro_Link__c row : [
                SELECT Veleiro_Id__c FROM Veleiro_Link__c
                WHERE SObject__c = :sobjectName AND Veleiro_Entity__c = :entity
            ]) {
                ids.add(row.Veleiro_Id__c);
            }
        }
        return ids;
    }

    // Registros de ese objeto que ya tienen vinculo (para excluirlos de los candidatos).
    public static Set<Id> linkedRecords(String sobjectName, String entity) {
        Set<Id> ids = new Set<Id>();
        if (isNative(sobjectName, entity)) {
            String field = nativeFields(sobjectName, entity)[0];
            String soql = 'SELECT Id FROM ' + String.escapeSingleQuotes(sobjectName) +
                          ' WHERE ' + field + ' != null';
            for (SObject r : Database.query(soql)) ids.add(r.Id);
        } else {
            for (Veleiro_Link__c row : [
                SELECT Record_Id__c FROM Veleiro_Link__c
                WHERE SObject__c = :sobjectName AND Veleiro_Entity__c = :entity
            ]) {
                ids.add((Id) row.Record_Id__c);
            }
        }
        return ids;
    }

    private static String linkKey(Id recordId, String entity) {
        return String.valueOf(recordId).left(15) + '|' + entity;
    }
}
