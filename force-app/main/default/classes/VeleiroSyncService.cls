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

    // Veleiro solo acepta website_url como URL http(s) absoluta sin espacios; si no, rechaza
    // (400) la creacion completa. Completa el esquema faltante ('acme.com' -> 'https://acme.com')
    // y devuelve null si no se puede arreglar (el client se crea igual, sin analisis).
    @TestVisible
    private static String researchWebsite(String raw) {
        if (String.isBlank(raw)) return null;
        String s = raw.trim();
        if (!s.toLowerCase().startsWith('http://') && !s.toLowerCase().startsWith('https://')) {
            s = 'https://' + s;
        }
        if (s.length() > 1000 || !Pattern.matches('(?i)https?://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?([/?#]\\S*)?', s)) {
            return null;
        }
        return s;
    }

    // Payload de CREATE del client. Con website_url, Veleiro lanza solo el analisis del client
    // (client-info research); solo ocurre al crear, un PATCH no lo dispara.
    private static Map<String, Object> newClientPayload(MappedPayload mp) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.putAll(mp.topLevel);
        payload.put('additional_fields', mp.additional);
        String website = researchWebsite((String) mp.record.get('Website'));
        if (website != null) payload.put('website_url', website);
        return payload;
    }

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

    // Candidatos en Veleiro para un Account aun no vinculado (lo consume el panel).
    @AuraEnabled
    public static VeleiroClientMatcher.MatchResult findClientCandidates(Id accountId) {
        return VeleiroClientMatcher.forAccount(accountId);
    }

    // Vincula el Account a un client existente y lo sincroniza como update (no crea nada).
    // El id NO se guarda antes: un DML previo al callout lanza "uncommitted work pending".
    @AuraEnabled
    public static ClientResult linkAccountToClient(Id accountId, String clientId) {
        if (String.isBlank(clientId)) {
            throw new VeleiroApiClient.VeleiroApiException('Missing Veleiro client id.');
        }
        return syncAccount(accountId, false, clientId.trim());
    }

    // Crea un client nuevo aunque existan candidatos (el usuario lo confirmo en el panel).
    @AuraEnabled
    public static ClientResult createClientForAccount(Id accountId) {
        return syncAccount(accountId, false, null);
    }

    @AuraEnabled
    public static ClientResult syncAccount(Id accountId) {
        // Por defecto se vincula solo cuando la coincidencia es fuerte (mismo sf_account_id o
        // mismo dominio): asi los flows automaticos tampoco duplican clients ya existentes.
        return syncAccount(accountId, true, null);
    }

    // linkClientId != null -> vincular a ese client (sin crear) en esta misma transaccion.
    public static ClientResult syncAccount(Id accountId, Boolean autoLink, String linkClientId) {
        PushOutcome o = pushAccount(accountId, autoLink, linkClientId);
        update o.account;
        return o.result;
    }

    // Empuja el Account a Veleiro SIN guardar en Salesforce: para procesar varias cuentas en
    // una sola transaccion (un DML despues de todos los callouts, nunca entre medio).
    public static Account pushAccountWithoutSaving(Id accountId) {
        return pushAccount(accountId, false, null).account;
    }

    private class PushOutcome {
        ClientResult result;
        Account account; // con el id/version de Veleiro ya puestos, listo para guardar
    }

    private static PushOutcome pushAccount(Id accountId, Boolean autoLink, String linkClientId) {
        // La direccion configurada define si Salesforce puede empujar a Veleiro.
        if (!VeleiroSyncConfig.pushEnabled()) {
            throw new VeleiroApiClient.VeleiroApiException('Push to Veleiro is disabled by the integration config (Veleiro to Salesforce only). Change the direction in the Veleiro Mappings panel.');
        }

        // El payload lo definen los mapeos configurados (Account -> client).
        MappedPayload mp = buildPayload('Account', 'client', accountId,
            new Set<String>{ 'Name', 'Website', 'Veleiro_Client_Id__c', 'Veleiro_Version__c' });
        Account a = (Account) mp.record;

        // Llave de correlacion de sistema: siempre va (no depende del mapeo).
        mp.additional.put('sf_account_id', a.Id);
        // 'name' es obligatorio en Veleiro: si el partner no lo mapeo, cae al Name del registro.
        if (!mp.topLevel.containsKey('name')) mp.topLevel.put('name', a.Name);

        Map<String, Object> result;
        Boolean created = false;

        // Vinculo elegido por el usuario en el panel: se aplica en memoria, se guarda al final.
        if (String.isNotBlank(linkClientId)) {
            a.Veleiro_Client_Id__c = linkClientId;
            a.Veleiro_Version__c = null; // version desconocida -> la toma del GET del client
        }

        // Antes de crear: si el client ya existe en Veleiro, vincular en vez de duplicar.
        if (String.isBlank(a.Veleiro_Client_Id__c) && autoLink == true) {
            VeleiroClientMatcher.Candidate match = VeleiroClientMatcher.autoLinkable(
                VeleiroClientMatcher.forAccount(a.Id));
            if (match != null) a.Veleiro_Client_Id__c = match.clientId;
        }

        if (String.isBlank(a.Veleiro_Client_Id__c)) {
            // CREATE
            result = VeleiroApiClient.doPost('/clients', newClientPayload(mp));
            created = true;
        } else {
            // UPDATE: read-modify-write de additional_fields + If-Match version.
            result = patchClientWithMerge(a.Veleiro_Client_Id__c, mp.topLevel, mp.additional,
                        a.Veleiro_Version__c != null ? Integer.valueOf(a.Veleiro_Version__c) : null);
        }

        // Id + version de Veleiro sobre el registro (el DML lo hace quien llama).
        a.Veleiro_Client_Id__c = (String) result.get('id');
        if (result.get('version') != null) a.Veleiro_Version__c = Integer.valueOf(String.valueOf(result.get('version')));

        ClientResult r = new ClientResult();
        r.clientId = (String) result.get('id');
        r.name = (String) result.get('name');
        r.slug = (String) result.get('slug');
        r.version = (result.get('version') != null) ? Integer.valueOf(String.valueOf(result.get('version'))) : null;
        r.created = created;
        r.synced = true;
        r.veleiroUrl = appBase() + '/a/partner-portal/organizations/' + r.clientId;

        PushOutcome out = new PushOutcome();
        out.result = r;
        out.account = a;
        return out;
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
            MappedPayload amp = buildPayload('Account', 'client', a.Id, new Set<String>{ 'Name', 'Website' });
            amp.additional.put('sf_account_id', a.Id);
            if (!amp.topLevel.containsKey('name')) amp.topLevel.put('name', a.Name);
            Map<String, Object> cRes = VeleiroApiClient.doPost('/clients', newClientPayload(amp));
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

    // ===== Generico: cualquier objeto mapeado -> client / project =====

    public class RecordResult {
        @AuraEnabled public String veleiroId;
        @AuraEnabled public String name;
        @AuraEnabled public String entity;
        @AuraEnabled public Boolean created;
        @AuraEnabled public Boolean synced;
        @AuraEnabled public String veleiroUrl;
    }

    /**
     * Sincroniza CUALQUIER registro cuyo objeto tenga mapeos configurados para esa entidad.
     * Account->client y Opportunity->project conservan su ruta probada; el resto guarda el
     * vinculo en Veleiro_Link__c. Sin mapeos para el par (objeto, entidad) no hace nada:
     * lo que manda es lo configurado en el panel de Veleiro Mappings.
     */
    @AuraEnabled
    public static RecordResult syncRecord(Id recordId, String entity) {
        if (!VeleiroSyncConfig.pushEnabled()) {
            throw new VeleiroApiClient.VeleiroApiException('Push to Veleiro is disabled by the integration config (Veleiro to Salesforce only). Change the direction in the Veleiro Mappings panel.');
        }
        String ent = String.isBlank(entity) ? 'client' : entity.toLowerCase();
        if (ent != 'client' && ent != 'project') {
            throw new VeleiroApiClient.VeleiroApiException('Unknown Veleiro entity: ' + entity);
        }
        String obj = recordId.getSobjectType().getDescribe().getName();

        // Pares nativos: se delega a los metodos ya probados.
        String pair = VeleiroLinkStore.key(obj, ent);
        if (pair == 'account|client') return asRecordResult(syncAccount(recordId), ent);
        if (pair == 'opportunity|project') return asRecordResult(syncOpportunity(recordId), ent);

        if (!hasMappings(obj, ent)) {
            throw new VeleiroApiClient.VeleiroApiException(
                'No Veleiro mapping for ' + obj + ' -> ' + ent + '. Configure it in the Veleiro Mappings tab first.');
        }

        MappedPayload mp = buildPayload(obj, ent, recordId, new Set<String>());
        SObject rec = mp.record;
        mp.additional.put('sf_record_id', String.valueOf(recordId));
        mp.additional.put('sf_object', obj);
        if (!mp.topLevel.containsKey('name')) {
            String fallback = nameOf(rec, obj);
            if (String.isBlank(fallback)) {
                throw new VeleiroApiClient.VeleiroApiException(
                    'Map a field of ' + obj + ' to "name": Veleiro needs a name.');
            }
            mp.topLevel.put('name', fallback);
        }

        VeleiroLinkStore.Link link = VeleiroLinkStore.read(rec, obj, ent);
        Account parentToSave = null;
        Map<String, Object> result;
        Boolean created = false;

        if (String.isBlank(link.veleiroId)) {
            Map<String, Object> payload = new Map<String, Object>(mp.topLevel);
            payload.put('additional_fields', mp.additional);
            if (ent == 'project') {
                // Todo project cuelga de un client: del mapeo, o del Account al que apunte el registro.
                ClientForRecord c = clientFor(rec, obj, mp);
                payload.put('client_id', c.clientId);
                parentToSave = c.accountToSave;
            }
            result = VeleiroApiClient.doPost(ent == 'client' ? '/clients' : '/projects', payload);
            created = true;
        } else {
            mp.topLevel.remove('client_id'); // el client no se cambia en un update
            result = (ent == 'client')
                ? patchClientWithMerge(link.veleiroId, mp.topLevel, mp.additional, link.version)
                : patchProjectWithMerge(link.veleiroId, mp.topLevel, mp.additional, link.version);
        }

        Integer version = (result.get('version') != null)
            ? Integer.valueOf(String.valueOf(result.get('version'))) : null;
        SObject toSave = VeleiroLinkStore.apply(rec, obj, ent, (String) result.get('id'), version);

        // DML al final, despues de todos los callouts.
        if (toSave instanceof Veleiro_Link__c) {
            Veleiro_Link__c row = (Veleiro_Link__c) toSave;
            upsert row Link_Key__c;
        } else {
            update toSave;
        }
        if (parentToSave != null) update parentToSave;

        RecordResult r = new RecordResult();
        r.veleiroId = (String) result.get('id');
        r.name = (String) result.get('name');
        r.entity = ent;
        r.created = created;
        r.synced = true;
        r.veleiroUrl = appBase() + (ent == 'client' ? '/a/partner-portal/organizations/' : '/a/partner-portal/projects/') + r.veleiroId;
        return r;
    }

    public static Boolean hasMappings(String sobjectName, String entity) {
        return [
            SELECT COUNT() FROM Veleiro_Field_Mapping__c
            WHERE SObject__c = :sobjectName AND Veleiro_Entity__c = :entity AND Active__c = true
        ] > 0;
    }

    private class ClientForRecord {
        String clientId;
        Account accountToSave; // si hubo que crear el client del Account, se guarda al final
    }

    // client_id de un project: el mapeado, o el del Account al que apunte el registro.
    private static ClientForRecord clientFor(SObject rec, String obj, MappedPayload mp) {
        ClientForRecord out = new ClientForRecord();
        if (mp.topLevel.get('client_id') != null) {
            out.clientId = String.valueOf(mp.topLevel.remove('client_id'));
            return out;
        }
        Id accountId = lookupAccountId(rec, obj);
        if (accountId == null) {
            throw new VeleiroApiClient.VeleiroApiException(
                'A Veleiro project needs a client: map a field of ' + obj + ' to "client_id", or give the record an Account lookup.');
        }
        Account a = [SELECT Id, Name, Website, Veleiro_Client_Id__c, Veleiro_Version__c FROM Account WHERE Id = :accountId LIMIT 1];
        if (String.isNotBlank(a.Veleiro_Client_Id__c)) {
            out.clientId = a.Veleiro_Client_Id__c;
            return out;
        }
        // El Account aun no tiene client: se crea sin guardar todavia (no hay DML entre callouts).
        Account pushed = pushAccountWithoutSaving(a.Id);
        out.clientId = pushed.Veleiro_Client_Id__c;
        out.accountToSave = pushed;
        return out;
    }

    // Primer lookup a Account del objeto (AccountId, o cualquier relacion a Account).
    // Se consultan aparte: el registro se cargo con los campos del mapeo, no con estos.
    private static Id lookupAccountId(SObject rec, String obj) {
        Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(obj).getDescribe().fields.getMap();
        String standard;
        List<String> others = new List<String>();
        for (String f : fields.keySet()) {
            Schema.DescribeFieldResult d = fields.get(f).getDescribe();
            if (d.getType() == Schema.DisplayType.REFERENCE
                && d.getReferenceTo().size() == 1
                && String.valueOf(d.getReferenceTo()[0]) == 'Account') {
                // AccountId primero: es el estandar y el mas probable.
                if (d.getName().equalsIgnoreCase('AccountId')) standard = d.getName();
                else others.add(d.getName());
            }
        }
        List<String> lookups = new List<String>();
        if (standard != null) lookups.add(standard);
        lookups.addAll(others);
        if (lookups.isEmpty()) return null;

        Id recId = rec.Id;
        String soql = 'SELECT ' + String.join(lookups, ', ') +
                      ' FROM ' + String.escapeSingleQuotes(obj) + ' WHERE Id = :recId LIMIT 1';
        for (SObject row : Database.query(soql)) {
            for (String f : lookups) {
                Id value = (Id) row.get(f);
                if (value != null) return value;
            }
        }
        return null;
    }

    private static String nameOf(SObject rec, String obj) {
        Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(obj).getDescribe().fields.getMap();
        if (!fields.containsKey('name')) return null;
        Id recId = rec.Id;
        for (SObject row : Database.query('SELECT Name FROM ' + String.escapeSingleQuotes(obj) + ' WHERE Id = :recId LIMIT 1')) {
            return (String) row.get('Name');
        }
        return null;
    }

    private static RecordResult asRecordResult(ClientResult c, String entity) {
        RecordResult r = new RecordResult();
        r.veleiroId = c.clientId; r.name = c.name; r.entity = entity;
        r.created = c.created; r.synced = c.synced; r.veleiroUrl = c.veleiroUrl;
        return r;
    }

    private static RecordResult asRecordResult(ProjectResult p, String entity) {
        RecordResult r = new RecordResult();
        r.veleiroId = p.projectId; r.name = p.name; r.entity = entity;
        r.created = p.created; r.synced = p.synced; r.veleiroUrl = p.veleiroUrl;
        return r;
    }

    // Invocable para los flows (Closed Won + auto-sync opp). Apex permite 1 invocable por clase;
    // el de Account vive en VeleiroSyncAccountAction.
    @InvocableMethod(label='Sync Opportunity to Veleiro Project' callout=true)
    public static void syncOpportunitiesInvocable(List<Id> opportunityIds) {
        // Si el Account se creo en la misma operacion (conversion de Lead), su propio auto-sync
        // esta creando el client: esperamos a ese en vez de crear un duplicado.
        Set<Id> waiting = VeleiroOppSyncQueueable.waitingForAccountSync(opportunityIds);
        for (Id oid : opportunityIds) {
            if (!waiting.contains(oid)) syncOpportunity(oid);
        }
        if (!waiting.isEmpty()) {
            VeleiroOppSyncQueueable.defer(waiting, 1);
        }
    }
}
