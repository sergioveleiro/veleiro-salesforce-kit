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
        VeleiroSyncConfig.recordError(String.valueOf(recordId) + ': ' + VeleiroSecurity.forUi(e));
    }

    /**
     * Fallos acumulados durante un lote de callouts, escritos DESPUES en un solo DML.
     * recordError hace un upsert, y un callout despues de un DML truena con "uncommitted work
     * pending": anotar el fallo del registro 1 dentro del bucle dejaba sin sincronizar del 2 en
     * adelante. Se acumula aqui y se vuelca con flush() cuando ya no quedan callouts.
     */
    public class Failures {
        private final List<String> messages = new List<String>();

        public void add(Id recordId, Exception e) {
            add(recordId, VeleiroSecurity.forUi(e));
        }

        public void add(Id recordId, String why) {
            messages.add(String.valueOf(recordId) + ': ' + why);
        }

        public Boolean isEmpty() { return messages.isEmpty(); }
        public Integer size() { return messages.size(); }

        // Un solo registro de error (el panel muestra el ultimo): los mensajes van juntos,
        // recortados a 255 por recordError.
        public void flush() {
            if (messages.isEmpty()) return;
            String summary = messages.size() == 1 ? messages[0]
                : messages.size() + ' failed. ' + String.join(messages, ' | ');
            messages.clear();
            VeleiroSyncConfig.recordError(summary);
        }
    }
}
