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
            String idField = resolved(sobjectName, f[0]);
            String versionField = resolved(sobjectName, f[1]);
            if (idField == null) return l;
            l.veleiroId = (String) record.get(idField);
            Object v = versionField == null ? null : record.get(versionField);
            l.version = (v == null) ? null : Integer.valueOf(String.valueOf(v));
        } else {
            String soql = 'SELECT ' + VeleiroSecurity.api(Veleiro_Link__c.Veleiro_Id__c) + ', '
                + VeleiroSecurity.api(Veleiro_Link__c.Veleiro_Version__c)
                + ' FROM ' + VeleiroSecurity.api(Veleiro_Link__c.SObjectType)
                + ' WHERE ' + VeleiroSecurity.api(Veleiro_Link__c.Link_Key__c) + ' = :linkKey LIMIT 1';
            for (SObject raw : VeleiroSecurity.query(soql, new Map<String, Object>{
                'linkKey' => linkKey(record.Id, entity)
            })) {
                Veleiro_Link__c row = (Veleiro_Link__c) raw;
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
            String idField = resolved(sobjectName, f[0]);
            String versionField = resolved(sobjectName, f[1]);
            if (idField != null) record.put(idField, veleiroId);
            if (versionField != null) record.put(versionField, version);
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
            Schema.DescribeSObjectResult described = VeleiroSecurity.describeObject(sobjectName);
            String field = VeleiroSecurity.safeField(described, nativeFields(sobjectName, entity)[0]);
            if (described == null || field == null) return ids;
            String soql = 'SELECT ' + field + ' FROM ' + described.getName() +
                          ' WHERE ' + field + ' != null';
            for (SObject r : VeleiroSecurity.query(soql, new Map<String, Object>())) ids.add((String) r.get(field));
        } else {
            String linkSoql = 'SELECT ' + VeleiroSecurity.api(Veleiro_Link__c.Veleiro_Id__c)
                + ' FROM ' + VeleiroSecurity.api(Veleiro_Link__c.SObjectType)
                + ' WHERE ' + VeleiroSecurity.api(Veleiro_Link__c.SObject__c) + ' = :sobjectName'
                + ' AND ' + VeleiroSecurity.api(Veleiro_Link__c.Veleiro_Entity__c) + ' = :entity';
            for (SObject raw : VeleiroSecurity.query(linkSoql, new Map<String, Object>{
                'sobjectName' => sobjectName, 'entity' => entity
            })) {
                Veleiro_Link__c row = (Veleiro_Link__c) raw;
                ids.add(row.Veleiro_Id__c);
            }
        }
        return ids;
    }

    // Registros de ese objeto que ya tienen vinculo (para excluirlos de los candidatos).
    public static Set<Id> linkedRecords(String sobjectName, String entity) {
        Set<Id> ids = new Set<Id>();
        if (isNative(sobjectName, entity)) {
            Schema.DescribeSObjectResult described = VeleiroSecurity.describeObject(sobjectName);
            String field = VeleiroSecurity.safeField(described, nativeFields(sobjectName, entity)[0]);
            if (described == null || field == null) return ids;
            String soql = 'SELECT Id FROM ' + described.getName() +
                          ' WHERE ' + field + ' != null';
            for (SObject r : VeleiroSecurity.query(soql, new Map<String, Object>())) ids.add(r.Id);
        } else {
            String linkSoql = 'SELECT ' + VeleiroSecurity.api(Veleiro_Link__c.Record_Id__c)
                + ' FROM ' + VeleiroSecurity.api(Veleiro_Link__c.SObjectType)
                + ' WHERE ' + VeleiroSecurity.api(Veleiro_Link__c.SObject__c) + ' = :sobjectName'
                + ' AND ' + VeleiroSecurity.api(Veleiro_Link__c.Veleiro_Entity__c) + ' = :entity';
            for (SObject raw : VeleiroSecurity.query(linkSoql, new Map<String, Object>{
                'sobjectName' => sobjectName, 'entity' => entity
            })) {
                Veleiro_Link__c row = (Veleiro_Link__c) raw;
                ids.add((Id) row.Record_Id__c);
            }
        }
        return ids;
    }

    private static String resolved(String sobjectName, String localName) {
        return VeleiroSecurity.safeField(VeleiroSecurity.describeObject(sobjectName), localName);
    }

    private static String linkKey(Id recordId, String entity) {
        return String.valueOf(recordId).left(15) + '|' + entity;
    }
}
