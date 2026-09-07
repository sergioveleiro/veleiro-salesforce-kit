/**
 * Job programado que dispara el pull desde Veleiro hacia Salesforce.
 * No hay webhook en Veleiro (CRUD only), asi que el pull es por schedule.
 * La frecuencia se configura en el panel de Veleiro Mappings (off | hourly | daily).
 *
 * OJO: el Apex programado no puede hacer callouts directos -> encola un Queueable
 * (VeleiroPullQueueable) que si puede llamar la API.
 */
public with sharing class VeleiroPullJob implements Schedulable {
    public void execute(SchedulableContext sc) {
        System.enqueueJob(new VeleiroPullQueueable());
    }
}
