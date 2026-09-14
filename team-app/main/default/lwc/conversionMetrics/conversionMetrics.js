import { LightningElement, api, wire } from 'lwc';
import load from '@salesforce/apex/CockpitConversionController.load';
import getScopeOptions from '@salesforce/apex/CockpitConversionController.getScopeOptions';

const SESSION_KEY = 'gtmScopeFilters';
const DEFAULT_SCOPE = { directorId: null, teamMode: 'mine', productType: '', sizeBand: 'ALL' };

export default class ConversionMetrics extends LightningElement {
    @api embedded = false;
    directorId = null;
    teamMode = 'mine';
    productType = '';
    sizeBand = 'ALL';
    options = { directors: [], productTypes: [], sizeBands: [] };
    page;
    error;
    loading = true;

    connectedCallback() {
        this.restoreScope();
    }

    @wire(getScopeOptions)
    wiredOptions({ data, error }) {
        if (data) this.options = data;
        else if (error) this.error = this.msg(error);
    }

    @wire(load, {
        directorId: '$directorId',
        teamMode: '$teamMode',
        productType: '$productType',
        sizeBand: '$sizeBand'
    })
    wiredLoad(result) {
        this.loading = false;
        if (result.data) {
            this.page = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this.msg(result.error);
        }
    }

    restoreScope() {
        try {
            const raw = sessionStorage.getItem(SESSION_KEY);
            if (!raw) return;
            const s = Object.assign({}, DEFAULT_SCOPE, JSON.parse(raw));
            this.directorId = s.directorId || null;
            this.teamMode = s.teamMode || 'mine';
            this.productType = s.productType || '';
            this.sizeBand = s.sizeBand || 'ALL';
        } catch (e) {
            /* session is best-effort */
        }
    }

    persistScope() {
        const detail = {
            directorId: this.directorId,
            teamMode: this.teamMode,
            productType: this.productType,
            sizeBand: this.sizeBand
        };
        try {
            sessionStorage.setItem(SESSION_KEY, JSON.stringify(detail));
        } catch (e) {
            /* ignore quota */
        }
        return detail;
    }

    handleScopeChange(event) {
        const d = (event && event.detail) || {};
        if (d.directorId !== undefined) this.directorId = d.directorId || null;
        if (d.teamMode !== undefined) this.teamMode = d.teamMode || 'mine';
        if (d.productType !== undefined) this.productType = d.productType || '';
        if (d.sizeBand !== undefined) this.sizeBand = d.sizeBand || 'ALL';
        this.persistScope();
    }

    handleDirector(event) {
        const v = event.target.value;
        if (v === 'mine') {
            this.teamMode = 'mine';
            this.directorId = null;
        } else {
            this.teamMode = 'director';
            this.directorId = v;
        }
        this.emitScope();
    }

    handleProduct(event) {
        this.productType = event.target.value || '';
        this.emitScope();
    }

    handleSize(event) {
        this.sizeBand = event.target.value || 'ALL';
        this.emitScope();
    }

    emitScope() {
        const detail = this.persistScope();
        this.dispatchEvent(new CustomEvent('scopechange', { detail, bubbles: true, composed: true }));
    }

    get showChrome() {
        return this.embedded !== true && this.embedded !== 'true' && this.embedded !== '';
    }

    get directorValue() {
        return this.teamMode === 'director' && this.directorId ? this.directorId : 'mine';
    }
    get directorOptions() {
        return (this.options.directors || []).map((o) => ({
            value: o.value,
            label: o.label,
            selected: o.value === this.directorValue
        }));
    }
    get productOptions() {
        return (this.options.productTypes || []).map((o) => ({
            value: o.value,
            key: o.value || 'all-products',
            label: o.label,
            selected: (o.value || '') === (this.productType || '')
        }));
    }
    get sizeOptions() {
        return (this.options.sizeBands || []).map((o) => ({
            value: o.value,
            label: o.label,
            selected: o.value === this.sizeBand
        }));
    }

