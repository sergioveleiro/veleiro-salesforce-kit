/**
 * Invocable generico para flows sobre CUALQUIER objeto mapeado: recibe los ids y la entidad
 * ('client' o 'project'). Asi un partner automatiza su objeto personalizado sin Apex nuevo:
 * arma un record-triggered flow, llama esta accion y elige la entidad.
 *
 * Apex permite un solo @InvocableMethod por clase; los de Account y Opportunity viven en
 * VeleiroSyncAccountAction y VeleiroSyncService.
 */
public with sharing class VeleiroSyncRecordAction {

    public class Request {
        @InvocableVariable(label='Record Id' required=true)
        public Id recordId;
        @InvocableVariable(label='Veleiro entity (client or project)' required=true)
        public String entity;
    }

    @InvocableMethod(label='Sync record to Veleiro' callout=true)
    public static void syncRecords(List<Request> requests) {
        for (Request r : requests) {
            VeleiroSyncService.syncRecord(r.recordId, r.entity);
        }
    }
}
