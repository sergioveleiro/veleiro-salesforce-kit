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
                s.connectionMessage = 'Conectado a Veleiro';
            } catch (Exception e) {
                s.connectionMessage = e.getMessage();
            }
        } else if (tokenSet) {
            s.connected = true;   // sin ping: el token existe, es lo mas que sabemos sin callout
            s.connectionMessage = 'Token guardado';
        } else {
            s.connectionMessage = 'Falta el token de Veleiro';
        }
        s.environment = VeleiroApiClient.appBaseUrl();
        s.direction = VeleiroSyncConfig.direction();
        s.syncTrigger = VeleiroSyncConfig.syncTrigger();
        s.lastError = VeleiroSyncConfig.lastError();
        s.lastErrorAt = VeleiroSyncConfig.lastErrorAt() == null ? null : VeleiroSyncConfig.lastErrorAt().format();

        Step conn = new Step('connection', 'Conecta tu cuenta de Veleiro',
            'Pega el API token de Veleiro. Salesforce habla con Veleiro de servidor a servidor: el token se queda en la org y nunca llega al navegador.');
        conn.inline = 'token';
        conn.state = s.connected ? DONE : TODO;
        conn.evidence = s.connectionMessage;
        s.steps.add(conn);

        // --- como sincroniza ---
        Boolean configured = String.isNotBlank(storedTrigger());
        Step cfg = new Step('config', 'Elige cómo sincroniza',
            'Define si Salesforce empuja, jala o las dos, y si lo hace al crear el registro o solo cuando das clic. Mientras no lo guardes, el kit se queda en manual y no toca nada por su cuenta.');
        cfg.inline = 'config';
        cfg.state = configured ? DONE : TODO;
        cfg.evidence = configured
            ? label(s.direction) + ' · ' + label(s.syncTrigger)
            : 'Sin guardar — por ahora, manual';
        s.steps.add(cfg);

        // --- mapeo ---
        s.mappingCount = [SELECT COUNT() FROM Veleiro_Field_Mapping__c WHERE Active__c = true];
        Step mapStep = new Step('mapping', 'Mapea tus campos',
            'Elige qué objeto de Salesforce corresponde a un client o a un project en Veleiro, y qué campo va a dónde. Sin un mapeo no hay nada que sincronizar ni que vincular.');
        mapStep.state = s.mappingCount > 0 ? DONE : TODO;
        mapStep.evidence = s.mappingCount > 0
            ? s.mappingCount + (s.mappingCount == 1 ? ' campo mapeado' : ' campos mapeados')
            : 'Ningún campo mapeado todavía';
        mapStep.actionLabel = 'Abrir Veleiro Mappings';
        mapStep.actionTab = tab('Veleiro_Mappings');
        s.steps.add(mapStep);

        // --- vincular lo que ya existe (opcional: hay orgs sin historia) ---
        s.linkedCount = linkedCount();
        Step linkStep = new Step('link', 'Vincula lo que ya existe',
            'Si tus clientes ya existían en Veleiro y en Salesforce antes del kit, aquí los emparejas en vez de crearlos de nuevo. Veleiro te sugiere el registro que se le parece y tú confirmas.');
        linkStep.optional = true;
        linkStep.state = s.linkedCount > 0 ? DONE : (skips.contains('link') ? SKIPPED : TODO);
        linkStep.evidence = s.linkedCount > 0
            ? s.linkedCount + (s.linkedCount == 1 ? ' registro vinculado' : ' registros vinculados')
            : 'Nada vinculado — sáltalo si empiezas de cero';
        linkStep.actionLabel = 'Abrir Veleiro Link';
        linkStep.actionTab = tab('Veleiro_Link');
        s.steps.add(linkStep);

        // --- primer sync real ---
        s.syncedCount = syncedCount();
        Step syncStep = new Step('sync', 'Sincroniza tu primera cuenta',
            'Abre una Account y dale Sync. Es la prueba de que todo el camino funciona: Salesforce crea o actualiza el client en Veleiro y se trae su versión de vuelta.');
        syncStep.state = s.syncedCount > 0 ? DONE : TODO;
        syncStep.evidence = s.syncedCount > 0
            ? s.syncedCount + (s.syncedCount == 1 ? ' registro sincronizado' : ' registros sincronizados')
            : 'Ningún registro ha viajado a Veleiro';
        syncStep.actionLabel = 'Ver mis Accounts';
        syncStep.actionObject = 'Account';
        s.steps.add(syncStep);

        // --- flows: solo importan con el trigger en auto, y es justo lo que se rompe callado ---
        if (s.syncTrigger == VeleiroSyncConfig.TRIG_AUTO) {
            Step flows = new Step('flows', 'Activa los flows de sincronización automática',
                'Pediste sincronización automática, y eso lo hacen tres flows. En producción los flows se instalan inactivos: si no los enciendes, nada se sincroniza solo y no sale ningún error.');
            flows.state = flowState(flows);
            s.steps.add(flows);
        }

        // --- equipo (opcional: una org de una sola persona es legitima) ---
        Step team = new Step('team', 'Dale acceso a tu equipo',
            'El permission set Veleiro Integration Access es lo único que da acceso al app, a los campos y a los paneles. Sin él, tu equipo entra y no ve nada.');
        team.optional = true;
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
            for (String f : FLOWS) { wanted.add(f); wanted.add(prefix() + f); }
            Integer active = 0;
            List<String> inactive = new List<String>();
            for (FlowDefinitionView f : [
                SELECT ApiName, Label, IsActive FROM FlowDefinitionView WHERE ApiName IN :wanted
            ]) {
                if (f.IsActive) { active++; } else { inactive.add(f.Label); }
            }
            if (active >= FLOWS.size()) {
                st.evidence = 'Los 3 flows están activos';
                return DONE;
            }
            st.evidence = inactive.isEmpty()
                ? 'No encontré los flows en esta org'
                : 'Inactivos: ' + String.join(inactive, ', ');
            st.actionLabel = 'Cómo activarlos';
            return TODO;
        } catch (Exception e) {
            st.evidence = 'No pude revisarlo — hace falta permiso para ver la configuración de la org';
            return UNKNOWN;
        }
    }

    private static String teamState(Step st, Set<String> skips) {
        try {
            Integer others = [
                SELECT COUNT() FROM PermissionSetAssignment
                WHERE PermissionSet.Name = :PERMSET AND AssigneeId != :UserInfo.getUserId()
            ];
            if (others > 0) {
                st.evidence = others + (others == 1 ? ' persona más tiene acceso' : ' personas más tienen acceso');
                return DONE;
            }
            st.evidence = 'Solo tú tienes el permission set';
            st.actionLabel = 'Asignar el permission set';
            return skips.contains('team') ? SKIPPED : TODO;
        } catch (Exception e) {
            st.evidence = 'No pude revisar las asignaciones del permission set';
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

    /**
     * Prefijo del namespace cuando el kit corre como paquete administrado ('veleiro__'), vacio
     * cuando se desplego del codigo fuente. Se deduce del nombre real de un objeto nuestro:
     * sin namespace son 2 partes ('Veleiro_Field_Mapping', 'c'), con namespace son 3.
     */
    @TestVisible
    private static String prefix() {
        List<String> parts = String.valueOf(Veleiro_Field_Mapping__c.SObjectType).split('__');
        return parts.size() >= 3 ? parts[0] + '__' : '';
    }

    // Las pestanas tambien llevan prefijo dentro del paquete administrado.
    private static String tab(String apiName) { return prefix() + apiName; }

    private static String label(String raw) {
        if (raw == VeleiroSyncConfig.DIR_BOTH) return 'Salesforce ⇄ Veleiro';
        if (raw == VeleiroSyncConfig.DIR_SF) return 'Salesforce → Veleiro';
        if (raw == VeleiroSyncConfig.DIR_VELEIRO) return 'Veleiro → Salesforce';
        if (raw == VeleiroSyncConfig.TRIG_AUTO) return 'automático';
        if (raw == VeleiroSyncConfig.TRIG_MANUAL) return 'manual';
        return raw;
    }
}
