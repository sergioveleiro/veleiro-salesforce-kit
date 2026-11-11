/**
 * Package version creation runs Apex tests as a user who does not automatically
 * receive field access to this package. USER_MODE then reports the fields as
 * missing. Tests grant Veleiro Integration Access to the running user first.
 */
public with sharing class VeleiroTestAccess {
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
