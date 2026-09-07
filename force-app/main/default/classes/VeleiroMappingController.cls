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

    // Targets de Veleiro para el picklist: top-level + catalogo canonico + llaves ya en uso.
    // NO cacheable: descubre las llaves en uso con un callout (best-effort).
    @AuraEnabled
    public static List<Option> getTargets(String entity) {
        List<Option> out = new List<Option>();
        Set<String> seen = new Set<String>();
        for (String t : VeleiroTargets.topLevel(entity)) {
            if (seen.add(t)) out.add(new Option(t, t + '  ·  standard'));
        }
        for (String t : VeleiroTargets.canonical(entity)) {
            if (seen.add(t)) out.add(new Option(t, t));
        }
        // Llaves de additional_fields que YA existen en Veleiro -> reusar, no reinventar.
        try {
            for (String k : discoverKeys(entity)) {
                if (seen.add(k)) out.add(new Option(k, k + '  ·  in use'));
            }
        } catch (Exception e) {
            /* si el callout falla, el catalogo canonico sigue siendo util */
        }
        out.add(new Option('__custom__', 'Custom…'));
        return out;
    }

    // Lee las llaves de additional_fields de unos registros de muestra en Veleiro.
    private static List<String> discoverKeys(String entity) {
        List<String> keys = new List<String>();
        if (!VeleiroApiClient.hasToken()) return keys;
        String path = (entity == 'project') ? '/projects' : '/clients';
        Map<String, Object> res = VeleiroApiClient.doGet(path, new Map<String, String>{ 'limit' => '5' });
        Object dataObj = (res != null) ? res.get('data') : null;
        if (dataObj instanceof List<Object>) {
            for (Object item : (List<Object>) dataObj) {
                if (item instanceof Map<String, Object>) {
                    Object af = ((Map<String, Object>) item).get('additional_fields');
                    if (af instanceof Map<String, Object>) keys.addAll(((Map<String, Object>) af).keySet());
                }
            }
        }
        return keys;
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
                // Normaliza el target a una llave canonica (homologa nombres) e infiere el tipo.
                String target = VeleiroTargets.normalize(r.target);
                if (String.isBlank(target)) continue;
                Veleiro_Field_Mapping__c m = new Veleiro_Field_Mapping__c();
                if (String.isNotBlank(r.id)) m.Id = r.id;
                m.Name = (sobjectName + ' ' + r.sfField).left(80);
                m.SObject__c = sobjectName;
                m.Veleiro_Entity__c = entity;
                m.SF_Field__c = r.sfField;
                m.Veleiro_Target__c = target;
                m.Target_Type__c = VeleiroTargets.typeFor(entity, target);
                m.Is_Standard__c = false;
                m.Active__c = true;
                toUpsert.add(m);
            }
        }
        if (!toUpsert.isEmpty()) upsert toUpsert;
    }

    // ---- configuracion global de la integracion (direccion / quien manda / frecuencia) ----

    @AuraEnabled
    public static Map<String, String> getSyncConfig() {
        return new Map<String, String>{
            'direction' => VeleiroSyncConfig.direction(),
            'winner'    => VeleiroSyncConfig.winner(),
            'frequency' => VeleiroSyncConfig.frequency()
        };
    }

    @AuraEnabled
    public static void saveSyncConfig(String direction, String winner, String frequency) {
        VeleiroSyncConfig.save(direction, winner, frequency);
    }

    // ---- conexion: guardar token + verificar estado (para el panel) ----

    // Guarda el token del cliente (a nivel Org Default). Lo pega el propio cliente en el panel.
    @AuraEnabled
    public static void saveToken(String token) {
        if (String.isBlank(token)) return;
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c == null || c.Id == null) {
            c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        c.Api_Token__c = token.trim();
        upsert c;
    }

    // Estado en vivo: token puesto? conectado (callout real)? frecuencia + proximo run.
    @AuraEnabled
    public static Map<String, String> getStatus() {
        Map<String, String> s = new Map<String, String>();
        Boolean tokenSet = VeleiroApiClient.hasToken();
        s.put('tokenSet', String.valueOf(tokenSet));

        if (tokenSet) {
            try {
                VeleiroApiClient.doGet('/clients', new Map<String, String>{ 'limit' => '1' });
                s.put('connected', 'true');
                s.put('message', 'Connected to Veleiro');
            } catch (Exception e) {
                s.put('connected', 'false');
                s.put('message', e.getMessage());
            }
        } else {
            s.put('connected', 'false');
            s.put('message', 'No API token yet — paste it below to connect.');
        }

        s.put('frequency', VeleiroSyncConfig.frequency());
        String nextRun = '';
        for (CronTrigger ct : [
            SELECT NextFireTime FROM CronTrigger
            WHERE CronJobDetail.Name = :VeleiroSyncConfig.JOB_NAME AND NextFireTime != null
            ORDER BY NextFireTime ASC LIMIT 1
        ]) {
            if (ct.NextFireTime != null) nextRun = ct.NextFireTime.format();
        }
        s.put('nextRun', nextRun);
        return s;
    }

    public class OptionComparator implements Comparator<Option> {
        public Integer compare(Option a, Option b) {
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        }
    }
}
