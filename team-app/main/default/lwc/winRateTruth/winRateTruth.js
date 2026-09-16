import { LightningElement } from 'lwc';
import getPage from '@salesforce/apex/CockpitWinRateController.getPage';

export default class WinRateTruth extends LightningElement {
    loading = false;
    error;
    page;
    directorId = null;
    teamMode = 'my';
    productType = 'BUDGET';
    sizeBand = 'ALL';
    loadedOnce = false;
    showMeaning = false;

    handleScope(e) {
        const d = e.detail || {};
        this.directorId = d.directorId || null;
        this.teamMode = d.teamMode || 'my';
        this.productType = d.productType || 'BUDGET';
        this.sizeBand = d.sizeBand || 'ALL';
        this.showMeaning = false;
        this.refresh();
    }

    toggleMeaning() {
        this.showMeaning = !this.showMeaning;
    }

    refresh() {
        this.loading = true;
        this.error = undefined;
        getPage({
            directorId: this.directorId,
            teamMode: this.teamMode,
            productType: this.productType,
            sizeBand: this.sizeBand
        })
            .then((p) => {
                this.page = p;
                this.loadedOnce = true;
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || e.message || 'Could not load win rate truth.';
            })
            .finally(() => { this.loading = false; });
    }

    get emptyMessage() { return this.page && this.page.emptyMessage; }
    get hasRows() { return this.page && this.page.rows && this.page.rows.length > 0; }
    get captions() { return (this.page && this.page.captions) || []; }
    get ghostedConvention() { return this.page && this.page.ghostedConvention; }
    get scopeCaption() { return this.page && this.page.scopeCaption; }
    get meaning() { return this.page && this.page.meaning; }
    get meaningSections() { return (this.page && this.page.meaningSections) || []; }
    get closeMix() {
        return ((this.page && this.page.closeMix) || []).map((m) => ({
            cohortKey: m.cohortKey,
            label: m.label,
            won: m.won,
            lost: m.lost,
            share: this.pct(m.share)
        }));
    }
    get hasCloseMix() { return this.closeMix.length > 0; }
    get snapshotAsOf() {
        return this.page && this.page.snapshotAsOf
            ? `Latest nightly snapshot for this director: ${this.page.snapshotAsOf}`
            : 'No nightly snapshot yet for this director (live compute).';
    }
    get cycleCaption() {
        const p50 = this.page && this.page.p50Days != null ? this.page.p50Days : '—';
        const p75 = this.page && this.page.p75Days != null ? this.page.p75Days : '—';
        const lag = this.page && this.page.cycleLagQuarters != null ? this.page.cycleLagQuarters : '—';
        const matched = this.page && this.page.matchedCohortLabel ? this.page.matchedCohortLabel : '—';
        return `This product’s SQL→close cycle: median ${p50} days (~${lag} quarters), three-quarters done by ${p75} days. Deals closing this quarter map to SQL vintage ${matched}. Grey rows are still inside that cycle; samples under 15 qualified are directional.`;
    }
    get purgeSilent() { return this.page ? this.page.purgeSilentCount : 0; }
    get purgeDump() { return this.page ? this.page.purgeDumpCount : 0; }
    get unmapped() { return (this.page && this.page.unmappedReasons) || []; }
    get hasUnmapped() { return this.unmapped.length > 0; }

    get headlines() {
        const h = this.page && this.page.headlines;
        if (!h) return [];
        const matched = h.matchedLabel || 'matched vintage';
        return [
            {
                key: 'tq',
                lab: 'This-quarter close rate',
                val: this.pct(h.thisQuarterCloseRate),
                note: `${h.thisQuarterWon || 0} won / ${h.thisQuarterLost || 0} lost — close-date mix, not a cohort`,
                cls: 'card'
            },
            {
                key: 'mc',
                lab: `Matched contested · ${matched}`,
                val: this.pct(h.matchedContestedWR),
                note: `Won / (won + worked) on the SQL vintage due to close now`,
                cls: 'card hero'
            },
            {
                key: 'mq',
                lab: `Matched qualified / created · ${matched}`,
                val: this.pct(h.matchedQualYield),
                note: 'Funnel on that same vintage',
                cls: 'card'
            },
            {
                key: 'dx',
                lab: 'The read',
                val: this.diagnosisLabel(h.diagnosis),
                note: this.diagnosisNote(h.diagnosis),
                cls: this.diagnosisClass(h.diagnosis)
            }
        ];
    }

    diagnosisLabel(code) {
        if (code === 'FUNNEL') return 'Top of funnel';
        if (code === 'EXECUTION') return 'Sales execution';
        if (code === 'BOTH') return 'Funnel + execution';
        if (code === 'HEALTHY') return 'Neither leak';
        return 'Too thin to call';
    }
    diagnosisNote(code) {
        if (code === 'FUNNEL') return 'Qualified volume or yield is the constraint';
        if (code === 'EXECUTION') return 'Real contests on the matched vintage are losing';
        if (code === 'BOTH') return 'Not enough real pipeline, and the pipeline that is real is losing';
        if (code === 'HEALTHY') return 'Yield and contested on the matched vintage are holding';
        return 'Matched vintage does not yet have enough at-bats';
    }
    diagnosisClass(code) {
        if (code === 'HEALTHY') return 'card hero';
        if (code === 'FUNNEL' || code === 'EXECUTION' || code === 'BOTH') return 'card warn';
        return 'card';
    }

    get rows() {
        return ((this.page && this.page.rows) || []).map((r) => ({
            key: r.cohortKey,
            label: r.label,
            created: r.created,
            qualified: r.qualified,
            won: r.won,
            worked: r.worked,
            neverReal: r.neverReal,
            ghosted: r.ghosted,
            stillOpen: r.stillOpen,
            qualYield: this.pct(r.qualYield),
            contestedWR: this.pct(r.contestedWR),
            closureBased: this.pct(r.closureBased),
            distortion: this.pp(r.distortion),
            rowClass: this.rowClass(r),
            badge: this.badge(r)
        }));
    }

    rowClass(r) {
        const bits = [];
        if (r.mature === false) bits.push('immature');
        if (r.thinSample) bits.push('thin');
        if (r.headline) bits.push('headline');
        return bits.join(' ');
    }
    badge(r) {
        const bits = [];
        if (r.mature === false) bits.push('Immature');
        if (r.thinSample) bits.push('Directional');
        return bits.join(' · ');
    }

    pct(n) {
        if (n === null || n === undefined || Number.isNaN(n)) return '—';
        return (n * 100).toFixed(1) + '%';
    }
    pp(n) {
        if (n === null || n === undefined || Number.isNaN(n)) return '—';
        const pts = (n * 100).toFixed(1);
        return (n > 0 ? '+' : '') + pts + ' pts';
    }
}