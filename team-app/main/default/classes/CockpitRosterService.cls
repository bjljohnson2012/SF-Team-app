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

    public class Scope {
        @AuraEnabled public Id directorId;
        @AuraEnabled public String directorName;
        @AuraEnabled public Boolean selfScoped;
        @AuraEnabled public List<Member> members;
        public Set<Id> ids() {
            Set<Id> out = new Set<Id>();
            if (members == null) return out;
            for (Member m : members) out.add(m.userId);
            return out;
        }
    }

    /**
     * Director-driven roster. Default is the running user's team; an AE with
     * no reports sees themselves. Never a hardcoded director id.
     */
    public static Scope resolve(Id directorId, String teamMode) {
        Boolean mine = String.isBlank(teamMode)
            || teamMode == CockpitConstants.TEAM_MODE_MINE
            || directorId == null;
        Id scopeId = mine ? UserInfo.getUserId() : directorId;

        Scope s = new Scope();
        s.directorId = scopeId;
        s.members = teamFor(scopeId);
        s.selfScoped = false;

        if (s.members.isEmpty()) {
            User me = [
                SELECT Id, Name, Title, Profile.Name, UserRole.Name
                FROM User WHERE Id = :UserInfo.getUserId()
                WITH USER_MODE
            ];
            if (!isNonAE(me)) {
                s.members.add(new Member(me.Id, me.Name));
                s.selfScoped = true;
                s.directorId = me.Id;
                s.directorName = me.Name;
                return s;
            }
        }

        User director = [
            SELECT Id, Name FROM User WHERE Id = :scopeId
            WITH USER_MODE LIMIT 1
        ];
        s.directorName = director.Name;
        return s;
    }

    /** Active managers — the director picker, not a Team Johnson hardcode. */
    public static List<Member> listDirectors() {
        Set<Id> mgrIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT ManagerId mid
            FROM User
            WHERE IsActive = true AND ManagerId != null
            WITH USER_MODE
            GROUP BY ManagerId
        ]) {
            mgrIds.add((Id) ar.get('mid'));
        }
        List<Member> out = new List<Member>();
        if (mgrIds.isEmpty()) return out;
        for (User u : [
            SELECT Id, Name FROM User
            WHERE Id IN :mgrIds AND IsActive = true
            WITH USER_MODE ORDER BY Name
        ]) {
            out.add(new Member(u.Id, u.Name));
        }
        return out;
    }

    /** Euna product / solution family as it exists on Opportunity. */
    public static List<String> productTypes() {
        List<String> out = new List<String>();
        for (Schema.PicklistEntry e : Opportunity.EUNA_Solution__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) out.add(e.getValue());
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
