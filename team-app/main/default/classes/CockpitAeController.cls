/**
 * AE by AE page entry points. Scope is director-driven so any team can use
 * the tab; an AE still sees their own row.
 */
public with sharing class CockpitAeController {

    public class ScopeOptions {
        @AuraEnabled public Id runningUserId;
        @AuraEnabled public String runningUserName;
        @AuraEnabled public List<CockpitRosterService.Member> directors;
        @AuraEnabled public List<String> productTypes;
        @AuraEnabled public List<String> sizeBands;
    }

    @AuraEnabled(cacheable=true)
    public static ScopeOptions getScopeOptions() {
        ScopeOptions o = new ScopeOptions();
        o.runningUserId = UserInfo.getUserId();
        o.runningUserName = UserInfo.getName();
        o.directors = CockpitRosterService.listDirectors();
        o.productTypes = CockpitRosterService.productTypes();
        o.sizeBands = new List<String>{
            CockpitConstants.SIZE_ALL,
            CockpitConstants.SIZE_UNDER_50K,
            CockpitConstants.SIZE_50_150K,
            CockpitConstants.SIZE_OVER_150K
        };
        return o;
    }

    @AuraEnabled
    public static CockpitAeCompositionService.Payload loadComposition(
        Id directorId, String teamMode, String productType, String sizeBand
    ) {
        try {
            CockpitAeCompositionService.ScopeRequest req =
                new CockpitAeCompositionService.ScopeRequest();
            req.directorId = directorId;
            req.teamMode = teamMode;
            req.productType = productType;
            req.sizeBand = sizeBand;
            return CockpitAeCompositionService.compute(req);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getTypeName() + ': ' + e.getMessage());
        }
    }
}
