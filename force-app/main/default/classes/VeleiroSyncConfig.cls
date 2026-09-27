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
    public static Boolean autoSyncOpportunity() { return autoSyncOnCreate() && flag(cfg() != null ? cfg().Auto_Sync_Opportunity__c : null); }

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
        Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
        if (c == null || c.Id == null) {
            c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        c.Sync_Direction__c = normalizeDir(direction);
        c.Conflict_Winner__c = (String.isNotBlank(winner) && winner.toLowerCase() == WIN_VELEIRO) ? WIN_VELEIRO : WIN_SF;
        c.Pull_Frequency__c = normalizeFreq(frequency);
        c.Sync_Trigger__c = normalizeTrigger(triggerMode);
        c.Auto_Sync_Account__c = flag(autoAccount);
        c.Auto_Sync_Opportunity__c = flag(autoOpportunity);
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
