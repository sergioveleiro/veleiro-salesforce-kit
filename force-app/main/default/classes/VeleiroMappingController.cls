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

    /**
     * Mapeo guardado, tal como lo lee el UI.
     *
     * NUNCA se devuelve el sObject crudo: dentro del paquete administrado sus campos se
     * llaman veleiro__SObject__c, y el LWC que lee m.SObject__c recibe undefined. Eso se vio
     * en la org de un cliente como una lista de mapeos con todos los nombres en blanco.
     * Un DTO con nombres propios se comporta igual con namespace y sin el.
     */
    public class SavedMapping {
        @AuraEnabled public Id id;
        @AuraEnabled public String sobjectName;
        @AuraEnabled public String entity;
        @AuraEnabled public String sfField;
        @AuraEnabled public String target;
        @AuraEnabled public String type;

        private SavedMapping(Veleiro_Field_Mapping__c m) {
            id = m.Id;
            sobjectName = m.SObject__c;
            entity = m.Veleiro_Entity__c;
            sfField = m.SF_Field__c;
            target = m.Veleiro_Target__c;
            type = m.Target_Type__c;
        }
    }

    private static List<SavedMapping> asRows(List<Veleiro_Field_Mapping__c> records) {
        List<SavedMapping> out = new List<SavedMapping>();
        for (Veleiro_Field_Mapping__c m : records) out.add(new SavedMapping(m));
        return out;
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
    public static List<SavedMapping> getMappings() {
        String soql = 'SELECT Name, '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SObject__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Veleiro_Entity__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SF_Field__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Veleiro_Target__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Target_Type__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Is_Standard__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Active__c)
            + ' FROM ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SObjectType)
            + ' WHERE ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Active__c) + ' = true'
            + ' ORDER BY ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SObject__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Veleiro_Entity__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Is_Standard__c) + ' DESC, '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SF_Field__c);
        List<Veleiro_Field_Mapping__c> rows = new List<Veleiro_Field_Mapping__c>();
        for (SObject row : VeleiroSecurity.query(soql, new Map<String, Object>())) {
            rows.add((Veleiro_Field_Mapping__c) row);
        }
        return asRows(rows);
    }

    // Mapeos guardados para un par (objeto, entidad). NO cacheable (lectura fresca tras Save).
    @AuraEnabled
    public static List<SavedMapping> getMappingsFor(String sobjectName, String entity) {
        String soql = 'SELECT Id, '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SObject__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Veleiro_Entity__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SF_Field__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Veleiro_Target__c) + ', '
            + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Target_Type__c)
            + ' FROM ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SObjectType)
            + ' WHERE ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SObject__c) + ' = :sobjectName'
            + ' AND ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Veleiro_Entity__c) + ' = :entity'
            + ' AND ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Active__c) + ' = true'
            + ' ORDER BY ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SF_Field__c);
        List<Veleiro_Field_Mapping__c> rows = new List<Veleiro_Field_Mapping__c>();
        for (SObject row : VeleiroSecurity.query(soql, new Map<String, Object>{
            'sobjectName' => sobjectName, 'entity' => entity
        })) {
            rows.add((Veleiro_Field_Mapping__c) row);
        }
        return asRows(rows);
    }

    // Template default (sin guardar) para un par conocido; vacio si no aplica.
    @AuraEnabled(cacheable=true)
    public static List<SavedMapping> defaultTemplate(String sobjectName, String entity) {
        return asRows(VeleiroSeed.defaultsFor(sobjectName, entity));
    }

    // Objetos de Salesforce disponibles para mapear (creables/consultables).
    @AuraEnabled(cacheable=true)
    public static List<Option> getObjects() {
        List<Option> out = new List<Option>();
        for (Schema.SObjectType t : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult d = t.getDescribe();
            String n = d.getName();
            if (!d.isAccessible() || !d.isCreateable() || !d.isQueryable() || d.isCustomSetting() || d.isDeprecatedAndHidden()) continue;
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
            System.debug(LoggingLevel.FINE, 'Target discovery skipped: ' + e.getTypeName());
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
        Schema.DescribeSObjectResult described = VeleiroSecurity.describeObject(sobjectName);
        if (described == null) return out;
        for (Schema.SObjectField f : described.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            if (!fd.isAccessible()) continue;
            out.add(new Option(fd.getName(), fd.getLabel() + ' (' + fd.getName() + ')'));
        }
        out.sort(new OptionComparator());
        return out;
    }

    // ---- escritura ----

    // Reemplaza el conjunto COMPLETO de mapeos del par (objeto, entidad): borra lo que
    // existe y reinserta lo enviado. Asi el estado guardado == lo que manda la UI, sin
    // depender de ids/deletedIds del cliente -> nunca duplica ni deja filas huerfanas.
    // (El `deletedIds` se mantiene por compatibilidad de firma; ya no se usa.)
    @AuraEnabled
    public static void saveMappings(String sobjectName, String entity, List<MappingRow> rows, List<Id> deletedIds, String rowsJson) {
        VeleiroSecurity.assertCanManageSetup();
        Schema.DescribeSObjectResult described = VeleiroSecurity.describeObject(sobjectName);
        if (described == null) {
            throw VeleiroSecurity.handled(VeleiroI18n.t('err.objectUnavailable'));
        }
        // La UI manda las filas como JSON string (rowsJson). Motivo: el marshaling de un array de
        // objetos LWC hacia un parametro Apex tipado List<MappingRow> llega con TODOS los campos en
        // null (gotcha conocido de Aura/LWC con listas de clases Apex), mientras que el String
        // round-trips perfecto. Los tests Apex->Apex pasan `rows` tipado y rowsJson en blanco.
        if (String.isNotBlank(rowsJson)) {
            rows = (List<MappingRow>) JSON.deserialize(rowsJson, List<MappingRow>.class);
        }
        // 1) Construir PRIMERO (no borrar todavia). Normaliza el target y dedup por campo SF.
        Integer submitted = (rows == null) ? 0 : rows.size();
        List<Veleiro_Field_Mapping__c> toInsert = new List<Veleiro_Field_Mapping__c>();
        Set<String> seenFields = new Set<String>();
        if (rows != null) {
            for (MappingRow r : rows) {
                String sfField = VeleiroSecurity.safeField(described, r.sfField);
                if (sfField == null || String.isBlank(r.target)) continue;
                String target = VeleiroTargets.normalize(r.target);
                if (String.isBlank(target)) continue; // ej. un target de puro simbolo/espacio -> se descarta
                if (!seenFields.add(sfField)) continue; // un mismo campo SF, una sola vez por par
                Veleiro_Field_Mapping__c m = new Veleiro_Field_Mapping__c();
                m.Name = (described.getName() + ' ' + sfField).left(80);
                m.SObject__c = described.getName();
                m.Veleiro_Entity__c = entity;
                m.SF_Field__c = sfField;
                m.Veleiro_Target__c = target;
                m.Target_Type__c = VeleiroTargets.typeFor(entity, target);
                m.Is_Standard__c = false;
                m.Active__c = true;
                toInsert.add(m);
            }
        }
        // 2) Si mandaste filas pero TODAS se descartaron (targets invalidos), NO borres nada:
        //    aborta con error para no destruir el mapeo existente ni reportar falso exito.
        if (submitted > 0 && toInsert.isEmpty()) {
            throw VeleiroSecurity.handled(VeleiroI18n.t('err.mappingRows'));
        }
        // 3) Reemplazo del par: borrar + insertar juntos (atomico en la misma transaccion).
        //    submitted == 0 (sin filas) => vaciar el par a proposito. Con filas validas => reemplazar.
        String deleteSoql = 'SELECT Id FROM ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SObjectType)
            + ' WHERE ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.SObject__c) + ' = :sobjectName'
            + ' AND ' + VeleiroSecurity.api(Veleiro_Field_Mapping__c.Veleiro_Entity__c) + ' = :entity';
        VeleiroSecurity.deleteRecords(VeleiroSecurity.query(deleteSoql, new Map<String, Object>{
            'sobjectName' => described.getName(), 'entity' => entity
        }));
        VeleiroSecurity.insertRecords(toInsert);
    }

    // ---- configuracion global de la integracion (direccion / quien manda / frecuencia) ----

    @AuraEnabled
    public static Map<String, String> getSyncConfig() {
        return new Map<String, String>{
            'direction' => VeleiroSyncConfig.direction(),
            'winner'    => VeleiroSyncConfig.winner(),
            'frequency' => VeleiroSyncConfig.frequency(),
            'trigger'   => VeleiroSyncConfig.syncTrigger(),
            'autoAccount' => String.valueOf(VeleiroSyncConfig.autoSyncAccountFlag()),
            'autoOpportunity' => String.valueOf(VeleiroSyncConfig.autoSyncOpportunityFlag()),
            'opportunityMode' => VeleiroSyncConfig.opportunitySyncMode(),
            'pullWritesName' => String.valueOf(VeleiroSyncConfig.pullWritesName()),
            'lastError' => VeleiroSyncConfig.lastError(),
            'lastErrorAt' => VeleiroSyncConfig.lastErrorAt() == null ? null : VeleiroSyncConfig.lastErrorAt().format()
        };
    }

    @AuraEnabled
    public static void saveSyncConfig(String direction, String winner, String frequency, String triggerMode,
                                      Boolean autoAccount, Boolean autoOpportunity, Boolean pullWritesName,
                                      String opportunityMode) {
        VeleiroSecurity.assertCanManageSetup();
        VeleiroSyncConfig.save(direction, winner, frequency, triggerMode, autoAccount, autoOpportunity,
                               pullWritesName, opportunityMode);
    }

    // ---- conexion: guardar token + verificar estado (para el panel) ----

    // Guarda el token del cliente (a nivel Org Default). Lo pega el propio cliente en el panel.
    @AuraEnabled
    public static void saveToken(String token) {
        VeleiroSecurity.assertCanManageSetup();
        if (String.isBlank(token)) return;
        VeleiroCredentialStore.saveNewToken(token);
    }

    // Cambia el entorno (Production / Beta) escribiendo Base_Url + App_Base_Url. NO toca el token.
    // El host real lo enruta el Named Credential correspondiente (Veleiro_API / Veleiro_API_Beta).
    @AuraEnabled
    public static void saveEnvironment(String environment) {
        VeleiroSecurity.assertCanManageSetup();
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c == null || c.Id == null) {
            c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        // El nombre de la credencial lleva el prefijo del namespace dentro del paquete administrado.
        if (environment == 'Beta') {
            c.Base_Url__c = VeleiroApiClient.calloutTo(VeleiroApiClient.CRED_BETA) + '/api/v1';
            c.App_Base_Url__c = 'https://app.beta.veleiro.dev';
        } else { // Production (default)
            c.Base_Url__c = VeleiroApiClient.calloutTo(VeleiroApiClient.CRED_PROD) + '/api/v1';
            c.App_Base_Url__c = 'https://app.veleiro.ai';
        }
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
                s.put('message', VeleiroSecurity.forUi(e));
            }
        } else {
            s.put('connected', 'false');
            s.put('message', 'No API token yet — paste it below to connect.');
        }

        // Entorno actual (para que el panel muestre a donde esta conectado).
        String app = VeleiroApiClient.appBaseUrl();
        String env = app.containsIgnoreCase('beta') ? 'Beta'
                   : (app.containsIgnoreCase('app.veleiro.ai') ? 'Production' : 'Custom');
        s.put('appBase', app);
        s.put('apiBase', VeleiroApiClient.apiBaseConfigured());
        s.put('environment', env);

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
        // After the callout (or when there was none): move a legacy public token out of the public field.
        try {
            VeleiroCredentialStore.migrateLegacyToken();
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Token migration skipped: ' + e.getTypeName());
        }
        return s;
    }

    public class OptionComparator implements Comparator<Option> {
        public Integer compare(Option a, Option b) {
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        }
    }
}
