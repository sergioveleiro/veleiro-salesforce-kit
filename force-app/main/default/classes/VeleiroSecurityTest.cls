@isTest
private class VeleiroSecurityTest {

    @testSetup
    static void setup() {
        VeleiroTestAccess.grant();
    }

    private class CaptureMock implements HttpCalloutMock {
        public String endpoint;
        public String authorization;
        public Integer status = 200;
        public String body = '{"data":[],"has_more":false}';
        public HttpResponse respond(HttpRequest req) {
            endpoint = req.getEndpoint();
            authorization = req.getHeader('Authorization');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }
    }

    private static Veleiro_Config__c orgConfig(String token, String baseUrl, String appBase) {
        return new Veleiro_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Api_Token__c = token,
            Base_Url__c = baseUrl,
            App_Base_Url__c = appBase
        );
    }

    private static User standardUser() {
        // By permissions, not by name: the profile is "Usuario estándar" in a Spanish org.
        Profile p = [
            SELECT Id FROM Profile
            WHERE UserLicense.Name = 'Salesforce'
            AND PermissionsCustomizeApplication = false
            AND PermissionsModifyAllData = false
            AND PermissionsViewSetup = true
            ORDER BY Name
            LIMIT 1
        ];
        String stamp = String.valueOf(DateTime.now().getTime());
        User u = new User(
            Alias = 'vsec',
            Email = 'vsec' + stamp + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Security',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'vsec' + stamp + '@example.com'
        );
        insert u;
        return u;
    }

    @isTest
    static void unsafeBaseUrlNeverReceivesTheToken() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_keep', 'https://evil.example/api/v1', 'https://evil.example');
            System.assert(VeleiroApiClient.apiBaseConfigured().startsWith('callout:'),
                VeleiroApiClient.apiBaseConfigured());
            System.assert(!VeleiroApiClient.apiBaseConfigured().contains('evil'));
            System.assertEquals('https://app.veleiro.ai', VeleiroApiClient.appBaseUrl());

            CaptureMock mock = new CaptureMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            VeleiroApiClient.doGet('/clients', null);
            Test.stopTest();

            System.assert(mock.endpoint.startsWith('callout:'), mock.endpoint);
            System.assert(mock.endpoint.contains('Veleiro_API/api/v1'), mock.endpoint);
            System.assert(!mock.endpoint.contains('evil'), mock.endpoint);
            System.assert(mock.authorization != null && mock.authorization.startsWith('Bearer '), mock.authorization);
            System.assert(mock.authorization.contains('vlr_keep'));
        }
    }

    @isTest
    static void betaSelectionStaysOnThePackagedCredential() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_beta', 'callout:Veleiro_API_Beta/api/v1', 'https://app.beta.veleiro.dev/a/partner-portal');
            VeleiroSyncConfig.namespaceOverride = 'veleiro__';
            System.assertEquals('https://app.beta.veleiro.dev', VeleiroApiClient.appBaseUrl());
            System.assert(VeleiroApiClient.apiBaseConfigured().contains('veleiro__Veleiro_API_Beta/api/v1'),
                VeleiroApiClient.apiBaseConfigured());
            System.assert(!VeleiroApiClient.apiBaseConfigured().contains('Secure'));
        }
    }

    @isTest
    static void legacyTokenMigratesAndClearsThePublicField() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_legacy', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            System.assertEquals(true, VeleiroCredentialStore.migrateLegacyToken());
            System.assertEquals('vlr_legacy', Veleiro_Secret__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(false, VeleiroCredentialStore.platformAuthReady());
            System.assertEquals(true, VeleiroApiClient.hasToken());
        }
    }

    @isTest
    static void failedProtectedWriteKeepsTheLegacyToken() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_legacy', null, null);
            VeleiroCredentialStore.failProtectedWrite = true;
            System.assertEquals(false, VeleiroCredentialStore.migrateLegacyToken());
            System.assertEquals('vlr_legacy', Veleiro_Config__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(true, VeleiroApiClient.hasToken());
        }
    }

    @isTest
    static void postInstallMovesTheTokenWithoutRequiringAReconnect() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_upgrade', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            Test.startTest();
            new VeleiroPostInstall().onInstall(null);
            Test.stopTest();
            System.assertEquals('vlr_upgrade', Veleiro_Secret__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(false, VeleiroCredentialStore.platformAuthReady());
            System.assertEquals(true, VeleiroApiClient.hasToken());
        }
    }

    @isTest
    static void postInstallWithNoTokenDoesNotThrow() {
        System.runAs(VeleiroTestAccess.user()) {
            new VeleiroPostInstall().onInstall(null);
            System.assertEquals(false, VeleiroApiClient.hasToken());
        }
    }

    @isTest
    static void platformAuthDropsTheApexAuthorizationHeader() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_platform', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            System.assertEquals(true, VeleiroCredentialStore.migrateLegacyToken());
            VeleiroCredentialStore.platformWriteOverride = true;
            CaptureMock mock = new CaptureMock();
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            new VeleiroCredentialMigration().execute(null);
            Test.stopTest();

            System.assertEquals(true, VeleiroCredentialStore.platformAuthReady());
            System.assert(mock.endpoint != null && mock.endpoint.contains('Veleiro_API_Secure'), mock.endpoint);
            System.assertEquals(null, mock.authorization);
        }
    }

    @isTest
    static void platformProbeFailureStaysOnTheLegacyCredential() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_platform', 'callout:Veleiro_API_Beta/api/v1', 'https://app.beta.veleiro.dev');
            VeleiroCredentialStore.migrateLegacyToken();
            VeleiroCredentialStore.platformWriteOverride = true;
            CaptureMock mock = new CaptureMock();
            mock.status = 401;
            mock.body = '{"error":{"code":"invalid_token","message":"vlr_should_not_leak"}}';
            Test.setMock(HttpCalloutMock.class, mock);

            Test.startTest();
            new VeleiroCredentialMigration().execute(null);
            Test.stopTest();

            System.assertEquals(false, VeleiroCredentialStore.platformAuthReady());
            System.assert(VeleiroApiClient.apiBaseConfigured().contains('Veleiro_API_Beta'));
            System.assert(!VeleiroApiClient.apiBaseConfigured().contains('Secure'));
        }
    }

    @isTest
    static void httpBodyIsNotReturnedToTheCaller() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_keep', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            CaptureMock mock = new CaptureMock();
            mock.status = 500;
            mock.body = '{"error":{"code":"internal_error","message":"vlr_should_not_leak SECRET_BODY"}}';
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            try {
                VeleiroApiClient.doGet('/clients', null);
                System.assert(false, 'expected an API error');
            } catch (VeleiroApiClient.VeleiroApiException e) {
                System.assertEquals('internal_error', e.code);
                System.assert(!e.getMessage().contains('vlr_should_not_leak'), e.getMessage());
                System.assert(!e.getMessage().contains('SECRET_BODY'), e.getMessage());
                System.assert(!e.getMessage().contains('{'), e.getMessage());
            }
            Test.stopTest();
        }
    }

    @isTest
    static void saveTokenStoresItOutsideThePublicSetting() {
        System.runAs(VeleiroTestAccess.admin()) {
            VeleiroMappingController.saveToken('vlr_saved');
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Api_Token__c);
            System.assertEquals('vlr_saved', Veleiro_Secret__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(true, VeleiroApiClient.hasToken());
        }
    }

    @isTest
    static void standardUserCannotChangeSetup() {
        System.runAs(VeleiroTestAccess.user()) {
            User u = standardUser();
            System.runAs(u) {
                Boolean blocked = false;
                try {
                    VeleiroMappingController.saveToken('vlr_nope');
                } catch (AuraHandledException e) {
                    blocked = true;
                    System.assert(e.getMessage().toLowerCase().contains('admin'), e.getMessage());
                }
                System.assert(blocked, 'a non-admin must not save the token');
                System.assertEquals(false, VeleiroSecurity.canManageSetup());
            }
        }
    }

    @isTest
    static void customPermissionLetsADelegatedAdminSave() {
        System.runAs(VeleiroTestAccess.user()) {
            User u = standardUser();
            PermissionSet adminSet = [SELECT Id FROM PermissionSet WHERE Name = 'Veleiro_Admin' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = adminSet.Id);
            Test.startTest();
            System.runAs(u) {
                System.assertEquals(true, VeleiroSecurity.canManageSetup());
                VeleiroMappingController.saveEnvironment('Beta');
            }
            Test.stopTest();
            System.assert(Veleiro_Config__c.getOrgDefaults().Base_Url__c.contains('Veleiro_API_Beta'));
            System.assertEquals('https://app.beta.veleiro.dev', Veleiro_Config__c.getOrgDefaults().App_Base_Url__c);
        }
    }

    @isTest
    static void fieldAndObjectNamesAreDescribeChecked() {
        System.runAs(VeleiroTestAccess.user()) {
            // Do not name this variable Account. Apex is case-insensitive, so that
            // would hide the Account type and Account.Veleiro_Client_Id__c would not compile.
            Schema.DescribeSObjectResult accountDescribe = VeleiroSecurity.describeObject('Account');
            System.assertEquals('Name', VeleiroSecurity.safeField(accountDescribe, 'Name'));
            System.assertEquals(
                Account.Veleiro_Client_Id__c.getDescribe().getName(),
                VeleiroSecurity.safeField(accountDescribe, 'Veleiro_Client_Id__c')
            );
            System.assertEquals(null, VeleiroSecurity.safeField(accountDescribe, 'Name, (SELECT Id FROM Contacts)'));
            System.assertEquals(null, VeleiroSecurity.describeObject('Not_A_Real_Object__c'));
            System.assertEquals(0, VeleiroLinkController.searchRecords('User', 'client', 'admin').size());

            Map<String, Schema.SObjectField> accountFields = accountDescribe.fields.getMap();
            for (VeleiroMappingController.Option field : VeleiroMappingController.getFields('Account')) {
                System.assertEquals(true, accountFields.get(field.value).getDescribe().isAccessible(), field.value);
            }
            Boolean sawAccount = false;
            for (VeleiroMappingController.Option obj : VeleiroMappingController.getObjects()) {
                System.assertNotEquals(null, VeleiroSecurity.describeObject(obj.value), obj.value);
                if (obj.value == 'Account') sawAccount = true;
            }
            System.assert(sawAccount);
        }
    }

    @isTest
    static void sanitizeDropsBodiesAndTokens() {
        System.runAs(VeleiroTestAccess.user()) {
            System.assert(!VeleiroSecurity.sanitize('{"error":"vlr_abc"}').contains('vlr_'));
            System.assert(VeleiroSecurity.sanitize('Push to Veleiro is disabled').contains('disabled'));
            System.assertEquals(
                VeleiroI18n.t('err.generic'),
                VeleiroSecurity.forUi(new CalloutException('Bearer vlr_abc'))
            );
        }
    }

    // ---- AppExchange review: page-load methods are read only ----

    @isTest
    static void pageLoadMethodsNeverWrite() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_legacy', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            Test.setMock(HttpCalloutMock.class, new CaptureMock());

            Test.startTest();
            Integer before = Limits.getDmlStatements();
            Map<String, String> status = VeleiroMappingController.getStatus();
            VeleiroOnboardingController.State withPing = VeleiroOnboardingController.getState(true);
            VeleiroOnboardingController.State noPing = VeleiroOnboardingController.getState(false);
            Integer dml = Limits.getDmlStatements() - before;
            Test.stopTest();

            System.assertEquals(0, dml, 'getStatus and getState run on page load and must not write');
            System.assertEquals('vlr_legacy', Veleiro_Config__c.getOrgDefaults().Api_Token__c,
                'the legacy token is not moved by opening a page');
            System.assertEquals(null, Veleiro_Secret__c.getOrgDefaults().Api_Token__c);
            System.assertEquals('true', status.get('legacyToken'));
            System.assertEquals('false', status.get('platformAuthReady'));
            System.assertEquals('true', status.get('needsPlatformSetup'));
            System.assertEquals(true, withPing.legacyToken);
            System.assertEquals(true, noPing.legacyToken);
            System.assertEquals(true, noPing.needsPlatformSetup);
            System.assertEquals(false, noPing.platformAuthReady);
        }
    }

    @isTest
    static void adminButtonMovesTheLegacyToken() {
        System.runAs(VeleiroTestAccess.admin()) {
            insert orgConfig('vlr_legacy', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            System.assertEquals(true, VeleiroCredentialStore.hasLegacyToken());

            Test.startTest();
            System.assertEquals(true, VeleiroMappingController.secureLegacyToken());
            Test.stopTest();

            System.assertEquals('vlr_legacy', Veleiro_Secret__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(false, VeleiroCredentialStore.hasLegacyToken());
            System.assertEquals(true, VeleiroApiClient.hasToken());
        }
    }

    @isTest
    static void adminButtonFinishesPlatformAuthWhenProtectedTokenExists() {
        System.runAs(VeleiroTestAccess.admin()) {
            insert orgConfig('vlr_legacy', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            System.assertEquals(true, VeleiroCredentialStore.migrateLegacyToken());
            System.assertEquals(false, VeleiroCredentialStore.hasLegacyToken());
            System.assertEquals(false, VeleiroCredentialStore.platformAuthReady());

            VeleiroCredentialStore.platformWriteOverride = true;
            Test.setMock(HttpCalloutMock.class, new CaptureMock());
            Test.startTest();
            System.assertEquals(true, VeleiroMappingController.secureLegacyToken());
            Test.stopTest();

            System.assertEquals(true, VeleiroCredentialStore.platformAuthReady());
            System.assertEquals('vlr_legacy', Veleiro_Secret__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(true, VeleiroApiClient.hasToken());
        }
    }

    @isTest
    static void adminButtonRecordsAPlatformWriteFailureWithoutTheToken() {
        System.runAs(VeleiroTestAccess.admin()) {
            insert orgConfig('vlr_secret_token', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            VeleiroCredentialStore.platformWriteOverride = false;

            Test.startTest();
            System.assertEquals(true, VeleiroMappingController.secureLegacyToken());
            Test.stopTest();

            System.assertEquals('vlr_secret_token', Veleiro_Secret__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(false, VeleiroCredentialStore.platformAuthReady());
            String err = Veleiro_Config__c.getOrgDefaults().Last_Sync_Error__c;
            System.assert(err != null && err.contains('External Credential setup skipped:'), err);
            System.assert(err.contains('VeleiroApiException'), err);
            System.assert(!err.contains('vlr_secret_token'), err);
        }
    }

    @isTest
    static void queueableRecordsAPlatformWriteFailureWithoutTheToken() {
        System.runAs(VeleiroTestAccess.admin()) {
            insert orgConfig('vlr_secret_token', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            System.assertEquals(true, VeleiroCredentialStore.migrateLegacyToken());
            VeleiroCredentialStore.platformWriteOverride = false;

            Test.startTest();
            new VeleiroCredentialMigration().execute(null);
            Test.stopTest();

            System.assertEquals('vlr_secret_token', Veleiro_Secret__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(false, VeleiroCredentialStore.platformAuthReady());
            String err = Veleiro_Config__c.getOrgDefaults().Last_Sync_Error__c;
            System.assert(err != null && err.contains('External Credential setup skipped:'), err);
            System.assert(!err.contains('vlr_secret_token'), err);
        }
    }

    @isTest
    static void anAdminSaveFinishesAPendingMigration() {
        System.runAs(VeleiroTestAccess.admin()) {
            insert orgConfig('vlr_legacy', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            Test.startTest();
            VeleiroMappingController.saveEnvironment('Production');
            Test.stopTest();
            System.assertEquals('vlr_legacy', Veleiro_Secret__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Api_Token__c);
        }
    }

    @isTest
    static void standardUserCannotMoveTokenSkipStepsOrSeed() {
        System.runAs(VeleiroTestAccess.user()) {
            insert orgConfig('vlr_legacy', 'callout:Veleiro_API/api/v1', 'https://app.veleiro.ai');
            User u = standardUser();
            System.runAs(u) {
                Integer blocked = 0;
                try { VeleiroMappingController.secureLegacyToken(); } catch (AuraHandledException e) { blocked++; }
                try { VeleiroOnboardingController.skipStep('link', true); } catch (AuraHandledException e) { blocked++; }
                try { VeleiroSeed.seed(); } catch (AuraHandledException e) { blocked++; }
                System.assertEquals(3, blocked, 'all three need an administrator');
            }
            System.assertEquals('vlr_legacy', Veleiro_Config__c.getOrgDefaults().Api_Token__c);
            System.assertEquals(null, Veleiro_Config__c.getOrgDefaults().Onboarding_Skipped__c);
        }
    }

    // ---- AppExchange review: least privilege on the permission sets ----

    @isTest
    static void integrationAccessCannotChangeMappings() {
        String objectName = VeleiroSecurity.api(Veleiro_Field_Mapping__c.SObjectType);
        Integer seen = 0;
        for (ObjectPermissions op : [
            SELECT PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete,
                   PermissionsViewAllRecords, PermissionsModifyAllRecords, Parent.Name, Parent.NamespacePrefix
            FROM ObjectPermissions
            WHERE SobjectType = :objectName
            AND Parent.Name IN ('Veleiro_Integration_Access', 'Veleiro_Admin')
        ]) {
            if (op.Parent.NamespacePrefix != VeleiroSyncConfig.namespacePrefix().removeEnd('__')
                && !(String.isBlank(op.Parent.NamespacePrefix) && String.isBlank(VeleiroSyncConfig.namespacePrefix()))) continue;
            System.assertEquals(true, op.PermissionsRead, op.Parent.Name);
            System.assertEquals(false, op.PermissionsViewAllRecords, op.Parent.Name);
            System.assertEquals(false, op.PermissionsModifyAllRecords, op.Parent.Name);
            Boolean admin = op.Parent.Name == 'Veleiro_Admin';
            System.assertEquals(admin, op.PermissionsCreate, op.Parent.Name);
            System.assertEquals(admin, op.PermissionsEdit, op.Parent.Name);
            System.assertEquals(admin, op.PermissionsDelete, op.Parent.Name);
            seen++;
        }
        System.assertEquals(2, seen, 'both permission sets carry the mapping object');
    }

    @isTest
    static void integrationUserReadsMappingsButCannotWriteThem() {
        System.runAs(VeleiroTestAccess.user()) {
            insert new Veleiro_Field_Mapping__c(
                Name = 'Account Name', SObject__c = 'Account', Veleiro_Entity__c = 'client',
                SF_Field__c = 'Name', Veleiro_Target__c = 'name', Target_Type__c = 'Standard',
                Is_Standard__c = true, Active__c = true
            );
            User u = standardUser();
            PermissionSet access = [SELECT Id FROM PermissionSet WHERE Name = 'Veleiro_Integration_Access' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = access.Id);
            System.runAs(u) {
                // The sync reads mappings in user mode: read access has to be enough for that.
                System.assertEquals(1, VeleiroMappingController.getMappings().size());
                Schema.DescribeSObjectResult d = Veleiro_Field_Mapping__c.SObjectType.getDescribe();
                System.assertEquals(true, d.isAccessible());
                System.assertEquals(false, d.isCreateable());
                System.assertEquals(false, d.isUpdateable());
                System.assertEquals(false, d.isDeletable());
            }
        }
    }

    // ---- AppExchange review: links received from the API ----

    @isTest
    static void onlyHttpsVeleiroLinksSurvive() {
        String ok = 'https://app.veleiro.ai/a/partner-portal/meetings/bot_1/';
        System.assertEquals(ok, VeleiroApiClient.safeAppUrl(ok));
        System.assertEquals(ok, VeleiroApiClient.safeAppUrl('  ' + ok + ' '));
        System.assertEquals('https://app.beta.veleiro.dev/x', VeleiroApiClient.safeAppUrl('https://app.beta.veleiro.dev/x'));
        for (String bad : new List<String>{
            null, '', 'javascript:alert(1)', 'JaVaScRiPt:alert(1)', 'data:text/html,<script>1</script>',
            'http://app.veleiro.ai/a/partner-portal/meetings/bot_1/',
            'https://zoom.us/j/123', 'https://evil.example/https://app.veleiro.ai/',
            'https://app.veleiro.ai.evil.example/x', 'https://app.veleiro.ai@evil.example/x',
            'https://app.veleiro.ai:8443/x', 'https://app.veleiro.ai\\@evil.example/x',
            'https://app.veleiro.ai/a b', '//app.veleiro.ai/x', '/a/partner-portal/meetings/bot_1/'
        }) {
            System.assertEquals(null, VeleiroApiClient.safeAppUrl(bad), 'rejected: ' + bad);
        }
    }
}
