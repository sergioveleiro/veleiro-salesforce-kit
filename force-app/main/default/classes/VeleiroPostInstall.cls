/**
 * Upgrade hook for 1.9.0. Copies an existing API token into the protected setting
 * before the subscriber org is used again. Never fails the install: a failed copy
 * leaves Api_Token__c where it was, and callouts keep using it.
 *
 * Public, not global: nothing outside the package calls it, and the AppExchange
 * rules reject global install handlers. The platform runs it by name.
 */
public with sharing class VeleiroPostInstall implements InstallHandler {
    public void onInstall(InstallContext context) {
        try {
            Boolean moved = VeleiroCredentialStore.migrateLegacyToken();
            if (!moved || VeleiroCredentialStore.platformAuthReady()) return;
            if (String.isBlank(VeleiroCredentialStore.readToken())) return;
            System.enqueueJob(new VeleiroCredentialMigration());
        } catch (Exception e) {
            // The upgrade itself must succeed. The legacy token remains the fallback.
            System.debug(LoggingLevel.ERROR, 'Post-install token migration skipped: ' + e.getTypeName());
        }
    }
}
