/**
 * Resolves a director's selling team (guide P4). Walks User.ManagerId TWO levels
 * and removes anyone whose role, profile or title marks them BDR/SDR or an SE.
 * A one-level walk misses reports through a team lead; no exclusion counts
 * BDR/SE-owned records as pipeline.
 */
public with sharing class CockpitRosterService {

    public class Member {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        public Member(Id i, String n) { userId = i; name = n; }
    }

    public static List<Member> teamFor(Id directorId) {
        Set<Id> level1 = new Set<Id>();
        for (User u : [
            SELECT Id FROM User
            WHERE ManagerId = :directorId AND IsActive = true
            WITH USER_MODE
        ]) { level1.add(u.Id); }

        Set<Id> everyone = new Set<Id>(level1);
        if (!level1.isEmpty()) {
            for (User u : [
                SELECT Id FROM User
                WHERE ManagerId IN :level1 AND IsActive = true
                WITH USER_MODE
            ]) { everyone.add(u.Id); }
        }
        if (everyone.isEmpty()) return new List<Member>();

        List<Member> keep = new List<Member>();
        for (User u : [
            SELECT Id, Name, Title, Profile.Name, UserRole.Name
            FROM User WHERE Id IN :everyone
            WITH USER_MODE ORDER BY Name
        ]) {
            if (!isNonAE(u)) keep.add(new Member(u.Id, u.Name));
        }
        return keep;
    }

    public static Set<Id> teamIds(Id directorId) {
        Set<Id> ids = new Set<Id>();
        for (Member m : teamFor(directorId)) ids.add(m.userId);
        return ids;
    }

    /**
     * Selling-team leaders whose UserRole rolls up to Chief Sales Officer.
     * CS / PS / Finance managers are out — their roles sit under other execs.
     * Bid, SE, BDR, and Partnerships sit under the CSO but are not sales teams.
     */
    public class DirectorOption {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String segment;
        public DirectorOption(Id i, String n, String s) {
            userId = i;
            name = n;
            segment = s;
        }
    }

    public static List<DirectorOption> salesDirectors() {
        Set<Id> roleIds = rolesUnderChiefSalesOfficer();
        if (roleIds.isEmpty()) return new List<DirectorOption>();

        List<User> candidates = [
            SELECT Id, Name, Title, UserRoleId, UserRole.Name
            FROM User
            WHERE IsActive = true AND UserRoleId IN :roleIds
            WITH USER_MODE
            ORDER BY Name
        ];
        if (candidates.isEmpty()) return new List<DirectorOption>();

        Set<Id> candIds = new Set<Id>();
        for (User u : candidates) candIds.add(u.Id);

        Map<Id, Set<Id>> reports = new Map<Id, Set<Id>>();
        for (User u : [
            SELECT Id, ManagerId FROM User
            WHERE IsActive = true AND ManagerId IN :candIds
            WITH USER_MODE
        ]) {
            if (!reports.containsKey(u.ManagerId)) reports.put(u.ManagerId, new Set<Id>());
            reports.get(u.ManagerId).add(u.Id);
        }
        Set<Id> level1 = new Set<Id>();
        for (Set<Id> kids : reports.values()) level1.addAll(kids);
        if (!level1.isEmpty()) {
            for (User u : [
                SELECT Id, ManagerId FROM User
                WHERE IsActive = true AND ManagerId IN :level1
                WITH USER_MODE
            ]) {
                if (!reports.containsKey(u.ManagerId)) reports.put(u.ManagerId, new Set<Id>());
                reports.get(u.ManagerId).add(u.Id);
            }
        }

        Set<Id> teamIds = new Set<Id>();
        for (User c : candidates) teamIds.addAll(twoLevelReports(c.Id, reports));
        Map<Id, User> teamUsers = new Map<Id, User>();
        if (!teamIds.isEmpty()) {
            for (User u : [
                SELECT Id, Title, Profile.Name, UserRole.Name
                FROM User WHERE Id IN :teamIds
                WITH USER_MODE
            ]) {
                teamUsers.put(u.Id, u);
            }
        }

        Map<Id, String> segmentByUser = salesDirectorSegments();
        List<DirectorOption> out = new List<DirectorOption>();
        for (User c : candidates) {
            if (!isSalesTeamLeaderRole(
                c.UserRole == null ? null : c.UserRole.Name, c.Title
            )) continue;
            if (!hasAeOnTeam(twoLevelReports(c.Id, reports), teamUsers)) continue;
            out.add(new DirectorOption(c.Id, c.Name, segmentByUser.get(c.Id)));
        }
        return out;
    }

    public static Set<Id> rolesUnderChiefSalesOfficer() {
        Id cso = chiefSalesOfficerRoleId();
        if (cso == null) return new Set<Id>();
        Map<Id, List<Id>> children = new Map<Id, List<Id>>();
        for (UserRole r : [SELECT Id, ParentRoleId FROM UserRole]) {
            if (r.ParentRoleId == null) continue;
            if (!children.containsKey(r.ParentRoleId)) {
                children.put(r.ParentRoleId, new List<Id>());
            }
            children.get(r.ParentRoleId).add(r.Id);
        }
        Set<Id> under = new Set<Id>();
        List<Id> stack = new List<Id>{ cso };
        while (!stack.isEmpty()) {
            Id cur = stack.remove(stack.size() - 1);
            if (under.contains(cur)) continue;
            under.add(cur);
            if (children.containsKey(cur)) stack.addAll(children.get(cur));
        }
        return under;
    }

    @TestVisible
    static Boolean isSalesTeamLeaderRole(String roleName, String title) {
        if (String.isBlank(roleName)) return false;
        String role = roleName.toUpperCase();
        String ttl = title == null ? '' : title.toUpperCase();
        for (String token : CockpitConstants.NON_SALES_LEADER_ROLE_TOKENS) {
            if (role.contains(token)) return false;
        }
        if (role == CockpitConstants.CSO_ROLE_NAME.toUpperCase()) {
            return ttl.contains(CockpitConstants.CSO_ROLE_NAME.toUpperCase());
        }
        if (role == 'VP SALES') return true;
        return role.contains('DIRECTOR');
    }

    @TestVisible
    static Id chiefSalesOfficerRoleId() {
        for (UserRole r : [
            SELECT Id FROM UserRole
            WHERE DeveloperName = :CockpitConstants.CSO_ROLE_DEVELOPER_NAME
               OR Name = :CockpitConstants.CSO_ROLE_NAME
            LIMIT 1
        ]) {
            return r.Id;
        }
        return null;
    }

    private static Set<Id> twoLevelReports(Id managerId, Map<Id, Set<Id>> reports) {
        Set<Id> out = new Set<Id>();
        Set<Id> l1 = reports.containsKey(managerId) ? reports.get(managerId) : new Set<Id>();
        out.addAll(l1);
        for (Id kid : l1) {
            if (reports.containsKey(kid)) out.addAll(reports.get(kid));
        }
        return out;
    }

    private static Boolean hasAeOnTeam(Set<Id> team, Map<Id, User> teamUsers) {
        for (Id uid : team) {
            User u = teamUsers.get(uid);
            if (u != null && !isNonAE(u)) return true;
        }
        return false;
    }

    private static Map<Id, String> salesDirectorSegments() {
        Map<Id, String> out = new Map<Id, String>();
        List<Forecast_Director__mdt> rows = [
            SELECT Username__c, Segment_Label__c
            FROM Forecast_Director__mdt
            WHERE Is_Active__c = true AND Excluded__c = false
        ];
        Set<String> usernames = new Set<String>();
        for (Forecast_Director__mdt r : rows) {
            if (String.isNotBlank(r.Username__c)) usernames.add(r.Username__c);
        }
        if (usernames.isEmpty()) return out;
        Map<String, Id> idByUser = new Map<String, Id>();
        for (User u : [
            SELECT Id, Username FROM User
            WHERE Username IN :usernames AND IsActive = true
            WITH USER_MODE
        ]) {
            idByUser.put(u.Username, u.Id);
        }
        for (Forecast_Director__mdt r : rows) {
            Id uid = idByUser.get(r.Username__c);
            if (uid != null) out.put(uid, r.Segment_Label__c);
        }
        return out;
    }

    private static Boolean isNonAE(User u) {
        String haystack = (
            (u.Title == null ? '' : u.Title) + ' ' +
            (u.Profile == null || u.Profile.Name == null ? '' : u.Profile.Name) + ' ' +
            (u.UserRole == null || u.UserRole.Name == null ? '' : u.UserRole.Name)
        ).toUpperCase();

        for (String token : CockpitConstants.NON_AE_TOKENS) {
            if (haystack.contains(token)) return true;
        }
        return false;
    }
}
