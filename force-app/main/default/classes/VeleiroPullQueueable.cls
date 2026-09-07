/**
 * Hace el callout de pull (Veleiro -> Salesforce). Se encola desde VeleiroPullJob
 * porque el Apex PROGRAMADO (Schedulable) no puede hacer callouts directos;
 * un Queueable con Database.AllowsCallouts si puede.
 */
public with sharing class VeleiroPullQueueable implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext qc) {
        VeleiroSync.pullUpdates();
    }
}
