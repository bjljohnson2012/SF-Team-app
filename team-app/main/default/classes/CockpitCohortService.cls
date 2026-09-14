/**
 * SQL-cohort win rates and purge detectors for Win Rate Truth. Cohorts on
 * SQL_Datestamp_bf__c, never CreatedDate. Ghosted follows Euna canon unless
 * winrate.exclude.ghosted says otherwise.
 */
public with sharing class CockpitCohortService {

    public class Filter {
        @AuraEnabled public Id directorId;
        @AuraEnabled public String teamMode;
        @AuraEnabled public String productType;
        @AuraEnabled public String sizeBand;
    }

    public class CohortRow {
        @AuraEnabled public String cohortKey;
        @AuraEnabled public String label;
        @AuraEnabled public Date cohortStart;
        @AuraEnabled public Date cohortEnd;
        @AuraEnabled public Integer created = 0;
        @AuraEnabled public Integer won = 0;
        @AuraEnabled public Integer worked = 0;
        @AuraEnabled public Integer neverReal = 0;
        @AuraEnabled public Integer stillOpen = 0;
        @AuraEnabled public Integer closureWon = 0;
        @AuraEnabled public Integer closureLost = 0;
        @AuraEnabled public Decimal cohortConversion;
        @AuraEnabled public Decimal resolvedWR;
        @AuraEnabled public Decimal contestedWR;
        @AuraEnabled public Decimal qualYield;
        @AuraEnabled public Decimal closureBased;
        @AuraEnabled public Decimal distortion;
        @AuraEnabled public Decimal arrWon = 0;
        @AuraEnabled public Decimal arrCreated = 0;
        @AuraEnabled public Boolean mature = false;
        @AuraEnabled public Boolean thinSample = false;
        @AuraEnabled public Boolean headline = false;
    }

    public class Headline {
        @AuraEnabled public Decimal contestedWR;
        @AuraEnabled public Decimal qualYield;
        @AuraEnabled public Decimal closureBased;
        @AuraEnabled public Decimal distortion;
        @AuraEnabled public Integer matureCreated = 0;
        @AuraEnabled public Integer matureWon = 0;
        @AuraEnabled public Integer matureWorked = 0;
    }

    public class UnmappedReason {
        @AuraEnabled public String reason;
        @AuraEnabled public Integer count = 0;
    }

    public class Page {
        @AuraEnabled public List<CohortRow> rows;
        @AuraEnabled public Headline headlines;
        @AuraEnabled public String ghostedConvention;
        @AuraEnabled public List<String> captions;
        @AuraEnabled public String scopeCaption;
        @AuraEnabled public String emptyMessage;
        @AuraEnabled public String directorName;
        @AuraEnabled public Date snapshotAsOf;
        @AuraEnabled public Integer p75Days;
        @AuraEnabled public Integer purgeSilentCount = 0;
        @AuraEnabled public Integer purgeDumpCount = 0;
        @AuraEnabled public List<UnmappedReason> unmappedReasons;
        @AuraEnabled public Boolean excludeGhosted;
    }

    public class Settings {
        public Boolean excludeGhosted;
        public Integer thinSample;
        public Integer purgeSilentDays;
        public Integer purgeDumpMin;
        public Decimal sizeUnder;
        public Decimal sizeMid;
    }

    private class LossMap {
        public String classification;
        public String root;
        public Boolean mapped;
    }

    private static Settings cachedSettings;
    private static Map<String, LossMap> cachedLoss;

    public static Settings settings() {
        if (cachedSettings != null) return cachedSettings;
        Settings s = new Settings();
        s.excludeGhosted = true;
        s.thinSample = CockpitConstants.DEFAULT_THIN_SAMPLE;
        s.purgeSilentDays = CockpitConstants.DEFAULT_PURGE_SILENT_DAYS;
        s.purgeDumpMin = CockpitConstants.DEFAULT_PURGE_DUMP_MIN;
        s.sizeUnder = CockpitConstants.DEFAULT_SIZE_UNDER;
        s.sizeMid = CockpitConstants.DEFAULT_SIZE_MID;
        for (Cockpit_Setting__mdt row : [
            SELECT Setting_Key__c, Value__c FROM Cockpit_Setting__mdt
        ]) {
            if (row.Setting_Key__c == CockpitConstants.SETTING_EXCLUDE_GHOSTED) {
                s.excludeGhosted = 'true'.equalsIgnoreCase(row.Value__c);
            } else if (row.Setting_Key__c == CockpitConstants.SETTING_THIN_SAMPLE) {
                s.thinSample = toInt(row.Value__c, s.thinSample);
            } else if (row.Setting_Key__c == CockpitConstants.SETTING_PURGE_SILENT_DAYS) {
                s.purgeSilentDays = toInt(row.Value__c, s.purgeSilentDays);
            } else if (row.Setting_Key__c == CockpitConstants.SETTING_PURGE_DUMP_MIN) {
                s.purgeDumpMin = toInt(row.Value__c, s.purgeDumpMin);
            } else if (row.Setting_Key__c == CockpitConstants.SETTING_SIZE_UNDER) {
                s.sizeUnder = toDec(row.Value__c, s.sizeUnder);
            } else if (row.Setting_Key__c == CockpitConstants.SETTING_SIZE_MID) {
                s.sizeMid = toDec(row.Value__c, s.sizeMid);
            }
        }
        cachedSettings = s;
        return s;
    }

    @TestVisible
    static void overrideSettings(Settings s) {
        cachedSettings = s;
    }

    public static Page buildPage(Filter f) {
        CockpitRosterService.ScopeResult scope = CockpitRosterService.resolveScope(
            f == null ? null : f.directorId,
            f == null ? null : f.teamMode
        );
        String productType = (f == null || String.isBlank(f.productType))
            ? CockpitConstants.PRODUCT_ALL : f.productType;
        String sizeBand = (f == null || String.isBlank(f.sizeBand))
            ? CockpitConstants.SIZE_ALL : f.sizeBand;

        Page page = new Page();
        page.directorName = scope.directorName;
        page.scopeCaption = 'Team of ' + scope.directorName
            + ' · ' + productLabel(productType)
            + ' · ' + sizeLabel(sizeBand);
        page.emptyMessage = scope.emptyMessage;
        page.rows = new List<CohortRow>();
        page.unmappedReasons = new List<UnmappedReason>();
        page.captions = new List<String>();
        page.headlines = new Headline();
        Settings cfg = settings();
        page.excludeGhosted = cfg.excludeGhosted;
        page.ghostedConvention = cfg.excludeGhosted
            ? 'Euna canon: Ghosted is never-real and excluded from contested win rate (winrate.exclude.ghosted).'
            : 'Ghosted is kept in the contested denominator (winrate.exclude.ghosted is off).';

        Set<Id> owners = scope.ownerIds();
        if (owners.isEmpty()) return page;

        Date sqlFloor = Date.newInstance(2023, 1, 1);
        List<Opportunity> opps = queryCohort(owners, sqlFloor, productType);
        opps = applySize(opps, sizeBand, cfg);

        Map<String, Integer> unmapped = new Map<String, Integer>();
        List<Integer> cycles = new List<Integer>();
        Boolean sawPre2024 = false;
        Boolean sawUnreliableLoss = false;
        Boolean sawQ32025 = false;
        Map<Id, Map<Date, Integer>> dump = new Map<Id, Map<Date, Integer>>();

        for (Opportunity o : opps) {
            if (o.SQL_Datestamp_bf__c != null && o.SQL_Datestamp_bf__c.year() < 2024) {
                sawPre2024 = true;
            }
            if (o.IsClosed && !o.IsWon && o.CloseDate != null
                    && o.CloseDate < CockpitConstants.LOSS_REASON_RELIABLE_FROM) {
                sawUnreliableLoss = true;
            }
            if (o.IsClosed && o.CloseDate != null
                    && o.CloseDate >= Date.newInstance(2025, 7, 1)
                    && o.CloseDate <= Date.newInstance(2025, 9, 30)) {
                sawQ32025 = true;
            }
            if (o.IsClosed && o.CloseDate != null && o.SQL_Datestamp_bf__c != null) {
                cycles.add(o.SQL_Datestamp_bf__c.daysBetween(o.CloseDate));
            }
            if (isSilentPurge(o, cfg)) page.purgeSilentCount++;
            if (o.IsClosed && !o.IsWon && o.CloseDate != null) {
                if (!dump.containsKey(o.OwnerId)) dump.put(o.OwnerId, new Map<Date, Integer>());
                Map<Date, Integer> byDay = dump.get(o.OwnerId);
                Integer n = byDay.containsKey(o.CloseDate) ? byDay.get(o.CloseDate) : 0;
                byDay.put(o.CloseDate, n + 1);
            }
        }
        for (Map<Date, Integer> byDay : dump.values()) {
            for (Integer n : byDay.values()) {
                if (n >= cfg.purgeDumpMin) page.purgeDumpCount += n;
            }
        }

        Integer p75 = percentile75(cycles);
        page.p75Days = p75;
        Date today = Date.today();

        Map<String, CohortRow> byKey = new Map<String, CohortRow>();
        for (Opportunity o : opps) {
            Date sql = o.SQL_Datestamp_bf__c;
            String key = cohortKeyOf(sql);
            CohortRow row = byKey.get(key);
            if (row == null) {
                row = newRow(sql);
                byKey.put(key, row);
            }
            Decimal arr = o.ARR_Opportunity_Amount_USD_Num__c == null
                ? 0 : o.ARR_Opportunity_Amount_USD_Num__c;
            row.created++;
            row.arrCreated += arr;

            String bucket = classify(o, cfg, unmapped);
            if (bucket == 'OPEN') {
                row.stillOpen++;
            } else if (bucket == 'WON') {
                row.won++;
                row.arrWon += arr;
            } else if (bucket == 'NEVER') {
                row.neverReal++;
            } else {
                row.worked++;
            }

            if (o.IsClosed && o.CloseDate != null) {
                String closeKey = cohortKeyOf(o.CloseDate);
                CohortRow closeRow = byKey.get(closeKey);
                if (closeRow == null) {
                    closeRow = newRow(o.CloseDate);
                    byKey.put(closeKey, closeRow);
                }
                if (o.IsWon) closeRow.closureWon++;
                else closeRow.closureLost++;
            }
        }

        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        Headline h = page.headlines;
        for (Integer i = keys.size() - 1; i >= 0; i--) {
            CohortRow row = byKey.get(keys[i]);
            finishRow(row, p75, today, cfg);
            if (row.created == 0 && row.closureWon == 0 && row.closureLost == 0) continue;
            row.headline = row.mature && !row.thinSample && row.created > 0;
            page.rows.add(row);
        }
        Integer hc = 0, hw = 0, hwk = 0, hcw = 0, hcl = 0;
        for (CohortRow row : page.rows) {
            if (!row.mature || row.thinSample || row.created == 0) continue;
            hc += row.created;
            hw += row.won;
            hwk += row.worked;
            hcw += row.closureWon;
            hcl += row.closureLost;
        }
        h.matureCreated = hc;
        h.matureWon = hw;
        h.matureWorked = hwk;
        h.contestedWR = rate(hw, hw + hwk);
        h.qualYield = rate(hw + hwk, hc);
        h.closureBased = rate(hcw, hcw + hcl);
        h.distortion = (h.contestedWR == null || h.closureBased == null)
            ? null : h.contestedWR - h.closureBased;

        for (String reason : unmapped.keySet()) {
            UnmappedReason u = new UnmappedReason();
            u.reason = reason;
            u.count = unmapped.get(reason);
            page.unmappedReasons.add(u);
        }
        page.unmappedReasons.sort(new UnmappedSort());

        page.captions.add('Loss reasons are unreliable for CloseDate before 2026-02-05.');
        if (sawUnreliableLoss) {
            page.captions.add('This scope includes closes before 2026-02-05 — treat loss buckets as directional.');
        }
        if (sawQ32025) {
            page.captions.add('Q3 2025 cleanup distorted closures in that window.');
        }
        if (sawPre2024) {
            page.captions.add('Pre-2024 SQL datestamps are noisy; those vintages stay visible but are not headlines.');
        }
        page.snapshotAsOf = latestSnapshotDate(scope.directorId);
        return page;
    }

    public static List<Cockpit_Cohort_Snapshot__c> toSnapshots(Id directorId, Page page, Date asOf) {
        List<Cockpit_Cohort_Snapshot__c> rows = new List<Cockpit_Cohort_Snapshot__c>();
        if (page == null || page.rows == null) return rows;
        Settings cfg = settings();
        for (CohortRow r : page.rows) {
            if (r.created == 0 && r.closureWon == 0 && r.closureLost == 0) continue;
            Cockpit_Cohort_Snapshot__c s = new Cockpit_Cohort_Snapshot__c();
            s.External_Id__c = String.valueOf(directorId) + '_' + r.cohortKey + '_' + String.valueOf(asOf);
            s.Snapshot_Date__c = asOf;
            s.Director__c = directorId;
            s.Cohort_Key__c = r.cohortKey;
            s.Cohort_Start__c = r.cohortStart;
            s.Cohort_End__c = r.cohortEnd;
            s.Created_Count__c = r.created;
            s.Won_Count__c = r.won;
            s.Worked_Loss_Count__c = r.worked;
            s.Never_Real_Count__c = r.neverReal;
            s.Still_Open_Count__c = r.stillOpen;
            s.Closure_Won_Count__c = r.closureWon;
            s.Closure_Lost_Count__c = r.closureLost;
            s.Closure_Based_Rate__c = r.closureBased;
            s.Cohort_Conversion_Rate__c = r.cohortConversion;
            s.Resolved_Win_Rate__c = r.resolvedWR;
            s.Contested_Win_Rate__c = r.contestedWR;
            s.Qualification_Yield__c = r.qualYield;
            s.Distortion__c = r.distortion;
            s.ARR_Won__c = r.arrWon;
            s.ARR_Created__c = r.arrCreated;
            s.Mature__c = r.mature;
            s.Thin_Sample__c = r.thinSample;
            s.P75_Cycle_Days__c = page.p75Days;
            s.Purge_Silent_Count__c = page.purgeSilentCount;
            s.Purge_Dump_Count__c = page.purgeDumpCount;
            s.Ghosted_Excluded__c = cfg.excludeGhosted;
            s.Unmapped_Reasons__c = joinUnmapped(page.unmappedReasons);
            rows.add(s);
        }
        return rows;
    }

    public static String classifyForTest(Opportunity o) {
        return classify(o, settings(), new Map<String, Integer>());
    }

    public static Decimal rate(Integer num, Integer den) {
        if (den == null || den == 0) return null;
        return ((Decimal) num).divide(den, 4);
    }

    public static String cohortKeyOf(Date d) {
        return d.year() + 'Q' + CockpitConstants.quarterOf(d);
    }

    public static Boolean isSilentPurge(Opportunity o, Settings cfg) {
        if (o == null || !o.IsClosed || o.IsWon || o.CloseDate == null) return false;
        if (o.LastActivityDate == null) return true;
        return o.LastActivityDate.daysBetween(o.CloseDate) > cfg.purgeSilentDays;
    }

    private static List<Opportunity> queryCohort(Set<Id> owners, Date sqlFloor, String productType) {
        if (productType != CockpitConstants.PRODUCT_ALL) {
            return [
                SELECT Id, OwnerId, SQL_Datestamp_bf__c, CloseDate, LastActivityDate,
                       IsClosed, IsWon, Lost_Reason__c, ARR_Opportunity_Amount_USD_Num__c,
                       EUNA_Solution__c, StageName, Type
                FROM Opportunity
                WHERE OwnerId IN :owners
                  AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
                  AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
                  AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
                  AND SQL_Datestamp_bf__c != null
                  AND SQL_Datestamp_bf__c >= :sqlFloor
                  AND EUNA_Solution__c = :productType
                WITH USER_MODE
            ];
        }
        return [
            SELECT Id, OwnerId, SQL_Datestamp_bf__c, CloseDate, LastActivityDate,
                   IsClosed, IsWon, Lost_Reason__c, ARR_Opportunity_Amount_USD_Num__c,
                   EUNA_Solution__c, StageName, Type
            FROM Opportunity
            WHERE OwnerId IN :owners
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
              AND SQL_Datestamp_bf__c != null
              AND SQL_Datestamp_bf__c >= :sqlFloor
            WITH USER_MODE
        ];
    }

    private static List<Opportunity> applySize(List<Opportunity> opps, String sizeBand, Settings cfg) {
        if (sizeBand == CockpitConstants.SIZE_ALL) return opps;
        List<Opportunity> keep = new List<Opportunity>();
        for (Opportunity o : opps) {
            Decimal arr = o.ARR_Opportunity_Amount_USD_Num__c == null
                ? 0 : o.ARR_Opportunity_Amount_USD_Num__c;
            if (sizeBand == CockpitConstants.SIZE_UNDER_50K && arr < cfg.sizeUnder) keep.add(o);
            else if (sizeBand == CockpitConstants.SIZE_50_150K
                    && arr >= cfg.sizeUnder && arr < cfg.sizeMid) keep.add(o);
            else if (sizeBand == CockpitConstants.SIZE_OVER_150K && arr >= cfg.sizeMid) keep.add(o);
        }
        return keep;
    }

    private static String classify(Opportunity o, Settings cfg, Map<String, Integer> unmapped) {
        if (!o.IsClosed) return 'OPEN';
        if (o.IsWon) return 'WON';
        if (String.isBlank(o.Lost_Reason__c)) return 'NEVER';
        LossMap m = lossOf(o.Lost_Reason__c);
        if (!m.mapped) {
            Integer n = unmapped.containsKey(o.Lost_Reason__c) ? unmapped.get(o.Lost_Reason__c) : 0;
            unmapped.put(o.Lost_Reason__c, n + 1);
            return 'WORKED';
        }
        if (o.Lost_Reason__c == 'Ghosted' && !cfg.excludeGhosted) return 'WORKED';
        return m.classification == 'Never_Real' ? 'NEVER' : 'WORKED';
    }

    private static LossMap lossOf(String reason) {
        Map<String, LossMap> all = lossMaps();
        if (all.containsKey(reason)) return all.get(reason);
        LossMap m = new LossMap();
        m.mapped = false;
        m.classification = 'Worked';
        m.root = 'UNMAPPED';
        return m;
    }

    private static Map<String, LossMap> lossMaps() {
        if (cachedLoss != null) return cachedLoss;
        cachedLoss = new Map<String, LossMap>();
        for (Cockpit_Loss_Root__mdt row : [
            SELECT Lost_Reason__c, Classification__c, Root_Cause__c, Active__c
            FROM Cockpit_Loss_Root__mdt
        ]) {
            if (row.Active__c == false) continue;
            LossMap m = new LossMap();
            m.mapped = true;
            m.classification = row.Classification__c;
            m.root = row.Root_Cause__c;
            cachedLoss.put(row.Lost_Reason__c, m);
        }
        return cachedLoss;
    }

    private static CohortRow newRow(Date d) {
        CohortRow r = new CohortRow();
        Integer y = d.year();
        Integer q = CockpitConstants.quarterOf(d);
        r.cohortKey = y + 'Q' + q;
        r.label = 'Q' + q + ' ' + y;
        r.cohortStart = CockpitConstants.quarterStart(y, q);
        r.cohortEnd = CockpitConstants.quarterEnd(y, q);
        return r;
    }

    private static void finishRow(CohortRow r, Integer p75, Date today, Settings cfg) {
        Integer resolved = r.won + r.worked + r.neverReal;
        Integer contested = r.won + r.worked;
        r.cohortConversion = rate(r.won, r.created);
        r.resolvedWR = rate(r.won, resolved);
        r.contestedWR = rate(r.won, contested);
        r.qualYield = rate(contested, r.created);
        r.closureBased = rate(r.closureWon, r.closureWon + r.closureLost);
        r.distortion = (r.contestedWR == null || r.closureBased == null)
            ? null : r.contestedWR - r.closureBased;
        Integer lag = p75 == null ? 0 : p75;
        r.mature = r.cohortEnd != null && r.cohortEnd.addDays(lag) < today;
        r.thinSample = r.created < cfg.thinSample;
    }

    private static Integer percentile75(List<Integer> values) {
        if (values == null || values.isEmpty()) return 90;
        values.sort();
        Integer idx = (Integer) Math.ceil(values.size() * 0.75) - 1;
        if (idx < 0) idx = 0;
        if (idx >= values.size()) idx = values.size() - 1;
        return values[idx];
    }

    private static Date latestSnapshotDate(Id directorId) {
        try {
            List<Cockpit_Cohort_Snapshot__c> rows = [
                SELECT Snapshot_Date__c
                FROM Cockpit_Cohort_Snapshot__c
                WHERE Director__c = :directorId
                ORDER BY Snapshot_Date__c DESC
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0].Snapshot_Date__c;
        } catch (Exception e) {
            return null;
        }
    }

    private static String joinUnmapped(List<UnmappedReason> rows) {
        if (rows == null || rows.isEmpty()) return null;
        List<String> bits = new List<String>();
        for (UnmappedReason u : rows) bits.add(u.reason + ' (' + u.count + ')');
        return String.join(bits, '; ').left(2000);
    }

    private static String productLabel(String productType) {
        return productType == CockpitConstants.PRODUCT_ALL ? 'All products' : productType;
    }

    public static String sizeLabel(String sizeBand) {
        if (sizeBand == CockpitConstants.SIZE_UNDER_50K) return 'Under $50k';
        if (sizeBand == CockpitConstants.SIZE_50_150K) return '$50–150k';
        if (sizeBand == CockpitConstants.SIZE_OVER_150K) return '$150k+';
        return 'All sizes';
    }

    private static Integer toInt(String v, Integer fallback) {
        try { return Integer.valueOf(v); } catch (Exception e) { return fallback; }
    }
    private static Decimal toDec(String v, Decimal fallback) {
        try { return Decimal.valueOf(v); } catch (Exception e) { return fallback; }
    }

    private class UnmappedSort implements Comparator<UnmappedReason> {
        public Integer compare(UnmappedReason a, UnmappedReason b) {
            Integer ac = a == null || a.count == null ? 0 : a.count;
            Integer bc = b == null || b.count == null ? 0 : b.count;
            if (ac == bc) return 0;
            return ac > bc ? -1 : 1;
        }
    }
}
