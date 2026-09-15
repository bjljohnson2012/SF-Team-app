/**
 * Resolves a selling team from a director (or the running user). Walks
 * User.ManagerId TWO levels and removes BDR/SDR/SE. Scope is director-driven
 * — never a hardcoded roster. An AE with no reports sees themselves.
 */
public with sharing class CockpitRosterService {

    public class Member {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        public Member(Id i, String n) { userId = i; name = n; }
    }

    public class ScopeResult {
        @AuraEnabled public Id directorId;
        @AuraEnabled public String directorName;
        @AuraEnabled public String teamMode;
        @AuraEnabled public List<Member> members;
        @AuraEnabled public String emptyMessage;
        public Set<Id> ownerIds() {
            Set<Id> ids = new Set<Id>();
            if (members == null) return ids;
            for (Member m : members) ids.add(m.userId);
            return ids;
        }
    }

    public static Id resolveDirectorId(Id directorId, String teamMode) {
        if (directorId == null
            || teamMode == CockpitConstants.TEAM_MODE_MY
            || teamMode == 'mine') {
            return UserInfo.getUserId();
        }
        return directorId;
    }

    /** Euna product / solution family as it exists on Opportunity. */
    public static List<String> productTypes() {
        List<String> out = new List<String>();
        for (Schema.PicklistEntry e : Opportunity.EUNA_Solution__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) out.add(e.getValue());
        }
        return out;
    }

    public static ScopeResult resolveScope(Id directorId, String teamMode) {
        ScopeResult s = new ScopeResult();
        s.teamMode = String.isBlank(teamMode) ? CockpitConstants.TEAM_MODE_MY : teamMode;
        s.directorId = resolveDirectorId(directorId, s.teamMode);
        s.members = teamFor(s.directorId);
        User dir = [
            SELECT Name FROM User WHERE Id = :s.directorId
            WITH USER_MODE
            LIMIT 1
        ];
        s.directorName = dir.Name;
        if (s.members.isEmpty()) {
            s.emptyMessage = 'This scope has no account executives. '
                + 'An AE can still open their own row; pick another director or My team.';
        }
        return s;
    }

    public static List<Member> listDirectors() {
        Map<Id, List<Id>> children = new Map<Id, List<Id>>();
        Map<Id, User> byId = new Map<Id, User>();
        for (User u : [
            SELECT Id, Name, Title, ManagerId, Profile.Name, UserRole.Name
            FROM User
            WHERE IsActive = true
            WITH USER_MODE
        ]) {
            byId.put(u.Id, u);
            if (u.ManagerId == null) continue;
            if (!children.containsKey(u.ManagerId)) children.put(u.ManagerId, new List<Id>());
            children.get(u.ManagerId).add(u.Id);
        }

        List<Member> out = new List<Member>();
        for (Id mgrId : children.keySet()) {
            User mgr = byId.get(mgrId);
            if (mgr == null) continue;
            if (!aeReportsOf(mgrId, children, byId).isEmpty()) {
                out.add(new Member(mgr.Id, mgr.Name));
            }
        }
        out.sort(new MemberNameSort());
        return out;
    }

    public static List<Id> directorIdsForBatch() {
        List<Id> ids = new List<Id>();
        for (Member m : listDirectors()) ids.add(m.userId);
        return ids;
    }

    public static List<Member> teamFor(Id directorId) {
        if (directorId == null) directorId = UserInfo.getUserId();

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

        List<Member> keep = new List<Member>();
        if (!everyone.isEmpty()) {
            for (User u : [
                SELECT Id, Name, Title, Profile.Name, UserRole.Name
                FROM User WHERE Id IN :everyone
                WITH USER_MODE ORDER BY Name
            ]) {
                if (!isNonAE(u)) keep.add(new Member(u.Id, u.Name));
            }
        }
        if (!keep.isEmpty()) return keep;

        User self = [
            SELECT Id, Name, Title, Profile.Name, UserRole.Name
            FROM User WHERE Id = :directorId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!isNonAE(self)) keep.add(new Member(self.Id, self.Name));
        return keep;
    }

    public static Set<Id> teamIds(Id directorId) {
        Set<Id> ids = new Set<Id>();
        for (Member m : teamFor(directorId)) ids.add(m.userId);
        return ids;
    }

    private static Set<Id> aeReportsOf(Id mgrId, Map<Id, List<Id>> children, Map<Id, User> byId) {
        Set<Id> walk = new Set<Id>();
        if (children.containsKey(mgrId)) walk.addAll(children.get(mgrId));
        Set<Id> level2 = new Set<Id>();
        for (Id mid : walk) {
            if (children.containsKey(mid)) level2.addAll(children.get(mid));
        }
        walk.addAll(level2);
        Set<Id> aes = new Set<Id>();
        for (Id uid : walk) {
            User u = byId.get(uid);
            if (u != null && !isNonAE(u)) aes.add(uid);
        }
        return aes;
    }

    private class MemberNameSort implements Comparator<Member> {
        public Integer compare(Member a, Member b) {
            String an = a == null || a.name == null ? '' : a.name;
            String bn = b == null || b.name == null ? '' : b.name;
            return an.toLowerCase().compareTo(bn.toLowerCase());
        }
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