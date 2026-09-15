/**
 * Deterministic evidence scoring (guide P5). Same record -> same score, and the
 * reason string explains it. Phase B: MEDDPICC is optional (null here, since the
 * 8 Rich Text Area(5000) fields cannot be read synchronously per guide P3 heap
 * limits); push count is passed in rather than read from a stored field.
 */
public with sharing class CockpitScoreService {

    public class Result {
        @AuraEnabled public Integer score;
        @AuraEnabled public String klass;   // HI | MD | EX
        @AuraEnabled public String reason;
    }

    /**
     * @param o         Opportunity with score inputs populated (no MEDDPICC fields)
     * @param meddpicc  null in Phase B (added by the nightly batch in Phase A)
     * @param pushCount close-date change count (from history in Phase B)
     * @param today     passed in so tests are deterministic
     */
    public static Result score(Opportunity o, Integer meddpicc, Decimal pushCount, Date today) {
        Integer s = 0;
        List<String> why = new List<String>();

        Integer sp = CockpitConstants.STAGE_POINTS.containsKey(o.StageName)
            ? CockpitConstants.STAGE_POINTS.get(o.StageName) : 0;
        s += sp;
        if (sp != 0) why.add(o.StageName + ' (' + signed(sp) + ')');

        if (o.Pricing_Approval_Status__c == 'Approved') {
            s += 2; why.add('pricing approved (+2)');
        } else if (o.Pricing_Approval_Status__c == 'Submitted for Approval') {
            s += 1; why.add('pricing submitted (+1)');
        }

        if (meddpicc != null) {
            if (meddpicc >= 5)      { s += 2; why.add('MEDDPICC ' + meddpicc + '/8 (+2)'); }
            else if (meddpicc >= 3) { s += 1; why.add('MEDDPICC ' + meddpicc + '/8 (+1)'); }
            else                    { s -= 1; why.add('MEDDPICC ' + meddpicc + '/8 (-1)'); }
        }

        // Guide correction 7: a rolled date is weak evidence.
        if (o.Next_Step_Date_bf__c == null) {
            s -= 1; why.add('no next step date (-1)');
        } else if (o.Next_Step_Date_bf__c < today) {
            s -= 1; why.add('next step lapsed (-1)');
        }

        // Guide correction 6: real activity, future-dated events are not evidence.
        Integer quiet = daysQuiet(o, today);
        if (quiet == null)      { s -= 2; why.add('no activity ever (-2)'); }
        else if (quiet <= 21)   { s += 1; why.add('active ' + quiet + 'd (+1)'); }
        else if (quiet > 45)    { s -= 2; why.add('silent ' + quiet + 'd (-2)'); }

        if (o.SQL_Datestamp_bf__c != null) { s += 1; }
        else { s -= 3; why.add('not SQL-qualified (-3)'); }

        Decimal pushes = (pushCount == null) ? 0 : pushCount;
        if (pushes >= 6)      { s -= 2; why.add(pushes + ' close-date pushes (-2)'); }
        else if (pushes >= 3) { s -= 1; why.add(pushes + ' close-date pushes (-1)'); }

        Result r = new Result();
        r.score = s;

        Decimal arr = o.ARR_Opportunity_Amount_USD_Num__c;
        if (arr == null || arr <= 0) {
            r.klass  = 'EX';
            r.reason = 'zero ARR on the record'
                     + (why.isEmpty() ? '' : '; ' + String.join(why, ', '));
            return r;
        }

        r.klass  = s >= CockpitConstants.THRESHOLD_HIGH
            ? 'HI' : (s >= CockpitConstants.THRESHOLD_MED ? 'MD' : 'EX');
        r.reason = String.join(why, ', ');
        return r;
    }

    /**
     * Guide correction 6. LastActivityDate counts FUTURE Events, so a deal with
     * next month's meeting booked reads as touched today. A future date is
     * treated as no evidence of a real touch.
     */
    private static Integer daysQuiet(Opportunity o, Date today) {
        Date touch = o.LastActivityDate;
        if (touch == null) return null;
        if (touch > today) return null;
        return touch.daysBetween(today);
    }

    private static String signed(Integer n) { return n > 0 ? '+' + n : String.valueOf(n); }
}
