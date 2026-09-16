import { LightningElement, track } from 'lwc';
import load from '@salesforce/apex/WaterfallController.load';
import savePlays from '@salesforce/apex/WaterfallController.savePlays';

const RATE_FIELDS = new Set(['winRate', 'qualRate', 'selfShare', 'oppsPerConnect', 'connectRate']);
/** UI data-field → PlayDraft property the cascade actually reads. */
const FIELD_PROP = {
    dials: 'dialsNeeded',
    dialsWeek: 'dialsNeeded',
    connects: 'connectsNeeded',
    connectRate: 'connectRate',
    oppsPerConnect: 'oppsPerConnect',
    selfShare: 'selfShare',
    oppsToCreate: 'oppsToCreate',
    qoNeeded: 'qoNeeded',
    qualRate: 'qualRate',
    winRate: 'winRate'
};
const PROJECT_FROM = {
    dials: 'dials',
    dialsWeek: 'dials',
    connects: 'connects',
    oppsToCreate: 'oppsToCreate',
    qoNeeded: 'qoNeeded'
};

export default class AeWaterfall extends LightningElement {
    loading = true;
    error;
    page;
    directorId;
    teamMode = 'my';
    productType = 'ALL';
    sizeBand = 'ALL';
    req = 0;
    plannerOwnerId;
    @track drafts = {};
    @track reasons = {};
    @track saveMsgs = {};
    @track saving = {};

    connectedCallback() {
        this.refresh();
    }

