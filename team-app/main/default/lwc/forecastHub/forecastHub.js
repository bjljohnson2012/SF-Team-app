import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { loadScript } from 'lightning/platformResourceLoader';
import CHARTJS from '@salesforce/resourceUrl/chartjs';
import load from '@salesforce/apex/CockpitForecastController.load';
import getCreatedPipeline from '@salesforce/apex/CockpitForecastController.getCreatedPipeline';
import getConversion from '@salesforce/apex/CockpitForecastController.getConversion';
import getWinRateTruth from '@salesforce/apex/CockpitForecastController.getWinRateTruth';
import getAeConversion from '@salesforce/apex/CockpitForecastController.getAeConversion';
import getProblems from '@salesforce/apex/CockpitForecastController.getProblems';
import getClosedWon from '@salesforce/apex/CockpitForecastController.getClosedWon';
import setInCall from '@salesforce/apex/CockpitForecastController.setInCall';
import setOverride from '@salesforce/apex/CockpitForecastController.setOverride';
import applyDefaultPicks from '@salesforce/apex/CockpitForecastController.applyDefaultPicks';
import analyzePerformance from '@salesforce/apex/CockpitForecastController.analyzePerformance';

const SFBASE = 'https://euna.my.salesforce.com/';

const SEED = {
    '006OL00000aPCqrYAG': ['HI', 'Verbal Win, pricing approved, MEDDPICC 8/8, legal negotiation booked.'],
    '006OL00000fNF1zYAG': ['HI', 'Signature Pending. Order form and SOW out for Mayor signature.'],
    '006OL00000d3KlJYAU': ['HI', 'Verbal Win, COI requested, signature authority confirmed.'],
    '006OL00000i2VjmYAE': ['HI', 'Verbal Win. Buyer holds order form, SOW, W9 and COI.'],
    '006OL00000iLE9vYAG': ['HI', 'Signature Pending on a Judge Executive approval.'],
    '006OL00000Zl1ZCYAZ': ['MD', 'Order form, EULA, SOW and security questionnaire in flight.'],
    '006OL00000cz8MAYAY': ['MD', 'Vendor of choice per the onsite, beat OpenGov on integration.'],
    '006OL00000csyxNYAQ': ['MD', 'Inside an existing Grants agreement; SE demo booked.'],
    '006OL00000Nz2UHYAZ': ['EX', '11 close-date pushes, silent since Jun 26.'],
    '006OL00000QiagjYAB': ['EX', '11 pushes, quote expired, buyer retired.'],
    '006OL00000ccN8zYAE': ['EX', '56 days silent on a Jun 16 proposal.']
};
const PULL = {
    '006OL00000kpQZ3YAM': ['Current', 'Budget locks mid-September; close sits on the wrong side of the funding gate. MEDDPICC 8/8, pricing approved.', 'Single-threaded, quiet 19 days. CFO never engaged.'],
    '006OL00000eVB6dYAG': ['Current', 'Verbal Win, Commit, MEDDPICC 8/8. Champion is also the economic buyer.', '6 pushes. Next step unchanged since Jun 29.'],
    '006OL00000lweYHYAY': ['Current', 'Live RFP with hard dates. Largest single swing from next quarter.', 'Conditional. MEDDPICC 0/8. Award cycles run 60-90 days.'],
    '006OL00000jftY5YAI': ['Next', 'Pricing approved, MEDDPICC 7/8. Decision process implies a Q4 close.', 'Already pushed once. Springbrook competing.'],
    '006OL00000kXEjFYAW': ['Next', 'Close sits one day outside the quarter. Zero pushes. Real week-over-week progression.', 'Alignment stage, MEDDPICC 0/8, OpenGov competing.'],
    '006OL00000Y88JNYAZ': ['Next', 'Verbal Win, Commit, MEDDPICC 8/8. SOW, EULA and DPA sent.', 'Pricing still requires approval.']
};

