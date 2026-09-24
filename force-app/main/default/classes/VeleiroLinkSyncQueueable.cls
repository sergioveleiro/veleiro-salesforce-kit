/**
 * Empuja a Veleiro las cuentas recien vinculadas desde la pestaña Veleiro Link.
 *
 * Vincular solo escribe el id; los campos mapeados (sf_website, sf_phone, ...) y el
 * sf_account_id viajan aqui. Se procesa por tandas porque cada cuenta gasta 2 callouts
 * (GET + PATCH) y Salesforce permite 100 por transaccion. Todos los callouts van primero
 * y el DML al final: un DML entre callouts lanza "uncommitted work pending".
 *
 * Si una cuenta falla (token, 409 que Veleiro gana, permisos), se salta y el lote sigue:
 * el error queda en el debug log y el vinculo, que es lo importante, ya esta guardado.
 */
public with sharing class VeleiroLinkSyncQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible private static Integer batchSize = 20;

    private final List<Id> accountIds;

    public VeleiroLinkSyncQueueable(List<Id> accountIds) {
        this.accountIds = accountIds;
    }

    public void execute(QueueableContext qc) {
        List<Id> batch = new List<Id>();
        List<Id> rest = new List<Id>();
        for (Integer i = 0; i < accountIds.size(); i++) {
            if (i < batchSize) batch.add(accountIds[i]);
            else rest.add(accountIds[i]);
        }

        List<Account> toSave = new List<Account>();
        for (Id accountId : batch) {
            try {
                toSave.add(VeleiroSyncService.pushAccountWithoutSaving(accountId));
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'VeleiroLinkSync: ' + accountId + ' -> ' + e.getMessage());
            }
        }
        if (!toSave.isEmpty()) update toSave;

        // La siguiente tanda va en su propia transaccion (limites de callouts).
        if (!rest.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new VeleiroLinkSyncQueueable(rest));
        }
    }
}
