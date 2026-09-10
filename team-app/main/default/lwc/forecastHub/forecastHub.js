import { LightningElement, wire } from 'lwc';
import load from '@salesforce/apex/CockpitForecastController.load';

const SFBASE = 'https://euna.my.salesforce.com/';

// Seeded judgment overrides from the deep dive (id -> [class, rationale]).
// The rule engine cannot read prose; these are the calls it cannot make.
const SEED = {
    '006OL00000g35fjYAA': ['EX', "MEDDPICC fields all contain the placeholder 'RFP'. INFOR subcontract, no customer decision date."],
    '006OL00000Hwjz3YAB': ['EX', "Lost. Next step reads 'we were not selected as the winner'."],
    '006OL00000YBgErYAL': ['EX', "'We're not bidding on this.' Should be Closed/Lost."],
    '006OL00000gAKOfYAO': ['EX', 'Buyer stated not interested on the Jul 16 call.'],
    '006OL00000flDF7YAM': ['EX', 'Both grant-management RFPs formally rejected via posted resolutions.'],
    '006OL00000Nz2UHYAZ': ['EX', '11 close-date pushes, silent since Jun 26. AE note says reset the close.'],
    '006OL00000QiagjYAB': ['EX', '11 pushes, quote expired Jun 2025, buyer retired.'],
    '006OL00000W88VpYAJ': ['EX', 'Parked since April. AE note says move off Best Case.'],
    '006OL00000ccN8zYAE': ['EX', '56 days silent on a Jun 16 proposal.'],
    '006OL00000S9bi1YAB': ['EX', 'Economic buyer declined; AE note says reset the close to 2027.'],
    '006OL00000iZcieYAC': ['EX', "Next step opens '(on hold)' and says reforecast off Best Case."],
    '006OL00000aZdD3YAK': ['EX', 'Customer confirms budget not approved until September.'],
    '006OL00000QHUCRYA5': ["EX", "AE's own next step resets the close to the November budget timeline."],
    '006OL00000dQ9xJYAS': ['EX', 'Next step meeting date falls after the close date. Scope undefined.'],
    '006OL00000aPCqrYAG': ['HI', 'Verbal Win, pricing approved, MEDDPICC 8/8, Aug 28 legal negotiation booked.'],
    '006OL00000fNF1zYAG': ['HI', 'Signature Pending. Order form and SOW out for Mayor signature.'],
    '006OL00000d3KlJYAU': ['HI', 'Verbal Win, COI requested, signature authority confirmed.'],
    '006OL00000i2VjmYAE': ['HI', 'Verbal Win. Buyer holds order form, SOW, W9 and COI.'],
    '006OL00000iLE9vYAG': ['HI', 'Signature Pending on a Judge Executive approval; quote expires Aug 28.'],
    '006OL00000Zl1ZCYAZ': ['MD', 'Order form, EULA, SOW and security questionnaire in flight with pricing approved.'],
    '006OL00000cz8MAYAY': ['MD', 'Vendor of choice per the Jul 28 onsite, beat OpenGov on CGI integration.'],
    '006OL00000csyxNYAQ': ['MD', 'Inside an existing Grants agreement; SE demo scoped and booked.'],
    '006OL00000S3ifVYAR': ['MD', 'MEDDPICC records tentative selection as vendor of choice; budget finalized.'],
    '006OL00000US8MLYA1': ['MD', 'Champion reset in progress. AE trigger: no meeting by Aug 21 and the date resets.']
};

