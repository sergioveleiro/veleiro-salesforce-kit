/**
 * Best-effort move of the protected token into the External Credential principal.
 * Runs after install (the install script itself cannot call out) and only flips
 * platform auth on after a real GET /clients through the secure Named Credential.
 * A failure leaves the legacy Named Credential path in place.
 */
public with sharing class VeleiroCredentialMigration implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext context) {
        if (VeleiroCredentialStore.platformAuthReady()) return;
        String token = VeleiroCredentialStore.readToken();
        if (String.isBlank(token)) return;
        if (!VeleiroCredentialStore.writePlatformCredential(token)) return;
        try {
            VeleiroApiClient.probeSecureCredential();
        } catch (Exception e) {
            return;
        }
        VeleiroCredentialStore.markPlatformAuth();
    }
}
