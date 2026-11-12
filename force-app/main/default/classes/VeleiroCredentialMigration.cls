/**
 * Best-effort move of the protected token into the External Credential principal.
 * Runs after install (the install script itself cannot call out). The install
 * user usually does not have External Credential principal access, so this
 * job often cannot finish the write; an administrator retries it with
 * VeleiroMappingController.secureLegacyToken(). Failures are recorded by
 * exception type only, so a Completed job is not silent success.
 * A failure leaves the legacy Named Credential path in place.
 */
public with sharing class VeleiroCredentialMigration implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext context) {
        VeleiroCredentialStore.finishPlatformAuth();
    }
}
