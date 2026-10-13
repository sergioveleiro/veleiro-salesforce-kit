/**
 * Envio masivo de registros de Salesforce a Veleiro ("Enviar a Veleiro" en la pestaña
 * Veleiro Link). Es el arranque de un cliente nuevo: su Veleiro esta vacio y lo que tiene
 * son cuentas en Salesforce.
 *
 * Por que no reusa VeleiroLinkSyncQueueable: ese manda UN registro por transaccion porque
 * syncRecord hace DML despues de sus callouts, y un segundo registro en la misma transaccion
 * truena con "uncommitted work pending". Para el par nativo Account -> client existe
 * pushAccountWithoutSaving, que hace el callout y devuelve el Account listo para guardar: asi
 * caben decenas por transaccion (todos los callouts, un solo DML al final). Eso importa de
 * verdad porque encadenar Queueables tiene tope de 5 saltos en orgs Developer y de prueba:
 * con un registro por salto, un cliente que prueba en una Developer solo enviaria 5.
 *
 * Cualquier otro par cae en syncRecord, uno por transaccion, que ya esta probado.
 *
 * Seguridad del org del cliente:
 *  - el DML es parcial (Database.update(..., false)): una validation rule del cliente sobre
 *    una cuenta no tumba el lote completo;
 *  - si Veleiro ya creo el client pero Salesforce no pudo guardar el id, el error lo dice con
 *    el id incluido, para poder recuperarlo a mano en vez de dejarlo huerfano en silencio;
 *  - los callouts se cuentan contra el limite real de la transaccion, no contra un numero fijo.
 */
public with sharing class VeleiroBulkSendQueueable implements Queueable, Database.AllowsCallouts {

    // Margen de callouts que dejamos libre: un update gasta 2 (GET + PATCH), un create 1.
    @TestVisible private static Integer calloutHeadroom = 4;
    // Tope por transaccion aunque sobren callouts (CPU y heap tambien cuentan).
    @TestVisible private static Integer maxPerTransaction = 50;

    private final List<Id> recordIds;
    private final String entity;
    private final Map<Id, String> linkTo;   // registros que el usuario mando vincular a un recurso ya existente

    public VeleiroBulkSendQueueable(List<Id> recordIds, String entity, Map<Id, String> linkTo) {
        this.recordIds = recordIds;
        this.entity = entity;
        this.linkTo = (linkTo == null) ? new Map<Id, String>() : linkTo;
    }

    public void execute(QueueableContext qc) {
        if (recordIds == null || recordIds.isEmpty()) return;

        String pair = VeleiroLinkStore.key(recordIds[0].getSobjectType().getDescribe().getName(), entity);
        Boolean batchable = (pair == 'account|client');

        List<Id> rest = new List<Id>();
        List<Account> toSave = new List<Account>();
        Map<Id, String> createdFor = new Map<Id, String>();   // para explicar un DML fallido

        for (Integer i = 0; i < recordIds.size(); i++) {
            Id recordId = recordIds[i];

            Boolean roomLeft = Limits.getCallouts() <= (Limits.getLimitCallouts() - calloutHeadroom)
                && toSave.size() < maxPerTransaction;
            // Sin el par nativo solo cabe uno: syncRecord guarda al final de su propia llamada.
            if ((!batchable && i > 0) || (batchable && !roomLeft)) {
                rest.add(recordId);
                continue;
            }

            try {
                if (batchable) {
                    Account pushed = VeleiroSyncService.pushAccountWithoutSaving(recordId, linkTo.get(recordId));
                    toSave.add(pushed);
                    createdFor.put(recordId, pushed.Veleiro_Client_Id__c);
                } else {
                    VeleiroSyncService.syncRecord(recordId, entity);
                }
            } catch (Exception e) {
                VeleiroAutoSyncGuard.recordFailure(recordId, e);
            }
        }

        // Un solo DML, ya sin callouts pendientes, y parcial para no perder el lote por uno.
        if (!toSave.isEmpty()) {
            List<Database.SaveResult> results = Database.update(toSave, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) continue;
                Id failedId = toSave[i].Id;
                String why = results[i].getErrors().isEmpty() ? 'unknown' : results[i].getErrors()[0].getMessage();
                // El client SI existe en Veleiro: lo decimos con su id para poder rescatarlo.
                VeleiroAutoSyncGuard.recordFailure(failedId, new VeleiroApiClient.VeleiroApiException(
                    'Veleiro client ' + createdFor.get(failedId) + ' was created but Salesforce could not'
                    + ' save the link: ' + why));
            }
        }

        if (!rest.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new VeleiroBulkSendQueueable(rest, entity, linkTo));
        }
    }
}
