/**
 * Pure Pipeline Review engine: history parse, parked detection, grade,
 * contact pick, and priority. No SOQL, DML, callouts, or Date.today() —
 * the caller passes today and every queried input.
 */
public with sharing class PipelineReviewGradeService {
    public class HistoryEntry {
        public Date entryDate;
        public Integer ageDays;
        public String text;
    }

    public class TitlePattern {
        public String category;
        public String pattern;
    }

    public class ContactCandidate {
        public Id contactId;
        public Id opportunityId;
        public String name;
        public String title;
        public String email;
        public Boolean isPrimary;
        public String role;
        public Integer daysSinceActivity;
        public Integer inboundReplyAgeDays;
        public Boolean bounced;
        public Boolean inActiveCadence;
    }

    public class ContactPick {
        public Id contactId;
        public String reason;
        public Integer score;
        public List<ContactPick> alternates;
    }

    public class WeightConfig {
        public Decimal wV;
        public Decimal wU;
        public Decimal wS;
        public Decimal wR;
        public Integer focusCapWeek;
        public Integer focusCapToday;
        public Decimal carryoverBoost;
    }

    public class PrioritySignals {
        public Boolean meetingToday;
        public Boolean inbound24h;
        public Boolean inbound48h;
        public Boolean stepDoneYesterdayNoNew;
    }

    public class GradeInput {
        public Id opportunityId;
        public String stageName;
        public Date closeDate;
        public String forecastCategoryName;
        public String directorForecast;
        public String rollupForecast;
        public String nextStep;
        public Date nextStepDate;
        public String directorNote;
        public Date lastActivityDate;
        public Decimal arr;
        public String pricingApproval;
        public Boolean forecastWeekLocked;
        public List<HistoryEntry> history;
        public List<ContactCandidate> contacts;
        public List<TitlePattern> titlePatterns;
    }

    public class GradeResult {
        public String pipelineGrade;
        public String recommendedForecast;
        public String rationale;
        public String inputHash;
        public Integer parkedCycles;
        public Integer freshestAge;
        public Boolean dateConflict;
        public Boolean forecastMismatch;
        public String nextStepState;
        public Decimal actionPriority;
        public String actionPriorityReason;
        public String actionBucket;
        public Id recommendedContactId;
        public String recommendedContactReason;
        public List<ContactPick> alternateContacts;
        public Decimal valueScore;
        public Decimal urgencyWeek;
        public Decimal urgencyToday;
        public Decimal leverageScore;
        public Decimal decayScore;
        public Decimal actionability;
    }

    public class ReplyMatch {
        public Map<Id, Map<String, String>> matched = new Map<Id, Map<String, String>>();
        public Set<Id> missing = new Set<Id>();
        public Integer rejected = 0;
    }

    public class BucketRow {
        public Id opportunityId;
        public Decimal priority;
        public String naturalBucket;
    }

    private static final Pattern HISTORY_MARK =
        Pattern.compile('(\\d{1,2})/(\\d{1,2})/(\\d{4})\\s*:\\s*');
    private static final Pattern NOTE_PREFIX =
        Pattern.compile('^\\s*(\\d{1,2})/(\\d{1,2})');
    private static final Pattern DATE_TOKEN =
        Pattern.compile('(?i)\\b\\d{1,2}/\\d{1,2}(/\\d{2,4})?\\b');
    private static final Pattern MONTH_DAY =
        Pattern.compile('(?i)\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?\\s*\\d{1,2}\\b');
    private static final Pattern NOTE_SHAPE =
        Pattern.compile('^\\d{1,2}/\\d{1,2}\\s*-.*');
    private static final Pattern ERROR_ISH =
        Pattern.compile('(?i)tool call failed|unavailable|timed out|artifact is no longer shown');

    public static List<HistoryEntry> parseHistory(String rich, Date today) {
        List<HistoryEntry> out = new List<HistoryEntry>();
        if (String.isBlank(rich) || today == null) return out;
        String flat = flattenRich(rich);
        if (String.isBlank(flat)) return out;
        Matcher m = HISTORY_MARK.matcher(flat);
        List<Integer> starts = new List<Integer>();
        List<Integer> ends = new List<Integer>();
        List<Date> dates = new List<Date>();
        while (m.find()) {
            Date d = safeDate(m.group(3), m.group(1), m.group(2));
            if (d == null) continue;
            starts.add(m.start());
            ends.add(m.end());
            dates.add(d);
        }
        Integer n = dates.size();
        for (Integer i = 0; i < n; i++) {
            Integer textStart = ends[i];
            Integer textEnd = (i + 1 < n) ? starts[i + 1] : flat.length();
            String text = textStart < textEnd ? flat.substring(textStart, textEnd).trim() : '';
            if (String.isBlank(text)) continue;
            HistoryEntry e = new HistoryEntry();
            e.entryDate = dates[i];
            e.ageDays = dates[i].daysBetween(today);
            e.text = text;
            out.add(e);
        }
        out.sort(new HistoryNewestFirst());
        return out;
    }

    public static String ageBand(Integer days) {
        if (days == null) return PipelineReviewConstants.BAND_UNKNOWN;
        if (days <= 7) return PipelineReviewConstants.BAND_CURRENT;
        if (days <= 21) return PipelineReviewConstants.BAND_RECENT;
        if (days <= 45) return PipelineReviewConstants.BAND_AGING;
        return PipelineReviewConstants.BAND_HISTORY;
    }

    public static Decimal similarity(String a, String b) {
        Set<String> ta = tokens(a);
        Set<String> tb = tokens(b);
        if (ta.isEmpty() || tb.isEmpty()) return 0;
        Set<String> inter = new Set<String>(ta);
        inter.retainAll(tb);
        Set<String> uni = new Set<String>(ta);
        uni.addAll(tb);
        return Decimal.valueOf(inter.size()) / Decimal.valueOf(uni.size());
    }

    public static Integer parkedRuns(List<HistoryEntry> entries) {
        return parkedRuns(entries, PipelineReviewConstants.PARKED_SIMILARITY);
    }

    public static Integer parkedRuns(List<HistoryEntry> entries, Decimal threshold) {
        if (entries == null || entries.size() < 2) return 0;
        Decimal t = threshold == null ? PipelineReviewConstants.PARKED_SIMILARITY : threshold;
        Integer count = 0;
        for (Integer i = 0; i < entries.size() - 1; i++) {
            Decimal s = similarity(entries[i].text, entries[i + 1].text);
            if (s >= t) count++;
            else break;
        }
        return count;
    }

    public static GradeResult grade(GradeInput input, Date today, WeightConfig weights, Decimal maxTeamArr) {
        GradeResult r = new GradeResult();
        if (input == null || today == null) return r;
        List<HistoryEntry> history = input.history == null ? new List<HistoryEntry>() : input.history;
        Integer parked = parkedRuns(history);
        Integer noteAge = noteAgeDays(input.directorNote, today);
        Integer nextAge = input.nextStepDate == null ? null : input.nextStepDate.daysBetween(today);
        Boolean nextMissing = String.isBlank(input.nextStep);
        Boolean nextPastDue = input.nextStepDate != null && input.nextStepDate < today;
        Integer lastActAge = input.lastActivityDate == null ? null : input.lastActivityDate.daysBetween(today);
        Integer freshest = minAge(minAge(noteAge, lastActAge), newestHistoryAge(history));
        Boolean dateConflict = input.nextStepDate != null && input.closeDate != null
            && input.nextStepDate > input.closeDate;
        Boolean riskHeavy = parked >= 2 || (freshest != null && freshest > 30) || nextMissing;

        String rec = recommendForecast(
            input.stageName, freshest, nextMissing, parked, dateConflict, riskHeavy,
            input.forecastCategoryName
        );
        String rationale = recommendRationale(
            input.stageName, freshest, nextMissing, parked, dateConflict, riskHeavy,
            input.forecastCategoryName, rec
        );
        String ae = PipelineReviewConstants.normalizeForecast(input.forecastCategoryName);
        String dir = PipelineReviewConstants.normalizeForecast(input.directorForecast);
        String roll = PipelineReviewConstants.normalizeForecast(input.rollupForecast);
        Boolean mismatch = forecastsDisagree(new List<String>{ ae, dir, roll, rec });

        r.recommendedForecast = rec;
        r.rationale = rationale;
        r.pipelineGrade = letterGrade(rec, riskHeavy);
        r.parkedCycles = parked;
        r.freshestAge = freshest;
        r.dateConflict = dateConflict;
        r.forecastMismatch = mismatch;
        r.nextStepState = nextStepState(nextMissing, nextPastDue, parked);
        r.inputHash = inputHash(input, history);
        r.actionBucket = naturalBucket(
            input.contacts, input.pricingApproval, nextMissing, input.nextStepDate, nextAge
        );

        ContactPick pick = pickContact(input.contacts, input.opportunityId, input.stageName, input.titlePatterns);
        if (pick != null) {
            r.recommendedContactId = pick.contactId;
            r.recommendedContactReason = pick.reason;
            r.alternateContacts = pick.alternates;
        }

        fillPriority(r, input, today, weights, maxTeamArr, null, nextAge, parked, freshest, nextMissing);
        return r;
    }

    public static void fillPriority(
        GradeResult r,
        GradeInput input,
        Date today,
        WeightConfig weights,
        Decimal maxTeamArr,
        PrioritySignals live,
        Integer nextAge,
        Integer parked,
        Integer freshest,
        Boolean nextMissing
    ) {
        WeightConfig w = weights == null ? defaultWeights() : weights;
        Decimal value = valueScore(input == null ? null : input.arr, maxTeamArr);
        Decimal urgW = urgencyWeek(nextAge);
        Decimal urgT = urgencyToday(nextAge, live);
        Decimal closeMul = closeDateMultiplier(input == null ? null : input.closeDate, today);
        urgW = cap01(urgW * closeMul);
        urgT = cap01(urgT * closeMul);
        Decimal lev = leverageScore(input);
        Decimal decay = decayScore(parked, freshest, r == null ? false : r.forecastMismatch);
        Decimal act = actionabilityScore(input);
        Decimal week = priorityFrom(w, value, urgW, lev, decay, act);
        r.valueScore = value;
        r.urgencyWeek = urgW;
        r.urgencyToday = urgT;
        r.leverageScore = lev;
        r.decayScore = decay;
        r.actionability = act;
        r.actionPriority = week;
        r.actionPriorityReason = reasonText(value, urgW, lev, decay, act, input, nextAge, parked, freshest);
    }

    public static Decimal scorePriorityToday(
        GradeResult stored,
        PrioritySignals live,
        WeightConfig weights,
        Decimal maxTeamArr,
        Decimal arr,
        Date closeDate,
        Date today
    ) {
        WeightConfig w = weights == null ? defaultWeights() : weights;
        Decimal value = stored != null && stored.valueScore != null
            ? stored.valueScore
            : valueScore(arr, maxTeamArr);
        Integer nextAge = null;
        Decimal urgT = stored == null ? urgencyToday(null, live) : stored.urgencyToday;
        if (live != null) {
            urgT = urgencyToday(nextAgeFromReason(stored), live);
        }
        Decimal closeMul = closeDateMultiplier(closeDate, today);
        urgT = cap01((urgT == null ? 0.4 : urgT) * closeMul);
        Decimal lev = stored == null || stored.leverageScore == null ? 0.3 : stored.leverageScore;
        Decimal decay = stored == null || stored.decayScore == null ? 0.1 : stored.decayScore;
        Decimal act = stored == null || stored.actionability == null ? 0.5 : stored.actionability;
        return priorityFrom(w, value, urgT, lev, decay, act);
    }

    public static String naturalBucket(
        List<ContactCandidate> contacts,
        String pricingApproval,
        Boolean nextMissing,
        Date nextStepDate,
        Integer nextAge
    ) {
        Boolean noContact = contacts == null || contacts.isEmpty();
        Boolean noEmail = true;
        if (contacts != null) {
            for (ContactCandidate c : contacts) {
                if (c != null && String.isNotBlank(c.email)) {
                    noEmail = false;
                    break;
                }
            }
        }
        Boolean pricingPending = String.isNotBlank(pricingApproval)
            && pricingApproval.toLowerCase().contains('pend');
        if (noContact || noEmail || pricingPending || nextStepDate == null || nextMissing == true) {
            return PipelineReviewConstants.BUCKET_FIX;
        }
        if (nextAge != null && nextAge > 60) return PipelineReviewConstants.BUCKET_KILL;
        if (nextAge != null && nextAge >= -7 && nextAge <= 7) return PipelineReviewConstants.BUCKET_DUE;
        return PipelineReviewConstants.BUCKET_NONE;
    }

    public static Map<Id, String> assignBuckets(List<BucketRow> rows, Integer focusCap) {
        Map<Id, String> out = new Map<Id, String>();
        if (rows == null) return out;
        Integer cap = focusCap == null ? PipelineReviewConstants.DEFAULT_FOCUS_CAP_WEEK : focusCap;
        List<BucketRow> candidates = new List<BucketRow>();
        for (BucketRow row : rows) {
            if (row == null || row.opportunityId == null) continue;
            String nat = String.isBlank(row.naturalBucket)
                ? PipelineReviewConstants.BUCKET_NONE
                : row.naturalBucket;
            if (nat == PipelineReviewConstants.BUCKET_FIX || nat == PipelineReviewConstants.BUCKET_KILL) {
                out.put(row.opportunityId, nat);
            } else {
                candidates.add(row);
            }
        }
        candidates.sort(new BucketPriorityDesc());
        Integer i = 0;
        for (BucketRow row : candidates) {
            if (i < cap) {
                out.put(row.opportunityId, PipelineReviewConstants.BUCKET_FOCUS);
            } else if (row.naturalBucket == PipelineReviewConstants.BUCKET_DUE) {
                out.put(row.opportunityId, PipelineReviewConstants.BUCKET_DUE);
            } else {
                out.put(row.opportunityId, PipelineReviewConstants.BUCKET_NONE);
            }
            i++;
        }
        return out;
    }

    public static ContactPick pickContact(
        List<ContactCandidate> contacts,
        Id opportunityId,
        String stageName,
        List<TitlePattern> patterns
    ) {
        if (contacts == null || contacts.isEmpty()) return null;
        List<ContactPick> scored = new List<ContactPick>();
        for (ContactCandidate c : contacts) {
            if (c == null || c.contactId == null) continue;
            if (opportunityId != null && c.opportunityId != null && c.opportunityId != opportunityId) continue;
            ContactPick p = new ContactPick();
            p.contactId = c.contactId;
            p.score = scoreContact(c, stageName, patterns);
            p.reason = contactReason(c);
            scored.add(p);
        }
        if (scored.isEmpty()) return null;
        scored.sort(new ContactScoreDesc());
        ContactPick top = scored[0];
        top.alternates = new List<ContactPick>();
        for (Integer i = 1; i < scored.size() && top.alternates.size() < 2; i++) {
            top.alternates.add(scored[i]);
        }
        return top;
    }

    public static Integer scoreContact(ContactCandidate c, String stage, List<TitlePattern> patterns) {
        if (c == null) return -1000;
        Integer score = 0;
        if (c.inboundReplyAgeDays != null) {
            if (c.inboundReplyAgeDays <= 14) score += 40;
            else if (c.inboundReplyAgeDays <= 30) score += 30;
            else if (c.inboundReplyAgeDays <= 60) score += 20;
        }
        if (c.isPrimary == true) score += 20;
        if (String.isNotBlank(c.role) && PipelineReviewConstants.DECISION_ROLES.contains(c.role)) {
            score += 15;
        }
        String cat = matchTitleCategory(c.title, patterns);
        if (cat != null) score += 10;
        Boolean late = stage != null && PipelineReviewConstants.LATE_STAGES.contains(stage);
        Boolean early = stage != null && PipelineReviewConstants.EARLY_STAGES.contains(stage);
        if (late && cat == PipelineReviewConstants.TITLE_EB) score += 8;
        if (early && cat == PipelineReviewConstants.TITLE_PRAC) score += 8;
        if (c.daysSinceActivity != null) {
            if (c.daysSinceActivity <= 7) score += 15;
            else if (c.daysSinceActivity <= 30) score += 10;
            else if (c.daysSinceActivity <= 90) score += 5;
        }
        if (String.isBlank(c.email)) score -= 25;
        if (c.bounced == true) score -= 30;
        if (c.inActiveCadence == true) score -= 15;
        return score;
    }

    public static List<List<Id>> chunk(List<Id> ids, Integer size) {
        List<List<Id>> out = new List<List<Id>>();
        if (ids == null || ids.isEmpty()) return out;
        Integer n = size == null || size < 1 ? 50 : size;
        List<Id> cur = new List<Id>();
        for (Id i : ids) {
            cur.add(i);
            if (cur.size() == n) {
                out.add(cur);
                cur = new List<Id>();
            }
        }
        if (!cur.isEmpty()) out.add(cur);
        return out;
    }

    public static ReplyMatch matchReply(List<Id> requested, String rawJson) {
        ReplyMatch r = new ReplyMatch();
        Set<Id> want = new Set<Id>();
        if (requested != null) want.addAll(requested);
        r.missing.addAll(want);
        if (String.isBlank(rawJson) || want.isEmpty()) return r;
        List<Object> rows;
        try {
            Object parsed = JSON.deserializeUntyped(rawJson.trim());
            if (parsed instanceof List<Object>) {
                rows = (List<Object>) parsed;
            } else {
                return r;
            }
        } catch (Exception e) {
            return r;
        }
        Set<Id> seen = new Set<Id>();
        for (Object row : rows) {
            if (!(row instanceof Map<String, Object>)) continue;
            Map<String, Object> m = (Map<String, Object>) row;
            String idStr = m.containsKey('id') ? String.valueOf(m.get('id')) : null;
            Id rid;
            try {
                rid = String.isBlank(idStr) ? null : (Id) idStr;
            } catch (Exception e) {
                r.rejected++;
                continue;
            }
            if (rid == null || !want.contains(rid)) {
                r.rejected++;
                continue;
            }
            if (seen.contains(rid)) {
                r.rejected++;
                continue;
            }
            String forecast = m.containsKey('forecast') ? String.valueOf(m.get('forecast')) : null;
            if (String.isNotBlank(forecast) && !PipelineReviewConstants.isLegalForecast(forecast)) {
                r.rejected++;
                continue;
            }
            Map<String, String> payload = new Map<String, String>();
            if (m.containsKey('note')) payload.put('note', String.valueOf(m.get('note')));
            if (m.containsKey('nextStep')) payload.put('nextStep', String.valueOf(m.get('nextStep')));
            if (m.containsKey('nextStepDate')) payload.put('nextStepDate', String.valueOf(m.get('nextStepDate')));
            if (String.isNotBlank(forecast)) {
                payload.put('forecast', PipelineReviewConstants.normalizeForecast(forecast));
            }
            seen.add(rid);
            r.matched.put(rid, payload);
            r.missing.remove(rid);
        }
        return r;
    }

    public static Boolean isValidNote(String s) {
        if (String.isBlank(s) || s.length() < 40) return false;
        if (s.length() > PipelineReviewConstants.NOTE_MAX_CHARS) return false;
        if (!NOTE_SHAPE.matcher(s).matches()) return false;
        if (ERROR_ISH.matcher(s).find()) return false;
        return true;
    }

    public static String inputHash(GradeInput input, List<HistoryEntry> history) {
        String newest = '';
        if (history != null && !history.isEmpty()) newest = String.valueOf(history[0].text);
        String raw = String.valueOf(input.stageName) + '|'
            + String.valueOf(input.closeDate) + '|'
            + String.valueOf(input.forecastCategoryName) + '|'
            + String.valueOf(input.nextStep) + '|'
            + String.valueOf(input.nextStepDate) + '|'
            + String.valueOf(input.lastActivityDate) + '|'
            + newest + '|'
            + String.valueOf(input.arr);
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(raw))).left(64);
    }

    public static WeightConfig defaultWeights() {
        WeightConfig w = new WeightConfig();
        w.wV = 0.30;
        w.wU = 0.30;
        w.wS = 0.25;
        w.wR = 0.15;
        w.focusCapWeek = PipelineReviewConstants.DEFAULT_FOCUS_CAP_WEEK;
        w.focusCapToday = PipelineReviewConstants.DEFAULT_FOCUS_CAP_TODAY;
        w.carryoverBoost = PipelineReviewConstants.DEFAULT_CARRYOVER;
        return w;
    }

    public static String flattenRich(String rich) {
        String s = rich.replaceAll('(?i)<br\\s*/?>', ' ');
        s = s.replaceAll('(?i)</p>', ' ');
        s = s.replaceAll('<[^>]+>', ' ');
        s = s.replace('&nbsp;', ' ');
        s = s.replace('&#39;', '\'');
        s = s.replace('&quot;', '"');
        s = s.replace('&lt;', '<');
        s = s.replace('&gt;', '>');
        s = s.replace('&amp;', '&');
        s = s.replaceAll('\\s+', ' ').trim();
        return s;
    }

    @TestVisible
    static Date safeDate(String y, String mo, String d) {
        try {
            return Date.newInstance(Integer.valueOf(y), Integer.valueOf(mo), Integer.valueOf(d));
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    static Set<String> tokens(String raw) {
        Set<String> out = new Set<String>();
        if (String.isBlank(raw)) return out;
        String s = raw.toLowerCase();
        s = DATE_TOKEN.matcher(s).replaceAll(' ');
        s = MONTH_DAY.matcher(s).replaceAll(' ');
        s = s.replaceAll('[^a-z ]', ' ');
        for (String part : s.split('\\s+')) {
            if (part != null && part.length() > 3) out.add(part);
        }
        return out;
    }

    @TestVisible
    static Integer noteAgeDays(String note, Date today) {
        if (String.isBlank(note) || today == null) return null;
        Matcher m = NOTE_PREFIX.matcher(note);
        if (!m.find()) return null;
        Integer year = today.year();
        Date d = safeDate(String.valueOf(year), m.group(1), m.group(2));
        if (d == null) return null;
        if (d > today.addDays(7)) {
            d = safeDate(String.valueOf(year - 1), m.group(1), m.group(2));
        }
        return d == null ? null : d.daysBetween(today);
    }

    static Integer newestHistoryAge(List<HistoryEntry> history) {
        if (history == null || history.isEmpty()) return null;
        return history[0].ageDays;
    }

    static Integer minAge(Integer a, Integer b) {
        if (a == null) return b;
        if (b == null) return a;
        return a < b ? a : b;
    }

    @TestVisible
    static String recommendForecast(
        String stage,
        Integer freshestAge,
        Boolean nextMissing,
        Integer parked,
        Boolean dateConflict,
        Boolean riskHeavy,
        String aeForecast
    ) {
        Boolean early = stage != null && PipelineReviewConstants.EARLY_STAGES.contains(stage);
        String ae = PipelineReviewConstants.normalizeForecast(aeForecast);
        if (ae == null) ae = PipelineReviewConstants.FC_PIPE;
        if (freshestAge != null && freshestAge > 60 && early) return PipelineReviewConstants.FC_OMITTED;
        if (nextMissing == true && freshestAge != null && freshestAge > 30) return PipelineReviewConstants.FC_PIPE;
        String rec = ae;
        if (parked != null && parked >= 3) {
            rec = PipelineReviewConstants.capForecast(rec, PipelineReviewConstants.FC_BC);
        }
        if (dateConflict == true) {
            rec = PipelineReviewConstants.capForecast(rec, PipelineReviewConstants.FC_ML);
        }
        if (riskHeavy == true) {
            rec = PipelineReviewConstants.capForecast(rec, PipelineReviewConstants.oneTierBelow(ae));
        }
        return rec;
    }

    static String recommendRationale(
        String stage,
        Integer freshestAge,
        Boolean nextMissing,
        Integer parked,
        Boolean dateConflict,
        Boolean riskHeavy,
        String aeForecast,
        String rec
    ) {
        if (freshestAge != null && freshestAge > 60
            && stage != null && PipelineReviewConstants.EARLY_STAGES.contains(stage)) {
            return 'No motion in ' + freshestAge + ' days on an early-stage deal.';
        }
        if (nextMissing == true && freshestAge != null && freshestAge > 30) {
            return 'Next step missing and nothing has moved in ' + freshestAge + ' days.';
        }
        if (parked != null && parked >= 3) {
            return 'Same next step restated ' + parked + ' cycles running.';
        }
        if (dateConflict == true) {
            return 'Next step date sits after the close date.';
        }
        if (riskHeavy == true) {
            return 'Risk-heavy book: parked, stale, or missing next step caps the AE forecast.';
        }
        return 'Mirrors the AE forecast of ' + PipelineReviewConstants.normalizeForecast(aeForecast) + '.';
    }

    static Boolean forecastsDisagree(List<String> values) {
        Set<String> setv = new Set<String>();
        for (String v : values) {
            if (String.isNotBlank(v)) setv.add(v);
        }
        return setv.size() > 1;
    }

    static String letterGrade(String rec, Boolean riskHeavy) {
        if (rec == PipelineReviewConstants.FC_COMMIT && riskHeavy != true) return 'A';
        if (rec == PipelineReviewConstants.FC_COMMIT || rec == PipelineReviewConstants.FC_ML) return 'B';
        if (rec == PipelineReviewConstants.FC_BC) return 'C';
        return 'D';
    }

    static String nextStepState(Boolean missing, Boolean pastDue, Integer parked) {
        if (missing == true) return PipelineReviewConstants.STATE_MISSING;
        if (parked != null && parked >= 2) return PipelineReviewConstants.STATE_PARKED;
        if (pastDue == true) return PipelineReviewConstants.STATE_PAST_DUE;
        return PipelineReviewConstants.STATE_HEALTHY;
    }

    static String matchTitleCategory(String title, List<TitlePattern> patterns) {
        if (String.isBlank(title) || patterns == null) return null;
        String t = title.toLowerCase();
        for (TitlePattern p : patterns) {
            if (p == null || String.isBlank(p.pattern)) continue;
            if (t.contains(p.pattern.toLowerCase())) return p.category;
        }
        return null;
    }

    static String contactReason(ContactCandidate c) {
        List<String> bits = new List<String>();
        if (c.inboundReplyAgeDays != null && c.inboundReplyAgeDays <= 60) {
            bits.add('Replied ' + c.inboundReplyAgeDays + ' days ago');
        }
        if (c.isPrimary == true) bits.add('primary contact');
        if (String.isNotBlank(c.title)) bits.add(c.title);
        if (bits.isEmpty()) bits.add('Attached contact');
        return String.join(bits, ', ');
    }

    public static Decimal valueScore(Decimal arr, Decimal maxTeamArr) {
        Decimal a = arr == null || arr < 1000 ? 1000 : arr;
        Decimal maxA = maxTeamArr == null || maxTeamArr < 1000 ? 1000 : maxTeamArr;
        Double num = Math.log10(a.doubleValue());
        Double den = Math.log10(maxA.doubleValue());
        if (den == 0) return 0;
        return cap01(Decimal.valueOf(num / den));
    }

    public static Decimal urgencyWeek(Integer daysOverdue) {
        if (daysOverdue == null) return 0.50;
        if (daysOverdue > 60) return 0.25;
        if (daysOverdue >= 15) return 0.55;
        if (daysOverdue >= 1) return 1.00;
        if (daysOverdue == 0) return 1.00;
        if (daysOverdue >= -7) return 0.85;
        if (daysOverdue >= -21) return 0.40;
        return 0.15;
    }

    public static Decimal urgencyToday(Integer daysOverdue, PrioritySignals live) {
        Decimal u;
        if (live != null && live.meetingToday == true) {
            u = 1.00;
        } else if (daysOverdue == null) {
            u = 0.40;
        } else if (daysOverdue == 0) {
            u = 1.00;
        } else if (daysOverdue >= 1 && daysOverdue <= 7) {
            u = 0.95;
        } else if (daysOverdue == -1) {
            u = 0.85;
        } else if (daysOverdue >= 8 && daysOverdue <= 30) {
            u = 0.50;
        } else if (daysOverdue >= -7 && daysOverdue <= -2) {
            u = 0.40;
        } else if (daysOverdue > 60) {
            u = 0.15;
        } else {
            u = 0.40;
        }
        if (live != null) {
            if (live.inbound24h == true) u += 0.25;
            else if (live.inbound48h == true) u += 0.15;
            if (live.stepDoneYesterdayNoNew == true) u += 0.20;
        }
        return cap01(u);
    }

    static Decimal closeDateMultiplier(Date closeDate, Date today) {
        if (closeDate == null || today == null) return 1;
        Integer days = today.daysBetween(closeDate);
        if (days < 0) return 1.20;
        if (days <= 14) return 1.30;
        if (days <= 30) return 1.15;
        return 1;
    }

    static Decimal leverageScore(GradeInput input) {
        String dir = input == null ? null : PipelineReviewConstants.normalizeForecast(input.directorForecast);
        Decimal lev = 0.30;
        if (dir == PipelineReviewConstants.FC_COMMIT) lev = 1.00;
        else if (dir == PipelineReviewConstants.FC_ML) lev = 0.85;
        else if (dir == PipelineReviewConstants.FC_BC) lev = 0.60;
        else if (dir == PipelineReviewConstants.FC_PIPE) lev = 0.30;
        else if (dir == PipelineReviewConstants.FC_OMITTED) lev = 0.05;
        if (input != null && input.stageName != null && PipelineReviewConstants.LATE_STAGES.contains(input.stageName)) {
            lev = cap01(lev + 0.15);
        }
        if (input != null && input.closeDate != null && input.forecastCategoryName != null) {
            // out-of-quarter close applied by caller when they know fiscal period;
            // Grade() does not call Date.today() and does not query Forecast_Week__c.
        }
        return lev;
    }

    public static Decimal applyOutOfQuarter(Decimal leverage, Boolean outOfQuarter) {
        if (outOfQuarter == true) return cap01((leverage == null ? 0.3 : leverage) * 0.50);
        return leverage;
    }

    static Decimal decayScore(Integer parked, Integer freshest, Boolean mismatch) {
        Decimal d = 0.10;
        if (parked != null && parked >= 3) d = 1.00;
        else if (parked != null && parked == 2) d = 0.75;
        else if (freshest != null && freshest > 30) d = 0.85;
        else if (freshest != null && freshest > 14) d = 0.50;
        if (mismatch == true) d = cap01(d + 0.20);
        return d;
    }

    static Decimal actionabilityScore(GradeInput input) {
        if (input == null) return 0.50;
        List<ContactCandidate> contacts = input.contacts;
        if (contacts == null || contacts.isEmpty()) return 0.50;
        Boolean hasEmail = false;
        Boolean inCadence = false;
        for (ContactCandidate c : contacts) {
            if (c != null && String.isNotBlank(c.email)) hasEmail = true;
            if (c != null && c.inActiveCadence == true) inCadence = true;
        }
        if (String.isNotBlank(input.pricingApproval) && input.pricingApproval.toLowerCase().contains('pend')) {
            return 0.70;
        }
        if (input.forecastWeekLocked == true) return 0.60;
        if (!hasEmail) return 0.80;
        if (inCadence) return 0.75;
        return 1.00;
    }

    static Decimal priorityFrom(
        WeightConfig w, Decimal value, Decimal urgency, Decimal leverage, Decimal decay, Decimal act
    ) {
        Decimal wv = nz(w.wV), wu = nz(w.wU), ws = nz(w.wS), wr = nz(w.wR);
        Decimal den = wv + wu + ws + wr;
        if (den == 0) {
            wv = 1; wu = 1; ws = 1; wr = 1; den = 4;
        }
        Decimal mix = (wv * nz(value) + wu * nz(urgency) + ws * nz(leverage) + wr * nz(decay)) / den;
        Decimal raw = 100 * nz(act) * mix;
        if (raw < 0) raw = 0;
        if (raw > 100) raw = 100;
        return raw.setScale(2);
    }

    static String reasonText(
        Decimal value, Decimal urg, Decimal lev, Decimal decay, Decimal act,
        GradeInput input, Integer nextAge, Integer parked, Integer freshest
    ) {
        List<String> parts = new List<String>();
        if (input != null && (input.contacts == null || input.contacts.isEmpty())) {
            parts.add('nobody is attached to it');
        }
        if (input != null && PipelineReviewConstants.normalizeForecast(input.directorForecast)
            == PipelineReviewConstants.FC_COMMIT && input.closeDate != null) {
            parts.add('Commit deal');
        }
        if (nextAge != null && nextAge > 0 && nextAge <= 14) {
            parts.add('next step missed ' + nextAge + ' days ago');
        } else if (nextAge != null && nextAge > 60) {
            parts.add('overdue ' + nextAge + ' days');
        }
        if (parked != null && parked >= 2) {
            parts.add('same next step restated ' + parked + ' cycles');
        }
        if (freshest != null && freshest > 14) {
            parts.add('nothing logged in ' + freshest + ' days');
        }
        if (value != null && value >= 0.85) parts.add('largest deal in the queue');
        if (parts.size() < 2 && lev != null && lev >= 0.85) parts.add('high leverage this quarter');
        if (parts.size() < 2 && urg != null && urg >= 0.85) parts.add('due now');
        while (parts.size() < 2) parts.add('needs a look this week');
        String text = parts[0].substring(0, 1).toUpperCase() + parts[0].substring(1)
            + ', ' + parts[1] + '.';
        return text.length() > 255 ? text.left(255) : text;
    }

    static Integer nextAgeFromReason(GradeResult stored) {
        return stored == null ? null : stored.freshestAge;
    }

    static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }

    static Decimal cap01(Decimal d) {
        if (d == null) return 0;
        if (d < 0) return 0;
        if (d > 1) return 1;
        return d;
    }

    private class HistoryNewestFirst implements Comparator<HistoryEntry> {
        public Integer compare(HistoryEntry a, HistoryEntry b) {
            if (a == null && b == null) return 0;
            if (a == null) return 1;
            if (b == null) return -1;
            if (a.entryDate == b.entryDate) return 0;
            if (a.entryDate == null) return 1;
            if (b.entryDate == null) return -1;
            return a.entryDate > b.entryDate ? -1 : 1;
        }
    }

    private class ContactScoreDesc implements Comparator<ContactPick> {
        public Integer compare(ContactPick a, ContactPick b) {
            Integer sa = a == null || a.score == null ? -10000 : a.score;
            Integer sb = b == null || b.score == null ? -10000 : b.score;
            if (sa != sb) return sa > sb ? -1 : 1;
            String ia = a == null ? '' : String.valueOf(a.contactId);
            String ib = b == null ? '' : String.valueOf(b.contactId);
            return ia < ib ? -1 : (ia == ib ? 0 : 1);
        }
    }

    private class BucketPriorityDesc implements Comparator<BucketRow> {
        public Integer compare(BucketRow a, BucketRow b) {
            Decimal pa = a == null || a.priority == null ? -1 : a.priority;
            Decimal pb = b == null || b.priority == null ? -1 : b.priority;
            if (pa != pb) return pa > pb ? -1 : 1;
            return 0;
        }
    }
}
