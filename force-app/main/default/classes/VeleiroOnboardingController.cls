/**
 * Estado del setup del kit, medido contra la org real y no contra banderas que alguien
 * tuvo que marcar a mano. Cada paso tiene su propia senal en los datos:
 *
 *   connection -> token puesto + un GET real a /clients
 *   config     -> Sync_Trigger__c escrito (el campo nace en blanco: solo un Save lo llena)
 *   mapping    -> al menos un Veleiro_Field_Mapping__c activo
 *   link       -> al menos un registro con id de Veleiro
 *   sync       -> al menos un registro con version (la version solo puede venir de la API)
 *   flows      -> los tres flows activos (solo cuenta con el trigger en auto)
 *   team       -> el permission set asignado a alguien mas que quien instalo
 *
 * Las lecturas de Account/Opportunity filtran primero por el external id (indexado) para que
 * el conteo siga siendo selectivo en una org con millones de registros.
 */
public with sharing class VeleiroOnboardingController {

    public static final String DONE    = 'done';
    public static final String TODO    = 'todo';
    public static final String SKIPPED = 'skipped';
    public static final String UNKNOWN = 'unknown';   // no se pudo verificar (permisos)

    private static final String PERMSET = 'Veleiro_Integration_Access';
    // Costuras para los tests: en la org de un cliente puede haber asignaciones reales, y un
    // test que dependa de ellas falla en unas orgs y pasa en otras (y tumba su deploy).
    @TestVisible private static Integer assignedToMe = null;
    @TestVisible private static Integer assignedToOthers = null;
    private static final List<String> FLOWS = new List<String>{
        'Auto_Sync_Account_On_Create',
        'Auto_Sync_Opportunity_On_Create',
        'Create_Veleiro_Project_On_Closed_Won'
    };

    public class Step {
        @AuraEnabled public String key;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;      // que es y por que importa
        @AuraEnabled public String state;        // done | todo | skipped | unknown
        @AuraEnabled public Boolean optional = false;
        @AuraEnabled public String evidence;     // '3 mapeos activos'
        @AuraEnabled public String actionLabel;
        @AuraEnabled public String actionTab;    // api name de la pestana (con prefijo si aplica)
        @AuraEnabled public String actionObject; // objeto cuya lista abrir (Account)
        @AuraEnabled public String inline;       // bloque que el UI dibuja dentro del paso

        private Step(String key, String title, String summary) {
            this.key = key;
            this.title = title;
            this.summary = summary;
            this.state = TODO;
        }
    }

    public class State {
        @AuraEnabled public List<Step> steps = new List<Step>();
        @AuraEnabled public Integer done = 0;        // pasos obligatorios cumplidos
        @AuraEnabled public Integer total = 0;       // pasos obligatorios
        @AuraEnabled public Boolean complete = false;
        @AuraEnabled public String setupTab;         // api name de esta pestana (el aviso del Home la abre)
        // salud de la integracion (lo que queda cuando el setup ya esta completo)
        @AuraEnabled public Boolean connected = false;
        @AuraEnabled public String connectionMessage;
        @AuraEnabled public String environment;
        @AuraEnabled public String direction;
        @AuraEnabled public String syncTrigger;
        @AuraEnabled public Integer mappingCount = 0;
        @AuraEnabled public Integer linkedCount = 0;
        @AuraEnabled public Integer syncedCount = 0;
        @AuraEnabled public String lastError;
        @AuraEnabled public String lastErrorAt;
    }

    /**
     * verifyConnection = false evita el callout: lo usa el aviso del Home, que solo necesita
     * el avance. La pestana de setup lo llama con true para probar la conexion de verdad.
     */
    @AuraEnabled
    public static State getState(Boolean verifyConnection) {
        State s = new State();
        s.setupTab = tab('Veleiro_Setup');
        Set<String> skips = skippedKeys();

        // --- conexion ---
        Boolean tokenSet = VeleiroApiClient.hasToken();
        if (tokenSet && verifyConnection == true) {
            try {
                VeleiroApiClient.doGet('/clients', new Map<String, String>{ 'limit' => '1' });
                s.connected = true;
                s.connectionMessage = VeleiroI18n.t('ev.connected');
            } catch (Exception e) {
                s.connectionMessage = e.getMessage();
            }
        } else if (tokenSet) {
            s.connected = true;   // sin ping: el token existe, es lo mas que sabemos sin callout
            s.connectionMessage = VeleiroI18n.t('ev.tokenSaved');
        } else {
            s.connectionMessage = VeleiroI18n.t('ev.noToken');
        }
        s.environment = VeleiroApiClient.appBaseUrl();
        s.direction = VeleiroSyncConfig.direction();
        s.syncTrigger = VeleiroSyncConfig.syncTrigger();
        s.lastError = VeleiroSyncConfig.lastError();
        s.lastErrorAt = VeleiroSyncConfig.lastErrorAt() == null ? null : VeleiroSyncConfig.lastErrorAt().format();

        Step conn = new Step('connection', VeleiroI18n.t('step.connection.title'),
            VeleiroI18n.t('step.connection.summary'));
        conn.inline = 'token';
        conn.state = s.connected ? DONE : TODO;
        conn.evidence = s.connectionMessage;
        s.steps.add(conn);

        // --- como sincroniza ---
        Boolean configured = String.isNotBlank(storedTrigger());
        Step cfg = new Step('config', VeleiroI18n.t('step.config.title'),
            VeleiroI18n.t('step.config.summary'));
        cfg.inline = 'config';
        cfg.state = configured ? DONE : TODO;
        cfg.evidence = configured
            ? label(s.direction) + ' · ' + label(s.syncTrigger)
            : VeleiroI18n.t('ev.configUnsaved');
        s.steps.add(cfg);

        // --- mapeo ---
        s.mappingCount = [SELECT COUNT() FROM Veleiro_Field_Mapping__c WHERE Active__c = true];
        Step mapStep = new Step('mapping', VeleiroI18n.t('step.mapping.title'),
            VeleiroI18n.t('step.mapping.summary'));
        mapStep.state = s.mappingCount > 0 ? DONE : TODO;
        mapStep.evidence = s.mappingCount > 0
            ? VeleiroI18n.plural(s.mappingCount, 'ev.mappedField', 'ev.mappedFields')
            : VeleiroI18n.t('ev.noMappings');
        mapStep.actionLabel = VeleiroI18n.t('act.openMappings');
        mapStep.actionTab = tab('Veleiro_Mappings');
        s.steps.add(mapStep);

        // --- vincular lo que ya existe (opcional: hay orgs sin historia) ---
        s.linkedCount = linkedCount();
        Step linkStep = new Step('link', VeleiroI18n.t('step.link.title'),
            VeleiroI18n.t('step.link.summary'));
        linkStep.optional = true;
        linkStep.state = s.linkedCount > 0 ? DONE : (skips.contains('link') ? SKIPPED : TODO);
        linkStep.evidence = s.linkedCount > 0
            ? VeleiroI18n.plural(s.linkedCount, 'ev.linkedRecord', 'ev.linkedRecords')
            : VeleiroI18n.t('ev.nothingLinked');
        linkStep.actionLabel = VeleiroI18n.t('act.openLink');
        linkStep.actionTab = tab('Veleiro_Link');
        s.steps.add(linkStep);

        // --- primer sync real ---
        s.syncedCount = syncedCount();
        Step syncStep = new Step('sync', VeleiroI18n.t('step.sync.title'),
            VeleiroI18n.t('step.sync.summary'));
        syncStep.state = s.syncedCount > 0 ? DONE : TODO;
        syncStep.evidence = s.syncedCount > 0
            ? VeleiroI18n.plural(s.syncedCount, 'ev.syncedRecord', 'ev.syncedRecords')
            : VeleiroI18n.t('ev.nothingSynced');
        syncStep.actionLabel = VeleiroI18n.t('act.myAccounts');
        syncStep.actionObject = 'Account';
        s.steps.add(syncStep);

        // --- flows: solo importan con el trigger en auto, y es justo lo que se rompe callado ---
        if (s.syncTrigger == VeleiroSyncConfig.TRIG_AUTO) {
            Step flows = new Step('flows', VeleiroI18n.t('step.flows.title'),
                VeleiroI18n.t('step.flows.summary'));
            flows.state = flowState(flows);
            s.steps.add(flows);
        }

        // --- acceso: el permission set es lo UNICO que da acceso (los profiles no se empaquetan) ---
        Step team = new Step('team', VeleiroI18n.t('step.team.title'),
            VeleiroI18n.t('step.team.summary'));
        // teamState decide tambien si es opcional: si le falta a quien esta configurando, no lo es.
        team.state = teamState(team, skips);
        s.steps.add(team);

        for (Step st : s.steps) {
            if (st.optional) continue;
            s.total++;
            if (st.state == DONE) s.done++;
        }
        s.complete = s.done == s.total;
        return s;
    }

    // Marca un paso opcional como "no aplica" (o lo devuelve a pendiente).
    @AuraEnabled
    public static void skipStep(String key, Boolean skip) {
        if (String.isBlank(key)) return;
        Set<String> keys = skippedKeys();
        if (skip == false) { keys.remove(key); } else { keys.add(key); }
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c == null || c.Id == null) c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        c.Onboarding_Skipped__c = keys.isEmpty() ? null : String.join(new List<String>(keys), ',').abbreviate(255);
        upsert c;
    }

    // ---- señales ----

    // Vinculado = tiene id de Veleiro. El filtro arranca por el external id, que esta indexado.
    private static Integer linkedCount() {
        return [SELECT COUNT() FROM Account WHERE Veleiro_Client_Id__c != null]
             + [SELECT COUNT() FROM Opportunity WHERE Veleiro_Project_Id__c != null]
             + [SELECT COUNT() FROM Veleiro_Link__c];
    }

    // Sincronizado = ademas trae version, y la version solo la devuelve la API de Veleiro.
    private static Integer syncedCount() {
        return [SELECT COUNT() FROM Account WHERE Veleiro_Client_Id__c != null AND Veleiro_Version__c != null]
             + [SELECT COUNT() FROM Opportunity WHERE Veleiro_Project_Id__c != null AND Veleiro_Project_Version__c != null]
             + [SELECT COUNT() FROM Veleiro_Link__c WHERE Veleiro_Version__c != null];
    }

    // FlowDefinitionView necesita permisos de Setup: si no se puede leer, el paso queda en
    // 'unknown' con su explicacion, en vez de mentir diciendo que falta.
    private static String flowState(Step st) {
        try {
            Set<String> wanted = new Set<String>();
            for (String f : FLOWS) { wanted.add(f); wanted.add(VeleiroSyncConfig.namespacePrefix() + f); }
            Integer active = 0;
            List<String> inactive = new List<String>();
            for (FlowDefinitionView f : [
                SELECT ApiName, Label, IsActive FROM FlowDefinitionView WHERE ApiName IN :wanted
            ]) {
                if (f.IsActive) { active++; } else { inactive.add(f.Label); }
            }
            if (active >= FLOWS.size()) {
                st.evidence = VeleiroI18n.t('ev.flowsActive');
                return DONE;
            }
            st.evidence = inactive.isEmpty()
                ? VeleiroI18n.t('ev.flowsMissing')
                : VeleiroI18n.t('ev.flowsInactive', new List<Object>{ String.join(inactive, ', ') });
            st.actionLabel = VeleiroI18n.t('act.howToActivate');
            return TODO;
        } catch (Exception e) {
            st.evidence = VeleiroI18n.t('ev.flowsUnknown');
            return UNKNOWN;
        }
    }

    /**
     * Tres situaciones distintas, no dos:
     *  - ni quien esta mirando lo tiene -> el kit se ve roto (campos invisibles, paneles vacios).
     *    Esto no es un consejo, es el paso que hay que hacer, y por eso deja de ser opcional.
     *  - solo quien esta mirando lo tiene -> funciona, pero el equipo no lo ve. Se puede saltar.
     *  - alguien mas lo tiene -> listo.
     */
    private static String teamState(Step st, Set<String> skips) {
        try {
            Integer mine = (assignedToMe != null) ? assignedToMe : [
                SELECT COUNT() FROM PermissionSetAssignment
                WHERE PermissionSet.Name = :PERMSET AND AssigneeId = :UserInfo.getUserId()
            ];
            Integer others = (assignedToOthers != null) ? assignedToOthers : [
                SELECT COUNT() FROM PermissionSetAssignment
                WHERE PermissionSet.Name = :PERMSET AND AssigneeId != :UserInfo.getUserId()
            ];
            st.actionLabel = VeleiroI18n.t('act.assignPermset');
            st.optional = true;
            if (mine == 0) {
                // Nada del kit se ve sin esto: no es un consejo que se pueda saltar.
                st.optional = false;
                st.evidence = VeleiroI18n.t('ev.teamNobody');
                return TODO;
            }
            if (others > 0) {
                st.evidence = VeleiroI18n.plural(others, 'ev.teamOther', 'ev.teamOthers');
                st.actionLabel = null;
                return DONE;
            }
            st.evidence = VeleiroI18n.t('ev.teamOnlyYou');
            return skips.contains('team') ? SKIPPED : TODO;
        } catch (Exception e) {
            st.optional = true;
            st.evidence = VeleiroI18n.t('ev.teamUnknown');
            return UNKNOWN;
        }
    }

    // ---- utilerias ----

    private static Set<String> skippedKeys() {
        Set<String> out = new Set<String>();
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c != null && String.isNotBlank(c.Onboarding_Skipped__c)) {
            for (String k : c.Onboarding_Skipped__c.split(',')) {
                if (String.isNotBlank(k)) out.add(k.trim());
            }
        }
        return out;
    }

    // Valor crudo del campo: en blanco significa que nadie ha guardado la configuracion.
    private static String storedTrigger() {
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        return (c == null) ? null : c.Sync_Trigger__c;
    }

    // Las pestanas llevan prefijo de namespace dentro del paquete administrado.
    private static String tab(String apiName) { return VeleiroSyncConfig.namespacePrefix() + apiName; }

    private static String label(String raw) {
        if (raw == VeleiroSyncConfig.DIR_BOTH) return VeleiroI18n.t('cfg.both');
        if (raw == VeleiroSyncConfig.DIR_SF) return VeleiroI18n.t('cfg.sfToVeleiro');
        if (raw == VeleiroSyncConfig.DIR_VELEIRO) return VeleiroI18n.t('cfg.veleiroToSf');
        if (raw == VeleiroSyncConfig.TRIG_AUTO) return VeleiroI18n.t('cfg.auto');
        if (raw == VeleiroSyncConfig.TRIG_MANUAL) return VeleiroI18n.t('cfg.manual');
        return raw;
    }
}