// Pull-in candidates: id -> [target quarter, case for, case against].
const PULL = {
    '006OL00000kpQZ3YAM': ['Current', 'Customer budget locks mid-September; the close sits on the wrong side of their funding gate. MEDDPICC 8/8, pricing approved.', 'Single-threaded on the champion, quiet 19 days. CFO never engaged.'],
    '006OL00000eVB6dYAG': ['Current', 'Verbal Win, Commit, MEDDPICC 8/8, pricing approved. Champion is also the economic buyer.', '6 close-date pushes. Next step unchanged since Jun 29. Discount deadline lapsed.'],
    '006OL00000lweYHYAY': ['Current', 'Live RFP with hard dates. Largest single swing available from next quarter.', 'Conditional only. MEDDPICC 0/8. Public award cycles run 60-90 days.'],
    '006OL00000aXRr7YAG': ['Current', 'Existing-customer upsell, pricing approved, MEDDPICC 6/8, demo booked with named attendees.', "Still Proof stage with a short runway. Next step ends 'Handoff?'."],
    '006OL00000S9blTYAR': ['Current', 'Pricing approved, MEDDPICC 8/8, activity yesterday.', 'Champion strength questioned. Council approval not scheduled.'],
    '006OL00000jftY5YAI': ['Next', 'Pricing approved, MEDDPICC 7/8. Decision Process implies a March go-live => Q4 close.', 'Already pushed once. Springbrook competing. Judge Executive not engaged.'],
    '006OL00000k7V30YAE': ['Next', 'Pricing approved, MEDDPICC 7/8, budget approved at $50K+. Onsite booked.', "No economic buyer. Procurement path 'TBD'."],
    '006OL00000fob6PYAQ': ['Next', 'Pricing approved, MEDDPICC 7/8, standalone quote sent. Pairs with the Budget deal.', "Buyer: 'not in a rush.' Prior demo landed poorly. No champion."],
    '006OL00000kXEjFYAW': ['Next', 'Close sits one day outside the quarter. Zero pushes. Genuine week-over-week progression.', 'Alignment stage, MEDDPICC 0/8, OpenGov competing, no decision date.'],
    '006OL00000lTumxYAC': ['Next', 'Down to a 2-vendor shortlist from 5. Debrief booked to present pricing.', 'MEDDPICC 0/8. Pricing requires approval. No stated decision date.'],
    '006OL00000aqBvVYAU': ['Next', 'Champion pushing for RFP release this quarter. Budget meeting booked.', 'Reverses a deliberate push made Jun 30. Still ballpark pricing.'],
    '006OL00000m0GIrYAM': ['Next', 'Newest record with a deliberately set close date. Demo booked.', 'Speculative. No demo held, MEDDPICC 0/8, no economic buyer.'],
    '006OL00000lD4xBYAS': ['Next', 'Live email thread, onsite offered, pricing drafted, product fit confirmed.', 'Prior contact left the City. No economic buyer named. MEDDPICC 0/8.'],
    '006OL00000haNqAYAU': ['Next', 'Pricing approved, SOW and EULA answered, order form finalizing for council.', 'MEDDPICC 0/8, council date not confirmed.'],
    '006OL00000Y88JNYAZ': ['Next', 'Verbal Win, Commit, MEDDPICC 8/8. SOW, EULA and DPA already sent.', 'Pricing still requires approval. A Verbal Win two quarters out is a date error.'],
    '006OL00000hjFjiYAE': ['Next', 'Verbal Win, MEDDPICC 8/8, champion and economic buyer are one, no competition.', 'Small dollar. Tied to the Year 2 renewal cycle.']
};

const TABS = [
    { id: 't1', label: 'Summary' },
    { id: 't2', label: 'Current Qtr' },
    { id: 't3', label: 'Next Qtr' },
    { id: 't4', label: 'Pull-Ins' }
];
const CLS_META = { HI: ['p-hi', 'Include-High'], MD: ['p-med', 'Include-Med'], EX: ['p-ex', 'Exclude'] };
const BAND_META = { 'Commit': 'p-com', 'Most Likely': 'p-ml', 'Best Case': 'p-bc', 'Pipeline': 'p-pipe', 'Omitted': 'p-om' };

export default class ForecastHub extends LightningElement {
    loading = true;
    error;
    deals = [];
    teamSize;
    qLabelA;
    qLabelB;
    activeTab = 't1';
    wHi = 85; wMed = 30; wPull = 20;
    overrides = {};
    pickDev = {};

    @wire(load)
    handle({ data, error }) {
        this.loading = false;
        if (data) {
            this.deals = data.deals || [];
            this.teamSize = data.teamSize;
            this.qLabelA = data.qLabelA;
            this.qLabelB = data.qLabelB;
            this.overrides = { ...SEED };
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Could not load the Forecasting Hub.';
        }
    }

    money(n) { return (n == null || isNaN(n)) ? '$0' : '$' + Math.round(n).toLocaleString('en-US'); }
    clsOf(d) { const o = this.overrides[d.id]; return o ? o[0] : d.klass; }
    noteOf(d) { const o = this.overrides[d.id]; return o ? o[1] : null; }
    isPicked(d) {
        const cls = this.clsOf(d);
        const def = cls === 'HI' || cls === 'MD';
        return this.pickDev[d.id] !== undefined ? this.pickDev[d.id] : def;
    }

    decorate(d) {
        const cls = this.clsOf(d);
        const meta = CLS_META[cls] || CLS_META.EX;
        const note = this.noteOf(d);
        const picked = this.isPicked(d);
        return {
            id: d.id, account: d.account, ae: d.ae, stage: d.stage, score: d.score,
            arr: d.arr, arrFmt: this.money(d.arr), reason: d.reason, note, hasNote: !!note,
            url: SFBASE + d.id, cls, clsLabel: meta[1], clsPill: 'pill ' + meta[0],
            selClass: 'clssel v-' + cls,
            clsOptions: ['HI', 'MD', 'EX'].map((v) => ({ value: v, label: CLS_META[v][1], selected: v === cls })),
            band: d.band || '-', bandPill: 'pill ' + (BAND_META[d.band] || 'p-pipe'),
            picked, rowClass: picked ? 'picked' : ''
        };
    }

