/**
 * Named tokens for Pipeline Review. No org Ids, user names, or quotas live here —
 * those come from ForecastConfigService and Pipeline_Priority_Config__mdt.
 */
public with sharing class PipelineReviewConstants {
    public static final String ACCESS_REP = 'REP';
    public static final String ACCESS_MANAGER = 'MANAGER';
    public static final String ACCESS_VP = 'VP';

    public static final String SALE_RECORDTYPE = 'Euna_Sale';
    public static final String ARR_FIELD = 'ARR_Opportunity_Amount_USD_Num__c';

    public static final String FC_COMMIT = 'Commit';
    public static final String FC_ML = 'Most Likely';
    public static final String FC_BC = 'Best Case';
    public static final String FC_PIPE = 'Pipeline';
    public static final String FC_OMITTED = 'Omitted';

    public static final List<String> FORECAST_TIERS = new List<String>{
        FC_COMMIT, FC_ML, FC_BC, FC_PIPE, FC_OMITTED
    };

    public static final String STATE_MISSING = 'Missing';
    public static final String STATE_PAST_DUE = 'PastDue';
    public static final String STATE_PARKED = 'Parked';
    public static final String STATE_HEALTHY = 'Healthy';

    public static final String BUCKET_FOCUS = 'Focus';
    public static final String BUCKET_DUE = 'DueThisWeek';
    public static final String BUCKET_KILL = 'DecideOrKill';
    public static final String BUCKET_FIX = 'FixFirst';
    public static final String BUCKET_NONE = 'None';

    public static final String BAND_CURRENT = 'current';
    public static final String BAND_RECENT = 'recent';
    public static final String BAND_AGING = 'aging';
    public static final String BAND_HISTORY = 'history';
    public static final String BAND_UNKNOWN = 'unknown';

    public static final String TITLE_EB = 'EconomicBuyer';
    public static final String TITLE_PRAC = 'Practitioner';
    public static final String TITLE_TECH = 'Technical';

    public static final String NS_REP = 'Rep';
    public static final String NS_ACCEPTED = 'Rep-accepted-AI';
    public static final String NS_AUTO = 'AI-auto';
    public static final String NS_DIRECTOR = 'Director';

    public static final String SRC_HUMAN = 'Human';
    public static final String SRC_AI = 'AI-generated';

    public static final String RUN_QUEUED = 'Queued';
    public static final String RUN_RUNNING = 'Running';
    public static final String RUN_COMPLETED = 'Completed';
    public static final String RUN_FAILED = 'Failed';
    public static final String RUN_CANCELLED = 'Cancelled';

    public static final String ITEM_PENDING = 'Pending';
    public static final String ITEM_SUCCEEDED = 'Succeeded';
    public static final String ITEM_FAILED = 'Failed';
    public static final String ITEM_SKIPPED = 'Skipped';

    public static final String FOCUS_OPEN = 'Open';
    public static final String FOCUS_DONE = 'Done';
    public static final String FOCUS_RESCHEDULED = 'Rescheduled';
    public static final String FOCUS_DROPPED = 'Dropped';

    public static final String MODE_WEEK = 'week';
    public static final String MODE_TODAY = 'today';

    public static final Decimal PARKED_SIMILARITY = 0.6;
    public static final Integer NOTE_MAX_CHARS = 400;
    public static final Integer SUGGEST_MAX_CHARS = 160;
    public static final Integer DEFAULT_NOTE_BATCH = 15;
    public static final Integer DEFAULT_GRADE_BATCH = 200;
    public static final Integer DEFAULT_FOCUS_CAP_WEEK = 10;
    public static final Integer DEFAULT_FOCUS_CAP_TODAY = 5;
    public static final Decimal DEFAULT_CARRYOVER = 10;

    public static final Set<String> EARLY_STAGES = new Set<String>{
        'Discovery', 'Alignment', 'Qualification', 'Prospecting', 'Identify'
    };
    public static final Set<String> LATE_STAGES = new Set<String>{
        'Verbal Win', 'Signature Pending', 'Negotiation', 'Contract', 'Closed Won'
    };
    public static final Set<String> DECISION_ROLES = new Set<String>{
        'Economic Buyer', 'Decision Maker', 'Champion', 'Executive Sponsor'
    };

    public static Integer forecastRank(String value) {
        String n = normalizeForecast(value);
        Integer idx = FORECAST_TIERS.indexOf(n);
        return idx < 0 ? FORECAST_TIERS.size() : idx;
    }

    public static String normalizeForecast(String raw) {
        if (String.isBlank(raw)) return null;
        String v = raw.trim();
        if (v == FC_COMMIT || v == 'Forecast') return FC_COMMIT;
        if (v == FC_ML || v == 'MostLikely') return FC_ML;
        if (v == FC_BC || v == 'BestCase') return FC_BC;
        if (v == FC_PIPE) return FC_PIPE;
        if (v == FC_OMITTED || v == 'Omitted') return FC_OMITTED;
        return v;
    }

    public static String capForecast(String recommended, String atMost) {
        if (String.isBlank(recommended)) return atMost;
        if (String.isBlank(atMost)) return recommended;
        return forecastRank(recommended) > forecastRank(atMost) ? recommended : atMost;
    }

    public static String oneTierBelow(String forecast) {
        Integer idx = forecastRank(forecast);
        if (idx < 0 || idx >= FORECAST_TIERS.size() - 1) return FC_OMITTED;
        return FORECAST_TIERS[idx + 1];
    }

    public static Boolean isLegalForecast(String value) {
        String n = normalizeForecast(value);
        return n != null && FORECAST_TIERS.contains(n);
    }
}
