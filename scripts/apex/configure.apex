/**
 * One-time configuration of the Veleiro integration — run with:
 *   sf apex run -o <your-org> -f scripts/apex/configure.apex
 *
 * SECURITY: this writes your Veleiro API token as DATA into the Veleiro_Config__c
 * custom setting. Do NOT commit your real token. Edit a LOCAL copy of this file,
 * paste your token, run it, then discard the change (or clear the value).
 *
 * Get your token + scopes (read/write on clients & projects) from the Veleiro app.
 */

String API_TOKEN   = 'REPLACE_WITH_YOUR_VELEIRO_API_TOKEN';   // e.g. vlr_...
String BASE_URL     = 'https://app.beta.veleiro.dev/api/v1';    // API base, NO trailing slash
String APP_BASE_URL = 'https://app.beta.veleiro.dev';           // human portal base for links

if (API_TOKEN == 'REPLACE_WITH_YOUR_VELEIRO_API_TOKEN') {
    throw new CalloutException('Edit configure.apex and set your API_TOKEN before running.');
}

Veleiro_Config__c c = Veleiro_Config__c.getOrgDefaults();
if (c == null || c.Id == null) {
    c = new Veleiro_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
}
c.Api_Token__c   = API_TOKEN;
c.Base_Url__c     = BASE_URL;
c.App_Base_Url__c = APP_BASE_URL;
upsert c;

System.debug('Veleiro_Config__c configured. Base=' + c.Base_Url__c + ' App=' + c.App_Base_Url__c);
