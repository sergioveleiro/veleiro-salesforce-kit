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

    public static Schema.DescribeSObjectResult describeObject(String apiName) {
        if (String.isBlank(apiName)) return null;
        if (apiName.contains(' ') || apiName.contains(',') || apiName.contains(':') || apiName.contains('\'')) {
            return null;
        }
        Schema.SObjectType type = Schema.getGlobalDescribe().get(apiName);
        if (type == null) return null;
        Schema.DescribeSObjectResult d = type.getDescribe();
        if (!d.isAccessible() || !d.isQueryable() || d.isDeprecatedAndHidden()) return null;
        return d;
    }

    /** Canonical field API name, or null when the value is not a real readable field. */
    public static String safeField(Schema.DescribeSObjectResult d, String fieldName) {
        if (d == null || String.isBlank(fieldName)) return null;
        if (fieldName.contains('.') || fieldName.contains(' ') || fieldName.contains(',')
            || fieldName.contains('(') || fieldName.contains(')') || fieldName.contains('\'')
            || fieldName.contains(';')) {
            return null;
        }
        Schema.SObjectField field = d.fields.getMap().get(fieldName);
        if (field == null) return null;
        Schema.DescribeFieldResult fd = field.getDescribe();
        if (!fd.isAccessible()) return null;
        return fd.getName();
    }

    public static List<SObject> query(String soql) {
        return Database.query(soql, AccessLevel.USER_MODE);
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
