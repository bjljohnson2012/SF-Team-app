/**
 * Tests for GtmTeamAccessController. Covers the manage-users gate, user search,
 * role presets, grant upsert, permset assign/revoke, and getMyAccess.
 *
 * Same session wrote the implementation and these tests — they need an
 * independent look, especially mixed-DML sequencing and negative gates.
 */
@isTest
private class GtmTeamAccessControllerTest {

    private static final String SUFFIX = 'gtmteamacc';

    @TestSetup
    static void setup() {
        Id adminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        Id stdProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
        User manager = buildUser('mgr', adminProfileId);
        User target = buildUser('tgt', stdProfileId);
        User other = buildUser('oth', stdProfileId);
        insert new List<User>{ manager, target, other };
    }

    private static User buildUser(String tag, Id profileId) {
        String stamp = String.valueOf(System.currentTimeMillis());
        return new User(
            FirstName = 'Grant',
            LastName = tag,
            Email = tag + '.' + SUFFIX + '@eunatest.example.com',
            Username = tag + '.' + SUFFIX + stamp + '@eunatest.example.com',
            Alias = (tag + 'gta').left(8),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
    }

    private static User mgr() {
        return [SELECT Id, Name FROM User WHERE LastName = 'mgr' AND Email LIKE :('%' + SUFFIX + '%') LIMIT 1];
    }
    private static User tgt() {
        return [SELECT Id, Name FROM User WHERE LastName = 'tgt' AND Email LIKE :('%' + SUFFIX + '%') LIMIT 1];
    }
    private static User oth() {
        return [SELECT Id, Name FROM User WHERE LastName = 'oth' AND Email LIKE :('%' + SUFFIX + '%') LIMIT 1];
    }

    @isTest
    static void gateBlocksStandardUser() {
        Boolean threw = false;
        System.runAs(oth()) {
            try {
                GtmTeamAccessController.searchUsers('Grant');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'searchUsers should throw without manage-users rights');
    }

    @isTest
    static void searchUsersFindsNameFragment() {
        Test.startTest();
        List<GtmTeamAccessController.AccessUserHit> hits;
        System.runAs(mgr()) {
            hits = GtmTeamAccessController.searchUsers('Grant tgt');
            if (hits.isEmpty()) {
                hits = GtmTeamAccessController.searchUsers('tgt');
            }
        }
        Test.stopTest();
        System.assert(!hits.isEmpty(), 'search should return the target user');
        Boolean found = false;
        for (GtmTeamAccessController.AccessUserHit h : hits) {
            if (h.id == tgt().Id) {
                found = true;
            }
        }
        System.assert(found, 'target user should appear in search hits');
    }

    @isTest
    static void searchUsersIgnoresShortTerm() {
        System.runAs(mgr()) {
            System.assertEquals(0, GtmTeamAccessController.searchUsers('a').size());
            System.assertEquals(0, GtmTeamAccessController.searchUsers('').size());
        }
    }

    @isTest
    static void rolePresetAdminIncludesAdminTabAndManage() {
        GtmTeamAccessController.UserGrant g;
        System.runAs(mgr()) {
            g = GtmTeamAccessController.rolePreset('Admin');
        }
        System.assertEquals(GtmTeamAccessController.ROLE_ADMIN, g.role);
        System.assert(isChecked(g.tabs, 'admin'), 'Admin role should check the Admin tab');
        System.assert(isChecked(g.activities, 'manage_users'), 'Admin role should check manage users');
        System.assert(isChecked(g.activities, 'tick_call'), 'Admin role should check tick call');
    }

    @isTest
    static void rolePresetMemberIsViewOnly() {
        GtmTeamAccessController.UserGrant g;
        System.runAs(mgr()) {
            g = GtmTeamAccessController.rolePreset('Team member');
        }
        System.assertEquals(GtmTeamAccessController.ROLE_MEMBER, g.role);
        System.assert(!isChecked(g.tabs, 'admin'), 'Team member should not get Admin by default');
        System.assert(!isChecked(g.activities, 'tick_call'), 'Team member should not tick the call by default');
        System.assert(isChecked(g.tabs, 'sales_performance'), 'Team member still sees Sales Performance');
    }

    @isTest
    static void saveGrantThenAssignLeaderPermset() {
        Id targetId = tgt().Id;
        List<PermissionSet> access = [
            SELECT Id FROM PermissionSet WHERE Name = :GtmTeamAccessController.PERM_ACCESS LIMIT 1
        ];
        System.assertEquals(1, access.size(), 'GTM_Team_Johnson_Access must exist in the org');

        System.runAs(mgr()) {
            GtmTeamAccessController.saveGrant(
                targetId,
                GtmTeamAccessController.ROLE_LEADER,
                new List<String>{ 'sales_performance', 'sales_tools' },
                new List<String>{ 'view_forecast', 'tick_call' }
            );
        }
        System.runAs(mgr()) {
            Test.startTest();
            GtmTeamAccessController.assignAppPermset(
                targetId,
                GtmTeamAccessController.ROLE_LEADER,
                new List<String>{ 'view_forecast', 'tick_call' }
            );
            Test.stopTest();
        }

        GTM_Team_Access__c row = [
            SELECT Role__c, Tabs__c, Activities__c
            FROM GTM_Team_Access__c
            WHERE User_Key__c = :String.valueOf(targetId)
            LIMIT 1
        ];
        System.assertEquals(GtmTeamAccessController.ROLE_LEADER, row.Role__c);
        System.assert(row.Tabs__c.contains('sales_performance'));
        System.assert(row.Activities__c.contains('tick_call'));
        System.assertEquals(1, [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :targetId AND PermissionSet.Name = :GtmTeamAccessController.PERM_ACCESS
        ]);
    }

    @isTest
    static void saveGrantKeepsCheckboxOverridesAfterRole() {
        Id targetId = tgt().Id;
        System.runAs(mgr()) {
            GtmTeamAccessController.saveGrant(
                targetId,
                GtmTeamAccessController.ROLE_MEMBER,
                new List<String>{ 'sales_performance', 'admin' },
                new List<String>{ 'view_forecast', 'manage_users' }
            );
            GtmTeamAccessController.UserGrant loaded = GtmTeamAccessController.getUserGrant(targetId);
            System.assertEquals(true, loaded.existing);
            System.assertEquals(GtmTeamAccessController.ROLE_MEMBER, loaded.role);
            System.assert(isChecked(loaded.tabs, 'admin'), 'checkbox override should keep Admin tab on a Team member');
            System.assert(isChecked(loaded.activities, 'manage_users'), 'checkbox override should keep manage users');
        }
    }

    @isTest
    static void memberWithoutEditGetsViewerPermset() {
        Id targetId = tgt().Id;
        List<PermissionSet> viewer = [
            SELECT Id FROM PermissionSet WHERE Name = :GtmTeamAccessController.PERM_VIEWER LIMIT 1
        ];
        System.assertEquals(1, viewer.size(), 'GTM_Team_Johnson_Viewer must exist in the org');

        System.runAs(mgr()) {
            Test.startTest();
            GtmTeamAccessController.assignAppPermset(
                targetId,
                GtmTeamAccessController.ROLE_MEMBER,
                new List<String>{ 'view_forecast', 'pricing_review' }
            );
            Test.stopTest();
        }
        System.assertEquals(1, [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :targetId AND PermissionSet.Name = :GtmTeamAccessController.PERM_VIEWER
        ]);
        System.assertEquals(GtmTeamAccessController.PERM_VIEWER,
            GtmTeamAccessController.targetPermset(
                GtmTeamAccessController.ROLE_MEMBER,
                new Set<String>{ 'view_forecast' }
            ));
        System.assertEquals(GtmTeamAccessController.PERM_ACCESS,
            GtmTeamAccessController.targetPermset(
                GtmTeamAccessController.ROLE_MEMBER,
                new Set<String>{ 'tick_call' }
            ));
    }

    @isTest
    static void revokeRemovesGrantAndPermset() {
        Id targetId = tgt().Id;
        Set<String> appPerms = new Set<String>{
            GtmTeamAccessController.PERM_ACCESS,
            GtmTeamAccessController.PERM_VIEWER
        };
        System.runAs(mgr()) {
            GtmTeamAccessController.saveGrant(
                targetId,
                GtmTeamAccessController.ROLE_LEADER,
                new List<String>{ 'sales_performance' },
                new List<String>{ 'view_forecast' }
            );
        }
        System.runAs(mgr()) {
            GtmTeamAccessController.assignAppPermset(
                targetId,
                GtmTeamAccessController.ROLE_LEADER,
                new List<String>{ 'view_forecast' }
            );
        }
        System.runAs(mgr()) {
            Test.startTest();
            GtmTeamAccessController.revokeAppPermset(targetId);
            Test.stopTest();
        }
        System.runAs(mgr()) {
            GtmTeamAccessController.deleteGrant(targetId);
        }
        System.assertEquals(0, [
            SELECT COUNT() FROM GTM_Team_Access__c WHERE User_Key__c = :String.valueOf(targetId)
        ]);
        System.assertEquals(0, [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :targetId AND PermissionSet.Name IN :appPerms
        ]);
    }

    @isTest
    static void getAccessMatrixListsSavedUser() {
        Id targetId = tgt().Id;
        System.runAs(mgr()) {
            GtmTeamAccessController.saveGrant(
                targetId,
                GtmTeamAccessController.ROLE_ADMIN,
                new List<String>{ 'admin', 'sales_performance' },
                new List<String>{ 'manage_users' }
            );
            GtmTeamAccessController.AccessInfo info = GtmTeamAccessController.getAccessMatrix();
            System.assertEquals(true, info.canManage);
            System.assert(!info.tabCatalog.isEmpty());
            System.assert(!info.activityCatalog.isEmpty());
            Boolean found = false;
            for (GtmTeamAccessController.AccessUser u : info.users) {
                if (u.id == targetId) {
                    found = true;
                    System.assertEquals('Admin', u.roleLabel);
                }
            }
            System.assert(found, 'saved grant user should appear on the matrix');
        }
    }

    @isTest
    static void getMyAccessReadsOwnGrant() {
        Id managerId = mgr().Id;
        System.runAs(mgr()) {
            GtmTeamAccessController.saveGrant(
                managerId,
                GtmTeamAccessController.ROLE_ADMIN,
                new List<String>{ 'admin' },
                new List<String>{ 'manage_users' }
            );
            GtmTeamAccessController.UserGrant mine = GtmTeamAccessController.getMyAccess();
            System.assertEquals(managerId, mine.userId);
            System.assertEquals(GtmTeamAccessController.ROLE_ADMIN, mine.role);
            System.assertEquals(true, mine.existing);
        }
    }

    @isTest
    static void normalizeRoleAcceptsLegacyValues() {
        System.assertEquals(GtmTeamAccessController.ROLE_ADMIN, GtmTeamAccessController.normalizeRole('full'));
        System.assertEquals(GtmTeamAccessController.ROLE_MEMBER, GtmTeamAccessController.normalizeRole('viewer'));
        System.assertEquals(GtmTeamAccessController.ROLE_LEADER, GtmTeamAccessController.normalizeRole('Leader'));
    }

    private static Boolean isChecked(List<GtmTeamAccessController.CatalogItem> items, String key) {
        for (GtmTeamAccessController.CatalogItem item : items) {
            if (item.key == key) {
                return item.checked == true;
            }
        }
        return false;
    }
}