const CLS_META = { HI: ['p-hi', 'Include-High'], MD: ['p-med', 'Include-Med'], EX: ['p-ex', 'Exclude'] };
const BAND_META = { 'Commit': 'p-com', 'Most Likely': 'p-ml', 'Best Case': 'p-bc', 'Pipeline': 'p-pipe', 'Omitted': 'p-om' };
const ROOT_LABELS = { QUAL: 'Qualification', ENGAGE: 'Champion / engagement', VALUE: 'Value articulation', FIT: 'Product fit', EB: 'Economic buyer access', COMP: 'Competitive displacement', TIMING: 'Entry timing', PAPER: 'Paper process', DUPE: 'Duplicate', UNMAPPED: 'Unmapped' };
const CLASS_CHIPS = [['ALL', 'All'], ['PICK', 'In call'], ['HI', 'High'], ['MD', 'Med'], ['EX', 'Exclude']];

const SECTIONS = [
    { id: 'forecast', label: 'Forecast', subs: [['summary', 'Call Summary'], ['current', 'Current Qtr'], ['next', 'Next Qtr'], ['pull', 'Pull-Ins'], ['hygiene', 'Hygiene & Risks']] },
    { id: 'pipeline', label: 'Pipeline', subs: [['created', 'Created'], ['open', 'Open'], ['won', 'Closed-Won']] },
    { id: 'conversion', label: 'Conversion Metrics', subs: [['win', 'Win Rate Truth'], ['ae', 'AE by AE'], ['problems', 'Problems']] }
];

export default class ForecastHub extends LightningElement {
    loading = true;
    error;
    deals = [];
    teamSize;
    qLabelA;
    qLabelB;
    aeNames = [];
    section = 'forecast';
    subForecast = 'summary';
    subPipeline = 'created';
    subConversion = 'win';
    wHi = 85; wMed = 30; wPull = 20;
    aeFilter = 'ALL';
    classFilter = 'ALL';
    createdRows = [];
    conversionRows = [];
    winRows = [];
    aeRows = [];
    problemRows = [];
    closedWonRows = [];
    wiredLoad;
    aiText;
    aiLoading = false;
    chartLoaded = false;
    charts = {};

    @wire(load) handle(result) {
        this.wiredLoad = result; this.loading = false;
        if (result.data) {
            this.deals = result.data.deals || [];
            this.teamSize = result.data.teamSize;
            this.qLabelA = result.data.qLabelA; this.qLabelB = result.data.qLabelB;
            this.aeNames = result.data.aeNames || []; this.error = undefined;
        } else if (result.error) { this.error = this.msg(result.error); }
    }
    @wire(getCreatedPipeline) wCP({ data }) { if (data) this.createdRows = data; }
    @wire(getConversion) wCV({ data }) { if (data) this.conversionRows = data; }
    @wire(getWinRateTruth) wWR({ data }) { if (data) this.winRows = data; }
    @wire(getAeConversion) wAE({ data }) { if (data) this.aeRows = data; }
    @wire(getProblems) wPB({ data }) { if (data) this.problemRows = data; }
    @wire(getClosedWon) wCW({ data }) { if (data) this.closedWonRows = data; }

    renderedCallback() {
        if (!this.chartLoaded) {
            loadScript(this, CHARTJS)
                .then(() => { this.chartLoaded = true; this.drawCharts(); })
                .catch(() => { /* charts degrade; tables still work */ });
            return;
        }
        this.drawCharts();
    }

