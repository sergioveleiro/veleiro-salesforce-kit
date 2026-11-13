/**
 * Invocable para el flow de auto-sync al crear un Account (Account -> client de Veleiro).
 * En clase aparte porque Apex permite solo UN @InvocableMethod por clase (el de Opportunity
 * vive en VeleiroSyncService). Corre en la ruta async del flow (callout=true).
 */
public with sharing class VeleiroSyncAccountAction {
    @InvocableMethod(label='Sync Account to Veleiro Client' callout=true)
    public static void syncAccounts(List<Id> accountIds) {
        // El flow ya filtro por el trigger global; aqui manda el interruptor de este par.
        if (!VeleiroSyncConfig.autoSyncAccount()) return;
        if (VeleiroAutoSyncGuard.tooManyForAutoSync(accountIds, 'accounts')) return;
        // Todos los callouts y un solo DML al final: syncAccount por registro guardaba entre
        // callouts y el segundo Account del lote tronaba con "uncommitted work pending".
        List<Id> rest = VeleiroSyncService.syncAccounts(accountIds);
        if (!rest.isEmpty()) {
            VeleiroSyncConfig.recordError('Callout limit reached: ' + rest.size()
                + ' account(s) not synced. Sync them with the button or the Veleiro Link tab.');
        }
    }
}
