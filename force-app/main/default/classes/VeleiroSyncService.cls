/**
 * Sincronizacion Salesforce -> Veleiro (write). Manual, desde el boton "Sync with Veleiro".
 * Account -> client de Veleiro. Crea si es nuevo; si ya existe, actualiza campos.
 * additional_fields se maneja read-modify-write (el PATCH lo reemplaza entero).
 */
public with sharing class VeleiroSyncService {

    // Base humana de la app Veleiro (para el hipervinculo). Configurable a futuro.
    // Base humana del portal de Veleiro (hipervinculos). Config: Veleiro_Config__c.App_Base_Url__c (default beta).
    private static String appBase() { return VeleiroApiClient.appBaseUrl(); }

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
        Account a = [
            SELECT Id, Name, Website, Veleiro_Client_Id__c, Veleiro_Version__c
            FROM Account WHERE Id = :accountId LIMIT 1
        ];

        // Campos "gestionados" que empujamos a additional_fields (Fase 1: linkage basico).
        Map<String, Object> managed = new Map<String, Object>{
            'sf_account_id' => a.Id,
            'sf_account_name' => a.Name
        };
        if (String.isNotBlank(a.Website)) managed.put('sf_website', a.Website);

        Map<String, Object> result;
        Boolean created = false;

        if (String.isBlank(a.Veleiro_Client_Id__c)) {
            // CREATE
            Map<String, Object> payload = new Map<String, Object>{
                'name' => a.Name,
                'additional_fields' => managed
            };
            result = VeleiroApiClient.doPost('/clients', payload);
            created = true;
        } else {
            // UPDATE: read-modify-write de additional_fields + If-Match version.
            result = patchClientWithMerge(a.Veleiro_Client_Id__c, a.Name, managed,
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

    // GET actual -> merge de las llaves gestionadas -> PATCH del additional_fields completo.
    // Reintenta una vez si hay 409 version_conflict usando detail.current_version.
    private static Map<String, Object> patchClientWithMerge(String clientId, String name, Map<String, Object> managed, Integer knownVersion) {
        Map<String, Object> current = VeleiroApiClient.doGet('/clients/' + clientId, null);
        Map<String, Object> data = (Map<String, Object>) current.get('data');
        Integer version = (knownVersion != null) ? knownVersion
                          : (data.get('version') != null ? Integer.valueOf(String.valueOf(data.get('version'))) : null);

        Map<String, Object> af = new Map<String, Object>();
        Object existingAf = data.get('additional_fields');
        if (existingAf instanceof Map<String, Object>) af.putAll((Map<String, Object>) existingAf);
        af.putAll(managed); // sobreescribe solo nuestras llaves gestionadas, preserva el resto

        Map<String, Object> payload = new Map<String, Object>{
            'name' => name,
            'additional_fields' => af
        };
        try {
            return VeleiroApiClient.doPatch('/clients/' + clientId, payload, version);
        } catch (VeleiroApiClient.VeleiroApiException e) {
            if (e.code == 'version_conflict' && e.currentVersion != null) {
                // re-leer + reintentar una vez con la version actual
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
        Opportunity o = [
            SELECT Id, Name, Amount, CloseDate, AccountId, Veleiro_Project_Id__c, Veleiro_Project_Version__c
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        if (o.AccountId == null) {
            throw new VeleiroApiClient.VeleiroApiException('The Opportunity has no Account.');
        }
        Account a = [
            SELECT Id, Name, Website, Veleiro_Client_Id__c, Veleiro_Version__c
            FROM Account WHERE Id = :o.AccountId LIMIT 1
        ];

        // Asegurar el client (crearlo si el Account aun no esta sincronizado) - callout
        String clientId = a.Veleiro_Client_Id__c;
        Boolean accountNeedsUpdate = false;
        if (String.isBlank(clientId)) {
            Map<String, Object> af = new Map<String, Object>{ 'sf_account_id' => a.Id, 'sf_account_name' => a.Name };
            if (String.isNotBlank(a.Website)) af.put('sf_website', a.Website);
            Map<String, Object> cRes = VeleiroApiClient.doPost('/clients',
                new Map<String, Object>{ 'name' => a.Name, 'additional_fields' => af });
            clientId = (String) cRes.get('id');
            a.Veleiro_Client_Id__c = clientId;
            if (cRes.get('version') != null) a.Veleiro_Version__c = Integer.valueOf(String.valueOf(cRes.get('version')));
            accountNeedsUpdate = true;
        }

        // additional_fields del project
        Map<String, Object> paf = new Map<String, Object>{ 'sf_opportunity_id' => o.Id };
        if (o.Amount != null) paf.put('sf_amount', o.Amount);
        if (o.CloseDate != null) paf.put('sf_close_date', String.valueOf(o.CloseDate));

        Map<String, Object> result;
        Boolean created = false;
        if (String.isBlank(o.Veleiro_Project_Id__c)) {
            result = VeleiroApiClient.doPost('/projects',
                new Map<String, Object>{ 'name' => o.Name, 'client_id' => clientId, 'additional_fields' => paf });
            created = true;
        } else {
            result = patchProjectWithMerge(o.Veleiro_Project_Id__c, o.Name, paf,
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

    private static Map<String, Object> patchProjectWithMerge(String projectId, String name, Map<String, Object> managed, Integer knownVersion) {
        Map<String, Object> current = VeleiroApiClient.doGet('/projects/' + projectId, null);
        Map<String, Object> data = (Map<String, Object>) current.get('data');
        Integer version = (knownVersion != null) ? knownVersion
                          : (data.get('version') != null ? Integer.valueOf(String.valueOf(data.get('version'))) : null);
        Map<String, Object> af = new Map<String, Object>();
        Object existingAf = data.get('additional_fields');
        if (existingAf instanceof Map<String, Object>) af.putAll((Map<String, Object>) existingAf);
        af.putAll(managed);
        Map<String, Object> payload = new Map<String, Object>{ 'name' => name, 'additional_fields' => af };
        try {
            return VeleiroApiClient.doPatch('/projects/' + projectId, payload, version);
        } catch (VeleiroApiClient.VeleiroApiException e) {
            if (e.code == 'version_conflict' && e.currentVersion != null) {
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