    rowsFor(bucket) {
        return this.deals
            .filter((d) => d.bucket === bucket)
            .sort((a, b) => (b.arr || 0) - (a.arr || 0))
            .map((d) => this.decorate(d));
    }
    get currentRows() { return this.rowsFor('A'); }
    get nextRows() { return this.rowsFor('B'); }

    totals(rows) {
        let hi = 0, md = 0, pickedArr = 0, pickedN = 0;
        rows.forEach((r) => {
            if (r.picked) {
                pickedN++; pickedArr += r.arr || 0;
                if (r.cls === 'HI') hi += r.arr || 0;
                else if (r.cls === 'MD') md += r.arr || 0;
            }
        });
        return { pickedN, pickedArr, call: (hi * this.wHi) / 100 + (md * this.wMed) / 100 };
    }
    get currentTotals() { const t = this.totals(this.currentRows); return { n: t.pickedN, arr: this.money(t.pickedArr), call: this.money(t.call) }; }
    get nextTotals() { const t = this.totals(this.nextRows); return { n: t.pickedN, arr: this.money(t.pickedArr), call: this.money(t.call) }; }

    get summary() {
        const a = this.totals(this.currentRows);
        const b = this.totals(this.nextRows);
        let hi = 0, md = 0, ex = 0;
        this.currentRows.forEach((r) => { if (r.cls === 'HI') hi++; else if (r.cls === 'MD') md++; else ex++; });
        return {
            teamSize: this.teamSize, dealCount: this.deals.length,
            currentCall: this.money(a.call), nextCall: this.money(b.call),
            combined: this.money(a.call + b.call), hi, md, ex, qA: this.qLabelA, qB: this.qLabelB
        };
    }

    get pullRows() {
        const byId = {};
        this.deals.forEach((d) => { byId[d.id] = d; });
        return Object.keys(PULL).map((id) => {
            const p = PULL[id];
            const d = byId[id];
            return {
                id, url: SFBASE + id, target: p[0], targetPill: 'pill ' + (p[0] === 'Current' ? 'p-com' : 'p-bc'),
                caseFor: p[1], caseAgainst: p[2],
                account: d ? d.account : '(not in the current window)',
                arrFmt: d ? this.money(d.arr) : '-'
            };
        });
    }

    get tabs() { return TABS.map((t) => ({ id: t.id, label: t.label, cls: this.activeTab === t.id ? 'on' : '' })); }
    get isSummary() { return this.activeTab === 't1'; }
    get isCurrent() { return this.activeTab === 't2'; }
    get isNext() { return this.activeTab === 't3'; }
    get isPull() { return this.activeTab === 't4'; }
    get hasData() { return this.deals && this.deals.length > 0; }
    get noData() { return !this.loading && !this.error && !this.hasData; }
    get statusText() { return this.hasData ? this.deals.length + ' open opps \u00b7 ' + this.teamSize + ' AEs' : ''; }

    handleTab(e) { this.activeTab = e.currentTarget.dataset.t; }
    handlePick(e) {
        const id = e.currentTarget.dataset.id;
        const d = this.deals.find((x) => x.id === id);
        const cls = this.clsOf(d);
        const def = cls === 'HI' || cls === 'MD';
        const v = e.currentTarget.checked;
        if (v === def) delete this.pickDev[id]; else this.pickDev[id] = v;
        this.pickDev = { ...this.pickDev };
    }
    handleClass(e) {
        const id = e.currentTarget.dataset.id;
        const v = e.detail ? e.detail.value : e.target.value;
        const d = this.deals.find((x) => x.id === id);
        if (v === d.klass && !SEED[id]) delete this.overrides[id];
        else this.overrides[id] = [v, this.overrides[id] ? this.overrides[id][1] : 'Manual override'];
        this.overrides = { ...this.overrides };
    }
    handleWHi(e) { this.wHi = Number(e.target.value) || 0; }
    handleWMed(e) { this.wMed = Number(e.target.value) || 0; }
    handleWPull(e) { this.wPull = Number(e.target.value) || 0; }
    reset() {
        this.overrides = { ...SEED };
        this.pickDev = {};
        this.wHi = 85; this.wMed = 30; this.wPull = 20;
    }
}
