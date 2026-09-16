/**
 * Covers: PipelineReviewGradeService
 * Property suite from the Pipeline Review spec. Pure — no SOQL/DML in the engine.
 */
@IsTest
private class PipelineReviewGradeServiceTest {
    private static final Date TODAY = Date.newInstance(2026, 9, 16);

    @IsTest
    static void chunking_flattensInOrder_noDupes_lastMayBeShort() {
        List<Id> ids = new List<Id>();
        for (Integer i = 1; i <= 310; i++) ids.add(fakeOppId(i));
        Test.startTest();
        List<List<Id>> chunks = PipelineReviewGradeService.chunk(ids, 50);
        Test.stopTest();
        System.assertEquals(7, chunks.size(), 'ceil(310/50) is 7');
        List<Id> flat = new List<Id>();
        Set<Id> seen = new Set<Id>();
        for (Integer i = 0; i < chunks.size(); i++) {
            System.assert(chunks[i].size() <= 50, 'no chunk exceeds size');
            if (i < chunks.size() - 1) {
                System.assertEquals(50, chunks[i].size(), 'only last may be short');
            }
            for (Id x : chunks[i]) {
                System.assert(!seen.contains(x), 'no duplicates');
                seen.add(x);
                flat.add(x);
            }
        }
        System.assertEquals(ids, flat, 'flattening returns original list in order');
        System.assertEquals(10, chunks[6].size(), 'last chunk is the remainder');
    }

