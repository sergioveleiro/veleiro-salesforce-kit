/**
 * Shared guards for the AppExchange security review: who may change setup,
 * which objects and fields may be queried, and which text may reach the UI.
 * Dynamic field names from Veleiro_Field_Mapping__c are accepted only when the
 * describe confirms they exist and the running user can read them.
 */
public with sharing class VeleiroSecurity {

    public static final String SETUP_PERMISSION = 'Veleiro_Manage_Setup';

    public static void assertCanManageSetup() {
        if (!canManageSetup()) {
            throw handled(VeleiroI18n.t('err.adminOnly'));
        }
    }

    /**
     * System administrators keep working after the upgrade without a new assignment.
     * A delegated admin without Customize Application needs the Veleiro Admin permission set.
     */
    public static Boolean canManageSetup() {
        if (FeatureManagement.checkPermission(SETUP_PERMISSION)) return true;
        try {
            return [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSet.PermissionsCustomizeApplication = true
                WITH USER_MODE
            ] > 0;
        } catch (Exception e) {
            System.debug(LoggingLevel.FINE, 'Setup check skipped: ' + e.getTypeName());
            return false;
        }
    }

    public static AuraHandledException handled(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    /** Text safe to store or show. HTTP bodies and bearer tokens never pass through. */
    public static String forUi(Exception e) {
        if (e instanceof VeleiroApiClient.VeleiroApiException) {
            return sanitize(e.getMessage());
        }
        if (e instanceof DmlException) {
            DmlException dml = (DmlException) e;
            if (dml.getNumDml() > 0) return sanitize(dml.getDmlMessage(0));
        }
        return VeleiroI18n.t('err.generic');
    }

    public static String sanitize(String message) {
        if (String.isBlank(message)) return message;
        String trimmed = message.trim();
        String lower = trimmed.toLowerCase();
        if (lower.contains('bearer ') || lower.contains('vlr_') || lower.contains('<html')
            || lower.contains('<!doctype') || trimmed.startsWith('{') || trimmed.startsWith('[')) {
            return VeleiroI18n.t('err.generic');
        }
        return trimmed.abbreviate(255);
    }

    /** API name of an object, including the package namespace when one is in effect. */
    public static String api(Schema.SObjectType type) {
        return type.getDescribe().getName();
    }

    /** API name of a field, including the package namespace when one is in effect. */
    public static String api(Schema.SObjectField field) {
        return field.getDescribe().getName();
    }

    public static Schema.DescribeSObjectResult describeObject(String apiName) {
        Schema.SObjectType type = resolveType(apiName);
        if (type == null) return null;
        Schema.DescribeSObjectResult d = type.getDescribe();
        if (!d.isAccessible() || !d.isQueryable() || d.isDeprecatedAndHidden()) return null;
        return d;
    }

    /**
     * Canonical field API name for dynamic SOQL and SObject.get/put.
     * Inside the managed package that name carries the veleiro__ prefix.
     * Returns null when the value is not a real field the user can read.
     */
    public static String safeField(Schema.DescribeSObjectResult d, String fieldName) {
        Schema.SObjectField field = resolveField(d, fieldName);
        if (field == null) return null;
        Schema.DescribeFieldResult fd = field.getDescribe();
        if (!fd.isAccessible()) return null;
        return fd.getName();
    }

    public static List<SObject> query(String soql, Map<String, Object> binds) {
        if (binds == null) binds = new Map<String, Object>();
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    public static Integer countQuery(String soql, Map<String, Object> binds) {
        if (binds == null) binds = new Map<String, Object>();
        return Database.countQueryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    public static Account loadAccount(Id accountId, List<Schema.SObjectField> fields) {
        return (Account) loadOne(Account.SObjectType, accountId, fields);
    }

    public static Opportunity loadOpportunity(Id opportunityId, List<Schema.SObjectField> fields) {
        return (Opportunity) loadOne(Opportunity.SObjectType, opportunityId, fields);
    }

    private static SObject loadOne(Schema.SObjectType type, Id recordId, List<Schema.SObjectField> fields) {
        Set<String> cols = new Set<String>{ 'Id' };
        for (Schema.SObjectField field : fields) cols.add(api(field));
        String soql = 'SELECT ' + String.join(new List<String>(cols), ', ') + ' FROM ' + api(type)
            + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> rows = query(soql, new Map<String, Object>{ 'recordId' => recordId });
        return rows.isEmpty() ? null : rows[0];
    }

    private static Schema.SObjectType resolveType(String apiName) {
        if (String.isBlank(apiName)) return null;
        if (apiName.contains(' ') || apiName.contains(',') || apiName.contains(':') || apiName.contains('\'')) {
            return null;
        }
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Schema.SObjectType type = gd.get(apiName);
        if (type != null) return type;
        String prefix = VeleiroSyncConfig.namespacePrefix();
        if (String.isNotBlank(prefix) && !apiName.toLowerCase().startsWith(prefix)) {
            type = gd.get(prefix + apiName);
        }
        return type;
    }

    private static Schema.SObjectField resolveField(Schema.DescribeSObjectResult d, String fieldName) {
        if (d == null || String.isBlank(fieldName)) return null;
        if (fieldName.contains('.') || fieldName.contains(' ') || fieldName.contains(',')
            || fieldName.contains('(') || fieldName.contains(')') || fieldName.contains('\'')
            || fieldName.contains(';')) {
            return null;
        }
        Map<String, Schema.SObjectField> fields = d.fields.getMap();
        Schema.SObjectField field = fields.get(fieldName);
        if (field != null) return field;
        String prefix = VeleiroSyncConfig.namespacePrefix();
        if (String.isNotBlank(prefix) && !fieldName.toLowerCase().startsWith(prefix)) {
            field = fields.get(prefix + fieldName);
        }
        return field;
    }

    public static void updateRecords(List<SObject> rows) {
        if (rows == null || rows.isEmpty()) return;
        Database.update(stripped(AccessType.UPDATABLE, rows), true, AccessLevel.USER_MODE);
    }

    public static List<Database.SaveResult> updatePartial(List<SObject> rows) {
        if (rows == null || rows.isEmpty()) return new List<Database.SaveResult>();
        return Database.update(stripped(AccessType.UPDATABLE, rows), false, AccessLevel.USER_MODE);
    }

    public static void insertRecords(List<SObject> rows) {
        if (rows == null || rows.isEmpty()) return;
        Database.insert(stripped(AccessType.CREATABLE, rows), true, AccessLevel.USER_MODE);
    }

    public static void deleteRecords(List<SObject> rows) {
        if (rows == null || rows.isEmpty()) return;
        if (!rows[0].getSObjectType().getDescribe().isDeletable()) {
            throw new VeleiroApiClient.VeleiroApiException(VeleiroI18n.t('err.notDeletable'));
        }
        Database.delete(rows, true, AccessLevel.USER_MODE);
    }

    public static void upsertAccounts(List<Account> rows) {
        if (rows == null || rows.isEmpty()) return;
        List<Account> clean = new List<Account>();
        for (SObject row : stripped(AccessType.UPSERTABLE, rows)) clean.add((Account) row);
        Database.upsert(clean, Account.Veleiro_Client_Id__c, true, AccessLevel.USER_MODE);
    }

    public static void upsertLinks(List<Veleiro_Link__c> rows) {
        if (rows == null || rows.isEmpty()) return;
        List<Veleiro_Link__c> clean = new List<Veleiro_Link__c>();
        for (SObject row : stripped(AccessType.UPSERTABLE, rows)) clean.add((Veleiro_Link__c) row);
        Database.upsert(clean, Veleiro_Link__c.Link_Key__c, true, AccessLevel.USER_MODE);
    }

    private static List<SObject> stripped(AccessType access, List<SObject> rows) {
        return Security.stripInaccessible(access, rows).getRecords();
    }
}
