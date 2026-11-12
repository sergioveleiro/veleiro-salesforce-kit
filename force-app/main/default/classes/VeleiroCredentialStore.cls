/**
 * Where the Veleiro API token lives after 1.9.0.
 *
 * Preferred store: the packaged External Credential principal (platform-encrypted).
 * Callouts then use Veleiro_API_Secure / Veleiro_API_Beta_Secure and Apex does not
 * attach an Authorization header.
 *
 * Reliable store: protected hierarchy custom setting Veleiro_Secret__c. Subscribers
 * cannot read it. The post-install script can write it, because that context cannot
 * make the ConnectApi callout that an External Credential needs.
 *
 * Fallback: the legacy public Veleiro_Config__c.Api_Token__c field, only when the
 * protected copy did not succeed. It is cleared after a successful copy. Callouts
 * that still use this token go only to the original packaged Named Credentials.
 */
public with sharing class VeleiroCredentialStore {

    public static final String EXTERNAL_CREDENTIAL = 'Veleiro_External';
    public static final String PRINCIPAL = 'VeleiroPrincipal';
    public static final String TOKEN_PARAMETER = 'ApiToken';

    // Tests cannot call ConnectApi. Null means "skip the platform write".
    @TestVisible private static Boolean platformWriteOverride;
    @TestVisible private static Boolean failProtectedWrite = false;

    public static Boolean hasToken() {
        return String.isNotBlank(readToken());
    }

    public static String readToken() {
        String protectedToken = protectedToken();
        if (String.isNotBlank(protectedToken)) return protectedToken;
        return readLegacyToken();
    }

    /** True while a token is still in the public Veleiro_Config__c field. Read only. */
    public static Boolean hasLegacyToken() {
        return String.isNotBlank(readLegacyToken());
    }

    public static Boolean platformAuthReady() {
        Veleiro_Secret__c secret = Veleiro_Secret__c.getOrgDefaults();
        return secret != null && secret.Platform_Auth__c == true && String.isNotBlank(secret.Api_Token__c);
    }

    /**
     * Copies a legacy public token into the protected setting and, only then, clears
     * the public field. A failed protected write leaves the public token untouched
     * so the org keeps calling Veleiro. Returns true when a protected token is in place.
     */
    public static Boolean migrateLegacyToken() {
        String legacy = readLegacyToken();
        Boolean protectedReady = String.isNotBlank(protectedToken());
        if (String.isBlank(legacy)) return protectedReady;
        if (!protectedReady) {
            try {
                writeProtected(legacy, false);
            } catch (Exception e) {
                return false;
            }
        }
        try {
            clearLegacyTokens();
        } catch (Exception e) {
            // The protected copy is already there. The public field is cleared on a later run.
            return true;
        }
        return true;
    }

    /** Admin save. ConnectApi runs before any DML. A platform failure still stores the token. */
    public static void saveNewToken(String token) {
        if (String.isBlank(token)) return;
        String clean = token.trim();
        Boolean platform = attemptPlatform(clean);
        writeProtected(clean, platform);
        clearLegacyTokens();
    }

    public static Boolean writePlatformCredential(String token) {
        if (String.isBlank(token)) return false;
        if (Test.isRunningTest()) return platformWriteOverride == true;
        try {
            String externalName = VeleiroSyncConfig.namespacePrefix() + EXTERNAL_CREDENTIAL;
            ConnectApi.CredentialInput input = credentialInput(externalName, token);
            try {
                ConnectApi.NamedCredentials.updateCredential(input);
            } catch (Exception updateFailed) {
                ConnectApi.NamedCredentials.createCredential(input);
            }
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public static void markPlatformAuth() {
        String token = protectedToken();
        if (String.isBlank(token)) token = readLegacyToken();
        if (String.isBlank(token)) return;
        writeProtected(token, true);
    }

    private static Boolean attemptPlatform(String token) {
        if (!writePlatformCredential(token)) return false;
        try {
            VeleiroApiClient.probeSecureCredential();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static String protectedToken() {
        Veleiro_Secret__c secret = Veleiro_Secret__c.getOrgDefaults();
        return (secret == null) ? null : secret.Api_Token__c;
    }

    private static String readLegacyToken() {
        Veleiro_Config__c userLevel = Veleiro_Config__c.getInstance();
        if (userLevel != null && String.isNotBlank(userLevel.Api_Token__c)) return userLevel.Api_Token__c;
        Veleiro_Config__c orgLevel = Veleiro_Config__c.getOrgDefaults();
        if (orgLevel != null && String.isNotBlank(orgLevel.Api_Token__c)) return orgLevel.Api_Token__c;
        for (Veleiro_Config__c row : [
            SELECT Api_Token__c FROM Veleiro_Config__c WHERE Api_Token__c != null LIMIT 1
        ]) {
            return row.Api_Token__c;
        }
        return null;
    }

    private static void writeProtected(String token, Boolean platform) {
        if (Test.isRunningTest() && failProtectedWrite == true) {
            throw new VeleiroApiClient.VeleiroApiException('Protected token write failed.');
        }
        Veleiro_Secret__c secret = Veleiro_Secret__c.getOrgDefaults();
        if (secret == null || secret.Id == null) {
            secret = new Veleiro_Secret__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        secret.Api_Token__c = token;
        secret.Platform_Auth__c = platform == true;
        upsert secret;
    }

    private static void clearLegacyTokens() {
        List<Veleiro_Config__c> rows = [
            SELECT Id, Api_Token__c FROM Veleiro_Config__c WHERE Api_Token__c != null
        ];
        if (rows.isEmpty()) return;
        for (Veleiro_Config__c row : rows) row.Api_Token__c = null;
        update rows;
    }

    private static ConnectApi.CredentialInput credentialInput(String externalName, String token) {
        ConnectApi.CredentialValueInput value = new ConnectApi.CredentialValueInput();
        value.encrypted = true;
        value.value = token;
        ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
        input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.Custom;
        input.externalCredential = externalName;
        input.principalName = PRINCIPAL;
        input.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
        input.credentials = new Map<String, ConnectApi.CredentialValueInput>{
            TOKEN_PARAMETER => value
        };
        return input;
    }
}
