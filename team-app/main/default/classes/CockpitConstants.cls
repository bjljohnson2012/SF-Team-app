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
