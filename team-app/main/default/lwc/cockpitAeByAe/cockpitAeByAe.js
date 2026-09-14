import { LightningElement } from 'lwc';
import loadComposition from '@salesforce/apex/CockpitAeController.loadComposition';

export default class CockpitAeByAe extends LightningElement {
    loading = true;
    error;
    payload;
    directorId;
    teamMode = 'mine';
    productType = 'ALL';
    sizeBand = 'ALL';

    handleScope(e) {
        const d = e.detail || {};
        this.directorId = d.directorId;
        this.teamMode = d.teamMode || 'mine';
        this.productType = d.productType || 'ALL';
        this.sizeBand = d.sizeBand || 'ALL';
        this.refresh();
    }

    refresh() {
        this.loading = true;
        this.error = undefined;
        loadComposition({
            directorId: this.directorId,
            teamMode: this.teamMode,
            productType: this.productType,
            sizeBand: this.sizeBand
        })
            .then((data) => { this.payload = data; })
            .catch((err) => { this.error = this.msg(err); })
            .finally(() => { this.loading = false; });
    }

    msg(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.'; }
    money(n) {
        if (n == null || isNaN(n)) return '$0';
        return '$' + Math.round(Number(n)).toLocaleString('en-US');
    }
    pct(n) {
        if (n == null || isNaN(n)) return '—';
        return (Number(n) * 100).toFixed(1) + '%';
    }
    cell(c) {
        return { deals: c && c.deals ? c.deals : 0, arr: this.money(c && c.arr), share: this.pct(c && c.share) };
    }
    decorateSlice(s) {
        if (!s) return null;
        return {
            label: s.label,
            showBooked: s.showBooked === true,
            booked: s.showBooked ? this.money(s.bookedArr) : null,
            bookedN: s.bookedN || 0,
            open: this.money(s.openArr),
            openN: s.openN || 0,
            holdover: this.money(s.holdoverArr),
            holdoverN: s.holdoverN || 0,
            evidence: this.money(s.evidenceCall),
            hi: this.money(s.includeHighArr) + ' · ' + (s.includeHighN || 0),
            md: this.money(s.includeMedArr) + ' · ' + (s.includeMedN || 0),
            ex: this.money(s.excludeArr) + ' · ' + (s.excludeN || 0),
            commit: this.cell(s.commitBand),
            mostLikely: this.cell(s.mostLikely),
            bestCase: this.cell(s.bestCase),
            pipeline: this.cell(s.pipeline),
            omitted: this.cell(s.omitted),
            unbanded: this.cell(s.unbanded)
        };
    }

    get emptyReason() { return this.payload && this.payload.emptyReason; }
    get classCaption() { return this.payload && this.payload.classCaption; }
    get classMissing() { return this.payload && this.payload.classMissing; }
    get hasRows() { return this.payload && this.payload.rows && this.payload.rows.length > 0 && !this.classMissing; }
    get scopeCaption() { return this.payload && this.payload.scopeCaption; }
    get qA() { return this.payload && this.payload.qLabelA; }
    get qB() { return this.payload && this.payload.qLabelB; }
    get weights() {
        if (!this.payload) return '';
        return 'Evidence call uses Include-High × ' + this.payload.weightHighPct
            + '% and Include-Med × ' + this.payload.weightMedPct + '%. Booked applies to the current quarter only.';
    }
    get teamWindow() { return this.payload ? this.decorateSlice(this.payload.teamWindow) : null; }
    get hasTeamWindow() { return this.teamWindow && this.teamWindow.openN > 0; }
    get aeCards() {
        if (!this.hasRows) return [];
        return this.payload.rows.map((r) => ({
            ownerId: r.ownerId,
            name: r.name,
            currentQ: this.decorateSlice(r.currentQ),
            nextQ: this.decorateSlice(r.nextQ),
            signals: r.signals || [],
            hasSignals: r.signals && r.signals.length > 0,
            cleanBook: r.cleanBook || 'Nothing cleared the evidence bar.'
        }));
    }
}