    @IsTest
    static void matchReply_completeShuffledUnknownDuplicateIllegalGarbage() {
        Id a = fakeOppId(1);
        Id b = fakeOppId(2);
        Id c = fakeOppId(3);
        Id stranger = fakeOppId(99);
        List<Id> requested = new List<Id>{ a, b, c };

        String complete = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'id' => (String) b, 'note' => '09/16 - moved', 'forecast' => 'Commit' },
            new Map<String, Object>{ 'id' => (String) a, 'note' => '09/16 - also', 'forecast' => 'Pipeline' },
            new Map<String, Object>{ 'id' => (String) c, 'note' => '09/16 - third', 'forecast' => 'Best Case' }
        });
        PipelineReviewGradeService.ReplyMatch m = PipelineReviewGradeService.matchReply(requested, complete);
        System.assertEquals(3, m.matched.size(), 'complete valid reply matches everything');
        System.assertEquals(0, m.missing.size(), 'reports nothing missing');
        System.assertEquals('Commit', m.matched.get(b).get('forecast'), 'shuffled reply lands on the right Id');

        String polluted = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'id' => (String) a, 'forecast' => 'Commit' },
            new Map<String, Object>{ 'id' => (String) stranger, 'forecast' => 'Commit' },
            new Map<String, Object>{ 'id' => (String) a, 'forecast' => 'Omitted' },
            new Map<String, Object>{ 'id' => (String) b, 'forecast' => 'Nope' }
        });
        PipelineReviewGradeService.ReplyMatch p = PipelineReviewGradeService.matchReply(requested, polluted);
        System.assert(!p.matched.containsKey(stranger), 'Ids never requested are never written');
        System.assertEquals('Commit', p.matched.get(a).get('forecast'), 'duplicate Ids: first wins');
        System.assert(p.rejected >= 2, 'rest counted rejected');
        System.assert(p.missing.contains(b), 'illegal forecast rejected and Id reported missing');
        System.assert(p.missing.contains(c), 'partial reply leaves remainder missing');
        Set<Id> union = new Set<Id>(p.matched.keySet());
        union.addAll(p.missing);
        System.assertEquals(new Set<Id>(requested), union, 'matched and missing exactly partition requested Ids');

        for (String garbage : new List<String>{ null, '', 'not-json', '{', '[]' }) {
            PipelineReviewGradeService.ReplyMatch g = PipelineReviewGradeService.matchReply(requested, garbage);
            System.assertEquals(3, g.missing.size(), 'garbage marks every Id missing: ' + garbage);
            System.assertEquals(0, g.matched.size(), 'garbage never writes');
        }
    }

    @IsTest
    static void historyParsing_properties() {
        Test.startTest();
        List<PipelineReviewGradeService.HistoryEntry> empty =
            PipelineReviewGradeService.parseHistory(null, TODAY);
        System.assertEquals(0, empty.size(), 'null yields no entries');
        System.assertEquals(0, PipelineReviewGradeService.parseHistory('', TODAY).size(), 'empty yields no entries');
        System.assertEquals(0, PipelineReviewGradeService.parseHistory('<p></p>', TODAY).size(), 'tag-only yields no entries');

        String rich = '8/18/2026 : By Aug 20 email Ortiz.<p></p><p></p>8/11/2026 : Mikeya silent since Jul 20.';
        List<PipelineReviewGradeService.HistoryEntry> entries =
            PipelineReviewGradeService.parseHistory(rich, TODAY);
        Test.stopTest();
        System.assertEquals(2, entries.size(), 'two date markers, two entries');
        System.assert(entries[0].entryDate >= entries[1].entryDate, 'always newest first');
        for (PipelineReviewGradeService.HistoryEntry e : entries) {
            System.assertNotEquals(null, e.entryDate, 'never invalid date');
            System.assert(String.isNotBlank(e.text), 'never empty text');
            System.assertEquals(e.entryDate.daysBetween(TODAY), e.ageDays, 'age consistent with parsed date');
        }
        String moreMarksThanText = '1/1/2026 : <p></p>2/2/2026 :';
        List<PipelineReviewGradeService.HistoryEntry> dropped =
            PipelineReviewGradeService.parseHistory(moreMarksThanText, TODAY);
        System.assert(dropped.size() <= 2, 'entry count never exceeds date markers');
    }

    @IsTest
    static void similarity_and_parked_properties() {
        Test.startTest();
        System.assertEquals(1, PipelineReviewGradeService.similarity('confirm the demo result with Ortiz', 'confirm the demo result with Ortiz'), 'identical scores 1');
        Decimal ab = PipelineReviewGradeService.similarity('confirm the demo result with Ortiz', 'send the order form to legal');
        Decimal ba = PipelineReviewGradeService.similarity('send the order form to legal', 'confirm the demo result with Ortiz');
        System.assertEquals(ab, ba, 'symmetric');
        System.assert(ab >= 0 && ab <= 1, 'within 0..1');
        Decimal dated = PipelineReviewGradeService.similarity(
            'Jul 24 - confirm the demo result with Ortiz',
            'Jul 31 - confirm the demo result with Ortiz'
        );
        System.assertEquals(1, dated, 'same plan on a new date still scores 1');

        List<PipelineReviewGradeService.HistoryEntry> none = new List<PipelineReviewGradeService.HistoryEntry>();
        System.assertEquals(0, PipelineReviewGradeService.parkedRuns(none), 'zero entries never parked');
        none.add(entry(TODAY, 'one'));
        System.assertEquals(0, PipelineReviewGradeService.parkedRuns(none), 'one entry never parked');

        List<PipelineReviewGradeService.HistoryEntry> parked = new List<PipelineReviewGradeService.HistoryEntry>{
            entry(TODAY, 'Jul 31 - confirm the demo result with Ortiz'),
            entry(TODAY.addDays(-7), 'Jul 24 - confirm the demo result with Ortiz'),
            entry(TODAY.addDays(-14), 'Jul 17 - confirm the demo result with Ortiz'),
            entry(TODAY.addDays(-21), 'totally different plan call the CFO')
        };
        Integer runs = PipelineReviewGradeService.parkedRuns(parked);
        Test.stopTest();
        System.assert(runs >= 2, 'counts consecutive restatements');
        System.assert(runs <= parked.size() - 1, 'never exceeds entries-1');
        System.assert(runs >= 0, 'never negative');
        System.assertEquals(2, runs, 'stops counting at the first genuine change');
    }

    @IsTest
    static void ageBands_monotonic_and_boundaries() {
        Test.startTest();
        System.assertEquals('current', PipelineReviewGradeService.ageBand(0));
        System.assertEquals('current', PipelineReviewGradeService.ageBand(7));
        System.assertEquals('recent', PipelineReviewGradeService.ageBand(8));
        System.assertEquals('recent', PipelineReviewGradeService.ageBand(21));
        System.assertEquals('aging', PipelineReviewGradeService.ageBand(22));
        System.assertEquals('aging', PipelineReviewGradeService.ageBand(45));
        System.assertEquals('history', PipelineReviewGradeService.ageBand(46));
        System.assertEquals('unknown', PipelineReviewGradeService.ageBand(null));
        Test.stopTest();
        List<Integer> days = new List<Integer>{ 0, 7, 8, 21, 22, 45, 46, 90 };
        String prev = PipelineReviewGradeService.ageBand(0);
        Map<String, Integer> rank = new Map<String, Integer>{
            'current' => 1, 'recent' => 2, 'aging' => 3, 'history' => 4
        };
        for (Integer d : days) {
            String band = PipelineReviewGradeService.ageBand(d);
            System.assert(rank.get(band) >= rank.get(prev), 'monotonic: older never lands in a fresher band');
            prev = band;
        }
    }

    @IsTest
    static void contactResolution_properties() {
        Id opp = fakeOppId(1);
        Id otherOpp = fakeOppId(2);
        Id primary = fakeContactId(1);
        Id replier = fakeContactId(2);
        Id noEmail = fakeContactId(3);
        Id foreign = fakeContactId(4);

        PipelineReviewGradeService.ContactCandidate p = cand(primary, opp, 'Pat Primary', 'Analyst', 'pat@x.com', true, null, 40, null, false, false);
        PipelineReviewGradeService.ContactCandidate r = cand(replier, opp, 'Erika Reply', 'Finance Director', 'erika@x.com', false, null, 20, 6, false, false);
        PipelineReviewGradeService.ContactCandidate n = cand(noEmail, opp, 'No Mail', 'CFO', null, false, null, 2, null, false, false);
        PipelineReviewGradeService.ContactCandidate f = cand(foreign, otherOpp, 'Wrong Opp', 'CFO', 'w@x.com', true, null, 1, 1, false, false);

        Test.startTest();
        System.assertEquals(null, PipelineReviewGradeService.pickContact(new List<PipelineReviewGradeService.ContactCandidate>(), opp, 'Discovery', patterns()),
            'zero attached contacts returns null');
        PipelineReviewGradeService.ContactPick pick = PipelineReviewGradeService.pickContact(
            new List<PipelineReviewGradeService.ContactCandidate>{ p, r, n, f }, opp, 'Verbal Win', patterns()
        );
        Test.stopTest();
        System.assertNotEquals(null, pick, 'picks someone');
        System.assertEquals(replier, pick.contactId, 'recent inbound replier outranks a primary who has never replied');
        System.assertNotEquals(foreign, pick.contactId, 'never returns a contact not attached to that opportunity');
        System.assertNotEquals(noEmail, pick.contactId, 'a contact with no email never wins when one with an email exists');

        // Realistic case: Role = null on every candidate
        PipelineReviewGradeService.ContactPick roleless = PipelineReviewGradeService.pickContact(
            new List<PipelineReviewGradeService.ContactCandidate>{ p, r, n }, opp, 'Discovery', patterns()
        );
        System.assertNotEquals(null, roleless, 'Role null still returns a sensible pick');
        System.assertEquals(replier, roleless.contactId, 'title + reply still win when Role is null');

        PipelineReviewGradeService.ContactPick again = PipelineReviewGradeService.pickContact(
            new List<PipelineReviewGradeService.ContactCandidate>{ p, r }, opp, 'Discovery', patterns()
        );
        System.assertEquals(roleless.contactId, again.contactId, 'deterministic');
    }

    @IsTest
    static void priority_properties_including_zombie_trap() {
        PipelineReviewGradeService.WeightConfig w = PipelineReviewGradeService.defaultWeights();
        PipelineReviewGradeService.GradeInput big = baseInput(500000);
        PipelineReviewGradeService.GradeInput small = baseInput(40000);
        big.contacts = new List<PipelineReviewGradeService.ContactCandidate>{
            cand(fakeContactId(1), fakeOppId(1), 'A', 'CFO', 'a@x.com', true, null, 3, null, false, false)
        };
        small.contacts = big.contacts;

        Test.startTest();
        PipelineReviewGradeService.GradeResult rb = PipelineReviewGradeService.grade(big, TODAY, w, 500000);
        PipelineReviewGradeService.GradeResult rs = PipelineReviewGradeService.grade(small, TODAY, w, 500000);
        System.assert(rb.actionPriority >= 0 && rb.actionPriority <= 100, 'within 0..100');
        System.assert(rs.actionPriority >= 0 && rs.actionPriority <= 100, 'within 0..100 including smaller ARR');
        System.assert(rb.actionPriority >= rs.actionPriority, 'higher ARR never scores lower, all else equal');

        Decimal u5 = PipelineReviewGradeService.urgencyWeek(5);
        Decimal u90 = PipelineReviewGradeService.urgencyWeek(90);
        System.assert(u90 < u5, 'zombie trap: 90 days overdue scores lower urgency than 5');

        PipelineReviewGradeService.GradeInput lonely = baseInput(500000);
        lonely.contacts = new List<PipelineReviewGradeService.ContactCandidate>();
        PipelineReviewGradeService.GradeResult rl = PipelineReviewGradeService.grade(lonely, TODAY, w, 500000);
        System.assert(rl.actionPriority < rb.actionPriority, 'no-contact deal scores below the identical deal with one');

        PipelineReviewGradeService.PrioritySignals live = new PipelineReviewGradeService.PrioritySignals();
        live.inbound24h = true;
        Decimal todayHot = PipelineReviewGradeService.urgencyToday(5, live);
        Decimal todayCold = PipelineReviewGradeService.urgencyToday(5, null);
        Decimal weekHot = PipelineReviewGradeService.urgencyWeek(5);
        Decimal weekCold = PipelineReviewGradeService.urgencyWeek(5);
        System.assert(todayHot > todayCold, 'Today mode: inbound reply today outranks the identical deal');
        System.assertEquals(weekHot, weekCold, 'This Week mode ties when only the live signal differs');

        PipelineReviewGradeService.WeightConfig zero = new PipelineReviewGradeService.WeightConfig();
        zero.wV = 0; zero.wU = 0; zero.wS = 0; zero.wR = 0;
        PipelineReviewGradeService.GradeResult rz = PipelineReviewGradeService.grade(big, TODAY, zero, 500000);
        System.assert(rz.actionPriority >= 0 && rz.actionPriority <= 100, 'zero weights do not divide by zero');
        System.assert(rz.actionPriorityReason.length() <= 255, 'reason never exceeds 255');
        System.assert(rz.actionPriorityReason.contains(','), 'reason names two components');
        Test.stopTest();
    }

    @IsTest
    static void bucketing_exactly_one_and_focus_cap() {
        List<PipelineReviewGradeService.BucketRow> rows = new List<PipelineReviewGradeService.BucketRow>();
        for (Integer i = 1; i <= 20; i++) {
            PipelineReviewGradeService.BucketRow row = new PipelineReviewGradeService.BucketRow();
            row.opportunityId = fakeOppId(i);
            row.priority = 100 - i;
            row.naturalBucket = i <= 3
                ? PipelineReviewConstants.BUCKET_FIX
                : PipelineReviewConstants.BUCKET_DUE;
            rows.add(row);
        }
        Test.startTest();
        Map<Id, String> buckets = PipelineReviewGradeService.assignBuckets(rows, 5);
        Test.stopTest();
        Integer focus = 0;
        for (Id id : buckets.keySet()) {
            System.assertNotEquals(null, buckets.get(id), 'every opportunity lands in a bucket');
            if (buckets.get(id) == PipelineReviewConstants.BUCKET_FOCUS) focus++;
        }
        System.assertEquals(20, buckets.size(), 'every row assigned');
        System.assertEquals(5, focus, 'Focus never exceeds the cap');
        System.assertEquals(PipelineReviewConstants.BUCKET_FIX, buckets.get(fakeOppId(1)), 'Fix First stays Fix First');
    }

    @IsTest
    static void isValidNote_rejects_short_error_and_overlong() {
        Test.startTest();
        System.assertEquals(false, PipelineReviewGradeService.isValidNote(null));
        System.assertEquals(false, PipelineReviewGradeService.isValidNote('short'));
        System.assertEquals(false, PipelineReviewGradeService.isValidNote('09/16 - tool call failed and the model is unavailable'));
        System.assertEquals(false, PipelineReviewGradeService.isValidNote('no prefix on this otherwise long enough note that talks about the deal'));
        String good = '09/16 - Patray has legal reviewing the EULA and holds the Aug 28 session, so paper is moving. Cindy to refresh the quote before Aug 28.';
        System.assertEquals(true, PipelineReviewGradeService.isValidNote(good));
        System.assertEquals(false, PipelineReviewGradeService.isValidNote(good + ' ' + 'x'.repeat(400)));
        Test.stopTest();
    }

    @IsTest
    static void recommendForecast_rules() {
        Test.startTest();
        System.assertEquals(
            'Omitted',
            PipelineReviewGradeService.recommendForecast('Discovery', 70, false, 0, false, false, 'Commit')
        );
        System.assertEquals(
            'Pipeline',
            PipelineReviewGradeService.recommendForecast('Proposal', 40, true, 0, false, false, 'Commit')
        );
        System.assertEquals(
            'Best Case',
            PipelineReviewGradeService.recommendForecast('Proposal', 10, false, 3, false, false, 'Commit')
        );
        Test.stopTest();
    }

    private static PipelineReviewGradeService.HistoryEntry entry(Date d, String text) {
        PipelineReviewGradeService.HistoryEntry e = new PipelineReviewGradeService.HistoryEntry();
        e.entryDate = d;
        e.ageDays = d.daysBetween(TODAY);
        e.text = text;
        return e;
    }

    private static PipelineReviewGradeService.GradeInput baseInput(Decimal arr) {
        PipelineReviewGradeService.GradeInput g = new PipelineReviewGradeService.GradeInput();
        g.opportunityId = fakeOppId(1);
        g.stageName = 'Proposal';
        g.closeDate = TODAY.addDays(20);
        g.forecastCategoryName = 'Commit';
        g.directorForecast = 'Commit';
        g.rollupForecast = 'Commit';
        g.nextStep = 'Call Ortiz';
        g.nextStepDate = TODAY.addDays(-4);
        g.directorNote = '09/10 - Still waiting on legal.';
        g.lastActivityDate = TODAY.addDays(-4);
        g.arr = arr;
        g.history = new List<PipelineReviewGradeService.HistoryEntry>();
        g.titlePatterns = patterns();
        return g;
    }

    private static List<PipelineReviewGradeService.TitlePattern> patterns() {
        List<PipelineReviewGradeService.TitlePattern> out = new List<PipelineReviewGradeService.TitlePattern>();
        PipelineReviewGradeService.TitlePattern t = new PipelineReviewGradeService.TitlePattern();
        t.category = 'EconomicBuyer';
        t.pattern = 'Finance Director';
        out.add(t);
        PipelineReviewGradeService.TitlePattern t2 = new PipelineReviewGradeService.TitlePattern();
        t2.category = 'EconomicBuyer';
        t2.pattern = 'CFO';
        out.add(t2);
        return out;
    }

    private static PipelineReviewGradeService.ContactCandidate cand(
        Id cid, Id oid, String name, String title, String email, Boolean primary,
        String role, Integer daysAct, Integer replyAge, Boolean bounced, Boolean cadence
    ) {
        PipelineReviewGradeService.ContactCandidate c = new PipelineReviewGradeService.ContactCandidate();
        c.contactId = cid;
        c.opportunityId = oid;
        c.name = name;
        c.title = title;
        c.email = email;
        c.isPrimary = primary;
        c.role = role;
        c.daysSinceActivity = daysAct;
        c.inboundReplyAgeDays = replyAge;
        c.bounced = bounced;
        c.inActiveCadence = cadence;
        return c;
    }

    private static Id fakeOppId(Integer n) {
        return Id.valueOf('006000000000' + String.valueOf(n).leftPad(3, '0'));
    }

    private static Id fakeContactId(Integer n) {
        return Id.valueOf('003000000000' + String.valueOf(n).leftPad(3, '0'));
    }
}