    get scopeCaption() { return this.page && this.page.scope ? this.page.scope.caption : ''; }
    get emptyScope() { return this.page && this.page.scope && this.page.scope.emptyScope; }
    get emptyMessage() { return this.emptyScope ? this.page.scope.emptyMessage : ''; }
    get hasPage() { return this.page && !this.emptyScope && !this.loading && !this.error; }
    get convention() { return this.page ? this.page.conventionCaption : ''; }
    get writerCaption() { return this.page ? this.page.bandWriterCaption : ''; }
    get lossFloor() { return this.page ? this.page.lossReasonFloorCaption : ''; }
    get interpretation() { return this.page ? this.page.bandInterpretation : ''; }
    get hasInterpretation() { return !!this.interpretation; }
    get meddpiccNote() {
        if (!this.page) return '';
        return this.page.meddpiccAvailable
            ? 'MEDDPICC is the materialized Cockpit_MEDDPICC__c score, not the eight rich-text sources.'
            : 'Cockpit_MEDDPICC__c is not in the org yet — MEDDPICC columns stay a dash. This page does not read the eight rich-text fields.';
    }
    get medianCycle() {
        return this.page && this.page.medianCycleDays != null ? this.page.medianCycleDays + ' days' : '—';
    }
    get closedInWindow() { return this.page && this.page.closedInWindow != null ? this.page.closedInWindow : 0; }

    get bandRows() {
        return (this.page && this.page.bands ? this.page.bands : []).map((r) => ({
            band: r.band,
            pill: 'pill ' + this.bandClass(r.band),
            won: r.won,
            lost: r.lost,
            total: r.total,
            winRateCount: this.pct(r.winRateCount),
            arrWon: this.money(r.arrWon),
            arrTotal: this.money(r.arrTotal),
            winRateArr: this.pct(r.winRateArr),
            gapClass: r.largeDealsLose ? 'gap-warn' : ''
        }));
    }

    get commitRows() {
        return (this.page && this.page.commitAccuracy ? this.page.commitAccuracy : []).map((r) => ({
            ownerId: r.ownerId,
            aeName: r.aeName,
            won: r.won,
            commitCloses: r.commitCloses,
            rate: this.pct(r.rate),
            title: r.sampleTooltip || '',
            rowClass: r.flagged ? 'flag-row' : ''
        }));
    }

    get lossRows() {
        return (this.page && this.page.lossMatrix ? this.page.lossMatrix : []).map((r) => ({
            reason: r.reason,
            root: r.root,
            losses: r.losses,
            share: this.pct(r.share),
            rowClass: r.mapped ? '' : 'teamrow'
        }));
    }

    get overIndexRows() {
        return (this.page && this.page.overIndexed ? this.page.overIndexed : []).map((r) => ({
            key: r.ownerId + r.reason,
            aeName: r.aeName,
            reason: r.reason,
            root: r.root,
            losses: r.losses,
            share: this.pct(r.share),
            teamShare: this.pct(r.teamShare)
        }));
    }
    get hasOverIndex() { return this.overIndexRows.length > 0; }

    get liveRows() {
        return (this.page && this.page.liveBook ? this.page.liveBook : []).map((r) => ({
            ownerId: r.ownerId,
            aeName: r.aeName,
            openArr: this.money(r.openArr),
            dealCount: r.dealCount,
            avgMeddpicc: r.avgMeddpicc == null ? '—' : Number(r.avgMeddpicc).toFixed(1),
            shareBelow3: this.pct(r.shareBelow3),
            silentShare: this.pct(r.silentShare),
            nextStepShare: this.pct(r.nextStepShare),
            pushedShare: this.pct(r.pushedShare),
            aboveBestCaseShare: this.pct(r.aboveBestCaseShare),
            flags: (r.flags || []).join(', ') || '—',
            rowClass: r.flags && r.flags.length ? 'flag-row' : ''
        }));
    }

    bandClass(band) {
        if (band === 'Commit') return 'p-com';
        if (band === 'Most Likely') return 'p-ml';
        if (band === 'Best Case') return 'p-bc';
        if (band === 'Omitted') return 'p-om';
        if (band === 'Unbanded') return 'p-un';
        return 'p-pipe';
    }
    money(n) {
        return n == null || isNaN(n) ? '$0' : '$' + Math.round(Number(n)).toLocaleString('en-US');
    }
    pct(n) {
        return n == null || isNaN(n) ? '—' : (Number(n) * 100).toFixed(1) + '%';
    }
    msg(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
    }
}
