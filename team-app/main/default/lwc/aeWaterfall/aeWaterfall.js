import { LightningElement } from 'lwc';
import load from '@salesforce/apex/WaterfallController.load';

export default class AeWaterfall extends LightningElement {
    loading = true;
    error;
    page;
    directorId;
    teamMode = 'my';
    productType = 'ALL';
    sizeBand = 'ALL';
    req = 0;

    connectedCallback() {
        this.refresh();
    }

    handleScope(e) {
        const d = e.detail || {};
        this.directorId = d.directorId;
        this.teamMode = d.teamMode || 'my';
        this.productType = !d.productType || d.productType === 'ALL' ? 'ALL' : d.productType;
        this.sizeBand = !d.sizeBand || d.sizeBand === 'ALL' ? 'ALL' : d.sizeBand;
        this.refresh();
    }

    refresh() {
        const req = ++this.req;
        this.loading = true;
        this.error = undefined;
        load({
            directorId: this.directorId || null,
            teamMode: this.teamMode,
            productType: this.productType,
            sizeBand: this.sizeBand
        })
            .then((data) => { if (req === this.req) this.page = data; })
            .catch((err) => { if (req === this.req) this.error = this.msg(err); })
            .finally(() => { if (req === this.req) this.loading = false; });
    }

    msg(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.'; }
    pct(n) {
        if (n == null || isNaN(n)) return '—';
        return (Number(n) * 100).toFixed(1) + '%';
    }
    money(n) {
        if (n == null || isNaN(n)) return '—';
        return '$' + Math.round(Number(n)).toLocaleString('en-US');
    }
    num(n, d) {
        if (n == null || isNaN(n)) return '—';
        return Number(n).toFixed(d);
    }
    pill(v) {
        if (v === 'High') return 'pill high';
        if (v === 'Medium') return 'pill med';
        return 'pill low';
    }

    get scopeCaption() { return this.page && this.page.scopeCaption; }
    get emptyReason() { return this.page && this.page.emptyReason; }
    get teamCaption() { return this.page && this.page.teamCaption; }
    get periodLabel() { return this.page && this.page.periodLabel; }
    get createPeriodLabel() { return this.page && this.page.createPeriodLabel; }
    get hasRows() { return this.page && this.page.rows && this.page.rows.length > 0 && !this.emptyReason; }

    get cards() {
        if (!this.hasRows) return [];
        return this.page.rows.map((r) => ({
            ownerId: r.ownerId,
            name: r.name,
            sampleConfidence: r.sampleConfidence || 'Low',
            pillClass: this.pill(r.sampleConfidence),
            closedCount: r.closedCount || 0,
            winRateRaw: this.pct(r.winRateRaw),
            winRateBlended: this.pct(r.winRateBlended),
            aspRaw: this.money(r.aspRaw),
            aspBlended: this.money(r.aspBlended),
            cycle: r.cycleMedianDays == null ? '—' : Math.round(r.cycleMedianDays) + 'd',
            lands: r.landsQuarters == null ? '—' : 'Q+' + r.landsQuarters,
            qualRate: this.pct(r.qualRate),
            selfMix: this.pct(r.selfSourcedShare),
            connectRate: this.pct(r.connectRate),
            reqQo: this.num(r.closePlan && r.closePlan.qoNeeded, 1),
            have: r.haveQo == null ? 0 : r.haveQo,
            haveArr: this.money(r.haveArr),
            quota: this.money(r.quota),
            created: r.created == null ? 0 : r.created,
            dials: r.dials == null ? 0 : r.dials,
            connects: r.connects == null ? 0 : r.connects,
            emailsSent: r.emailsSent == null ? 0 : r.emailsSent,
            replies: r.replies == null ? 0 : r.replies,
            meetingsHeld: r.meetingsHeld == null ? 0 : r.meetingsHeld,
            activityIndicative: r.activityIndicative === true,
            activityComplete: this.pct(r.activityComplete),
            closePlan: this.decoratePlan(r.closePlan, 'locked'),
            createPlan: this.decoratePlan(r.createPlan, 'live')
        }));
    }

    decoratePlan(p, kind) {
        if (!p) return null;
        return {
            kindClass: 'plan ' + kind,
            periodLabel: p.periodLabel,
            lever: p.lever,
            rungs: (p.rungs || []).map((r, i) => ({
                key: p.kind + '-' + i,
                name: r.name,
                op: r.op,
                value: r.value,
                depth: String(r.depth == null ? 0 : r.depth),
                rungClass: 'rung' + (r.indicative ? ' hatch' : '')
            }))
        };
    }
}
