/**
 * Aura entry for Win Rate Truth and the shared gtmScopeFilters bar.
 * Director / product / size are parameters — never a hardcoded team.
 */
public with sharing class CockpitWinRateController {

    public class Pick {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public Pick(String v, String l) { value = v; label = l; }
    }

    public class FilterOptions {
        @AuraEnabled public Id defaultDirectorId;
        @AuraEnabled public String defaultDirectorName;
        @AuraEnabled public List<Pick> directors;
        @AuraEnabled public List<Pick> productTypes;
        @AuraEnabled public List<Pick> sizeBands;
    }

    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        FilterOptions o = new FilterOptions();
        o.defaultDirectorId = UserInfo.getUserId();
        o.defaultDirectorName = UserInfo.getName();
        o.directors = new List<Pick>{ new Pick('', 'My team') };
        for (CockpitRosterService.Member m : CockpitRosterService.listDirectors()) {
            o.directors.add(new Pick(String.valueOf(m.userId), m.name));
        }
        o.productTypes = new List<Pick>{ new Pick(CockpitConstants.PRODUCT_ALL, 'All products') };
        Schema.DescribeFieldResult d = Opportunity.EUNA_Solution__c.getDescribe();
        for (Schema.PicklistEntry pe : d.getPicklistValues()) {
            if (pe.isActive()) o.productTypes.add(new Pick(pe.getValue(), pe.getLabel()));
        }
        o.sizeBands = new List<Pick>{
            new Pick(CockpitConstants.SIZE_ALL, 'All sizes'),
            new Pick(CockpitConstants.SIZE_UNDER_50K, 'Under $50k'),
            new Pick(CockpitConstants.SIZE_50_150K, '$50–150k'),
            new Pick(CockpitConstants.SIZE_OVER_150K, '$150k+')
        };
        return o;
    }

    @AuraEnabled(cacheable=true)
    public static CockpitCohortService.WinRatePage getPage(
        Id directorId, String teamMode, String productType, String sizeBand
    ) {
        CockpitCohortService.Filter f = new CockpitCohortService.Filter();
        f.directorId = directorId;
        f.teamMode = teamMode;
        f.productType = productType;
        f.sizeBand = sizeBand;
        return CockpitCohortService.buildPage(f);
    }
}
