/**
 * Sync diferido de Opportunities cuyo Account se acaba de crear en la misma operacion
 * (ej. conversion de Lead: Account + Contact + Opportunity de un jalon).
 *
 * Ahi corren en paralelo el auto-sync del Account (crea el client) y el de la Opportunity.
 * Si la Opportunity no espera, tambien crea un client -> duplicado en Veleiro y los dos
 * jobs pelean por actualizar el mismo Account. Este Queueable reintenta cada minuto hasta
 * que el Account ya tenga Veleiro_Client_Id__c; tras MAX_ATTEMPTS sincroniza igual
 * (syncOpportunity crea el client si sigue faltando).
 */
public with sharing class VeleiroOppSyncQueueable implements Queueable, Database.AllowsCallouts {

    public static final Integer MAX_ATTEMPTS = 3;
    // Un Account creado hace menos de esto probablemente tiene su propio auto-sync en vuelo.
    private static final Integer FRESH_ACCOUNT_MINUTES = 5;

    private final List<Id> opportunityIds;
    private final Integer attempt;

    public VeleiroOppSyncQueueable(List<Id> opportunityIds, Integer attempt) {
        this.opportunityIds = opportunityIds;
        this.attempt = attempt;
    }

    // Opportunities que deben esperar al auto-sync de su Account (recien creado y aun sin client).
    public static Set<Id> waitingForAccountSync(List<Id> opportunityIds) {
        Set<Id> waiting = new Set<Id>();
        if (opportunityIds == null || opportunityIds.isEmpty() || !VeleiroSyncConfig.autoSyncOnCreate()) {
            return waiting;
        }
        Datetime freshSince = Datetime.now().addMinutes(-FRESH_ACCOUNT_MINUTES);
        for (Opportunity o : [
            SELECT Id FROM Opportunity
            WHERE Id IN :opportunityIds
              AND Veleiro_Project_Id__c = null
              AND AccountId != null
              AND Account.Veleiro_Client_Id__c = null
              AND Account.CreatedDate >= :freshSince
        ]) {
            waiting.add(o.Id);
        }
        return waiting;
    }

    public static void defer(Set<Id> opportunityIds, Integer attempt) {
        System.enqueueJob(new VeleiroOppSyncQueueable(new List<Id>(opportunityIds), attempt), 1);
    }

    public void execute(QueueableContext qc) {
        // En tests no se pueden encadenar Queueables: el primer intento es el ultimo.
        Boolean lastAttempt = attempt >= MAX_ATTEMPTS || Test.isRunningTest();

        Set<Id> stillWaiting = new Set<Id>();
        for (Opportunity o : [
            SELECT Id, Account.Veleiro_Client_Id__c FROM Opportunity WHERE Id IN :opportunityIds
        ]) {
            if (String.isBlank(o.Account.Veleiro_Client_Id__c) && !lastAttempt) {
                stillWaiting.add(o.Id);
            } else {
                VeleiroSyncService.syncOpportunity(o.Id);
            }
        }
        // Encolar despues de los callouts (un callout despues de encolar truena).
        if (!stillWaiting.isEmpty()) {
            defer(stillWaiting, attempt + 1);
        }
    }
}
