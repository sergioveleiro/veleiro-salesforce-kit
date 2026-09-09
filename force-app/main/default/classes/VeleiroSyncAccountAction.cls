/**
 * Invocable para el flow de auto-sync al crear un Account (Account -> client de Veleiro).
 * En clase aparte porque Apex permite solo UN @InvocableMethod por clase (el de Opportunity
 * vive en VeleiroSyncService). Corre en la ruta async del flow (callout=true).
 */
public with sharing class VeleiroSyncAccountAction {
    @InvocableMethod(label='Sync Account to Veleiro Client' callout=true)
    public static void syncAccounts(List<Id> accountIds) {
        for (Id aid : accountIds) {
            VeleiroSyncService.syncAccount(aid);
        }
    }
}
