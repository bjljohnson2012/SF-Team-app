/**
 * Win Rate Truth: created vs qualified, then won / worked / never-real /
 * ghosted. Win-rate math is SQL-cohort. Ghosted is its own bucket.
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
        @AuraEnabled public Integer qualified = 0;
        @AuraEnabled public Integer won = 0;
        @AuraEnabled public Integer worked = 0;
        @AuraEnabled public Integer neverReal = 0;
        @AuraEnabled public Integer ghosted = 0;
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
        @AuraEnabled public Integer matureQualified = 0;
        @AuraEnabled public Integer matureWon = 0;
        @AuraEnabled public Integer matureWorked = 0;
        @AuraEnabled public Integer matureNeverReal = 0;
        @AuraEnabled public Integer matureGhosted = 0;
        @AuraEnabled public Integer matureClosureWon = 0;
        @AuraEnabled public Integer matureClosureLost = 0;
        @AuraEnabled public Decimal thisQuarterCloseRate;
        @AuraEnabled public Integer thisQuarterWon = 0;
        @AuraEnabled public Integer thisQuarterLost = 0;
        @AuraEnabled public Decimal matchedContestedWR;
        @AuraEnabled public Decimal matchedQualYield;
        @AuraEnabled public Integer matchedQualified = 0;
        @AuraEnabled public Integer matchedCreated = 0;
        @AuraEnabled public Integer matchedWon = 0;
        @AuraEnabled public Integer matchedWorked = 0;
        @AuraEnabled public String matchedLabel;
        @AuraEnabled public String matchedKey;
        @AuraEnabled public String diagnosis;
        @AuraEnabled public Integer cycleLagQuarters;
    }

    public class CloseVintage {
        @AuraEnabled public String cohortKey;
        @AuraEnabled public String label;
        @AuraEnabled public Integer won = 0;
        @AuraEnabled public Integer lost = 0;
        @AuraEnabled public Decimal share;
    }

    public class MeaningSection {
        @AuraEnabled public String title;
        @AuraEnabled public String body;
    }

    public class UnmappedReason {
        @AuraEnabled public String reason;
        @AuraEnabled public Integer count = 0;
    }

    public class WinRatePage {
        @AuraEnabled public List<CohortRow> rows;
        @AuraEnabled public Headline headlines;
        @AuraEnabled public String ghostedConvention;
        @AuraEnabled public List<String> captions;
        @AuraEnabled public String scopeCaption;
        @AuraEnabled public String emptyMessage;
        @AuraEnabled public String directorName;
        @AuraEnabled public Date snapshotAsOf;
        @AuraEnabled public Integer p50Days;
        @AuraEnabled public Integer p75Days;
        @AuraEnabled public String meaning;
        @AuraEnabled public List<MeaningSection> meaningSections;
        @AuraEnabled public List<CloseVintage> closeMix;
        @AuraEnabled public Integer cycleLagQuarters;
        @AuraEnabled public String currentQuarterKey;
        @AuraEnabled public String currentQuarterLabel;
        @AuraEnabled public String matchedCohortKey;
        @AuraEnabled public String matchedCohortLabel;
        @AuraEnabled public String diagnosis;
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
        public Decimal funnelYieldFloor;
        public Decimal funnelDropFloor;
        public Decimal executionContestedFloor;
        public Integer diagnosisMinCreated;
        public Integer diagnosisMinContests;
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
        s.funnelYieldFloor = CockpitConstants.DEFAULT_FUNNEL_YIELD_FLOOR;
        s.funnelDropFloor = CockpitConstants.DEFAULT_FUNNEL_DROP_FLOOR;
        s.executionContestedFloor = CockpitConstants.DEFAULT_EXECUTION_CONTESTED_FLOOR;
        s.diagnosisMinCreated = CockpitConstants.DEFAULT_DIAGNOSIS_MIN_CREATED;
        s.diagnosisMinContests = CockpitConstants.DEFAULT_DIAGNOSIS_MIN_CONTESTS;
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
            } else if (row.Setting_Key__c == CockpitConstants.SETTING_FUNNEL_YIELD_FLOOR) {
                s.funnelYieldFloor = toDec(row.Value__c, s.funnelYieldFloor);
            } else if (row.Setting_Key__c == CockpitConstants.SETTING_FUNNEL_DROP_FLOOR) {
                s.funnelDropFloor = toDec(row.Value__c, s.funnelDropFloor);
            } else if (row.Setting_Key__c == CockpitConstants.SETTING_EXECUTION_CONTESTED_FLOOR) {
                s.executionContestedFloor = toDec(row.Value__c, s.executionContestedFloor);
            }
        }
        cachedSettings = s;
        return s;
    }

    @TestVisible
    static void overrideSettings(Settings s) {
        cachedSettings = s;
    }

    public static WinRatePage buildPage(Filter f) {
        CockpitRosterService.ScopeResult scope = CockpitRosterService.resolveScope(
            f == null ? null : f.directorId,
            f == null ? null : f.teamMode
        );
        String productType = (f == null || String.isBlank(f.productType))
            ? CockpitConstants.PRODUCT_ALL : f.productType;
        String sizeBand = (f == null || String.isBlank(f.sizeBand))
            ? CockpitConstants.SIZE_ALL : f.sizeBand;

        WinRatePage page = new WinRatePage();
        page.directorName = scope.directorName;
        page.scopeCaption = 'Team of ' + scope.directorName
            + ' · ' + CockpitConstants.productGroupLabel(productType)
            + ' · ' + sizeLabel(sizeBand);
        page.emptyMessage = scope.emptyMessage;
        page.rows = new List<CohortRow>();
        page.unmappedReasons = new List<UnmappedReason>();
        page.captions = new List<String>();
        page.headlines = new Headline();
        page.meaningSections = new List<MeaningSection>();
        page.closeMix = new List<CloseVintage>();
        Settings cfg = settings();
        page.excludeGhosted = true;
        page.ghostedConvention =
            'Ghosted is its own bucket — not never-real, and not in contested win rate. '
            + 'Never-real is blank reason, not qualified, duplicate, or insufficient data. '
            + 'Both counts are on the page.';

        Set<Id> owners = scope.ownerIds();
        if (owners.isEmpty()) return page;

        Date floor = Date.newInstance(2023, 1, 1);
        List<Opportunity> opps = queryCohort(owners, floor, productType);
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

        Integer p50 = percentileAt(cycles, 0.50);
        Integer p75 = percentileAt(cycles, 0.75);
        page.p50Days = p50;
        page.p75Days = p75;
        Date today = Date.today();
        String currentKey = cohortKeyOf(today);
        Integer thisWon = 0;
        Integer thisLost = 0;
        Map<String, CloseVintage> mixBySql = new Map<String, CloseVintage>();

        Map<String, CohortRow> byKey = new Map<String, CohortRow>();
        for (Opportunity o : opps) {
            Decimal arr = o.ARR_Opportunity_Amount_USD_Num__c == null
                ? 0 : o.ARR_Opportunity_Amount_USD_Num__c;

            if (o.CreatedDate != null) {
                Date createdOn = o.CreatedDate.date();
                if (createdOn >= floor) {
                    CohortRow opened = rowFor(byKey, createdOn);
                    opened.created++;
                }
            }

            if (o.SQL_Datestamp_bf__c != null && o.SQL_Datestamp_bf__c >= floor) {
                CohortRow row = rowFor(byKey, o.SQL_Datestamp_bf__c);
                row.qualified++;
                row.arrCreated += arr;
                String bucket = classify(o, cfg, unmapped);
                if (bucket == 'OPEN') {
                    row.stillOpen++;
                } else if (bucket == 'WON') {
                    row.won++;
                    row.arrWon += arr;
                } else if (bucket == 'NEVER') {
                    row.neverReal++;
                } else if (bucket == 'GHOSTED') {
                    row.ghosted++;
                } else {
                    row.worked++;
                }
            }

            if (o.IsClosed && o.CloseDate != null) {
                CohortRow closeRow = rowFor(byKey, o.CloseDate);
                if (o.IsWon) closeRow.closureWon++;
                else closeRow.closureLost++;
                if (cohortKeyOf(o.CloseDate) == currentKey) {
                    if (o.IsWon) thisWon++;
                    else thisLost++;
                    String sqlKey = o.SQL_Datestamp_bf__c == null
                        ? CockpitConstants.CLOSE_MIX_UNQUALIFIED
                        : cohortKeyOf(o.SQL_Datestamp_bf__c);
                    CloseVintage cv = mixBySql.get(sqlKey);
                    if (cv == null) {
                        cv = new CloseVintage();
                        cv.cohortKey = sqlKey;
                        cv.label = labelFromKey(sqlKey);
                        mixBySql.put(sqlKey, cv);
                    }
                    if (o.IsWon) cv.won++;
                    else cv.lost++;
                }
            }
        }

        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        Headline h = page.headlines;
        for (Integer i = keys.size() - 1; i >= 0; i--) {
            CohortRow row = byKey.get(keys[i]);
            finishRow(row, p75, today, cfg);
            if (row.created == 0 && row.qualified == 0
                    && row.closureWon == 0 && row.closureLost == 0) continue;
            row.headline = row.mature && !row.thinSample && row.qualified > 0;
            page.rows.add(row);
        }
        Integer hc = 0, hq = 0, hw = 0, hwk = 0, hn = 0, hg = 0, hcw = 0, hcl = 0;
        for (CohortRow row : page.rows) {
            if (!row.mature || row.thinSample || row.qualified == 0) continue;
            hc += row.created;
            hq += row.qualified;
            hw += row.won;
            hwk += row.worked;
            hn += row.neverReal;
            hg += row.ghosted;
            hcw += row.closureWon;
            hcl += row.closureLost;
        }
        h.matureCreated = hc;
        h.matureQualified = hq;
        h.matureWon = hw;
        h.matureWorked = hwk;
        h.matureNeverReal = hn;
        h.matureGhosted = hg;
        h.matureClosureWon = hcw;
        h.matureClosureLost = hcl;
        h.contestedWR = rate(hw, hw + hwk);
        h.qualYield = rate(hq, hc);
        h.closureBased = rate(hcw, hcw + hcl);
        h.distortion = (h.contestedWR == null || h.closureBased == null)
            ? null : h.contestedWR - h.closureBased;

        Integer lag = cycleLagQuarters(p50);
        String matchedKey = cohortKeyOf(CockpitConstants.shiftQuarters(today, -lag));
        String priorKey = cohortKeyOf(CockpitConstants.shiftQuarters(today, -(lag + 1)));
        CohortRow matched = rowByKey(page.rows, matchedKey);
        CohortRow prior = rowByKey(page.rows, priorKey);
        h.thisQuarterWon = thisWon;
        h.thisQuarterLost = thisLost;
        h.thisQuarterCloseRate = rate(thisWon, thisWon + thisLost);
        h.cycleLagQuarters = lag;
        h.matchedKey = matchedKey;
        h.matchedLabel = matched == null ? labelFromKey(matchedKey) : matched.label;
        if (matched != null) {
            h.matchedContestedWR = matched.contestedWR;
            h.matchedQualYield = matched.qualYield;
            h.matchedQualified = matched.qualified;
            h.matchedCreated = matched.created;
            h.matchedWon = matched.won;
            h.matchedWorked = matched.worked;
        }
        h.diagnosis = diagnose(matched, prior, cfg);
        page.cycleLagQuarters = lag;
        page.currentQuarterKey = currentKey;
        page.currentQuarterLabel = labelFromKey(currentKey);
        page.matchedCohortKey = matchedKey;
        page.matchedCohortLabel = h.matchedLabel;
        page.diagnosis = h.diagnosis;
        page.closeMix = mixList(mixBySql, thisWon + thisLost);

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
        page.meaning = meaningOf(page);
        return page;
    }

    public static List<Cockpit_Cohort_Snapshot__c> toSnapshots(Id directorId, WinRatePage page, Date asOf) {
        List<Cockpit_Cohort_Snapshot__c> rows = new List<Cockpit_Cohort_Snapshot__c>();
        if (page == null || page.rows == null) return rows;
        Settings cfg = settings();
        for (CohortRow r : page.rows) {
            if (r.created == 0 && r.qualified == 0
                    && r.closureWon == 0 && r.closureLost == 0) continue;
            Cockpit_Cohort_Snapshot__c s = new Cockpit_Cohort_Snapshot__c();
            s.External_Id__c = String.valueOf(directorId) + '_' + r.cohortKey + '_' + String.valueOf(asOf);
            s.Snapshot_Date__c = asOf;
            s.Director__c = directorId;
            s.Cohort_Key__c = r.cohortKey;
            s.Cohort_Start__c = r.cohortStart;
            s.Cohort_End__c = r.cohortEnd;
            s.Created_Count__c = r.created;
            s.Qualified_Count__c = r.qualified;
            s.Won_Count__c = r.won;
            s.Worked_Loss_Count__c = r.worked;
            s.Never_Real_Count__c = r.neverReal;
            s.Ghosted_Count__c = r.ghosted;
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

    private static List<Opportunity> queryCohort(Set<Id> owners, Date floor, String productType) {
        Set<String> solutions = CockpitConstants.solutionsInProductFilter(productType);
        Datetime createdFloor = Datetime.newInstance(floor, Time.newInstance(0, 0, 0, 0));
        return [
            SELECT Id, OwnerId, CreatedDate, SQL_Datestamp_bf__c, CloseDate, LastActivityDate,
                   IsClosed, IsWon, Lost_Reason__c, ARR_Opportunity_Amount_USD_Num__c,
                   EUNA_Solution__c, StageName, Type
            FROM Opportunity
            WHERE OwnerId IN :owners
              AND RecordType.DeveloperName = :CockpitConstants.SALE_RECORDTYPE
              AND Type IN :CockpitConstants.NEW_BUSINESS_TYPES
              AND StageName NOT IN :CockpitConstants.MIGRATION_STAGES
              AND EUNA_Solution__c IN :solutions
              AND (CreatedDate >= :createdFloor OR SQL_Datestamp_bf__c >= :floor)
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
        if (o.Lost_Reason__c == 'Ghosted') return 'GHOSTED';
        if (String.isBlank(o.Lost_Reason__c)) return 'NEVER';
        LossMap m = lossOf(o.Lost_Reason__c);
        if (!m.mapped) {
            Integer n = unmapped.containsKey(o.Lost_Reason__c) ? unmapped.get(o.Lost_Reason__c) : 0;
            unmapped.put(o.Lost_Reason__c, n + 1);
            return 'WORKED';
        }
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

    private static CohortRow rowFor(Map<String, CohortRow> byKey, Date d) {
        String key = cohortKeyOf(d);
        CohortRow row = byKey.get(key);
        if (row == null) {
            row = newRow(d);
            byKey.put(key, row);
        }
        return row;
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
        Integer resolved = r.won + r.worked + r.neverReal + r.ghosted;
        Integer contested = r.won + r.worked;
        r.cohortConversion = rate(r.won, r.qualified);
        r.resolvedWR = rate(r.won, resolved);
        r.contestedWR = rate(r.won, contested);
        r.qualYield = rate(r.qualified, r.created);
        r.closureBased = rate(r.closureWon, r.closureWon + r.closureLost);
        r.distortion = (r.contestedWR == null || r.closureBased == null)
            ? null : r.contestedWR - r.closureBased;
        Integer lag = p75 == null ? 0 : p75;
        r.mature = r.cohortEnd != null && r.cohortEnd.addDays(lag) < today;
        r.thinSample = r.qualified < cfg.thinSample;
    }

    private static Integer percentileAt(List<Integer> values, Decimal fraction) {
        if (values == null || values.isEmpty()) return 90;
        values.sort();
        Integer idx = (Integer) Math.ceil(values.size() * fraction) - 1;
        if (idx < 0) idx = 0;
        if (idx >= values.size()) idx = values.size() - 1;
        return values[idx];
    }

    @TestVisible
    static Integer cycleLagQuarters(Integer p50Days) {
        Integer days = (p50Days == null || p50Days < 1)
            ? CockpitConstants.DAYS_PER_QUARTER : p50Days;
        Integer lag = (Integer) Math.round((Decimal) days / CockpitConstants.DAYS_PER_QUARTER);
        if (lag < CockpitConstants.CYCLE_LAG_MIN) return CockpitConstants.CYCLE_LAG_MIN;
        if (lag > CockpitConstants.CYCLE_LAG_MAX) return CockpitConstants.CYCLE_LAG_MAX;
        return lag;
    }

    @TestVisible
    static String diagnose(CohortRow matched, CohortRow prior, Settings cfg) {
        Integer minCreated = cfg == null || cfg.diagnosisMinCreated == null
            ? CockpitConstants.DEFAULT_DIAGNOSIS_MIN_CREATED : cfg.diagnosisMinCreated;
        Integer minContests = cfg == null || cfg.diagnosisMinContests == null
            ? CockpitConstants.DEFAULT_DIAGNOSIS_MIN_CONTESTS : cfg.diagnosisMinContests;
        Decimal yieldFloor = cfg == null || cfg.funnelYieldFloor == null
            ? CockpitConstants.DEFAULT_FUNNEL_YIELD_FLOOR : cfg.funnelYieldFloor;
        Decimal dropFloor = cfg == null || cfg.funnelDropFloor == null
            ? CockpitConstants.DEFAULT_FUNNEL_DROP_FLOOR : cfg.funnelDropFloor;
        Decimal contestedFloor = cfg == null || cfg.executionContestedFloor == null
            ? CockpitConstants.DEFAULT_EXECUTION_CONTESTED_FLOOR : cfg.executionContestedFloor;

        Boolean canFunnel = matched != null && matched.created >= minCreated;
        Boolean canExec = matched != null && (matched.won + matched.worked) >= minContests;
        Boolean funnel = false;
        Boolean execution = false;
        if (canFunnel) {
            if (matched.qualYield != null && matched.qualYield < yieldFloor) funnel = true;
            if (prior != null && prior.qualified > 0) {
                Decimal ratio = ((Decimal) matched.qualified).divide(prior.qualified, 4);
                if ((1 - ratio) >= dropFloor) funnel = true;
            }
            if (prior != null && prior.created > 0) {
                Decimal ratio = ((Decimal) matched.created).divide(prior.created, 4);
                if ((1 - ratio) >= dropFloor) funnel = true;
            }
        }
        if (canExec) {
            if (matched.contestedWR != null && matched.contestedWR < contestedFloor) {
                execution = true;
            }
            if (matched.worked >= matched.won) execution = true;
        }
        if (funnel && execution) return CockpitConstants.DIAGNOSIS_BOTH;
        if (funnel) return CockpitConstants.DIAGNOSIS_FUNNEL;
        if (execution) return CockpitConstants.DIAGNOSIS_EXECUTION;
        if (canFunnel && canExec) return CockpitConstants.DIAGNOSIS_HEALTHY;
        return CockpitConstants.DIAGNOSIS_INSUFFICIENT;
    }

    @TestVisible
    static String meaningOf(WinRatePage page) {
        if (page == null) return '';
        if (page.meaningSections == null) page.meaningSections = new List<MeaningSection>();
        page.meaningSections.clear();
        Headline h = page.headlines == null ? new Headline() : page.headlines;
        Integer neverN = 0;
        Integer ghostN = 0;
        if (page.rows != null) {
            for (CohortRow r : page.rows) {
                neverN += r.neverReal;
                ghostN += r.ghosted;
            }
        }
        CohortRow matched = rowByKey(page.rows, page.matchedCohortKey);
        CohortRow prior = rowByKey(
            page.rows,
            page.cycleLagQuarters == null
                ? null
                : cohortKeyOf(CockpitConstants.shiftQuarters(Date.today(), -(page.cycleLagQuarters + 1)))
        );
        CohortRow filling = rowByKey(page.rows, page.currentQuarterKey);
        Integer lag = page.cycleLagQuarters == null ? 1 : page.cycleLagQuarters;
        String currentLabel = String.isBlank(page.currentQuarterLabel)
            ? labelFromKey(cohortKeyOf(Date.today())) : page.currentQuarterLabel;
        String matchedLabel = String.isBlank(page.matchedCohortLabel)
            ? 'the matched SQL vintage' : page.matchedCohortLabel;

        addSection(page, CockpitConstants.MEANING_COHORT,
            'A cohort on this page is a product family plus that family’s own SQL→close cycle. '
            + 'This read is ' + nvl(page.scopeCaption, 'the current filter') + '. '
            + 'Median cycle is ' + String.valueOf(page.p50Days) + ' days (~'
            + String.valueOf(lag) + (lag == 1 ? ' quarter' : ' quarters') + '). '
            + 'Deals closing in ' + currentLabel + ' were typically qualified in '
            + matchedLabel + '. Judge that matched SQL vintage — not the close-date mix '
            + 'of the quarter that is ending.');

        addSection(page, CockpitConstants.MEANING_CLOSING, closingBody(page, h, currentLabel, matchedLabel));
        addSection(page, CockpitConstants.MEANING_FUNNEL, funnelBody(h, matched, prior, filling, currentLabel, matchedLabel));
        addSection(page, CockpitConstants.MEANING_EXECUTION, executionBody(h, matched, matchedLabel));
        addSection(page, CockpitConstants.MEANING_READ, readBody(page.diagnosis, matchedLabel));
        addSection(page, CockpitConstants.MEANING_BUCKETS,
            'Never-real in this filter is ' + neverN
            + ' (blank reason, not qualified, duplicate, insufficient data). Ghosted is '
            + ghostN + '. Ghosted is not never-real and is not in the contested denominator. '
            + 'You need both numbers. Immature vintages stay on the table. Grey rows are still '
            + 'inside this product’s cycle (median ' + String.valueOf(page.p50Days)
            + ' days, three-quarters done by ' + String.valueOf(page.p75Days)
            + ' days) and samples under 15 qualified deals are directional only.');

        List<String> bits = new List<String>();
        for (MeaningSection s : page.meaningSections) {
            bits.add(s.title + '. ' + s.body);
        }
        return String.join(bits, ' ');
    }

    private static String closingBody(WinRatePage page, Headline h, String currentLabel, String matchedLabel) {
        if (h.thisQuarterWon + h.thisQuarterLost == 0) {
            return 'No deals have closed in ' + currentLabel
                + ' yet in this filter. When they do, this section splits them by SQL vintage '
                + 'so the close-date rate is not mistaken for a cohort conversion rate.';
        }
        String mix = mixSentence(page.closeMix);
        return 'This quarter closed ' + h.thisQuarterWon + ' won / ' + h.thisQuarterLost
            + ' lost = ' + pctText(h.thisQuarterCloseRate)
            + ' won/(won+lost). That is a close-date rate, not a conversion rate. ' + mix
            + ' The real win-rate question is how ' + matchedLabel
            + ' (the cycle-matched SQL vintage) is converting.';
    }

    private static String funnelBody(
        Headline h, CohortRow matched, CohortRow prior, CohortRow filling,
        String currentLabel, String matchedLabel
    ) {
        if (matched == null) {
            return 'No SQL vintage exists for ' + matchedLabel
                + ' in this filter, so funnel yield cannot be judged yet. '
                + fillingSentence(filling, currentLabel);
        }
        String body = 'On the matched vintage ' + matchedLabel + ': '
            + matched.created + ' created, ' + matched.qualified + ' qualified'
            + ' (' + pctText(matched.qualYield) + ' qualified / created).';
        if (prior != null && prior.qualified > 0) {
            body += ' The prior vintage ' + prior.label + ' qualified ' + prior.qualified
                + ' — this vintage is ' + deltaText(matched.qualified, prior.qualified) + '.';
        }
        if (matched.qualYield != null && matched.qualYield < CockpitConstants.DEFAULT_FUNNEL_YIELD_FLOOR) {
            body += ' Yield is below ' + pctText(CockpitConstants.DEFAULT_FUNNEL_YIELD_FLOOR)
                + ' — not enough of what we open is becoming real pipeline.';
        } else if (matched.qualYield != null) {
            body += ' Yield on that vintage is holding.';
        }
        return body + ' ' + fillingSentence(filling, currentLabel);
    }

    private static String executionBody(Headline h, CohortRow matched, String matchedLabel) {
        if (matched == null) {
            return 'No matched SQL vintage to judge selling ability against. Contested is won / (won + worked) — Ghosted and never-real stay out of that denominator.';
        }
        Integer contests = matched.won + matched.worked;
        String body = 'On matched ' + matchedLabel + ': ' + matched.won + ' wins against '
            + matched.worked + ' worked losses = ' + pctText(matched.contestedWR)
            + ' contested. Ghosted (' + matched.ghosted + ') and never-real ('
            + matched.neverReal + ') are out of that denominator.';
        if (contests < CockpitConstants.DEFAULT_DIAGNOSIS_MIN_CONTESTS) {
            body += ' Fewer than ' + CockpitConstants.DEFAULT_DIAGNOSIS_MIN_CONTESTS
                + ' real contests — treat execution as directional.';
        } else if (matched.contestedWR != null
                && matched.contestedWR < CockpitConstants.DEFAULT_EXECUTION_CONTESTED_FLOOR) {
            body += ' Contested is below ' + pctText(CockpitConstants.DEFAULT_EXECUTION_CONTESTED_FLOOR)
                + ' — real deals are losing contests.';
        } else {
            body += ' Execution on real contests is holding.';
        }
        return body;
    }

    private static String readBody(String diagnosis, String matchedLabel) {
        if (diagnosis == CockpitConstants.DIAGNOSIS_BOTH) {
            return 'Both. Funnel yield or volume on ' + matchedLabel
                + ' is the constraint, and contested on that same vintage is losing. '
                + 'This is a top-of-funnel problem and a sales-execution problem.';
        }
        if (diagnosis == CockpitConstants.DIAGNOSIS_FUNNEL) {
            return 'Top of funnel. Qualified volume or yield on ' + matchedLabel
                + ' is the constraint. Contested on that vintage is not the leak.';
        }
        if (diagnosis == CockpitConstants.DIAGNOSIS_EXECUTION) {
            return 'Sales execution. Funnel on ' + matchedLabel
                + ' is holding; contested on that vintage is the leak.';
        }
        if (diagnosis == CockpitConstants.DIAGNOSIS_HEALTHY) {
            return 'Neither leak on the matched vintage. Yield and contested on '
                + matchedLabel + ' are both holding — look at mix and immature rows before declaring a problem.';
        }
        return 'Too thin to call. The matched vintage ' + matchedLabel
            + ' does not yet have enough created deals or real contests to separate funnel from execution. Read the table; do not quote a headline.';
    }

    private static String fillingSentence(CohortRow filling, String currentLabel) {
        if (filling == null) {
            return currentLabel + ' has not opened or qualified anything in this filter yet.';
        }
        return currentLabel + ' (still cooking) has opened ' + filling.created
            + ' and qualified ' + filling.qualified + ' so far.';
    }

    private static String mixSentence(List<CloseVintage> mix) {
        if (mix == null || mix.isEmpty()) {
            return 'No SQL-vintage mix yet.';
        }
        List<String> parts = new List<String>();
        for (CloseVintage cv : mix) {
            parts.add(
                cv.label + ' ' + (cv.won + cv.lost) + ' closes ('
                + cv.won + ' won, ' + pctText(cv.share) + ')'
            );
        }
        return 'SQL vintage mix of those closes: ' + String.join(parts, '; ') + '.';
    }

    private static void addSection(WinRatePage page, String title, String body) {
        MeaningSection s = new MeaningSection();
        s.title = title;
        s.body = body;
        page.meaningSections.add(s);
    }

    private static List<CloseVintage> mixList(Map<String, CloseVintage> byKey, Integer total) {
        List<CloseVintage> out = new List<CloseVintage>();
        if (byKey == null) return out;
        out.addAll(byKey.values());
        for (CloseVintage cv : out) {
            cv.share = rate(cv.won + cv.lost, total);
        }
        out.sort(new MixSort());
        return out;
    }

    private static CohortRow rowByKey(List<CohortRow> rows, String key) {
        if (rows == null || String.isBlank(key)) return null;
        for (CohortRow r : rows) {
            if (r.cohortKey == key) return r;
        }
        return null;
    }

    private static String labelFromKey(String key) {
        if (key == CockpitConstants.CLOSE_MIX_UNQUALIFIED) return 'Never SQL’d';
        if (String.isBlank(key) || key.length() < 6) return key;
        return 'Q' + key.substring(5) + ' ' + key.substring(0, 4);
    }

    private static String nvl(String v, String fallback) {
        return String.isBlank(v) ? fallback : v;
    }

    private static String deltaText(Integer nowN, Integer thenN) {
        if (thenN == null || thenN == 0 || nowN == null) return 'uncompared';
        Decimal ratio = ((Decimal) nowN).divide(thenN, 4);
        Decimal change = ratio - 1;
        return ppText(change);
    }

    private static String pctText(Decimal n) {
        if (n == null) return '—';
        return String.valueOf((n * 100).setScale(1)) + '%';
    }
    private static String ppText(Decimal n) {
        if (n == null) return '—';
        Decimal pts = (n * 100).setScale(1);
        return (n > 0 ? '+' : '') + String.valueOf(pts) + ' pts';
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

    private class MixSort implements Comparator<CloseVintage> {
        public Integer compare(CloseVintage a, CloseVintage b) {
            Integer ac = a == null ? 0 : ((a.won == null ? 0 : a.won) + (a.lost == null ? 0 : a.lost));
            Integer bc = b == null ? 0 : ((b.won == null ? 0 : b.won) + (b.lost == null ? 0 : b.lost));
            if (ac == bc) return 0;
            return ac > bc ? -1 : 1;
        }
    }
}