    money(n) { return (n == null || isNaN(n)) ? '$0' : '$' + Math.round(n).toLocaleString('en-US'); }
    pctFmt(n) { return (n == null || isNaN(n)) ? '-' : (n * 100).toFixed(1) + '%'; }
    msg(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.'; }

    clsOf(d) { return d.overrideCls || (SEED[d.id] ? SEED[d.id][0] : d.klass); }
    noteOf(d) { return d.overrideNote || (SEED[d.id] ? SEED[d.id][1] : null); }

    decorate(d) {
        const cls = this.clsOf(d);
        const meta = CLS_META[cls] || CLS_META.EX;
        const note = this.noteOf(d);
        const picked = d.inCall === true;
        return {
            id: d.id, account: d.account, ae: d.ae, stage: d.stage, score: d.score,
            arr: d.arr, arrFmt: this.money(d.arr), reason: d.reason, note, hasNote: !!note,
            url: SFBASE + d.id, cls, clsPill: 'pill ' + meta[0], selClass: 'clssel v-' + cls,
            clsOptions: ['HI', 'MD', 'EX'].map((v) => ({ value: v, label: CLS_META[v][1], selected: v === cls })),
            band: d.band || '-', bandPill: 'pill ' + (BAND_META[d.band] || 'p-pipe'),
            picked, rowClass: picked ? 'picked' : '',
            pushes: d.pushes, closeDate: d.closeDate
        };
    }
    passesFilter(row) {
        if (this.aeFilter !== 'ALL' && row.ae !== this.aeFilter) return false;
        if (this.classFilter === 'ALL') return true;
        if (this.classFilter === 'PICK') return row.picked;
        return row.cls === this.classFilter;
    }
    rowsFor(bucket) {
        return this.deals.filter((d) => d.bucket === bucket).sort((a, b) => (b.arr || 0) - (a.arr || 0))
            .map((d) => this.decorate(d)).filter((r) => this.passesFilter(r));
    }
    get currentRows() { return this.rowsFor('A'); }
    get nextRows() { return this.rowsFor('B'); }

    totals(rows) {
        let hi = 0, md = 0, arr = 0, n = 0;
        rows.forEach((r) => { if (r.picked) { n++; arr += r.arr || 0; if (r.cls === 'HI') hi += r.arr || 0; else if (r.cls === 'MD') md += r.arr || 0; } });
        return { n, arr, call: (hi * this.wHi) / 100 + (md * this.wMed) / 100 };
    }
    get currentTotals() { const t = this.totals(this.currentRows); return { n: t.n, arr: this.money(t.arr), call: this.money(t.call) }; }
    get nextTotals() { const t = this.totals(this.nextRows); return { n: t.n, arr: this.money(t.arr), call: this.money(t.call) }; }
    get summary() {
        const a = this.totals(this.currentRows), b = this.totals(this.nextRows);
        let hi = 0, md = 0, ex = 0;
        this.currentRows.forEach((r) => { if (r.cls === 'HI') hi++; else if (r.cls === 'MD') md++; else ex++; });
        return { teamSize: this.teamSize, dealCount: this.deals.length, currentCall: this.money(a.call),
            nextCall: this.money(b.call), combined: this.money(a.call + b.call), hi, md, ex, qA: this.qLabelA, qB: this.qLabelB };
    }
    get pullRows() {
        const byId = {}; this.deals.forEach((d) => { byId[d.id] = d; });
        return Object.keys(PULL).map((id) => {
            const p = PULL[id]; const d = byId[id];
            return { id, url: SFBASE + id, target: p[0], targetPill: 'pill ' + (p[0] === 'Current' ? 'p-com' : 'p-bc'),
                caseFor: p[1], caseAgainst: p[2], account: d ? d.account : '(not in the current window)', arrFmt: d ? this.money(d.arr) : '-' };
        });
    }
    // Hygiene: risk flags on the open book
    get hygieneRows() {
        return this.deals.map((d) => this.decorate(d)).map((r) => {
            const flags = [];
            if (!r.arr || r.arr <= 0) flags.push('zero ARR');
            if (r.pushes >= 6) flags.push(r.pushes + ' pushes');
            if (r.reason && r.reason.indexOf('silent') >= 0) flags.push('silent');
            if (r.reason && r.reason.indexOf('no next step') >= 0) flags.push('no next step');
            if (r.reason && r.reason.indexOf('not SQL') >= 0) flags.push('not SQL-qualified');
            return { ...r, flags: flags.join(', '), risky: flags.length > 0 };
        }).filter((r) => r.risky).sort((a, b) => (b.arr || 0) - (a.arr || 0));
    }

    // analytics displays
    get createdDisplay() { return this.createdRows.map((r) => ({ label: r.label, bookedArr: this.money(r.bookedArr), createdArr: this.money(r.createdArr), bookedN: r.bookedN, createdN: r.createdN })); }
    get conversionDisplay() { return this.conversionRows.map((r) => ({ band: r.band, bandPill: 'pill ' + (BAND_META[r.band] || 'p-pipe'), total: r.total, won: r.won, winRate: this.pctFmt(r.winRate), totalArr: this.money(r.totalArr), wonArr: this.money(r.wonArr), winRateArr: this.pctFmt(r.winRateArr) })); }
    get winDisplay() { return this.winRows.map((r) => ({ label: r.label, created: r.created, won: r.won, worked: r.worked, never: r.never, stillOpen: r.stillOpen, cohortWR: this.pctFmt(r.cohortWR), resolvedWR: this.pctFmt(r.resolvedWR), contestedWR: this.pctFmt(r.contestedWR), qualYield: this.pctFmt(r.qualYield), rowClass: r.label.indexOf('Team') === 0 ? 'teamrow' : '' })); }
    get aeDisplay() { return this.aeRows.map((r) => ({ ae: r.ae, won: r.won, lost: r.lost, winRate: this.pctFmt(r.winRate), wonArr: this.money(r.wonArr), lostArr: this.money(r.lostArr), topRoot: ROOT_LABELS[r.topRoot] || (r.topRoot || '-') })); }
    get problemDisplay() { return this.problemRows.map((r) => ({ reason: r.reason, count: r.count, root: ROOT_LABELS[r.root] || r.root, rowClass: r.mapped ? '' : 'teamrow' })); }
    get closedWonDisplay() { return this.closedWonRows.map((d) => ({ id: d.id, url: SFBASE + d.id, account: d.account, ae: d.ae, arrFmt: this.money(d.arr), closeDate: d.closeDate })); }

    // nav
    get sections() { return SECTIONS.map((s) => ({ id: s.id, label: s.label, cls: this.section === s.id ? 'on' : '' })); }
    get subTabs() {
        const s = SECTIONS.find((x) => x.id === this.section);
        const active = this.activeSub;
        return s.subs.map((t) => ({ id: t[0], label: t[1], cls: active === t[0] ? 'on' : '' }));
    }
    get activeSub() { return this.section === 'forecast' ? this.subForecast : (this.section === 'pipeline' ? this.subPipeline : this.subConversion); }

    get isForecast() { return this.section === 'forecast'; }
    get isPipeline() { return this.section === 'pipeline'; }
    get isConversion() { return this.section === 'conversion'; }
    get vSummary() { return this.isForecast && this.subForecast === 'summary'; }
    get vCurrent() { return this.isForecast && this.subForecast === 'current'; }
    get vNext() { return this.isForecast && this.subForecast === 'next'; }
    get vPull() { return this.isForecast && this.subForecast === 'pull'; }
    get vHygiene() { return this.isForecast && this.subForecast === 'hygiene'; }
    get vCreated() { return this.isPipeline && this.subPipeline === 'created'; }
    get vOpen() { return this.isPipeline && this.subPipeline === 'open'; }
    get vWon() { return this.isPipeline && this.subPipeline === 'won'; }
    get vWin() { return this.isConversion && this.subConversion === 'win'; }
    get vAe() { return this.isConversion && this.subConversion === 'ae'; }
    get vProblems() { return this.isConversion && this.subConversion === 'problems'; }
    get showFilters() { return this.vCurrent || this.vNext; }

    get aeOptions() { return [{ v: 'ALL', label: 'All AEs', sel: this.aeFilter === 'ALL' }].concat(this.aeNames.map((n) => ({ v: n, label: n, sel: this.aeFilter === n }))); }
    get classChips() { return CLASS_CHIPS.map((c) => ({ v: c[0], label: c[1], cls: this.classFilter === c[0] ? 'on' : '' })); }
    get hasData() { return this.deals && this.deals.length > 0; }
    get noData() { return !this.loading && !this.error && !this.hasData; }
    get statusText() { return this.hasData ? this.deals.length + ' open opps \u00b7 ' + this.teamSize + ' AEs' : ''; }
    get hasCreated() { return this.createdDisplay.length > 0; }
    get hasConversion() { return this.conversionDisplay.length > 0; }
    get hasWin() { return this.winDisplay.length > 0; }
    get hasAe() { return this.aeDisplay.length > 0; }
    get hasProblems() { return this.problemDisplay.length > 0; }
    get hasWon() { return this.closedWonDisplay.length > 0; }
    get hasHygiene() { return this.hygieneRows.length > 0; }
    get aiLabel() { return this.isConversion ? 'Ask Claude: where is my team losing?' : (this.isPipeline ? 'Ask Claude to read my pipeline' : 'Ask Claude to critique my call'); }

    // events
    handleSection(e) { this.section = e.currentTarget.dataset.s; this.aiText = undefined; }
    handleSub(e) {
        const v = e.currentTarget.dataset.t;
        if (this.section === 'forecast') this.subForecast = v;
        else if (this.section === 'pipeline') this.subPipeline = v;
        else this.subConversion = v;
    }
    handleAe(e) { this.aeFilter = e.target.value; }
    handleChip(e) { this.classFilter = e.currentTarget.dataset.v; }
    handleWHi(e) { this.wHi = Number(e.target.value) || 0; }
    handleWMed(e) { this.wMed = Number(e.target.value) || 0; }
    handleWPull(e) { this.wPull = Number(e.target.value) || 0; }

    handlePick(e) {
        const id = e.currentTarget.dataset.id;
        setInCall({ opportunityId: id, included: e.currentTarget.checked })
            .then(() => refreshApex(this.wiredLoad)).catch((err) => { this.error = this.msg(err); });
    }
    handleClass(e) {
        const id = e.currentTarget.dataset.id; const klass = e.target.value;
        const d = this.deals.find((x) => x.id === id);
        const note = (SEED[id] && SEED[id][0] === klass) ? SEED[id][1] : (d && d.overrideNote) || 'Director override';
        setOverride({ opportunityId: id, klass, note })
            .then(() => refreshApex(this.wiredLoad)).catch((err) => { this.error = this.msg(err); });
    }
    applyDefaults() {
        applyDefaultPicks({ bucket: this.vNext ? 'B' : 'A' })
            .then(() => refreshApex(this.wiredLoad)).catch((err) => { this.error = this.msg(err); });
    }
    askAi() {
        this.aiText = undefined; this.aiLoading = true;
        analyzePerformance({ area: this.section })
            .then((res) => { this.aiText = res; })
            .catch((err) => { this.aiText = 'AI error: ' + this.msg(err); })
            .finally(() => { this.aiLoading = false; });
    }

    // ---- charts ----
    drawCharts() {
        if (!this.chartLoaded || !window.Chart) return;
        if (this.vCreated) this.barChart('cvCreated', this.createdRows.map((r) => r.label),
            [{ label: 'Created ARR', data: this.createdRows.map((r) => r.createdArr || 0), backgroundColor: '#4A32C4' },
             { label: 'Booked ARR', data: this.createdRows.map((r) => r.bookedArr || 0), backgroundColor: '#FF6E14' }]);
        if (this.vOpen) this.doughnut('cvOpen', this.openBreakdown());
        if (this.vWin) this.barChart('cvWin', this.conversionRows.map((r) => r.band),
            [{ label: 'Win rate', data: this.conversionRows.map((r) => Math.round((r.winRate || 0) * 1000) / 10), backgroundColor: '#00A9E0' }]);
        if (this.vAe) this.barChart('cvAe', this.aeRows.map((r) => r.ae),
            [{ label: 'Win rate %', data: this.aeRows.map((r) => Math.round((r.winRate || 0) * 1000) / 10), backgroundColor: '#CB007B' }]);
    }
    openBreakdown() {
        let hi = 0, md = 0, ex = 0;
        this.deals.forEach((d) => { const c = this.clsOf(d); const a = d.arr || 0; if (c === 'HI') hi += a; else if (c === 'MD') md += a; else ex += a; });
        return { labels: ['Include-High', 'Include-Med', 'Exclude'], data: [Math.round(hi), Math.round(md), Math.round(ex)], colors: ['#0F7B3E', '#B45309', '#B00020'] };
    }
    barChart(ref, labels, datasets) {
        const canvas = this.template.querySelector('canvas[data-id="' + ref + '"]');
        if (!canvas) return;
        if (this.charts[ref]) this.charts[ref].destroy();
        this.charts[ref] = new window.Chart(canvas, {
            type: 'bar', data: { labels, datasets },
            options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: datasets.length > 1 } } }
        });
    }
    doughnut(ref, b) {
        const canvas = this.template.querySelector('canvas[data-id="' + ref + '"]');
        if (!canvas) return;
        if (this.charts[ref]) this.charts[ref].destroy();
        this.charts[ref] = new window.Chart(canvas, {
            type: 'doughnut', data: { labels: b.labels, datasets: [{ data: b.data, backgroundColor: b.colors }] },
            options: { responsive: true, maintainAspectRatio: false }
        });
    }
}
