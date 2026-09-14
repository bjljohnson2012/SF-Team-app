/**
 * Aura entry for the Conversion Metrics page. Scope arrives from the shared
 * gtmScopeFilters contract (directorId, teamMode, productType, sizeBand).
 * Computes live — this tab is closure-based, not a cohort snapshot.
 */
public with sharing class CockpitConversionController {

    @AuraEnabled(cacheable=true)
    public static CockpitConversionService.ScopeOptions getScopeOptions() {
        return CockpitConversionService.getScopeOptions();
    }

    @AuraEnabled(cacheable=true)
    public static CockpitConversionService.PagePayload load(
        Id directorId,
        String teamMode,
        String productType,
        String sizeBand
    ) {
        return CockpitConversionService.load(directorId, teamMode, productType, sizeBand);
    }
}
