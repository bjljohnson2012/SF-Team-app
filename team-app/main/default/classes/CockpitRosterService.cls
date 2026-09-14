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
