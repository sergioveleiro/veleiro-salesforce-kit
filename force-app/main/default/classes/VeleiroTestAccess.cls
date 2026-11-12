/**
 * Package version creation runs Apex tests as a user who does not automatically
 * receive field access to this package. USER_MODE then reports the fields as
 * missing. Tests grant Veleiro Integration Access to the running user first.
 *
 * The assignment alone is not enough: the platform keeps the permissions it
 * resolved when the test started, so a user-mode query still hides the fields
 * afterwards. Only System.runAs re-reads them, which is why every test body runs
 * inside System.runAs(VeleiroTestAccess.user()).
 */
public with sharing class VeleiroTestAccess {
    /** The running user, with the permission set assigned, ready for System.runAs. */
    public static User user() {
        grant();
        return new User(Id = UserInfo.getUserId());
    }

    public static void grant() {
        if (!Test.isRunningTest()) return;
        Id userId = UserInfo.getUserId();
        System.runAs(new User(Id = userId)) {
            String namespace = VeleiroSyncConfig.namespacePrefix();
            String prefix = String.isBlank(namespace) ? null : namespace.removeEnd('__');
            PermissionSet chosen;
            for (PermissionSet ps : [
                SELECT Id, NamespacePrefix FROM PermissionSet WHERE Name = 'Veleiro_Integration_Access'
            ]) {
                if (prefix == null && String.isBlank(ps.NamespacePrefix)) chosen = ps;
                if (prefix != null && ps.NamespacePrefix == prefix) chosen = ps;
            }
            if (chosen == null) return;
            List<PermissionSetAssignment> existing = [
                SELECT Id FROM PermissionSetAssignment
                WHERE AssigneeId = :userId AND PermissionSetId = :chosen.Id
                LIMIT 1
            ];
            if (!existing.isEmpty()) return;
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = chosen.Id);
        }
    }
}
