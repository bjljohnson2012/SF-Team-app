import { LightningElement } from 'lwc';
import getPage from '@salesforce/apex/CockpitWinRateController.getPage';

export default class WinRateTruth extends LightningElement {
    loading = false;
    error;
    page;
    directorId = null;
    teamMode = 'my';
    productType = 'ALL';
    sizeBand = 'ALL';
    loadedOnce = false;
    showMeaning = false;

    handleScope(e) {
        const d = e.detail || {};
        this.directorId = d.directorId || null;
        this.teamMode = d.teamMode || 'my';
        this.productType = d.productType || 'ALL';
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
    get snapshotAsOf() {
        return this.page && this.page.snapshotAsOf
            ? `Latest nightly snapshot for this director: ${this.page.snapshotAsOf}`
            : 'No nightly snapshot yet for this director (live compute).';
    }
    get cycleCaption() {
        const p50 = this.page && this.page.p50Days != null ? this.page.p50Days : '—';
        const p75 = this.page && this.page.p75Days != null ? this.page.p75Days : '—';
        return `SQL→close cycle on resolved deals: median ${p50} days, three-quarters done by ${p75} days. Immature vintages stay listed; headlines wait until quarter-end is past that cycle and skip samples under 15 qualified deals.`;
    }
    get purgeSilent() { return this.page ? this.page.purgeSilentCount : 0; }
    get purgeDump() { return this.page ? this.page.purgeDumpCount : 0; }
    get unmapped() { return (this.page && this.page.unmappedReasons) || []; }
    get hasUnmapped() { return this.unmapped.length > 0; }

    get headlines() {
        const h = this.page && this.page.headlines;
        if (!h) return [];
        return [
            { key: 'cb', lab: 'Won / (won + lost)', val: this.pct(h.closureBased), note: 'What reports quote — close-date, not conversion', cls: 'card' },
            { key: 'cwr', lab: 'Contested win rate', val: this.pct(h.contestedWR), note: 'Won / (won + worked) — selling ability', cls: 'card hero' },
            { key: 'qy', lab: 'Qualified / created', val: this.pct(h.qualYield), note: 'Opened this quarter that reached SQL', cls: 'card' },
            { key: 'di', lab: 'Distortion', val: this.pp(h.distortion), note: 'Contested minus won/(won+lost)', cls: 'card warn' }
        ];
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
