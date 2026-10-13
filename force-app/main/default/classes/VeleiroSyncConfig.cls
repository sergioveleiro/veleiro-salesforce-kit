/**
 * Configuracion GLOBAL de la integracion (definida por el cliente en el panel de Veleiro Mappings):
 *  - Direction: bidirectional | sf_to_veleiro | veleiro_to_sf
 *  - Conflict winner (quien manda en un 409): salesforce | veleiro
 *  - Pull frequency (cada cuanto jala de Veleiro): off | hourly | daily
 *
 * "Reference implementation" (segun el CTO de Veleiro) — el cliente la puede ajustar.
 * Guardada como datos en el custom setting Veleiro_Config__c (nivel Org Default).
 */
public with sharing class VeleiroSyncConfig {

    public static final String DIR_BOTH    = 'bidirectional';
    public static final String DIR_SF      = 'sf_to_veleiro';
    public static final String DIR_VELEIRO = 'veleiro_to_sf';
    public static final String WIN_SF      = 'salesforce';
    public static final String WIN_VELEIRO = 'veleiro';
    public static final String FREQ_OFF    = 'off';
    public static final String FREQ_HOURLY = 'hourly';
    public static final String FREQ_DAILY  = 'daily';
    // Momento en que nace el project de una Opportunity (con el trigger global en auto).
    public static final String OPP_CREATE = 'create';   // al crear la oportunidad
    public static final String OPP_WON    = 'won';      // solo cuando se gana
    public static final String OPP_MANUAL = 'manual';   // nunca sola: solo con el boton
    public static final String TRIG_AUTO   = 'auto';    // sincroniza al crear el registro
    public static final String TRIG_MANUAL = 'manual';  // solo cuando el usuario da clic al boton
    public static final String JOB_NAME    = 'Veleiro Pull Job';

    // ---- lecturas (con defaults sensatos si no se ha configurado) ----
    public static String direction() {
        String d = str(cfg() != null ? cfg().Sync_Direction__c : null);
        return String.isNotBlank(d) ? d : DIR_BOTH;
    }
    public static String winner() {
        String w = str(cfg() != null ? cfg().Conflict_Winner__c : null);
        return String.isNotBlank(w) ? w : WIN_SF;
    }
    public static String frequency() {
        String f = str(cfg() != null ? cfg().Pull_Frequency__c : null);
        return String.isNotBlank(f) ? f : FREQ_OFF;
    }

    public static String syncTrigger() {
        String t = str(cfg() != null ? cfg().Sync_Trigger__c : null);
        return String.isNotBlank(t) ? t : TRIG_MANUAL; // default seguro: manual (nada auto)
    }

    public static Boolean pushEnabled()   { return direction() != DIR_VELEIRO; } // SF -> Veleiro permitido?
    public static Boolean pullEnabled()   { return direction() != DIR_SF; }      // Veleiro -> SF permitido?
    public static Boolean salesforceWins(){ return winner() != WIN_VELEIRO; }
    // Auto-sincronizar al crear? solo si el trigger es 'auto' Y el push (SF->Veleiro) esta permitido.
    public static Boolean autoSyncOnCreate() { return syncTrigger() == TRIG_AUTO && pushEnabled(); }

    // Interruptores por par: con el trigger global en 'auto', cada uno decide si ese par
    // se sincroniza solo. Sin config guardada, ambos vienen encendidos (checkbox default true).
    public static Boolean autoSyncAccount() { return autoSyncOnCreate() && flag(cfg() != null ? cfg().Auto_Sync_Account__c : null); }
    public static Boolean autoSyncOpportunity() { return autoSyncOnCreate() && opportunitySyncMode() != OPP_MANUAL; }

    /**
     * Cuando nace el project: al crear la Opportunity, solo al ganarla, o nunca sola.
     *
     * El campo nuevo manda; en blanco se deduce del checkbox Auto_Sync_Opportunity__c, que es
     * como se configuraba antes. Asi una org que ya tenia el checkbox encendido sigue creando
     * el project al crear la oportunidad, sin que nadie tenga que volver a configurar nada.
     */
    public static String opportunitySyncMode() {
        String m = str(cfg() != null ? cfg().Opportunity_Sync_Mode__c : null);
        if (m == OPP_CREATE || m == OPP_WON || m == OPP_MANUAL) return m;
        return flag(cfg() != null ? cfg().Auto_Sync_Opportunity__c : null) ? OPP_CREATE : OPP_MANUAL;
    }

    // El pull solo pisa Account.Name si el cliente lo enciende a proposito.
    public static Boolean pullWritesName() { return cfg() != null && cfg().Pull_Writes_Name__c == true; }

    // Los flows se tragan los errores: aqui queda el ultimo para que el panel lo muestre.
    public static void recordError(String message) {
        try {
            Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
            if (c == null || c.Id == null) c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
            c.Last_Sync_Error__c = String.isBlank(message) ? null : message.abbreviate(255);
            c.Last_Sync_Error_At__c = System.now();
            upsert c;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'No se pudo registrar el error: ' + e.getMessage());
        }
    }

    public static String lastError() { return cfg() != null ? cfg().Last_Sync_Error__c : null; }
    public static Datetime lastErrorAt() { return cfg() != null ? cfg().Last_Sync_Error_At__c : null; }

    // Valor tal cual del interruptor, para mostrarlo en el panel.
    public static Boolean autoSyncAccountFlag() { return flag(cfg() != null ? cfg().Auto_Sync_Account__c : null); }
    public static Boolean autoSyncOpportunityFlag() { return flag(cfg() != null ? cfg().Auto_Sync_Opportunity__c : null); }

    /**
     * Prefijo del namespace cuando el kit corre como paquete administrado ('veleiro__'), vacio
     * cuando se desplego del codigo fuente. Se deduce del nombre real de un objeto nuestro: sin
     * namespace son 2 partes ('Veleiro_Field_Mapping', 'c'), con namespace son 3. Lo usan las
     * pantallas que navegan a otra pestaña, porque las pestañas tambien llevan prefijo.
     */
    // Costura para los tests: sin namespace el bug del prefijo es INVISIBLE, porque aqui siempre
    // sale vacio. Simularlo es la unica forma de probar en el codigo fuente lo que solo falla
    // dentro del paquete administrado.
    @TestVisible private static String namespaceOverride;

    public static String namespacePrefix() {
        if (namespaceOverride != null) return namespaceOverride;
        List<String> parts = String.valueOf(Veleiro_Field_Mapping__c.SObjectType).split('__');
        return parts.size() >= 3 ? parts[0] + '__' : '';
    }

    // Un checkbox sin registro de config todavia cuenta como encendido.
    private static Boolean flag(Boolean value) { return value == null ? true : value; }

    // ---- escritura + (re)programacion del job ----
    public static void save(String direction, String winner, String frequency, String triggerMode) {
        save(direction, winner, frequency, triggerMode, true, true, false);
    }

    public static void save(String direction, String winner, String frequency, String triggerMode,
                            Boolean autoAccount, Boolean autoOpportunity) {
        save(direction, winner, frequency, triggerMode, autoAccount, autoOpportunity, pullWritesName());
    }

    public static void save(String direction, String winner, String frequency, String triggerMode,
                            Boolean autoAccount, Boolean autoOpportunity, Boolean pullWritesName) {
        // Sin modo explicito se respeta el que ya este guardado (o el que deduce el checkbox).
        save(direction, winner, frequency, triggerMode, autoAccount, autoOpportunity, pullWritesName,
             autoOpportunity == false ? OPP_MANUAL : opportunitySyncMode());
    }

    public static void save(String direction, String winner, String frequency, String triggerMode,
                            Boolean autoAccount, Boolean autoOpportunity, Boolean pullWritesName,
                            String opportunityMode) {
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c == null || c.Id == null) {
            c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        c.Sync_Direction__c = normalizeDir(direction);
        c.Conflict_Winner__c = (String.isNotBlank(winner) && winner.toLowerCase() == WIN_VELEIRO) ? WIN_VELEIRO : WIN_SF;
        c.Pull_Frequency__c = normalizeFreq(frequency);
        c.Sync_Trigger__c = normalizeTrigger(triggerMode);
        c.Auto_Sync_Account__c = flag(autoAccount);
        String mode = normalizeOppMode(opportunityMode);
        c.Opportunity_Sync_Mode__c = mode;
        // El checkbox se mantiene en sintonia: hay orgs con la version anterior leyendolo.
        c.Auto_Sync_Opportunity__c = (mode != OPP_MANUAL);
        c.Pull_Writes_Name__c = pullWritesName == true; // por defecto NO se pisa el nombre
        upsert c;
        reschedule(c.Pull_Frequency__c);
    }

    // Aborta el job existente y lo re-agenda segun la frecuencia (off = solo aborta).
    public static void reschedule(String frequency) {
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME]) {
            System.abortJob(ct.Id);
        }
        String f = normalizeFreq(frequency);
        if (f == FREQ_HOURLY) {
            System.schedule(JOB_NAME, '0 0 * * * ?', new VeleiroPullJob());       // cada hora, minuto 0
        } else if (f == FREQ_DAILY) {
            System.schedule(JOB_NAME, '0 0 2 * * ?', new VeleiroPullJob());       // diario 2:00 AM
        }
        // off -> queda abortado, no se re-agenda
    }

    private static String normalizeDir(String d) {
        String v = str(d);
        if (v == DIR_SF || v == DIR_VELEIRO) return v;
        return DIR_BOTH;
    }
    private static String normalizeFreq(String f) {
        String v = str(f);
        if (v == FREQ_HOURLY || v == FREQ_DAILY) return v;
        return FREQ_OFF;
    }
    private static String normalizeOppMode(String m) {
        String v = str(m);
        if (v == OPP_WON || v == OPP_MANUAL) return v;
        return OPP_CREATE;
    }
    private static String normalizeTrigger(String tm) {
        return str(tm) == TRIG_AUTO ? TRIG_AUTO : TRIG_MANUAL;
    }
    private static String str(String s) { return (s == null) ? null : s.trim().toLowerCase(); }

    private static Veleiro_Config__c cfg() {
        Veleiro_Config__c c = Veleiro_Config__c.getInstance();
        if (c == null || (String.isBlank(c.Sync_Direction__c) && String.isBlank(c.Pull_Frequency__c))) {
            Veleiro_Config__c org = Veleiro_Config__c.getOrgDefaults();
            if (org != null) return org;
        }
        return c;
    }
}
