/**
 * Waterfall filters, shrinkage, and period math. Every division in the
 * cascade is a calibrated rate; this class is where those rates are defined.
 */
public with sharing class WaterfallConstants {

    public static final Integer SHRINKAGE_K = 20;
    public static final Integer TRAILING_QUARTERS = 8;
    public static final Integer QUARTER_DAYS = 91;
    public static final Decimal ACTIVITY_COMPLETE_FLOOR = 0.70;
    public static final Integer CONFIDENCE_HIGH_N = 50;
    public static final Integer CONFIDENCE_MED_N = 15;

    public static final Set<String> EXCLUDED_LOST_REASONS = new Set<String>{
        'Opportunity not Qualified', 'Duplicate Opportunity', 'Ghosted'
    };
    public static final Set<String> SELF_SOURCED = new Set<String>{
        'AE Outbound', 'AM'
    };
    public static final String DISPOSITION_CONNECTED = 'Connected';
    public static final Set<String> BAD_NUMBER_DISPOSITIONS = new Set<String>{
        'Wrong Number', 'Not in Service'
    };
    public static final String CONFIDENCE_HIGH = 'High';
    public static final String CONFIDENCE_MEDIUM = 'Medium';
    public static final String CONFIDENCE_LOW = 'Low';
    public static final String SOLUTION_ALL = 'ALL';

    public static final String METRIC_WIN_RATE = 'WinRate';
    public static final String METRIC_QUAL_RATE = 'QualRate';
    public static final String METRIC_SELF_SHARE = 'SelfShare';
    public static final String METRIC_OPPS_PER_CONNECT = 'OppsPerConnect';
    public static final String METRIC_CONNECT_RATE = 'ConnectRate';
    public static final String METRIC_QO = 'QoNeeded';
    public static final String METRIC_OPPS = 'OppsToCreate';
    public static final String METRIC_CONNECTS = 'Connects';
    public static final String METRIC_DIALS = 'Dials';

    /** Monday = 0. 1900-01-01 was a Monday. */
    public static Integer weekdayIndex(Date day) {
        if (day == null) return null;
        Integer delta = Date.newInstance(1900, 1, 1).daysBetween(day);
        Integer raw = Math.mod(delta, 7);
        return raw < 0 ? raw + 7 : raw;
    }

    /** Inclusive Monday–Friday count. Weekends contribute nothing. */
    public static Integer workingDaysBetween(Date startDate, Date endDate) {
        if (startDate == null || endDate == null || endDate < startDate) return 0;
        Integer n = 0;
        Date d = startDate;
        while (d <= endDate) {
            Integer dow = weekdayIndex(d);
            if (dow != null && dow <= 4) n++;
            d = d.addDays(1);
        }
        return n;
    }

    public static String targetKey(Id aeId, String product, Date periodStart, String metric) {
        return String.valueOf(aeId) + '|'
            + (String.isBlank(product) ? SOLUTION_ALL : product) + '|'
            + String.valueOf(periodStart) + '|'
            + metric;
    }

    /** blended = (n * personal + K * baseline) / (n + K) */
    public static Decimal blend(Decimal personal, Integer n, Decimal baseline) {
        Decimal p = personal == null ? 0 : personal;
        Decimal b = baseline == null ? 0 : baseline;
        Integer sample = n == null ? 0 : n;
        return ((sample * p) + (SHRINKAGE_K * b)) / (sample + SHRINKAGE_K);
    }

    public static String sampleConfidence(Integer n) {
        Integer sample = n == null ? 0 : n;
        if (sample >= CONFIDENCE_HIGH_N) return CONFIDENCE_HIGH;
        if (sample >= CONFIDENCE_MED_N) return CONFIDENCE_MEDIUM;
        return CONFIDENCE_LOW;
    }

    /** ceil(medianDays / 91), minimum 1. A 4-day cycle still lands Q+1. */
    public static Integer landsQuarters(Decimal medianDays) {
        if (medianDays == null || medianDays <= 0) return 1;
        Integer q = Integer.valueOf(Math.ceil(medianDays / QUARTER_DAYS));
        return q < 1 ? 1 : q;
    }

    public static Decimal median(List<Decimal> values) {
        if (values == null || values.isEmpty()) return null;
        List<Decimal> sorted = new List<Decimal>(values);
        sorted.sort();
        Integer mid = sorted.size() / 2;
        if (Math.mod(sorted.size(), 2) == 1) return sorted[mid];
        return (sorted[mid - 1] + sorted[mid]) / 2;
    }

    public static Date windowStart(Date asOf) {
        Date qStart = periodStart(asOf);
        return qStart.addMonths(-3 * TRAILING_QUARTERS);
    }

    public static Date periodStart(Date asOf) {
        return CockpitConstants.quarterStart(asOf.year(), CockpitConstants.quarterOf(asOf));
    }

    public static Date periodEnd(Date asOf) {
        return CockpitConstants.quarterEnd(asOf.year(), CockpitConstants.quarterOf(asOf));
    }

    public static Date shiftPeriod(Date asOf, Integer quarters) {
        return periodStart(asOf).addMonths(3 * quarters);
    }

    public static String periodLabel(Date asOf) {
        return 'Q' + CockpitConstants.quarterOf(asOf) + ' ' + asOf.year();
    }

    public static Decimal clampShare(Decimal share) {
        if (share == null) return null;
        if (share > 1) return 1;
        if (share < 0) return 0;
        return share;
    }

    public static Decimal safeDiv(Decimal num, Decimal den) {
        if (num == null || den == null || den == 0) return null;
        return num / den;
    }

    public static Boolean matchesSize(Decimal arr, String sizeBand) {
        if (String.isBlank(sizeBand) || sizeBand == CockpitConstants.SIZE_ALL) return true;
        Decimal a = arr == null ? 0 : arr;
        if (sizeBand == CockpitConstants.SIZE_UNDER_50K) return a < 50000;
        if (sizeBand == CockpitConstants.SIZE_50_150K) return a >= 50000 && a < 150000;
        if (sizeBand == CockpitConstants.SIZE_OVER_150K) return a >= 150000;
        return true;
    }

    public static Boolean isCompetitiveLoss(String lostReason) {
        return String.isBlank(lostReason) || !EXCLUDED_LOST_REASONS.contains(lostReason);
    }

    public static Boolean isSelfSourced(String source) {
        return String.isNotBlank(source) && SELF_SOURCED.contains(source);
    }

    public static String sizeLabel(String sizeBand) {
        if (sizeBand == CockpitConstants.SIZE_UNDER_50K) return 'Under $50k';
        if (sizeBand == CockpitConstants.SIZE_50_150K) return '$50–150k';
        if (sizeBand == CockpitConstants.SIZE_OVER_150K) return '$150k+';
        return 'All sizes';
    }
}
