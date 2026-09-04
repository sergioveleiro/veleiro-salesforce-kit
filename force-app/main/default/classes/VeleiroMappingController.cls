/**
 * Backend del builder de mapeo. Deja al partner elegir CUALQUIER objeto de Salesforce,
 * mapearlo a una entidad de Veleiro (client | project) y definir los campos manualmente.
 * Para los pares que "hacen sentido" (Account->client, Opportunity->project) hay un
 * template default que el UI autopopula.
 */
public with sharing class VeleiroMappingController {

    public class Option {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public Option(String v, String l) { value = v; label = l; }
    }

    // Fila de mapeo que viaja LWC <-> Apex.
    public class MappingRow {
        @AuraEnabled public String id;
        @AuraEnabled public String sfField;
        @AuraEnabled public String target;
        @AuraEnabled public String type;   // Standard | Additional Field
    }

    // ---- lectura para el UI ----

    // Todos los mapeos activos (para el resumen), agrupables por objeto+entidad.
    // NO cacheable: debe leer fresco tras cada Save (si no, la UI muestra data vieja).
    @AuraEnabled
    public static List<Veleiro_Field_Mapping__c> getMappings() {
        return [
            SELECT Name, SObject__c, Veleiro_Entity__c, SF_Field__c, Veleiro_Target__c,
                   Target_Type__c, Is_Standard__c, Active__c
            FROM Veleiro_Field_Mapping__c
            WHERE Active__c = true
            ORDER BY SObject__c, Veleiro_Entity__c, Is_Standard__c DESC, SF_Field__c
        ];
    }

    // Mapeos guardados para un par (objeto, entidad). NO cacheable (lectura fresca tras Save).
    @AuraEnabled
    public static List<Veleiro_Field_Mapping__c> getMappingsFor(String sobjectName, String entity) {
        return [
            SELECT Id, SObject__c, Veleiro_Entity__c, SF_Field__c, Veleiro_Target__c, Target_Type__c
            FROM Veleiro_Field_Mapping__c
            WHERE SObject__c = :sobjectName AND Veleiro_Entity__c = :entity AND Active__c = true
            ORDER BY SF_Field__c
        ];
    }

    // Template default (sin guardar) para un par conocido; vacio si no aplica.
    @AuraEnabled(cacheable=true)
    public static List<Veleiro_Field_Mapping__c> defaultTemplate(String sobjectName, String entity) {
        return VeleiroSeed.defaultsFor(sobjectName, entity);
    }

    // Objetos de Salesforce disponibles para mapear (creables/consultables).
    @AuraEnabled(cacheable=true)
    public static List<Option> getObjects() {
        List<Option> out = new List<Option>();
        for (Schema.SObjectType t : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult d = t.getDescribe();
            String n = d.getName();
            if (!d.isCreateable() || !d.isQueryable() || d.isCustomSetting() || d.isDeprecatedAndHidden()) continue;
            if (n.endsWithIgnoreCase('Share') || n.endsWithIgnoreCase('History') ||
                n.endsWithIgnoreCase('Feed') || n.endsWithIgnoreCase('ChangeEvent') ||
                n.endsWithIgnoreCase('__Tag')) continue;
            out.add(new Option(n, d.getLabel() + ' (' + n + ')'));
        }
        out.sort(new OptionComparator());
        return out;
    }

    // Campos de un objeto (para el picklist de "Salesforce field").
    @AuraEnabled(cacheable=true)
    public static List<Option> getFields(String sobjectName) {
        List<Option> out = new List<Option>();
        if (String.isBlank(sobjectName)) return out;
        Schema.SObjectType t = Schema.getGlobalDescribe().get(sobjectName);
        if (t == null) return out;
        for (Schema.SObjectField f : t.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            out.add(new Option(fd.getName(), fd.getLabel() + ' (' + fd.getName() + ')'));
        }
        out.sort(new OptionComparator());
        return out;
    }

    // ---- escritura ----

    // Reemplaza el conjunto de mapeos del par (objeto, entidad).
    @AuraEnabled
    public static void saveMappings(String sobjectName, String entity, List<MappingRow> rows, List<Id> deletedIds) {
        if (deletedIds != null && !deletedIds.isEmpty()) {
            delete [SELECT Id FROM Veleiro_Field_Mapping__c WHERE Id IN :deletedIds];
        }
        List<Veleiro_Field_Mapping__c> toUpsert = new List<Veleiro_Field_Mapping__c>();
        if (rows != null) {
            for (MappingRow r : rows) {
                if (String.isBlank(r.sfField) || String.isBlank(r.target)) continue;
                Veleiro_Field_Mapping__c m = new Veleiro_Field_Mapping__c();
                if (String.isNotBlank(r.id)) m.Id = r.id;
                m.Name = (sobjectName + ' ' + r.sfField).left(80);
                m.SObject__c = sobjectName;
                m.Veleiro_Entity__c = entity;
                m.SF_Field__c = r.sfField;
                m.Veleiro_Target__c = r.target;
                m.Target_Type__c = String.isNotBlank(r.type) ? r.type : 'Additional Field';
                m.Is_Standard__c = false;
                m.Active__c = true;
                toUpsert.add(m);
            }
        }
        if (!toUpsert.isEmpty()) upsert toUpsert;
    }

    public class OptionComparator implements Comparator<Option> {
        public Integer compare(Option a, Option b) {
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        }
    }
}