    handleScope(e) {
        const d = e.detail || {};
        this.directorId = d.directorId;
        this.teamMode = d.teamMode || 'my';
        this.productType = !d.productType || d.productType === 'ALL' ? 'ALL' : d.productType;
        this.sizeBand = !d.sizeBand || d.sizeBand === 'ALL' ? 'ALL' : d.sizeBand;
        this.drafts = {};
        this.reasons = {};
        this.saveMsgs = {};
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

    togglePlanner(e) {
        const id = e.currentTarget.dataset.owner;
        this.plannerOwnerId = this.plannerOwnerId === id ? null : id;
        if (this.plannerOwnerId && !this.drafts[id]) {
            const row = this.rowById(id);
            if (row) {
                this.drafts = { ...this.drafts, [id]: this.clone(row.planned || row.recommended) };
            }
        }
    }

    handlePlanField(e) {
        const id = e.target.dataset.owner;
        const field = e.target.dataset.field;
        const kind = e.target.dataset.kind;
        const row = this.rowById(id);
        if (!row || !field) return;
        const draft = this.clone(this.drafts[id] || row.planned || row.recommended);
        let n = e.target.value === '' ? null : Number(e.target.value);
        if (n != null && isNaN(n)) return;
        if (kind === 'pct' && n != null) n = n / 100;
        const prop = FIELD_PROP[field] || field;
        if (field === 'dialsWeek') {
            const weeks = this.remainingWeeks();
            draft.dialsNeeded = n == null ? null : (weeks > 0 ? n * weeks : n);
        } else {
            draft[prop] = n;
        }
        let edited = PROJECT_FROM[field] || 'rate';
        if (RATE_FIELDS.has(prop) && draft.editedField === 'dials') {
            edited = 'dials';
        }
        draft.editedField = edited;
        this.drafts = { ...this.drafts, [id]: this.project(draft, edited) };
        this.saveMsgs = { ...this.saveMsgs, [id]: '' };
    }

    remainingWeeks() {
        const days = this.page && this.page.remainingWorkingDays != null ? this.page.remainingWorkingDays : 0;
        return days / 5;
    }

    handleReason(e) {
        const id = e.target.dataset.owner;
        this.reasons = { ...this.reasons, [id]: e.target.value };
    }

    resetPlanner(e) {
        const id = e.currentTarget.dataset.owner;
        const row = this.rowById(id);
        if (!row) return;
        const next = { ...this.drafts };
        delete next[id];
        this.drafts = next;
        this.saveMsgs = { ...this.saveMsgs, [id]: 'Reset to engine recommended.' };
    }

    savePlanner(e) {
        const id = e.currentTarget.dataset.owner;
        const row = this.rowById(id);
        if (!row) return;
        const planned = this.drafts[id] || row.planned || row.recommended;
        const reason = (this.reasons[id] || '').trim();
        if (!reason) {
            this.saveMsgs = { ...this.saveMsgs, [id]: 'A reason is required so the change stays auditable.' };
            return;
        }
        this.saving = { ...this.saving, [id]: true };
        this.saveMsgs = { ...this.saveMsgs, [id]: 'Saving…' };
        savePlays({
            ownerId: id,
            productType: this.productType,
            reason,
            planned
        })
            .then(() => {
                this.saveMsgs = { ...this.saveMsgs, [id]: 'Saved. Refresh keeps these as the starting plan.' };
            })
            .catch((err) => {
                this.saveMsgs = { ...this.saveMsgs, [id]: this.msg(err) };
            })
            .finally(() => {
                this.saving = { ...this.saving, [id]: false };
            });
    }

    rowById(id) {
        const rows = this.page && this.page.rows ? this.page.rows : [];
        return rows.find((r) => r.ownerId === id);
    }

    clone(d) {
        return d ? { ...d } : {};
    }

    project(incoming, editedField) {
        const d = { ...incoming };
        const field = editedField || 'rate';
        const oppPer = d.oppsPerConnect != null && d.oppsPerConnect > 0 ? Number(d.oppsPerConnect) : 1;
        const selfShare = this.clampShare(d.selfShare);
        d.selfShare = selfShare;

        if (field === 'dials') {
            d.connectsNeeded = this.mul(d.dialsNeeded, d.connectRate);
            d.selfSourced = this.mul(d.connectsNeeded, oppPer);
            d.oppsToCreate = this.safeDiv(d.selfSourced, selfShare);
            d.qoNeeded = this.mul(d.oppsToCreate, d.qualRate);
            d.winsNeeded = this.mul(d.qoNeeded, d.winRate);
        } else if (field === 'connects') {
            d.dialsNeeded = this.safeDiv(d.connectsNeeded, d.connectRate);
            d.selfSourced = this.mul(d.connectsNeeded, oppPer);
            d.oppsToCreate = this.safeDiv(d.selfSourced, selfShare);
            d.qoNeeded = this.mul(d.oppsToCreate, d.qualRate);
            d.winsNeeded = this.mul(d.qoNeeded, d.winRate);
        } else if (field === 'selfSourced') {
            d.oppsToCreate = this.safeDiv(d.selfSourced, selfShare);
            d.qoNeeded = this.mul(d.oppsToCreate, d.qualRate);
            d.winsNeeded = this.mul(d.qoNeeded, d.winRate);
            d.connectsNeeded = this.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = this.safeDiv(d.connectsNeeded, d.connectRate);
        } else if (field === 'oppsToCreate') {
            d.qoNeeded = this.mul(d.oppsToCreate, d.qualRate);
            d.winsNeeded = this.mul(d.qoNeeded, d.winRate);
            d.selfSourced = this.mul(d.oppsToCreate, selfShare);
            d.connectsNeeded = this.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = this.safeDiv(d.connectsNeeded, d.connectRate);
        } else if (field === 'qoNeeded') {
            d.winsNeeded = this.mul(d.qoNeeded, d.winRate);
            d.oppsToCreate = this.safeDiv(d.qoNeeded, d.qualRate);
            d.selfSourced = this.mul(d.oppsToCreate, selfShare);
            d.connectsNeeded = this.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = this.safeDiv(d.connectsNeeded, d.connectRate);
        } else if (field === 'winsNeeded') {
            d.qoNeeded = this.safeDiv(d.winsNeeded, d.winRate);
            d.oppsToCreate = this.safeDiv(d.qoNeeded, d.qualRate);
            d.selfSourced = this.mul(d.oppsToCreate, selfShare);
            d.connectsNeeded = this.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = this.safeDiv(d.connectsNeeded, d.connectRate);
        } else {
            d.winsNeeded = this.safeDiv(d.quota, d.asp);
            d.qoNeeded = this.safeDiv(d.winsNeeded, d.winRate);
            d.oppsToCreate = this.safeDiv(d.qoNeeded, d.qualRate);
            d.selfSourced = this.mul(d.oppsToCreate, selfShare);
            d.connectsNeeded = this.safeDiv(d.selfSourced, oppPer);
            d.dialsNeeded = this.safeDiv(d.connectsNeeded, d.connectRate);
        }

        d.channelOpps = d.oppsToCreate == null || d.selfSourced == null ? null : d.oppsToCreate - d.selfSourced;
        d.projectedArr = this.mul(d.winsNeeded, d.asp);
        d.quotaCoverage = this.safeDiv(d.projectedArr, d.quota);
        const daysLeft = this.page && this.page.remainingWorkingDays != null ? this.page.remainingWorkingDays : 0;
        d.remainingWorkingDays = daysLeft;
        d.remainingWeeks = daysLeft / 5;
        d.dialsPerDay = daysLeft === 0 ? d.dialsNeeded : this.safeDiv(d.dialsNeeded, daysLeft);
        d.connectsPerDay = daysLeft === 0 ? d.connectsNeeded : this.safeDiv(d.connectsNeeded, daysLeft);
        d.dialsPerWeek = this.mul(d.dialsPerDay, 5);
        d.connectsPerWeek = this.mul(d.connectsPerDay, 5);
        const elapsed = this.page && this.page.elapsedWorkingDays != null ? this.page.elapsedWorkingDays : 0;
        const actualDials = d.actualDials == null ? 0 : d.actualDials;
        d.normalDialsPerDay = elapsed === 0 ? null : this.safeDiv(actualDials, elapsed);
        d.normalDialsPerWeek = this.mul(d.normalDialsPerDay, 5);
        d.weeklyPaceGap = d.dialsPerWeek == null || d.normalDialsPerWeek == null
            ? null
            : d.dialsPerWeek - d.normalDialsPerWeek;
        return d;
    }

    clampShare(share) {
        if (share == null || isNaN(share)) return share;
        if (share > 1) return 1;
        if (share < 0) return 0;
        return share;
    }
    mul(a, b) {
        if (a == null || b == null || isNaN(a) || isNaN(b)) return null;
        return Number(a) * Number(b);
    }
    safeDiv(num, den) {
        if (num == null || den == null || isNaN(num) || isNaN(den) || Number(den) === 0) return null;
        return Number(num) / Number(den);
    }

    msg(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.'; }
    pct(n) {
        if (n == null || isNaN(n)) return '—';
        return (Number(n) * 100).toFixed(1) + '%';
    }
    pctIn(n) {
        if (n == null || isNaN(n)) return '';
        return (Number(n) * 100).toFixed(1);
    }
    money(n) {
        if (n == null || isNaN(n)) return '—';
        return '$' + Math.round(Number(n)).toLocaleString('en-US');
    }
    num(n, d) {
        if (n == null || isNaN(n)) return '—';
        return Number(n).toFixed(d);
    }
    numIn(n, d) {
        if (n == null || isNaN(n)) return '';
        return Number(n).toFixed(d);
    }
    signed(n, fmt) {
        if (n == null || isNaN(n)) return '—';
        const v = Number(n);
        const body = fmt === 'money' ? this.money(Math.abs(v)) : this.num(Math.abs(v), 1);
        if (v > 0) return '+' + body;
        if (v < 0) return '−' + body;
        return fmt === 'money' ? this.money(0) : this.num(0, 1);
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
    get remainingDaysLabel() {
        if (!this.page || this.page.remainingWorkingDays == null) return '';
        return this.page.remainingWorkingDays + ' working days left in the close period ('
            + this.page.elapsedWorkingDays + ' elapsed of ' + this.page.workingDaysInPeriod + ').';
    }

    get cards() {
        if (!this.hasRows) return [];
        return this.page.rows.map((r) => {
            const rec = r.recommended || {};
            const plan = this.drafts[r.ownerId] || r.planned || rec;
            const qoGap = plan.qoNeeded == null ? null : Number(plan.qoNeeded) - (r.haveQo || 0);
            const arrDelta = plan.projectedArr == null || rec.projectedArr == null
                ? null
                : Number(plan.projectedArr) - Number(rec.projectedArr);
            const dialDelta = plan.dialsNeeded == null || rec.dialsNeeded == null
                ? null
                : Number(plan.dialsNeeded) - Number(rec.dialsNeeded);
            const qoDelta = plan.qoNeeded == null || rec.qoNeeded == null
                ? null
                : Number(plan.qoNeeded) - Number(rec.qoNeeded);
            return {
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
                createPlan: this.decoratePlan(r.createPlan, 'live'),
                plannerOpen: this.plannerOwnerId === r.ownerId,
                rec: {
                    dials: this.num(rec.dialsNeeded, 0),
                    connects: this.num(rec.connectsNeeded, 1),
                    connectRate: this.pct(rec.connectRate),
                    oppsPerConnect: this.num(rec.oppsPerConnect, 2),
                    selfShare: this.pct(rec.selfShare),
                    oppsToCreate: this.num(rec.oppsToCreate, 1),
                    qoNeeded: this.num(rec.qoNeeded, 1),
                    qualRate: this.pct(rec.qualRate),
                    winRate: this.pct(rec.winRate)
                },
                plan: {
                    dials: this.numIn(plan.dialsNeeded, 0),
                    dialsWeekIn: this.numIn(plan.dialsPerWeek, 1),
                    connects: this.numIn(plan.connectsNeeded, 1),
                    connectRate: this.pctIn(plan.connectRate),
                    oppsPerConnect: this.numIn(plan.oppsPerConnect, 2),
                    selfShare: this.pctIn(plan.selfShare),
                    oppsToCreate: this.numIn(plan.oppsToCreate, 1),
                    qoNeeded: this.numIn(plan.qoNeeded, 1),
                    qualRate: this.pctIn(plan.qualRate),
                    winRate: this.pctIn(plan.winRate),
                    selfSourced: this.num(plan.selfSourced, 1),
                    channelOpps: this.num(plan.channelOpps, 1),
                    winsNeeded: this.num(plan.winsNeeded, 1),
                    projectedArr: this.money(plan.projectedArr),
                    coverage: this.pct(plan.quotaCoverage),
                    remainingDays: plan.remainingWorkingDays == null
                        ? (this.page.remainingWorkingDays || 0)
                        : plan.remainingWorkingDays,
                    remainingWeeks: this.num(plan.remainingWeeks != null
                        ? plan.remainingWeeks
                        : (this.page.remainingWorkingDays || 0) / 5, 1),
                    dialsDay: this.num(plan.dialsPerDay, 1),
                    dialsWeek: this.num(plan.dialsPerWeek, 1),
                    normalDialsWeek: this.num(plan.normalDialsPerWeek, 1),
                    normalConnectRate: this.pct(plan.normalConnectRate || r.connectRate),
                    paceGap: this.signed(plan.weeklyPaceGap, 'num') + ' / week',
                    qoGapClass: qoGap != null && qoGap > 0 ? 'gap short' : 'gap ok',
                    qoGapLabel: qoGap == null
                        ? '—'
                        : (qoGap > 0
                            ? this.num(qoGap, 1) + ' QO still to find this period'
                            : 'Book covers the qualified need'),
                    arrDelta: this.signed(arrDelta, 'money'),
                    dialDelta: this.signed(dialDelta, 'num'),
                    qoDelta: this.signed(qoDelta, 'num'),
                    deltaClass: arrDelta != null && arrDelta < 0 ? 'play-big short' : 'play-big',
                    reason: this.reasons[r.ownerId] || '',
                    saveMsg: this.saveMsgs[r.ownerId] || '',
                    saving: this.saving[r.ownerId] === true
                }
            };
        });
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
