/**
 * Sincronizacion Salesforce -> Veleiro (write). Manual, desde el boton "Sync with Veleiro".
 * Account -> client de Veleiro. Crea si es nuevo; si ya existe, actualiza campos.
 * additional_fields se maneja read-modify-write (el PATCH lo reemplaza entero).
 *
 * El payload que se empuja lo DEFINEN los mapeos (Veleiro_Field_Mapping__c) que el
 * partner configura en el panel de Veleiro Mappings. Si no hay mapeos para el par
 * (objeto, entidad), se cae al template default (VeleiroSeed) para no quedar en no-op.
 * La llave de correlacion de sistema (sf_account_id / sf_opportunity_id) SIEMPRE se
 * envia, independientemente del mapeo, porque es como Veleiro referencia el registro.
 */
public with sharing class VeleiroSyncService {

    // Base humana de la app Veleiro (para el hipervinculo). Configurable a futuro.
    // Base humana del portal de Veleiro (hipervinculos). Config: Veleiro_Config__c.App_Base_Url__c (default beta).
    private static String appBase() { return VeleiroApiClient.appBaseUrl(); }

    // ===== Mapeo -> payload =====

    // Payload derivado de los mapeos: campos top-level (Standard) vs additional_fields.
    private class MappedPayload {
        Map<String, Object> topLevel = new Map<String, Object>();
        Map<String, Object> additional = new Map<String, Object>();
        SObject record;
    }

    // Mapeos activos del par; si el partner no configuro ninguno, cae al template default.
    private static List<Veleiro_Field_Mapping__c> mappingsFor(String sobjectName, String entity) {
        List<Veleiro_Field_Mapping__c> maps = [
            SELECT SF_Field__c, Veleiro_Target__c, Target_Type__c
            FROM Veleiro_Field_Mapping__c
            WHERE SObject__c = :sobjectName AND Veleiro_Entity__c = :entity AND Active__c = true
        ];
        if (maps.isEmpty()) maps = VeleiroSeed.defaultsFor(sobjectName, entity);
        return maps;
    }

    // Consulta dinamica del registro con los campos mapeados (+ extra) y arma el payload.
    private static MappedPayload buildPayload(String sobjectName, String entity, Id recordId, Set<String> extraFields) {
        List<Veleiro_Field_Mapping__c> maps = mappingsFor(sobjectName, entity);

        Set<String> fields = new Set<String>{ 'Id' };
        if (extraFields != null) fields.addAll(extraFields);
        for (Veleiro_Field_Mapping__c m : maps) {
            if (String.isNotBlank(m.SF_Field__c)) fields.add(m.SF_Field__c);
        }

        String soql = 'SELECT ' + String.join(new List<String>(fields), ', ') +
                      ' FROM ' + String.escapeSingleQuotes(sobjectName) + ' WHERE Id = :recordId LIMIT 1';
        SObject rec = Database.query(soql);

        MappedPayload p = new MappedPayload();
        p.record = rec;
        for (Veleiro_Field_Mapping__c m : maps) {
            Object val = rec.get(m.SF_Field__c);
            if (val == null) continue; // no pisamos con null (read-modify-write preserva lo existente)
            if (val instanceof Date) val = String.valueOf((Date) val);
            else if (val instanceof Datetime) val = ((Datetime) val).formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            if (m.Target_Type__c == 'Standard') p.topLevel.put(m.Veleiro_Target__c, val);
            else p.additional.put(m.Veleiro_Target__c, val);
        }
        return p;
    }

    // ===== Account -> Client =====

    // Resultado que consume el LWC / boton.
    public class ClientResult {
        @AuraEnabled public String clientId;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public Integer version;
        @AuraEnabled public Boolean created;
        @AuraEnabled public String veleiroUrl;
        @AuraEnabled public Boolean synced;
    }

    // Lectura para el LWC (sin callout): estado de sync del Account.
    @AuraEnabled(cacheable=true)
    public static ClientResult getClientSummary(Id accountId) {
        Account a = [
            SELECT Id, Name, Veleiro_Client_Id__c, Veleiro_Slug__c, Veleiro_Version__c
            FROM Account WHERE Id = :accountId LIMIT 1
        ];
        ClientResult r = new ClientResult();
        r.clientId = a.Veleiro_Client_Id__c;
        r.name = a.Name;
        r.slug = a.Veleiro_Slug__c;
        r.version = (a.Veleiro_Version__c != null) ? Integer.valueOf(a.Veleiro_Version__c) : null;
        r.synced = String.isNotBlank(a.Veleiro_Client_Id__c);
        r.veleiroUrl = r.synced ? (appBase() + '/a/partner-portal/organizations/' + a.Veleiro_Client_Id__c) : null;
        return r;
    }

    @AuraEnabled
    public static ClientResult syncAccount(Id accountId) {
        // La direccion configurada define si Salesforce puede empujar a Veleiro.
        if (!VeleiroSyncConfig.pushEnabled()) {
            throw new VeleiroApiClient.VeleiroApiException('Push to Veleiro is disabled by the integration config (Veleiro to Salesforce only). Change the direction in the Veleiro Mappings panel.');
        }

        // El payload lo definen los mapeos configurados (Account -> client).
        MappedPayload mp = buildPayload('Account', 'client', accountId,
            new Set<String>{ 'Name', 'Veleiro_Client_Id__c', 'Veleiro_Version__c' });
        Account a = (Account) mp.record;

        // Llave de correlacion de sistema: siempre va (no depende del mapeo).
        mp.additional.put('sf_account_id', a.Id);
        // 'name' es obligatorio en Veleiro: si el partner no lo mapeo, cae al Name del registro.
        if (!mp.topLevel.containsKey('name')) mp.topLevel.put('name', a.Name);

        Map<String, Object> result;
        Boolean created = false;

        if (String.isBlank(a.Veleiro_Client_Id__c)) {
            // CREATE
            Map<String, Object> payload = new Map<String, Object>();
            payload.putAll(mp.topLevel);
            payload.put('additional_fields', mp.additional);
            result = VeleiroApiClient.doPost('/clients', payload);
            created = true;
        } else {
            // UPDATE: read-modify-write de additional_fields + If-Match version.
            result = patchClientWithMerge(a.Veleiro_Client_Id__c, mp.topLevel, mp.additional,
                        a.Veleiro_Version__c != null ? Integer.valueOf(a.Veleiro_Version__c) : null);
        }

        // Guardar id + version de vuelta en el Account.
        a.Veleiro_Client_Id__c = (String) result.get('id');
        if (result.get('version') != null) a.Veleiro_Version__c = Integer.valueOf(String.valueOf(result.get('version')));
        update a;

        ClientResult r = new ClientResult();
        r.clientId = (String) result.get('id');
        r.name = (String) result.get('name');
        r.slug = (String) result.get('slug');
        r.version = (result.get('version') != null) ? Integer.valueOf(String.valueOf(result.get('version'))) : null;
        r.created = created;
        r.synced = true;
        r.veleiroUrl = appBase() + '/a/partner-portal/organizations/' + r.clientId;
        return r;
    }

    // GET actual -> merge de las llaves gestionadas -> PATCH del payload completo.
    // Reintenta una vez si hay 409 version_conflict usando detail.current_version.
    private static Map<String, Object> patchClientWithMerge(String clientId, Map<String, Object> topLevel, Map<String, Object> managed, Integer knownVersion) {
        Map<String, Object> current = VeleiroApiClient.doGet('/clients/' + clientId, null);
        Map<String, Object> data = (Map<String, Object>) current.get('data');
        Integer version = (knownVersion != null) ? knownVersion
                          : (data.get('version') != null ? Integer.valueOf(String.valueOf(data.get('version'))) : null);

        Map<String, Object> af = new Map<String, Object>();
        Object existingAf = data.get('additional_fields');
        if (existingAf instanceof Map<String, Object>) af.putAll((Map<String, Object>) existingAf);
        af.putAll(managed); // sobreescribe solo nuestras llaves gestionadas, preserva el resto

        Map<String, Object> payload = new Map<String, Object>();
        payload.putAll(topLevel);
        payload.put('additional_fields', af);
        try {
            return VeleiroApiClient.doPatch('/clients/' + clientId, payload, version);
        } catch (VeleiroApiClient.VeleiroApiException e) {
            if (e.code == 'version_conflict' && e.currentVersion != null && VeleiroSyncConfig.salesforceWins()) {
                // Salesforce manda -> reintenta pisando con la version actual.
                // (Si Veleiro manda, no pisamos: dejamos ganar el cambio de Veleiro y relanzamos.)
                return VeleiroApiClient.doPatch('/clients/' + clientId, payload, e.currentVersion);
            }
            throw e;
        }
    }

    // ===== Opportunity -> Project =====

    public class ProjectResult {
        @AuraEnabled public String projectId;
        @AuraEnabled public String name;
        @AuraEnabled public Integer progress;
        @AuraEnabled public Integer version;
        @AuraEnabled public Boolean created;
        @AuraEnabled public String veleiroUrl;
        @AuraEnabled public Boolean synced;
        @AuraEnabled public String status;
    }

    // Lectura EN VIVO del project (con callout): trae progress + status actuales desde Veleiro.
    // La usa el panel de Opportunity para pintar la barra de avance real.
    @AuraEnabled
    public static ProjectResult getProjectLive(Id opportunityId) {
        Opportunity o = [
            SELECT Id, Name, Veleiro_Project_Id__c, Veleiro_Project_Version__c
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        ProjectResult r = new ProjectResult();
        r.projectId = o.Veleiro_Project_Id__c;
        r.name = o.Name;
        r.synced = String.isNotBlank(o.Veleiro_Project_Id__c);
        r.veleiroUrl = r.synced ? (appBase() + '/a/partner-portal/projects/' + o.Veleiro_Project_Id__c) : null;
        if (r.synced) {
            Map<String, Object> cur = VeleiroApiClient.doGet('/projects/' + o.Veleiro_Project_Id__c, null);
            Map<String, Object> d = (Map<String, Object>) cur.get('data');
            if (d != null) {
                r.progress = (d.get('progress') != null) ? Integer.valueOf(String.valueOf(d.get('progress'))) : null;
                r.version = (d.get('version') != null) ? Integer.valueOf(String.valueOf(d.get('version'))) : null;
                r.status = (String) d.get('status');
            }
        }
        return r;
    }

    @AuraEnabled
    public static ProjectResult syncOpportunity(Id opportunityId) {
        if (!VeleiroSyncConfig.pushEnabled()) {
            throw new VeleiroApiClient.VeleiroApiException('Push to Veleiro is disabled by the integration config (Veleiro to Salesforce only). Change the direction in the Veleiro Mappings panel.');
        }

        // El payload del project lo definen los mapeos (Opportunity -> project).
        MappedPayload mp = buildPayload('Opportunity', 'project', opportunityId,
            new Set<String>{ 'Name', 'AccountId', 'Veleiro_Project_Id__c', 'Veleiro_Project_Version__c' });
        Opportunity o = (Opportunity) mp.record;
        if (o.AccountId == null) {
            throw new VeleiroApiClient.VeleiroApiException('The Opportunity has no Account.');
        }

        // Llave de correlacion de sistema + name obligatorio.
        mp.additional.put('sf_opportunity_id', o.Id);
        if (!mp.topLevel.containsKey('name')) mp.topLevel.put('name', o.Name);

        // Asegurar el client (crearlo si el Account aun no esta sincronizado) - callout
        Account a = [
            SELECT Id, Name, Veleiro_Client_Id__c, Veleiro_Version__c
            FROM Account WHERE Id = :o.AccountId LIMIT 1
        ];
        String clientId = a.Veleiro_Client_Id__c;
        Boolean accountNeedsUpdate = false;
        if (String.isBlank(clientId)) {
            // Crea el client usando SUS propios mapeos (Account -> client).
            MappedPayload amp = buildPayload('Account', 'client', a.Id, new Set<String>{ 'Name' });
            amp.additional.put('sf_account_id', a.Id);
            if (!amp.topLevel.containsKey('name')) amp.topLevel.put('name', a.Name);
            Map<String, Object> cpayload = new Map<String, Object>();
            cpayload.putAll(amp.topLevel);
            cpayload.put('additional_fields', amp.additional);
            Map<String, Object> cRes = VeleiroApiClient.doPost('/clients', cpayload);
            clientId = (String) cRes.get('id');
            a.Veleiro_Client_Id__c = clientId;
            if (cRes.get('version') != null) a.Veleiro_Version__c = Integer.valueOf(String.valueOf(cRes.get('version')));
            accountNeedsUpdate = true;
        }

        Map<String, Object> result;
        Boolean created = false;
        if (String.isBlank(o.Veleiro_Project_Id__c)) {
            Map<String, Object> payload = new Map<String, Object>();
            payload.putAll(mp.topLevel);
            payload.put('client_id', clientId);
            payload.put('additional_fields', mp.additional);
            result = VeleiroApiClient.doPost('/projects', payload);
            created = true;
        } else {
            result = patchProjectWithMerge(o.Veleiro_Project_Id__c, mp.topLevel, mp.additional,
                        o.Veleiro_Project_Version__c != null ? Integer.valueOf(o.Veleiro_Project_Version__c) : null);
        }

        // DML al final (despues de los callouts)
        o.Veleiro_Project_Id__c = (String) result.get('id');
        if (result.get('version') != null) o.Veleiro_Project_Version__c = Integer.valueOf(String.valueOf(result.get('version')));
        List<SObject> toUpdate = new List<SObject>{ o };
        if (accountNeedsUpdate) toUpdate.add(a);
        update toUpdate;

        ProjectResult r = new ProjectResult();
        r.projectId = (String) result.get('id');
        r.name = (String) result.get('name');
        r.progress = (result.get('progress') != null) ? Integer.valueOf(String.valueOf(result.get('progress'))) : null;
        r.version = (result.get('version') != null) ? Integer.valueOf(String.valueOf(result.get('version'))) : null;
        r.created = created;
        r.synced = true;
        r.veleiroUrl = appBase() + '/a/partner-portal/projects/' + r.projectId;
        return r;
    }

    @AuraEnabled(cacheable=true)
    public static ProjectResult getProjectSummary(Id opportunityId) {
        Opportunity o = [
            SELECT Id, Name, Veleiro_Project_Id__c, Veleiro_Project_Version__c
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        ProjectResult r = new ProjectResult();
        r.projectId = o.Veleiro_Project_Id__c;
        r.name = o.Name;
        r.version = (o.Veleiro_Project_Version__c != null) ? Integer.valueOf(o.Veleiro_Project_Version__c) : null;
        r.synced = String.isNotBlank(o.Veleiro_Project_Id__c);
        r.veleiroUrl = r.synced ? (appBase() + '/a/partner-portal/projects/' + o.Veleiro_Project_Id__c) : null;
        return r;
    }

    private static Map<String, Object> patchProjectWithMerge(String projectId, Map<String, Object> topLevel, Map<String, Object> managed, Integer knownVersion) {
        Map<String, Object> current = VeleiroApiClient.doGet('/projects/' + projectId, null);
        Map<String, Object> data = (Map<String, Object>) current.get('data');
        Integer version = (knownVersion != null) ? knownVersion
                          : (data.get('version') != null ? Integer.valueOf(String.valueOf(data.get('version'))) : null);
        Map<String, Object> af = new Map<String, Object>();
        Object existingAf = data.get('additional_fields');
        if (existingAf instanceof Map<String, Object>) af.putAll((Map<String, Object>) existingAf);
        af.putAll(managed);
        Map<String, Object> payload = new Map<String, Object>();
        payload.putAll(topLevel);
        payload.put('additional_fields', af);
        try {
            return VeleiroApiClient.doPatch('/projects/' + projectId, payload, version);
        } catch (VeleiroApiClient.VeleiroApiException e) {
            if (e.code == 'version_conflict' && e.currentVersion != null && VeleiroSyncConfig.salesforceWins()) {
                // Salesforce manda -> reintenta pisando; si Veleiro manda, relanza (Veleiro gana).
                return VeleiroApiClient.doPatch('/projects/' + projectId, payload, e.currentVersion);
            }
            throw e;
        }
    }

    // Invocable para el flow de Closed Won (crea el project; corre en la ruta async del flow).
    @InvocableMethod(label='Sync Opportunity to Veleiro Project' callout=true)
    public static void syncOpportunitiesInvocable(List<Id> opportunityIds) {
        for (Id oid : opportunityIds) {
            syncOpportunity(oid);
        }
    }
}
