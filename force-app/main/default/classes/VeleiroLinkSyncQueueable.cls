/**
 * Empuja a Veleiro los registros recien vinculados desde la pestaña Veleiro Link.
 *
 * Vincular solo escribe el vinculo; los campos mapeados y la llave de correlacion viajan aqui.
 * Un registro por transaccion, encadenando el resto: syncRecord guarda en Salesforce despues
 * de sus callouts, y un segundo registro en la misma transaccion truena con "uncommitted work
 * pending". Encadenar no tiene tope en produccion y sandboxes (si lo tiene en orgs Developer,
 * donde son 5 saltos: ahi conviene vincular en grupos chicos).
 *
 * Si un registro falla (token, 409 que Veleiro gana, permisos), se salta y el lote sigue: el
 * error queda en el debug log y el vinculo, que es lo importante, ya esta guardado.
 */
public with sharing class VeleiroLinkSyncQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible private static Integer batchSize = 1;

    private final List<Id> recordIds;
    private final String entity;

    public VeleiroLinkSyncQueueable(List<Id> recordIds, String entity) {
        this.recordIds = recordIds;
        this.entity = entity;
    }

    public void execute(QueueableContext qc) {
        List<Id> batch = new List<Id>();
        List<Id> rest = new List<Id>();
        for (Integer i = 0; i < recordIds.size(); i++) {
            if (i < batchSize) batch.add(recordIds[i]);
            else rest.add(recordIds[i]);
        }

        for (Id recordId : batch) {
            try {
                VeleiroSyncService.syncRecord(recordId, entity);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'VeleiroLinkSync: ' + recordId + ' -> ' + e.getMessage());
            }
        }

        // La siguiente tanda va en su propia transaccion (limites de callouts).
        if (!rest.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new VeleiroLinkSyncQueueable(rest, entity));
        }
    }
}
