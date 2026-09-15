/**
 * Aura entry for the Conversion Metrics page. Scope arrives from the shared
 * gtmScopeFilters contract (directorId, teamMode, productType, sizeBand)
 * plus a page-local closeQuarter. Computes live — this tab is closure-based.
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
        String sizeBand,
        String closeQuarter
    ) {
        return CockpitConversionService.load(directorId, teamMode, productType, sizeBand, closeQuarter);
    }
}
