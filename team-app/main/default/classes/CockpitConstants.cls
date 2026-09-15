/**
 * Euna canon in one place, per the Forecast Cockpit build guide (P3).
 * Phase B (read-only hub) subset: filters, stage weights, roster tokens,
 * scoring thresholds and modeled-call weights. Phase A lifts the thresholds
 * and weights into Cockpit_Setting__mdt; here they are constants.
 * Verified against euna prod schema 2026-09-10.
 */
public with sharing class CockpitConstants {

    // New bookings: 'Cross Sell' has a space; 'Cross-Sell' is not a picklist value.
    public static final Set<String> NEW_BUSINESS_TYPES =
        new Set<String>{ 'New Sale', 'Upsell', 'Cross Sell' };

    // Type alone is not the filter; RecordType is the other half.
    public static final String SALE_RECORDTYPE = 'Euna_Sale';

    // The only ARR field safe to SUM/GROUP BY/ORDER BY across currencies.
    public static final String ARR_FIELD = 'ARR_Opportunity_Amount_USD_Num__c';

    // Deal-stage evidence weights for the rule engine.
    public static final Map<String, Integer> STAGE_POINTS = new Map<String, Integer>{
        'Signature Pending' => 3,
        'Verbal Win'        => 3,
        'Proposal'          => 2,
        'Proof'             => 1,
        'Alignment'         => 0,
        'Discovery'         => -1
    };

    // Who is not an AE, by role / profile / title token (roster exclusion).
    public static final Set<String> NON_AE_TOKENS = new Set<String>{
        'SDR', 'BDR', 'BUSINESS DEVELOPMENT', 'SOLUTION ENGINEER',
        'SOLUTIONS ENGINEER', 'SALES ENGINEER'
    };

    // Apex of the sales role tree. Resolved at runtime via UserRole; not a person.
    public static final String CSO_ROLE_DEVELOPER_NAME = 'Chief_Sales_Officer';
    public static final String CSO_ROLE_NAME = 'Chief Sales Officer';

    // Roles under the CSO that are not selling-team leaders (support, SE, BDR, alliances).
    public static final Set<String> NON_SALES_LEADER_ROLE_TOKENS = new Set<String>{
        'SALES SUPPORT', 'SOLUTION', 'BDR', 'PARTNERSHIP', 'ALLIANCE'
    };

    // Migration stages are not new-business conversion (Type Migration is already out).
    public static final Set<String> MIGRATION_STAGES = new Set<String>{
        'Migration', 'Migrating', 'Migration Complete'
    };

    // Product / solution family as it exists on Opportunity — do not invent a field.
    public static final String PRODUCT_FIELD = 'EUNA_Solution__c';

    public static final String SIZE_ALL = 'ALL';
    public static final String SIZE_UNDER_50K = 'UNDER_50K';
    public static final String SIZE_50_150K = 'BAND_50_150K';
    public static final String SIZE_OVER_150K = 'OVER_150K';
    public static final String PRODUCT_ALL = 'ALL';
    public static final String TEAM_MODE_MY = 'my';
    public static final String TEAM_MODE_DIRECTOR = 'director';

    public static final String SETTING_EXCLUDE_GHOSTED = 'winrate.exclude.ghosted';
    public static final String SETTING_THIN_SAMPLE = 'winrate.thin.sample';
    public static final String SETTING_PURGE_SILENT_DAYS = 'winrate.purge.silent.days';
    public static final String SETTING_PURGE_DUMP_MIN = 'winrate.purge.dump.min';
    public static final String SETTING_SIZE_UNDER = 'winrate.size.under';
    public static final String SETTING_SIZE_MID = 'winrate.size.mid';

    public static final Date LOSS_REASON_RELIABLE_FROM = Date.newInstance(2026, 2, 5);
    public static final Integer DEFAULT_THIN_SAMPLE = 15;
    public static final Integer DEFAULT_PURGE_SILENT_DAYS = 60;
    public static final Integer DEFAULT_PURGE_DUMP_MIN = 5;
    public static final Decimal DEFAULT_SIZE_UNDER = 50000;
    public static final Decimal DEFAULT_SIZE_MID = 150000;

    // Phase B thresholds and modeled-call weights (Phase A: Cockpit_Setting__mdt).
    public static final Integer THRESHOLD_HIGH = 7;   // score >= : Include-High
    public static final Integer THRESHOLD_MED  = 3;   // score >= : Include-Med
    public static final Decimal WEIGHT_HIGH_PCT = 85; // strike rate on Include-High ARR
    public static final Decimal WEIGHT_MED_PCT  = 30; // strike rate on Include-Med ARR

    // Calendar quarter arithmetic. Euna's fiscal calendar IS the calendar year.
    public static Date quarterStart(Integer year, Integer q) {
        return Date.newInstance(year, (q - 1) * 3 + 1, 1);
    }
    public static Date quarterEnd(Integer year, Integer q) {
        return quarterStart(year, q).addMonths(3).addDays(-1);
    }
    public static Integer quarterOf(Date d) {
        return ((d.month() - 1) / 3) + 1;
    }
}
