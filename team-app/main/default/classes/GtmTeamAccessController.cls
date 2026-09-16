/**
 * Admin tab for GTM - Team Johnson (salesPerfAdmin). Search a user, pick a
 * role (Admin / Leader / Team member), then edit tab and activity checkboxes.
 *
 * Salesforce app access still uses the existing Team Johnson permsets:
 * GTM_Team_Johnson_Access (edit) and GTM_Team_Johnson_Viewer (view-only).
 * Fine-grained tab/activity grants live on GTM_Team_Access__c so this class
 * does not touch CockpitForecastController, roster services, or hub panes.
 *
 * Mixed DML: PermissionSetAssignment is setup; GTM_Team_Access__c is not.
 * The LWC therefore calls assignAppPermset / saveGrant (and the revoke pair)
 * as separate transactions. Audit rows go to GTM_Access_Log__c via @future.
 */
public with sharing class GtmTeamAccessController {

    public static final String ROLE_ADMIN = 'Admin';
    public static final String ROLE_LEADER = 'Leader';
    public static final String ROLE_MEMBER = 'Team_Member';

    public static final String PERM_ACCESS = 'GTM_Team_Johnson_Access';
    public static final String PERM_VIEWER = 'GTM_Team_Johnson_Viewer';
    private static final Set<String> APP_PERMSETS = new Set<String>{ PERM_ACCESS, PERM_VIEWER };

    public class CatalogItem {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean checked;
        public CatalogItem() {}
        public CatalogItem(String key, String label, Boolean checked) {
            this.key = key;
            this.label = label;
            this.checked = checked;
        }
    }

    public class AccessUser {
        @AuraEnabled public Id id;
        @AuraEnabled public String name, username, profile, title, role, roleLabel;
        @AuraEnabled public Boolean active;
        @AuraEnabled public List<String> tabs = new List<String>();
        @AuraEnabled public List<String> activities = new List<String>();
        @AuraEnabled public String tabSummary;
        @AuraEnabled public String activitySummary;
    }

    public class AccessInfo {
        @AuraEnabled public List<AccessUser> users = new List<AccessUser>();
        @AuraEnabled public List<CatalogItem> tabCatalog = new List<CatalogItem>();
        @AuraEnabled public List<CatalogItem> activityCatalog = new List<CatalogItem>();
        @AuraEnabled public Boolean canManage = false;
        @AuraEnabled public Boolean editInCall = false, overrideClass = false, apexAccess = false;
        @AuraEnabled public String permSet = PERM_ACCESS;
        @AuraEnabled public String viewerPermSet = PERM_VIEWER;
        @AuraEnabled public Integer userCount = 0;
    }

    public class UserGrant {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name, username, profile, title;
        @AuraEnabled public String role;
        @AuraEnabled public List<CatalogItem> tabs = new List<CatalogItem>();
        @AuraEnabled public List<CatalogItem> activities = new List<CatalogItem>();
        @AuraEnabled public Boolean existing = false;
    }

    public class AccessUserHit {
        @AuraEnabled public Id id;
        @AuraEnabled public String name, username, profile, title;
        @AuraEnabled public Boolean alreadyAssigned;
    }

    @AuraEnabled(cacheable=true)
    public static AccessInfo getAccessMatrix() {
        AccessInfo info = new AccessInfo();
        info.canManage = canManageAssignments();
        info.tabCatalog = defaultCatalog('tab', ROLE_LEADER);
        info.activityCatalog = defaultCatalog('activity', ROLE_LEADER);
        fillPermsetBadges(info);

        Map<Id, GTM_Team_Access__c> grants = loadGrantsByUser();
        Set<Id> seen = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, Assignee.Name, Assignee.Username, Assignee.IsActive,
                   Assignee.Title, Assignee.Profile.Name, PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name IN :APP_PERMSETS AND Assignee.IsActive = true
            ORDER BY Assignee.Name
        ]) {
            if (seen.contains(psa.AssigneeId)) {
                continue;
            }
            seen.add(psa.AssigneeId);
            info.users.add(toAccessUser(
                psa.AssigneeId,
                psa.Assignee.Name,
                psa.Assignee.Username,
                psa.Assignee.Profile != null ? psa.Assignee.Profile.Name : null,
                psa.Assignee.Title,
                psa.Assignee.IsActive,
                grants.get(psa.AssigneeId),
                psa.PermissionSet.Name
            ));
        }
        for (GTM_Team_Access__c g : grants.values()) {
            if (g.User__c == null || seen.contains(g.User__c)) {
                continue;
            }
            seen.add(g.User__c);
            User u = g.User__r;
            info.users.add(toAccessUser(
                g.User__c,
                u != null ? u.Name : null,
                u != null ? u.Username : null,
                u != null && u.Profile != null ? u.Profile.Name : null,
                u != null ? u.Title : null,
                u != null ? u.IsActive : true,
                g,
                null
            ));
        }
        info.userCount = info.users.size();
        return info;
    }

    @AuraEnabled
    public static List<AccessUserHit> searchUsers(String term) {
        assertCanManage();
        String raw = term == null ? '' : term.trim();
        if (raw.length() < 2) {
            return new List<AccessUserHit>();
        }
        String likeTerm = '%' + raw + '%';
        Set<Id> assigned = assignedUserIds();
        List<AccessUserHit> hits = new List<AccessUserHit>();
        for (User u : [
            SELECT Id, Name, Username, Title, Profile.Name
            FROM User
            WHERE IsActive = true
              AND UserType = 'Standard'
              AND (Name LIKE :likeTerm OR Username LIKE :likeTerm OR Email LIKE :likeTerm)
            ORDER BY Name
            LIMIT 25
        ]) {
            AccessUserHit h = new AccessUserHit();
            h.id = u.Id;
            h.name = u.Name;
            h.username = u.Username;
            h.title = u.Title;
            h.profile = u.Profile != null ? u.Profile.Name : null;
            h.alreadyAssigned = assigned.contains(u.Id);
            hits.add(h);
        }
        return hits;
    }

    @AuraEnabled
    public static UserGrant getUserGrant(Id userId) {
        assertCanManage();
        if (userId == null) {
            throw new AuraHandledException('A user is required.');
        }
        List<User> found = [
            SELECT Id, Name, Username, Title, Profile.Name
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new AuraHandledException('That user was not found.');
        }
        User u = found[0];
        UserGrant g = new UserGrant();
        g.userId = u.Id;
        g.name = u.Name;
        g.username = u.Username;
        g.title = u.Title;
        g.profile = u.Profile != null ? u.Profile.Name : null;
        List<GTM_Team_Access__c> rows = [
            SELECT Role__c, Tabs__c, Activities__c
            FROM GTM_Team_Access__c
            WHERE User_Key__c = :String.valueOf(userId)
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            g.role = ROLE_MEMBER;
            g.tabs = defaultCatalog('tab', g.role);
            g.activities = defaultCatalog('activity', g.role);
            g.existing = false;
            return g;
        }
        g.existing = true;
        g.role = normalizeRole(rows[0].Role__c);
        g.tabs = catalogFromStored('tab', g.role, rows[0].Tabs__c);
        g.activities = catalogFromStored('activity', g.role, rows[0].Activities__c);
        return g;
    }

    @AuraEnabled
    public static UserGrant rolePreset(String role) {
        assertCanManage();
        UserGrant g = new UserGrant();
        g.role = normalizeRole(role);
        g.tabs = defaultCatalog('tab', g.role);
        g.activities = defaultCatalog('activity', g.role);
        return g;
    }

    @AuraEnabled
    public static void saveGrant(Id userId, String role, List<String> tabs, List<String> activities) {
        assertCanManage();
        if (userId == null) {
            throw new AuraHandledException('A user is required.');
        }
        String normalized = normalizeRole(role);
        Set<String> tabKeys = sanitizeKeys('tab', tabs);
        Set<String> actKeys = sanitizeKeys('activity', activities);
        GTM_Team_Access__c row = new GTM_Team_Access__c(
            User__c = userId,
            User_Key__c = String.valueOf(userId),
            Role__c = normalized,
            Tabs__c = joinKeys(tabKeys),
            Activities__c = joinKeys(actKeys)
        );
        try {
            upsert row User_Key__c;
        } catch (DmlException e) {
            throw new AuraHandledException('Could not save access: ' + e.getDmlMessage(0));
        }
        logAccessChange(userId, 'GTM Team Access', 'GTM_Team_Access__c', null, 'Assigned',
            'Saved Team Johnson ' + roleLabel(normalized) + ' grant for user ' + String.valueOf(userId) + '.');
    }

    @AuraEnabled
    public static void assignAppPermset(Id userId, String role, List<String> activities) {
        assertCanManage();
        if (userId == null) {
            throw new AuraHandledException('A user is required.');
        }
        String target = targetPermset(normalizeRole(role), sanitizeKeys('activity', activities));
        Map<String, Id> psByName = permsetIds();
        if (!psByName.containsKey(target)) {
            throw new AuraHandledException('Access permission set not found: ' + target);
        }
        List<PermissionSetAssignment> existing = [
            SELECT Id, PermissionSetId, PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name IN :APP_PERMSETS
        ];
        List<PermissionSetAssignment> toDelete = new List<PermissionSetAssignment>();
        Boolean alreadyTarget = false;
        for (PermissionSetAssignment a : existing) {
            if (a.PermissionSetId == psByName.get(target)) {
                alreadyTarget = true;
            } else {
                toDelete.add(a);
            }
        }
        try {
            if (!toDelete.isEmpty()) {
                delete toDelete;
            }
            if (!alreadyTarget) {
                insert new PermissionSetAssignment(PermissionSetId = psByName.get(target), AssigneeId = userId);
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Could not update access: ' + e.getDmlMessage(0));
        }
        logAccessChange(userId, target, target, psByName.get(target), 'Assigned',
            'Assigned ' + target + ' to user ' + String.valueOf(userId) + '.');
    }

    @AuraEnabled
    public static void deleteGrant(Id userId) {
        assertCanManage();
        if (userId == null) {
            throw new AuraHandledException('A user is required.');
        }
        List<GTM_Team_Access__c> rows = [
            SELECT Id FROM GTM_Team_Access__c WHERE User_Key__c = :String.valueOf(userId)
        ];
        if (!rows.isEmpty()) {
            delete rows;
        }
        logAccessChange(userId, 'GTM Team Access', 'GTM_Team_Access__c', null, 'Removed',
            'Removed Team Johnson grant for user ' + String.valueOf(userId) + '.');
    }

    @AuraEnabled
    public static void revokeAppPermset(Id userId) {
        assertCanManage();
        if (userId == null) {
            throw new AuraHandledException('A user is required.');
        }
        List<PermissionSetAssignment> psa = [
            SELECT Id, PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name IN :APP_PERMSETS AND AssigneeId = :userId
        ];
        if (!psa.isEmpty()) {
            String names = psa[0].PermissionSet.Name;
            delete psa;
            logAccessChange(userId, names, names, null, 'Removed',
                'Removed Team Johnson permset from user ' + String.valueOf(userId) + '.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static UserGrant getMyAccess() {
        Id uid = UserInfo.getUserId();
        UserGrant g = new UserGrant();
        g.userId = uid;
        g.name = UserInfo.getName();
        List<GTM_Team_Access__c> rows = [
            SELECT Role__c, Tabs__c, Activities__c
            FROM GTM_Team_Access__c
            WHERE User_Key__c = :String.valueOf(uid)
            LIMIT 1
        ];
        String inferred = inferredRoleFromPermset(uid);
        if (rows.isEmpty()) {
            g.role = inferred == null ? ROLE_MEMBER : inferred;
            g.tabs = defaultCatalog('tab', g.role);
            g.activities = defaultCatalog('activity', g.role);
            g.existing = false;
            return g;
        }
        g.existing = true;
        g.role = normalizeRole(rows[0].Role__c);
        g.tabs = catalogFromStored('tab', g.role, rows[0].Tabs__c);
        g.activities = catalogFromStored('activity', g.role, rows[0].Activities__c);
        return g;
    }

    @TestVisible
    static Boolean canManageAssignments() {
        return ![
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND (
                  PermissionSet.PermissionsManageUsers = true
                  OR PermissionSet.PermissionsAssignPermissionSets = true
              )
            LIMIT 1
        ].isEmpty();
    }

    private static void assertCanManage() {
        if (!canManageAssignments()) {
            throw new AuraHandledException('You do not have permission to assign users. Ask a Salesforce admin.');
        }
    }

    @TestVisible
    static String normalizeRole(String role) {
        String r = role == null ? '' : role.trim();
        if (r.equalsIgnoreCase(ROLE_ADMIN) || r.equalsIgnoreCase('full')) {
            return ROLE_ADMIN;
        }
        if (r.equalsIgnoreCase(ROLE_LEADER)) {
            return ROLE_LEADER;
        }
        if (r.equalsIgnoreCase(ROLE_MEMBER) || r.equalsIgnoreCase('viewer') || r.equalsIgnoreCase('Team member')) {
            return ROLE_MEMBER;
        }
        return ROLE_MEMBER;
    }

    @TestVisible
    static String roleLabel(String role) {
        String r = normalizeRole(role);
        if (r == ROLE_ADMIN) {
            return 'Admin';
        }
        if (r == ROLE_LEADER) {
            return 'Leader';
        }
        return 'Team member';
    }

    @TestVisible
    static String targetPermset(String role, Set<String> activities) {
        if (role == ROLE_ADMIN || role == ROLE_LEADER) {
            return PERM_ACCESS;
        }
        if (activities != null && (activities.contains('tick_call')
                || activities.contains('override_class')
                || activities.contains('manage_users'))) {
            return PERM_ACCESS;
        }
        return PERM_VIEWER;
    }

    @TestVisible
    static List<CatalogItem> defaultCatalog(String kind, String role) {
        String r = normalizeRole(role);
        List<CatalogItem> items = new List<CatalogItem>();
        if (kind == 'tab') {
            items.add(new CatalogItem('main', 'Main (Team Opportunity Insights)', r != ROLE_MEMBER));
            items.add(new CatalogItem('sales_performance', 'Sales Performance', true));
            items.add(new CatalogItem('conversion_metrics', 'Conversion Metrics', r != ROLE_MEMBER));
            items.add(new CatalogItem('sales_tools', 'Sales Tools', true));
            items.add(new CatalogItem('pricing_review', 'Pricing Review Checklist', true));
            items.add(new CatalogItem('admin', 'Admin', r == ROLE_ADMIN));
            return items;
        }
        items.add(new CatalogItem('view_forecast', 'View Forecast, Pipeline & Conversion sub-tabs', true));
        items.add(new CatalogItem('tick_call', 'Tick deals into the call', r != ROLE_MEMBER));
        items.add(new CatalogItem('override_class', 'Override deal classification', r != ROLE_MEMBER));
        items.add(new CatalogItem('pricing_review', 'Run the Pricing Review checklist', true));
        items.add(new CatalogItem('claude_insight', 'Run Claude AI insight', true));
        items.add(new CatalogItem('adjust_weights', 'Adjust weights & submitted call', r != ROLE_MEMBER));
        items.add(new CatalogItem('manage_users', 'Assign and edit user access', r == ROLE_ADMIN));
        return items;
    }

    private static List<CatalogItem> catalogFromStored(String kind, String role, String stored) {
        Set<String> keys = splitKeys(stored);
        if (keys.isEmpty()) {
            return defaultCatalog(kind, role);
        }
        List<CatalogItem> items = defaultCatalog(kind, role);
        for (CatalogItem item : items) {
            item.checked = keys.contains(item.key);
        }
        return items;
    }

    private static Set<String> sanitizeKeys(String kind, List<String> incoming) {
        Set<String> allowed = new Set<String>();
        for (CatalogItem item : defaultCatalog(kind, ROLE_ADMIN)) {
            allowed.add(item.key);
        }
        Set<String> out = new Set<String>();
        if (incoming == null) {
            return out;
        }
        for (String key : incoming) {
            if (String.isNotBlank(key) && allowed.contains(key)) {
                out.add(key);
            }
        }
        return out;
    }

    private static Set<String> splitKeys(String stored) {
        Set<String> keys = new Set<String>();
        if (String.isBlank(stored)) {
            return keys;
        }
        for (String part : stored.split(';')) {
            String key = part == null ? '' : part.trim();
            if (String.isNotBlank(key)) {
                keys.add(key);
            }
        }
        return keys;
    }

    private static String joinKeys(Set<String> keys) {
        if (keys == null || keys.isEmpty()) {
            return '';
        }
        List<String> ordered = new List<String>(keys);
        ordered.sort();
        return String.join(ordered, ';');
    }

    private static Map<Id, GTM_Team_Access__c> loadGrantsByUser() {
        Map<Id, GTM_Team_Access__c> byUser = new Map<Id, GTM_Team_Access__c>();
        for (GTM_Team_Access__c row : [
            SELECT User__c, User_Key__c, Role__c, Tabs__c, Activities__c,
                   User__r.Name, User__r.Username, User__r.IsActive, User__r.Title, User__r.Profile.Name
            FROM GTM_Team_Access__c
            WHERE User__c != null
        ]) {
            byUser.put(row.User__c, row);
        }
        return byUser;
    }

    private static Set<Id> assignedUserIds() {
        Set<Id> ids = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name IN :APP_PERMSETS AND Assignee.IsActive = true
        ]) {
            ids.add(psa.AssigneeId);
        }
        for (GTM_Team_Access__c row : [SELECT User__c FROM GTM_Team_Access__c WHERE User__c != null]) {
            ids.add(row.User__c);
        }
        return ids;
    }

    private static AccessUser toAccessUser(
        Id userId,
        String name,
        String username,
        String profile,
        String title,
        Boolean active,
        GTM_Team_Access__c grant,
        String permsetName
    ) {
        AccessUser u = new AccessUser();
        u.id = userId;
        u.name = name;
        u.username = username;
        u.profile = profile;
        u.title = title;
        u.active = active == true;
        String role = grant != null ? normalizeRole(grant.Role__c) : inferredRoleFromName(permsetName);
        u.role = role;
        u.roleLabel = roleLabel(role);
        List<CatalogItem> tabs = grant != null
            ? catalogFromStored('tab', role, grant.Tabs__c)
            : defaultCatalog('tab', role);
        List<CatalogItem> acts = grant != null
            ? catalogFromStored('activity', role, grant.Activities__c)
            : defaultCatalog('activity', role);
        for (CatalogItem t : tabs) {
            if (t.checked == true) {
                u.tabs.add(t.label);
            }
        }
        for (CatalogItem a : acts) {
            if (a.checked == true) {
                u.activities.add(a.label);
            }
        }
        u.tabSummary = u.tabs.isEmpty() ? 'None' : String.join(u.tabs, ', ');
        u.activitySummary = u.activities.isEmpty() ? 'None' : String.join(u.activities, ', ');
        return u;
    }

    private static String inferredRoleFromName(String permsetName) {
        if (permsetName == PERM_VIEWER) {
            return ROLE_MEMBER;
        }
        return ROLE_LEADER;
    }

    private static String inferredRoleFromPermset(Id userId) {
        for (PermissionSetAssignment psa : [
            SELECT PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name IN :APP_PERMSETS
        ]) {
            return inferredRoleFromName(psa.PermissionSet.Name);
        }
        return null;
    }

    private static Map<String, Id> permsetIds() {
        Map<String, Id> byName = new Map<String, Id>();
        for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :APP_PERMSETS]) {
            byName.put(ps.Name, ps.Id);
        }
        return byName;
    }

    private static void fillPermsetBadges(AccessInfo info) {
        for (FieldPermissions fp : [
            SELECT Field, PermissionsEdit
            FROM FieldPermissions
            WHERE Parent.Name = :PERM_ACCESS
        ]) {
            if (fp.Field == 'Opportunity.Cockpit_In_Call__c' && fp.PermissionsEdit) {
                info.editInCall = true;
            }
            if (fp.Field == 'Opportunity.Cockpit_Class_Override__c' && fp.PermissionsEdit) {
                info.overrideClass = true;
            }
        }
        for (SetupEntityAccess sea : [
            SELECT SetupEntityType
            FROM SetupEntityAccess
            WHERE Parent.Name = :PERM_ACCESS AND SetupEntityType = 'ApexClass'
            LIMIT 1
        ]) {
            info.apexAccess = true;
        }
    }

    private static void logAccessChange(
        String targetUserId,
        String item,
        String apiName,
        Id permRecordId,
        String action,
        String detail
    ) {
        logChangeFuture(
            String.valueOf(targetUserId),
            item,
            apiName,
            permRecordId == null ? null : String.valueOf(permRecordId),
            'Permission Set',
            action,
            detail
        );
    }

    @future
    private static void logChangeFuture(
        String targetUserId,
        String item,
        String apiName,
        String permRecordId,
        String permType,
        String action,
        String detail
    ) {
        try {
            insert new GTM_Access_Log__c(
                Target_User__c = (Id) targetUserId,
                Permission_Item__c = item,
                Permission_Api_Name__c = apiName,
                Permission_Record_Id__c = permRecordId,
                Permission_Type__c = permType,
                Action__c = action,
                Detail__c = detail
            );
        } catch (Exception e) {
            // Audit must never roll back the access change.
        }
    }
}
