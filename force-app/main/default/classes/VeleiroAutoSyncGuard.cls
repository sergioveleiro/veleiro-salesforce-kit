/**
 * Frenos de las rutas AUTOMATICAS (flows). Existen para proteger la org del cliente, no al kit:
 *
 *  - Carga masiva: un Data Loader de miles de registros encolaria miles de ejecuciones
 *    asincronas y llamadas a Veleiro, comiendose limites que COMPARTE con los procesos del
 *    cliente. Por encima de MAX_AUTO_BATCH el auto-sync se salta el lote y lo deja anotado;
 *    esos registros se sincronizan despues con el boton o con la pestaña Veleiro Link.
 *  - Errores invisibles: los flows atrapan la excepcion y nadie se entera. Aqui se guarda el
 *    ultimo error en la config para que el panel lo muestre.
 */
public with sharing class VeleiroAutoSyncGuard {

    // Un flow bulkificado recibe hasta 200 registros por transaccion; 50 es trabajo humano
    // normal (una conversion de Lead, un punado de altas), no una importacion.
    @TestVisible private static Integer maxAutoBatch = 50;

    public static Boolean tooManyForAutoSync(List<Id> recordIds, String what) {
        if (recordIds == null || recordIds.size() <= maxAutoBatch) return false;
        VeleiroSyncConfig.recordError(
            'Skipped auto-sync of ' + recordIds.size() + ' ' + what + ' (bulk load). '
            + 'Sync them with the button or the Veleiro Link tab.');
        return true;
    }

    // Corre el sync de un registro sin dejar que un fallo tumbe el resto del lote.
    public static void recordFailure(Id recordId, Exception e) {
        VeleiroSyncConfig.recordError(String.valueOf(recordId) + ': ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Veleiro auto-sync ' + recordId + ' -> ' + e.getMessage());
    }
}
